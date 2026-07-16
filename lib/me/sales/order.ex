defmodule Me.Sales.Order do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Sales,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshJsonApi.Resource]

  json_api do
    type "order"
    includes [:customer, payments: [:recorded_by], line_items: [:product_variant]]

    default_fields [
      :order_number,
      :order_kind,
      :payment_terms,
      :status,
      :fulfillment_status,
      :sales_channel,
      :external_reference,
      :expected_at,
      :payment_due_at,
      :subtotal_cents,
      :discount_cents,
      :total_cents,
      :paid_cents,
      :balance_cents,
      :payment_state,
      :placed_at,
      :fulfilled_at,
      :cancelled_at,
      :cancel_reason,
      :returned_at,
      :return_reason,
      :inserted_at,
      :updated_at
    ]
  end

  postgres do
    table "orders"
    repo Me.Repo

    check_constraints do
      check_constraint :subtotal_cents, "order_subtotal_non_negative",
        check: "subtotal_cents >= 0",
        message: "must be greater than or equal to zero"

      check_constraint :discount_cents, "order_discount_not_greater_than_subtotal",
        check: "discount_cents >= 0 AND discount_cents <= subtotal_cents",
        message: "cannot exceed the subtotal"
    end
  end

  field_policies do
    field_policy :discount_cents do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :submit, from: :draft, to: :pending
      transition :confirm_preorder, from: :draft, to: :pending
      transition :fulfill, from: :pending, to: :fulfilled
      transition :cancel, from: [:draft, :pending], to: :cancelled
      transition :return, from: :fulfilled, to: :returned
    end
  end

  actions do
    defaults [:read]

    read :api_index do
      pagination offset?: true, keyset?: true, default_limit: 25, max_page_size: 100
    end

    create :create do
      primary? true

      accept [
        :order_kind,
        :payment_terms,
        :sales_channel,
        :external_reference,
        :expected_at,
        :payment_due_at
      ]

      change Me.Sales.Changes.EnsureCreditAuthorized
      argument :customer_id, :uuid
      change Me.Sales.Changes.SetOrderActors
      change Me.Sales.Changes.EnsureCustomerCanOrder
    end

    update :set_discount do
      accept [:discount_cents]
    end

    update :submit do
      accept []
      require_atomic? false

      argument :initial_payment_amount_cents, :integer do
        constraints min: 0
      end

      argument :initial_payment_method, :atom do
        constraints one_of: [:cash, :bank_transfer, :card_manual, :other]
      end

      argument :initial_payment_note, :string
      argument :initial_payment_external_reference, :string

      change {Me.Sales.Changes.EnsureOrderKind, kind: :sale}
      change Me.Sales.Changes.CommitOrderStock
      change transition_state(:pending)
      change set_attribute(:placed_at, &DateTime.utc_now/0)
      change Me.Sales.Changes.RecordInitialPayment
    end

    update :confirm_preorder do
      accept []
      require_atomic? false

      argument :initial_payment_amount_cents, :integer do
        constraints min: 0
      end

      argument :initial_payment_method, :atom do
        constraints one_of: [:cash, :bank_transfer, :card_manual, :other]
      end

      argument :initial_payment_note, :string
      argument :initial_payment_external_reference, :string

      change {Me.Sales.Changes.EnsureOrderKind, kind: :preorder}
      change Me.Sales.Changes.EnsureOrderHasLineItems
      change transition_state(:pending)
      change set_attribute(:fulfillment_status, :awaiting_stock)
      change set_attribute(:placed_at, &DateTime.utc_now/0)
      change Me.Sales.Changes.RecordInitialPayment
    end

    update :allocate_preorder do
      accept []
      require_atomic? false
      change {Me.Sales.Changes.EnsureOrderKind, kind: :preorder}
      change Me.Sales.Changes.ReservePreorderStock
      change set_attribute(:fulfillment_status, :ready)
    end

    update :fulfill do
      accept []
      require_atomic? false
      change Me.Sales.Changes.EnsurePaymentReadyForFulfillment
      change Me.Sales.Changes.CommitPreorderFulfillment
      change transition_state(:fulfilled)
      change Me.Sales.Changes.MarkFulfillmentCompleted
      change set_attribute(:fulfilled_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept [:cancel_reason]
      require_atomic? false

      change Me.Sales.Changes.RestoreOrderStock do
        where attribute_equals(:order_kind, :sale)
        where attribute_equals(:status, :pending)
      end

      change Me.Sales.Changes.CancelPreorderFulfillment do
        where attribute_equals(:order_kind, :preorder)
      end

      change transition_state(:cancelled)
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)
    end

    update :return do
      accept [:return_reason]
      require_atomic? false
      change Me.Sales.Changes.RestockReturnedOrder
      change transition_state(:returned)
      change set_attribute(:returned_at, &DateTime.utc_now/0)
    end

    update :set_subtotal do
      public? false
      accept [:subtotal_cents]
    end
  end

  policies do
    bypass actor_attribute_equals(:active, true) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:customer)
    end

    policy action(:create) do
      authorize_if relating_to_actor(:customer)
    end

    policy action([:submit, :cancel]) do
      authorize_if relates_to_actor_via(:customer)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :order_number, :integer do
      allow_nil? false
      generated? true
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:draft, :pending, :fulfilled, :cancelled, :returned]
      default :draft
      public? true
    end

    attribute :order_kind, :atom do
      allow_nil? false
      constraints one_of: [:sale, :preorder]
      default :sale
      public? true
    end

    attribute :payment_terms, :atom do
      allow_nil? false
      constraints one_of: [:immediate, :credit]
      default :immediate
      public? true
    end

    attribute :fulfillment_status, :atom do
      allow_nil? false
      constraints one_of: [:not_applicable, :awaiting_stock, :ready, :fulfilled, :cancelled]
      default :not_applicable
      public? true
    end

    attribute :sales_channel, :atom do
      constraints one_of: [:pos, :group_chat, :other]
      default :pos
      public? true
    end

    attribute :external_reference, :string do
      public? true
    end

    attribute :expected_at, :utc_datetime_usec do
      public? true
    end

    attribute :payment_due_at, :utc_datetime_usec do
      public? true
    end

    attribute :subtotal_cents, :integer do
      allow_nil? false
      constraints min: 0
      default 0
      public? true
    end

    attribute :discount_cents, :integer do
      allow_nil? false
      constraints min: 0
      default 0
      public? true
    end

    attribute :placed_at, :utc_datetime_usec do
      public? true
    end

    attribute :fulfilled_at, :utc_datetime_usec do
      public? true
    end

    attribute :cancelled_at, :utc_datetime_usec do
      public? true
    end

    attribute :cancel_reason, :string do
      public? true
    end

    attribute :returned_at, :utc_datetime_usec do
      public? true
    end

    attribute :return_reason, :string do
      public? true
    end

    timestamps public?: true
  end

  relationships do
    belongs_to :customer, Me.Accounts.Customer do
      allow_nil? false
      public? true
    end

    belongs_to :placed_by, Me.Accounts.User do
      source_attribute :placed_by_user_id
      public? true
    end

    has_many :line_items, Me.Sales.OrderLineItem do
      public? true
    end

    has_many :payments, Me.Sales.Payment do
      public? true
    end
  end

  calculations do
    calculate :total_cents, :integer, expr(subtotal_cents - discount_cents) do
      public? true
    end

    calculate :payment_state,
              :atom,
              expr(
                if total_cents == 0 do
                  :paid
                else
                  if paid_cents == 0 do
                    :unpaid
                  else
                    if paid_cents < total_cents do
                      :partially_paid
                    else
                      :paid
                    end
                  end
                end
              ) do
      constraints one_of: [:unpaid, :partially_paid, :paid]
      public? true
    end

    calculate :balance_cents,
              :integer,
              expr(
                if paid_cents < total_cents do
                  total_cents - paid_cents
                else
                  0
                end
              ) do
      public? true
    end
  end

  aggregates do
    sum :paid_cents, :payments, :amount_cents do
      filter expr(is_nil(voided_at))
      default 0
    end
  end

  identities do
    identity :unique_order_number, [:order_number]
    identity :unique_external_reference, [:external_reference]
  end
end

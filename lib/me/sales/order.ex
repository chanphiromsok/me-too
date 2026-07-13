defmodule Me.Sales.Order do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Sales,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshJsonApi.Resource]

  json_api do
    type "order"
  end

  postgres do
    table "orders"
    repo Me.Repo
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
      transition :fulfill, from: :pending, to: :fulfilled
      transition :cancel, from: [:draft, :pending], to: :cancelled
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:customer_id]
      change Me.Sales.Changes.SetOrderActors
    end

    update :set_discount do
      accept [:discount_cents]
    end

    update :submit do
      accept []
      require_atomic? false
      change Me.Sales.Changes.CommitOrderStock
      change transition_state(:pending)
      change set_attribute(:placed_at, &DateTime.utc_now/0)
    end

    update :fulfill do
      accept []
      require_atomic? false
      change transition_state(:fulfilled)
      change set_attribute(:fulfilled_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept [:cancel_reason]
      require_atomic? false
      change Me.Sales.Changes.RestoreOrderStock
      change transition_state(:cancelled)
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)
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
      constraints one_of: [:draft, :pending, :fulfilled, :cancelled]
      default :draft
      public? true
    end

    attribute :subtotal_cents, :integer do
      allow_nil? false
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

    timestamps()
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
                if paid_cents == 0 do
                  :unpaid
                else
                  if paid_cents < total_cents do
                    :partially_paid
                  else
                    :paid
                  end
                end
              ) do
      constraints one_of: [:unpaid, :partially_paid, :paid]
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
  end
end

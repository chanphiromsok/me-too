defmodule Me.Sales.Receivable do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Sales,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "receivable"

    default_fields [
      :order_number,
      :order_kind,
      :status,
      :customer_id,
      :customer_name,
      :customer_phone,
      :total_cents,
      :paid_cents,
      :balance_cents,
      :payment_due_at,
      :overdue,
      :placed_at,
      :customer_balance_cents,
      :customer_unpaid_order_count,
      :portfolio_balance_cents
    ]
  end

  postgres do
    table "receivables"
    repo Me.Repo
    migrate? false
  end

  actions do
    defaults [:read]

    read :api_index do
      pagination offset?: true, keyset?: true, default_limit: 25, max_page_size: 100
      prepare build(sort: [:payment_due_at, :placed_at, :order_number])
    end
  end

  policies do
    policy action_type(:read) do
      access_type :strict

      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end
  end

  attributes do
    attribute :id, :uuid do
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :order_number, :integer do
      allow_nil? false
      public? true
    end

    attribute :order_kind, :atom do
      allow_nil? false
      constraints one_of: [:sale, :preorder]
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :fulfilled]
      public? true
    end

    attribute :customer_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :customer_name, :string do
      allow_nil? false
      public? true
    end

    attribute :customer_phone, :string do
      public? true
    end

    attribute :total_cents, :integer do
      allow_nil? false
      public? true
    end

    attribute :paid_cents, :integer do
      allow_nil? false
      public? true
    end

    attribute :balance_cents, :integer do
      allow_nil? false
      public? true
    end

    attribute :payment_due_at, :utc_datetime_usec do
      public? true
    end

    attribute :overdue, :boolean do
      allow_nil? false
      public? true
    end

    attribute :placed_at, :utc_datetime_usec do
      public? true
    end

    attribute :customer_balance_cents, :integer do
      allow_nil? false
      public? true
    end

    attribute :customer_unpaid_order_count, :integer do
      allow_nil? false
      public? true
    end

    attribute :portfolio_balance_cents, :integer do
      allow_nil? false
      public? true
    end
  end
end

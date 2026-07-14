defmodule Me.Sales.Payment do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Sales,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "payment"
  end

  postgres do
    table "payments"
    repo Me.Repo

    check_constraints do
      check_constraint :amount_cents, "payment_amount_positive",
        check: "amount_cents > 0",
        message: "must be greater than zero"
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:amount_cents, :method, :note]
      argument :order_id, :uuid, allow_nil?: false

      change set_attribute(:order_id, arg(:order_id))
      change relate_actor(:recorded_by)
    end

    update :void do
      accept []
      change set_attribute(:voided_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass actor_attribute_equals(:active, true) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:order, :customer])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :amount_cents, :integer do
      allow_nil? false
      constraints min: 1
      public? true
    end

    attribute :method, :atom do
      allow_nil? false
      constraints one_of: [:cash, :bank_transfer, :card_manual, :other]
      public? true
    end

    attribute :note, :string do
      public? true
    end

    create_timestamp :recorded_at

    attribute :voided_at, :utc_datetime_usec do
      public? true
    end
  end

  relationships do
    belongs_to :order, Me.Sales.Order do
      allow_nil? false
      public? true
    end

    belongs_to :recorded_by, Me.Accounts.User do
      allow_nil? false
      source_attribute :recorded_by_user_id
      public? true
    end
  end
end

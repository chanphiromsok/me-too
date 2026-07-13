defmodule Me.Catalog.Product do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "product"
  end

  postgres do
    table "products"
    repo Me.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :description, :category]
    end

    update :update do
      primary? true
      accept [:name, :description, :category]
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end
  end

  policies do
    bypass action_type(:read) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end

    policy action_type(:read) do
      authorize_if expr(status == :active)
    end

    policy action([:create, :update]) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end

    policy action(:archive) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :category, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:active, :archived]
      default :active
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :variants, Me.Catalog.ProductVariant do
      public? true
    end
  end
end

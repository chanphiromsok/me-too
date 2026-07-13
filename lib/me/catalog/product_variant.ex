defmodule Me.Catalog.ProductVariant do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "product_variant"
  end

  postgres do
    table "product_variants"
    repo Me.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :product_id,
        :sku,
        :size,
        :color,
        :price_cents,
        :quantity_on_hand,
        :barcode,
        :active
      ]
    end

    update :update do
      primary? true
      accept [:sku, :size, :color, :price_cents, :barcode, :active]
    end
  end

  policies do
    bypass action_type(:read) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end

    policy action_type(:read) do
      authorize_if expr(active == true and product.status == :active)
    end

    policy action([:create, :update]) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :sku, :string do
      allow_nil? false
      public? true
    end

    attribute :size, :string do
      allow_nil? false
      public? true
    end

    attribute :color, :string do
      allow_nil? false
      public? true
    end

    attribute :price_cents, :integer do
      allow_nil? false
      public? true
    end

    attribute :quantity_on_hand, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :barcode, :string do
      public? true
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :product, Me.Catalog.Product do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_sku, [:sku]
    identity :unique_product_size_color, [:product_id, :size, :color]
  end
end

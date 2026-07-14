defmodule Me.Sales.OrderLineItem do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Sales,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "order_line_item"
  end

  postgres do
    table "order_line_items"
    repo Me.Repo

    check_constraints do
      check_constraint :unit_price_cents, "order_line_item_unit_price_non_negative",
        check: "unit_price_cents >= 0",
        message: "must be greater than or equal to zero"
    end
  end

  actions do
    defaults [:read]

    create :add_line_item do
      accept [:product_variant_id, :quantity]
      argument :order_id, :uuid, allow_nil?: false

      upsert? true
      upsert_identity :unique_order_variant
      upsert_fields [:quantity]

      change set_attribute(:order_id, arg(:order_id))
      change Me.Sales.Changes.EnsureDraftOrder
      change Me.Sales.Changes.SnapshotVariantPrice
      change Me.Sales.Changes.RecalculateOrderSubtotal
    end

    update :edit do
      accept [:quantity]
      require_atomic? false
      argument :order_id, :uuid, allow_nil?: false
      change Me.Sales.Changes.EnsureDraftOrder
      change Me.Sales.Changes.RecalculateOrderSubtotal
    end

    destroy :remove do
      require_atomic? false
      argument :order_id, :uuid, allow_nil?: false
      change Me.Sales.Changes.EnsureDraftOrder
      change Me.Sales.Changes.RecalculateOrderSubtotal
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

    policy action_type([:create, :update, :destroy]) do
      forbid_unless expr(order.status == :draft)
      authorize_if relates_to_actor_via([:order, :customer])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :quantity, :integer do
      allow_nil? false
      constraints min: 1
      public? true
    end

    attribute :unit_price_cents, :integer do
      allow_nil? false
      constraints min: 0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :order, Me.Sales.Order do
      allow_nil? false
      public? true
    end

    belongs_to :product_variant, Me.Catalog.ProductVariant do
      allow_nil? false
      public? true
    end

    has_one :inventory_allocation, Me.Inventory.InventoryAllocation
  end

  calculations do
    calculate :line_total_cents, :integer, expr(quantity * unit_price_cents) do
      public? true
    end
  end

  identities do
    identity :unique_order_variant, [:order_id, :product_variant_id]
  end
end

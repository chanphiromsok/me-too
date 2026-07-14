defmodule Me.Inventory.InventoryAllocation do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Inventory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "inventory_allocations"
    repo Me.Repo

    check_constraints do
      check_constraint :quantity, "inventory_allocation_quantity_positive",
        check: "quantity > 0",
        message: "must be greater than zero"

      check_constraint :status, "inventory_allocation_status_valid",
        check: "status IN ('reserved', 'consumed', 'released')",
        message: "must be reserved, consumed, or released"
    end
  end

  actions do
    defaults [:read]

    create :reserve do
      public? false

      accept [
        :order_line_item_id,
        :product_variant_id,
        :quantity,
        :allocated_by_user_id
      ]
    end

    update :consume do
      public? false
      accept []
      change set_attribute(:status, :consumed)
      change set_attribute(:consumed_at, &DateTime.utc_now/0)
    end

    update :release do
      public? false
      accept []
      change set_attribute(:status, :released)
      change set_attribute(:released_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :quantity, :integer do
      allow_nil? false
      constraints min: 1
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:reserved, :consumed, :released]
      default :reserved
      public? true
    end

    create_timestamp :allocated_at

    attribute :consumed_at, :utc_datetime_usec do
      public? true
    end

    attribute :released_at, :utc_datetime_usec do
      public? true
    end
  end

  relationships do
    belongs_to :order_line_item, Me.Sales.OrderLineItem do
      allow_nil? false
      public? true
    end

    belongs_to :product_variant, Me.Catalog.ProductVariant do
      allow_nil? false
      public? true
    end

    belongs_to :allocated_by, Me.Accounts.User do
      source_attribute :allocated_by_user_id
      public? true
    end
  end

  identities do
    identity :unique_order_line_item, [:order_line_item_id]
  end
end

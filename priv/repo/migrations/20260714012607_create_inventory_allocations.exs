defmodule Me.Repo.Migrations.CreateInventoryAllocations do
  use Ecto.Migration

  def change do
    create table(:inventory_allocations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :quantity, :bigint, null: false
      add :status, :text, null: false, default: "reserved"

      add :allocated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :consumed_at, :utc_datetime_usec
      add :released_at, :utc_datetime_usec

      add :order_line_item_id,
          references(:order_line_items,
            column: :id,
            name: "inventory_allocations_order_line_item_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :product_variant_id,
          references(:product_variants,
            column: :id,
            name: "inventory_allocations_product_variant_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :allocated_by_user_id,
          references(:users,
            column: :id,
            name: "inventory_allocations_allocated_by_user_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    create unique_index(:inventory_allocations, [:order_line_item_id],
             name: "inventory_allocations_unique_order_line_item_index"
           )

    create index(:inventory_allocations, [:product_variant_id, :status])

    create constraint(:inventory_allocations, :inventory_allocation_quantity_positive,
             check: "quantity > 0"
           )

    create constraint(:inventory_allocations, :inventory_allocation_status_valid,
             check: "status IN ('reserved', 'consumed', 'released')"
           )

    execute(
      """
      INSERT INTO inventory_allocations (
        id,
        quantity,
        status,
        allocated_at,
        order_line_item_id,
        product_variant_id
      )
      SELECT
        gen_random_uuid(),
        line.quantity,
        'reserved',
        orders.updated_at,
        line.id,
        line.product_variant_id
      FROM order_line_items AS line
      INNER JOIN orders ON orders.id = line.order_id
      WHERE orders.order_kind = 'preorder'
        AND orders.status = 'pending'
        AND orders.fulfillment_status = 'ready'
      """,
      "DELETE FROM inventory_allocations"
    )

    create constraint(:product_variants, :reserved_quantity_cannot_exceed_stock,
             check: "reserved_quantity <= quantity_on_hand"
           )
  end
end

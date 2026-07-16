defmodule Me.Repo.Migrations.RequireStockMovementReferences do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE stock_movements
    SET reference_type = COALESCE(reference_type, 'legacy_inventory_operation'),
        reference_id = COALESCE(reference_id, id)
    WHERE reference_type IS NULL OR reference_id IS NULL
    """)

    alter table(:stock_movements) do
      modify :reference_type, :text,
        null: false,
        default: "manual_inventory_operation"

      modify :reference_id, :uuid,
        null: false,
        default: fragment("gen_random_uuid()")
    end
  end

  def down do
    alter table(:stock_movements) do
      modify :reference_type, :text, null: true, default: nil
      modify :reference_id, :uuid, null: true, default: nil
    end
  end
end

defmodule Me.Repo.Migrations.AddMutationIdempotencyReferences do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :external_reference, :text
    end

    create unique_index(:orders, [:external_reference],
             name: "orders_unique_external_reference_index"
           )

    create unique_index(:payments, [:external_reference],
             name: "payments_unique_external_reference_index"
           )

    create unique_index(
             :stock_movements,
             [:product_variant_id, :reason, :reference_type, :reference_id],
             name: "stock_movements_unique_reference_index"
           )
  end
end

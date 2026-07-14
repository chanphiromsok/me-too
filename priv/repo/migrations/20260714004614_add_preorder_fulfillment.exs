defmodule Me.Repo.Migrations.AddPreorderFulfillment do
  use Ecto.Migration

  def change do
    alter table(:product_variants) do
      add :reserved_quantity, :bigint, null: false, default: 0
    end

    create constraint(:product_variants, :reserved_quantity_must_be_non_negative,
             check: "reserved_quantity >= 0"
           )

    alter table(:orders) do
      add :order_kind, :text, null: false, default: "sale"
      add :fulfillment_status, :text, null: false, default: "not_applicable"
      add :sales_channel, :text, null: false, default: "pos"
      add :external_reference, :text
      add :expected_at, :utc_datetime_usec
    end
  end
end

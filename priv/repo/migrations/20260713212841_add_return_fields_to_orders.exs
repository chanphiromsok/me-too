defmodule Me.Repo.Migrations.AddReturnFieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :returned_at, :utc_datetime_usec
      add :return_reason, :text
    end
  end
end

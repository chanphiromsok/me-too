defmodule Me.Repo.Migrations.AddPaidAtToPayments do
  use Ecto.Migration

  def up do
    alter table(:payments) do
      add :paid_at, :utc_datetime_usec
    end

    execute "UPDATE payments SET paid_at = recorded_at"

    alter table(:payments) do
      modify :paid_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end
  end

  def down do
    alter table(:payments) do
      remove :paid_at
    end
  end
end

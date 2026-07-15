defmodule Me.Repo.Migrations.AddStatusToCustomers do
  use Ecto.Migration

  def up do
    alter table(:customers) do
      add :status, :text, null: false, default: "needs_approval"
    end

    execute("UPDATE customers SET status = 'approved' WHERE confirmed_at IS NOT NULL")
  end

  def down do
    alter table(:customers) do
      remove :status
    end
  end
end

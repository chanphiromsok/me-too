defmodule Me.Sales.Changes.SetOrderActors do
  use Ash.Resource.Change

  alias Me.Accounts.{Customer, User}

  @impl Ash.Resource.Change
  def change(changeset, _opts, %{actor: %Customer{id: customer_id}}) do
    Ash.Changeset.force_change_attribute(changeset, :customer_id, customer_id)
  end

  def change(changeset, _opts, %{actor: %User{id: user_id}}) do
    Ash.Changeset.force_change_attribute(changeset, :placed_by_user_id, user_id)
  end

  def change(changeset, _opts, _context), do: changeset
end

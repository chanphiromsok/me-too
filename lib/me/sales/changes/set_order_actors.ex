defmodule Me.Sales.Changes.SetOrderActors do
  use Ash.Resource.Change

  alias Me.Accounts.{Customer, User}

  @impl Ash.Resource.Change
  def change(changeset, _opts, %{actor: %Customer{id: customer_id}}) do
    Ash.Changeset.force_change_attribute(changeset, :customer_id, customer_id)
  end

  def change(changeset, _opts, %{actor: %User{id: user_id}}) do
    changeset
    |> Ash.Changeset.force_change_attribute(:placed_by_user_id, user_id)
    |> set_staff_customer()
  end

  def change(changeset, _opts, _context), do: changeset

  defp set_staff_customer(changeset) do
    case Ash.Changeset.get_argument(changeset, :customer_id) do
      nil -> changeset
      customer_id -> Ash.Changeset.force_change_attribute(changeset, :customer_id, customer_id)
    end
  end
end

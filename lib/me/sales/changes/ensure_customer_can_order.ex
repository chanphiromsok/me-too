defmodule Me.Sales.Changes.EnsureCustomerCanOrder do
  use Ash.Resource.Change

  alias Me.Accounts.Customer

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      ensure_customer_can_order(changeset, Ash.Changeset.get_attribute(changeset, :customer_id))
    end)
  end

  defp ensure_customer_can_order(changeset, nil), do: changeset

  defp ensure_customer_can_order(changeset, customer_id) do
    case Ash.get(Customer, customer_id, authorize?: false) do
      {:ok, %Customer{status: :suspended}} ->
        Ash.Changeset.add_error(changeset,
          field: :customer_id,
          message: "suspended customers cannot create new orders"
        )

      _result ->
        changeset
    end
  end
end

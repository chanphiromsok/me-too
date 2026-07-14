defmodule Me.Sales.Changes.EnsurePayableOrder do
  use Ash.Resource.Change

  alias Me.Sales.Order

  require Ash.Query

  @payable_statuses [:pending, :fulfilled]

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &validate_order/1)
  end

  defp validate_order(changeset) do
    order_id = Ash.Changeset.get_argument(changeset, :order_id)

    Order
    |> Ash.Query.filter(id == ^order_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Order{status: status}} when status in @payable_statuses ->
        changeset

      {:ok, %Order{}} ->
        Ash.Changeset.add_error(changeset,
          field: :order_id,
          message: "order is not open for payment"
        )

      {:ok, nil} ->
        Ash.Changeset.add_error(changeset, field: :order_id, message: "does not exist")

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end

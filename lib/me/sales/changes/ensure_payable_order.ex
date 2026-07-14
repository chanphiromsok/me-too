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
    amount_cents = Ash.Changeset.get_attribute(changeset, :amount_cents)

    Order
    |> Ash.Query.filter(id == ^order_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Order{status: status} = order} when status in @payable_statuses ->
        validate_balance(changeset, order, amount_cents)

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

  defp validate_balance(changeset, order, amount_cents) do
    order = Ash.load!(order, [:total_cents, :paid_cents, :balance_cents], authorize?: false)

    cond do
      order.balance_cents == 0 ->
        Ash.Changeset.add_error(changeset,
          field: :amount_cents,
          message: "order has no remaining balance"
        )

      amount_cents > order.balance_cents ->
        Ash.Changeset.add_error(changeset,
          field: :amount_cents,
          message: "cannot exceed the remaining balance of #{order.balance_cents} cents"
        )

      true ->
        changeset
    end
  end
end

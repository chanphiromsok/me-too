defmodule Me.Sales.Changes.RecalculateOrderSubtotal do
  use Ash.Resource.Change

  alias Me.Sales.{Order, OrderLineItem}

  require Ash.Query

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, result ->
      order_id =
        Ash.Changeset.get_argument(changeset, :order_id) ||
          Ash.Changeset.get_attribute(changeset, :order_id) ||
          result.order_id

      subtotal =
        OrderLineItem
        |> Ash.Query.filter(order_id == ^order_id)
        |> Ash.read!(authorize?: false)
        |> Enum.sum_by(&(&1.quantity * &1.unit_price_cents))

      with {:ok, order} <- Ash.get(Order, order_id, authorize?: false),
           {:ok, _order} <-
             Ash.update(
               order,
               %{subtotal_cents: subtotal},
               action: :set_subtotal,
               authorize?: false
             ) do
        {:ok, result}
      end
    end)
  end
end

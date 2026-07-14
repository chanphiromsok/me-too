defmodule Me.Sales.Changes.EnsureOrderHasLineItems do
  use Ash.Resource.Change

  alias Me.Sales.OrderLineItem

  require Ash.Query

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      OrderLineItem
      |> Ash.Query.filter(order_id == ^changeset.data.id)
      |> Ash.exists?(authorize?: false)
      |> case do
        true ->
          changeset

        false ->
          Ash.Changeset.add_error(changeset, field: :id, message: "order has no line items")
      end
    end)
  end
end

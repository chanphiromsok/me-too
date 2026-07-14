defmodule Me.Sales.Changes.CommitOrderStock do
  use Ash.Resource.Change

  alias Me.Inventory.StockMovement
  alias Me.Accounts.User
  alias Me.Sales.OrderLineItem

  require Ash.Query

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, &commit(&1, context))
  end

  def commit(changeset, context) do
    lines =
      OrderLineItem
      |> Ash.Query.filter(order_id == ^changeset.data.id)
      |> Ash.read!(authorize?: false)

    if lines == [] do
      Ash.Changeset.add_error(changeset, field: :id, message: "order has no line items")
    else
      Enum.reduce_while(lines, changeset, fn line, changeset ->
        movement_actor = if match?(%User{}, context.actor), do: context.actor

        case Ash.create(
               StockMovement,
               %{
                 product_variant_id: line.product_variant_id,
                 quantity: line.quantity,
                 reference_type: "order",
                 reference_id: changeset.data.id
               },
               action: :sale,
               actor: movement_actor,
               authorize?: false
             ) do
          {:ok, _movement} ->
            {:cont, changeset}

          {:error, error} ->
            {:halt, Ash.Changeset.add_error(changeset, error)}
        end
      end)
    end
  end
end

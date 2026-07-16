defmodule Me.Sales.Changes.RestoreOrderStock do
  use Ash.Resource.Change

  alias Me.Inventory.StockMovement
  alias Me.Accounts.User
  alias Me.Sales.OrderLineItem

  require Ash.Query

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      OrderLineItem
      |> Ash.Query.filter(order_id == ^changeset.data.id)
      |> Ash.read!(authorize?: false)
      |> Enum.reduce_while(changeset, fn line, changeset ->
        movement_actor = if match?(%User{}, context.actor), do: context.actor

        case Ash.create(
               StockMovement,
               %{
                 product_variant_id: line.product_variant_id,
                 quantity: line.quantity,
                 reference_type: "order",
                 reference_id: changeset.data.id
               },
               action: :cancellation_restock,
               actor: movement_actor,
               authorize?: false
             ) do
          {:ok, _movement} -> {:cont, changeset}
          {:error, error} -> {:halt, Ash.Changeset.add_error(changeset, error)}
        end
      end)
    end)
  end
end

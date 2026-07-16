defmodule Me.Sales.Changes.RestockReturnedOrder do
  use Ash.Resource.Change

  alias Me.Accounts.User
  alias Me.Inventory.StockMovement
  alias Me.Sales.OrderLineItem

  require Ash.Query

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      OrderLineItem
      |> Ash.Query.filter(order_id == ^changeset.data.id)
      |> Ash.Query.sort(:product_variant_id)
      |> Ash.read!(authorize?: false)
      |> Enum.reduce_while(changeset, fn line, changeset ->
        movement_actor = if match?(%User{}, context.actor), do: context.actor

        case Ash.create(
               StockMovement,
               %{
                 product_variant_id: line.product_variant_id,
                 quantity: line.quantity,
                 reference_type: "order_return",
                 reference_id: changeset.data.id,
                 note: Ash.Changeset.get_attribute(changeset, :return_reason)
               },
               action: :return_restock,
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

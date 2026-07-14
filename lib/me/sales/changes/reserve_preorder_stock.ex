defmodule Me.Sales.Changes.ReservePreorderStock do
  use Ash.Resource.Change

  alias Me.Catalog.ProductVariant
  alias Me.Inventory.InventoryAllocation
  alias Me.Accounts.User
  alias Me.Sales.OrderLineItem

  require Ash.Query

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, &reserve_order_stock(&1, context))
  end

  defp reserve_order_stock(changeset, context) do
    cond do
      changeset.data.status != :pending ->
        Ash.Changeset.add_error(changeset,
          field: :status,
          message: "must be pending before stock can be allocated"
        )

      changeset.data.fulfillment_status != :awaiting_stock ->
        Ash.Changeset.add_error(changeset,
          field: :fulfillment_status,
          message: "must be awaiting stock before allocation"
        )

      true ->
        changeset.data.id
        |> order_lines()
        |> Enum.reduce_while(changeset, &reserve_line(&1, &2, context))
    end
  end

  defp reserve_line(line, changeset, context) do
    with {:ok, variant} <- lock_variant(line.product_variant_id),
         :ok <- ensure_available(variant, line.quantity),
         {:ok, _variant} <- set_reserved(variant, variant.reserved_quantity + line.quantity),
         {:ok, _allocation} <- create_allocation(line, context) do
      {:cont, changeset}
    else
      {:error, message} when is_binary(message) ->
        {:halt, Ash.Changeset.add_error(changeset, field: :fulfillment_status, message: message)}

      {:error, error} ->
        {:halt, Ash.Changeset.add_error(changeset, error)}
    end
  end

  defp create_allocation(line, context) do
    allocated_by_user_id = if match?(%User{}, context.actor), do: context.actor.id

    Ash.create(
      InventoryAllocation,
      %{
        order_line_item_id: line.id,
        product_variant_id: line.product_variant_id,
        quantity: line.quantity,
        allocated_by_user_id: allocated_by_user_id
      },
      action: :reserve,
      authorize?: false
    )
  end

  defp order_lines(order_id) do
    OrderLineItem
    |> Ash.Query.filter(order_id == ^order_id)
    |> Ash.Query.sort(:product_variant_id)
    |> Ash.read!(authorize?: false)
  end

  defp lock_variant(variant_id) do
    ProductVariant
    |> Ash.Query.filter(id == ^variant_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, "product variant does not exist"}
      result -> result
    end
  end

  defp ensure_available(variant, quantity) do
    available = variant.quantity_on_hand - variant.reserved_quantity

    if available >= quantity,
      do: :ok,
      else: {:error, "#{variant.sku} needs #{quantity}, but only #{available} is available"}
  end

  defp set_reserved(variant, quantity) do
    Ash.update(variant, %{reserved_quantity: quantity},
      action: :set_reserved_quantity,
      authorize?: false
    )
  end
end

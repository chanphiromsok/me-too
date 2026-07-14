defmodule Me.Sales.Changes.ReleasePreorderStock do
  alias Me.Catalog.ProductVariant
  alias Me.Inventory.InventoryAllocation
  alias Me.Sales.OrderLineItem

  require Ash.Query

  def release(changeset, disposition) when disposition in [:consumed, :released] do
    changeset.data.id
    |> order_lines()
    |> Enum.reduce_while(changeset, &release_line(&1, &2, disposition))
  end

  defp release_line(line, changeset, disposition) do
    with {:ok, variant} <- lock_variant(line.product_variant_id),
         :ok <- ensure_reserved(variant, line.quantity),
         {:ok, allocation} <- reserved_allocation(line.id),
         {:ok, _allocation} <- close_allocation(allocation, disposition),
         {:ok, _variant} <- set_reserved(variant, variant.reserved_quantity - line.quantity) do
      {:cont, changeset}
    else
      {:error, message} when is_binary(message) ->
        {:halt, Ash.Changeset.add_error(changeset, field: :fulfillment_status, message: message)}

      {:error, error} ->
        {:halt, Ash.Changeset.add_error(changeset, error)}
    end
  end

  defp reserved_allocation(order_line_item_id) do
    InventoryAllocation
    |> Ash.Query.filter(order_line_item_id == ^order_line_item_id and status == :reserved)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, "reserved stock allocation does not exist"}
      result -> result
    end
  end

  defp close_allocation(allocation, :consumed) do
    Ash.update(allocation, %{}, action: :consume, authorize?: false)
  end

  defp close_allocation(allocation, :released) do
    Ash.update(allocation, %{}, action: :release, authorize?: false)
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

  defp ensure_reserved(variant, quantity) when variant.reserved_quantity >= quantity, do: :ok
  defp ensure_reserved(_variant, _quantity), do: {:error, "reserved stock is no longer available"}

  defp set_reserved(variant, quantity) do
    Ash.update(variant, %{reserved_quantity: quantity},
      action: :set_reserved_quantity,
      authorize?: false
    )
  end
end

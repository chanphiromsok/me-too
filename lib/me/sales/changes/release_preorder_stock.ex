defmodule Me.Sales.Changes.ReleasePreorderStock do
  alias Me.Catalog.ProductVariant
  alias Me.Sales.OrderLineItem

  require Ash.Query

  def release(changeset) do
    changeset.data.id
    |> order_lines()
    |> Enum.reduce_while(changeset, &release_line/2)
  end

  defp release_line(line, changeset) do
    with {:ok, variant} <- lock_variant(line.product_variant_id),
         :ok <- ensure_reserved(variant, line.quantity),
         {:ok, _variant} <- set_reserved(variant, variant.reserved_quantity - line.quantity) do
      {:cont, changeset}
    else
      {:error, message} when is_binary(message) ->
        {:halt, Ash.Changeset.add_error(changeset, field: :fulfillment_status, message: message)}

      {:error, error} ->
        {:halt, Ash.Changeset.add_error(changeset, error)}
    end
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

defmodule Me.Sales.Changes.ReservePreorderStock do
  use Ash.Resource.Change

  alias Me.Catalog.ProductVariant
  alias Me.Sales.OrderLineItem

  require Ash.Query

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &reserve_order_stock/1)
  end

  defp reserve_order_stock(changeset) do
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
        |> Enum.reduce_while(changeset, &reserve_line/2)
    end
  end

  defp reserve_line(line, changeset) do
    with {:ok, variant} <- lock_variant(line.product_variant_id),
         :ok <- ensure_available(variant, line.quantity),
         {:ok, _variant} <- set_reserved(variant, variant.reserved_quantity + line.quantity) do
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

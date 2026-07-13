defmodule Me.Inventory.Changes.ApplyStockMovement do
  use Ash.Resource.Change

  alias Me.Catalog.ProductVariant

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &apply_movement/1)
  end

  defp apply_movement(changeset) do
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)
    delta = Ash.Changeset.get_attribute(changeset, :delta)
    reason = Ash.Changeset.get_attribute(changeset, :reason)

    with :ok <- validate_direction(delta, reason),
         {:ok, variant} <- lock_variant(variant_id),
         :ok <- validate_quantity(variant.quantity_on_hand + delta, reason),
         {:ok, _variant} <- update_quantity(variant, variant.quantity_on_hand + delta) do
      changeset
    else
      {:error, message} when is_binary(message) ->
        Ash.Changeset.add_error(changeset, field: :delta, message: message)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp validate_direction(0, _reason), do: {:error, "must not be zero"}

  defp validate_direction(delta, reason)
       when reason in [:restock, :cancellation_restock] and delta < 0,
       do: {:error, "must be positive for #{reason}"}

  defp validate_direction(delta, :sale) when delta > 0,
    do: {:error, "must be negative for sale"}

  defp validate_direction(_delta, _reason), do: :ok

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

  defp validate_quantity(new_quantity, reason)
       when new_quantity < 0 and reason != :adjustment,
       do: {:error, "would oversell this variant"}

  defp validate_quantity(_new_quantity, _reason), do: :ok

  defp update_quantity(variant, quantity) do
    Ash.update(
      variant,
      %{quantity_on_hand: quantity},
      action: :set_quantity_on_hand,
      authorize?: false
    )
  end
end

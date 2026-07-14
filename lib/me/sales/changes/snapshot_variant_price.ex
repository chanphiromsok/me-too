defmodule Me.Sales.Changes.SnapshotVariantPrice do
  use Ash.Resource.Change

  alias Me.Catalog.ProductVariant

  require Ash.Query

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

      ProductVariant
      |> Ash.Query.filter(id == ^variant_id and active == true and product.status == :active)
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, nil} ->
          Ash.Changeset.add_error(changeset,
            field: :product_variant_id,
            message: "is not available for sale"
          )

        {:ok, variant} ->
          Ash.Changeset.force_change_attribute(changeset, :unit_price_cents, variant.price_cents)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end

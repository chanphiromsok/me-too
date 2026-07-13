defmodule Me.Inventory.Changes.SetSignedDelta do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, opts, _context) do
    quantity = Ash.Changeset.get_argument(changeset, :quantity)

    delta =
      case opts[:sign] do
        :positive ->
          quantity

        :negative ->
          -quantity

        :from_direction ->
          signed_quantity(quantity, Ash.Changeset.get_argument(changeset, :direction))
      end

    Ash.Changeset.force_change_attribute(changeset, :delta, delta)
  end

  defp signed_quantity(quantity, :increase), do: quantity
  defp signed_quantity(quantity, :decrease), do: -quantity
end

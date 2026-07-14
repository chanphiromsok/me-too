defmodule Me.Sales.Changes.CancelPreorderFulfillment do
  use Ash.Resource.Change

  alias Me.Sales.Changes.ReleasePreorderStock

  @impl Ash.Resource.Change
  def change(%{data: %{order_kind: :sale}} = changeset, _opts, _context), do: changeset

  def change(%{data: %{fulfillment_status: :ready}} = changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.change_attribute(:fulfillment_status, :cancelled)
    |> Ash.Changeset.before_action(&ReleasePreorderStock.release/1)
  end

  def change(changeset, _opts, _context) do
    Ash.Changeset.change_attribute(changeset, :fulfillment_status, :cancelled)
  end
end

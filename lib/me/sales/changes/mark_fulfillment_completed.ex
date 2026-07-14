defmodule Me.Sales.Changes.MarkFulfillmentCompleted do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(%{data: %{order_kind: :preorder}} = changeset, _opts, _context) do
    Ash.Changeset.change_attribute(changeset, :fulfillment_status, :fulfilled)
  end

  def change(changeset, _opts, _context), do: changeset
end

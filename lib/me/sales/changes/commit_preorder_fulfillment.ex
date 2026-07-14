defmodule Me.Sales.Changes.CommitPreorderFulfillment do
  use Ash.Resource.Change

  alias Me.Sales.Changes.{CommitOrderStock, ReleasePreorderStock}

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      commit_preorder(changeset, context)
    end)
  end

  defp commit_preorder(%{data: %{order_kind: :sale}} = changeset, _context), do: changeset

  defp commit_preorder(%{data: %{fulfillment_status: :ready}} = changeset, context) do
    changeset
    |> ReleasePreorderStock.release(:consumed)
    |> CommitOrderStock.commit(context)
  end

  defp commit_preorder(changeset, _context) do
    Ash.Changeset.add_error(changeset,
      field: :fulfillment_status,
      message: "must be ready before a preorder can be fulfilled"
    )
  end
end

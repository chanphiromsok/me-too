defmodule Me.Sales.Changes.EnsureOrderKind do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, opts, _context) do
    expected_kind = opts[:kind]

    if changeset.data.order_kind == expected_kind do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :order_kind,
        message: "must be #{expected_kind} for this action"
      )
    end
  end
end

defmodule Me.Sales.Changes.EnsureDraftOrder do
  use Ash.Resource.Change

  alias Me.Sales.Order

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order_id =
        Ash.Changeset.get_argument(changeset, :order_id) ||
          Ash.Changeset.get_attribute(changeset, :order_id) ||
          changeset.data.order_id

      case Ash.get(Order, order_id, authorize?: false) do
        {:ok, %Order{status: :draft}} ->
          changeset

        {:ok, %Order{}} ->
          Ash.Changeset.add_error(changeset, field: :order_id, message: "order is not a draft")

        {:ok, nil} ->
          Ash.Changeset.add_error(changeset, field: :order_id, message: "does not exist")

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end

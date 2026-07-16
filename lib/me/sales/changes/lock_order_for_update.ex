defmodule Me.Sales.Changes.LockOrderForUpdate do
  use Ash.Resource.Change

  alias Me.Sales.Order

  require Ash.Query

  @concurrency_fields [:status, :fulfillment_status]

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &lock_current_order/1, prepend?: true)
  end

  defp lock_current_order(changeset) do
    Order
    |> Ash.Query.filter(id == ^changeset.data.id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> validate_locked_order(changeset)
  end

  defp validate_locked_order({:ok, nil}, changeset) do
    Ash.Changeset.add_error(changeset, field: :id, message: "order no longer exists")
  end

  defp validate_locked_order({:ok, locked_order}, changeset) do
    if unchanged_for_action?(locked_order, changeset.data) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :status,
        message: "order changed while this action was waiting; reload and try again"
      )
    end
  end

  defp validate_locked_order({:error, error}, changeset) do
    Ash.Changeset.add_error(changeset, error)
  end

  defp unchanged_for_action?(locked_order, action_order) do
    Enum.all?(@concurrency_fields, fn field ->
      Map.fetch!(locked_order, field) == Map.fetch!(action_order, field)
    end)
  end
end

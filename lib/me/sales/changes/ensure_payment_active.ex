defmodule Me.Sales.Changes.EnsurePaymentActive do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if changeset.data.voided_at do
        Ash.Changeset.add_error(changeset,
          field: :voided_at,
          message: "payment has already been voided"
        )
      else
        changeset
      end
    end)
  end
end

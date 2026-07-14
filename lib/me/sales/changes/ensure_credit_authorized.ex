defmodule Me.Sales.Changes.EnsureCreditAuthorized do
  use Ash.Resource.Change

  alias Me.Accounts.User

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    case {Ash.Changeset.get_attribute(changeset, :payment_terms), context.actor} do
      {:credit, %User{active: true, role: role}} when role in [:admin, :staff] ->
        changeset

      {:credit, _actor} ->
        Ash.Changeset.add_error(changeset,
          field: :payment_terms,
          message: "credit can only be approved by active staff"
        )

      {_payment_terms, _actor} ->
        changeset
    end
  end
end

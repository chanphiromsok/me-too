defmodule Me.Sales.Changes.EnsurePaymentReadyForFulfillment do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &validate_payment/1)
  end

  defp validate_payment(%{data: %{payment_terms: :credit}} = changeset), do: changeset

  defp validate_payment(changeset) do
    order = Ash.load!(changeset.data, [:total_cents, :paid_cents], authorize?: false)

    if order.paid_cents >= order.total_cents do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :status,
        message: "must be paid in full before an immediate-payment order can be fulfilled"
      )
    end
  end
end

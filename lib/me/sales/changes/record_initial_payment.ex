defmodule Me.Sales.Changes.RecordInitialPayment do
  use Ash.Resource.Change

  alias Me.Accounts.User
  alias Me.Sales.Payment

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(&validate_initial_payment(&1, context.actor))
    |> Ash.Changeset.after_action(&record_initial_payment(&1, &2, context.actor))
  end

  defp validate_initial_payment(changeset, actor) do
    case Ash.Changeset.get_argument(changeset, :initial_payment_amount_cents) do
      amount_cents when amount_cents in [nil, 0] ->
        changeset

      _amount_cents ->
        changeset
        |> validate_staff_actor(actor)
        |> validate_payment_method()
    end
  end

  defp validate_staff_actor(changeset, %User{active: true, role: role})
       when role in [:admin, :staff],
       do: changeset

  defp validate_staff_actor(changeset, _actor) do
    Ash.Changeset.add_error(changeset,
      field: :initial_payment_amount_cents,
      message: "can only be recorded by active staff"
    )
  end

  defp validate_payment_method(changeset) do
    case Ash.Changeset.get_argument(changeset, :initial_payment_method) do
      nil ->
        Ash.Changeset.add_error(changeset,
          field: :initial_payment_method,
          message: "is required when an initial payment is recorded"
        )

      _method ->
        changeset
    end
  end

  defp record_initial_payment(changeset, order, actor) do
    case Ash.Changeset.get_argument(changeset, :initial_payment_amount_cents) do
      amount_cents when amount_cents in [nil, 0] ->
        {:ok, order}

      amount_cents ->
        payment_attributes = %{
          order_id: order.id,
          amount_cents: amount_cents,
          method: Ash.Changeset.get_argument(changeset, :initial_payment_method),
          note: Ash.Changeset.get_argument(changeset, :initial_payment_note),
          external_reference:
            Ash.Changeset.get_argument(changeset, :initial_payment_external_reference)
        }

        with {:ok, _payment} <-
               Payment
               |> Ash.Changeset.for_create(:record, payment_attributes, actor: actor)
               |> Ash.create(),
             {:ok, refreshed_order} <-
               Ash.reload(order,
                 load: [:paid_cents, :balance_cents, :payment_state],
                 authorize?: false
               ) do
          {:ok, refreshed_order}
        end
    end
  end
end

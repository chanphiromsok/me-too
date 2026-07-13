defmodule Me.SalesTest do
  use Me.DataCase, async: true

  alias Me.Accounts.{Customer, User}
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.StockMovement
  alias Me.Sales.{Order, OrderLineItem, Payment}

  @password "password123"

  test "happy path submits stock, progresses payment state, and fulfills" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 5, 1_500)

    order = Ash.create!(Order, %{}, actor: customer)

    line =
      Ash.create!(
        OrderLineItem,
        %{order_id: order.id, product_variant_id: variant.id, quantity: 2},
        action: :add_line_item,
        actor: customer
      )

    assert line.unit_price_cents == 1_500
    assert Ash.load!(line, :line_total_cents).line_total_cents == 3_000

    order = Ash.reload!(order, authorize?: false)
    assert order.subtotal_cents == 3_000

    submitted = Ash.update!(order, %{}, action: :submit, actor: customer)
    assert submitted.status == :pending
    assert %DateTime{} = submitted.placed_at
    assert quantity(variant) == 3

    partially_paid =
      Ash.create!(
        Payment,
        %{order_id: order.id, amount_cents: 1_000, method: :cash},
        action: :record,
        actor: staff
      )

    assert partially_paid.recorded_by_user_id == staff.id
    assert payment_state(order, customer) == :partially_paid

    _payment =
      Ash.create!(
        Payment,
        %{order_id: order.id, amount_cents: 2_500, method: :bank_transfer},
        action: :record,
        actor: staff
      )

    assert payment_state(order, customer) == :paid

    fulfilled = Ash.update!(submitted, %{}, action: :fulfill, actor: staff)
    assert fulfilled.status == :fulfilled
    assert %DateTime{} = fulfilled.fulfilled_at
  end

  test "cancelling a pending order restores stock; fulfilled orders cannot cancel" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 4, 2_000)
    order = order_with_line!(customer, variant, 3)

    submitted = Ash.update!(order, %{}, action: :submit, actor: customer)
    assert quantity(variant) == 1

    cancelled =
      Ash.update!(
        submitted,
        %{cancel_reason: "Customer changed their mind"},
        action: :cancel,
        actor: customer
      )

    assert cancelled.status == :cancelled
    assert quantity(variant) == 4
    assert movement_reasons(variant) == [:cancellation_restock, :restock, :sale]

    second_order = order_with_line!(customer, variant, 1)
    second_order = Ash.update!(second_order, %{}, action: :submit, actor: customer)
    fulfilled = Ash.update!(second_order, %{}, action: :fulfill, actor: staff)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(fulfilled, %{}, action: :cancel, actor: customer)
  end

  test "returning a fulfilled order restores every item once" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 4, 2_000)
    order = order_with_line!(customer, variant, 2)

    fulfilled =
      order
      |> Ash.update!(%{}, action: :submit, actor: customer)
      |> Ash.update!(%{}, action: :fulfill, actor: staff)

    assert quantity(variant) == 2

    returned =
      Ash.update!(
        fulfilled,
        %{return_reason: "Wrong size"},
        action: :return,
        actor: staff
      )

    assert returned.status == :returned
    assert returned.return_reason == "Wrong size"
    assert %DateTime{} = returned.returned_at
    assert quantity(variant) == 4
    assert movement_reasons(variant) == [:restock, :return_restock, :sale]

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(returned, %{}, action: :return, actor: staff)

    assert quantity(variant) == 4
  end

  test "insufficient stock rolls back all movements and leaves the order draft" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 1, 1_000)
    order = order_with_line!(customer, variant, 2)

    assert {:error, error} = Ash.update(order, %{}, action: :submit, actor: customer)
    assert Exception.message(error) =~ "would oversell this variant"
    assert Ash.reload!(order, authorize?: false).status == :draft
    assert quantity(variant) == 1
    assert movement_reasons(variant) == [:restock]
  end

  test "customers cannot discover another customer's order" do
    owner = create_customer!()
    other_customer = create_customer!()
    order = Ash.create!(Order, %{}, actor: owner)

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
             Ash.get(Order, order.id, actor: other_customer)
  end

  test "line item price is snapshotted and draft-only" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 3, 1_200)
    order = order_with_line!(customer, variant, 1)

    Ash.update!(variant, %{price_cents: 1_800}, actor: staff)

    [line] = Ash.read!(OrderLineItem, actor: customer)
    assert line.unit_price_cents == 1_200

    submitted = Ash.update!(order, %{}, action: :submit, actor: customer)

    assert {:error, _error} =
             Ash.update(
               line,
               %{order_id: submitted.id, quantity: 2},
               action: :edit,
               actor: customer
             )
  end

  test "adding the same variant upserts quantity without changing the snapshotted price" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 10, 900)
    order = order_with_line!(customer, variant, 1)

    Ash.update!(variant, %{price_cents: 1_100}, actor: staff)

    _line =
      Ash.create!(
        OrderLineItem,
        %{order_id: order.id, product_variant_id: variant.id, quantity: 3},
        action: :add_line_item,
        actor: customer
      )

    [line] = Ash.read!(OrderLineItem, actor: customer)
    assert line.quantity == 3
    assert line.unit_price_cents == 900
    assert Ash.reload!(order, authorize?: false).subtotal_cents == 2_700
  end

  test "voided payments no longer contribute to payment state" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2, 1_000)
    order = order_with_line!(customer, variant, 1)
    _submitted = Ash.update!(order, %{}, action: :submit, actor: customer)

    payment =
      Ash.create!(
        Payment,
        %{order_id: order.id, amount_cents: 1_000, method: :cash},
        action: :record,
        actor: staff
      )

    assert payment_state(order, customer) == :paid
    assert %DateTime{} = Ash.update!(payment, %{}, action: :void, actor: staff).voided_at
    assert payment_state(order, customer) == :unpaid
  end

  test "order numbers are sequential and unique" do
    customer = create_customer!()
    first = Ash.create!(Order, %{}, actor: customer)
    second = Ash.create!(Order, %{}, actor: customer)

    assert second.order_number > first.order_number
  end

  defp order_with_line!(customer, variant, quantity) do
    order = Ash.create!(Order, %{}, actor: customer)

    _line =
      Ash.create!(
        OrderLineItem,
        %{order_id: order.id, product_variant_id: variant.id, quantity: quantity},
        action: :add_line_item,
        actor: customer
      )

    Ash.reload!(order, authorize?: false)
  end

  defp payment_state(order, actor) do
    order
    |> Ash.reload!(authorize?: false)
    |> Ash.load!([:total_cents, :paid_cents, :payment_state], actor: actor)
    |> Map.fetch!(:payment_state)
  end

  defp movement_reasons(variant) do
    StockMovement
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(&1.product_variant_id == variant.id))
    |> Enum.map(& &1.reason)
    |> Enum.sort()
  end

  defp quantity(variant) do
    Ash.reload!(variant, authorize?: false).quantity_on_hand
  end

  defp create_stocked_variant!(staff, quantity, price) do
    product = Ash.create!(Product, %{name: "Sales Test Product"}, actor: staff)

    variant =
      Ash.create!(
        ProductVariant,
        %{
          product_id: product.id,
          sku: "SALES-#{System.unique_integer([:positive])}",
          size: "M",
          color: "Black",
          price_cents: price
        },
        actor: staff
      )

    Ash.create!(
      StockMovement,
      %{product_variant_id: variant.id, quantity: quantity},
      action: :restock,
      actor: staff
    )

    variant
  end

  defp create_staff! do
    Ash.create!(
      User,
      %{
        name: "Sales Test Staff",
        email: unique_email("staff"),
        password: @password,
        password_confirmation: @password
      },
      action: :register_with_password,
      authorize?: false
    )
  end

  defp create_customer! do
    Customer
    |> Ash.create!(
      %{
        name: "Sales Test Customer",
        email: unique_email("customer"),
        password: @password,
        password_confirmation: @password
      },
      action: :register
    )
    |> Ash.update!(%{}, action: :confirm, authorize?: false)
  end

  defp unique_email(prefix) do
    "sales-#{prefix}-#{System.unique_integer([:positive])}@example.com"
  end
end

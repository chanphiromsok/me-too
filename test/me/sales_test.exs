defmodule Me.SalesTest do
  use Me.DataCase, async: true

  alias Me.Accounts.{Customer, User}
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.{InventoryAllocation, StockMovement}
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

  test "preorder confirmation records demand without changing stock, then allocates and fulfills" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 0, 1_250)

    preorder =
      customer
      |> preorder_with_line!(variant, 2)
      |> Ash.update!(%{}, action: :confirm_preorder, actor: staff)

    assert preorder.status == :pending
    assert preorder.fulfillment_status == :awaiting_stock
    assert quantity(variant) == 0
    assert reserved_quantity(variant) == 0
    assert movement_reasons(variant) == []

    assert {:error, allocation_error} =
             Ash.update(preorder, %{}, action: :allocate_preorder, actor: staff)

    assert Exception.message(allocation_error) =~ "only 0 is available"

    Ash.create!(
      StockMovement,
      %{product_variant_id: variant.id, quantity: 5},
      action: :restock,
      actor: staff
    )

    ready = Ash.update!(preorder, %{}, action: :allocate_preorder, actor: staff)
    assert ready.fulfillment_status == :ready
    assert quantity(variant) == 5
    assert reserved_quantity(variant) == 2

    allocation = allocation_for_variant!(variant)
    assert allocation.quantity == 2
    assert allocation.status == :reserved
    assert allocation.allocated_by_user_id == staff.id

    fulfilled = Ash.update!(ready, %{}, action: :fulfill, actor: staff)
    assert fulfilled.status == :fulfilled
    assert fulfilled.fulfillment_status == :fulfilled
    assert quantity(variant) == 3
    assert reserved_quantity(variant) == 0
    assert movement_reasons(variant) == [:restock, :sale]

    consumed_allocation = Ash.reload!(allocation, authorize?: false)
    assert consumed_allocation.status == :consumed
    assert %DateTime{} = consumed_allocation.consumed_at
    assert is_nil(consumed_allocation.released_at)
  end

  test "reserved preorder stock cannot be sold and cancellation releases it" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2, 1_000)

    ready_preorder =
      customer
      |> preorder_with_line!(variant, 2)
      |> Ash.update!(%{}, action: :confirm_preorder, actor: staff)
      |> Ash.update!(%{}, action: :allocate_preorder, actor: staff)

    sale = order_with_line!(customer, variant, 1)
    assert {:error, sale_error} = Ash.update(sale, %{}, action: :submit, actor: staff)
    assert Exception.message(sale_error) =~ "reserved for another order"

    assert {:error, adjustment_error} =
             Ash.create(
               StockMovement,
               %{
                 product_variant_id: variant.id,
                 quantity: 1,
                 direction: :decrease,
                 note: "Count correction"
               },
               action: :adjust,
               actor: staff
             )

    assert Exception.message(adjustment_error) =~ "reserved for another order"
    assert quantity(variant) == 2

    cancelled =
      Ash.update!(
        ready_preorder,
        %{cancel_reason: "Customer changed their mind"},
        action: :cancel,
        actor: staff
      )

    assert cancelled.status == :cancelled
    assert cancelled.fulfillment_status == :cancelled
    assert quantity(variant) == 2
    assert reserved_quantity(variant) == 0
    assert movement_reasons(variant) == [:restock]

    released_allocation = allocation_for_variant!(variant)
    assert released_allocation.status == :released
    assert %DateTime{} = released_allocation.released_at
    assert is_nil(released_allocation.consumed_at)
  end

  test "a multi-line preorder allocation is all-or-nothing" do
    staff = create_staff!()
    customer = create_customer!()
    available_variant = create_stocked_variant!(staff, 3, 1_000)
    unavailable_variant = create_stocked_variant!(staff, 1, 2_000)

    preorder = preorder_with_line!(customer, available_variant, 2)

    _line =
      Ash.create!(
        OrderLineItem,
        %{
          order_id: preorder.id,
          product_variant_id: unavailable_variant.id,
          quantity: 2
        },
        action: :add_line_item,
        actor: customer
      )

    confirmed =
      preorder
      |> Ash.reload!(authorize?: false)
      |> Ash.update!(%{}, action: :confirm_preorder, actor: staff)

    assert {:error, error} =
             Ash.update(confirmed, %{}, action: :allocate_preorder, actor: staff)

    assert Exception.message(error) =~ "only 1 is available"
    assert Ash.reload!(confirmed, authorize?: false).fulfillment_status == :awaiting_stock
    assert reserved_quantity(available_variant) == 0
    assert reserved_quantity(unavailable_variant) == 0
    assert Ash.read!(InventoryAllocation, authorize?: false) == []
  end

  test "a preorder cannot fulfill before stock is allocated" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2, 1_000)

    confirmed =
      customer
      |> preorder_with_line!(variant, 2)
      |> Ash.update!(%{}, action: :confirm_preorder, actor: staff)

    assert {:error, error} = Ash.update(confirmed, %{}, action: :fulfill, actor: staff)
    assert Exception.message(error) =~ "must be ready"
    assert Ash.reload!(confirmed, authorize?: false).status == :pending
    assert quantity(variant) == 2
    assert reserved_quantity(variant) == 0
    assert movement_reasons(variant) == [:restock]
  end

  test "cancelling a preorder awaiting stock does not create inventory activity" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 0, 1_000)

    confirmed =
      customer
      |> preorder_with_line!(variant, 2)
      |> Ash.update!(%{}, action: :confirm_preorder, actor: staff)

    cancelled = Ash.update!(confirmed, %{}, action: :cancel, actor: staff)

    assert cancelled.status == :cancelled
    assert cancelled.fulfillment_status == :cancelled
    assert quantity(variant) == 0
    assert reserved_quantity(variant) == 0
    assert movement_reasons(variant) == []
    assert Ash.read!(InventoryAllocation, authorize?: false) == []
  end

  test "competing preorders cannot reserve the same stock and released stock becomes available" do
    staff = create_staff!()
    first_customer = create_customer!()
    second_customer = create_customer!()
    variant = create_stocked_variant!(staff, 2, 1_000)

    first_preorder =
      first_customer
      |> preorder_with_line!(variant, 2)
      |> Ash.update!(%{}, action: :confirm_preorder, actor: staff)
      |> Ash.update!(%{}, action: :allocate_preorder, actor: staff)

    second_preorder =
      second_customer
      |> preorder_with_line!(variant, 2)
      |> Ash.update!(%{}, action: :confirm_preorder, actor: staff)

    assert {:error, error} =
             Ash.update(second_preorder, %{}, action: :allocate_preorder, actor: staff)

    assert Exception.message(error) =~ "only 0 is available"
    assert reserved_quantity(variant) == 2

    _cancelled = Ash.update!(first_preorder, %{}, action: :cancel, actor: staff)
    assert reserved_quantity(variant) == 0

    second_ready =
      Ash.update!(second_preorder, %{}, action: :allocate_preorder, actor: staff)

    assert second_ready.fulfillment_status == :ready
    assert reserved_quantity(variant) == 2

    allocations = Ash.read!(InventoryAllocation, authorize?: false)
    assert Enum.count(allocations, &(&1.status == :released)) == 1
    assert Enum.count(allocations, &(&1.status == :reserved)) == 1
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

  test "inactive variants and archived products cannot be added from stale product results" do
    staff = create_staff!()
    admin = create_staff!(role: :admin)
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2, 1_000)
    inactive_variant = Ash.update!(variant, %{active: false}, actor: staff)
    order = Ash.create!(Order, %{}, actor: customer)

    assert {:error, error} =
             Ash.create(
               OrderLineItem,
               %{
                 order_id: order.id,
                 product_variant_id: inactive_variant.id,
                 quantity: 1
               },
               action: :add_line_item,
               actor: customer
             )

    assert Exception.message(error) =~ "is not available for sale"
    assert Ash.read!(OrderLineItem, actor: customer) == []
    assert Ash.reload!(order, authorize?: false).subtotal_cents == 0

    archived_variant = create_stocked_variant!(staff, 2, 1_000)
    product = Ash.get!(Product, archived_variant.product_id, authorize?: false)
    _archived_product = Ash.update!(product, %{}, action: :archive, actor: admin)

    assert {:error, error} =
             Ash.create(
               OrderLineItem,
               %{
                 order_id: order.id,
                 product_variant_id: archived_variant.id,
                 quantity: 1
               },
               action: :add_line_item,
               actor: customer
             )

    assert Exception.message(error) =~ "is not available for sale"
    assert Ash.read!(OrderLineItem, actor: customer) == []
    assert Ash.reload!(order, authorize?: false).subtotal_cents == 0
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

  defp preorder_with_line!(customer, variant, quantity) do
    order =
      Ash.create!(
        Order,
        %{order_kind: :preorder, sales_channel: :group_chat},
        actor: customer
      )

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

  defp allocation_for_variant!(variant) do
    InventoryAllocation
    |> Ash.read!(authorize?: false)
    |> Enum.find(&(&1.product_variant_id == variant.id))
  end

  defp quantity(variant) do
    Ash.reload!(variant, authorize?: false).quantity_on_hand
  end

  defp reserved_quantity(variant) do
    Ash.reload!(variant, authorize?: false).reserved_quantity
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

    if quantity > 0 do
      Ash.create!(
        StockMovement,
        %{product_variant_id: variant.id, quantity: quantity},
        action: :restock,
        actor: staff
      )
    end

    variant
  end

  defp create_staff!(opts \\ []) do
    role = Keyword.get(opts, :role, :staff)

    Ash.create!(
      User,
      %{
        name: "Sales Test #{role}",
        email: unique_email(to_string(role)),
        role: role,
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

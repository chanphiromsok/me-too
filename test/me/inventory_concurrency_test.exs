defmodule Me.InventoryConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Me.Accounts.{Customer, User}
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.{InventoryAllocation, StockMovement}
  alias Me.Repo
  alias Me.Sales.{Order, OrderLineItem}

  require Ash.Query

  @password "password123"

  test "two simultaneous sales of the last unit allow exactly one" do
    fixture = Sandbox.unboxed_run(Repo, &create_fixture!/0)
    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup!(fixture) end) end)

    results =
      race([
        fn -> sell_last_unit(fixture) end,
        fn -> sell_last_unit(fixture) end
      ])

    assert Enum.count(results, &match?({:ok, %StockMovement{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Ash.Error.Invalid{}}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      assert Ash.reload!(fixture.variant, authorize?: false).quantity_on_hand == 0
      assert_ledger_balances(fixture.variant, 2)
    end)
  end

  test "two simultaneous order submits competing for the last unit allow exactly one" do
    fixture =
      Sandbox.unboxed_run(Repo, fn ->
        fixture = create_fixture!()

        Map.put(fixture, :orders, [
          create_sale_order!(fixture, 1),
          create_sale_order!(fixture, 1)
        ])
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup!(fixture) end) end)

    results =
      race(
        Enum.map(fixture.orders, fn order ->
          fn -> Ash.update(order, %{}, action: :submit, actor: fixture.staff) end
        end)
      )

    assert Enum.count(results, &match?({:ok, %Order{status: :pending}}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Ash.Error.Invalid{}}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      statuses = Enum.map(fixture.orders, &Ash.reload!(&1, authorize?: false).status)

      assert Enum.sort(statuses) == [:draft, :pending]
      assert Ash.reload!(fixture.variant, authorize?: false).quantity_on_hand == 0
      assert_ledger_balances(fixture.variant, 2)
    end)
  end

  test "simultaneous cancel and fulfill on one pending order allow only one transition" do
    fixture =
      Sandbox.unboxed_run(Repo, fn ->
        fixture = create_fixture!()

        submitted =
          fixture
          |> create_sale_order!(1)
          |> Ash.update!(%{}, action: :submit, actor: fixture.staff)

        Map.put(fixture, :submitted_order, submitted)
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup!(fixture) end) end)

    results =
      race([
        fn ->
          Ash.update(fixture.submitted_order, %{}, action: :cancel, actor: fixture.staff)
        end,
        fn ->
          Ash.update(fixture.submitted_order, %{}, action: :fulfill, actor: fixture.staff)
        end
      ])

    assert Enum.count(results, &match?({:ok, %Order{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Ash.Error.Invalid{}}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      order = Ash.reload!(fixture.submitted_order, authorize?: false)
      quantity = Ash.reload!(fixture.variant, authorize?: false).quantity_on_hand

      assert order.status in [:cancelled, :fulfilled]
      assert quantity == if(order.status == :cancelled, do: 1, else: 0)
      assert_ledger_balances(fixture.variant, if(order.status == :cancelled, do: 3, else: 2))
    end)
  end

  test "two simultaneous preorders cannot reserve the same last unit" do
    fixture =
      Sandbox.unboxed_run(Repo, fn ->
        fixture = create_fixture!()

        preorders =
          for _attempt <- 1..2 do
            fixture
            |> create_preorder!(1)
            |> Ash.update!(%{}, action: :confirm_preorder, actor: fixture.staff)
          end

        Map.put(fixture, :preorders, preorders)
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup!(fixture) end) end)

    results =
      race(
        Enum.map(fixture.preorders, fn preorder ->
          fn ->
            Ash.update(preorder, %{}, action: :allocate_preorder, actor: fixture.staff)
          end
        end)
      )

    assert Enum.count(
             results,
             &match?({:ok, %Order{fulfillment_status: :ready}}, &1)
           ) == 1

    assert Enum.count(results, &match?({:error, %Ash.Error.Invalid{}}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      fulfillment_statuses =
        Enum.map(
          fixture.preorders,
          &Ash.reload!(&1, authorize?: false).fulfillment_status
        )

      variant = Ash.reload!(fixture.variant, authorize?: false)

      assert Enum.sort(fulfillment_statuses) == [:awaiting_stock, :ready]
      assert variant.quantity_on_hand == 1
      assert variant.reserved_quantity == 1

      allocations =
        InventoryAllocation
        |> Ash.Query.filter(product_variant_id == ^variant.id)
        |> Ash.read!(authorize?: false)

      assert length(allocations) == 1
      assert_ledger_balances(fixture.variant, 1)
    end)
  end

  test "preorder allocation wins before a simultaneous sale can consume the same unit" do
    fixture =
      Sandbox.unboxed_run(Repo, fn ->
        fixture = create_fixture!()
        sale_order = create_sale_order!(fixture, 1)

        preorder =
          fixture
          |> create_preorder!(1)
          |> Ash.update!(%{}, action: :confirm_preorder, actor: fixture.staff)

        fixture
        |> Map.put(:sale_order, sale_order)
        |> Map.put(:preorder, preorder)
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup!(fixture) end) end)

    parent = self()

    allocation_task =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.query!("SELECT id FROM product_variants WHERE id = $1::uuid FOR UPDATE", [
              Ecto.UUID.dump!(fixture.variant.id)
            ])

            send(parent, {:allocation_locked, self()})
            receive do: (:go -> :ok)

            Ash.update(
              fixture.preorder,
              %{},
              action: :allocate_preorder,
              actor: fixture.staff,
              return_notifications?: true
            )
          end)
        end)
      end)

    assert_receive {:allocation_locked, allocation_pid}

    sale_task =
      Task.async(fn ->
        send(parent, {:sale_ready, self()})
        receive do: (:go -> :ok)

        Sandbox.unboxed_run(Repo, fn ->
          Ash.update(fixture.sale_order, %{}, action: :submit, actor: fixture.staff)
        end)
      end)

    assert_receive {:sale_ready, sale_pid}
    send(allocation_pid, :go)
    send(sale_pid, :go)

    assert {:ok, {:ok, %Order{fulfillment_status: :ready}, _notifications}} =
             Task.await(allocation_task, 5_000)

    assert {:error, %Ash.Error.Invalid{} = sale_error} = Task.await(sale_task, 5_000)
    assert Exception.message(sale_error) =~ "reserved for another order"

    Sandbox.unboxed_run(Repo, fn ->
      assert Ash.reload!(fixture.preorder, authorize?: false).fulfillment_status == :ready
      assert Ash.reload!(fixture.sale_order, authorize?: false).status == :draft

      variant = Ash.reload!(fixture.variant, authorize?: false)
      assert variant.quantity_on_hand == 1
      assert variant.reserved_quantity == 1
      assert_ledger_balances(fixture.variant, 1)
    end)
  end

  defp race(functions) do
    parent = self()

    tasks =
      Enum.map(functions, fn operation ->
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do: (:go -> :ok)
          Sandbox.unboxed_run(Repo, operation)
        end)
      end)

    task_pids = Enum.map(tasks, & &1.pid)

    for task_pid <- task_pids do
      assert_receive {:ready, ^task_pid}
    end

    Enum.each(task_pids, &send(&1, :go))
    Enum.map(tasks, &Task.await(&1, 5_000))
  end

  defp sell_last_unit(fixture) do
    Ash.create(
      StockMovement,
      %{product_variant_id: fixture.variant.id, quantity: 1},
      action: :sale,
      actor: fixture.staff
    )
  end

  defp create_fixture! do
    unique = Ash.UUID.generate()

    staff =
      Ash.create!(
        User,
        %{
          name: "Concurrency Test Staff",
          email: "inventory-concurrency-staff-#{unique}@example.com",
          password: @password,
          password_confirmation: @password
        },
        action: :register_with_password,
        authorize?: false
      )

    customer =
      Customer
      |> Ash.create!(
        %{
          name: "Concurrency Test Customer",
          email: "inventory-concurrency-customer-#{unique}@example.com",
          password: @password,
          password_confirmation: @password
        },
        action: :register
      )
      |> Ash.update!(%{}, action: :confirm, authorize?: false)

    product = Ash.create!(Product, %{name: "Concurrency Product #{unique}"}, actor: staff)

    variant =
      Ash.create!(
        ProductVariant,
        %{
          product_id: product.id,
          sku: "CONCURRENCY-#{unique}",
          size: "One Size",
          color: "Black",
          price_cents: 1_000
        },
        actor: staff
      )

    Ash.create!(
      StockMovement,
      %{product_variant_id: variant.id, quantity: 1},
      action: :restock,
      actor: staff
    )

    %{customer: customer, product: product, staff: staff, variant: variant}
  end

  defp create_sale_order!(fixture, quantity) do
    order =
      Ash.create!(
        Order,
        %{customer_id: fixture.customer.id, payment_terms: :credit},
        actor: fixture.staff
      )

    add_line!(fixture, order, quantity)
    Ash.reload!(order, authorize?: false)
  end

  defp create_preorder!(fixture, quantity) do
    order =
      Ash.create!(
        Order,
        %{
          customer_id: fixture.customer.id,
          order_kind: :preorder,
          payment_terms: :credit,
          sales_channel: :group_chat
        },
        actor: fixture.staff
      )

    add_line!(fixture, order, quantity)
    Ash.reload!(order, authorize?: false)
  end

  defp add_line!(fixture, order, quantity) do
    Ash.create!(
      OrderLineItem,
      %{
        order_id: order.id,
        product_variant_id: fixture.variant.id,
        quantity: quantity
      },
      action: :add_line_item,
      actor: fixture.staff
    )
  end

  defp assert_ledger_balances(variant, expected_movement_count) do
    variant = Ash.reload!(variant, authorize?: false)

    movements =
      StockMovement
      |> Ash.Query.filter(product_variant_id == ^variant.id)
      |> Ash.read!(authorize?: false)

    assert Enum.sum_by(movements, & &1.delta) == variant.quantity_on_hand
    assert length(movements) == expected_movement_count
    assert Enum.all?(movements, &(&1.reference_type && &1.reference_id))
  end

  defp cleanup!(fixture) do
    customer_id = Ecto.UUID.dump!(fixture.customer.id)
    variant_id = Ecto.UUID.dump!(fixture.variant.id)

    Repo.query!(
      """
      DELETE FROM inventory_allocations
      WHERE order_line_item_id IN (
        SELECT line.id
        FROM order_line_items AS line
        INNER JOIN orders ON orders.id = line.order_id
        WHERE orders.customer_id = $1::uuid
      )
      """,
      [customer_id]
    )

    Repo.query!(
      "DELETE FROM payments WHERE order_id IN (SELECT id FROM orders WHERE customer_id = $1::uuid)",
      [customer_id]
    )

    Repo.query!(
      "DELETE FROM order_line_items WHERE order_id IN (SELECT id FROM orders WHERE customer_id = $1::uuid)",
      [customer_id]
    )

    Repo.query!("DELETE FROM orders WHERE customer_id = $1::uuid", [customer_id])
    Repo.query!("DELETE FROM stock_movements WHERE product_variant_id = $1::uuid", [variant_id])
    Repo.query!("DELETE FROM product_variants WHERE id = $1::uuid", [variant_id])

    Repo.query!("DELETE FROM products WHERE id = $1::uuid", [
      Ecto.UUID.dump!(fixture.product.id)
    ])

    Repo.query!("DELETE FROM tokens WHERE subject IN ($1, $2)", [
      "user?id=#{fixture.staff.id}",
      "customer?id=#{fixture.customer.id}"
    ])

    Repo.query!("DELETE FROM customers WHERE id = $1::uuid", [customer_id])

    Repo.query!("DELETE FROM users WHERE id = $1::uuid", [
      Ecto.UUID.dump!(fixture.staff.id)
    ])
  end
end

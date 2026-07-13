defmodule Me.InventoryConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Me.Accounts.User
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.StockMovement
  alias Me.Repo

  require Ash.Query

  @password "password123"

  test "two simultaneous sales of the last unit allow exactly one" do
    fixture = Sandbox.unboxed_run(Repo, &create_fixture!/0)
    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup!(fixture) end) end)

    parent = self()

    tasks =
      for _attempt <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do: (:go -> :ok)

          Sandbox.unboxed_run(Repo, fn ->
            Ash.create(
              StockMovement,
              %{product_variant_id: fixture.variant.id, quantity: 1},
              action: :sale,
              actor: fixture.staff
            )
          end)
        end)
      end

    task_pids = Enum.map(tasks, & &1.pid)

    for task_pid <- task_pids do
      assert_receive {:ready, ^task_pid}
    end

    Enum.each(task_pids, &send(&1, :go))
    results = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, %StockMovement{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Ash.Error.Invalid{}}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      assert Ash.reload!(fixture.variant, authorize?: false).quantity_on_hand == 0

      movements =
        StockMovement
        |> Ash.Query.filter(product_variant_id == ^fixture.variant.id)
        |> Ash.read!(authorize?: false)

      assert Enum.sum_by(movements, & &1.delta) == 0
      assert length(movements) == 2
    end)
  end

  defp create_fixture! do
    unique = System.unique_integer([:positive])

    staff =
      Ash.create!(
        User,
        %{
          name: "Concurrency Test Staff",
          email: "inventory-concurrency-#{unique}@example.com",
          password: @password,
          password_confirmation: @password
        },
        action: :register_with_password,
        authorize?: false
      )

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

    %{staff: staff, product: product, variant: variant}
  end

  defp cleanup!(fixture) do
    Repo.query!("DELETE FROM stock_movements WHERE product_variant_id = $1::uuid", [
      Ecto.UUID.dump!(fixture.variant.id)
    ])

    Repo.query!("DELETE FROM product_variants WHERE id = $1::uuid", [
      Ecto.UUID.dump!(fixture.variant.id)
    ])

    Repo.query!("DELETE FROM products WHERE id = $1::uuid", [
      Ecto.UUID.dump!(fixture.product.id)
    ])

    Repo.query!("DELETE FROM tokens WHERE subject = $1", ["user?id=#{fixture.staff.id}"])

    Repo.query!("DELETE FROM users WHERE id = $1::uuid", [
      Ecto.UUID.dump!(fixture.staff.id)
    ])
  end
end

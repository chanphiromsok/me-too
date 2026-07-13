defmodule Me.InventoryTest do
  use Me.DataCase, async: true

  alias Me.Accounts.{Customer, User}
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.StockMovement

  require Ash.Query

  @password "password123"

  test "ledger sum stays equal to quantity_on_hand after a sequence of movements" do
    staff = create_staff!()
    variant = create_variant!(staff)

    restock = move_stock!(variant, staff, :restock, 10)
    _sale = move_stock!(variant, staff, :sale, 3)
    _cancellation = move_stock!(variant, staff, :cancellation_restock, 1)
    _adjustment = move_stock!(variant, staff, :adjust, 2, direction: :decrease)

    assert restock.actor_id == staff.id
    assert restock.delta == 10
    assert quantity(variant) == 6
    assert movement_sum(variant) == quantity(variant)
  end

  test "overselling returns a validation error without changing stock or ledger" do
    staff = create_staff!()
    variant = create_variant!(staff)

    assert {:error, error} =
             Ash.create(
               StockMovement,
               %{product_variant_id: variant.id, quantity: 1},
               action: :sale,
               actor: staff
             )

    assert Exception.message(error) =~ "would oversell this variant"
    assert quantity(variant) == 0
    assert movement_sum(variant) == 0
  end

  test "the ledger is staff-only and insert-only" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_variant!(staff)

    assert {:error, _error} =
             Ash.create(
               StockMovement,
               %{product_variant_id: variant.id, quantity: 1},
               action: :restock,
               actor: customer
             )

    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(StockMovement)
    assert is_nil(Ash.Resource.Info.action(StockMovement, :update))
    assert is_nil(Ash.Resource.Info.action(StockMovement, :destroy))
  end

  defp move_stock!(variant, actor, action, quantity, opts \\ []) do
    attrs =
      %{product_variant_id: variant.id, quantity: quantity}
      |> Map.merge(Map.new(opts))

    Ash.create!(
      StockMovement,
      attrs,
      action: action,
      actor: actor
    )
  end

  defp movement_sum(variant) do
    StockMovement
    |> Ash.Query.filter(product_variant_id == ^variant.id)
    |> Ash.read!(authorize?: false)
    |> Enum.sum_by(& &1.delta)
  end

  defp quantity(variant) do
    variant
    |> Ash.reload!(authorize?: false)
    |> Map.fetch!(:quantity_on_hand)
  end

  defp create_variant!(staff) do
    product = Ash.create!(Product, %{name: "Inventory Test Product"}, actor: staff)

    Ash.create!(
      ProductVariant,
      %{
        product_id: product.id,
        sku: "INV-#{System.unique_integer([:positive])}",
        size: "M",
        color: "Black",
        price_cents: 2_000
      },
      actor: staff
    )
  end

  defp create_staff! do
    Ash.create!(
      User,
      %{
        name: "Inventory Test Staff",
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
        name: "Inventory Test Customer",
        email: unique_email("customer"),
        password: @password,
        password_confirmation: @password
      },
      action: :register
    )
    |> Ash.update!(%{}, action: :confirm, authorize?: false)
  end

  defp unique_email(prefix) do
    "inventory-#{prefix}-#{System.unique_integer([:positive])}@example.com"
  end
end

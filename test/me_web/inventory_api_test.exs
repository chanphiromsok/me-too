defmodule MeWeb.InventoryApiTest do
  use MeWeb.ConnCase, async: true

  alias Me.Accounts.User
  alias Me.Catalog.{Product, ProductVariant}

  @password "password123"

  test "inventory exposes only the narrow variant routes" do
    staff = create_staff!()
    variant = create_variant!(staff)

    restock = movement_request(staff, variant, "restock", 5)
    adjustment = movement_request(staff, variant, "adjust", 2, direction: "decrease")

    assert json_response(restock, 201)["data"]["attributes"]["reason"] == "restock"
    assert json_response(adjustment, 201)["data"]["attributes"]["reason"] == "adjustment"
    assert json_response(restock, 201)["data"]["attributes"]["delta"] == 5
    assert json_response(adjustment, 201)["data"]["attributes"]["delta"] == -2

    invalid_restock = movement_request(staff, variant, "restock", -1)
    assert json_response(invalid_restock, 400)["errors"]

    movements =
      build_conn()
      |> put_req_header("authorization", "Bearer #{staff.__metadata__.token}")
      |> get("/api/product-variants/#{variant.id}/stock-movements")
      |> json_response(200)

    assert length(movements["data"]) == 2

    generic =
      build_conn()
      |> put_req_header("authorization", "Bearer #{staff.__metadata__.token}")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post(
        "/api/stock-movements",
        Jason.encode!(%{data: %{type: "stock_movement", attributes: %{delta: 1}}})
      )

    assert json_response(generic, 404)["errors"]
  end

  test "a client reference prevents a retried restock from adding stock twice" do
    staff = create_staff!()
    variant = create_variant!(staff)
    reference_id = Ecto.UUID.generate()

    attributes = [reference_type: "mobile", reference_id: reference_id]

    first_restock = movement_request(staff, variant, "restock", 5, attributes)
    assert json_response(first_restock, 201)["data"]["attributes"]["delta"] == 5

    retried_restock = movement_request(staff, variant, "restock", 5, attributes)
    assert json_response(retried_restock, 400)["errors"]
    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 5
  end

  defp movement_request(staff, variant, action, quantity, opts \\ []) do
    attributes =
      %{quantity: quantity, note: "API test"}
      |> Map.merge(Map.new(opts))

    build_conn()
    |> put_req_header("authorization", "Bearer #{staff.__metadata__.token}")
    |> put_req_header("content-type", "application/vnd.api+json")
    |> post(
      "/api/product-variants/#{variant.id}/#{action}",
      Jason.encode!(%{
        data: %{type: "stock_movement", attributes: attributes}
      })
    )
  end

  defp create_variant!(staff) do
    product = Ash.create!(Product, %{name: "Inventory API Product"}, actor: staff)

    Ash.create!(
      ProductVariant,
      %{
        product_id: product.id,
        sku: "INV-API-#{System.unique_integer([:positive])}",
        size: "L",
        color: "Blue",
        price_cents: 2_500
      },
      actor: staff
    )
  end

  defp create_staff! do
    Ash.create!(
      User,
      %{
        name: "Inventory API Staff",
        email: "inventory-api-#{System.unique_integer([:positive])}@example.com",
        password: @password,
        password_confirmation: @password
      },
      action: :register_with_password,
      authorize?: false
    )
  end
end

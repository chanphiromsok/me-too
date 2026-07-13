defmodule MeWeb.ApiSurfaceTest do
  use MeWeb.ConnCase, async: true

  alias Me.Accounts.{Customer, User}
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.StockMovement
  alias Me.Sales.{Order, OrderLineItem, Payment}

  @password "password123"

  test "filtering, sorting, and receipt includes work for customer flows" do
    fixture = create_fixture!()

    variant_query = URI.encode_query(%{"filter[barcode]" => fixture.variant.barcode})

    variants =
      build_conn()
      |> get("/api/product-variants?#{variant_query}")
      |> json_response(200)

    assert [variant_data] = variants["data"]
    assert variant_data["id"] == fixture.variant.id

    product_query = URI.encode_query(%{"filter[status]" => "active"})
    products = build_conn() |> get("/api/products?#{product_query}") |> json_response(200)
    assert Enum.any?(products["data"], &(&1["id"] == fixture.product.id))

    history =
      fixture.customer
      |> api_conn()
      |> get("/api/orders?sort=-placed_at")
      |> json_response(200)

    assert Enum.map(history["data"], & &1["id"]) == [fixture.order.id]

    receipt_query =
      URI.encode_query(%{"include" => "line_items.product_variant,payments"})

    receipt =
      fixture.customer
      |> api_conn()
      |> get("/api/orders/#{fixture.order.id}?#{receipt_query}")
      |> json_response(200)

    assert receipt["data"]["attributes"]["payment_state"] == "partially_paid"
    assert receipt["data"]["attributes"]["total_cents"] == 2_000
    assert Enum.any?(receipt["included"], &(&1["type"] == "order_line_item"))
    assert Enum.any?(receipt["included"], &(&1["type"] == "product_variant"))
    assert Enum.any?(receipt["included"], &(&1["type"] == "payment"))
  end

  test "OpenAPI omits forbidden generic and destructive routes", %{conn: conn} do
    paths =
      conn |> get("/api/open-api") |> response(200) |> Jason.decode!() |> Map.fetch!("paths")

    refute paths["/api/stock-movements"]
    refute paths["/api/orders/{id}"]["patch"]
    refute paths["/api/orders/{id}"]["delete"]
    refute paths["/api/payments/{id}/void"]["delete"]
    refute paths["/api/customers/{id}"]["delete"]
    refute paths["/api/staff/{id}"]["delete"]

    assert paths["/api/orders/{id}/submit"]["patch"]
    assert paths["/api/product-variants/{product_variant_id}/restock"]["post"]
  end

  test "list endpoints enforce the maximum page size" do
    query = URI.encode_query(%{"page[limit]" => "101"})
    response = build_conn() |> get("/api/products?#{query}")

    assert json_response(response, 400)["errors"]
  end

  defp create_fixture! do
    staff = create_staff!()
    customer = create_customer!()
    other_customer = create_customer!()
    unique = System.unique_integer([:positive])

    product =
      Ash.create!(Product, %{name: "API Surface Product #{unique}", category: "Kids"},
        actor: staff
      )

    variant =
      Ash.create!(
        ProductVariant,
        %{
          product_id: product.id,
          sku: "SURFACE-#{unique}",
          size: "4T",
          color: "Green",
          barcode: "BARCODE-#{unique}",
          price_cents: 1_000
        },
        actor: staff
      )

    Ash.create!(
      StockMovement,
      %{product_variant_id: variant.id, quantity: 5},
      action: :restock,
      actor: staff
    )

    order = Ash.create!(Order, %{}, actor: customer)

    Ash.create!(
      OrderLineItem,
      %{order_id: order.id, product_variant_id: variant.id, quantity: 2},
      action: :add_line_item,
      actor: customer
    )

    order =
      order
      |> Ash.reload!(authorize?: false)
      |> Ash.update!(%{}, action: :submit, actor: customer)

    Ash.create!(
      Payment,
      %{order_id: order.id, amount_cents: 500, method: :cash},
      action: :record,
      actor: staff
    )

    _other_order = Ash.create!(Order, %{}, actor: other_customer)

    %{staff: staff, customer: customer, product: product, variant: variant, order: order}
  end

  defp api_conn(actor) do
    signed_in =
      actor.__struct__
      |> Ash.Query.for_read(:sign_in_with_password, %{email: actor.email, password: @password})
      |> Ash.read_one!()

    build_conn()
    |> put_req_header("authorization", "Bearer #{signed_in.__metadata__.token}")
  end

  defp create_staff! do
    Ash.create!(
      User,
      %{
        name: "API Surface Staff",
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
        name: "API Surface Customer",
        email: unique_email("customer"),
        password: @password,
        password_confirmation: @password
      },
      action: :register
    )
    |> Ash.update!(%{}, action: :confirm, authorize?: false)
  end

  defp unique_email(prefix) do
    "surface-#{prefix}-#{System.unique_integer([:positive])}@example.com"
  end
end

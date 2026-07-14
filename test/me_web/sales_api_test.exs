defmodule MeWeb.SalesApiTest do
  use MeWeb.ConnCase, async: true

  alias Me.Accounts.{Customer, User}
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.StockMovement
  alias Me.Sales.Order

  @password "password123"

  test "customer order creation derives the customer from the bearer token" do
    customer = create_customer!()

    order =
      api_conn(customer)
      |> post(
        "/api/orders",
        Jason.encode!(%{data: %{type: "order", attributes: %{}}})
      )
      |> json_response(201)

    assert order["data"]["attributes"]["status"] == "draft"
  end

  test "cross-customer order probes return 404" do
    owner = create_customer!()
    other = create_customer!()
    order = Ash.create!(Order, %{}, actor: owner)

    response = api_conn(other) |> get("/api/orders/#{order.id}")

    assert json_response(response, 404)["errors"]
  end

  test "insufficient stock returns 422 and an illegal transition returns 409" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 1)
    order = create_order_with_line!(customer, variant, 2)

    oversell =
      api_conn(customer)
      |> patch_json_api("/api/orders/#{order.id}/submit", "order", order.id, %{})

    assert json_response(oversell, 422)["errors"]

    valid_order = create_order_with_line!(customer, variant, 1)
    submitted = Ash.update!(valid_order, %{}, action: :submit, actor: customer)
    fulfilled = Ash.update!(submitted, %{}, action: :fulfill, actor: staff)

    illegal =
      api_conn(customer)
      |> patch_json_api("/api/orders/#{fulfilled.id}/cancel", "order", fulfilled.id, %{})

    assert json_response(illegal, 409)["errors"]
  end

  test "staff can return a fulfilled order through JSON API" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2)
    order = create_order_with_line!(customer, variant, 1)

    fulfilled =
      order
      |> Ash.update!(%{}, action: :submit, actor: customer)
      |> Ash.update!(%{}, action: :fulfill, actor: staff)

    response =
      staff
      |> api_conn()
      |> patch_json_api(
        "/api/orders/#{fulfilled.id}/return",
        "order",
        fulfilled.id,
        %{return_reason: "Customer return"}
      )
      |> json_response(200)

    assert response["data"]["attributes"]["status"] == "returned"
    assert response["data"]["attributes"]["return_reason"] == "Customer return"
    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 2
  end

  test "staff confirms and allocates a preorder through JSON API" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2)

    preorder =
      Ash.create!(
        Order,
        %{customer_id: customer.id, order_kind: :preorder, sales_channel: :group_chat},
        actor: staff
      )

    _line =
      Ash.create!(
        Me.Sales.OrderLineItem,
        %{order_id: preorder.id, product_variant_id: variant.id, quantity: 2},
        action: :add_line_item,
        actor: staff
      )

    confirmed =
      staff
      |> api_conn()
      |> patch_json_api(
        "/api/orders/#{preorder.id}/confirm-preorder",
        "order",
        preorder.id,
        %{}
      )
      |> json_response(200)

    assert confirmed["data"]["attributes"]["fulfillment_status"] == "awaiting_stock"
    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 2

    allocated =
      staff
      |> api_conn()
      |> patch_json_api(
        "/api/orders/#{preorder.id}/allocate-stock",
        "order",
        preorder.id,
        %{}
      )
      |> json_response(200)

    assert allocated["data"]["attributes"]["fulfillment_status"] == "ready"
    assert Ash.reload!(variant, authorize?: false).reserved_quantity == 2
  end

  test "preorder API rejects out-of-order and repeated lifecycle requests without duplicating stock" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2)

    preorder =
      Ash.create!(
        Order,
        %{customer_id: customer.id, order_kind: :preorder, sales_channel: :group_chat},
        actor: staff
      )

    _line =
      Ash.create!(
        Me.Sales.OrderLineItem,
        %{order_id: preorder.id, product_variant_id: variant.id, quantity: 2},
        action: :add_line_item,
        actor: staff
      )

    allocate_before_confirmation =
      staff
      |> api_conn()
      |> patch_json_api(
        "/api/orders/#{preorder.id}/allocate-stock",
        "order",
        preorder.id,
        %{}
      )

    assert json_response(allocate_before_confirmation, 400)["errors"]
    assert Ash.reload!(variant, authorize?: false).reserved_quantity == 0

    confirm_path = "/api/orders/#{preorder.id}/confirm-preorder"

    assert staff
           |> api_conn()
           |> patch_json_api(confirm_path, "order", preorder.id, %{})
           |> json_response(200)

    assert staff
           |> api_conn()
           |> patch_json_api(confirm_path, "order", preorder.id, %{})
           |> json_response(409)

    fulfill_before_allocation =
      staff
      |> api_conn()
      |> patch_json_api("/api/orders/#{preorder.id}/fulfill", "order", preorder.id, %{})

    assert json_response(fulfill_before_allocation, 400)["errors"]
    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 2

    allocation_path = "/api/orders/#{preorder.id}/allocate-stock"

    assert staff
           |> api_conn()
           |> patch_json_api(allocation_path, "order", preorder.id, %{})
           |> json_response(200)

    assert staff
           |> api_conn()
           |> patch_json_api(allocation_path, "order", preorder.id, %{})
           |> json_response(400)

    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 2
    assert Ash.reload!(variant, authorize?: false).reserved_quantity == 2

    fulfill_path = "/api/orders/#{preorder.id}/fulfill"

    assert staff
           |> api_conn()
           |> patch_json_api(fulfill_path, "order", preorder.id, %{})
           |> json_response(200)

    assert staff
           |> api_conn()
           |> patch_json_api(fulfill_path, "order", preorder.id, %{})
           |> json_response(409)

    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 0
    assert Ash.reload!(variant, authorize?: false).reserved_quantity == 0
  end

  test "payment API rejects draft orders and repeated void requests" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 1)
    order = create_order_with_line!(customer, variant, 1)

    payment_attributes = %{amount_cents: 1_000, method: "cash"}

    draft_payment =
      staff
      |> api_conn()
      |> post_json_api(
        "/api/orders/#{order.id}/payments",
        "payment",
        payment_attributes
      )

    assert json_response(draft_payment, 400)["errors"]

    _submitted = Ash.update!(order, %{}, action: :submit, actor: customer)

    payment =
      staff
      |> api_conn()
      |> post_json_api(
        "/api/orders/#{order.id}/payments",
        "payment",
        payment_attributes
      )
      |> json_response(201)

    payment_id = payment["data"]["id"]
    void_path = "/api/payments/#{payment_id}/void"

    assert staff
           |> api_conn()
           |> patch_json_api(void_path, "payment", payment_id, %{})
           |> json_response(200)

    assert staff
           |> api_conn()
           |> patch_json_api(void_path, "payment", payment_id, %{})
           |> json_response(400)
  end

  defp create_order_with_line!(customer, variant, quantity) do
    order = Ash.create!(Order, %{}, actor: customer)

    _line =
      Ash.create!(
        Me.Sales.OrderLineItem,
        %{order_id: order.id, product_variant_id: variant.id, quantity: quantity},
        action: :add_line_item,
        actor: customer
      )

    Ash.reload!(order, authorize?: false)
  end

  defp create_stocked_variant!(staff, quantity) do
    product = Ash.create!(Product, %{name: "Sales API Product"}, actor: staff)

    variant =
      Ash.create!(
        ProductVariant,
        %{
          product_id: product.id,
          sku: "SALES-API-#{System.unique_integer([:positive])}",
          size: "M",
          color: "Blue",
          price_cents: 1_000
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

  defp api_conn(actor) do
    signed_in =
      actor.__struct__
      |> Ash.Query.for_read(:sign_in_with_password, %{email: actor.email, password: @password})
      |> Ash.read_one!()

    build_conn()
    |> put_req_header("authorization", "Bearer #{signed_in.__metadata__.token}")
    |> put_req_header("content-type", "application/vnd.api+json")
  end

  defp patch_json_api(conn, path, type, id, attributes) do
    patch(
      conn,
      path,
      Jason.encode!(%{data: %{type: type, id: id, attributes: attributes}})
    )
  end

  defp post_json_api(conn, path, type, attributes) do
    post(
      conn,
      path,
      Jason.encode!(%{data: %{type: type, attributes: attributes}})
    )
  end

  defp create_staff! do
    Ash.create!(
      User,
      %{
        name: "Sales API Staff",
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
        name: "Sales API Customer",
        email: unique_email("customer"),
        password: @password,
        password_confirmation: @password
      },
      action: :register
    )
    |> Ash.update!(%{}, action: :confirm, authorize?: false)
  end

  defp unique_email(prefix) do
    "sales-api-#{prefix}-#{System.unique_integer([:positive])}@example.com"
  end
end

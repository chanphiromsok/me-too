defmodule MeWeb.SalesApiTest do
  use MeWeb.ConnCase, async: true

  alias Me.Accounts.{Customer, User}
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.StockMovement
  alias Me.Sales.{Order, Payment}

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

  test "client references prevent duplicate orders after a retried request" do
    customer = create_customer!()
    external_reference = "mobile-order-#{System.unique_integer([:positive])}"
    attributes = %{external_reference: external_reference}

    first_response =
      customer
      |> api_conn()
      |> post_json_api("/api/orders", "order", attributes)

    assert json_response(first_response, 201)["data"]["attributes"]["external_reference"] ==
             external_reference

    retried_response =
      customer
      |> api_conn()
      |> post_json_api("/api/orders", "order", attributes)

    assert json_response(retried_response, 400)["errors"]

    orders = Ash.read!(Order, actor: customer)
    assert Enum.count(orders, &(&1.external_reference == external_reference)) == 1
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
    _payment = pay_in_full!(submitted, staff)
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

    submitted = Ash.update!(order, %{}, action: :submit, actor: customer)
    _payment = pay_in_full!(submitted, staff)
    fulfilled = Ash.update!(submitted, %{}, action: :fulfill, actor: staff)

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

  test "staff confirms a preorder with an initial payment and allocates stock" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2)

    preorder =
      Ash.create!(
        Order,
        %{
          customer_id: customer.id,
          order_kind: :preorder,
          payment_terms: :credit,
          sales_channel: :group_chat
        },
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
        %{
          initial_payment_amount_cents: 500,
          initial_payment_method: "cash",
          initial_payment_note: "Deposit received"
        }
      )
      |> json_response(200)

    assert confirmed["data"]["attributes"]["fulfillment_status"] == "awaiting_stock"
    assert confirmed["data"]["attributes"]["payment_state"] == "partially_paid"
    assert confirmed["data"]["attributes"]["paid_cents"] == 500
    assert confirmed["data"]["attributes"]["balance_cents"] == 1_500
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
        %{
          customer_id: customer.id,
          order_kind: :preorder,
          payment_terms: :credit,
          sales_channel: :group_chat
        },
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

    payment_reference = "mobile-payment-#{System.unique_integer([:positive])}"

    payment_attributes = %{
      amount_cents: 1_000,
      method: "cash",
      external_reference: payment_reference
    }

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

    retried_payment =
      staff
      |> api_conn()
      |> post_json_api(
        "/api/orders/#{order.id}/payments",
        "payment",
        payment_attributes
      )

    assert json_response(retried_payment, 400)["errors"]
    assert Enum.count(Ash.read!(Payment, authorize?: false)) == 1

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

  test "staff submits a credit sale with an initial partial payment" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2)

    order =
      Ash.create!(
        Order,
        %{customer_id: customer.id, payment_terms: :credit},
        actor: staff
      )

    _line =
      Ash.create!(
        Me.Sales.OrderLineItem,
        %{order_id: order.id, product_variant_id: variant.id, quantity: 2},
        action: :add_line_item,
        actor: staff
      )

    submitted =
      staff
      |> api_conn()
      |> patch_json_api("/api/orders/#{order.id}/submit", "order", order.id, %{
        initial_payment_amount_cents: 750,
        initial_payment_method: "bank_transfer",
        initial_payment_note: "Customer paid at checkout",
        initial_payment_external_reference: "bank-#{System.unique_integer([:positive])}"
      })
      |> json_response(200)

    assert submitted["data"]["attributes"]["status"] == "pending"
    assert submitted["data"]["attributes"]["payment_state"] == "partially_paid"
    assert submitted["data"]["attributes"]["paid_cents"] == 750
    assert submitted["data"]["attributes"]["balance_cents"] == 1_250

    assert [payment] = Ash.read!(Payment, authorize?: false)
    assert payment.amount_cents == 750
    assert payment.method == :bank_transfer
    assert payment.recorded_by_user_id == staff.id
  end

  test "an invalid initial payment rolls back order submission and stock" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 1)

    order =
      Ash.create!(
        Order,
        %{customer_id: customer.id, payment_terms: :credit},
        actor: staff
      )

    _line =
      Ash.create!(
        Me.Sales.OrderLineItem,
        %{order_id: order.id, product_variant_id: variant.id, quantity: 1},
        action: :add_line_item,
        actor: staff
      )

    missing_method =
      staff
      |> api_conn()
      |> patch_json_api("/api/orders/#{order.id}/submit", "order", order.id, %{
        initial_payment_amount_cents: 500
      })

    assert json_response(missing_method, 400)["errors"]
    assert Ash.reload!(order, authorize?: false).status == :draft
    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 1

    response =
      staff
      |> api_conn()
      |> patch_json_api("/api/orders/#{order.id}/submit", "order", order.id, %{
        initial_payment_amount_cents: 1_001,
        initial_payment_method: "cash"
      })

    assert json_response(response, 400)["errors"]
    assert Ash.reload!(order, authorize?: false).status == :draft
    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 1
    assert Ash.read!(Payment, authorize?: false) == []
  end

  test "a customer cannot record a manual initial payment" do
    customer = create_customer!()
    staff = create_staff!()
    variant = create_stocked_variant!(staff, 1)
    order = create_order_with_line!(customer, variant, 1)

    response =
      customer
      |> api_conn()
      |> patch_json_api("/api/orders/#{order.id}/submit", "order", order.id, %{
        initial_payment_amount_cents: 500,
        initial_payment_method: "cash"
      })

    assert json_response(response, 400)["errors"]
    assert Ash.reload!(order, authorize?: false).status == :draft
    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 1
    assert Ash.read!(Payment, authorize?: false) == []
  end

  test "staff records partial credit payments and reads the receivables report" do
    staff = create_staff!()
    customer = create_customer!()
    variant = create_stocked_variant!(staff, 2)

    order =
      Ash.create!(
        Order,
        %{customer_id: customer.id, payment_terms: :credit},
        actor: staff
      )

    _line =
      Ash.create!(
        Me.Sales.OrderLineItem,
        %{order_id: order.id, product_variant_id: variant.id, quantity: 2},
        action: :add_line_item,
        actor: staff
      )

    _submitted =
      order
      |> Ash.reload!(authorize?: false)
      |> Ash.update!(%{}, action: :submit, actor: staff)

    report =
      staff
      |> api_conn()
      |> get("/api/receivables")
      |> json_response(200)

    assert [%{"id" => order_id, "attributes" => attributes}] = report["data"]
    assert order_id == order.id
    assert attributes["total_cents"] == 2_000
    assert attributes["paid_cents"] == 0
    assert attributes["balance_cents"] == 2_000

    forbidden_report = customer |> api_conn() |> get("/api/receivables")
    assert json_response(forbidden_report, 403)["errors"]

    overpayment =
      staff
      |> api_conn()
      |> post_json_api("/api/orders/#{order.id}/payments", "payment", %{
        amount_cents: 2_001,
        method: "cash"
      })

    assert json_response(overpayment, 400)["errors"]

    payment =
      staff
      |> api_conn()
      |> post_json_api("/api/orders/#{order.id}/payments", "payment", %{
        amount_cents: 750,
        method: "bank_transfer",
        note: "Verified manually"
      })
      |> json_response(201)

    assert payment["data"]["attributes"]["amount_cents"] == 750

    [updated] =
      staff
      |> api_conn()
      |> get("/api/receivables")
      |> json_response(200)
      |> Map.fetch!("data")

    assert updated["attributes"]["paid_cents"] == 750
    assert updated["attributes"]["balance_cents"] == 1_250
  end

  test "a customer cannot grant credit to their own order" do
    customer = create_customer!()

    response =
      customer
      |> api_conn()
      |> post_json_api("/api/orders", "order", %{payment_terms: "credit"})

    assert json_response(response, 400)["errors"]
    assert Ash.read!(Order, actor: customer) == []
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

  defp pay_in_full!(order, staff) do
    loaded_order = Ash.load!(order, [:balance_cents], authorize?: false)

    Ash.create!(
      Payment,
      %{order_id: order.id, amount_cents: loaded_order.balance_cents, method: :cash},
      action: :record,
      actor: staff
    )
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

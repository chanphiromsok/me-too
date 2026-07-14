defmodule MeWeb.JsonApiRouterTest do
  use MeWeb.ConnCase, async: true

  alias Me.Accounts.{Customer, User}

  test "serves the OpenAPI document", %{conn: conn} do
    conn = get(conn, "/api/open-api")

    assert response(conn, 200) |> Jason.decode!() |> Map.fetch!("openapi")
  end

  test "serves the JSON schema", %{conn: conn} do
    conn = get(conn, "/api/json-schema")

    assert json_response(conn, 200)["$schema"]
  end

  test "serves Swagger UI", %{conn: conn} do
    conn = get(conn, "/api/swaggerui")

    assert html_response(conn, 200) =~ "Swagger UI"
  end

  test "customer registration stays pending until confirmed through the admin API", %{conn: conn} do
    email = "pending-#{System.unique_integer([:positive])}@example.com"

    conn =
      conn
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post(
        "/api/customers/register",
        Jason.encode!(%{
          data: %{
            type: "customer",
            attributes: %{
              name: "Pending Customer",
              email: email,
              customer_type: "retail",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        })
      )

    body = json_response(conn, 201)

    assert body["data"]["attributes"]["confirmed_at"] == nil
    refute get_in(body, ["meta", "token"])
    refute get_in(body, ["data", "meta", "token"])

    admin = create_admin!()

    confirmation =
      build_conn()
      |> put_req_header("authorization", "Bearer #{admin.__metadata__.token}")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> patch(
        "/api/customers/#{body["data"]["id"]}/confirm",
        Jason.encode!(%{
          data: %{
            id: body["data"]["id"],
            type: "customer",
            attributes: %{}
          }
        })
      )
      |> json_response(200)

    assert confirmation["data"]["attributes"]["confirmed_at"]
  end

  test "OpenAPI exposes the admin customer confirmation route", %{conn: conn} do
    document = conn |> get("/api/open-api") |> response(200) |> Jason.decode!()

    assert document["paths"]["/api/customers/{id}/confirm"]["patch"]
    assert document["paths"]["/api/staff/sign-in"]["post"]
    assert document["paths"]["/api/customers/sign-in"]["post"]
    assert document["paths"]["/api/customers/register"]["post"]
  end

  test "OpenAPI exposes credit payments and receivables routes", %{conn: conn} do
    document = conn |> get("/api/open-api") |> response(200) |> Jason.decode!()

    assert document["paths"]["/api/orders/{order_id}/payments"]["post"]
    assert document["paths"]["/api/payments/{id}/void"]["patch"]
    assert document["paths"]["/api/receivables"]["get"]
  end

  test "staff and customer sign-in use separate paths" do
    staff = create_admin!()
    customer = create_confirmed_customer!()

    staff_response =
      post_json_api("/api/staff/sign-in", "user", %{
        email: to_string(staff.email),
        password: "password123"
      })

    customer_response =
      post_json_api("/api/customers/sign-in", "customer", %{
        email: to_string(customer.email),
        password: "password123"
      })

    assert is_binary(staff_response["meta"]["token"])
    assert is_binary(customer_response["meta"]["token"])
  end

  defp create_admin! do
    Ash.create!(
      User,
      %{
        name: "API Test Admin",
        email: "admin-#{System.unique_integer([:positive])}@example.com",
        role: :admin,
        password: "password123",
        password_confirmation: "password123"
      },
      action: :register_with_password,
      authorize?: false
    )
  end

  defp create_confirmed_customer! do
    Customer
    |> Ash.create!(
      %{
        name: "API Test Customer",
        email: "customer-#{System.unique_integer([:positive])}@example.com",
        password: "password123",
        password_confirmation: "password123"
      },
      action: :register
    )
    |> Ash.update!(%{}, action: :confirm, authorize?: false)
  end

  defp post_json_api(path, type, attributes) do
    build_conn()
    |> put_req_header("content-type", "application/vnd.api+json")
    |> post(path, Jason.encode!(%{data: %{type: type, attributes: attributes}}))
    |> json_response(201)
  end
end

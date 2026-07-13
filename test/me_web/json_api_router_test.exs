defmodule MeWeb.JsonApiRouterTest do
  use MeWeb.ConnCase, async: true

  alias Me.Accounts.User

  test "serves the OpenAPI document", %{conn: conn} do
    conn = get(conn, "/api/json/open-api")

    assert response(conn, 200) |> Jason.decode!() |> Map.fetch!("openapi")
  end

  test "serves the JSON schema", %{conn: conn} do
    conn = get(conn, "/api/json/json-schema")

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
        "/api/json/customers/register",
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
        "/api/json/customers/#{body["data"]["id"]}/confirm",
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
    document = conn |> get("/api/json/open-api") |> response(200) |> Jason.decode!()

    assert document["paths"]["/api/json/customers/{id}/confirm"]["patch"]
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
end

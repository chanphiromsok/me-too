defmodule MeWeb.JsonApiRouterTest do
  use MeWeb.ConnCase, async: true

  test "serves the OpenAPI document", %{conn: conn} do
    conn = get(conn, "/api/json/open-api")

    assert response(conn, 200) |> Jason.decode!() |> Map.fetch!("openapi")
  end

  test "serves the JSON schema", %{conn: conn} do
    conn = get(conn, "/api/json/json-schema")

    assert json_response(conn, 200)["$schema"]
  end
end

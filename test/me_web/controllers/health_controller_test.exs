defmodule MeWeb.HealthControllerTest do
  use MeWeb.ConnCase

  test "GET /health", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end

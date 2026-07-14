defmodule MeWeb.HealthController do
  use MeWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end

defmodule MeWeb.PageController do
  use MeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

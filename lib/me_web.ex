defmodule MeWeb do
  @moduledoc """
  The entrypoint for defining the API's routers and controllers.

  This can be used in your application as:

      use MeWeb, :controller

  The definitions below will be executed for every router and controller,
  so keep them short and focused on imports, uses, and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: MeWeb.Endpoint,
        router: MeWeb.Router,
        statics: []
    end
  end

  @doc """
  When used, dispatch to the requested router, controller, or route helper.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

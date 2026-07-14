defmodule MeWeb.Router do
  use MeWeb, :router

  import MeWeb.AuthPlug

  pipeline :docs do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers
  end

  pipeline :dashboard do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug MeWeb.ApiActorPlug
    plug MeWeb.ApiPaginationPlug, max_page_size: 100
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  scope "/", MeWeb do
    pipe_through :health

    get "/health", HealthController, :show
  end

  scope "/api" do
    pipe_through :docs

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/open-api",
      default_model_expand_depth: 4,
      display_operation_id: true,
      persist_authorization: true
  end

  scope "/api" do
    pipe_through :api

    forward "/", MeWeb.AshJsonApiRouter
  end

  # Enable operational tools in development.
  if Application.compile_env(:me, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :dashboard

      live_dashboard "/dashboard", metrics: MeWeb.Telemetry
    end

    scope "/dev" do
      pipe_through :docs

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

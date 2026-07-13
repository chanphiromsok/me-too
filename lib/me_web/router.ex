defmodule MeWeb.Router do
  use MeWeb, :router

  import MeWeb.AuthPlug

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/api" do
    pipe_through :api

    forward "/json", MeWeb.JsonApiRouter
  end

  scope "/", MeWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api" do
    pipe_through :browser

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open-api",
      default_model_expand_depth: 4,
      display_operation_id: true,
      persist_authorization: true
  end

  # Other scopes may use custom stacks.
  # scope "/api", MeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:me, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

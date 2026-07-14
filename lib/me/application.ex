defmodule Me.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MeWeb.Telemetry,
      Me.Repo,
      {DNSCluster, query: Application.get_env(:me, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Me.PubSub},
      # Start a worker by calling: Me.Worker.start_link(arg)
      # {Me.Worker, arg},
      # Start to serve requests, typically the last entry
      MeWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :me]}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Me.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

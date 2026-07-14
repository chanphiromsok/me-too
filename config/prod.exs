import Config

# Force using SSL in production. Local Docker builds set FORCE_SSL=false at
# image build time so physical devices on the local network can use HTTP.
if System.get_env("FORCE_SSL", "true") in ~w(true 1) do
  config :me, MeWeb.Endpoint,
    force_ssl: [
      rewrite_on: [:x_forwarded_proto],
      exclude: [
        paths: ["/health"],
        hosts: ["localhost", "127.0.0.1"]
      ]
    ]
end

# Configure Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

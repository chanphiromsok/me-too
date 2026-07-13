defmodule MeWeb.JsonApiRouter do
  use AshJsonApi.Router,
    domains: [Me.Accounts],
    open_api: "/open-api",
    json_schema: "/json-schema",
    prefix: "/api"
end

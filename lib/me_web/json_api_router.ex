defmodule MeWeb.JsonApiRouter do
  use AshJsonApi.Router,
    domains: [Me.Accounts, Me.Catalog],
    open_api: "/open-api",
    json_schema: "/json-schema",
    prefix: "/api"
end

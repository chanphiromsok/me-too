defmodule MeWeb.ApiPaginationPlug do
  @moduledoc """
  Rejects JSON:API page sizes above the configured API-wide maximum.

  Ash enforces resource pagination when executing queries, while this plug
  gives clients an explicit JSON:API error instead of silently accepting an
  oversized HTTP page request.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts) do
    Keyword.fetch!(opts, :max_page_size)
  end

  @impl Plug
  def call(conn, max_page_size) do
    conn = fetch_query_params(conn)

    case conn.query_params do
      %{"page" => %{"limit" => limit}} -> validate_limit(conn, limit, max_page_size)
      _ -> conn
    end
  end

  defp validate_limit(conn, limit, max_page_size) do
    case Integer.parse(limit) do
      {parsed_limit, ""} when parsed_limit > max_page_size ->
        body =
          Jason.encode!(%{
            errors: [
              %{
                status: "400",
                code: "invalid_page_size",
                title: "Invalid Page Size",
                detail: "page[limit] cannot exceed #{max_page_size}.",
                source: %{parameter: "page[limit]"}
              }
            ],
            jsonapi: %{version: "1.0"}
          })

        conn
        |> put_resp_content_type("application/vnd.api+json")
        |> send_resp(:bad_request, body)
        |> halt()

      _ ->
        conn
    end
  end
end

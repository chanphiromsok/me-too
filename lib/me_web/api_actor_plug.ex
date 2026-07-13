defmodule MeWeb.ApiActorPlug do
  @moduledoc """
  Resolves the subjects loaded by AshAuthentication into the Ash API actor.

  Requests without an Authorization header remain anonymous. A supplied bearer
  token must resolve to exactly one supported authentication resource.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    authorization_headers = get_req_header(conn, "authorization")

    actors =
      [conn.assigns[:current_user], conn.assigns[:current_customer]]
      |> Enum.reject(&is_nil/1)

    case {authorization_headers, actors} do
      {[], []} ->
        Ash.PlugHelpers.set_actor(conn, nil)

      {["Bearer " <> token], [actor]} when byte_size(token) > 0 ->
        Ash.PlugHelpers.set_actor(conn, actor)

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    body =
      Jason.encode!(%{
        errors: [
          %{
            status: "401",
            code: "unauthorized",
            title: "Unauthorized",
            detail: "The bearer token is invalid, expired, or no longer authorized."
          }
        ],
        jsonapi: %{version: "1.0"}
      })

    conn
    |> put_resp_content_type("application/vnd.api+json")
    |> send_resp(:unauthorized, body)
    |> halt()
  end
end

defmodule MeWeb.ApiActorPlugTest do
  use MeWeb.ConnCase, async: true

  alias AshAuthentication.Jwt
  alias Me.Accounts.{Customer, User}

  @password "password123"

  test "a staff token sets the User as the Ash actor" do
    staff = create_user!()

    conn = authenticate(staff.__metadata__.token)

    assert %User{id: id} = Ash.PlugHelpers.get_actor(conn)
    assert id == staff.id
    refute conn.halted
  end

  test "a customer token sets the Customer as the Ash actor" do
    customer = create_confirmed_customer!()
    signed_in = sign_in!(Customer, customer.email)

    conn = authenticate(signed_in.__metadata__.token)

    assert %Customer{id: id} = Ash.PlugHelpers.get_actor(conn)
    assert id == customer.id
    refute conn.halted
  end

  test "a request without an Authorization header remains anonymous" do
    conn = authenticate(nil)

    assert is_nil(Ash.PlugHelpers.get_actor(conn))
    refute conn.halted
  end

  test "a tampered bearer token returns a JSON:API 401", %{conn: conn} do
    token = create_user!().__metadata__.token <> "tampered"

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/open-api")

    assert_json_api_unauthorized(response)
  end

  test "an expired bearer token returns a JSON:API 401", %{conn: conn} do
    staff = create_user!()
    {:ok, token, _claims} = Jwt.token_for_user(staff, %{}, token_lifetime: {0, :seconds})

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/open-api")

    assert_json_api_unauthorized(response)
  end

  test "an existing staff token is rejected after deactivation", %{conn: conn} do
    staff = create_user!()
    token = staff.__metadata__.token
    Ash.update!(staff, %{}, action: :deactivate, authorize?: false)

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/open-api")

    assert_json_api_unauthorized(response)
  end

  defp authenticate(nil) do
    build_conn()
    |> MeWeb.AuthPlug.load_from_bearer([])
    |> MeWeb.ApiActorPlug.call([])
  end

  defp authenticate(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> MeWeb.AuthPlug.load_from_bearer([])
    |> MeWeb.ApiActorPlug.call([])
  end

  defp create_user! do
    Ash.create!(
      User,
      %{
        name: "Actor Test Staff",
        email: unique_email("staff"),
        password: @password,
        password_confirmation: @password
      },
      action: :register_with_password,
      authorize?: false
    )
  end

  defp create_confirmed_customer! do
    Customer
    |> Ash.create!(
      %{
        name: "Actor Test Customer",
        email: unique_email("customer"),
        password: @password,
        password_confirmation: @password
      },
      action: :register
    )
    |> Ash.update!(%{}, action: :confirm, authorize?: false)
  end

  defp sign_in!(resource, email) do
    resource
    |> Ash.Query.for_read(:sign_in_with_password, %{email: email, password: @password})
    |> Ash.read_one!()
  end

  defp assert_json_api_unauthorized(conn) do
    body = json_response(conn, 401)

    assert get_resp_header(conn, "content-type") == ["application/vnd.api+json; charset=utf-8"]
    assert [%{"status" => "401", "code" => "unauthorized"}] = body["errors"]
  end

  defp unique_email(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}@example.com"
  end
end

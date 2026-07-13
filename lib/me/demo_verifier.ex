defmodule Me.DemoVerifier do
  @moduledoc """
  Runs the documented demo flows against a running JSON:API server.
  """

  @password "password123"
  @json_api "application/vnd.api+json"

  def run(base_url \\ "http://localhost:4000/api") do
    base_url = String.trim_trailing(base_url, "/")
    suffix = System.unique_integer([:positive])

    admin_token = sign_in(base_url, "/staff/sign-in", "user", "admin@example.com")
    staff_token = sign_in(base_url, "/staff/sign-in", "user", "staff@example.com")

    customer = customer_self_service(base_url, admin_token, suffix)
    staff_phone_order(base_url, staff_token, suffix)
    restock_day(base_url, staff_token)
    oversell_check(base_url, staff_token, customer, suffix)

    :ok
  end

  defp customer_self_service(base_url, admin_token, suffix) do
    email = "verify-customer-#{suffix}@example.com"

    registration =
      request!(base_url, :post, "/customers/register", 201,
        type: "customer",
        attributes: %{
          name: "Verification Customer",
          email: email,
          customer_type: "retail",
          password: @password,
          password_confirmation: @password
        }
      )

    customer_id = data_id(registration)

    request!(base_url, :patch, "/customers/#{customer_id}/confirm", 200,
      token: admin_token,
      type: "customer",
      id: customer_id,
      attributes: %{}
    )

    token = sign_in(base_url, "/customers/sign-in", "customer", email)
    variants = request!(base_url, :get, "/product-variants?page[limit]=1", 200)
    variant_id = variants |> Map.fetch!("data") |> List.first() |> Map.fetch!("id")

    order =
      request!(base_url, :post, "/orders", 201,
        token: token,
        type: "order",
        attributes: %{}
      )

    order_id = data_id(order)

    request!(base_url, :post, "/orders/#{order_id}/line-items", 201,
      token: token,
      type: "order_line_item",
      attributes: %{product_variant_id: variant_id, quantity: 1}
    )

    request!(base_url, :patch, "/orders/#{order_id}/submit", 200,
      token: token,
      type: "order",
      id: order_id,
      attributes: %{}
    )

    invoice =
      request!(
        base_url,
        :get,
        "/orders/#{order_id}?include=line_items.product_variant,payments",
        200,
        token: token
      )

    assert_equal!(get_in(invoice, ["data", "attributes", "status"]), "pending", "invoice")
    report("customer self-service")

    %{id: customer_id, token: token}
  end

  defp staff_phone_order(base_url, staff_token, suffix) do
    customer =
      request!(base_url, :post, "/customers/staff", 201,
        token: staff_token,
        type: "customer",
        attributes: %{
          name: "Phone Order Customer",
          phone: "+855 10 #{suffix}",
          customer_type: "retail"
        }
      )

    customer_id = data_id(customer)
    variants = request!(base_url, :get, "/product-variants?page[limit]=1", 200)
    variant = variants |> Map.fetch!("data") |> List.first()
    variant_id = Map.fetch!(variant, "id")
    price_cents = get_in(variant, ["attributes", "price_cents"])

    order =
      request!(base_url, :post, "/orders", 201,
        token: staff_token,
        type: "order",
        attributes: %{customer_id: customer_id}
      )

    order_id = data_id(order)

    request!(base_url, :post, "/orders/#{order_id}/line-items", 201,
      token: staff_token,
      type: "order_line_item",
      attributes: %{product_variant_id: variant_id, quantity: 1}
    )

    request!(base_url, :patch, "/orders/#{order_id}/submit", 200,
      token: staff_token,
      type: "order",
      id: order_id,
      attributes: %{}
    )

    request!(base_url, :post, "/orders/#{order_id}/payments", 201,
      token: staff_token,
      type: "payment",
      attributes: %{amount_cents: price_cents, method: "cash", note: "Paid at pickup"}
    )

    fulfilled =
      request!(base_url, :patch, "/orders/#{order_id}/fulfill", 200,
        token: staff_token,
        type: "order",
        id: order_id,
        attributes: %{}
      )

    assert_equal!(get_in(fulfilled, ["data", "attributes", "status"]), "fulfilled", "phone order")
    report("staff phone order")
  end

  defp restock_day(base_url, staff_token) do
    variants = request!(base_url, :get, "/product-variants?filter[sku]=CCT-2T-SKY", 200)
    variant_id = variants |> Map.fetch!("data") |> List.first() |> Map.fetch!("id")

    movement =
      request!(base_url, :post, "/product-variants/#{variant_id}/restock", 201,
        token: staff_token,
        type: "stock_movement",
        attributes: %{quantity: 5, note: "Verification restock day"}
      )

    assert_equal!(get_in(movement, ["data", "attributes", "delta"]), 5, "restock")
    report("restock day")
  end

  defp oversell_check(base_url, staff_token, customer, suffix) do
    product =
      request!(base_url, :post, "/products", 201,
        token: staff_token,
        type: "product",
        attributes: %{name: "Last Unit Verification #{suffix}", category: "Verification"}
      )

    variant =
      request!(base_url, :post, "/product-variants", 201,
        token: staff_token,
        type: "product_variant",
        attributes: %{
          product_id: data_id(product),
          sku: "LAST-UNIT-#{suffix}",
          size: "4T",
          color: "Black",
          price_cents: 1_000
        }
      )

    variant_id = data_id(variant)

    request!(base_url, :post, "/product-variants/#{variant_id}/restock", 201,
      token: staff_token,
      type: "stock_movement",
      attributes: %{quantity: 1, note: "Oversell verification"}
    )

    order_ids =
      Enum.map(1..2, fn _index ->
        order =
          request!(base_url, :post, "/orders", 201,
            token: customer.token,
            type: "order",
            attributes: %{}
          )

        order_id = data_id(order)

        request!(base_url, :post, "/orders/#{order_id}/line-items", 201,
          token: customer.token,
          type: "order_line_item",
          attributes: %{product_variant_id: variant_id, quantity: 1}
        )

        order_id
      end)

    statuses =
      order_ids
      |> Task.async_stream(
        fn order_id ->
          request_status(base_url, :patch, "/orders/#{order_id}/submit",
            token: customer.token,
            type: "order",
            id: order_id,
            attributes: %{}
          )
        end,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn {:ok, status} -> status end)
      |> Enum.sort()

    assert_equal!(statuses, [200, 422], "concurrent oversell")
    report("concurrent oversell")
  end

  defp sign_in(base_url, path, type, email) do
    response =
      request!(base_url, :post, path, 201,
        type: type,
        attributes: %{email: email, password: @password}
      )

    Map.fetch!(response, "meta") |> Map.fetch!("token")
  end

  defp request!(base_url, method, path, expected_status, opts \\ []) do
    response = request(base_url, method, path, opts)

    if response.status != expected_status do
      raise "#{method |> Atom.to_string() |> String.upcase()} #{path} returned #{response.status}, expected #{expected_status}: #{inspect(response.body)}"
    end

    response.body
  end

  defp request_status(base_url, method, path, opts) do
    request(base_url, method, path, opts).status
  end

  defp request(base_url, method, path, opts) do
    token = Keyword.get(opts, :token)
    headers = [{"accept", @json_api}] ++ authorization_header(token)

    request_options = [method: method, url: base_url <> path, headers: headers, retry: false]

    request_options =
      if type = Keyword.get(opts, :type) do
        body = %{
          data: %{
            type: type,
            attributes: Keyword.fetch!(opts, :attributes)
          }
        }

        body =
          case Keyword.get(opts, :id) do
            nil -> body
            id -> put_in(body, [:data, :id], id)
          end

        Keyword.merge(request_options,
          json: body,
          headers: [{"content-type", @json_api} | headers]
        )
      else
        request_options
      end

    case Req.request(request_options) do
      {:ok, response} -> response
      {:error, error} -> raise "request failed for #{path}: #{Exception.message(error)}"
    end
  end

  defp authorization_header(nil), do: []
  defp authorization_header(token), do: [{"authorization", "Bearer #{token}"}]

  defp data_id(response), do: response |> Map.fetch!("data") |> Map.fetch!("id")

  defp assert_equal!(actual, expected, _flow) when actual == expected, do: :ok

  defp assert_equal!(actual, expected, flow) do
    raise "#{flow} verification failed: expected #{inspect(expected)}, got #{inspect(actual)}"
  end

  defp report(flow), do: IO.puts("✓ #{flow}")
end

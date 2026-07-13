defmodule MeWeb.CatalogApiTest do
  use MeWeb.ConnCase, async: true

  alias Me.Accounts.User
  alias Me.Catalog.Product

  @password "password123"

  test "duplicate product size and color returns a JSON:API 409" do
    staff = create_staff!()
    product = Ash.create!(Product, %{name: "Kids T-shirt"}, actor: staff)

    first = create_variant_request(staff, product, "SKU-ONE")
    duplicate = create_variant_request(staff, product, "SKU-TWO")

    assert json_response(first, 201)["data"]["id"]

    assert [%{"status" => "409"}] =
             duplicate
             |> json_response(409)
             |> Map.fetch!("errors")
  end

  test "variant PATCH rejects quantity_on_hand" do
    staff = create_staff!()
    product = Ash.create!(Product, %{name: "Kids T-shirt"}, actor: staff)
    created = create_variant_request(staff, product, "SKU-PATCH") |> json_response(201)

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{staff.__metadata__.token}")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> patch(
        "/api/product-variants/#{created["data"]["id"]}",
        Jason.encode!(%{
          data: %{
            id: created["data"]["id"],
            type: "product_variant",
            attributes: %{quantity_on_hand: 50}
          }
        })
      )

    assert json_response(response, 400)["errors"]
  end

  defp create_variant_request(staff, product, sku) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{staff.__metadata__.token}")
    |> put_req_header("content-type", "application/vnd.api+json")
    |> post(
      "/api/product-variants",
      Jason.encode!(%{
        data: %{
          type: "product_variant",
          attributes: %{
            product_id: product.id,
            sku: sku,
            size: "3T",
            color: "Blue",
            price_cents: 1_299
          }
        }
      })
    )
  end

  defp create_staff! do
    Ash.create!(
      User,
      %{
        name: "Catalog API Staff",
        email: "catalog-api-#{System.unique_integer([:positive])}@example.com",
        password: @password,
        password_confirmation: @password
      },
      action: :register_with_password,
      authorize?: false
    )
  end
end

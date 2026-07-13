defmodule Me.Seeds do
  @moduledoc false

  require Ash.Query

  alias Me.Accounts.{Customer, User}
  alias Me.Catalog.{Product, ProductVariant}
  alias Me.Inventory.StockMovement

  @password "password123"

  @products [
    {"Classic Cotton Tee", "Soft everyday cotton jersey.", "Tops",
     [
       {"CCT-2T-SKY", "2T", "Sky Blue", 1_200, 14},
       {"CCT-4T-SKY", "4T", "Sky Blue", 1_300, 12},
       {"CCT-6T-CORAL", "6T", "Coral", 1_400, 10}
     ]},
    {"Playground Shorts", "Easy pull-on shorts for active days.", "Bottoms",
     [
       {"PGS-2T-NAVY", "2T", "Navy", 1_500, 11},
       {"PGS-3T-SAND", "3T", "Sand", 1_500, 9},
       {"PGS-5T-NAVY", "5T", "Navy", 1_650, 8}
     ]},
    {"Weekend Dress", "Lightweight dress with a relaxed fit.", "Dresses",
     [
       {"WKD-3T-LILAC", "3T", "Lilac", 2_400, 8},
       {"WKD-4T-ROSE", "4T", "Rose", 2_400, 10},
       {"WKD-6T-LILAC", "6T", "Lilac", 2_600, 7}
     ]},
    {"Cozy Zip Hoodie", "Midweight layer with a soft brushed inside.", "Outerwear",
     [
       {"CZH-2T-SAGE", "2T", "Sage", 2_800, 7},
       {"CZH-4T-GREY", "4T", "Grey", 3_000, 9},
       {"CZH-6T-SAGE", "6T", "Sage", 3_200, 6}
     ]},
    {"Everyday Pajama Set", "Breathable two-piece sleep set.", "Sleepwear",
     [
       {"EPS-3T-MINT", "3T", "Mint", 2_100, 12},
       {"EPS-5T-MINT", "5T", "Mint", 2_300, 10},
       {"EPS-6T-PLUM", "6T", "Plum", 2_300, 8}
     ]}
  ]

  def run do
    admin = seed_user("Demo Admin", "admin@example.com", :admin, nil)
    staff = seed_user("Demo Staff", "staff@example.com", :staff, admin)

    seed_registered_customer("Sophea Retail", "sophea@example.com", :retail, admin)
    seed_registered_customer("Dara Retail", "dara@example.com", :retail, admin)

    seed_wholesale_customer(
      "Malis Shop",
      "orders@malis-shop.example.com",
      "Malis Kids Shop",
      admin
    )

    seed_wholesale_customer(
      "Sovann Boutique",
      "buying@sovann-boutique.example.com",
      "Sovann Boutique",
      staff
    )

    Enum.each(@products, &seed_product(&1, staff))

    IO.puts("Seeded demo users, customers, catalog, and stock ledger.")
    IO.puts("Demo password: #{@password} (admin@example.com / staff@example.com)")
  end

  defp seed_user(name, email, role, actor) do
    find_one(User, email: email) ||
      Ash.create!(
        User,
        %{
          name: name,
          email: email,
          role: role,
          password: @password,
          password_confirmation: @password
        },
        action: :register_with_password,
        actor: actor,
        authorize?: not is_nil(actor)
      )
  end

  defp seed_registered_customer(name, email, customer_type, admin) do
    customer =
      find_one(Customer, email: email) ||
        Ash.create!(
          Customer,
          %{
            name: name,
            email: email,
            customer_type: customer_type,
            password: @password,
            password_confirmation: @password
          },
          action: :register
        )

    if customer.confirmed_at do
      customer
    else
      Ash.update!(customer, %{}, action: :confirm, actor: admin)
    end
  end

  defp seed_wholesale_customer(name, email, business_name, staff) do
    find_one(Customer, email: email) ||
      Ash.create!(
        Customer,
        %{
          name: name,
          email: email,
          phone: "+855 12 000 000",
          customer_type: :wholesale,
          business_name: business_name
        },
        action: :create_by_staff,
        actor: staff
      )
  end

  defp seed_product({name, description, category, variants}, staff) do
    product =
      find_one(Product, name: name) ||
        Ash.create!(
          Product,
          %{name: name, description: description, category: category},
          actor: staff
        )

    Enum.each(variants, fn {sku, size, color, price_cents, opening_stock} ->
      unless find_one(ProductVariant, sku: sku) do
        variant =
          Ash.create!(
            ProductVariant,
            %{
              product_id: product.id,
              sku: sku,
              size: size,
              color: color,
              price_cents: price_cents,
              barcode: "885#{String.pad_leading(Integer.to_string(:erlang.phash2(sku)), 9, "0")}"
            },
            actor: staff
          )

        Ash.create!(
          StockMovement,
          %{
            product_variant_id: variant.id,
            quantity: opening_stock,
            note: "Opening stock"
          },
          action: :restock,
          actor: staff
        )
      end
    end)
  end

  defp find_one(resource, filters) do
    resource
    |> Ash.Query.filter(^filters)
    |> Ash.read_one!(authorize?: false)
  end
end

Me.Seeds.run()

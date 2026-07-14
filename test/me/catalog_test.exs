defmodule Me.CatalogTest do
  use Me.DataCase, async: true

  alias Me.Accounts.User
  alias Me.Catalog.{Product, ProductVariant}

  @password "password123"

  test "a product can have six independently tracked size and color variants" do
    staff = create_user!()
    product = create_product!(staff)

    variants =
      for size <- ["2T", "3T", "4T"], color <- ["Red", "Blue"] do
        create_variant!(product, staff, size, color)
      end

    assert length(variants) == 6
    assert variants |> Enum.map(& &1.sku) |> Enum.uniq() |> length() == 6
    assert Enum.all?(variants, &(&1.quantity_on_hand == 0))
  end

  test "duplicate product, size, and color combinations are rejected" do
    staff = create_user!()
    product = create_product!(staff)

    _variant = create_variant!(product, staff, "3T", "Blue")

    assert {:error, %Ash.Error.Invalid{}} =
             create_variant(product, staff, "3T", "Blue", sku: unique_sku())
  end

  test "SKUs are globally unique across products" do
    staff = create_user!()
    first_product = create_product!(staff)

    second_product =
      Ash.create!(Product, %{name: "Kids Shorts", category: "Kids"}, actor: staff)

    sku = unique_sku()
    _variant = create_variant!(first_product, staff, "3T", "Blue", sku: sku)

    assert {:error, %Ash.Error.Invalid{}} =
             create_variant(second_product, staff, "4T", "Red", sku: sku)
  end

  test "variant updates cannot write quantity_on_hand" do
    staff = create_user!()
    product = create_product!(staff)
    variant = create_variant!(product, staff, "4T", "Red")

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(variant, %{quantity_on_hand: 99}, actor: staff)

    assert Ash.reload!(variant, authorize?: false).quantity_on_hand == 0
  end

  test "the database constraint rejects negative stock" do
    staff = create_user!()
    product = create_product!(staff)

    variant = create_variant!(product, staff, "2T", "Black")

    assert {:error, error} =
             Ash.update(
               variant,
               %{quantity_on_hand: -1},
               action: :set_quantity_on_hand,
               authorize?: false
             )

    assert Exception.message(error) =~ "quantity_on_hand_non_negative"
  end

  test "the database constraint rejects reservations greater than physical stock" do
    staff = create_user!()
    product = create_product!(staff)
    variant = create_variant!(product, staff, "2T", "Navy")

    assert {:error, error} =
             Ash.update(
               variant,
               %{reserved_quantity: 1},
               action: :set_reserved_quantity,
               authorize?: false
             )

    assert Exception.message(error) =~ "cannot exceed quantity on hand"
  end

  test "public reads hide archived products and their variants from non-staff" do
    admin = create_user!(role: :admin)
    staff = create_user!()
    product = create_product!(staff)
    variant = create_variant!(product, staff, "2T", "Green")

    assert {:ok, archived} = Ash.update(product, %{}, action: :archive, actor: admin)

    public_products = Ash.read!(Product)
    public_variants = Ash.read!(ProductVariant)
    staff_products = Ash.read!(Product, actor: staff)
    staff_variants = Ash.read!(ProductVariant, actor: staff)

    refute Enum.any?(public_products, &(&1.id == archived.id))
    refute Enum.any?(public_variants, &(&1.id == variant.id))
    assert Enum.any?(staff_products, &(&1.id == archived.id))
    assert Enum.any?(staff_variants, &(&1.id == variant.id))
  end

  test "active staff can write products but only admins can archive" do
    staff = create_user!()
    admin = create_user!(role: :admin)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(Product, %{name: "Unauthorized"})

    product = create_product!(staff)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(product, %{}, action: :archive, actor: staff)

    assert {:ok, archived} = Ash.update(product, %{}, action: :archive, actor: admin)
    assert archived.status == :archived
  end

  defp create_product!(actor) do
    Ash.create!(
      Product,
      %{name: "Kids T-shirt", description: "Soft cotton tee", category: "Kids"},
      actor: actor
    )
  end

  defp create_variant!(product, actor, size, color, opts \\ []) do
    {:ok, variant} = create_variant(product, actor, size, color, opts)
    variant
  end

  defp create_variant(product, actor, size, color, opts) do
    attrs =
      %{
        product_id: product.id,
        sku: unique_sku(),
        size: size,
        color: color,
        price_cents: 1_299
      }
      |> Map.merge(Map.new(opts))

    Ash.create(ProductVariant, attrs, actor: actor)
  end

  defp create_user!(opts \\ []) do
    role = Keyword.get(opts, :role, :staff)

    Ash.create!(
      User,
      %{
        name: "Catalog Test #{role}",
        email: "catalog-#{role}-#{System.unique_integer([:positive])}@example.com",
        role: role,
        password: @password,
        password_confirmation: @password
      },
      action: :register_with_password,
      authorize?: false
    )
  end

  defp unique_sku do
    "SKU-#{System.unique_integer([:positive])}"
  end
end

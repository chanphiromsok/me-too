defmodule Me.Repo.Migrations.EnforceMoneyInvariants do
  use Ecto.Migration

  def change do
    create constraint(:product_variants, :product_variant_price_non_negative,
             check: "price_cents >= 0"
           )

    create constraint(:orders, :order_subtotal_non_negative, check: "subtotal_cents >= 0")

    create constraint(:orders, :order_discount_not_greater_than_subtotal,
             check: "discount_cents >= 0 AND discount_cents <= subtotal_cents"
           )

    create constraint(:order_line_items, :order_line_item_unit_price_non_negative,
             check: "unit_price_cents >= 0"
           )

    create constraint(:payments, :payment_amount_positive, check: "amount_cents > 0")
  end
end

defmodule Me.Inventory do
  use Ash.Domain,
    otp_app: :me,
    extensions: [AshJsonApi.Domain]

  json_api do
    routes do
      base_route "/product-variants", Me.Inventory.StockMovement do
        post :restock, route: "/:product_variant_id/restock"
        post :adjust, route: "/:product_variant_id/adjust"

        index :for_variant,
          route: "/:product_variant_id/stock-movements"
      end
    end
  end

  resources do
    resource Me.Inventory.StockMovement
  end
end

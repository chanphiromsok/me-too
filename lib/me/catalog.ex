defmodule Me.Catalog do
  use Ash.Domain,
    otp_app: :me,
    extensions: [AshJsonApi.Domain]

  json_api do
    error_handler {Me.JsonApiErrorHandler, :handle_error, []}

    routes do
      base_route "/products", Me.Catalog.Product do
        index :api_index
        get :read
        post :create
        patch :update
        patch :archive, route: "/:id/archive"
      end

      base_route "/product-variants", Me.Catalog.ProductVariant do
        index :api_index
        get :read
        post :create
        patch :update
      end
    end
  end

  resources do
    resource Me.Catalog.Product
    resource Me.Catalog.ProductVariant
  end
end

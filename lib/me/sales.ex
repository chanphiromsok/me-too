defmodule Me.Sales do
  use Ash.Domain,
    otp_app: :me,
    extensions: [AshJsonApi.Domain]

  json_api do
    error_handler {Me.JsonApiErrorHandler, :handle_error, []}

    routes do
      base_route "/orders", Me.Sales.Order do
        index :read
        get :read
        post :create
        patch :submit, route: "/:id/submit"
        patch :fulfill, route: "/:id/fulfill"
        patch :cancel, route: "/:id/cancel"
        patch :set_discount, route: "/:id/discount"
      end

      base_route "/orders", Me.Sales.OrderLineItem do
        post :add_line_item, route: "/:order_id/line-items", upsert?: true
        patch :edit, route: "/:order_id/line-items/:id"
        delete :remove, route: "/:order_id/line-items/:id"
      end

      base_route "/orders", Me.Sales.Payment do
        post :record, route: "/:order_id/payments"
      end

      base_route "/payments", Me.Sales.Payment do
        patch :void, route: "/:id/void"
      end
    end
  end

  resources do
    resource Me.Sales.Order
    resource Me.Sales.OrderLineItem
    resource Me.Sales.Payment
  end
end

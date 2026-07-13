defmodule Me.Accounts do
  use Ash.Domain,
    otp_app: :me,
    extensions: [AshJsonApi.Domain]

  json_api do
    routes do
      base_route "/staff", Me.Accounts.User do
        post :sign_in_with_password,
          route: "/sign-in",
          metadata: fn _subject, user, _request ->
            %{token: user.__metadata__.token}
          end
      end

      base_route "/customers", Me.Accounts.Customer do
        post :register, route: "/register"

        post :sign_in_with_password,
          route: "/sign-in",
          metadata: fn _subject, customer, _request ->
            %{token: customer.__metadata__.token}
          end

        post :create_by_staff, route: "/staff"

        patch :confirm, route: "/:id/confirm"
      end
    end
  end

  resources do
    resource Me.Accounts.Token
    resource Me.Accounts.User
    resource Me.Accounts.Customer
  end
end

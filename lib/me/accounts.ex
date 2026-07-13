defmodule Me.Accounts do
  use Ash.Domain,
    otp_app: :me,
    extensions: [AshJsonApi.Domain]

  json_api do
    routes do
      base_route "/users", Me.Accounts.User do
        post :register_with_password,
          route: "/register",
          metadata: fn _subject, user, _request ->
            %{token: user.__metadata__.token}
          end

        post :sign_in_with_password,
          route: "/sign-in",
          metadata: fn _subject, user, _request ->
            %{token: user.__metadata__.token}
          end
      end
    end
  end

  resources do
    resource Me.Accounts.Token
    resource Me.Accounts.User
  end
end

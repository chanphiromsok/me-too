defmodule Me.Accounts do
  use Ash.Domain,
    otp_app: :me

  resources do
    resource Me.Accounts.Token
    resource Me.Accounts.User
  end
end

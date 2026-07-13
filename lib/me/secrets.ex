defmodule Me.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        resource,
        _opts,
        _context
      )
      when resource in [Me.Accounts.User, Me.Accounts.Customer] do
    Application.fetch_env(:me, :token_signing_secret)
  end
end

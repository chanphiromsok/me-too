defmodule Me.Repo do
  use Ecto.Repo,
    otp_app: :me,
    adapter: Ecto.Adapters.Postgres
end

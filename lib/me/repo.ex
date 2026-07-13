defmodule Me.Repo do
  use AshPostgres.Repo,
    otp_app: :me,
    warn_on_missing_ash_functions?: false

  @impl true
  def min_pg_version, do: %Version{major: 15, minor: 0, patch: 0}

  @impl true
  def installed_extensions, do: ["citext", "ash-functions"]

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end
end

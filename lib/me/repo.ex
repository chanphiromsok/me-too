defmodule Me.Repo do
  use AshPostgres.Repo,
    otp_app: :me,
    warn_on_missing_ash_functions?: false

  def min_pg_version, do: %Version{major: 15, minor: 0, patch: 0}

  def installed_extensions, do: ["citext"]
end

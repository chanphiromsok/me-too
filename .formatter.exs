[
  import_deps: [
    :ash_state_machine,
    :ash_json_api,
    :ash_postgres,
    :ash,
    :reactor,
    :ash_authentication,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"]
]

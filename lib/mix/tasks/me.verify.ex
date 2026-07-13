defmodule Mix.Tasks.Me.Verify do
  use Mix.Task

  @shortdoc "Runs the demo API flows against a development server"

  @moduledoc """
  Runs customer self-service, staff phone order, restock day, and concurrent
  oversell verification against a running server.

      mix me.verify
      mix me.verify --base-url http://localhost:4000/api
  """

  @impl Mix.Task
  def run(args) do
    {options, [], []} = OptionParser.parse(args, strict: [base_url: :string])
    base_url = Keyword.get(options, :base_url, "http://localhost:4000/api")

    Mix.Task.run("app.start")
    Me.DemoVerifier.run(base_url)
    Mix.shell().info("All demo API flows passed.")
  end
end

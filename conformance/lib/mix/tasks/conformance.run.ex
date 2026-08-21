defmodule Mix.Tasks.Conformance.Run do
  @shortdoc "Run a conformance leg and write a provenance manifest beside its artefacts"

  @moduledoc """
  Run one conformance leg, capturing run-level provenance the harness does not
  record.

      mix conformance.run --leg server
      mix conformance.run --leg client -o /tmp/mes56/client-run

  ## Options

    * `--leg` — `server` or `client` (required)
    * `-o`, `--out-dir` — run directory. Defaults under
      `/tmp/mcp-conformance-runs/`, i.e. **outside the repository**, so the run
      cannot dirty the tree it is measuring.
    * `--adapter` — `sdk` (default) or `null`. `null` substitutes the
      do-nothing control at `conformance/controls/null_server.py`, so the run
      measures what a server with no implementation earns from the same suite.
      Server leg only.
    * `--cwd` — directory the harness and adapter run in. Defaults to the
      project root; pointing it elsewhere reproduces the wrong-cwd control.
    * `--harness-dir` — npm install root holding
      `node_modules/@modelcontextprotocol/conformance` (default `/tmp/conf11`)
    * `--requirements` — frozen requirement-set revision (default `2026-07-28`)
    * `--port` — port for the server leg's adapter (default `3001`)

  Writing the manifest is not the same as being allowed to quote the run.
  `mix conformance.adjudicate` decides that.
  """

  use Mix.Task

  alias MCP.Conformance.Argv

  @switches [
    leg: :string,
    adapter: :string,
    out_dir: :string,
    cwd: :string,
    harness_dir: :string,
    requirements: :string,
    port: :integer
  ]

  @aliases [o: :out_dir]

  @usage "mix conformance.run --leg server|client [--adapter sdk|null] [-o RUN_DIR] [--cwd DIR]"

  @impl Mix.Task
  def run(argv) do
    # Rejected here, before compile / beacon pre-flight / adapter launch — a
    # misspelled `--cwd` would otherwise make the wrong-cwd positive control run
    # correctly, and a control that silently did not fire is the failure this
    # ticket exists to stop. Same class as the adjudicator's: see
    # `MCP.Conformance.Argv`, which states it once for both tasks.
    {opts, _args} =
      Argv.parse!("conformance.run", argv,
        strict: @switches,
        aliases: @aliases,
        positional: 0,
        usage: @usage
      )

    leg =
      case opts[:leg] do
        "server" -> :server
        "client" -> :client
        other -> Mix.raise("--leg must be server or client, got: #{inspect(other)}")
      end

    adapter =
      case opts[:adapter] do
        nil -> :sdk
        "sdk" -> :sdk
        "null" -> :null
        other -> Mix.raise("--adapter must be sdk or null, got: #{inspect(other)}")
      end

    run_opts =
      [leg: leg, adapter: adapter]
      |> put_if(:out_dir, opts[:out_dir])
      |> put_if(:cwd, opts[:cwd])
      |> put_if(:harness_dir, opts[:harness_dir])
      |> put_if(:requirements, opts[:requirements])
      |> put_if(:port, opts[:port])

    {:ok, _manifest, out_dir} = MCP.Conformance.Runner.run(run_opts)

    Mix.shell().info("""

    Run complete. It is NOT quotable until adjudicated:

        mix conformance.adjudicate #{out_dir}
    """)
  end

  defp put_if(opts, _key, nil), do: opts
  defp put_if(opts, key, value), do: Keyword.put(opts, key, value)
end

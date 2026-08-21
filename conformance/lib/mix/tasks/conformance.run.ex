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
    * `--adapter` — which of the leg's named adapters to drive the run with.
      Defaults to `sdk`, the SDK under test. The rest are the controls and the
      probe, enumerated per leg in `MCP.Conformance.Adapters`:

        * server: `null` — answers -32601 to everything, so the run measures
          what a server with no implementation earns from the same suite;
        * client: `null_exit0`, `null_connect`, `null_request` — three nulls of
          increasing strictness, because on this leg a **stricter** null scores
          **lower** and "the null control" is therefore not one number;
        * client: `strict_connect` — not a control but a **probe**: the SDK
          client halting the moment `connect/1` errors, which is what turns the
          drive-policy discount from something inherited into something
          measured.
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

  # The usage line does NOT enumerate the adapter names, and that is the fix
  # rather than an omission: the admissible set is per leg, so any one-line enum
  # is false for the other leg. It used to read `sdk|null`, which is the server
  # leg's set — an operator on the client leg following it got a raise. The
  # per-leg enumeration is printed where it can be correct, by `run/1` below,
  # out of `MCP.Conformance.Adapters.names/1`.
  @usage "mix conformance.run --leg server|client [--adapter NAME] [-o RUN_DIR] [--cwd DIR]"

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

    # Validated against the registry for THIS leg, and converted through
    # `Adapters.atom/1` — the only sanctioned string -> atom conversion for an
    # adapter name, and one that can only return an atom the registry itself
    # minted. The membership check is `Adapters.fetch/2`, not a hardcoded list:
    # the client leg's four adapters were added to the registry alone.
    adapter =
      case opts[:adapter] do
        nil ->
          :sdk

        name ->
          MCP.Conformance.Adapters.fetch(leg, name) ||
            Mix.raise(
              "--adapter must be one of #{Enum.join(MCP.Conformance.Adapters.names(leg), ", ")} " <>
                "for the #{leg} leg, got: #{inspect(name)}"
            )

          MCP.Conformance.Adapters.atom(name)
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

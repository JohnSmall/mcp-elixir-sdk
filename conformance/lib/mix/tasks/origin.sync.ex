defmodule Mix.Tasks.Origin.Sync do
  @shortdoc "Is origin/main and the version's tag what we actually hold? Live, fail-closed."

  @moduledoc """
  The instrument for the standing push rule (overrides page **D8**, MES-95):
  `main` **and the merge's tag** are pushed as the final step of every merge
  gate.

      mix origin.sync

  Exit **0** all five conjuncts green. Exit **1** any conjunct red or
  undetermined. Exit **64** usage error.

  ## Where it runs, and where it deliberately does not

  Three run points, none of them a seventh DoD gate. Gates 1-6 are per-ticket
  and run by CODE_CREATOR on a branch, *before* the merge exists — a sync check
  there would be red by construction on every ticket, which would make the gate
  table permanently false rather than informative.

    1. **PM, immediately after the push.** The primary assertion.
    2. **CODE_REVIEWER, on the merge-gate checklist**, attesting the
       **previous** merge. This is the limb that makes the rule self-enforcing:
       a missed push goes red at the very next merge gate rather than never.
    3. **The end-of-sprint sweep**, alongside the dependency sweep.

  ## Switches, and why they exist

      mix origin.sync --repo DIR --remote NAME --version STRING

  All three default to this project: the working directory, `origin`, and
  `Mix.Project.config()[:version]`. They are overridable so the controls in
  `conformance/controls/origin_sync_controls.exs` can drive **this task** — the
  real decision path, not a re-implementation of it — against a throwaway
  fixture repository. A run that takes any of them from the command line prints
  **DIAGNOSTIC RUN** and names what was supplied, so a fixture run can never be
  quoted as an attestation about this repository. Same shape as `MCP_ETCC_TAG`
  in `mix test.etcc`.

  See `MCP.Conformance.OriginSync` for the five conjuncts, the two measured
  false-greens in the obvious `rev-parse` form, and the fail-closed rule.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, OriginSync}

  @switches [repo: :string, remote: :string, version: :string]
  @usage "mix origin.sync [--repo DIR] [--remote NAME] [--version STRING]"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = Argv.parse!("origin.sync", argv, strict: @switches, usage: @usage)

    settings = [
      repo: opts[:repo] || File.cwd!(),
      remote: opts[:remote] || "origin",
      version: opts[:version] || Mix.Project.config()[:version]
    ]

    verdict = settings |> OriginSync.observe() |> OriginSync.decide()

    report(settings, opts, verdict)
    finish(settings, verdict)
  end

  defp report(settings, opts, verdict) do
    Mix.shell().info("""

    ORIGIN SYNC — the published state versus the state we hold

      repo      #{settings[:repo]}#{supplied(opts, :repo)}
      remote    #{settings[:remote]}#{supplied(opts, :remote)}
      version   #{settings[:version]}#{supplied(opts, :version)}\
    #{diagnostic_note(opts)}
    """)

    for c <- verdict.conjuncts do
      Mix.shell().info("  #{mark(c.status)} #{String.upcase(to_string(c.id))}  #{c.claim}")
      for line <- c.lines, do: Mix.shell().info("        #{line}")
    end
  end

  defp supplied(opts, key), do: if(opts[key], do: "   (supplied)", else: "")

  defp diagnostic_note(opts) do
    case Enum.filter([:repo, :remote, :version], &opts[&1]) do
      [] ->
        ""

      given ->
        "\n\n  DIAGNOSTIC RUN — #{Enum.map_join(given, ", ", &"--#{&1}")} supplied on the " <>
          "command line.\n  This run says nothing about this repository."
    end
  end

  defp mark(:green), do: "GREEN"
  defp mark(:red), do: "RED  "
  defp mark(:undetermined), do: "UNDET"

  defp finish(_settings, %{ok?: true}) do
    Mix.shell().info("\n  IN SYNC — main and the version's tag are both published as held.\n")
  end

  defp finish(settings, %{conjuncts: conjuncts}) do
    failed =
      conjuncts
      |> Enum.reject(&(&1.status == :green))
      |> Enum.map_join(", ", &String.upcase(to_string(&1.id)))

    Mix.raise("""
    NOT IN SYNC — #{failed} did not come back green.

    Remedy, and it is the merge gate's final step either way:

        git push #{settings[:remote]} main
        git push #{settings[:remote]} #{OriginSync.tag_for(settings[:version])}

    An undetermined conjunct is a failure here on purpose: an origin we could not
    read is an origin we cannot attest, and a check that cannot tell must not
    return the success signal.
    """)
  end
end

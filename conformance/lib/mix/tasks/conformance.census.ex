defmodule Mix.Tasks.Conformance.Census do
  @shortdoc "Convert an accepted conformance run into census.json, and render the table from it"

  @moduledoc """
  Read an **accepted** run and emit the per-scenario census as JSON, optionally
  rendering the Markdown table from that same JSON.

      mix conformance.census RUN_DIR -o docs/conformance/server-2026-07-28.json
      mix conformance.census RUN_DIR --control NULL_RUN_DIR --markdown docs/conformance/server-2026-07-28.md

  ## Options

    * `-o`, `--out` — where `census.json` goes. Defaults to `census.json`
      inside the run directory.
    * `--control` — a null-implementation run to join, so the passes a
      do-nothing implementation also earns are visible rather than inherited.
      Leg-neutral by construction: on a server census that control is a null
      server, on a client census a null client, and the console output names
      whichever the census's own `run.leg` says it is.
    * `--markdown` — also render the table to this path. It is rendered **from**
      the census, never written by hand: a committed table that can drift from
      the run it reports is MES-24's defect, and the only reliable fix is to
      make the table a projection rather than a copy.
    * `--expect-commit` — the tree under review, passed to the adjudicator's own
      `judge/3`. Defaults to the commit the manifest recorded, because a census
      may legitimately be taken of a run whose tree is no longer checked out.

  ## Exit status

  `0` census written. `1` refused — the run was not accepted, or the census's
  own conditions were not met, and nothing was written. `64` usage error.

  There is **no flag that prints a census anyway.** This task calls the same
  `MCP.Conformance.Manifest.judge/3` the adjudicator calls, so "no figure may be
  quoted from a run the adjudicator has not accepted" is a property of the code
  rather than a rule someone has to remember.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, Census}

  @switches [
    out: :string,
    control: :string,
    markdown: :string,
    expect_commit: :string
  ]

  @aliases [o: :out]

  @usage "mix conformance.census RUN_DIR [-o census.json] [--control DIR] [--markdown FILE]"

  @impl Mix.Task
  def run(argv) do
    {opts, args} =
      Argv.parse!("conformance.census", argv,
        strict: @switches,
        aliases: @aliases,
        positional: 1,
        usage: @usage
      )

    run_dir =
      case args do
        [dir] -> Path.expand(dir)
        [] -> Mix.raise("usage: #{@usage}")
      end

    build_opts =
      [control: opts[:control]] ++
        if(opts[:expect_commit], do: [expect_commit: opts[:expect_commit]], else: [])

    case Census.build(run_dir, build_opts) do
      {:ok, census} -> emit(census, run_dir, opts)
      {:refused, code, detail} -> refuse(run_dir, code, detail)
    end
  end

  defp emit(census, run_dir, opts) do
    json = Census.write!(census, opts[:out] || Path.join(run_dir, "census.json"))

    markdown =
      if opts[:markdown] do
        path = opts[:markdown]
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, MCP.Conformance.Census.Markdown.render(census))
        path
      end

    Mix.shell().info("""
    CENSUS  #{run_dir}

      role              #{census["run"]["role"]} (adapter #{census["run"]["adapter"]})
      leg               #{census["run"]["leg"]}
      commit            #{census["run"]["commit"]}
      requirements      #{census["run"]["requirements_revision"]} md5:#{census["run"]["requirements_md5"]}
      scenarios         #{length(census["scenarios"])} ran, #{scored(census)} scored
    #{headline(census)}
      json              #{json}#{if markdown, do: "\n      markdown          " <> markdown, else: ""}
    """)
  end

  defp scored(census), do: Enum.count(census["scenarios"], & &1["scored"])

  # A control gets no headline. The number that says how many scenarios a
  # do-nothing implementation passes is meaningful only beside the measurement it
  # disciplines; printed alone in the same shape as a conformance figure, it is
  # a rate waiting to be quoted as one.
  #
  # MES-57 round 4: "server" was hard-coded in three console strings here and
  # printed over CLIENT-leg censuses, whose controls are null CLIENTS. Console
  # output is not a published artefact, so this is outside the C3 sweep's set —
  # but it is the same false statement, and the operator reading it is the one
  # deciding whether the run is sound.
  defp headline(%{"run" => %{"role" => "control"}} = census) do
    tally = get_in(census, ["totals", "by_reducer", "requirements_exit", "scored"])

    "  CONTROL — no headline. A do-nothing #{null_noun(census)} passed " <>
      "#{tally["passed"]}/#{tally["total"]} scored scenarios;\n" <>
      "                        that figure exists to be subtracted, not quoted."
  end

  defp headline(census) do
    census
    |> get_in(["totals", "by_reducer"])
    |> Enum.sort()
    |> Enum.map_join("\n", fn {name, t} ->
      "      #{String.pad_trailing(name, 18)}#{t["scored"]["passed"]}/#{t["scored"]["total"]} scored"
    end)
    |> Kernel.<>(control_line(census))
  end

  defp control_line(census) do
    case get_in(census, ["totals", "control"]) do
      nil ->
        "\n      control           NOT JOINED — pass --control to state how many of those " <>
          "passes a\n                        do-nothing #{null_noun(census)} also earns"

      c ->
        "\n      control           #{length(c["discriminating"])} of those passes are ours " <>
          "alone; #{length(c["inherited"])} are also earned\n" <>
          "                        by a do-nothing #{null_noun(census)} (reducer #{c["reducer"]})\n" <>
          "      coverage          the control ran every scored scenario measured here — " <>
          "checked, not\n                        assumed: a gap refuses " <>
          "(CONTROL_MISSING_SCENARIOS) and nothing above\n                        is printed"
    end
  end

  defp null_noun(%{"run" => %{"leg" => "client"}}), do: "client"
  defp null_noun(_census), do: "server"

  defp refuse(run_dir, code, detail) do
    Mix.shell().error("""
    REFUSED  #{run_dir}

      #{code}
      #{detail}

    No census was written and no figure from this run may be quoted.
    """)

    exit({:shutdown, 1})
  end
end

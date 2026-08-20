defmodule Mix.Tasks.Conformance.Adjudicate do
  @shortdoc "Refuse to report figures from a conformance run whose provenance does not hold"

  @moduledoc """
  Read a run's `manifest.json` and decide whether its figures may be quoted.

      mix conformance.adjudicate /tmp/mcp-conformance-runs/server-20260820T193000Z

  Exits **0** and prints an acceptance block naming the tree measured, or exits
  **1** printing a single refusal code and why, or — under `--diagnose` — exits
  **2** having reported every condition and accepted nothing. It never warns: a
  warning is a gate that can be ignored while continuing to look like one (R4).

  ## Options

    * `--expect-commit` — the tree under review. Defaults to `HEAD` of the
      current worktree.
    * `--expect-requirements-md5`, `--expect-harness-dist-sha256` — pin the
      instrument as well as the tree. Optional; when omitted, those manifest
      fields are recorded provenance and nothing judges them.
    * `--diagnose` — report EVERY refusal condition's status instead of halting
      at the first, and exit **2** whatever it finds. A diagnosis is not a
      verdict: this mode cannot accept a run, and no invocation carrying it can
      reach exit 0. For seeing what is wrong with a run — including a run you
      already know will be refused — without any way to obtain acceptance from
      one that should not have it.

  ## Exit status is the whole contract

  `0` acceptance, and only with every condition passing. `1` refusal. `2`
  diagnosis, no verdict. **Nothing yields 0 with a refusal condition
  outstanding** — there is no waiver, no override and no flag that relaxes a
  condition, because MES-56 and MES-57 gate on the exit status and an automated
  consumer reading only that status cannot see a waiver however loudly it is
  printed. A rule without a gate is a rule that gets missed.

  ## What acceptance does and does not mean

  An accepted manifest makes a figure **attributable**, not **correct**: it ties
  a number to a tree and says nothing about whether the number is a good
  measurement of conformance. The enumerated residual is printed with every
  acceptance so the bound travels with the claim.
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, Manifest, Provenance}

  @switches [
    expect_commit: :string,
    expect_requirements_md5: :string,
    expect_harness_dist_sha256: :string,
    diagnose: :boolean
  ]

  # A diagnosis issues no verdict, so it gets its own status: never 0 (it cannot
  # accept), never 1 (it did not refuse either). One constant, taken
  # unconditionally, is what makes "this mode cannot exit 0" a property of the
  # code's shape rather than a claim about its branches.
  @diagnostic_exit 2

  @usage "mix conformance.adjudicate RUN_DIR [--expect-commit REF]"

  # `--allow-dirty` was removed a round ago precisely so it could not yield exit
  # 0. It still did, by a different route: unrecognised, discarded, and the run
  # accepted on its merits. An operator working from a stale runbook got exactly
  # the outcome the removal was meant to prevent, which is why the flag is named
  # here rather than left to read as a typo.
  @retired %{
    "--allow-dirty" =>
      "it waived WORKTREE_DIRTY and exited 0. Use --diagnose to see every " <>
        "outstanding condition; nothing waives one."
  }

  @impl Mix.Task
  def run(argv) do
    {opts, args} =
      Argv.parse!("conformance.adjudicate", argv,
        strict: @switches,
        positional: 1,
        usage: @usage,
        retired: @retired
      )

    run_dir =
      case args do
        [dir] -> Path.expand(dir)
        [] -> Mix.raise("usage: #{@usage}")
      end

    expect = %{
      commit: opts[:expect_commit] || resolved_head(),
      requirements_md5: opts[:expect_requirements_md5],
      harness_dist_sha256: opts[:expect_harness_dist_sha256]
    }

    if opts[:diagnose] == true do
      diagnose(run_dir, expect)
    else
      case adjudicate(run_dir, expect) do
        {:ok, manifest} -> accept(run_dir, manifest, expect)
        {:refused, code, detail} -> refuse(run_dir, code, detail)
      end
    end
  end

  defp adjudicate(run_dir, expect) do
    with {:ok, manifest} <- Manifest.read(run_dir) do
      case Manifest.judge(manifest, observe(run_dir), expect) do
        :ok -> {:ok, manifest}
        refusal -> refusal
      end
    end
  end

  defp observe(run_dir) do
    console = Path.join(run_dir, Manifest.console_filename())

    %{
      scenario_dirs: Provenance.scenario_dirs(run_dir),
      console_sha256: Provenance.sha256_file(console)
    }
  end

  # The block is split because it was caught asserting what it had not checked:
  # a run with no console.txt was accepted while this block printed the stored
  # console hash, for a file that did not exist. A printed field that nothing
  # verified is a claim wider than its check — the whole subject of MES-51 —
  # so every line now sits under the heading that says which it is.
  defp accept(run_dir, m, expect) do
    Mix.shell().info("""
    ACCEPTED  #{run_dir}

      VERIFIED — each of these was compared this run, and a mismatch would have refused it:
        commit            #{m["git"]["commit_sha_start"]}
                          == the tree under review #{expect.commit}
        worktree          #{if m["git"]["dirty_start"] != false, do: "DIRTY", else: "clean"} at start and end, over the whole tree
        cwd               #{m["invocation"]["cwd"]}
                          == project root #{m["invocation"]["project_root"]}
        adapter beacons   #{m["beacon"]["adapter_count"]} > 0, over #{m["result"]["scenario_dir_count"]} scenario dirs enumerated on disk
        console           #{Manifest.console_filename()} sha256:#{short(m["result"]["console_sha256"])} — re-hashed from the file now
    #{instrument_lines(m, expect, :verified)}
      RECORDED — provenance this run carries. Nothing here was verified; do not read it as a check:
        leg               #{m["leg"]}
        branch            #{m["git"]["branch_start"]}
        harness version   #{m["harness"]["version_reported"]}
        requirements      #{m["requirements"]["revision"]}
        console bytes     #{m["result"]["console_bytes"]}
        ran               #{m["timing"]["started_at"]} -> #{m["timing"]["ended_at"]} (container local offset #{m["timing"]["utc_offset"]})
    #{instrument_lines(m, expect, :recorded)}
    Figures from this run are ATTRIBUTABLE to the tree above. That is not the same
    as CORRECT. This acceptance does not establish:
    #{Enum.map_join(Manifest.residual(), "\n", &"  - #{&1}")}
    """)
  end

  # The diagnostic mode. Two things make it safe to have at all:
  #
  #   * it reports conditions, it does not relax them — `Manifest.judge/3` is
  #     untouched by this path and is still the only thing that can accept;
  #   * every path through here ends at the same unconditional `exit/1`, so
  #     "cannot exit 0" needs no case analysis over which conditions fired.
  #
  # It replaced `--allow-dirty`, which waived WORKTREE_DIRTY and printed
  # ACCEPTED with exit 0. That the waiver was printed loudly did not save it: the
  # adjudicator is binding on MES-56 and MES-57 through its EXIT STATUS, and a
  # consumer reading only the status cannot see anything that was printed.
  defp diagnose(run_dir, expect) do
    rows =
      case Manifest.read(run_dir) do
        {:ok, manifest} -> Manifest.diagnose(manifest, observe(run_dir), expect)
        refusal -> Manifest.diagnose(refusal, observe(run_dir), expect)
      end

    outstanding = for {code, {:refused, _}} <- rows, do: code
    unevaluated = for {code, {:not_evaluated, _}} <- rows, do: code

    summary =
      "#{length(outstanding)} outstanding, #{length(unevaluated)} not evaluated, " <>
        "#{length(rows) - length(outstanding) - length(unevaluated)} passing."

    Mix.shell().info("""
    DIAGNOSIS  #{run_dir}

      No verdict. This mode reports; it cannot accept. Every one of the
      #{length(rows)} refusal conditions is listed below, passing or not.

    #{Enum.map_join(rows, "\n", &row_lines/1)}

      #{summary}
    #{verdict_pointer(outstanding, expect)}
    """)

    exit({:shutdown, @diagnostic_exit})
  end

  defp row_lines({code, :ok}), do: "    PASS           #{code}"

  defp row_lines({code, {:refused, detail}}),
    do: "    OUTSTANDING    #{code}\n                   #{detail}"

  defp row_lines({code, {:not_evaluated, why}}),
    do: "    NOT EVALUATED  #{code}\n                   #{why}"

  defp verdict_pointer([], expect) do
    """

      Nothing is outstanding, and this run is still not accepted: a diagnosis is
      not a verdict, and this invocation exits #{@diagnostic_exit}. For one that
      can accept, drop --diagnose:

        mix conformance.adjudicate RUN_DIR --expect-commit #{expect.commit}
    """
  end

  defp verdict_pointer(outstanding, _expect) do
    """

      An ordinary adjudication of this run would refuse it with #{hd(outstanding)},
      the first condition outstanding, and exit 1. Nothing here can waive that.
    """
  end

  defp short(nil), do: "(none)"
  defp short(hash), do: String.slice(to_string(hash), 0, 16)

  # The instrument fields are judged only when the caller pins them, so they
  # belong under whichever heading is true for THIS invocation. Printing them
  # unconditionally under VERIFIED, annotated as unverified, would be a heading
  # that contradicts its own contents.
  defp instrument_lines(m, expect, section) do
    [
      {"harness dist", m["harness"]["dist_sha256"], expect.harness_dist_sha256,
       "--expect-harness-dist-sha256"},
      {"requirements md5", m["requirements"]["md5"], expect.requirements_md5,
       "--expect-requirements-md5"}
    ]
    |> Enum.filter(fn {_, _, pin, _} ->
      section == if(is_nil(pin), do: :recorded, else: :verified)
    end)
    |> Enum.map_join("", fn {label, actual, pin, flag} ->
      suffix =
        if is_nil(pin),
          do: " — unpinned this run; pass #{flag} to have it checked",
          else: " == the pinned value"

      "    #{String.pad_trailing(label, 18)}#{short(actual)}#{suffix}\n"
    end)
  end

  defp refuse(run_dir, code, detail) do
    Mix.shell().error("""
    REFUSED  #{run_dir}

      #{code}
      #{detail}

    No figure from this run may be quoted. This is a refusal, not a warning.
    """)

    exit({:shutdown, 1})
  end

  # `judge/3` treats a nil expectation as "no tree nominated, do not judge the
  # commit" — a deliberate affordance for callers that pin nothing. Resolving
  # HEAD to nil and passing it in would take that affordance by accident:
  # COMMIT_MISMATCH would be skipped, silently, on exactly the invocation that
  # could not tell what it was measuring. Same class as B1 and B2, so it fails
  # here rather than passing there.
  defp resolved_head do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {out, 0} ->
        String.trim(out)

      _ ->
        Mix.raise(
          "cannot resolve the tree under review: `git rev-parse HEAD` failed here. " <>
            "Adjudicating without one would skip COMMIT_MISMATCH silently. " <>
            "Run this from the worktree under review, or nominate it with --expect-commit REF."
        )
    end
  end
end

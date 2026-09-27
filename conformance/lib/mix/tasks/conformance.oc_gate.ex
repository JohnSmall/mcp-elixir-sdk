defmodule Mix.Tasks.Conformance.OcGate do
  @shortdoc "Gate 7: every new or changed test is cross-checked live against the official conformance suite"

  @moduledoc """
  Gate 7 (MES-160). **No test merges green while its OC check is red.**

      mix conformance.oc_gate MES-123
      mix conformance.oc_gate MES-123 --base main --harness-dir /tmp/conf11

  Run from the project root, with `{TICKET_KEY}` checked out and the tree
  clean — the live legs measure the working tree, and the seats share one
  clone, so the gate refuses to measure anything but the branch tip.

  ## What it does

    1. Resolves `--base` (default `main`) and `KEY`, and takes the three-dot
       diff `base...KEY`. An unresolvable ref is a refusal, never an empty diff.
    2. **Applicability.** No path under `test/`, `lib/` or `conformance/` ⇒
       prints `OC-GATE N/A` and exits 0.
    3. Reads every new or changed `test/**/*_test.exs` declaration (and, when
       `lib/` or `conformance/` changed, every test already carrying
       `@tag oc:` check tokens) via `MCP.Conformance.OcGateDeclarations`.
    4. Runs, live and whole, each leg the tokens name, and judges each token
       on the run's `checks.json` via `MCP.Conformance.OcGate`.
    5. Prints one line per declaration, then exactly one of `OC-GATE PASS`,
       `OC-GATE N/A`, `OC-GATE REFUSE (n)`.

  **The exit status corresponds to the verdict**: 0 for PASS and N/A, 1 for
  REFUSE. Adjudicate on the final line all the same; it names what was
  measured.

  ## Options

    * `--base` — the ref the branch is diffed against (default `main`)
    * `--harness-dir` — npm install root of the pinned harness (default `/tmp/conf11`)
    * `--out-root` — where live runs are written (default `/tmp/mes-oc-gate`)
  """

  use Mix.Task

  alias MCP.Conformance.{Argv, OcGate, Provenance}
  alias MCP.Conformance.OcGateDeclarations, as: Decls

  @switches [base: :string, harness_dir: :string, out_root: :string]
  @usage "mix conformance.oc_gate TICKET_KEY [--base main] [--harness-dir DIR] [--out-root DIR]"

  @impl Mix.Task
  def run(argv) do
    {opts, args} =
      Argv.parse!("conformance.oc_gate", argv, strict: @switches, positional: 1, usage: @usage)

    key =
      case args do
        [key] -> key
        [] -> Mix.raise("usage: #{@usage}")
      end

    base = opts[:base] || "main"
    repo = Provenance.project_root(File.cwd!()) || File.cwd!()
    started = System.monotonic_time(:millisecond)

    case Decls.population(repo, base, key) do
      {:error, reason} ->
        refuse_whole(:unresolvable, "#{base}...#{key}: #{inspect(reason)}")

      {:ok, pop} ->
        gate(repo, key, base, pop, opts, started)
    end
  end

  defp gate(repo, key, base, pop, opts, started) do
    info("base #{base} merge-base #{short(pop.merge_base)}  #{key} tip #{short(pop.tip)}")

    cond do
      not (pop.test_changed or pop.lib_changed or pop.conformance_changed) ->
        info("OC-GATE N/A: no test/, lib/ or conformance/ change on #{base}...#{key}")

      (reason = tree_refusal(repo, pop.tip)) != nil ->
        refuse_whole(:wrong_tree, reason)

      true ->
        decls = pop.changed ++ pop.tagged_elsewhere
        measurements = measure(OcGate.legs(decls), pop.tip, opts)
        verdicts = OcGate.judge(decls, measurements)
        report(verdicts, measurements, pop, started)
    end
  end

  # Seats share one clone: the live legs measure the working tree, so it must BE
  # the branch tip, and clean.
  defp tree_refusal(repo, tip) do
    head = git(repo, ["rev-parse", "HEAD"])
    status = git(repo, ["status", "--porcelain"])

    cond do
      head != {:ok, tip} ->
        "HEAD is #{inspect(head)}, not the branch tip #{tip} — check the branch out"

      status != {:ok, ""} ->
        "the working tree is not clean: #{inspect(status)}"

      true ->
        nil
    end
  end

  defp measure(legs, tip, opts) do
    run_opts =
      [label: "gate"]
      |> put_if(:harness_dir, opts[:harness_dir])
      |> put_if(:out_root, opts[:out_root])

    Map.new(legs, fn leg ->
      t0 = System.monotonic_time(:millisecond)
      m = OcGate.measure(leg, tip, run_opts)
      info("measured #{leg} leg in #{System.monotonic_time(:millisecond) - t0} ms: #{summary(m)}")
      {leg, m}
    end)
  end

  defp summary({:ok, %{rows: rows, run_dir: dir}}), do: "#{length(rows)} checks, #{dir}"
  defp summary({:error, class, detail}), do: "#{class}: #{detail}"

  defp report(verdicts, measurements, pop, started) do
    info(
      "#{length(pop.changed)} new/changed declaration(s), " <>
        "#{length(pop.tagged_elsewhere)} unchanged oc-tagged (lib/ changed: #{pop.lib_changed}, " <>
        "conformance/ changed: #{pop.conformance_changed}); " <>
        "legs measured: #{inspect(Map.keys(measurements))}"
    )

    Enum.each(verdicts, &info(line(&1)))

    refused = Enum.count(verdicts, &(&1.outcome == :refuse))
    ms = System.monotonic_time(:millisecond) - started

    if refused == 0 do
      info("OC-GATE PASS (#{length(verdicts)} declaration(s), #{ms} ms)")
    else
      info("OC-GATE REFUSE (#{refused}) of #{length(verdicts)} declaration(s), #{ms} ms")
      exit({:shutdown, 1})
    end
  end

  defp line(%{decl: d, outcome: outcome, class: class, detail: detail, checks: checks}) do
    head =
      "#{verdict_word(outcome)}  #{d.file}:#{d.line}  #{inspect(d.id)}  [#{change_text(d)}]"

    body =
      case checks do
        [] -> if class, do: "#{class}: #{detail}", else: detail
        _ -> Enum.map_join(checks, "; ", &check_text/1)
      end

    head <> "  " <> body
  end

  # `changed: file` tells the author the test's own bytes did not move — the
  # file around it did (MES-160 correction round 1).
  defp change_text(%{change: :changed, cause: cause}) when cause != nil, do: "changed: #{cause}"
  defp change_text(%{change: change}), do: "#{change}"

  defp check_text(%{outcome: :pass} = c), do: "#{c.token} -> #{c.status}"

  defp check_text(c),
    do: "#{c.token} -> #{c.status || "-"} (#{c.outcome}: #{c.detail})"

  defp verdict_word(:pass), do: "PASS  "
  defp verdict_word(:none), do: "NONE  "
  defp verdict_word(:refuse), do: "REFUSE"

  defp refuse_whole(class, detail) do
    info("REFUSE  #{class}: #{detail}")
    info("OC-GATE REFUSE (1): #{class}")
    exit({:shutdown, 1})
  end

  defp git(repo, args) do
    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, code} -> {:error, code, String.trim(out)}
    end
  end

  defp short(sha), do: String.slice(sha, 0, 7)

  defp put_if(opts, _k, nil), do: opts
  defp put_if(opts, k, v), do: Keyword.put(opts, k, v)

  defp info(msg), do: Mix.shell().info(msg)
end

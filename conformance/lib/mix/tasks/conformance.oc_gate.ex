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
    2. **Applicability.** No path under `test/`, `lib/` or `conformance/`, and
       no change to the root `mix.lock` ⇒ prints `OC-GATE N/A` and exits 0.
    3. Reads every new or changed `test/**/*_test.exs` declaration (and, when
       `lib/`, `conformance/` or `mix.lock` changed, every test already
       carrying `@tag oc:` check tokens) via `MCP.Conformance.OcGateDeclarations`.
    4. Runs, live and whole, each leg the tokens name, and judges each token
       on the run's `checks.json` via `MCP.Conformance.OcGate`.
    5. **A `mix.lock` change** (PO ruling 2026-11-12, MES-236; the case was
       MES-227's bandit bump) also runs **every** leg whole, named or not, and
       a run the census does not accept is a refusal of its own — one
       whole-run line, counted in `REFUSE (n)` — so `PASS` on a lock change
       always means both legs ran and were accepted, never "nothing measured".
    6. Prints one line per declaration (and per refused whole run), then
       exactly one of `OC-GATE PASS`, `OC-GATE N/A`, `OC-GATE REFUSE (n)`.

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

  # Every leg a whole run exists for; a `mix.lock` change measures all of them.
  @all_legs ~w(client server)

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
      not (pop.test_changed or pop.lib_changed or pop.conformance_changed or pop.lock_changed) ->
        info("OC-GATE N/A: no test/, lib/, conformance/ or mix.lock change on #{base}...#{key}")

      (reason = tree_refusal(repo, pop.tip)) != nil ->
        refuse_whole(:wrong_tree, reason)

      true ->
        decls = pop.changed ++ pop.tagged_elsewhere
        forced = forced_legs(pop)
        legs = (OcGate.legs(decls) ++ forced) |> Enum.uniq() |> Enum.sort()
        measurements = measure(legs, pop.tip, opts)
        verdicts = OcGate.judge(decls, measurements)
        report(verdicts, forced, run_refusals(forced, measurements), measurements, pop, started)
    end
  end

  # A dependency bump can move any check, tagged or not (MES-236 Q2): on a
  # `mix.lock` change every leg runs whole, whether or not a token names it.
  defp forced_legs(%{lock_changed: true}), do: @all_legs
  defp forced_legs(_pop), do: []

  # A forced leg's run must itself be accepted; a declaration-free branch would
  # otherwise PASS having judged nothing. Only an accepted run passes: a missing
  # entry, or any shape but `{:ok, %{rows: _}}`, is refused too (MES-236
  # correction round 1, the CR's tripwire on CR-M15).
  defp run_refusals(forced, measurements) do
    Enum.flat_map(forced, fn leg ->
      case Map.fetch(measurements, leg) do
        {:ok, {:ok, %{rows: rows}}} when is_list(rows) ->
          []

        {:ok, {:error, class, detail}} ->
          [%{leg: leg, class: class, detail: detail}]

        {:ok, other} ->
          [%{leg: leg, class: :measurement_malformed, detail: inspect(other)}]

        :error ->
          [
            %{
              leg: leg,
              class: :measurement_missing,
              detail: "the leg was forced and not measured"
            }
          ]
      end
    end)
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

  defp report(verdicts, forced, runs, measurements, pop, started) do
    info(
      "#{length(pop.changed)} new/changed declaration(s), " <>
        "#{length(pop.tagged_elsewhere)} unchanged oc-tagged (lib/ changed: #{pop.lib_changed}, " <>
        "conformance/ changed: #{pop.conformance_changed}, mix.lock changed: #{pop.lock_changed}); " <>
        "legs measured: #{inspect(Map.keys(measurements))}"
    )

    Enum.each(verdicts, &info(line(&1)))
    Enum.each(runs, &info("REFUSE  #{&1.class} (#{&1.leg} leg, mix.lock changed): #{&1.detail}"))

    refused = Enum.count(verdicts, &(&1.outcome == :refuse)) + length(runs)
    ms = System.monotonic_time(:millisecond) - started
    whole = if forced == [], do: "", else: ", #{length(forced)} whole run(s)"

    if refused == 0 do
      info("OC-GATE PASS (#{length(verdicts)} declaration(s)#{whole}, #{ms} ms)")
    else
      info("OC-GATE REFUSE (#{refused}) of #{length(verdicts)} declaration(s)#{whole}, #{ms} ms")
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

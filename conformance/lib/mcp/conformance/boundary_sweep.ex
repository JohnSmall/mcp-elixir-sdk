defmodule MCP.Conformance.BoundarySweep do
  @moduledoc """
  Re-runs MES-81's boundary-liveness sweep from the repository and diffs the result
  against the committed `conformance/data/etcc-boundaries.json`.

  ## Why this module exists

  Until MES-81 every field in the ET-CC register was a **judgement** — a gate outcome, a
  label, a spec anchor. A judgement goes stale only when the *criterion* changes, and the
  criterion is a document under change control. `boundary` and its liveness verdict are
  the register's first **measurements**, and a measurement goes stale when the *code*
  changes. `etcc_register.ex`'s guard 19 validates the register **against the recorded
  table**, never the table against the tree, so it would stay green while every verdict
  underneath it rotted. Nothing re-ran the sweep. This is what re-runs it.

  The procedure is **not** re-derived here. It is
  `docs/conformance/etcc-membership.md` §2.3(d) and (e) — ratified Part A — and
  `conformance/data/etcc-boundaries.json`'s own `procedure` block. This module executes
  that procedure; where it needs to say what the procedure is, it cites.

  ## L2's trigger is a number, not an opinion

  §2.3(d): *L2 runs on EVERY boundary-direction whose live count is zero, and never on a
  selection.* Here that is a `case` on an integer (`l2_trigger?/1`), so "the ones the
  sweeper suspects" is **not expressible**. MES-81 hit exactly that defect: L1 was silent
  on 12 directions, L2 was run on the 3 the sweeper had a hunch about, and CODE_REVIEWER
  then found **6 of the remaining 9 were LIVE**.

  ## What is measured, and what is consumed as recorded

  * **Measured** — `suite_summary`, `unlocated_failures`, `reddened_total`,
    `reddened_by_module`, `reddened_outside_own`, `reddened_outside_own_and_dead`,
    `live_units`, and the L2 byte probe's `scenarios_run` / `scenarios_moved`.
  * **Consumed as recorded** — `own_tests`, the three live-column exclusions, and L2
    conjunct (ii), the alias-aware call-site enumeration. (ii) is a judgement about
    `lib/`, and a script that pretended to derive it would be the S7-16 error over again;
    what IS mechanised is that it must be **present** on every dead row (guard 25).
  * **A stated limit.** The exclusion sets are themselves a function of which directions
    are dead, so the table is a fixpoint that MES-81 reached by hand over six rounds. The
    re-run consumes them as recorded rather than re-deriving the fixpoint. A verdict flip
    therefore does not silently re-solve the exclusion sets — it fails `--check` loudly,
    which is the behaviour this ticket asks for.

  ## The expiry condition this module is built against

  §2.3(e), as extended on MES-88 (`[authored 26988 | ratified 26995]`): a verdict expires
  when `lib/` moves, and **its L1 measurements additionally expire when the unit
  population moves**. That is why `--check` compares **verdict fields only**
  (`verdict`, `established_by`, `direction`, `l2.ran`, `l2.verdict`) and reports the
  measurement fields as a stated delta. Measured on MES-88: the population moved
  979 → 1021 with `lib/` byte-unchanged since `5e1c376` — and the population is a
  function of the HOST as well as the tree (994 units with `node` on PATH, 991 without,
  at one unchanged tip), which no git-diff skip condition can see. That is why the
  cadence's skip carries a third, non-git condition: `host/0` and `host_check/2`, and
  `mix conformance.sweep --host`.
  """

  @boundaries "conformance/data/etcc-boundaries.json"
  @probe "conformance/etcc_l2_probe.exs"
  @register "docs/conformance/etcc-register.json"

  # The prose form a `mutation` line is written in: `FILE: FROM  ->  TO`, the separator
  # being exactly two spaces, an arrow and two spaces. Verified on MES-88 to parse and
  # render back byte-exactly for all 194 committed lines, embedded newlines included.
  @sep "  ->  "
  @prose_rx ~r/\A(?<file>[^\s:]+\.exs?): (?<rest>.*)\z/s

  # The verdict fields — claims about `lib/`, and the only fields `--check` compares.
  @verdict_fields ~w(verdict established_by direction)
  # SEVEN, not the six §2.3(e)'s rationale enumerates. `unlocated_failures` is measured
  # too, and it MOVED on the MES-88 re-run (`Meta` 36 → 0, `Dispatch` 8 → 0) while being
  # in neither the compared set nor the reported set — a measured field changing in
  # silence. Reporting it is strictly more disclosure and `--check` still compares
  # verdict fields only, so the PM's AC1 rescope is honoured; the seventh is DISCLOSED in
  # the hand-back rather than folded in quietly. This is S8-7's own mechanism one level
  # down: an enumeration that names six of seven silently claims the seventh is not one.
  @measurement_fields ~w(suite_summary reddened_total reddened_by_module
                         reddened_outside_own reddened_outside_own_and_dead live_units
                         unlocated_failures)

  @doc "Paths, so the task, the controls and this module cannot drift apart."
  def paths, do: %{boundaries: @boundaries, probe: @probe, register: @register}

  @doc "The fields `--check` compares. Measurement fields are deliberately NOT here."
  def verdict_fields, do: @verdict_fields

  @doc "The fields §2.3(e)'s extension puts on the population rather than on `lib/`."
  def measurement_fields, do: @measurement_fields

  # ------------------------------------------------------------------
  # the host — the input to L1 that no git diff can see
  # ------------------------------------------------------------------

  # The marker exists so the fact is read off a LINE WE CHOSE rather than off "the last
  # thing mix printed". A compile message, a warning or a deprecation notice arriving on
  # the same stream would otherwise be read as the host fact.
  @host_marker "ETCC-HOST-HARNESS "

  @doc """
  The host facts the unit population depends on, and the single string a skip compares.

  **The population is not a function of the tree alone** (`S8-11`).
  `test/test_helper.exs` EXCLUDES the three `:requires_live_harness` conformance tests
  where `node` or the pinned harness is absent — deliberately, per MES-56 — so one
  unchanged tip measures **994** units with `node` on PATH and **991** without, and
  *both* git-diff skip conditions are empty across that pair. A skip of the end-of-sprint
  sweep therefore additionally requires this fingerprint to match the one recorded with
  the committed table: `CLAUDE.md`, End-of-Sprint Procedure step 4, condition (c).

  The harness fact is read from **the predicate that decides the exclusion** —
  `MCP.Conformance.TestHarness.unavailable_reason/0` — and is never re-derived here.
  That module lives under `test/support/`, which `elixirc_paths` compiles in `:test`
  only, so it is reached by running it in that env rather than by copying its three
  conditions into this file, where they could drift away from the exclusion they claim
  to describe.

  `harness` is deliberately coarse — `"available"` or `"unavailable"`, with the reason
  recorded beside it and NOT in the fingerprint. The fingerprint tracks the
  **population**, and every unavailability reason excludes the same three units, so a
  host that swaps one reason for another has not moved what L1 quantifies over.
  """
  @spec host() :: map()
  def host do
    node = node_version()
    {state, reason} = harness_state()

    %{
      "node" => node,
      "harness" => state,
      "harness_reason" => reason,
      "fingerprint" => "node=#{node} harness=#{state}"
    }
  end

  @doc """
  Compares the current host against the one recorded with the committed table.

  Returns `{:match, current}`, `{:differ, recorded, current}` or `{:unrecorded, current}`.

  **Fail-closed on both "not recorded" and "could not tell".** A missing record and an
  unreadable current fact both resolve to *run the sweep*, never to *skippable*: this is
  the S8-11 defect written as a default, and absence read as satisfaction is the failure
  MES-56 already paid for once inside the test suite itself.
  """
  @spec host_check(map() | nil, map() | nil) ::
          {:match, map()} | {:differ, map(), map()} | {:unrecorded, map()}
  def host_check(committed_control, current \\ nil) do
    current = current || host()
    recorded = (committed_control || %{})["host"]

    cond do
      not is_map(recorded) or not is_binary(recorded["fingerprint"]) -> {:unrecorded, current}
      current["harness"] == "unknown" -> {:differ, recorded, current}
      recorded["fingerprint"] == current["fingerprint"] -> {:match, current}
      true -> {:differ, recorded, current}
    end
  end

  @doc """
  Re-measures the unmutated baseline at this tip and writes `control.host` into the
  committed table.

  This is how the host gets recorded **without** a 25-minute re-sweep, and it is not a
  hand-edit: `control` stays generated, by the same `control_block/3` the full sweep
  uses. What makes it honest is that it REFUSES unless the baseline it measures is the
  one the committed `control` block already records — same suite total, same baseline
  failure count, green. A host recorded against a different population would be a
  fingerprint for a table that was never taken here, which is a worse lie than no
  fingerprint at all.
  """
  @spec record_host!(keyword()) :: map()
  def record_host!(opts \\ []) do
    path = Keyword.get(opts, :boundaries, @boundaries)
    log = Keyword.get(opts, :log, &IO.puts/1)
    doc = read_json(path)
    prior = doc["control"] || %{}

    refuse_dirty_lib!()
    log.("  baseline: mix test --seed 0")
    base = run_suite()
    log.("  baseline: #{base.summary}")

    if base.units != [] or base.rc != 0 do
      raise "REFUSING to record a host: the UNMUTATED suite is not green (#{base.summary})."
    end

    assert_same_population!(prior, base)

    control = control_block(prior, base, host())
    doc = Map.put(doc, "control", control)
    File.write!(path, Jason.encode!(doc, pretty: true) <> "\n")
    control
  end

  defp assert_same_population!(prior, base) do
    got = {suite_total(base.summary), length(base.units)}
    want = {prior["suite_total"], prior["baseline_failures"]}

    if got != want do
      raise "REFUSING to record a host: this baseline is #{inspect(got)} " <>
              "(suite_total, baseline_failures) and the committed control block records " <>
              "#{inspect(want)}. The table was not taken at this population, so a host " <>
              "recorded from here would fingerprint a run that never happened. Run the " <>
              "full sweep (`mix conformance.sweep --check --out ...`) instead."
    end

    :ok
  end

  # `unknown` rather than a guess. It is compared as a MISMATCH by `host_check/2`, so an
  # unreadable host fact makes the sweep run instead of making it skippable.
  defp harness_state do
    reason = ~s[MCP.Conformance.TestHarness.unavailable_reason() || "available"]
    eval = ~s[IO.puts("#{@host_marker}" <> (#{reason}))]

    {out, rc} =
      System.cmd("mix", ["run", "--no-start", "-e", eval],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    marked = out |> String.split("\n") |> Enum.find(&String.starts_with?(&1, @host_marker))

    case {rc, marked} do
      {0, line} when is_binary(line) ->
        case line |> String.replace_prefix(@host_marker, "") |> String.trim() do
          "available" -> {"available", nil}
          reason -> {"unavailable", reason}
        end

      _ ->
        {"unknown", "`MCP.Conformance.TestHarness.unavailable_reason/0` could not be run here"}
    end
  end

  # ------------------------------------------------------------------
  # prose <-> mutation_spec
  # ------------------------------------------------------------------

  @doc """
  Parses one committed `mutation` prose line into an applicable spec entry.

  Returns `{:ok, %{"file" => .., "from" => .., "to" => ..}}` or `:error`. The prose is
  the authored record and stays byte-identical in the file; this is the reading of it
  that can actually be applied.
  """
  def parse_prose(line) when is_binary(line) do
    with %{"file" => file, "rest" => rest} <- Regex.named_captures(@prose_rx, line),
         [from, to] <- String.split(rest, @sep, parts: 2) do
      {:ok, %{"file" => file, "from" => from, "to" => to}}
    else
      _ -> :error
    end
  end

  @doc "The inverse of `parse_prose/1`. Guard 27 requires the round trip to be exact."
  def render_prose(%{"file" => file, "from" => from, "to" => to}),
    do: file <> ": " <> from <> @sep <> to

  @doc """
  Derives a `mutation_spec` for one boundary row from its committed `mutation` prose,
  counting each FROM's occurrences in the tree as it stands.

  `replace` defaults to `"all"`; the caller overrides it per entry where MES-88's
  disambiguation measurement settled on `"first"`.
  """
  def derive_spec(%{"mutation" => lines}, overrides \\ %{}) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, i} ->
      {:ok, e} = parse_prose(line)
      n = occurrences(e["file"], e["from"])
      Map.merge(e, %{"occurrences" => n, "replace" => Map.get(overrides, i, "all")})
    end)
  end

  @doc "How many times FROM occurs in FILE, as literal bytes."
  def occurrences(file, from) do
    file |> File.read!() |> String.split(from) |> length() |> Kernel.-(1)
  end

  # ------------------------------------------------------------------
  # applying and reverting
  # ------------------------------------------------------------------

  @doc """
  Applies a boundary's `mutation_spec` to the tree. Returns the backups to pass to
  `revert!/1`.

  Raises before touching anything if any entry does not resolve with its recorded
  occurrence count — a spec that no longer resolves means `lib/` moved under it, which is
  the condition this whole module exists to detect, and it must fail loud rather than
  mutate something else.
  """
  def apply!(spec) do
    Enum.each(spec, &resolve!/1)

    backups =
      spec
      |> Enum.map(& &1["file"])
      |> Enum.uniq()
      |> Map.new(&{&1, File.read!(&1)})

    Enum.each(spec, fn e ->
      src = File.read!(e["file"])

      out =
        case e["replace"] do
          "first" -> String.replace(src, e["from"], e["to"], global: false)
          _ -> String.replace(src, e["from"], e["to"])
        end

      File.write!(e["file"], out)
    end)

    backups
  end

  @doc "Restores the exact bytes `apply!/1` saved. Always call this from an `after`."
  def revert!(backups), do: Enum.each(backups, fn {path, bytes} -> File.write!(path, bytes) end)

  defp resolve!(%{"file" => f, "from" => from, "occurrences" => n} = e) do
    actual = occurrences(f, from)

    if actual != n do
      raise "mutation_spec does not resolve: #{f} contains #{actual} occurrence(s) of " <>
              "#{inspect(String.slice(from, 0, 60))}, the spec records #{n}. " <>
              "lib/ has moved under this spec; the verdict it supports has expired (§2.3(e))."
    end

    e
  end

  # ------------------------------------------------------------------
  # running the suite, and reading its failures
  # ------------------------------------------------------------------

  @doc """
  Runs `mix test --seed 0` and returns `%{summary:, units:, unlocated:, rc:}`.

  `units` are `"file:line (Module)"` strings — the register key shape. ExUnit reports
  the **declaration** line under the failure header and the **assertion** line in the
  stacktrace; the declaration line is what the artefact keys on, so it is the one taken.
  """
  def run_suite(opts \\ []) do
    {out, rc} =
      System.cmd("mix", ["test", "--seed", Integer.to_string(Keyword.get(opts, :seed, 0))],
        stderr_to_stdout: true
      )

    parse_run(out) |> Map.put(:rc, rc)
  end

  @doc "Parses a `mix test` transcript. Split out from `run_suite/1` so it is testable."
  def parse_run(out) do
    lines = String.split(out, "\n")

    {units, unlocated} =
      lines
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, &accumulate_failure(&1, &2, lines))

    %{summary: summary_line(lines), units: Enum.reverse(units), unlocated: unlocated}
  end

  defp accumulate_failure({line, i}, {acc, un}, lines) do
    case failure_module(line) do
      nil -> {acc, un}
      mod -> locate(mod, lines |> Enum.at(i + 1, "") |> String.trim(), acc, un)
    end
  end

  # ExUnit prints the DECLARATION line under the failure header; that is the line the
  # register keys on, so it is the one taken. A header whose next line is not a
  # `file.exs:line` is counted as UNLOCATED rather than dropped — a failure the parser
  # could not key is a gap in the measurement, and silence about it is the S8-13 error.
  defp locate(mod, loc, acc, un) do
    case Regex.run(~r/\A(\S+\.exs):(\d+)\z/, loc) do
      [_, file, no] -> {["#{file}:#{no} (#{mod})" | acc], un}
      _ -> {acc, un + 1}
    end
  end

  # "  1) test NAME (Module)" / "  3) doctest Mod.fun/1 (Module)" / property. The module
  # is the LAST parenthesised group, because a test name may itself contain parentheses.
  defp failure_module(line) do
    with true <- Regex.match?(~r/\A\s+\d+\) (test|doctest|property) /, line),
         [_, mod] <- Regex.run(~r/\(([A-Z][A-Za-z0-9_.]*)\)\s*\z/, line) do
      mod
    else
      _ -> nil
    end
  end

  # The trailing clauses are NOT decoration. ExUnit appends `(N excluded)` when
  # `test_helper.exs` excludes the three `:requires_live_harness` tests — which is
  # exactly what happens on a host without `node` — and an anchored pattern that stops
  # at `failures` does not match that line, so the summary came back `nil` and the sweep
  # recorded a table with NO population in it. Measured on MES-88 (`S8-18`): the one
  # transcript shape the host axis actually produces was the one shape this could not
  # read. The clauses are optional and the prefix is unchanged, so a transcript from a
  # complete host parses exactly as it did before.
  @summary_rx ~r/\A\d+ doctests?, \d+ tests?, \d+ failures?(, \d+ invalid)?( \(\d+ \w+\))*\z/

  defp summary_line(lines) do
    lines
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Regex.match?(@summary_rx, &1))
    |> List.last()
  end

  # ------------------------------------------------------------------
  # the L2 byte probe
  # ------------------------------------------------------------------

  @doc """
  Runs the L2 byte probe to a file and returns `{scenario => bytes}`.

  The output PATH is what keeps the compiler's `Compiling 1 file (.ex)` chatter out of
  the compared stream. In a mutation sweep the step before every probe run has changed
  `lib/`, so a diff of two raw stdout captures reports a difference on **every** run that
  is not a moved scenario (MES-81 `26071`, reproduced on MES-88).
  """
  def probe(out_path) do
    File.rm(out_path)
    {_out, _rc} = System.cmd("mix", ["run", @probe, out_path], stderr_to_stdout: true)

    out_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [k, v] = String.split(line, "\t", parts: 2)
      {k, v}
    end)
  end

  @doc "Scenarios whose bytes differ between the baseline and the mutated probe."
  def scenarios_moved(baseline, mutated) do
    baseline
    |> Map.keys()
    |> Kernel.++(Map.keys(mutated))
    |> Enum.uniq()
    |> Enum.filter(&(Map.get(baseline, &1) != Map.get(mutated, &1)))
    |> Enum.sort()
  end

  # ------------------------------------------------------------------
  # the guards — 23 to 27
  # ------------------------------------------------------------------

  @doc """
  Guards 23–27 over a whole boundaries document. Raises `RuntimeError` on the first
  violation; returns a map of the population each guard actually scanned.

  The population counts are the **positive control**: a guard reporting zero violations
  is otherwise indistinguishable between *the predicate fired and nothing matched* and
  *the sweep never reached the population*. Only a mutation proves the predicate can
  fire, and those live in `conformance/controls/etcc_boundary_sweep_controls.exs`.

  `check_tree: false` skips guard 26, the only one that is a function of the tree rather
  than of the table. That is how `MCP.Conformance.ETCCRegister` calls it: the ratified
  cadence (`CLAUDE.md`, End-of-Sprint Procedure step 4) puts `lib/`-drift detection at
  the **sprint boundary**, so a `lib/` move by an unrelated ticket must raise a sweep
  finding, not refuse that ticket's register build.
  """
  def check_table!(rows, opts \\ []) when is_list(rows) do
    %{
      guard_23_scanned: check_mechanical_trigger!(rows),
      guard_24_scanned: check_potency!(rows),
      guard_25_scanned: check_conjuncts!(rows),
      guard_26_scanned:
        if(Keyword.get(opts, :check_tree, true), do: check_spec_resolves!(rows), else: :skipped),
      guard_27_scanned: check_spec_prose!(rows)
    }
  end

  @doc """
  Guard 23 — the mechanical trigger, generalised to **any** direction whose live count is
  zero, whatever its verdict.

  Guard 20 in `etcc_register.ex` comprehends over `verdict: "dead"` only. Measured on the
  committed table at `7e935c2`: **10** directions have a live count of zero and a verdict
  of `live` — the L2 dead→live flips, `Types.Tool (encode)`, all five Content subtypes
  `(encode)`, `Server.Connection` and `Transport.Stdio` among them. Strip the `l2` off
  any of those ten and guard 20 does not look at it. §2.3(d) states the trigger on the
  **count**, not on the verdict, so this is the guard that matches the rule as ratified.
  """
  def check_mechanical_trigger!(rows) do
    triggered = Enum.filter(rows, &l2_trigger?/1)

    naked =
      for b <- triggered,
          not match?(%{"ran" => true, "verdict" => v} when is_binary(v), b["l2"]),
          do: b["id"]

    if naked != [] do
      raise "GUARD 23: #{length(naked)} direction(s) have a live count of ZERO and no L2 " <>
              "record (#{Enum.join(naked, ", ")}). §2.3(d) triggers L2 on the COUNT, not on " <>
              "the verdict — a zero-live direction is undecided until L2 has run on it."
    end

    length(triggered)
  end

  @doc """
  Guard 24 — potency. A DEAD verdict additionally requires the mutation to have reddened
  at least one of the direction's own units (§2.3(d)). Otherwise *"nothing broke"* may
  mean *"nothing was broken"*; `MCP.Server.Connection` is the worked case.
  """
  def check_potency!(rows) do
    dead = Enum.filter(rows, &(&1["verdict"] == "dead"))
    impotent = for b <- dead, own_reddened(b) == 0, do: b["id"]

    if impotent != [] do
      raise "GUARD 24: #{length(impotent)} DEAD direction(s) whose mutation reddened NONE of " <>
              "their own units (#{Enum.join(impotent, ", ")}). An impotent mutation establishes " <>
              "nothing in either direction — 'nothing broke' may mean 'nothing was broken'."
    end

    length(dead)
  end

  @doc """
  Guard 25 — both conjuncts. §2.3(d): DEAD requires **both** limbs of L2 — the byte probe
  **and** the alias-aware call-site enumeration. The probe alone cannot establish DEAD,
  because it is server-side and its silence is another proxy.
  """
  def check_conjuncts!(rows) do
    dead = Enum.filter(rows, &(&1["verdict"] == "dead"))

    missing =
      for b <- dead,
          l2 = b["l2"] || %{},
          is_nil(l2["byte_probe"]) or blank?(l2["call_site_enumeration"]),
          do: b["id"]

    if missing != [] do
      raise "GUARD 25: #{length(missing)} DEAD direction(s) are missing an L2 conjunct — a " <>
              "byte_probe or a call_site_enumeration (#{Enum.join(missing, ", ")}). The probe " <>
              "ALONE cannot establish DEAD; §2.3(d) requires both."
    end

    length(dead)
  end

  @doc """
  Guard 26 — the spec resolves. Every `mutation_spec` entry's FROM must occur in its file
  exactly as many times as recorded. A different count means `lib/` moved under the spec,
  so the mutation the verdict rests on can no longer be applied as it was.

  This is the one guard that is a function of the **tree** as well as the table.
  """
  def check_spec_resolves!(rows) do
    entries = Enum.flat_map(rows, fn b -> Enum.map(spec_of(b), &{b["id"], &1}) end)

    bad =
      for {id, e} <- entries,
          actual = occurrences(e["file"], e["from"]),
          actual != e["occurrences"],
          do: "#{id}: #{e["file"]} has #{actual}, spec records #{e["occurrences"]}"

    if bad != [] do
      raise "GUARD 26: #{length(bad)} mutation_spec entry/ies no longer resolve at this tip:\n  " <>
              Enum.join(bad, "\n  ")
    end

    length(entries)
  end

  @doc """
  Guard 27 — the spec agrees with the prose. `mutation_spec` is an ADDITION: the authored
  `mutation` prose stays byte-identical, so AC1's byte-comparison is about the bytes
  MES-81 actually committed and not about a re-serialisation. The duplication is only
  safe if the two cannot drift, so every spec entry must render back to its prose line
  **byte-for-byte**, in order and in count.
  """
  def check_spec_prose!(rows) do
    entries =
      Enum.flat_map(rows, fn b ->
        spec = spec_of(b)
        prose = b["mutation"] || []

        if length(spec) != length(prose) do
          raise "GUARD 27: #{b["id"]} has #{length(spec)} mutation_spec entry/ies against " <>
                  "#{length(prose)} mutation prose line(s). The spec is a reading of the prose; " <>
                  "it may not add to it or drop from it."
        end

        Enum.zip(spec, prose) |> Enum.map(&{b["id"], &1})
      end)

    bad =
      for {id, {e, line}} <- entries, render_prose(e) != line do
        "#{id}:\n     prose    #{inspect(line)}\n     rendered #{inspect(render_prose(e))}"
      end

    if bad != [] do
      raise "GUARD 27: #{length(bad)} mutation_spec entry/ies do not render back to their " <>
              "committed prose:\n  " <> Enum.join(bad, "\n  ")
    end

    length(entries)
  end

  @doc "§2.3(d)'s trigger, as a function of the recorded live count and nothing else."
  def l2_trigger?(b), do: live_count(b) == 0

  @doc "The live count — `reddened_outside_own_and_dead`, per the `procedure` block."
  def live_count(b), do: b["reddened_outside_own_and_dead"] || 0

  defp own_reddened(b), do: (b["reddened_total"] || 0) - (b["reddened_outside_own"] || 0)

  defp spec_of(b), do: b["mutation_spec"] || []

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  # ------------------------------------------------------------------
  # the sweep
  # ------------------------------------------------------------------

  @doc """
  Runs the whole sweep and returns a regenerated boundaries document.

  Options: `:boundaries` (path), `:only` (list of ids), `:tmp` (probe scratch dir),
  `:log` (a 1-arity chatter sink, defaults to `IO.puts/1`).
  """
  def sweep(opts \\ []) do
    log = Keyword.get(opts, :log, &IO.puts/1)
    doc = read_json(Keyword.get(opts, :boundaries, @boundaries))
    rows = Map.fetch!(doc, "boundaries")

    refuse_dirty_lib!()
    scanned = check_table!(rows)
    log.("  guards 23-27 scanned #{inspect(scanned)}")

    tmp = Keyword.get(opts, :tmp, Path.join(System.tmp_dir!(), "etcc-sweep"))
    File.mkdir_p!(tmp)

    log.("  baseline: mix test --seed 0")
    base = run_suite()

    if base.units != [] or base.rc != 0 do
      raise "REFUSING to sweep: the UNMUTATED suite is not green (#{base.summary}). " <>
              "Every count below is a difference from this baseline, so a red baseline " <>
              "makes all 50 of them unreadable."
    end

    log.("  baseline: #{base.summary}")
    base_probe = probe(Path.join(tmp, "probe-baseline.txt"))
    log.("  baseline probe: #{map_size(base_probe)} scenarios")

    selected =
      case Keyword.get(opts, :only) do
        nil -> rows
        ids -> Enum.filter(rows, &(&1["id"] in ids))
      end

    swept =
      selected
      |> Enum.with_index(1)
      |> Enum.map(fn {b, i} ->
        log.("  [#{i}/#{length(selected)}] #{b["id"]}")
        measure(b, doc, base_probe, tmp, log)
      end)

    by_id = Map.new(swept, &{&1["id"], &1})

    doc
    |> Map.put("boundaries", Enum.map(rows, &Map.get(by_id, &1["id"], &1)))
    |> Map.put("control", control_block(doc["control"] || %{}, base, host()))
  end

  # The document-level control block is a MEASUREMENT too, and regenerating the rows
  # without it ships a table whose 50 rows are one population and whose control block is
  # another. Measured on MES-88: the first regeneration left `suite_total: 979` standing
  # over 50 rows taken at 1021 — internally inconsistent, and in exactly the direction
  # nobody would check.
  #
  # `host` is recorded because the population is NOT a function of the tree alone. The
  # suite carries three conformance tests that shell out to `node`, and `test_helper.exs`
  # EXCLUDES them where node or the pinned harness is absent. Measured on MES-88 at one
  # unchanged tip: 994 units with node on PATH, 991 without. `node` is kept as a
  # top-level key beside it because five documents cite it by that name; both come from
  # the one `host/0` call below, so they cannot disagree.
  defp control_block(prior, base, host) do
    Map.merge(prior, %{
      "seed" => 0,
      "suite_total" => suite_total(base.summary),
      "baseline_failures" => length(base.units),
      "node" => host["node"],
      "host" => host,
      "note" => control_note(base.summary, host)
    })
  end

  defp control_note(summary, host) do
    "GENERATED by `mix conformance.sweep` — do not hand-edit. Unmutated control run " <>
      "before the sweep: #{summary}, node #{host["node"]}. Every mutation was " <>
      "applied, measured and REVERTED, and lib/ verified clean against the committed " <>
      "bytes afterwards. The suite total is a fact about THIS run, not a constant of " <>
      "the procedure (§2.3(e) as extended: L1's measurements expire when the unit " <>
      "population moves), and the population is a function of the host as well as the " <>
      "tree — which is what `host` records: #{host["fingerprint"]}. A skip of the " <>
      "end-of-sprint sweep requires that fingerprint to match the host it is being " <>
      "skipped on (CLAUDE.md, End-of-Sprint Procedure step 4, condition (c)); " <>
      "`mix conformance.sweep --host` compares the two and exits nonzero when they " <>
      "differ, when no host is recorded, or when the current one cannot be read."
  end

  defp suite_total(summary) do
    case Regex.run(~r/(\d+) tests?,/, summary || "") do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp node_version do
    case System.find_executable("node") do
      nil ->
        "absent"

      _ ->
        case System.cmd("node", ["--version"], stderr_to_stdout: true) do
          {v, 0} -> String.trim(v)
          _ -> "absent"
        end
    end
  end

  defp measure(b, doc, base_probe, tmp, log) do
    spec = spec_of(b)
    backups = apply!(spec)

    run =
      try do
        run_suite()
      after
        revert!(backups)
      end

    own = MapSet.new(b["own_tests"] || [])
    outside = Enum.reject(run.units, &(file_of(&1) in own))

    live = Enum.reject(outside, live_column_excluded(doc))

    l2 =
      if live == [] do
        log.("      live count 0 -> L2 fires (MECHANICAL, §2.3(d))")
        backups2 = apply!(spec)

        {moved, ran} =
          try do
            mutated = probe(Path.join(tmp, "probe-mutated.txt"))
            {scenarios_moved(base_probe, mutated), map_size(base_probe)}
          after
            revert!(backups2)
          end

        merge_l2(b, moved, ran)
      else
        b["l2"]
      end

    verdict = verdict_for(live, l2)

    b
    |> Map.merge(%{
      "mutation_spec" => spec,
      "suite_summary" => run.summary,
      "unlocated_failures" => run.unlocated,
      "reddened_total" => length(run.units),
      "reddened_by_module" => run.units |> Enum.map(&module_of/1) |> Enum.frequencies(),
      "reddened_outside_own" => length(outside),
      "reddened_outside_own_and_dead" => length(live),
      "live_units" => Enum.sort(live),
      "l2" => l2,
      "verdict" => verdict,
      "established_by" => if(live == [], do: "L2", else: "L1")
    })
    |> tap(fn r ->
      log.(
        "      #{r["suite_summary"]} | outside own #{r["reddened_outside_own"]} | " <>
          "live #{r["reddened_outside_own_and_dead"]} | #{r["verdict"]} (#{r["established_by"]})"
      )
    end)
  end

  # L2's conjunct (ii) is authored, not derived — the module keeps what is recorded and
  # replaces only what it measured, the byte probe. §2.3(d): L2 can only turn DEAD into
  # LIVE, so a probe that moves a scenario overrides a recorded `dead`, and a probe that
  # moves nothing never overrides a recorded `live`.
  defp merge_l2(b, moved, scenarios_run) do
    prior = b["l2"] || %{}

    probe_block =
      (prior["byte_probe"] || %{})
      |> Map.merge(%{
        "script" => @probe,
        "scenarios_run" => scenarios_run,
        "scenarios_moved" => moved
      })

    prior
    |> Map.merge(%{
      "ran" => true,
      "trigger" => "live count is zero",
      "byte_probe" => probe_block,
      "verdict" => if(moved != [], do: "live", else: prior["verdict"] || "dead")
    })
  end

  # The third exclusion, by DIRECTORY (§2.3(d) as amended on MES-137,
  # `[authored 29618 | ratified 29619]`): L1 counts units that EXECUTE `lib/`, never units
  # that READ it. `test/conformance/` is the population gate 1 already rules out as
  # instrument tests, and those units read `lib/` as cited bytes — so a mutation that only
  # SHIFTS lines reddens them with no path to the wire in sight. Measured on MES-137:
  # `adjudications_test.exs:1715` flipped `Error (encode)` dead -> live that way.

  @doc """
  The live column's directory exclusions, as committed in the boundaries document.

  Refuses an entry that does not end in `/`: a bare `test/conformance` would also match
  `test/conformance_x/`, silently widening the exclusion to a directory nobody ruled on.
  """
  def live_column_prefixes!(doc) do
    prefixes = doc["live_column_excluded_prefixes"] || []

    for p <- prefixes, not (is_binary(p) and p != "/" and String.ends_with?(p, "/")) do
      raise "REFUSING live_column_excluded_prefixes entry #{inspect(p)}: an entry must be " <>
              "a directory ending in \"/\", or it matches every sibling sharing its prefix."
    end

    prefixes
  end

  @doc "Whether a unit (`file:line (Module)`) lies under one of the directory `prefixes`."
  def excluded_by_prefix?(unit, prefixes),
    do: Enum.any?(prefixes, &String.starts_with?(file_of(unit), &1))

  # All three live-column exclusions, as one predicate over a unit.
  defp live_column_excluded(doc) do
    files = MapSet.new(doc["live_column_excluded_files"] || [])
    units = MapSet.new(doc["live_column_excluded_units"] || [])
    prefixes = live_column_prefixes!(doc)

    fn u -> file_of(u) in files or u in units or excluded_by_prefix?(u, prefixes) end
  end

  defp verdict_for([], l2), do: (l2 || %{})["verdict"] || "dead"
  defp verdict_for(_live, _l2), do: "live"

  defp file_of(unit), do: unit |> String.split(":") |> hd()
  defp module_of(unit), do: unit |> String.split(["(", ")"]) |> Enum.at(1)

  defp refuse_dirty_lib! do
    {out, 0} = System.cmd("git", ["status", "--porcelain", "--", "lib/"])

    if String.trim(out) != "" do
      raise "REFUSING to sweep: lib/ is not clean.\n#{out}" <>
              "The sweep mutates lib/ in place and reverts to the committed bytes, so a " <>
              "dirty lib/ makes every measurement a claim about a tree nobody can name."
    end

    :ok
  end

  # ------------------------------------------------------------------
  # --check
  # ------------------------------------------------------------------

  @doc """
  Diffs a regenerated document against a committed one on the VERDICT fields only, and
  names the ET-CC rows each moved direction would move.

  Returns `%{verdict_diffs: [...], measurement_deltas: [...]}`. A non-empty
  `verdict_diffs` is AC5's loud failure; `measurement_deltas` is §2.3(e)'s stated delta
  and is reported, never raised on.
  """
  def check(generated, committed, opts \\ []) do
    old = Map.new(Map.fetch!(committed, "boundaries"), &{&1["id"], &1})
    register = Keyword.get(opts, :register, @register)

    rows =
      case File.read(register) do
        {:ok, bin} -> Jason.decode!(bin)["rows"] || []
        _ -> []
      end

    verdict_diffs =
      for b <- Map.fetch!(generated, "boundaries"),
          o = Map.get(old, b["id"], %{}),
          d = field_diffs(o, b, @verdict_fields ++ ["l2.ran", "l2.verdict"]),
          d != [] do
        %{"id" => b["id"], "fields" => d, "et_cc_rows" => et_cc_rows(rows, b["id"])}
      end

    measurement_deltas =
      for b <- Map.fetch!(generated, "boundaries"),
          o = Map.get(old, b["id"], %{}),
          d = field_diffs(o, b, @measurement_fields),
          d != [],
          do: %{"id" => b["id"], "fields" => Enum.map(d, & &1["field"])}

    %{verdict_diffs: verdict_diffs, measurement_deltas: measurement_deltas}
  end

  defp field_diffs(old, new, fields) do
    fields
    |> Enum.map(&%{"field" => &1, "was" => dig(old, &1), "now" => dig(new, &1)})
    |> Enum.reject(&(&1["was"] == &1["now"]))
  end

  defp dig(map, field) do
    case String.split(field, ".") do
      [f] -> Map.get(map, f)
      path -> get_in(map, path)
    end
  end

  defp et_cc_rows(rows, id) do
    for r <- rows,
        r["label"] == "ET-CC",
        is_list(r["boundary"]),
        id in r["boundary"],
        do: r["key"]
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()
end

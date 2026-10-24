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
    `live_units`, and the L2 byte probe's `scenarios_run` / `scenarios_moved`. Every one
    of these is in `@measurement_fields`, so every one is REPORTED by `--check`. Until
    MES-174 the two byte-probe fields were listed here and reported nowhere, and the
    probe went blind (MES-161) with neither section of the MES-171 sweep showing it.
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

  alias MCP.Conformance.ExUnitRows

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
  #
  # NINE since MES-174: the byte probe's `scenarios_moved` and `scenarios_run` are
  # measured too, and they collapsed to `[]` on seven LIVE rows in the MES-171 sweep while
  # appearing in neither section. They are MEASUREMENT fields, not verdict fields: the
  # verdict they feed, `l2.verdict`, is already compared, and comparing the probe's bytes
  # as verdicts would report every re-baseline of the probe (this ticket's included) as
  # drift. Their re-baseline is made legible by `control.probe` instead.
  @measurement_fields ~w(suite_summary reddened_total reddened_by_module
                         reddened_outside_own reddened_outside_own_and_dead live_units
                         unlocated_failures
                         l2.byte_probe.scenarios_moved l2.byte_probe.scenarios_run)

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
  the committed table: `docs/procedure/end-of-sprint.md`, step 4, condition (c).

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

  @doc """
  Guard 27's positivity predicate: a recorded mutation has at least one site.

  `occurrences: 0` is a mutation that replaces nothing, so it reddens nothing and
  establishes nothing, LIVE or DEAD. Guard 24 cannot see it on a LIVE row, and guard 26
  passes it whenever FROM is indeed absent. Shared by `check_spec_prose!/1`, `apply!/1`
  and `emit_spec/1`, so no caller can apply or emit a zero-site mutation (MES-173).
  """
  def positive_occurrences?(entry),
    do: is_integer(entry["occurrences"]) and entry["occurrences"] > 0

  @doc """
  `--emit-spec`'s reading of a boundaries document. Returns the document with every row's
  `mutation_spec` completed from its prose, or raises before anything is written.

  An EXISTING entry — index `i` below the length of the row's input `mutation_spec` — is
  carried over verbatim and never re-derived. Re-counting it is MES-173's hazard: it
  turns guard 26 green over a tree that moved, while the verdict the entry supports has
  expired (MES-171's Meta widened to 9 sites, Plug's error entry a 0-site no-op). So,
  in order:

    1. the existing prefix must render back to its prose and record a positive count
       (guard 27, on the prefix);
    2. each existing entry's FROM must still occur as many times as recorded, or the
       emission refuses under GUARD 26 and names the re-anchor procedure.

  Only NEW slots, prose indices at or beyond the existing prefix, are derived, with
  `replace: "all"`. The completed document then passes guards 27 and 26 in full, so a new
  slot that derives zero is refused too.

  Stated residual: this protects the input as presented, not its history. Deleting a
  row's `mutation_spec`, or hand-editing a recorded count, then emitting, still derives
  afresh (PM ruling 34227, Q2).
  """
  def emit_spec(%{"boundaries" => rows} = doc) do
    rows |> Enum.map(&existing_prefix/1) |> check_spec_prose!()
    refuse_recount!(rows)

    emitted =
      Enum.map(rows, fn b ->
        spec = spec_of(b)
        new = derive_spec(%{"mutation" => Enum.drop(b["mutation"] || [], length(spec))})
        Map.put(b, "mutation_spec", spec ++ new)
      end)

    check_spec_prose!(emitted)
    check_spec_resolves!(emitted)
    %{doc | "boundaries" => emitted}
  end

  # The row as guard 27 should judge its existing entries: the prose cut to the spec's
  # length, so a prose line appended for a new slot is not a mismatch. A spec LONGER than
  # its prose keeps the whole prose, and guard 27's length check refuses it.
  defp existing_prefix(b),
    do: Map.put(b, "mutation", Enum.take(b["mutation"] || [], length(spec_of(b))))

  defp refuse_recount!(rows) do
    drifted =
      for b <- rows,
          {e, i} <- Enum.with_index(spec_of(b), 1),
          actual = occurrences(e["file"], e["from"]),
          actual != e["occurrences"],
          do:
            {b["id"],
             "#{b["id"]} entry #{i}, #{e["file"]}: recorded #{e["occurrences"]}, tree has #{actual}"}

    if drifted != [] do
      ids = drifted |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

      raise "GUARD 26: --emit-spec refuses to re-count #{length(drifted)} existing " <>
              "mutation_spec entry/ies:\n  " <>
              Enum.map_join(drifted, "\n  ", &elem(&1, 1)) <>
              "\nRe-counting turns guard 26 green while the verdict it supports has expired." <>
              "\nRe-anchor instead (MES-171): name the behaviour the mutation targets, edit the" <>
              "\nmutation prose and its mutation_spec entry together by hand, then measure with\n  " <>
              Enum.map_join(ids, "\n  ", &"mix conformance.sweep --check --only #{inspect(&1)}") <>
              "\n(docs/procedure/gate-8.md, 'Repairing a red GUARD 26')."
    end
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
  mutate something else. An entry recording no site at all is refused first, by guard
  27's predicate: a zero-site spec would "apply" cleanly and change nothing (MES-173).
  """
  def apply!(spec) do
    spec |> Enum.with_index(1) |> Enum.each(&resolve!/1)

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

  defp resolve!({%{"file" => f, "from" => from} = e, i}) do
    n = e["occurrences"]

    unless positive_occurrences?(e) do
      raise "GUARD 27: mutation_spec entry #{i}, #{f}: occurrences #{inspect(n)} is not a " <>
              "positive integer, and a zero-site mutation is a no-op. Nothing was applied."
    end

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
  Runs `mix test --seed 0` and returns `%{summary:, units:, unlocated:, rows_total:, rc:}`.

  `units` are `"file:line (Module)"` strings — the register key shape — one per red
  runtime test (failed or `setup_all`-invalidated), multiplicity kept. They are read off
  the ROWS `MCP.Conformance.ExUnitRows` writes, never off the CLI transcript (MES-208):
  the run attaches that formatter by naming a rows file in `MCP_ETCC_ROWS` for this
  `mix test` alone, and reads the file back. Stdout is read for ExUnit's summary line
  only, as the independent witness GUARD 34 reconciles the rows against.

  Every run passes `census!/3` before anything is returned, so every caller — the sweep
  baseline, every `measure/6`, `record_host!/1`, `--disambiguate` and the controls —
  refuses a run whose rows do not account for every test.

  Options: `:seed` (default 0), `:rows` (the rows file; defaults to a fresh path under
  the system tmp dir) and `:population` (the baseline's row total, which a mutated run
  must reproduce; `nil` skips that one kind). The transcript is kept beside the rows
  file as `<rows>.log`, so a refusal can be read after the fact.
  """
  def run_suite(opts \\ []) do
    rows_path = Keyword.get_lazy(opts, :rows, &fresh_rows_path/0)
    File.mkdir_p!(Path.dirname(rows_path))
    File.rm(rows_path)

    {out, rc} =
      System.cmd("mix", ["test", "--seed", Integer.to_string(Keyword.get(opts, :seed, 0))],
        stderr_to_stdout: true,
        env: [{ExUnitRows.env_path_var(), rows_path}]
      )

    File.write!(rows_path <> ".log", out)
    artefact = read_artefact(rows_path)
    census!(out, artefact, Keyword.get(opts, :population))
    read_run(out, artefact) |> Map.put(:rc, rc)
  end

  defp fresh_rows_path do
    Path.join([
      System.tmp_dir!(),
      "etcc-sweep",
      "rows-#{System.unique_integer([:positive])}.json"
    ])
  end

  @doc """
  Reads the rows file `run_suite/1` named. `:missing` when it is absent or unreadable —
  `ExUnitRows` rescues its own write error so as never to take the suite down, and this
  is where that becomes GUARD 34's `no_artefact` rather than an empty run.
  """
  def read_artefact(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, %{"rows" => rows} = artefact} when is_list(rows) <- Jason.decode(bytes) do
      artefact
    else
      _ -> :missing
    end
  end

  # The two statuses that are a red unit. `invalid` is a test whose module's `setup_all`
  # failed: it never ran, but the mutation broke it, and the PO ruled (MES-208 `34141`)
  # that every test is recorded — so it is keyed like any other red (MES-150).
  @red ~w(failed invalid)

  @doc """
  The run, read from its transcript and its rows. Pure, so `census/3` and the unit tests
  can reach it without a suite run.

  `unlocated` counts red rows with no file or line. GUARD 34 refuses any run where it is
  not zero, so a measured row always records 0; the field is kept for the table's
  schema until the regeneration ticket decides it (MES-208 R5).
  """
  def read_run(out, artefact) do
    rows = rows_of(artefact)

    {located, unlocated} =
      rows |> Enum.filter(&(&1["status"] in @red)) |> Enum.split_with(&located?/1)

    %{
      summary: summary_line(String.split(out, "\n")),
      units: Enum.map(located, &unit_key/1),
      unlocated: length(unlocated),
      rows_total: length(rows)
    }
  end

  defp rows_of(%{"rows" => rows}) when is_list(rows), do: rows
  defp rows_of(_), do: []

  defp located?(row), do: is_binary(row["file"]) and is_integer(row["line"])

  # The ET-CC unit key. `file` is relative to the checkout and `line` is the DECLARATION
  # line — `tags.file`/`tags.line`, the same pair ExUnit's CLI location line rendered,
  # so a key taken here is byte-identical to one the transcript parser took (measured on
  # MES-208: the old parser's 99 Meta keys are a sub-multiset of the 176 taken here).
  defp unit_key(row), do: "#{row["file"]}:#{row["line"]} (#{row["module"]})"

  # ------------------------------------------------------------------
  # GUARD 34 — the census: every test recorded, or refuse
  # ------------------------------------------------------------------

  # Any line shaped like ExUnit's summary — counts, then failures. Broader than
  # `@summary_rx` on purpose: kind `summary_count` exists to refuse a FORGED summary a
  # test prints, and a forgery need not be shaped exactly like the real thing.
  @summary_shape ~r/\A(?:\d+ \w+, )+\d+ failures?\b/

  # ANSI SGR escapes, removed before any line is matched as a summary. This is the
  # normalisation `ExUnitRows.parse_summary/1` applies before IT matches, so the count
  # and the reconciliation witness read one language (MES-208 correction round 1, CR F1
  # `34182`: a coloured forgery was read as the summary by the witness while the count,
  # matching raw bytes, did not see it).
  @ansi ~r/\e\[[0-9;]*m/

  @census_kinds ~w(no_artefact summary summary_count incomplete cross_check collision
                   unlocated units population)a

  @doc "GUARD 34's kinds, in the order `census/3` reports them."
  def census_kinds, do: @census_kinds

  @doc """
  GUARD 34. Every violation, as `{kind, detail}`, `[]` when the rows account for every
  test. Pure.

  Until MES-208 the sweep parsed the CLI transcript for failure headers, and dropped
  every failure numbered 100 or above (ExUnit stops padding the counter there,
  `formatter.ex:719-729`) and every `setup_all`-invalidated test (whose header has no
  `test` in it) — silently, which is the S8-13 error. This guard is what makes a gap
  in the measurement LOUD:

    * `no_artefact` — the formatter wrote no readable rows file;
    * `summary` — `ExUnitRows.reconcile/2` disagrees with ExUnit's own summary (per
      type, failures, invalid, skipped, excluded), or there is no summary line. Totals
      are re-derived from the rows here, never taken from the file's own `totals`;
    * `summary_count` — not exactly one summary-shaped line, so a test that prints one
      cannot supply the witness;
    * `incomplete` — the run block does not say `complete`;
    * `cross_check` — the `module_finished` witness disagrees, or is absent;
    * `collision` — two rows on one key;
    * `unlocated` — a red row with no file or line;
    * `units` — the red units derived are not summary failures + invalid, which holds
      the projection from rows to units that `reconcile/2` cannot see;
    * `population` — a mutated run whose row total is not the baseline's.
  """
  def census(out, :missing, _population),
    do: [{:no_artefact, "the formatter wrote no readable rows file"}] ++ summary_count(out)

  def census(out, artefact, population) do
    rows = rows_of(artefact)
    run = read_run(out, artefact)
    meta = artefact["run"] || %{}
    reconciled = ExUnitRows.reconcile(out, ExUnitRows.derive_totals(rows))

    [
      summary_violation(reconciled),
      summary_count(out),
      if(meta["complete"] != true,
        do: [{:incomplete, "run.complete is #{inspect(meta["complete"])}"}],
        else: []
      ),
      cross_check_violation(meta["module_cross_check"]),
      collision_violation(ExUnitRows.key_collisions(rows)),
      if(run.unlocated > 0,
        do: [{:unlocated, "#{run.unlocated} red row(s) with no file or line"}],
        else: []
      ),
      units_violation(out, run),
      population_violation(population, run.rows_total)
    ]
    |> List.flatten()
  end

  @doc "Raises one `GUARD 34: <kind> — <detail>` line per violation; `:ok` when there are none."
  def census!(out, artefact, population) do
    case census(out, artefact, population) do
      [] ->
        :ok

      violations ->
        raise Enum.map_join(violations, "\n", fn {kind, detail} ->
                "GUARD 34: #{kind} — #{detail}"
              end) <>
                "\nREFUSING this run: its rows do not account for every test (MES-208)."
    end
  end

  defp summary_violation(%{"ok" => true}), do: []

  defp summary_violation(%{"error" => error}), do: [{:summary, error}]

  defp summary_violation(%{"checks" => checks}) do
    bad = for c <- checks, not c["ok"], do: "#{c["name"]} exunit=#{c["exunit"]} rows=#{c["rows"]}"
    [{:summary, "rows disagree with ExUnit's summary: " <> Enum.join(bad, "; ")}]
  end

  defp summary_count(out) do
    n = out |> String.split("\n") |> Enum.count(&summary_shaped?/1)
    if n == 1, do: [], else: [{:summary_count, "#{n} summary-shaped line(s), not exactly 1"}]
  end

  # A line is counted when the reconciliation witness itself would read it as a summary
  # — `ExUnitRows.parse_summary/1` applied to that line alone, so its grammar and its
  # ANSI normalisation are reached rather than copied, and every line it accepts is
  # counted by construction — OR when the broader `@summary_shape` matches it after the
  # same ANSI normalisation. The second disjunct can only over-count, and an over-count
  # fails closed.
  defp summary_shaped?(line) do
    match?({:ok, _}, ExUnitRows.parse_summary(line)) or
      Regex.match?(@summary_shape, plain(line))
  end

  defp plain(line), do: line |> String.replace(@ansi, "") |> String.trim()

  defp cross_check_violation(%{"disagreements" => []}), do: []

  defp cross_check_violation(%{"disagreements" => d}) when is_list(d),
    do: [{:cross_check, "#{length(d)} module_finished disagreement(s)"}]

  defp cross_check_violation(_),
    do: [{:cross_check, "the run block carries no module cross-check"}]

  defp collision_violation([]), do: []
  defp collision_violation(c), do: [{:collision, "#{length(c)} key(s) on more than one row"}]

  defp units_violation(out, run) do
    with {:ok, %{"failures" => f, "invalid" => i}} <- ExUnitRows.parse_summary(out),
         n when n != f + i <- length(run.units) do
      [{:units, "#{n} red unit(s) derived, summary says #{f} failures + #{i} invalid"}]
    else
      _ -> []
    end
  end

  defp population_violation(nil, _total), do: []
  defp population_violation(n, n), do: []

  defp population_violation(want, got),
    do: [{:population, "#{got} rows, the unmutated baseline had #{want}"}]

  # The trailing clauses are NOT decoration. ExUnit appends `(N excluded)` when
  # `test_helper.exs` excludes the three `:requires_live_harness` tests — which is
  # exactly what happens on a host without `node` — and an anchored pattern that stops
  # at `failures` does not match that line, so the summary came back `nil` and the sweep
  # recorded a table with NO population in it. Measured on MES-88 (`S8-18`): the one
  # transcript shape the host axis actually produces was the one shape this could not
  # read. The clauses are optional and the prefix is unchanged, so a transcript from a
  # complete host parses exactly as it did before.
  @summary_rx ~r/\A\d+ doctests?, \d+ tests?, \d+ failures?(, \d+ invalid)?( \(\d+ \w+\))*\z/

  @doc "ExUnit's summary line, in the string form `suite_summary` records."
  def summary_line(lines) do
    lines
    |> Enum.map(&plain/1)
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

  `script` defaults to the committed probe. It is a parameter so that the controls can
  drive the sweep with the BLIND probe from git and show the baseline refusal firing at
  its call site, not merely existing (MES-174, W1).
  """
  def probe(out_path, script \\ @probe) do
    File.rm(out_path)
    {_out, _rc} = System.cmd("mix", ["run", script, out_path], stderr_to_stdout: true)

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

  # The probe scenarios whose reply is DESIGNED to be a JSON-RPC error, with the code it
  # must carry. Every other scenario whose value is a JSON-RPC response must be a result.
  # Declared, never inferred: an exception the predicate worked out for itself would be
  # the loosening MES-174's ruling (`31975` item 1) forbids.
  @probe_expected_errors %{"error response (unknown method)" => -32_601}

  # The probe scenarios that never pass through dispatch, so their value is NOT a
  # JSON-RPC reply — declared BY NAME (MES-174 correction round 1, CR F1, `31987`). Until
  # that round `:reached` exempted every non-reply value by its CLASS, so a dispatched
  # scenario that stopped producing a reply at all (`Dispatch.dispatch/3` can return
  # `{:noreply, state}`, which the probe writes as `inspect/1` of it) passed silently. A
  # declared name that DOES come back as a reply is refused too, so the list cannot go
  # stale without saying so.
  @probe_not_a_response [
    "SSE frame of a notification",
    "decode_message of a wire error",
    "decode_message of a wire result"
  ]

  @doc "The probe scenarios whose baseline reply must be a JSON-RPC error, and its code."
  def probe_expected_errors, do: @probe_expected_errors

  @doc "The probe scenarios whose baseline value must NOT be a JSON-RPC reply."
  def probe_not_a_response, do: @probe_not_a_response

  @doc """
  What one probe value is: `:result`, `{:error, code}` for a JSON-RPC reply, or
  `:not_a_response` for a value that is not a JSON-RPC reply at all (the SSE frame and
  the two `decode_message` scenarios, which never pass through dispatch).

  Values are stored as `inspect/1` of the scenario's output, so the string literal is
  read back with `Code.string_to_quoted/1` — parsing, never evaluation.
  """
  def classify_probe_value(value) do
    with {:ok, bytes} when is_binary(bytes) <- Code.string_to_quoted(value),
         {:ok, %{"jsonrpc" => "2.0"} = reply} <- Jason.decode(bytes) do
      case reply do
        %{"result" => _} -> :result
        %{"error" => %{"code" => code}} -> {:error, code}
        _ -> :not_a_response
      end
    else
      _ -> :not_a_response
    end
  end

  @doc """
  The violations of a sighted baseline, `[]` when there are none. Two conjuncts, each
  independent of the other (MES-174, ratified in `31975`):

    * `:distinct` — no two scenarios share bytes. Scenarios that collide can only move
      together, so the probe cannot say which path a mutation reached. This is the
      general form of the MES-161 blinding: 12 dispatch scenarios, one shared `-32602`.
    * `:reached` — every scenario's class is the DECLARED one: a scenario named in
      `probe_expected_errors/0` is a JSON-RPC error with its code, one named in
      `probe_not_a_response/0` is not a JSON-RPC reply, and EVERY other scenario is a
      `result`. A declared scenario absent from the baseline is a violation too. This
      catches a probe that is blind on ONE scenario, which `:distinct` cannot see —
      including a dispatched one that produced no reply at all.
  """
  def probe_baseline_violations(baseline) do
    groups =
      baseline
      |> Enum.group_by(fn {_k, v} -> v end, fn {k, _v} -> k end)
      |> Map.values()
      |> Enum.filter(&(length(&1) > 1))
      |> Enum.map(&Enum.sort/1)
      |> Enum.sort()

    unreached =
      for {k, v} <- Enum.sort(baseline),
          got = classify_probe_value(v),
          want = expected_class(k),
          got != want,
          do: {k, got, want}

    declared = Map.keys(@probe_expected_errors) ++ @probe_not_a_response
    absent = for k <- declared, not Map.has_key?(baseline, k), do: k

    [{:distinct, groups}, {:reached, unreached ++ Enum.map(absent, &{&1, :absent, :declared})}]
    |> Enum.reject(fn {_c, found} -> found == [] end)
  end

  defp expected_class(k) do
    case Map.fetch(@probe_expected_errors, k) do
      {:ok, code} -> {:error, code}
      :error -> if k in @probe_not_a_response, do: :not_a_response, else: :result
    end
  end

  @doc """
  Refuses a BLIND probe baseline — `probe_baseline_violations/1` non-empty. Returns the
  counts it scanned, as the positive control.

  The refusal lives in the SWEEP, on the UNMUTATED baseline only. The probe also runs
  under mutation, where scenarios collapsing together is a legitimate measurement; only
  the baseline must be sighted, because every `scenarios_moved` is a difference from it.
  """
  def check_probe_baseline!(baseline) do
    case probe_baseline_violations(baseline) do
      [] ->
        classes = baseline |> Map.values() |> Enum.map(&classify_probe_value/1)

        %{
          scenarios: map_size(baseline),
          distinct: baseline |> Map.values() |> Enum.uniq() |> length(),
          results: Enum.count(classes, &(&1 == :result)),
          expected_errors: Enum.count(classes, &match?({:error, _}, &1)),
          not_a_response: Enum.count(classes, &(&1 == :not_a_response))
        }

      violations ->
        raise "REFUSING to sweep: the L2 probe's UNMUTATED baseline is blind.\n" <>
                Enum.map_join(violations, "\n", &describe_violation(&1, baseline)) <>
                "\nEvery L2 silence measured against this baseline would be vacuous — a " <>
                "mutation behind these scenarios cannot move a byte the probe can tell " <>
                "apart (MES-174)."
    end
  end

  defp describe_violation({:distinct, groups}, baseline) do
    "  [distinct] #{length(groups)} group(s) of scenarios share bytes:\n" <>
      Enum.map_join(groups, "\n", fn [k | _] = g ->
        "    #{length(g)} x #{String.slice(baseline[k], 0, 120)}: " <>
          Enum.join(g, ", ")
      end)
  end

  defp describe_violation({:reached, rows}, _baseline) do
    "  [reached] #{length(rows)} scenario(s) did not reach the path they probe:\n" <>
      Enum.map_join(rows, "\n", fn {k, got, want} ->
        "    #{k}: got #{inspect(got)}, want #{inspect(want)}"
      end)
  end

  @doc """
  The generated `control.probe` record: which script, how many scenarios, how many
  distinct values, and the sha256 of the baseline probe file. A re-baseline of the probe
  shows up in the table's diff as this ONE changed record, rather than as an unexplained
  cause behind every `scenarios_moved` that moved with it.
  """
  def probe_record(script, file, baseline) do
    %{
      "script" => script,
      "scenarios" => map_size(baseline),
      "distinct" => baseline |> Map.values() |> Enum.uniq() |> length(),
      "sha256" => :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower)
    }
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
  than of the table. That is how `MCP.Conformance.ETCCRegister` calls it. Anchor drift
  is **DoD gate 8** (`mix conformance.sweep --verify`; when it applies is
  `docs/procedure/gate-8.md`), so the `lib/` move is refused on the ticket that makes
  it; liveness stays at the sprint boundary (`docs/procedure/end-of-sprint.md`, step 4).
  Guard 26 stays out of the register build so that each red has one meaning: a register
  refusal is a defect in the table, and a gate-8 GUARD 26 is a `lib/` move.
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

  Widened by MES-173 (PM ruling 34227, Q1): every entry's `occurrences` must also be a
  **positive integer** (`positive_occurrences?/1`), whatever the row's verdict. A zero is
  a function of the table alone, so it belongs to this table-local guard, which the
  register build runs too, and not to guard 26, which it skips. Checked before the
  render comparison, over every entry.
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

    siteless =
      for {{id, {e, _line}}, i} <- index_within_rows(entries), not positive_occurrences?(e) do
        "#{id} entry #{i}, #{e["file"]}: occurrences #{inspect(e["occurrences"])}"
      end

    if siteless != [] do
      raise "GUARD 27: #{length(siteless)} mutation_spec entry/ies do not record a " <>
              "positive integer occurrences:\n  " <>
              Enum.join(siteless, "\n  ") <>
              "\nA zero-site mutation is a no-op: it reddens nothing and establishes nothing, " <>
              "LIVE or DEAD."
    end

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

  @scanned_keys ~w(guard_23_scanned guard_24_scanned guard_25_scanned guard_26_scanned
                   guard_27_scanned)a

  @doc """
  The population refusal (MES-179) — `--verify`'s positive control, made a refusal.

  `scanned` is `check_table!/2`'s return and `total` the table's `mutation_spec` entry
  count, which the caller counts from the document itself, outside the guards. Three
  limbs, checked in this order, each with its own message:

    * **shape** — each of the five keys `guard_23_scanned` … `guard_27_scanned` is present
      and a non-negative integer. A missing key, a negative value, a non-integer or
      `:skipped` refuses, naming the key and its value. With the zero limb, every count
      must be a positive integer (MES-179 correction round 1, F3).
    * **zero** — any scanned count of `0`. A guard that scanned nothing reports no
      violation either, so an emptied table passed with every count at 0 (MES-175 RF), and
      a table with no DEAD row passed with 24 and 25 at 0. **Residual, by design:** a
      future table that legitimately has no DEAD row refuses here until this code changes.
    * **equality** — `guard_26_scanned` or `guard_27_scanned` other than `total`, each
      half checked on its own. Today's scans `flat_map` over every entry, so no table can
      fire this limb: it is entailed by the scan as written, and is a tripwire against a
      future scan that skips or short-counts.

  **Residual:** a table short by whole rows that leaves no count at zero passes all three.
  Only a floor from outside the table would see it, and nothing compares the table with
  its committed history.

  Only the task's `--verify` calls this. `MCP.Conformance.ETCCRegister` skips guard 26 by
  design, so its `:skipped` is not a refusal there.
  """
  def check_population!(scanned, total) when is_map(scanned) and is_integer(total) do
    malformed =
      for k <- @scanned_keys, not well_formed?(Map.fetch(scanned, k)) do
        "#{k} #{shown(Map.fetch(scanned, k))}"
      end

    if malformed != [] do
      raise "POPULATION: --verify refuses a malformed scan: #{Enum.join(malformed, ", ")}. " <>
              "Each of guard_23_scanned .. guard_27_scanned must be present and a positive " <>
              "integer."
    end

    vacuous = for {k, v} <- Enum.sort(scanned), v == 0, do: "#{k} 0"

    if vacuous != [] do
      raise "POPULATION: --verify refuses a vacuous scan: #{Enum.join(vacuous, ", ")}. A guard " <>
              "that scanned nothing also reports no violation (MES-175 RF). A table with no " <>
              "DEAD direction refuses here too, by design (MES-179 Q2): that is a code change, " <>
              "not a table edit."
    end

    equal_26? = scanned.guard_26_scanned == total
    equal_27? = scanned.guard_27_scanned == total

    short =
      for {k, false} <- [guard_26_scanned: equal_26?, guard_27_scanned: equal_27?] do
        "#{k} #{inspect(scanned[k])}"
      end

    if short != [] do
      raise "POPULATION: #{Enum.join(short, ", ")} is not the table's mutation_spec total " <>
              "#{total}; the guard did not reach every entry."
    end

    scanned
  end

  defp well_formed?({:ok, n}), do: is_integer(n) and n >= 0
  defp well_formed?(:error), do: false

  defp shown(:error), do: "absent"
  defp shown({:ok, v}), do: inspect(v)

  defp shown_pair({k, v}), do: "#{k}: #{inspect(v)}"

  @doc "§2.3(d)'s trigger, as a function of the recorded live count and nothing else."
  def l2_trigger?(b), do: live_count(b) == 0

  @doc "The live count — `reddened_outside_own_and_dead`, per the `procedure` block."
  def live_count(b), do: b["reddened_outside_own_and_dead"] || 0

  defp own_reddened(b), do: (b["reddened_total"] || 0) - (b["reddened_outside_own"] || 0)

  defp spec_of(b), do: b["mutation_spec"] || []

  # `{id, pair}` tuples numbered 1-based within their own row, for messages.
  defp index_within_rows(entries) do
    entries
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(&Enum.with_index(&1, 1))
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  # ------------------------------------------------------------------
  # the sweep
  # ------------------------------------------------------------------

  @doc """
  Runs the whole sweep and returns a regenerated boundaries document.

  Options: `:boundaries` (path), `:only` (list of ids), `:tmp` (probe scratch dir),
  `:log` (a 1-arity chatter sink, defaults to `IO.puts/1`), `:probe` (the probe script,
  defaulting to the committed one — the controls pass the blind one from git).

  The baseline PROBE runs before the baseline SUITE, and `check_probe_baseline!/1`
  refuses a blind one (MES-174): a probe that cannot see is refused in seconds, not
  after a full unmutated `mix test`.
  """
  def sweep(opts \\ []) do
    log = Keyword.get(opts, :log, &IO.puts/1)
    doc = read_json(Keyword.get(opts, :boundaries, @boundaries))
    rows = Map.fetch!(doc, "boundaries")

    refuse_dirty_lib!()
    scanned = check_table!(rows)
    # Keys in sorted order, so the line does not depend on atom-table order (OTP prints
    # a small atom-keyed map in atom-index order, which MES-179's new code shifted).
    log.("  guards 23-27 scanned %{#{Enum.map_join(Enum.sort(scanned), ", ", &shown_pair/1)}}")

    tmp = Keyword.get(opts, :tmp, Path.join(System.tmp_dir!(), "etcc-sweep"))
    File.mkdir_p!(tmp)

    script = Keyword.get(opts, :probe, @probe)
    base_file = Path.join(tmp, "probe-baseline.txt")
    base_probe = probe(base_file, script)
    probe_scanned = check_probe_baseline!(base_probe)
    log.("  baseline probe: sighted #{inspect(probe_scanned)}")
    probe_rec = probe_record(script, base_file, base_probe)

    log.("  baseline: mix test --seed 0")
    base = run_suite(rows: Path.join(tmp, "rows.json"))

    if base.units != [] or base.rc != 0 do
      raise "REFUSING to sweep: the UNMUTATED suite is not green (#{base.summary}). " <>
              "Every count below is a difference from this baseline, so a red baseline " <>
              "makes all 50 of them unreadable."
    end

    log.("  baseline: #{base.summary}")

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
        measure(b, doc, {script, base_probe}, tmp, log, base.rows_total)
      end)

    by_id = Map.new(swept, &{&1["id"], &1})

    doc
    |> Map.put("boundaries", Enum.map(rows, &Map.get(by_id, &1["id"], &1)))
    |> Map.put("control", control_block(doc["control"] || %{}, base, host(), probe_rec))
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
  #
  # `probe` (MES-174) is the baseline probe's fingerprint. `record_host!/1` measures no
  # probe, so it passes `nil` and the recorded one is kept as it stands.
  defp control_block(prior, base, host, probe_rec \\ nil) do
    prior
    |> Map.merge(%{
      "seed" => 0,
      "suite_total" => suite_total(base.summary),
      "baseline_failures" => length(base.units),
      "node" => host["node"],
      "host" => host,
      "note" => control_note(base.summary, host)
    })
    |> then(&if(probe_rec, do: Map.put(&1, "probe", probe_rec), else: &1))
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
      "skipped on (docs/procedure/end-of-sprint.md, step 4, condition (c)); " <>
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

  # `population` is the unmutated baseline's row total: a mutation that makes a test
  # module vanish from the run (rather than fail) is refused by GUARD 34 `population`,
  # since neither witness inside the run can see a module that never reached it.
  defp measure(b, doc, {script, base_probe}, tmp, log, population) do
    spec = spec_of(b)
    backups = apply!(spec)

    run =
      try do
        run_suite(rows: Path.join(tmp, "rows.json"), population: population)
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
            mutated = probe(Path.join(tmp, "probe-mutated.txt"), script)
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

  Returns `%{verdict_diffs: [...], measurement_deltas: [...], carried_forward: [...],
  control_probe: %{"was" => .., "now" => ..} | nil}`. A non-empty `verdict_diffs` is
  AC5's loud failure; everything else is reported, never raised on:

    * `measurement_deltas` — §2.3(e)'s stated delta. Where a row's `scenarios_moved`
      moved, the entry also carries it, was and now, because a field NAME alone is what
      let the MES-171 collapse read as routine (MES-174).
    * `carried_forward` — `carried_forward/1` over the generated document.
    * `control_probe` — the baseline probe's fingerprint, when it differs. A changed
      fingerprint is a RE-BASELINE of the probe, and it is the cause to read every
      `scenarios_moved` delta against before reading any of them as a move in `lib/`.
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
          do: measurement_delta(b["id"], d)

    was_probe = (committed["control"] || %{})["probe"]
    now_probe = (generated["control"] || %{})["probe"]

    %{
      verdict_diffs: verdict_diffs,
      measurement_deltas: measurement_deltas,
      carried_forward: carried_forward(generated),
      control_probe: if(was_probe != now_probe, do: %{"was" => was_probe, "now" => now_probe})
    }
  end

  @moved "l2.byte_probe.scenarios_moved"

  defp measurement_delta(id, diffs) do
    entry = %{"id" => id, "fields" => Enum.map(diffs, & &1["field"])}

    case Enum.find(diffs, &(&1["field"] == @moved)) do
      nil -> entry
      d -> Map.put(entry, "scenarios_moved", Map.take(d, ["was", "now"]))
    end
  end

  @doc """
  The directions whose LIVE verdict was CARRIED FORWARD over a silent probe: live count
  zero (so L2 decided them), `l2.verdict` live, and a `scenarios_moved` that is empty.

  `merge_l2/3` never lets a silent probe override a recorded `live` — §2.3(d): L2 can
  only turn DEAD into LIVE. That rule is right, and it is also what hid the MES-161
  blinding: seven LIVE verdicts stood on a probe that could no longer see them, and
  nothing printed the fact. This is the rule's reported counterpart (MES-174). It is
  derived from the table, so it adds no field and changes no verdict.
  """
  def carried_forward(doc) do
    for b <- doc["boundaries"] || [],
        l2_trigger?(b),
        l2 = b["l2"] || %{},
        l2["verdict"] == "live",
        (l2["byte_probe"] || %{})["scenarios_moved"] in [nil, []],
        do: b["id"]
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

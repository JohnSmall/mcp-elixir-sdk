defmodule MCP.Conformance.Census do
  @moduledoc """
  Convert an **accepted** conformance run into a documented intermediate
  representation.

  MES-51 stopped deliberately short of results: `checks.json` was detected and
  never read, because a provenance tool that also interprets results has two
  jobs and can fail at the second while looking green at the first. This module
  is the second job, and it is written as a **converter to a schema** rather
  than as a table printer, because three tickets consume it: MES-56 (server
  leg), MES-57 (client leg, which reuses this file unchanged) and MES-58 (the
  report, which reads it). Two bespoke censuses would re-run MES-24's defect and
  leave the report reconciling incompatible tables.

  ## Two structural properties, both gates rather than rules

  **A figure from an unaccepted run is unobtainable by construction.** `build/2`
  calls the same `MCP.Conformance.Manifest.judge/3` the adjudicator calls, over
  the same `MCP.Conformance.Provenance.observe_run/1` observation, and returns a
  refusal instead of a census. Not "remember to adjudicate first".

  **No verdict is stored — only raw counts and NAMED reducers.** Sprint 4
  measured three disagreeing reducers inside the harness, and shipped a
  correction round over exactly that. If this IR stored `passed: true`, MES-57
  would need its own census, and MES-58 could not say which rule produced a
  figure. Storing counts plus named reducers means the field name **is** the
  reducer, so every quoted number carries its own definition.

  ## Reducers

  All three are the harness's, read out of `dist/index.js` rather than inferred
  from its output, and each states what it does with **all five** check statuses
  — including `INFO`, which no reducer consumes and which the IR carries anyway.
  A status silently dropped from a denominator is the same defect as a scenario
  silently absent from one.

  ## What the census refuses

  The adjudicator's own conditions, inherited whole because `build/2` calls the
  same `judge/3`, plus this module's own. **The enumeration is
  `refusal_codes/0`, deliberately not a sentence here.** This paragraph used to
  restate the list in prose, and it had already drifted — it named seven of the
  then thirteen codes — which is S5-20's defect in the module that found it: a
  stated property with nothing checking the code against it. Two machine-checked
  lists replace it. A test asserts `refusal_codes/0` against the `refuse(` calls
  in this file, in both directions; another requires `precondition_register/0`
  to account for every code it names. Adding a refusal without both fails the
  suite.

  What the codes have in common is the shape rather than the subject: each names
  a value this converter would otherwise have computed as if a precondition
  held, with no one told when it did not.

  ## Precondition register

  Every site in this module that computes a value whose validity rests on a
  precondition is enumerated in `precondition_register/0`, together with what it
  does when that precondition fails — **including the sites that already did the
  right thing**. A value that degrades quietly is the same defect as a check
  that passes because it could not see, and the only way to know which sites do
  that is to walk all of them rather than the one that was just reported.

  The register's own bound, learned the hard way in round 2 and recorded as
  S5-19: **a register is complete only relative to the question that built it.**
  This one was built by asking what preconditions the code has, and a second,
  mechanical question — *trace every `Map.new`, every default and every
  list-to-set conversion, and ask where a value is valid only if an input is
  unique or complete* — found a sixteenth site it had missed, plus five more
  across the modules this one reads. Sites whose keys are literals of this
  codebase, and therefore unique by construction rather than by precondition,
  are enumerated in `docs/sprint_5_issues.md` under S5-19 rather than here: they
  are evidence that the pass was made, not conditions anything can violate.
  """

  alias MCP.Conformance.{
    Adapters,
    Beacon,
    Classification,
    Console,
    Manifest,
    Provenance,
    RequirementSet,
    RunIndex
  }

  @census_schema_version 1

  @statuses ~w(SUCCESS FAILURE WARNING SKIPPED INFO)

  # Each reducer's disposition over ALL FIVE statuses, stated as data so
  # "what does it do with INFO" is answerable by reading the IR rather than the
  # source. `:fail` — one such check fails the scenario. `:pass` — counts toward
  # the scenario's passed tally. `:ignored` — neither.
  @reducers %{
    "requirements_exit" => %{
      "scope" => "scored",
      "source" =>
        "the exit code of `conformance <leg> --requirements REV`; both legs. " <>
          "In dist/index.js: +!!scored.some(s => s.checks.some(c => c.status === 'FAILURE'))",
      "disposition" => %{
        "SUCCESS" => "pass",
        "FAILURE" => "fail",
        "WARNING" => "ignored",
        "SKIPPED" => "ignored",
        "INFO" => "ignored"
      }
    },
    "server_summary" => %{
      "scope" => "all_ran",
      "source" =>
        "the ✓/✗ mark the server leg prints per scenario in its SUMMARY block. " <>
          "In dist/index.js: failed = checks.filter(c => c.status === 'FAILURE').length; ✗ iff failed > 0",
      "disposition" => %{
        "SUCCESS" => "pass",
        "FAILURE" => "fail",
        "WARNING" => "ignored",
        "SKIPPED" => "ignored",
        "INFO" => "ignored"
      }
    },
    "client_summary" => %{
      "scope" => "all_ran",
      "source" =>
        "the client leg's suite verdict when NOT run under --requirements. " <>
          "In dist/index.js: process.exit(+(failed > 0 || warnings > 0)) — a WARNING fails " <>
          "here and is free in the other two. This is the leg-dependence that made Sprint 4 " <>
          "quote two different numbers for one run",
      "disposition" => %{
        "SUCCESS" => "pass",
        "FAILURE" => "fail",
        "WARNING" => "fail",
        "SKIPPED" => "ignored",
        "INFO" => "ignored"
      }
    }
  }

  @doc "Version of the `census.json` schema this module writes."
  @spec census_schema_version() :: pos_integer()
  def census_schema_version, do: @census_schema_version

  @doc "The named reducers, with each one's disposition over all five check statuses."
  @spec reducers() :: map()
  def reducers, do: @reducers

  @doc "The five check statuses the harness emits."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc """
  Every refusal code this module can emit, in the order the gates run.

  The adjudicator's own codes are not repeated here: `judge/3` is inherited
  whole, and a run it refuses never reaches these gates.
  """
  @spec refusal_codes() :: [atom()]
  def refusal_codes do
    [
      :ADAPTER_UNKNOWN,
      :ROLE_NOT_CORROBORATED,
      :REQUIREMENT_SET_UNREADABLE,
      :LEG_NOT_IN_REQUIREMENT_SET,
      :CHECKS_UNREADABLE,
      :CHECK_STATUS_UNKNOWN,
      :HARNESS_MARK_MISSING,
      :REDUCER_DISAGREES_WITH_HARNESS,
      :NOT_SCORED_DISAGREES_WITH_FROZEN_SET,
      :CONTROL_REFUSED,
      :CONTROL_IS_NOT_A_CONTROL,
      :CONTROL_MISSING_SCENARIOS,
      :SCENARIO_UNCLASSIFIED,
      :CLASSIFICATION_STALE
    ]
  end

  @doc """
  Every site in the census that computes a value whose validity rests on a
  precondition, with what it does when that precondition fails.

  Written because B1 — the null-control join subtracting over scenarios the
  control never ran — was the fourth defect of one shape in this sprint: a value
  computed as if its precondition held, and no one told when it did not. One
  fix does not answer the class, so the class is answered by enumeration, and
  **the sites that were already right are listed too**: "correct" and "not
  looked at" are indistinguishable from the outside, which is the whole
  complaint.

  `:on_failure` is one of:

    * `:refuses` — the census returns a refusal and nothing is written or
      printed;
    * `:refused_upstream` — the failure cannot reach this site, because
      `judge/3` refuses it first; the local `|| ""` or `nil` default is
      unreachable rather than benign, and the code that makes it unreachable is
      named;
    * `:reported` — the value is recorded in the IR and refuses nothing,
      because no printed figure depends on it. The reason it cannot move a
      figure is stated;
    * `:degrades` — the value is still computed and something weaker is true of
      it. **One site is in this state**, deliberately, and it says so.
  """
  @spec precondition_register() :: [map()]
  def precondition_register do
    [
      %{
        site: "build/2 → Manifest.read/1, judge/3",
        precondition: "the run was ACCEPTED by the adjudicator's own conditions",
        on_failure: :refuses,
        code: :inherited,
        note:
          "the same judge/3 the adjudicator calls, over the same observation, so the " <>
            "census cannot reach a verdict the adjudicator would not"
      },
      %{
        site: "build/2 → judge/3, :expect_commit default",
        precondition: "the caller nominates the tree under review",
        on_failure: :degrades,
        code: nil,
        note:
          "when no commit is nominated the census judges the manifest against its OWN " <>
            "recorded commit, so COMMIT_MISMATCH cannot fire — the run self-attests. " <>
            "Deliberate: a census may legitimately be taken of an archived run whose tree " <>
            "is no longer checked out. The bound is real, so it is stated rather than " <>
            "closed: the commit is recorded in run.commit, `mix conformance.adjudicate` " <>
            "raises instead of defaulting, and this ticket passes --expect-commit"
      },
      %{
        site: "corroborate_role/2",
        precondition:
          "beacon.jsonl on disk names the adapter the manifest claims, and that adapter " <>
            "is one this tooling can run",
        on_failure: :refuses,
        code: :ROLE_NOT_CORROBORATED,
        note:
          "an unmappable adapter refuses as ADAPTER_UNKNOWN rather than defaulting to " <>
            "\"measurement\" — the role decides whether a headline may be printed at all"
      },
      %{
        site: "requirement_set/1 (`observed.requirements_body || \"\"`)",
        precondition: "requirements.yaml and expected.txt are present and parse",
        on_failure: :refused_upstream,
        code: :REQUIREMENT_SET_UNREADABLE,
        note:
          "the `|| \"\"` cannot produce an empty denominator: both files are re-hashed " <>
            "against the manifest by check_artefacts/3 (ARTEFACTS_INCONSISTENT) before " <>
            "this runs, and RequirementSet.parse/2 refuses an empty body outright rather " <>
            "than returning a set with no scenarios in it. Round 2 added the multiplicity " <>
            "half of the same condition: parse/2 now refuses a scenario listed twice under " <>
            "one leg, twice in not_scored, or as both — a repeat that its own yaml-vs-listing " <>
            "cross-check cannot see, because that check compares MapSets"
      },
      %{
        site: "scenarios/4 (`observed.console_body || \"\"`)",
        precondition: "console.txt is present and hashes to what the run recorded",
        on_failure: :refused_upstream,
        code: nil,
        note:
          "an empty console parses to zero scenario mappings, which would make the census " <>
            "— and corroborate_reducer/3 below it — vacuous rather than wrong. It is " <>
            "unreachable: a run with no readable console.txt is refused " <>
            "ARTEFACTS_INCONSISTENT, a condition MES-51 added after exactly this hole " <>
            "was found open"
      },
      %{
        site: "read_checks/3",
        precondition: "each scenario the console names has a readable checks.json",
        on_failure: :refuses,
        code: :CHECKS_UNREADABLE,
        note:
          "a scenario that THREW has no checks.json by design; it is not read as \"no " <>
            "checks, therefore nothing failed\" but reconstructed as one synthesised " <>
            "FAILURE, tagged checks_source: console_thrown so the reader can tell a result " <>
            "that was read from one that was rebuilt"
      },
      %{
        site: "build/2 → leg_in_requirement_set/2",
        precondition: "the leg the run records is one the frozen set defines",
        on_failure: :refuses,
        code: :LEG_NOT_IN_REQUIREMENT_SET,
        note:
          "found by round 2's mechanical pass. The manifest records `leg` as provenance " <>
            "only, and `Map.get(set.scored, leg, [])` answers an unknown leg with an empty " <>
            "list rather than an error, so the scored denominator vanished and 0 of 0 " <>
            "rendered as a complete census"
      },
      %{
        site: "corroborate_reducer/3 (`Map.new(parsed.marks, &{&1.scenario, &1})`)",
        precondition: "each scenario carries exactly one SUMMARY mark, and no mark is invented",
        on_failure: :refused_upstream,
        code: nil,
        note:
          "B2. Keying marks by scenario collapses a duplicate last-wins, so a console " <>
            "carrying both ✗ and ✓ for one scenario was ACCEPTED on whichever came last — " <>
            "the flattering one, in the case measured. Console.parse/1 now faults a " <>
            "duplicated mark and a mark for a scenario that never ran, and judge/3 refuses " <>
            "the run ARTEFACTS_INCONSISTENT before build/2 reaches this line. The mirror " <>
            "direction is the point: HARNESS_MARK_MISSING covered a scenario with no mark " <>
            "and nothing covered a mark with no scenario"
      },
      %{
        site:
          "corroborate_reducer/3, not_in_control/3, control_totals/2, join_control/2 " <>
            "(scenario id used as a key)",
        precondition: "no scenario appears twice in one run",
        on_failure: :refused_upstream,
        code: nil,
        note:
          "four sites key on the scenario id — two Map.new, one Map.keys difference, one " <>
            "Enum.find — and each would silently keep one of a pair. Console.parse/1's " <>
            "duplicate_faults/1 has always faulted a scenario mapped twice, so judge/3 " <>
            "refuses first; listed because that guard lives in another module and the " <>
            "sibling guard beside it was the one missing"
      },
      %{
        site: "corroborate_statuses/1",
        precondition: "every check carries one of the five statuses the reducers define",
        on_failure: :refuses,
        code: :CHECK_STATUS_UNKNOWN,
        note:
          "found by this audit, not by the review. A sixth status has no disposition, so " <>
            "none_failing?/2 counted it as a pass under all three reducers at once, and " <>
            "the harness cross-check could not catch it because the harness keys on " <>
            "FAILURE and calls it non-failing too"
      },
      %{
        site: "corroborate_reducer/3",
        precondition: "every scenario that ran has a ✓/✗ mark in the console to check against",
        on_failure: :refuses,
        code: :HARNESS_MARK_MISSING,
        note:
          "a partial cross-check would report agreement it did not establish, so a missing " <>
            "mark refuses rather than being skipped for that scenario; a mark we disagree " <>
            "with refuses as REDUCER_DISAGREES_WITH_HARNESS"
      },
      %{
        site: "corroborate_not_scored/3",
        precondition:
          "the console's not-scored block and the frozen requirement set name the same " <>
            "scenarios, with the same reasons, for the leg the run records",
        on_failure: :refuses,
        code: :NOT_SCORED_DISAGREES_WITH_FROZEN_SET,
        note:
          "B3's cross-authority half, and the one Console cannot ask: the parser must not " <>
            "import its own referee. Two authorities describe the scored/not-scored split — " <>
            "the console the harness printed and the frozen set this census takes its " <>
            "denominator from — and nothing compared them. Measured: appending " <>
            "`✓ resources-list (extension)` to the not-scored block of a console whose " <>
            "frozen set SCORES resources-list left the run ACCEPTED with " <>
            "expected_counts.not_scored = 0, a census reporting nothing not-scored over a " <>
            "console that named one"
      },
      %{
        site: "classify/1",
        precondition: "every non-pass carries a classification and no pass carries a stale one",
        on_failure: :refuses,
        code: :SCENARIO_UNCLASSIFIED,
        note:
          "a pass that still carries an entry refuses too, as CLASSIFICATION_STALE. " <>
            "Skipped entirely for a control, deliberately: a control exists to fail, and it " <>
            "is also denied a headline, so nothing quotable rests on the skip"
      },
      %{
        site: "control/1",
        precondition: "the joined run is itself ACCEPTED and its adapter is the null control",
        on_failure: :refuses,
        code: :CONTROL_IS_NOT_A_CONTROL,
        note:
          "a control the adjudicator would refuse refuses here too, as CONTROL_REFUSED. " <>
            "The category error is tested off the manifest FIRST, so a measurement joined " <>
            "by mistake is not reported as \"the control was refused\" for some unrelated " <>
            "reason of its own"
      },
      %{
        site: "control_covers_measurement/2",
        precondition: "the control ran every SCORED scenario the measurement ran",
        on_failure: :refuses,
        code: :CONTROL_MISSING_SCENARIOS,
        note:
          "B1. Before this gate the join returned {:ok, _} and printed \"ours alone\" " <>
            "over a set the control had never been asked about"
      },
      %{
        site: "control_totals/2 — not_in_control_not_scored, in_control_only",
        precondition:
          "the control's scenario set matches the measurement's outside the scored set",
        on_failure: :reported,
        code: nil,
        note:
          "every figure the control licenses is quoted over the SCORED set, so neither of " <>
            "these can move a printed number. They are enumerated rather than dropped, so " <>
            "that the boundary is visibly drawn"
      },
      %{
        site: "join_control/2 (per-scenario `control: null`)",
        precondition: "the control ran this scenario",
        on_failure: :reported,
        code: nil,
        note:
          "unreachable for a scored scenario once the gate above holds. For a not-scored " <>
            "one the IR stores null, and the renderer prints \"not run\" rather than the " <>
            "same em dash it prints when no control was joined at all — two facts that " <>
            "rendered identically until this round"
      },
      %{
        site: "scenario/6 — harness_reason via RequirementSet.harness_reason/2",
        precondition: "the scenario is in the frozen set",
        on_failure: :reported,
        code: nil,
        note:
          "nil for a scenario outside the frozen set, which the denominator diff already " <>
            "enumerates as ran_outside_frozen_set; it carries no verdict and moves nothing"
      },
      %{
        site: "Mix.Tasks.Conformance.Census.emit/3 and Census.Markdown.render/1",
        precondition: "build/2 returned a census",
        on_failure: :refuses,
        code: nil,
        note:
          "both are on the {:ok, census} branch only. A refusal writes no JSON, renders no " <>
            "Markdown, prints no headline and exits 1 — which is what makes every gate " <>
            "above a gate rather than a warning"
      }
    ]
  end

  @doc """
  Build a census for `run_dir`.

  Options:

    * `:expect_commit` — passed through to `judge/3`; defaults to the manifest's
      own recorded commit, since the census may legitimately be taken of a run
      of a tree that is no longer checked out.
    * `:control` — a second run directory holding the null-implementation
      control, joined into the result.

  Returns `{:ok, census}` or `{:refused, code, detail}`.
  """
  @spec build(String.t(), keyword()) :: {:ok, map()} | {:refused, atom(), String.t()}
  def build(run_dir, opts \\ []) do
    run_dir = Path.expand(run_dir)

    with {:ok, m} <- Manifest.read(run_dir),
         observed = Provenance.observe_run(run_dir),
         :ok <- judge(m, observed, opts),
         :ok <- corroborate_role(run_dir, m),
         {:ok, set} <- requirement_set(observed),
         :ok <- leg_in_requirement_set(m, set),
         index = run_index(m, observed, set),
         {:ok, diff} <- Manifest.expected_diff(m, observed),
         {:ok, scenarios} <- scenarios(run_dir, m, index, set),
         :ok <- corroborate_statuses(scenarios),
         :ok <- corroborate_reducer(m, observed, scenarios),
         :ok <- corroborate_not_scored(m, observed, index, set),
         {:ok, control} <- control(opts[:control]),
         :ok <- control_covers_measurement(scenarios, control) do
      census =
        %{
          "census_schema_version" => @census_schema_version,
          "run" => run_block(run_dir, m),
          "reducers" => @reducers,
          "expected" => expected_block(set, m, diff),
          "scenarios" => Enum.map(scenarios, &join_control(&1, control)),
          "totals" => totals(scenarios, set, m, diff, control)
        }

      classify(census)
    end
  end

  @doc """
  Write `census` to `path` as pretty JSON, and return the path.
  """
  @spec write!(map(), String.t()) :: String.t()
  def write!(census, path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(census, pretty: true) <> "\n")
    path
  end

  # --- gates -----------------------------------------------------------------

  defp judge(m, observed, opts) do
    expect = %{
      commit: opts[:expect_commit] || m["git"]["commit_sha_start"],
      requirements_md5: opts[:expect_requirements_md5],
      harness_dist_sha256: opts[:expect_harness_dist_sha256]
    }

    Manifest.judge(m, observed, expect)
  end

  # E2's condition, answered rather than assumed. Making the null control
  # adjudicable means an ACCEPTED manifest can attest a run in which no SDK code
  # executed, and `role` is derived from `invocation.adapter` — a field the
  # runner wrote and an editor could rewrite. So it is not trusted: the beacon
  # journal is re-read FROM DISK and its `source` values must name the adapter
  # the manifest claims.
  #
  # The bound, stated because it is real: an operator who edits `beacon.jsonl`
  # to match will pass this. Nothing here defends against a forger with write
  # access to the run directory; what it defends against is a control being
  # relabelled by a one-field edit, or by being copied into the wrong report.
  defp corroborate_role(run_dir, m) do
    claimed = m["invocation"]["adapter"]

    case Adapters.fragment(m["leg"], claimed) do
      nil ->
        refuse(
          :ADAPTER_UNKNOWN,
          "invocation.adapter is #{inspect(claimed)} for leg #{inspect(m["leg"])}, which is " <>
            "not an adapter this tooling can run on that leg, so the run's role cannot be " <>
            "established. Admissible: #{inspect(Adapters.names(:server) ++ Adapters.names(:client))}"
        )

      fragment ->
        journal =
          Beacon.read(Path.join(run_dir, Manifest.beacon_filename()), m["beacon"]["token"])

        case Enum.reject(journal.adapter_sources, &String.contains?(&1, fragment)) do
          [] ->
            :ok

          mismatched ->
            refuse(
              :ROLE_NOT_CORROBORATED,
              "the manifest claims adapter #{inspect(claimed)}, but beacon.jsonl on disk " <>
                "names #{inspect(mismatched)} as the source that started. A control cannot " <>
                "be reported as a measurement, nor a measurement as a control"
            )
        end
    end
  end

  # MES-56 correction round 2. `m["leg"]` reaches the frozen set as
  # `Map.get(set.scored, m["leg"], [])`, and the manifest treats `leg` as
  # provenance only — it is recorded, never checked against a vocabulary. So a
  # leg the frozen set does not define does not fail: it produces an EMPTY
  # scored list, which is a valid list. Measured on an otherwise accepted
  # one-scenario run with `leg` set to "sever": the census was ACCEPTED with
  # `expected_counts.scored = 0`, `by_reducer.server_summary.scored` reading
  # 0 of 0, every scenario silently re-labelled not-scored, and `absentees`
  # empty — a complete-looking census whose scored denominator had vanished.
  # `summary_reducer/1` compounds it by mapping anything that is not "client"
  # to the server reducer, so the misspelling is not visible there either.
  #
  # The default is the whole defect: `Map.get/3` cannot distinguish "this leg
  # ran nothing" from "this leg is not in the set", and only the second is an
  # error. Asked as a key question instead, both are answerable.
  defp leg_in_requirement_set(m, set) do
    if Map.has_key?(set.scored, m["leg"]) do
      :ok
    else
      refuse(
        :LEG_NOT_IN_REQUIREMENT_SET,
        "the run records leg #{inspect(m["leg"])}, which the frozen requirement set does " <>
          "not define — it names #{inspect(Enum.sort(Map.keys(set.scored)))}. Every scored " <>
          "figure is taken against that leg's list, so an unknown leg yields an empty " <>
          "denominator rather than an error, and 0 of 0 renders as a complete census"
      )
    end
  end

  # Each reducer declares a disposition for exactly five statuses, so a sixth
  # has none — and `none_failing?/2` asks only whether a check carries a status
  # the reducer calls fatal. An unrecognised status is therefore silently
  # non-failing, in the flattering direction: it counts as a PASS under all
  # three reducers at once, vanishes from the printed
  # SUCCESS/FAILURE/WARNING/SKIPPED/INFO line while still counting in `total`,
  # and cannot be caught by the harness cross-check below, because the harness's
  # own reducer keys on `=== 'FAILURE'` and calls it non-failing too.
  #
  # Measured on a toy run rather than argued: one check rewritten to `ERROR`
  # made a scenario with zero SUCCESS checks pass under every reducer, flagged
  # `empty: true`, with the scored check census reading `SUCCESS 1 ... total 2`
  # — one check present in the denominator and absent from every column.
  #
  # `"ABSENT"` is `counts/1`'s bucket for a check whose `status` key is missing
  # altogether, and it lands here for the same reason.
  defp corroborate_statuses(scenarios) do
    unknown =
      for s <- scenarios,
          {status, n} <- s["checks"],
          status != "total",
          status not in @statuses,
          n > 0,
          do: "#{s["id"]}: #{n} check(s) with status #{inspect(status)}"

    case Enum.sort(unknown) do
      [] ->
        :ok

      found ->
        refuse(
          :CHECK_STATUS_UNKNOWN,
          "#{length(found)} scenario(s) carry a check status no reducer declares a " <>
            "disposition for: #{inspect(found)}. The five are #{inspect(@statuses)}; " <>
            "\"ABSENT\" means the check carried no status field at all. A status nothing " <>
            "calls fatal is counted as a pass by every reducer, so this refuses rather " <>
            "than resolving in the flattering direction"
        )
    end
  end

  # A third derivation, and the one that can falsify the other two. `checks.json`
  # is ours to reduce; the console's ✓/✗ is the harness reducing the same run.
  # If they disagree, one of us has misread the artefacts and no figure from
  # either is worth printing.
  defp corroborate_reducer(m, observed, scenarios) do
    blocks = Console.blocks(observed.console_body || "")
    reducer = summary_reducer(m["leg"])
    marks = Map.new(blocks.marks, &{&1.scenario, &1})
    by_id = Map.new(scenarios, &{&1["id"], &1})

    missing = Enum.sort(Map.keys(by_id) -- Map.keys(marks))

    disagreements =
      for {id, s} <- by_id,
          mark = Map.get(marks, id),
          not is_nil(mark),
          verdict(s, reducer) != mark.pass,
          do:
            "#{id}: we make it #{if verdict(s, reducer), do: "pass", else: "fail"} under " <>
              "#{reducer}, the harness printed #{if mark.pass, do: "✓", else: "✗"}"

    cond do
      missing != [] ->
        refuse(
          :HARNESS_MARK_MISSING,
          "#{length(missing)} scenario(s) ran with no ✓/✗ line in the console, so our " <>
            "reducer cannot be checked against the harness's for them: #{inspect(missing)}. " <>
            "A partial cross-check would report agreement it did not establish"
        )

      disagreements != [] ->
        refuse(
          :REDUCER_DISAGREES_WITH_HARNESS,
          "our #{reducer} reducer and the harness's own verdict differ on " <>
            "#{length(disagreements)} scenario(s): #{inspect(disagreements)}"
        )

      true ->
        :ok
    end
  end

  # C3 / B3's cross-authority half, placed here rather than in the parser on
  # purpose. `Console` can ask whether a not-scored line names a scenario that
  # RAN — that is intra-console and it now does. It cannot ask whether the
  # frozen set agrees the scenario is not scored, because that needs
  # `RequirementSet`, and a parser that imports its own referee is no longer a
  # parser. Every other console-versus-set comparison already lives here.
  #
  # Two authorities describe the same split: the console the harness printed,
  # and the frozen set this census takes its scored denominator from. Nothing
  # compared them. Measured on a probe built from an accepted one-scenario run:
  # appending `✓ resources-list (extension)` to the not-scored block of a
  # console whose frozen set SCORES resources-list left the run ACCEPTED, with
  # `expected_counts.not_scored = 0` — a census reporting nothing not-scored
  # over a console that named one, and no one told.
  #
  # Checked in BOTH directions, over the scenarios that ran, plus the reason:
  #
  #   * console says not-scored, set does not — a scenario excluded from the
  #     denominator by an edit to a file the census reads and never
  #     cross-examines, which is the flattering direction;
  #   * set says not-scored, the scenario ran, and the console's block omits it
  #     — the harness scored something this census does not, so the two are
  #     measuring different denominators over one run;
  #   * both agree it is not scored and give different reasons — `scenario/6`
  #     records the SET's reason as `harness_reason`, so a silent disagreement
  #     puts a reason in the IR that the run it describes never printed.
  #
  # A set entry whose scenario never ran at all is NOT this check's business:
  # that is an absentee, and `Manifest.expected_diff/2` already reports it as
  # `absent_not_scored`. Faulting it here too would give one defect two names.
  defp corroborate_not_scored(m, observed, index, set) do
    blocks = Console.blocks(observed.console_body || "")

    expected =
      set.not_scored
      |> Enum.filter(&(&1.leg == m["leg"]))
      |> Map.new(&{&1.scenario, &1.reason})

    # From the INDEX, not from `Console.ran/1`. On the client leg the console
    # yields no mappings at all, so `ran` was the empty set and `set_only/4`
    # could never fire — the check did not fail, it stopped being able to. A
    # guard that cannot see is the same defect as a guard that is absent, and
    # this one is harder to notice because it still reports :ok.
    ran = MapSet.new(RunIndex.ran(index))
    printed = Map.new(blocks.not_scored, &{&1.scenario, &1.reason})

    disagreements =
      Enum.flat_map(Enum.sort(Map.keys(printed)), &console_only(&1, printed, expected, m)) ++
        Enum.flat_map(Enum.sort(Map.keys(expected)), &set_only(&1, printed, ran, m))

    case disagreements do
      [] ->
        :ok

      _ ->
        refuse(
          :NOT_SCORED_DISAGREES_WITH_FROZEN_SET,
          "the console's not-scored block and the frozen requirement set disagree on " <>
            "#{length(disagreements)} scenario(s): #{inspect(disagreements)}. The scored " <>
            "denominator is taken from the SET and every per-scenario reason is reported " <>
            "from it, so a disagreement means the two authorities are describing different " <>
            "runs and no split read from either is worth printing"
        )
    end
  end

  defp console_only(id, printed, expected, m) do
    case Map.fetch(expected, id) do
      :error ->
        [
          "#{id}: the console lists it as not scored (#{Map.fetch!(printed, id)}) and the " <>
            "frozen set does not, for leg #{m["leg"]}"
        ]

      {:ok, reason} ->
        if reason == Map.fetch!(printed, id) do
          []
        else
          [
            "#{id}: the console's reason is #{inspect(Map.fetch!(printed, id))}, the frozen " <>
              "set's is #{inspect(reason)}"
          ]
        end
    end
  end

  defp set_only(id, printed, ran, m) do
    if Map.has_key?(printed, id) or not MapSet.member?(ran, id) do
      []
    else
      [
        "#{id}: the frozen set makes it not scored for leg #{m["leg"]}, it RAN, and the " <>
          "console's not-scored block omits it — the harness scored a scenario this census " <>
          "does not"
      ]
    end
  end

  # AC3. Enforced only for a measurement: a control exists to fail, and
  # demanding a rationale for each of its failures would be filing paperwork
  # against a straw man.
  # A control exists to fail, and a PROBE exists to fail differently on purpose:
  # demanding a written rationale for each of their failures would be filing
  # paperwork against a straw man. Only a MEASUREMENT owes one.
  defp classify(%{"run" => %{"role" => role}} = census) when role != "measurement",
    do: {:ok, census}

  defp classify(census) do
    scenarios = census["scenarios"]

    unclassified =
      for s <- scenarios,
          not s["passes"]["server_summary_or_client_summary"],
          is_nil(s["classification"]),
          do: s["id"]

    stale =
      for s <- scenarios,
          s["passes"]["server_summary_or_client_summary"],
          not is_nil(s["classification"]),
          do: s["id"]

    cond do
      unclassified != [] ->
        refuse(
          :SCENARIO_UNCLASSIFIED,
          "#{length(unclassified)} scenario(s) do not pass and carry no entry in " <>
            "MCP.Conformance.Classification: #{inspect(Enum.sort(unclassified))}. A rate " <>
            "printed beside an unexplained failure invites the reader to assume someone " <>
            "looked at it"
        )

      stale != [] ->
        refuse(
          :CLASSIFICATION_STALE,
          "#{length(stale)} scenario(s) now pass but are still classified: " <>
            "#{inspect(Enum.sort(stale))}. Remove the entries — a classification that " <>
            "outlives its failure describes something that is no longer true"
        )

      true ->
        {:ok, census}
    end
  end

  # --- the IR ----------------------------------------------------------------

  defp run_block(run_dir, m) do
    %{
      "run_dir" => run_dir,
      "leg" => m["leg"],
      # From the adapter registry rather than a bare `== "null"`. The client leg
      # has THREE nulls (`null_exit0`, `null_connect`, `null_request`), and a
      # bare equality would have filed all three as measurements — a control
      # reported as a measurement is the one mislabelling this whole tool exists
      # to prevent.
      "role" => Atom.to_string(Adapters.role(m["leg"], m["invocation"]["adapter"])),
      "adapter" => m["invocation"]["adapter"],
      "adapter_command" => m["invocation"]["adapter_command"],
      "commit" => m["git"]["commit_sha_start"],
      "branch" => m["git"]["branch_start"],
      "harness_version_reported" => m["harness"]["version_reported"],
      "harness_dist_sha256" => m["harness"]["dist_sha256"],
      "requirements_revision" => m["requirements"]["revision"],
      "requirements_md5" => m["requirements"]["md5"],
      "manifest_sha256" => Provenance.sha256_file(Path.join(run_dir, Manifest.filename())),
      "console_sha256" => m["result"]["console_sha256"],
      "expected_sha256" => m["result"]["expected_sha256"],
      "harness_exit_code" => m["result"]["harness_exit_code"],
      "started_at" => m["timing"]["started_at"],
      "adjudication" => %{
        "verdict" => "accepted",
        "judged_by" => "MCP.Conformance.Manifest.judge/3",
        "conditions" => Enum.map(Manifest.refusal_codes(), &Atom.to_string/1)
      }
    }
  end

  defp expected_block(set, m, diff) do
    %{
      "revision" => m["requirements"]["revision"],
      "scored" => set.scored,
      "not_scored" =>
        Enum.map(set.not_scored, fn e ->
          %{"scenario" => e.scenario, "leg" => e.leg, "reason" => e.reason}
        end),
      "absent_scored" => diff.missing_scored,
      "absent_not_scored" => diff.missing_not_scored,
      "ran_outside_frozen_set" => diff.unexpected
    }
  end

  # One derivation, shared with `Manifest.judge/3` through `RunIndex` itself:
  # the gate and the report must not be able to answer "what ran, and where are
  # its results?" differently. On the server leg it delegates to `Console`
  # unchanged; on the client leg it is the directory-name key.
  defp run_index(m, observed, set) do
    RunIndex.index(m["leg"],
      console_body: observed.console_body || "",
      run_dir: Map.get(observed, :run_dir) || m["invocation"]["out_dir"],
      out_dir: m["invocation"]["out_dir"],
      requirement_set: set
    )
  end

  defp requirement_set(observed) do
    case RequirementSet.parse(observed.requirements_body || "", observed.expected_body || "") do
      {:ok, set} -> {:ok, set}
      {:error, why} -> refuse(:REQUIREMENT_SET_UNREADABLE, why)
    end
  end

  defp scenarios(run_dir, m, index, set) do
    scored = MapSet.new(Map.get(set.scored, m["leg"], []))

    index.mappings
    |> Enum.reduce_while({:ok, []}, fn mapping, {:ok, acc} ->
      case read_checks(run_dir, m, mapping) do
        {:ok, checks, source} ->
          {:cont, {:ok, acc ++ [scenario(mapping, checks, source, scored, set, m)]}}

        {:refused, _, _} = refusal ->
          {:halt, refusal}
      end
    end)
  end

  # Read through the manifest's recorded out_dir so an archived run reads the
  # same as a fresh one, and so the path comes from the run rather than from
  # where the operator happens to be standing.
  # A thrown scenario has no checks.json, because the harness wrote none. It is
  # NOT treated as "no checks, therefore nothing failed" — that reading would
  # make every crash a pass, which is the flattering direction and the reason
  # this case is handled explicitly. The harness itself synthesises one FAILURE
  # check for a thrown scenario before printing its ✗; the same check is
  # synthesised here, from the console's own message, and the IR records that
  # it came from the console rather than from an artefact.
  defp read_checks(_run_dir, _m, %{dir: nil} = mapping) do
    {:ok,
     [
       %{
         "id" => mapping.scenario,
         "name" => mapping.scenario,
         "status" => "FAILURE",
         "errorMessage" => mapping.threw
       }
     ], "console_thrown"}
  end

  defp read_checks(run_dir, m, mapping) do
    rel = Path.relative_to(Path.expand(mapping.dir), Path.expand(m["invocation"]["out_dir"]))
    path = Path.join([run_dir, rel, "checks.json"])

    with {:ok, body} <- File.read(path),
         {:ok, checks} when is_list(checks) <- Jason.decode(body) do
      {:ok, checks, "artefacts"}
    else
      _ ->
        refuse(
          :CHECKS_UNREADABLE,
          "#{path} — the console attributes scenario #{inspect(mapping.scenario)} to this " <>
            "directory and its checks.json is absent or is not a JSON array"
        )
    end
  end

  defp scenario(mapping, checks, checks_source, scored, set, m) do
    counts = counts(checks)
    id = mapping.scenario
    is_scored = MapSet.member?(scored, id)

    passes =
      Map.new(@reducers, fn {name, spec} ->
        {name, none_failing?(checks, spec)}
      end)

    %{
      "id" => id,
      "leg" => m["leg"],
      "scored" => is_scored,
      "harness_reason" => RequirementSet.harness_reason(set, id),
      "artefact_dir" => artefact_dir(mapping, m),
      # "artefacts" or "console_thrown". A reader must be able to tell a
      # scenario whose result was READ from one whose result was RECONSTRUCTED,
      # without diffing the run directory against the console.
      "checks_source" => checks_source,
      "threw" => mapping.threw,
      "checks" => counts,
      "failed_checks" =>
        for c <- checks, c["status"] in ["FAILURE", "WARNING"] do
          %{
            "id" => c["id"],
            "name" => c["name"],
            "status" => c["status"],
            "message" => c["errorMessage"]
          }
        end,
      "passes" =>
        Map.put(
          passes,
          "server_summary_or_client_summary",
          Map.fetch!(passes, summary_reducer(m["leg"]))
        ),
      # A scenario can PASS while measuring nothing: all-SKIPPED, or a check
      # sheet that a do-nothing server satisfies by having no implementation to
      # contradict. `empty` is a field rather than a footnote because a rate
      # quoted over empties is a rate over scenarios that asked nothing.
      "empty" => counts["total"] == 0 or counts["SUCCESS"] + counts["FAILURE"] == 0,
      "classification" => classification(id)
    }
  end

  defp artefact_dir(%{dir: nil}, _m), do: nil

  defp artefact_dir(mapping, m),
    do: Path.relative_to(Path.expand(mapping.dir), Path.expand(m["invocation"]["out_dir"]))

  defp classification(id) do
    case Classification.fetch(id) do
      nil ->
        nil

      entry ->
        %{
          "class" => Atom.to_string(entry.class),
          "why" => entry.why,
          "owner" => entry.owner
        }
    end
  end

  defp counts(checks) do
    base = Map.new(@statuses, &{&1, 0})

    counted =
      Enum.reduce(checks, base, fn c, acc ->
        Map.update(acc, c["status"] || "ABSENT", 1, &(&1 + 1))
      end)

    Map.put(counted, "total", length(checks))
  end

  defp none_failing?(checks, spec) do
    failing = for {status, "fail"} <- spec["disposition"], do: status
    not Enum.any?(checks, &(&1["status"] in failing))
  end

  defp verdict(scenario, reducer), do: get_in(scenario, ["passes", reducer])

  defp summary_reducer("client"), do: "client_summary"
  defp summary_reducer(_), do: "server_summary"

  # --- totals ----------------------------------------------------------------

  defp totals(scenarios, set, m, diff, control) do
    scored = Enum.filter(scenarios, & &1["scored"])

    %{
      "by_reducer" =>
        Map.new(Map.keys(@reducers), fn name ->
          {name,
           %{
             "scored" => tally(scored, name),
             "all_ran" => tally(scenarios, name)
           }}
        end),
      "checks" => %{
        "all_ran" => sum_counts(scenarios),
        "scored" => sum_counts(scored)
      },
      # Enumerated, never counted: these are the scenarios the artefact tree does
      # not contain, so a census that failed to name them would be silently
      # short by exactly the ones that crashed.
      "thrown_scenarios" =>
        for(s <- scenarios, s["checks_source"] == "console_thrown", do: s["id"]),
      "empty_scenarios" => %{
        "scored" => for(s <- scored, s["empty"], do: s["id"]),
        "all_ran" => for(s <- scenarios, s["empty"], do: s["id"])
      },
      "absentees" => %{
        "scored" => diff.missing_scored,
        "not_scored" => diff.missing_not_scored
      },
      "expected_counts" => %{
        "scored" => length(Map.get(set.scored, m["leg"], [])),
        "not_scored" => set.not_scored |> Enum.filter(&(&1.leg == m["leg"])) |> length()
      },
      "classification" => classification_totals(scenarios),
      "control" => control_totals(scenarios, control)
    }
  end

  # Every one of the six classes appears here, including the ones nothing was
  # filed under. A bucket that is absent and a bucket that is empty read the
  # same in a table, and they mean opposite things: "no scenario is out of scope
  # under ADR-003" is a measured result, while a missing row is an unanswered
  # question. So the keys come from Classification.classes/0 rather than from
  # what happened to be observed, and the zeros are stated (A2d).
  defp classification_totals(scenarios) do
    classified =
      for s <- scenarios, class = get_in(s, ["classification", "class"]), reduce: %{} do
        acc -> Map.update(acc, class, [s["id"]], &(&1 ++ [s["id"]]))
      end

    by_class =
      Map.new(Classification.classes(), fn class ->
        ids = Map.get(classified, Atom.to_string(class), [])
        {Atom.to_string(class), %{"count" => length(ids), "scenarios" => ids}}
      end)

    %{
      "by_class" => by_class,
      "classified" => classified |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
    }
  end

  defp tally(scenarios, reducer) do
    {passing, failing} = Enum.split_with(scenarios, &verdict(&1, reducer))

    %{
      "passed" => length(passing),
      "total" => length(scenarios),
      "failing" => Enum.map(failing, & &1["id"])
    }
  end

  defp sum_counts(scenarios) do
    Enum.reduce(scenarios, Map.new(@statuses ++ ["total"], &{&1, 0}), fn s, acc ->
      Map.merge(acc, s["checks"], fn _k, a, b -> a + b end)
    end)
  end

  # --- the null-control join -------------------------------------------------

  defp control(nil), do: {:ok, nil}

  # The category error is checked FIRST, off the manifest alone. Building the
  # joined run and reading its role afterwards would report a measurement's own
  # unrelated refusal — an unclassified failure, say — as "the control was
  # refused", which sends the reader to fix the wrong run.
  defp control(dir) do
    case Manifest.read(dir) do
      {:refused, code, detail} ->
        refuse(:CONTROL_REFUSED, "the control run at #{dir} was refused: #{code} — #{detail}")

      {:ok, %{"leg" => leg, "invocation" => %{"adapter" => name}}}
      when is_binary(leg) and is_binary(name) ->
        control_by_role(dir, leg, name)

      {:ok, m} ->
        refuse(
          :ADAPTER_UNKNOWN,
          "#{dir} was joined as the null control but its leg (#{inspect(m["leg"])}) and " <>
            "adapter (#{inspect(get_in(m, ["invocation", "adapter"]))}) are not both strings, " <>
            "so its role cannot be established"
        )
    end
  end

  # The registry decides, so the client leg's three nulls are controls without
  # anyone remembering to extend an equality test. A PROBE is refused here on
  # purpose and with its own sentence: `strict_connect` is full of SDK, so
  # joining it would compute "ours alone" against ourselves and license a
  # subtraction that means nothing.
  defp control_by_role(dir, leg, name) do
    case Adapters.role(leg, name) do
      :control ->
        case build(dir, []) do
          {:ok, census} ->
            {:ok, census}

          {:refused, code, detail} ->
            refuse(
              :CONTROL_REFUSED,
              "the control run at #{dir} was refused: #{code} — #{detail}"
            )
        end

      nil ->
        refuse(
          :ADAPTER_UNKNOWN,
          "#{dir} was joined as the null control but its adapter #{inspect(name)} is not one " <>
            "this tooling can run on leg #{inspect(leg)}, so its role cannot be established"
        )

      other_role ->
        refuse(
          :CONTROL_IS_NOT_A_CONTROL,
          "#{dir} was joined as the null control but its adapter #{inspect(name)} has role " <>
            "#{inspect(other_role)}. Joining a #{other_role} run reports \"ours alone\" " <>
            "against a run that contains the very SDK the subtraction is supposed to " <>
            "exclude, which is not a subtraction"
        )
    end
  end

  # B1. The subtraction the control exists to license — "N of these passes are
  # ours alone" — is legal only if the control was ASKED every scored scenario
  # the measurement was asked. `discriminating` and `inherited` are both built
  # by looking each measured scenario up in the control; a scored scenario the
  # control never ran matches neither, so it leaves both sets silently, and the
  # headline reports a smaller "ours alone" figure over a denominator nobody
  # stated. Nothing printed it: `not_in_control` was computed and then shown to
  # no one.
  #
  # Reproduced before it was fixed, on the reviewer's two toy runs (a
  # measurement expecting `tools-list` + `resources-list`, a control expecting
  # `resources-list` alone, each individually ACCEPTED): the join returned
  # `{:ok, _}` with `not_in_control ["tools-list"]` and printed
  # **"Ours alone (0)"**.
  #
  # So it refuses, and it refuses HERE — before `build/2` returns, therefore
  # before any headline, census file or Markdown table exists. A join that
  # degrades quietly is the same defect as a check that passes because it could
  # not see.
  #
  # Scored only, and the asymmetry is deliberate: every figure the control
  # licenses is quoted over the scored set (`control_totals/2` filters to it),
  # so a not-scored scenario missing from the control cannot move a printed
  # number. It is enumerated instead, as `not_in_control_not_scored` — the same
  # rule the denominator diff already applies, where a scored absentee refuses
  # and a not-scored one is reported.
  defp control_covers_measurement(_scenarios, nil), do: :ok

  defp control_covers_measurement(scenarios, control) do
    case not_in_control(scenarios, control, & &1["scored"]) do
      [] ->
        :ok

      missing ->
        refuse(
          :CONTROL_MISSING_SCENARIOS,
          "the null control did not run #{length(missing)} scored scenario(s) this run " <>
            "measured: #{inspect(missing)}. Subtracting a control from a measurement it " <>
            "does not cover is not a subtraction: each of these would drop out of both " <>
            "`inherited` and `discriminating`, and the \"ours alone\" figure would be " <>
            "quoted over a denominator smaller than the one printed beside it. Join a " <>
            "control run over the same requirement set, or join none"
        )
    end
  end

  defp not_in_control(scenarios, control, filter) do
    by_id = Map.new(control["scenarios"], &{&1["id"], &1})

    for s <- scenarios, filter.(s), is_nil(Map.get(by_id, s["id"])), do: s["id"]
  end

  defp join_control(scenario, nil), do: Map.put(scenario, "control", nil)

  defp join_control(scenario, control) do
    match = Enum.find(control["scenarios"], &(&1["id"] == scenario["id"]))

    value =
      case match do
        nil ->
          nil

        c ->
          %{
            "passes" => c["passes"],
            "empty" => c["empty"],
            "checks" => c["checks"]
          }
      end

    Map.put(scenario, "control", value)
  end

  # The whole point of the control, computed rather than described: which
  # scenarios we pass that a do-nothing server does NOT. Sprint 4 measured 6/37
  # for a 25-line -32601-to-everything server and predicted only 3 of those 6
  # from reading the fixtures, so this is not derivable by inspection.
  defp control_totals(_scenarios, nil), do: nil

  defp control_totals(scenarios, control) do
    reducer = "requirements_exit"
    by_id = Map.new(control["scenarios"], &{&1["id"], &1})
    scored = Enum.filter(scenarios, & &1["scored"])

    inherited =
      for s <- scored,
          c = Map.get(by_id, s["id"]),
          not is_nil(c),
          verdict(s, reducer),
          verdict(c, reducer),
          do: s["id"]

    discriminating =
      for s <- scored,
          c = Map.get(by_id, s["id"]),
          not is_nil(c),
          verdict(s, reducer),
          not verdict(c, reducer),
          do: s["id"]

    %{
      "run_dir" => control["run"]["run_dir"],
      "commit" => control["run"]["commit"],
      "adapter_command" => control["run"]["adapter_command"],
      "reducer" => reducer,
      "control_passed_scored" => get_in(control, ["totals", "by_reducer", reducer, "scored"]),
      "inherited" => inherited,
      "discriminating" => discriminating,
      # Structurally empty: `control_covers_measurement/2` refuses before this
      # runs. It is still computed and still recorded, because "checked, and
      # empty" and "never asked" read the same when only the answer is printed
      # — the distinction this ticket keeps re-learning.
      "not_in_control" => not_in_control(scenarios, control, & &1["scored"]),
      # Reported, never refusing: no figure the control licenses is quoted over
      # the not-scored set, so an absence here cannot move a number. Stated so
      # that a reader can see the boundary was drawn rather than overlooked.
      "not_in_control_not_scored" => not_in_control(scenarios, control, &(not &1["scored"])),
      # The mirror direction: scenarios the control ran and the measurement did
      # not. It cannot move "ours alone" either — that set is built by walking
      # the measurement — but a control running a different suite is worth
      # seeing rather than inferring from two totals that do not add up.
      "in_control_only" => Enum.sort(Map.keys(by_id) -- Enum.map(scenarios, & &1["id"]))
    }
  end

  defp refuse(code, detail), do: {:refused, code, detail}
end

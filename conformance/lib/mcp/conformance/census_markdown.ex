defmodule MCP.Conformance.Census.Markdown do
  @moduledoc """
  Render a census as Markdown.

  The committed per-scenario table is a **projection of `census.json`**, never a
  document anyone types. MES-24's defect was a hand-maintained table that no
  longer described the run it named, and the only fix that holds is to remove
  the opportunity: this module reads the IR and writes the table, so the two
  cannot disagree.

  Every figure is printed beside the reducer that produced it. Sprint 4 shipped
  a correction round because one run yielded two different rates under two
  reducers and the text did not say which was which.
  """

  alias MCP.Conformance.{Census, Classification}

  @doc "Render `census` as a Markdown document."
  @spec render(map()) :: String.t()
  def render(census) do
    [
      heading(census),
      provenance(census),
      denominator(census),
      reducer_table(census),
      control_section(census),
      empties(census),
      classification(census),
      scenario_table(census),
      reducer_definitions(census)
    ]
    |> Enum.join("\n")
  end

  defp heading(census) do
    """
    # Official conformance census — #{census["run"]["leg"]} leg, #{census["run"]["requirements_revision"]}

    <!--
      GENERATED from census.json by MCP.Conformance.Census.Markdown. Do not edit by hand:
      a table that can drift from the run it reports is the MES-24 defect, and this file
      exists as a projection precisely so it cannot.
    -->

    Role: **#{census["run"]["role"]}** (adapter `#{census["run"]["adapter"]}`).
    """
  end

  defp provenance(census) do
    r = census["run"]

    """
    ## Provenance

    This run was **accepted** by `mix conformance.adjudicate`; no figure below could
    have been produced otherwise, because `mix conformance.census` calls the same
    `judge/3`. Acceptance makes these figures *attributable to the tree named here*,
    not *correct* — adapter fidelity is a separate question and is not established by
    any of this.

    | | |
    |---|---|
    | commit | `#{r["commit"]}` (branch `#{r["branch"]}`) |
    | adapter | `#{r["adapter_command"]}` |
    | harness | #{r["harness_version_reported"]}, dist sha256 `#{r["harness_dist_sha256"]}` |
    | requirement set | #{r["requirements_revision"]}, md5 `#{r["requirements_md5"]}` |
    | manifest sha256 | `#{r["manifest_sha256"]}` |
    | console sha256 | `#{r["console_sha256"]}` |
    | expected.txt sha256 | `#{r["expected_sha256"]}` |

    Hashes are printed **in full**. `--expect-harness-dist-sha256` and
    `--expect-requirements-md5` compare literally, so a value shortened to fit a column
    refuses when it is pasted back — the same trap as a short SHA under
    `--expect-commit`.

    | harness exit code | #{r["harness_exit_code"]} — recorded, **not** a gate (S5-6) |
    | started | #{r["started_at"]} |
    | run directory | `#{r["run_dir"]}` |
    """
  end

  defp denominator(census) do
    e = census["expected"]
    t = census["totals"]
    leg = census["run"]["leg"]

    """
    ## The denominator

    The frozen set requires #{t["expected_counts"]["scored"]} scored and
    #{t["expected_counts"]["not_scored"]} not-scored #{leg} scenarios, i.e.
    #{t["expected_counts"]["scored"] + t["expected_counts"]["not_scored"]} to run.
    This run ran #{length(census["scenarios"])}.

    - **Scored scenarios absent:** #{render_ids(e["absent_scored"])} — any one of these
      refuses the run outright (`SCORED_SCENARIO_ABSENT`), so this list being empty is a
      checked fact rather than an assumption.
    - **Not-scored scenarios absent:** #{render_ids(e["absent_not_scored"])} — reported and
      never refusing; they cannot move a rate.
    - **Ran but outside the frozen set:** #{render_ids(e["ran_outside_frozen_set"])}.
    """
  end

  defp reducer_table(census) do
    rows =
      census["totals"]["by_reducer"]
      |> Enum.sort()
      |> Enum.map_join("\n", fn {name, t} ->
        "| `#{name}` | #{t["scored"]["passed"]}/#{t["scored"]["total"]} | " <>
          "#{t["all_ran"]["passed"]}/#{t["all_ran"]["total"]} | #{render_ids(t["scored"]["failing"])} |"
      end)

    checks = census["totals"]["checks"]

    """
    ## Result, by reducer

    There is no single "pass rate": the harness applies three different rules and they
    do not agree. Each row names its own.

    | reducer | scored | all scenarios run | scored scenarios failing |
    |---|---|---|---|
    #{rows}

    Check-level census over the scored scenarios:
    #{status_line(checks["scored"])}

    Over every scenario run, scored or not:
    #{status_line(checks["all_ran"])}
    """
  end

  defp status_line(counts) do
    Census.statuses()
    |> Enum.map_join(", ", &"#{&1} #{counts[&1]}")
    |> then(&"#{&1} (#{counts["total"]} checks).")
  end

  defp control_section(%{"totals" => %{"control" => nil}} = census) do
    """
    ## Null-implementation control

    **NOT JOINED.** No figure here states how many of these passes a #{null_noun(census)}
    with no implementation also earns, so the headline's meaning is unbounded from below.
    """
  end

  defp control_section(census) do
    c = census["totals"]["control"]

    """
    ## Null-implementation control

    #{null_description(census)}

    - Control run: `#{c["run_dir"]}`, adapter `#{c["adapter_command"]}`.
    - Control scored result under `#{c["reducer"]}`:
      **#{c["control_passed_scored"]["passed"]}/#{c["control_passed_scored"]["total"]}**.
    - **Ours alone (#{length(c["discriminating"])}):** scenarios we pass and the null does not.
    - **Inherited (#{length(c["inherited"])}):** #{render_ids(c["inherited"])} — we pass these and so
      does a #{null_noun(census)} with no implementation.
    - **Coverage, which is what makes the subtraction legal:** the control ran every scored
      scenario this run measured. Scored scenarios missing from the control:
      #{render_ids(c["not_in_control"])} — a census carrying any is refused
      (`CONTROL_MISSING_SCENARIOS`) before this table exists, so the empty list is a checked
      fact and not an assumption. Not-scored scenarios missing from the control:
      #{render_ids(c["not_in_control_not_scored"])}; scenarios the control ran and this run did
      not: #{render_ids(c["in_control_only"])} — both reported, neither able to move a figure
      quoted over the scored set.
    """
  end

  defp empties(census) do
    e = census["totals"]["empty_scenarios"]

    """
    ## Scenarios that measured nothing

    A scenario can be marked ✓ having asked nothing — zero checks, or no SUCCESS and no
    FAILURE among them. Enumerated before any N/M above is read.

    - Scored: #{render_ids(e["scored"])}
    - All run: #{render_ids(e["all_ran"])}
    """
  end

  defp classification(census) do
    t = census["totals"]["classification"]

    rows =
      Enum.map_join(Classification.classes(), "\n", fn class ->
        key = Atom.to_string(class)
        bucket = t["by_class"][key]
        origin = if class in Classification.harness_classes(), do: "harness", else: "ours"

        "| `#{key}` | #{origin} | #{bucket["count"]} | #{render_ids(bucket["scenarios"])} |"
      end)

    """
    ## Every non-pass, by class

    All #{length(Classification.classes())} classes are listed, **including the ones nothing
    was filed under**. An absent bucket and an empty bucket look the same in a table and mean
    opposite things: a zero here is a measured result, a missing row is an unanswered
    question. `origin` says whose judgement the class is — `harness` classes restate the
    frozen set's own `not_scored` reason and are not ours to argue with; `ours` classes are
    assertions this ticket owns.

    | class | origin | count | scenarios |
    |---|---|---|---|
    #{rows}

    #{t["classified"]} non-passes classified, and the census refuses both ways: a non-pass
    with no entry, and an entry for a scenario that now passes.
    """
  end

  defp scenario_table(census) do
    joined? = census["totals"]["control"] != nil
    rows = Enum.map_join(census["scenarios"], "\n", &scenario_row(&1, joined?))

    """
    ## Per-scenario

    `verdict` is under the leg's own summary reducer. `S/F/W/K/I` are SUCCESS, FAILURE,
    WARNING, SKIPPED, INFO. Under `null`: `pass`/`fail` is the control's own verdict,
    `not run` means a control was joined and did not run this scenario, and `—` means no
    control was joined at all. The last two rendered identically until MES-56 round 1, and
    they mean opposite things.

    | scenario | scored | verdict | S/F/W/K/I | empty | null | class | owner |
    |---|---|---|---|---|---|---|---|
    #{rows}
    """
  end

  defp scenario_row(s, control_joined?) do
    c = s["checks"]
    class = s["classification"]

    "| `#{s["id"]}` | #{yn(s["scored"])} | #{if s["passes"]["server_summary_or_client_summary"], do: "PASS", else: "FAIL"} | " <>
      "#{c["SUCCESS"]}/#{c["FAILURE"]}/#{c["WARNING"]}/#{c["SKIPPED"]}/#{c["INFO"]} | " <>
      "#{yn(s["empty"])} | #{control_cell(s, control_joined?)} | #{if class, do: class["class"], else: "—"} | " <>
      "#{if class, do: class["owner"], else: "—"} |"
  end

  defp control_cell(%{"control" => nil}, false), do: "—"
  defp control_cell(%{"control" => nil}, true), do: "not run"

  # Under the LEG'S OWN summary reducer, the same one the row's own verdict is
  # printed under. It read `requirements_exit` until MES-57, which put the
  # measurement and the control in one row under two different reducers with
  # nothing saying so — the exact defect this file's moduledoc says it exists to
  # prevent, one column to the left of where it was being prevented.
  #
  # It cannot move a server figure: `requirements_exit` and `server_summary`
  # have identical dispositions over all five statuses, so they agree scenario
  # by scenario, and MES-56's committed table re-renders byte-identically (held
  # by a test). It CAN move a client one: `client_summary` fails a WARNING that
  # the other two ignore, and a null that merely warns would otherwise be
  # printed as "pass" and subtracted from the honest figure.
  defp control_cell(%{"control" => c}, _joined?),
    do: if(c["passes"]["server_summary_or_client_summary"], do: "pass", else: "fail")

  defp reducer_definitions(census) do
    rows =
      census["reducers"]
      |> Enum.sort()
      |> Enum.map_join("\n", fn {name, spec} ->
        d = spec["disposition"]

        "| `#{name}` | #{spec["scope"]} | " <>
          Enum.map_join(Census.statuses(), " ", &"#{&1}=#{d[&1]}") <>
          " | #{spec["source"]} |"
      end)

    """
    ## Reducer definitions

    Every reducer states what it does with **all five** check statuses, including
    `INFO`, which none of them consumes. A status quietly dropped from a denominator is
    the same defect as a scenario quietly absent from one.

    | reducer | scope | SUCCESS / FAILURE / WARNING / SKIPPED / INFO | where it comes from |
    |---|---|---|---|
    #{rows}
    """
  end

  # MES-57 round 4, and the same defect as the classification reason corrected in
  # the same commit: a sentence describing the SERVER leg's control was rendered
  # into the CLIENT census too. It read "a server that answers `-32601` to every
  # method" directly above a bullet naming `null_client_connect.py` — a Python
  # NULL CLIENT that opens a TCP socket, sends no byte and exits 0. It answers
  # nothing to anything, because nothing asks it. The contradiction was two lines
  # apart in the published file, which is how C1 read as well.
  #
  # The server sentence is reproduced here verbatim so the MES-56 markdown on
  # main re-renders byte-identically; only the client branch is new.
  #
  # The client sentence deliberately does NOT describe how the null behaves. It
  # cannot: three nulls of increasing strictness exist on this leg, and they
  # differ on exactly that (exit at once / connect and say nothing / send one
  # well-formed request for a nonexistent method). Any concrete description would
  # be false for two of the three. The adapter bullet immediately below names
  # which one ran, which is the fact rather than a paraphrase of it.
  defp null_description(census) do
    case census["run"]["leg"] do
      "client" ->
        """
        A null client — one that implements no MCP client behaviour at all — was run
        through the same suite; the adapter that produced it is named below. Any scenario
        it passes is one whose checks cannot distinguish this SDK from its absence.\
        """

      _ ->
        """
        A server that answers `-32601` to every method, implementing no MCP behaviour at
        all, was run through the same suite. Any scenario it passes is one whose checks
        cannot distinguish this SDK from its absence.\
        """
    end
  end

  defp null_noun(%{"run" => %{"leg" => "client"}}), do: "client"
  defp null_noun(_census), do: "server"

  defp render_ids([]), do: "none"
  defp render_ids(ids), do: Enum.map_join(ids, ", ", &"`#{&1}`")

  defp yn(true), do: "yes"
  defp yn(_), do: "no"
end

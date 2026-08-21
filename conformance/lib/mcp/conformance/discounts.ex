defmodule MCP.Conformance.Discounts do
  @moduledoc """
  The client leg's headline figure, derived from censuses rather than counted by
  hand.

  ## Why this is code and not a paragraph in a report

  MES-24's defect was a hand-written table drifting from the run it claimed to
  describe. This is the same hazard aimed at the single number the whole ticket
  exists to produce, so the number is a **projection of the census** and the
  Markdown is rendered from it.

  ## The two discounts, and why they are reported as THREE figures and never one

  Sprint 4 measured 7 of 7 core client scenarios passing as driven, and two
  separate subtractions apply:

    * **drive-policy** — a scenario that passes only because
      `conformance/client_adapter.exs` keeps driving after
      `MCP.Client.connect/1` errored. Measured, not asserted: the
      `strict_connect` PROBE re-runs the same scenario against the same fixture
      at the same tree, halting on a connect error, and a scenario that goes red
      under the probe and stays green under the measurement adapter is one whose
      pass depends on the policy.
    * **null-passable** — a scenario a null client also passes, so its checks
      cannot distinguish this SDK from its absence.

  Two units independently published "6 of 7" over **different** sets before
  anyone noticed: two right-looking answers to two different questions. So
  `derive/1` returns both intermediates as well as the endpoints, and
  `to_markdown/1` prints all four lines. Publishing a bare "6 of 7" without
  saying which subtraction produced it is the defect MES-19 shipped a correction
  round for.

  ## The in-scope denominator, derived rather than declared

  ADR-003 puts the authorization profile out of 2.0.0, and 25 of the client
  leg's 32 scored scenarios are in it. In-scope is therefore **the scored client
  scenarios whose id is not in the `auth/` namespace**.

  That derivation uses a fact the HARNESS authors — the scenario id's namespace —
  and not our own classification table. Deriving it from the table would have
  been wrong in a way that is worth stating, because it looks right:
  `auth/resource-mismatch` is scored, it PASSES, and a passing scenario carries
  no classification entry (the census refuses an entry for a scenario that
  passes). A table-driven derivation would therefore have counted that one auth
  scenario as in-scope and reported the core figure over a denominator of 8.

  Extensions need no subtraction here: the frozen set already files them under
  `not_scored`, so they are outside `scored` before this module sees them.

  ## What the null-passable subtraction depends on, stated because it bites

  On this leg "the null control" is not one number: a **stricter** null scores
  **lower**. So "a scenario a null also passes" depends on WHICH null, and this
  module takes the union — a scenario is null-passable if **any** of the nulls
  passes it. That is the reading least flattering to the SDK, and it is the one
  Sprint 4's figure was computed under.

  `per_null` reports each null separately so the choice is visible rather than
  folded into the headline.

  ## Reducer

  Every verdict here is read from `passes.server_summary_or_client_summary` —
  the leg's OWN summary reducer, which on the client leg fails a WARNING that
  the other two reducers ignore. Reading the control under `requirements_exit`
  while reading the measurement under `client_summary` is the leg-dependence
  that made Sprint 4 quote two different numbers for one run.
  """

  @verdict "server_summary_or_client_summary"

  @typedoc "One derived headline, every set enumerated rather than counted (A2d)."
  @type t :: %{
          in_scope: [String.t()],
          as_driven: [String.t()],
          drive_policy_removed: [String.t()],
          null_passable_removed: [String.t()],
          after_drive_policy: [String.t()],
          after_null_passable: [String.t()],
          surviving_both: [String.t()],
          per_null: %{String.t() => %{passed_in_scope: [String.t()], scored: map()}},
          probe_scope: [String.t()],
          probe: %{String.t() => boolean()},
          raw: %{scored_passed: [String.t()], scored_total: non_neg_integer()},
          excluded_auth: [String.t()]
        }

  @doc """
  Derive the headline.

  Options:

    * `:measurement` — the measurement census (required)
    * `:nulls` — `%{name => census}` for every null control run (required)
    * `:probe` — the `strict_connect` census, or `nil`
    * `:probe_scope` — the scenarios the probe DRIVES, from
      `MCP.Conformance.Adapters.scope/2`. Required whenever `:probe` is given,
      and required rather than defaulted for a measured reason: the probe drives
      one scenario and takes the not-driven path for the other 38, so reading
      its whole sheet subtracts 6 of 7 in-scope scenarios and reports **0 of 7**
      — a catastrophic-looking headline manufactured entirely by reading a
      narrow instrument as a wide one. A default of "all" would have made that
      the quiet behaviour.

  Raises rather than returning an error tuple: every input is a census this
  tooling has already ACCEPTED and written, so a shape problem here is a bug in
  this repository and not a condition to be handled.
  """
  @spec derive(keyword()) :: t()
  def derive(opts) do
    measurement = Keyword.fetch!(opts, :measurement)
    nulls = Keyword.fetch!(opts, :nulls)
    probe = Keyword.get(opts, :probe)
    probe_scope = probe_scope!(probe, Keyword.get(opts, :probe_scope))

    scored = for s <- measurement["scenarios"], s["scored"], do: s
    in_scope = for s <- scored, not auth?(s["id"]), do: s["id"]
    as_driven = for s <- scored, not auth?(s["id"]), passed?(s), do: s["id"]

    drive_policy = drive_policy_removed(as_driven, probe, probe_scope)
    null_passable = null_passable_removed(as_driven, nulls)

    %{
      in_scope: Enum.sort(in_scope),
      as_driven: Enum.sort(as_driven),
      drive_policy_removed: Enum.sort(drive_policy),
      null_passable_removed: Enum.sort(null_passable),
      after_drive_policy: Enum.sort(as_driven -- drive_policy),
      after_null_passable: Enum.sort(as_driven -- null_passable),
      surviving_both: Enum.sort(as_driven -- (drive_policy ++ null_passable)),
      per_null: per_null(nulls, in_scope),
      probe_scope: probe_scope,
      probe: probe_verdicts(probe, probe_scope),
      raw: %{
        scored_passed: Enum.sort(for s <- scored, passed?(s), do: s["id"]),
        scored_total: length(scored)
      },
      excluded_auth: Enum.sort(for s <- scored, auth?(s["id"]), do: s["id"])
    }
  end

  defp probe_scope!(nil, _scope), do: []

  defp probe_scope!(_probe, scope) when scope in [nil, :all] do
    raise ArgumentError,
          "a probe census was given without an explicit :probe_scope. The probe drives " <>
            "fewer scenarios than the measurement, so its other rows are not results; " <>
            "reading them as failures produces a plausible headline that is wrong by the " <>
            "width of the instrument."
  end

  defp probe_scope!(_probe, scope), do: Enum.sort(scope)

  # Restricted to the probe's own scope. Outside it the probe says nothing, and
  # "said nothing" must not read as "failed".
  defp drive_policy_removed(_as_driven, nil, _scope), do: []

  defp drive_policy_removed(as_driven, probe, scope) do
    for id <- as_driven, id in scope, not passed_in?(probe, id), do: id
  end

  # The UNION over every null, which is the reading least flattering to the SDK.
  # See the moduledoc: on this leg a stricter null scores lower, so taking only
  # the strictest would have published a larger figure.
  defp null_passable_removed(as_driven, nulls) do
    for id <- as_driven,
        Enum.any?(nulls, fn {_name, census} -> passed_in?(census, id) end),
        do: id
  end

  defp per_null(nulls, in_scope) do
    Map.new(nulls, fn {name, census} ->
      {name,
       %{
         passed_in_scope: Enum.sort(for id <- in_scope, passed_in?(census, id), do: id),
         scored: get_in(census, ["totals", "by_reducer", "client_summary", "scored"])
       }}
    end)
  end

  defp probe_verdicts(nil, _scope), do: %{}
  defp probe_verdicts(probe, scope), do: Map.new(scope, &{&1, passed_in?(probe, &1)})

  # The harness's own namespace, not our judgement. See the moduledoc for why
  # this is NOT read off `MCP.Conformance.Classification`.
  defp auth?(id), do: String.starts_with?(id, "auth/")

  defp passed?(scenario), do: scenario["passes"][@verdict]

  defp passed_in?(census, id) do
    case Enum.find(census["scenarios"], &(&1["id"] == id)) do
      nil -> false
      s -> passed?(s)
    end
  end

  @doc """
  Render `derive/1`'s result as Markdown.

  Rendered FROM the derivation, never written beside it, for the same reason
  `MCP.Conformance.CensusMarkdown` exists: a committed table that can drift from
  the figures it reports is MES-24's defect, and the only reliable fix is to make
  the table a projection rather than a copy.
  """
  @spec to_markdown(t(), map()) :: String.t()
  def to_markdown(d, meta) do
    n = length(d.in_scope)

    """
    # Client leg — the in-scope figure and the two discounts

    Rendered from `MCP.Conformance.Discounts`, which reads the committed censuses.
    Do not edit: regenerate with `mix conformance.discounts`.

    Measurement run: commit `#{meta["commit"]}`, harness
    `#{meta["harness_version_reported"]}`, requirements `#{meta["requirements_revision"]}`.

    ## The headline, and every subtraction behind it

    Every verdict below is under the leg's own summary reducer
    (`client_summary`), which **fails a WARNING** that `requirements_exit` and
    `server_summary` both ignore.

    | figure | value | scenarios removed |
    | --- | --- | --- |
    | as driven | **#{length(d.as_driven)} of #{n}** | — |
    | after drive-policy only | **#{length(d.after_drive_policy)} of #{n}** | #{ids(d.drive_policy_removed)} |
    | after null-passable only | **#{length(d.after_null_passable)} of #{n}** | #{ids(d.null_passable_removed)} |
    | **surviving BOTH** | **#{length(d.surviving_both)} of #{n}** | #{ids(Enum.uniq(d.drive_policy_removed ++ d.null_passable_removed))} |

    The two middle rows are published rather than the endpoints because they are
    the same number over **different sets**. Two units independently produced
    "6 of 7" from those two rows before anyone noticed they were answering
    different questions.

    Surviving both: #{ids(d.surviving_both)}.

    ## The in-scope denominator

    #{n} scenarios: #{ids(d.in_scope)}.

    In-scope is the scored client scenarios **not in the `auth/` namespace** —
    the authorization profile, which ADR-003 puts out of 2.0.0.
    #{length(d.excluded_auth)} scored scenarios are excluded on that ground, and
    they are named rather than counted: #{ids(d.excluded_auth)}.

    The raw figure is **#{length(d.raw.scored_passed)} of #{d.raw.scored_total}**,
    and it may appear only beside that exclusion, never as a bare pass rate. It
    is larger than the in-scope numerator by exactly the auth scenarios that
    pass: #{ids(d.raw.scored_passed -- d.as_driven)}.

    ## Discount 1 — drive-policy, re-derived by measurement

    The `strict_connect` probe drives one scenario under one changed policy: it
    halts the moment `MCP.Client.connect/1` errors, where the measurement adapter
    logs and carries on. A scenario that goes red under the probe and stays green
    under the measurement adapter is one whose pass depends on our policy rather
    than on a property of the SDK.

    The probe drives **only** #{ids(d.probe_scope)} — the scenario the claim is
    about. Every other scenario takes its not-driven path, so its other rows are
    not results and are not shown. Reading them as failures would report
    "0 of #{n}".

    | scenario | measurement | strict-connect probe |
    | --- | --- | --- |
    #{Enum.map_join(d.probe_scope, "\n", &probe_row(&1, d))}

    ## Discount 2 — null-passable, and which null

    A scenario is null-passable if **any** null client passes it — the reading
    least flattering to this SDK, and the one Sprint 4's figure was computed
    under. Which null matters, because a **stricter** null scores **lower**:

    | null control | scored (client_summary) | in-scope scenarios it passes |
    | --- | --- | --- |
    #{Enum.map_join(Enum.sort(Map.keys(d.per_null)), "\n", &null_row(&1, d))}

    Removed on this ground: #{ids(d.null_passable_removed)}.
    """
  end

  defp probe_row(id, d) do
    measurement = if id in d.as_driven, do: "PASS", else: "FAIL"

    probe =
      case Map.get(d.probe, id) do
        nil -> "not run"
        true -> "PASS"
        false -> "FAIL"
      end

    "| `#{id}` | #{measurement} | #{probe} |"
  end

  defp null_row(name, d) do
    entry = Map.fetch!(d.per_null, name)
    scored = entry.scored

    "| `#{name}` | #{scored["passed"]}/#{scored["total"]} | #{ids(entry.passed_in_scope)} |"
  end

  defp ids([]), do: "none"
  defp ids(list), do: Enum.map_join(list, ", ", &"`#{&1}`")
end

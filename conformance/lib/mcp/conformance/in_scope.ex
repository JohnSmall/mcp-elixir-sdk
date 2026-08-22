defmodule MCP.Conformance.InScope do
  @moduledoc """
  The frozen in-scope subset of the 2026-07-28 conformance suite, and the key
  that addresses one check inside it.

  Sprint 6 exists to establish every difference between our ET-CC figures and
  the official harness's before anything is fixed. Every ticket downstream of
  A1 counts against the manifest this module derives, so if the manifest is
  wrong they are all wrong together and nothing detects it. That is why it is
  **generated from the run artefacts** rather than written by hand: a
  hand-written table is the MES-24 defect, and it cannot re-derive anything.

  ## The scope rule, and the derivation that looks right and is not

  In scope is **the scored scenarios, minus (client leg) everything in the
  `auth/` namespace** — ADR-003 puts the authorization profile out of 2.0.0.

  The namespace is a fact the HARNESS authors. Deriving scope instead from our
  own census `classification.class` — "scored and not `out_of_scope_adr_003`" —
  yields 8 scenarios / 57 checks against the correct 7 / 56, and it yields it
  silently. The extra is `auth/resource-mismatch`: scored, one check, and it
  **passes**, so it carries `classification: null`, because the classification
  table explains why a scenario FAILED and has nothing to say about one that
  succeeded.

  A scope rule read off a field that only speaks about failures will always be
  wrong about the things that succeed, and it is wrong in the flattering
  direction. Three not-scored scenarios share the shape for the same reason —
  `tasks-status-notifications`, `json-schema-2020-12`,
  `json-schema-2020-12-preservation` all pass and all carry no class. So the
  exclusion reasons here come from the **frozen requirement set** (the census's
  `harness_reason`, mirrored in `expected.not_scored`), never from the
  classification table.

  ## The check key

      {leg, scenario, check id, name, description, discriminator}

  There is no naturally unique check key, and the two candidates the brief
  offered were both wrong:

    * **raw `details`** is unique and is the wrong thing to be unique on.
      `details.response` holds the server's entire reply. A key containing it
      changes whenever the implementation's behaviour changes — which is
      exactly when the crosswalk has to keep holding, because Sprint 6 exists
      so Sprint 7 can be measured against it. Every remediated check would
      present as one key vanishing and an unrelated one appearing.
    * **global ordinal** is unique and makes every row's identity positional.
      One inserted record renumbers every later row in the scenario, so a
      crosswalk keeps matching — to the wrong records, silently. Not
      hypothetical: `getChecks()` synthesises absent checks and appends them,
      so both the count and the order are functions of what the implementation
      did.

  So the discriminator is assigned by an ordered rule, and **the rule that
  fired is recorded on every row** as `discriminator_source`. That makes the
  residual queryable rather than merely stated: a reader can ask which rows are
  positional instead of trusting a paragraph.

    1. `unique` — the row is already alone on `{scenario, id, name,
       description}`. Discriminator empty.
    2. `field_issue` — tied, and the tied rows carry pairwise-distinct
       `details.fieldIssue`. Discriminator is that slug.
    3. `ordinal` — tied and rule 2 cannot separate them. Discriminator is the
       row's position **within its tie-group**, never within the scenario.

  Rule 2 is admissible where raw `details` is not, and that was established
  from the harness rather than assumed: the emitter is `fieldIssue: e.slug`
  where `e` ranges over a literal array of case descriptors declared in the
  scenario, so the slug is a property of the **scenario definition**, not of
  our response.

  Rule 3 exists with no members so that a future tie is keyed rather than
  dropped or crashed on. When it fires those rows ARE positional, and
  everything said above against global ordinal applies to them — which is what
  the per-row flag is for.
  """

  alias MCP.Conformance.Provenance

  # Carried VERBATIM. The PO ratified the "structurally unreachable" wording,
  # not a paraphrase of it, and `in_scope_manifest_test.exs` asserts the
  # committed file is byte-equal to this constant so a reword fails gate 5
  # rather than passing review.
  @match_target_rule "A check is a match target only if a conforming 2026-07-28 implementation can cause it to evaluate."

  @wording_note """
  Stated as "structurally unreachable for a conforming implementation", NOT as \
  "SKIPPED is excluded". The distinction is load-bearing: a check skipped because \
  our implementation did not exercise an optional but available path is a COVERAGE \
  GAP, not an exclusion. There are no such checks in the current in-scope run, so \
  the rule is written to distinguish them anyway — otherwise the next one is dropped \
  silently on this precedent.\
  """

  @member_set_owner "MES-70 (A5)"

  @revision "2026-07-28"
  @manifest_schema_version 1
  @generated_by "mix conformance.in_scope"

  @key_fields ~w(leg scenario check_id name description discriminator)

  @discriminator_rules [
    %{
      "rule" => "unique",
      "order" => 1,
      "when" => "the row is alone on {scenario, id, name, description}",
      "discriminator" => "empty string"
    },
    %{
      "rule" => "field_issue",
      "order" => 2,
      "when" => "tied, and the tied rows carry pairwise-distinct details.fieldIssue",
      "discriminator" => "that slug, which the scenario definition declares"
    },
    %{
      "rule" => "ordinal",
      "order" => 3,
      "when" => "tied and rule 2 cannot separate them",
      "discriminator" => "1-based position WITHIN THE TIE-GROUP, never within the scenario"
    }
  ]

  @typedoc "One leg's inputs: the ACCEPTED census, and the run tree it was written from."
  @type leg_input :: %{leg: String.t(), census: map(), run_dir: String.t()}

  @typedoc "The manifest, as written to disk."
  @type t :: map()

  @doc "The ratified match-target rule, verbatim."
  @spec match_target_rule() :: String.t()
  def match_target_rule, do: @match_target_rule

  @doc "The revision this manifest freezes."
  @spec revision() :: String.t()
  def revision, do: @revision

  @doc "The key's field names, in key order."
  @spec key_fields() :: [String.t()]
  def key_fields, do: @key_fields

  @doc "The ordered discriminator rules."
  @spec discriminator_rules() :: [map()]
  def discriminator_rules, do: @discriminator_rules

  @doc """
  Is this scenario in the frozen in-scope subset?

  Two arguments rather than one because the rule is per leg, and a single
  predicate that guessed the leg from the scenario id would be the same class
  of silent wrongness this module exists to avoid.
  """
  @spec in_scope?(String.t(), map()) :: boolean()
  def in_scope?("server", scenario), do: !!scenario["scored"]
  def in_scope?("client", scenario), do: !!scenario["scored"] and not auth?(scenario["id"])

  @doc """
  Derive the manifest from one accepted census and run tree per leg.

  Raises rather than returning an error tuple: every input is a census this
  tooling has already ADJUDICATED and written, so a shape problem here is a bug
  in this repository and not a condition to be handled.
  """
  @spec derive([leg_input()]) :: t()
  def derive(inputs) do
    scenarios = Enum.flat_map(inputs, &leg_scenarios/1)
    excluded = Enum.flat_map(inputs, &leg_exclusions/1)

    %{
      "manifest_schema_version" => @manifest_schema_version,
      "revision" => @revision,
      "generated_by" => @generated_by,
      "provenance" => Map.new(inputs, &{&1.leg, leg_provenance(&1)}),
      "derivation" => %{
        "rule" =>
          "In scope = the SCORED scenarios of the frozen #{@revision} requirement set, " <>
            "minus (client leg only) every scenario in the `auth/` namespace, which ADR-003 " <>
            "puts out of 2.0.0. Scope is read from the scenario id's namespace — a fact the " <>
            "harness authors — and NEVER from our own classification table.",
        "why_not_classification" =>
          "`classification.class` explains why a scenario FAILED, so it is null for every " <>
            "scenario that passes. Filtering on it readmits `auth/resource-mismatch` (scored, " <>
            "1 check, passing) and yields a plausible 8 scenarios / 57 checks against the " <>
            "correct 7 / 56.",
        "excluded" => excluded
      },
      "check_key" => check_key_block(scenarios),
      "match_target_rule" => %{
        "text" => @match_target_rule,
        "wording_note" => @wording_note,
        "member_set_owner" => @member_set_owner,
        "applied_by" => "MES-66 (A1) states the rule; it does not enumerate its members."
      },
      "arithmetic" => arithmetic(scenarios),
      "totals" => totals(scenarios),
      "residual" => residual(),
      "scenarios" => scenarios
    }
  end

  # --- scope ---------------------------------------------------------------

  defp auth?(id), do: String.starts_with?(id, "auth/")

  defp leg_scenarios(%{leg: leg, census: census, run_dir: run_dir}) do
    census["scenarios"]
    |> Enum.filter(&in_scope?(leg, &1))
    |> Enum.sort_by(& &1["id"])
    |> Enum.map(fn scenario ->
      checks = read_checks!(run_dir, scenario)

      %{
        "leg" => leg,
        "scenario" => scenario["id"],
        "artefact_dir" => scenario["artefact_dir"],
        "checks" => key_checks(leg, scenario["id"], checks)
      }
    end)
  end

  # Every exclusion is NAMED with a reason (A2d). A count is not an
  # enumeration, and the two mechanisms are kept apart because they are not the
  # same kind of exclusion: one is the frozen requirement set declining to
  # score a scenario, the other is an ADR putting a whole namespace out of the
  # release.
  defp leg_exclusions(%{leg: leg, census: census}) do
    census["scenarios"]
    |> Enum.reject(&in_scope?(leg, &1))
    |> Enum.sort_by(& &1["id"])
    |> Enum.map(fn scenario ->
      %{
        "leg" => leg,
        "scenario" => scenario["id"],
        "checks" => get_in(scenario, ["checks", "total"]),
        "mechanism" => exclusion_mechanism(scenario),
        "reason" => exclusion_reason(scenario)
      }
    end)
  end

  defp exclusion_mechanism(%{"scored" => true}), do: "adr_003_auth_namespace"
  defp exclusion_mechanism(_), do: "not_scored_by_frozen_set"

  defp exclusion_reason(%{"scored" => true} = scenario) do
    "ADR-003 puts the OAuth 2.1 authorization profile out of 2.0.0. `#{scenario["id"]}` is " <>
      "scored by the frozen set and so sits inside the raw n/32, but outside the in-scope " <>
      "denominator."
  end

  defp exclusion_reason(scenario) do
    case scenario["harness_reason"] do
      "extension" ->
        "Not scored by the frozen #{@revision} set: an extension, not part of the revision."

      "pending" ->
        "Not scored by the frozen #{@revision} set: pending — the harness does not yet " <>
          "hold it to the revision."

      "added-after-release" ->
        "Not scored by the frozen #{@revision} set: added to the harness after the " <>
          "revision was released."

      other ->
        "Not scored by the frozen #{@revision} set; reason recorded by the set as " <>
          "#{inspect(other)}."
    end
  end

  defp read_checks!(run_dir, scenario) do
    run_dir
    |> Path.join(scenario["artefact_dir"])
    |> Path.join("checks.json")
    |> File.read!()
    |> Jason.decode!()
  end

  # --- the key -------------------------------------------------------------

  @doc """
  Key one scenario's check records, assigning each row's discriminator by the
  ordered rule and recording which rule fired.

  Exposed so a test can key a synthesised sheet — the positive controls need to
  drive this and nothing else.
  """
  @spec key_checks(String.t(), String.t(), [map()]) :: [map()]
  def key_checks(leg, scenario, checks) do
    groups = Enum.group_by(checks, &identity/1)

    checks
    |> Enum.map_reduce(%{}, fn check, seen ->
      identity = identity(check)
      group = Map.fetch!(groups, identity)
      position = Map.get(seen, identity, 0) + 1
      {source, discriminator} = discriminate(group, check, position)

      row = %{
        "key" => [leg, scenario, check["id"], check["name"], check["description"], discriminator],
        "id" => check["id"],
        "name" => check["name"],
        "description" => check["description"],
        "status" => check["status"],
        "errorMessage" => check["errorMessage"],
        "discriminator" => discriminator,
        "discriminator_source" => source
      }

      {row, Map.put(seen, identity, position)}
    end)
    |> elem(0)
  end

  defp identity(check), do: {check["id"], check["name"], check["description"]}

  defp discriminate([_only], _check, _position), do: {"unique", ""}

  defp discriminate(group, check, position) do
    slugs = Enum.map(group, &field_issue/1)

    if Enum.all?(slugs, &is_binary/1) and length(Enum.uniq(slugs)) == length(slugs) do
      {"field_issue", field_issue(check)}
    else
      {"ordinal", Integer.to_string(position)}
    end
  end

  defp field_issue(check), do: get_in(check, ["details", "fieldIssue"])

  # --- blocks --------------------------------------------------------------

  defp check_key_block(scenarios) do
    rows = all_rows(scenarios)

    %{
      "fields" => @key_fields,
      "shape" => "an ordered array of the six field values, in `fields` order",
      "discriminator_rules" => @discriminator_rules,
      "rows_by_discriminator_source" =>
        rows
        |> Enum.frequencies_by(& &1["discriminator_source"])
        |> Map.merge(%{"unique" => 0, "field_issue" => 0, "ordinal" => 0}, fn _k, v, _d -> v end),
      "distinct_keys" => rows |> Enum.map(& &1["key"]) |> Enum.uniq() |> length(),
      "rows" => length(rows)
    }
  end

  defp arithmetic(scenarios) do
    %{
      "total" => scenarios |> all_rows() |> length(),
      "in_denominator" => nil,
      "out_of_denominator" => nil,
      "equation" => "total = in_denominator + out_of_denominator",
      "owner" => @member_set_owner,
      "note" =>
        "A1 fixes `total` and the rule. The out-of-denominator term is the set of checks " <>
          "the ratified rule excludes, and enumerating it is A5's job — so `in_denominator` " <>
          "is null here too, because it is the first term minus a set A1 does not own. Every " <>
          "row carries `status` and `errorMessage` so A5 can apply the rule without re-running " <>
          "anything."
    }
  end

  defp totals(scenarios) do
    by_leg =
      scenarios
      |> Enum.group_by(& &1["leg"])
      |> Map.new(fn {leg, list} ->
        {leg, %{"scenarios" => length(list), "checks" => length(all_rows(list))}}
      end)

    %{
      "scenarios" => length(scenarios),
      "checks" => scenarios |> all_rows() |> length(),
      "by_leg" => by_leg
    }
  end

  defp all_rows(scenarios), do: Enum.flat_map(scenarios, & &1["checks"])

  defp leg_provenance(%{leg: leg, census: census, run_dir: run_dir}) do
    run = census["run"]

    checks_sha256 =
      census["scenarios"]
      |> Enum.filter(&in_scope?(leg, &1))
      |> Enum.sort_by(& &1["id"])
      |> Map.new(fn scenario ->
        path = Path.join([run_dir, scenario["artefact_dir"], "checks.json"])
        {scenario["id"], Provenance.sha256_file(path)}
      end)

    %{
      "run_dir" => run["run_dir"],
      "read_from" => run_dir,
      "commit" => run["commit"],
      "branch" => run["branch"],
      "harness_dist_sha256" => run["harness_dist_sha256"],
      "harness_version_reported" => run["harness_version_reported"],
      "requirements_revision" => run["requirements_revision"],
      "adjudication_verdict" => get_in(run, ["adjudication", "verdict"]),
      "checks_sha256" => checks_sha256
    }
  end

  # --- residual ------------------------------------------------------------

  # Stated in the artefact a reader actually opens, not only in a register they
  # have no reason to open.
  defp residual do
    [
      %{
        "id" => "R1",
        "text" =>
          "3 of the rows hang on `details.fieldIssue`, a slug the harness scenario declares. " <>
            "If upstream renames one, those keys change. It fails VISIBLY — one key " <>
            "disappears and one appears — rather than merging two rows, which is the failure " <>
            "mode being bought off."
      },
      %{
        "id" => "R2",
        "text" =>
          "Rule 3 (`ordinal`) has no members today. It exists so a future tie is keyed rather " <>
            "than dropped or crashed on. When it fires, those rows ARE positional and every " <>
            "objection to a global-ordinal key applies to them. `discriminator_source` is the " <>
            "field to inspect, not the key."
      },
      %{
        "id" => "R3",
        "text" =>
          "The key identifies a check within a leg under ONE harness build. It says nothing " <>
            "across harness versions; a renamed check id is a new key. `provenance." <>
            "*.harness_dist_sha256` is recorded so a version change is visible rather than " <>
            "inferred."
      },
      %{
        "id" => "R4",
        "text" =>
          "The key says nothing about whether a check is reachable, meaningful, or a match " <>
            "target. That is `match_target_rule`'s job and #{@member_set_owner}'s set. A key " <>
            "is an address, not a verdict."
      },
      %{
        "id" => "R5",
        "status" => "CLOSED by construction",
        "text" =>
          "Rule 2 needs `details` to be present, and the harness has a branch that returns " <>
            "`{error: ...}` with no details object. Settled by running the server leg against " <>
            "a dead port, which takes that branch for every check: `details.fieldIssue` is " <>
            "still present and the three slugs are still pairwise distinct. The emitter is " <>
            "`details: s?.details || o` and the call site passes `{fieldIssue: e.slug}` as the " <>
            "fallback `o`, so the slug survives the probe-failure and throw paths alike. Rule " <>
            "3 gains no members from it."
      },
      %{
        "id" => "R6",
        "status" => "OPEN — tracked as MES-72",
        "text" =>
          "This manifest's rows are derived from run trees that live only in /tmp. The " <>
            "`checks_sha256` values recorded above become unverifiable once those trees are " <>
            "cleared, so provenance here is by ASSERTION, not by reproduction — the opposite " <>
            "of what S6-4 established for censuses. The manifest's agreement with the " <>
            "COMMITTED censuses (test T1) is what survives a /tmp wipe, and it is weaker: it " <>
            "checks scenario membership and per-scenario check counts, not the content of any " <>
            "row."
      }
    ]
  end
end

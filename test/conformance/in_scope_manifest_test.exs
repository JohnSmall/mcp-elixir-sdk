defmodule MCP.Conformance.InScopeManifestTest do
  @moduledoc """
  The frozen in-scope manifest is the artefact every ticket downstream of A1
  counts against. If it is wrong they are all wrong together, so these are the
  properties that must hold of the COMMITTED file — read from disk, not from a
  fixture this test also builds.

  ## What each test can actually fail on, in three tiers

  The tiers are not a ranking of importance. They say what a green run is
  EVIDENCE OF, and they differ in what a determined wrong answer would have to
  do to survive them.

    1. **Independent** — `T1`. It compares the manifest to the committed
       CENSUSES, two files this tooling wrote from the run trees on a different
       ticket and which the manifest generator does not author. A manifest
       edited by hand disagrees with them. This is the tier that survives
       `/tmp` being wiped.
    2. **Consistency** — `T5`, and `T2`'s key test. These join the manifest to
       `bucket-0`, or the manifest to itself. `bucket-0` is GENERATED FROM the
       manifest, so agreement between them is not provenance: a fabrication
       that regenerated both would agree. It catches every SINGLE-FILE edit,
       which is the whole of what has ever gone wrong here, and it reaches the
       152 SUCCESS rows that no census `failed_checks` list mentions.
    3. **Internal** — everything else. A wrong-but-tidy manifest satisfies it.

  Stated plainly because a test suite's greenness is easy to over-read: **none
  of these proves the manifest was derived from the accepted RUN TREES**. Those
  are not committed, so the `checks_sha256` values are unverifiable once /tmp is
  cleared. That is residual R6, tracked as MES-72 — narrowed by MES-75, not
  closed.

  ## What tier 1 pins, exactly (MES-75)

  `T1` used to compare only each scenario's check TOTAL, so a row whose status
  was flipped from FAILURE to SUCCESS changed no count, changed no key, and
  passed the whole suite. `status` is the field A5 applied the match-target rule
  to and the field C1 computes the verdict pair from, so that drift would have
  moved every bucket in the epic and nothing would have noticed.

  It now compares, per scenario:

    * the FULL status distribution — `SUCCESS / FAILURE / WARNING / SKIPPED /
      INFO / total` — against the census's `checks` block; and
    * the manifest's FAILURE|WARNING rows against the census's `failed_checks`,
      on id, name, status AND message.

  `failed_checks` is FAILURE|WARNING only, by construction at
  `conformance/lib/mcp/conformance/census.ex:935`
  (`for c <- checks, c["status"] in ["FAILURE", "WARNING"]`). SKIPPED and INFO
  never appear in it, so the 2 SKIPPED rows are pinned by the distribution
  above and by nothing finer. Their `errorMessage` is pinned by no committed
  artefact at all — see R6.

  Both tests iterate the CENSUS's in-scope set and demand a manifest entry for
  each, never the reverse. Driven from the manifest they would both be
  vacuously green on an empty one, which is the exact shape of defect this file
  exists to reject.

  ## The controls (C1-C3), and why they are here rather than in a run log

  A key that cannot be shown to discriminate is an assertion. Each control
  re-keys the manifest's OWN rows under a rejected candidate and demonstrates
  the failure mode, so the case against `details` and against global ordinal is
  a result rather than a paragraph. They need nothing outside this repository,
  so they keep discriminating long after the run trees are gone.

  The same argument applies to this file as a whole, and it is discharged the
  same way: `conformance/controls/manifest_mutation_sweep.exs` mutates the
  committed manifest one row at a time and reads this suite's verdict off each
  mutation. What these tests reject is therefore a measured result, and the
  mutation DEFINITIONS are committed alongside the runner so the measurement
  can be repeated rather than reconstructed from prose (S7-1).
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.InScope

  @manifest_path "docs/conformance/in-scope-2026-07-28.json"
  @bucket_zero_path "docs/conformance/bucket-0-2026-07-28.json"
  @censuses %{
    "server" => "docs/conformance/server-2026-07-28.json",
    "client" => "docs/conformance/client-2026-07-28.json"
  }

  setup_all do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()
    bucket_zero = @bucket_zero_path |> File.read!() |> Jason.decode!()

    censuses =
      Map.new(@censuses, fn {leg, path} -> {leg, path |> File.read!() |> Jason.decode!()} end)

    %{
      manifest: manifest,
      bucket_zero: bucket_zero,
      censuses: censuses,
      rows: rows(manifest)
    }
  end

  describe "T1 — the manifest agrees with the committed censuses" do
    test "the in-scope scenario set is exactly what the scope rule selects", %{
      manifest: manifest,
      censuses: censuses
    } do
      for {leg, census} <- censuses do
        expected =
          census["scenarios"]
          |> Enum.filter(&InScope.in_scope?(leg, &1))
          |> Enum.map(& &1["id"])
          |> Enum.sort()

        actual =
          manifest["scenarios"]
          |> Enum.filter(&(&1["leg"] == leg))
          |> Enum.map(& &1["scenario"])
          |> Enum.sort()

        assert actual == expected,
               "#{leg}: manifest in-scope set differs from the census's. " <>
                 "only in manifest: #{inspect(actual -- expected)}; " <>
                 "only in census: #{inspect(expected -- actual)}"
      end
    end

    # Was: `total` alone. A flipped status changes no total, so the assertion
    # this replaces was green on the one mutation it most needed to reject.
    # Comparing the whole distribution strictly subsumes it — the census's
    # `checks` block carries `total` as one of its keys — so nothing is given up.
    test "every scenario's FULL status distribution is the one the census records", %{
      manifest: manifest,
      censuses: censuses
    } do
      by_scenario =
        Map.new(manifest["scenarios"], &{{&1["leg"], &1["scenario"]}, &1})

      # Driven from the CENSUS. An empty manifest must fail this, not skip it.
      for {leg, census} <- censuses,
          scenario <- census["scenarios"],
          InScope.in_scope?(leg, scenario) do
        entry = by_scenario[{leg, scenario["id"]}]

        assert entry,
               "#{leg}/#{scenario["id"]} is in scope by the rule but absent from the manifest"

        assert distribution(entry["checks"]) == scenario["checks"],
               "#{leg}/#{scenario["id"]}: manifest rows give " <>
                 "#{inspect(distribution(entry["checks"]))}, census records " <>
                 "#{inspect(scenario["checks"])}"
      end
    end

    # AC2. The census's `failed_checks` is FAILURE|WARNING only — `census.ex:935`
    # — so this is the manifest's 21 non-passing rows compared on every field
    # both files carry, and NOT "every non-passing check": the 2 SKIPPED rows
    # appear in no `failed_checks` list and are pinned by the distribution above.
    #
    # A sorted LIST, not a MapSet. The three `field_issue`-tied rows are
    # `sep-2575-http-server-meta-invalid-400` three times over with the same id,
    # name, status and message; a set collapses them to one and stops noticing
    # if two go missing. Equality is bidirectional, so a dropped row and an
    # invented row both fail.
    test "every scenario's FAILURE|WARNING rows match the census's failed_checks", %{
      manifest: manifest,
      censuses: censuses
    } do
      by_scenario =
        Map.new(manifest["scenarios"], &{{&1["leg"], &1["scenario"]}, &1})

      for {leg, census} <- censuses,
          scenario <- census["scenarios"],
          InScope.in_scope?(leg, scenario) do
        entry = by_scenario[{leg, scenario["id"]}]

        assert entry,
               "#{leg}/#{scenario["id"]} is in scope by the rule but absent from the manifest"

        actual =
          entry["checks"]
          |> Enum.filter(&(&1["status"] in ~w(FAILURE WARNING)))
          |> Enum.map(&{&1["id"], &1["name"], &1["status"], &1["errorMessage"]})
          |> Enum.sort()

        expected =
          (scenario["failed_checks"] || [])
          |> Enum.map(&{&1["id"], &1["name"], &1["status"], &1["message"]})
          |> Enum.sort()

        assert actual == expected,
               "#{leg}/#{scenario["id"]}: non-passing rows disagree with the census. " <>
                 "only in manifest: #{inspect(actual -- expected)}; " <>
                 "only in census: #{inspect(expected -- actual)}"
      end
    end

    test "the exclusions are exactly the complement, and each is named with a reason", %{
      manifest: manifest,
      censuses: censuses
    } do
      excluded = manifest["derivation"]["excluded"]

      for {leg, census} <- censuses do
        expected =
          census["scenarios"]
          |> Enum.reject(&InScope.in_scope?(leg, &1))
          |> Enum.map(& &1["id"])
          |> Enum.sort()

        actual =
          excluded
          |> Enum.filter(&(&1["leg"] == leg))
          |> Enum.map(& &1["scenario"])
          |> Enum.sort()

        assert actual == expected,
               "#{leg}: excluded set is not the complement of the in-scope set. " <>
                 "only in manifest: #{inspect(actual -- expected)}; " <>
                 "only in census: #{inspect(expected -- actual)}"
      end

      # A2d: a count is not an enumeration, and a reason field that is present
      # but empty is a count wearing an enumeration's clothes.
      for e <- excluded do
        assert is_binary(e["reason"]) and byte_size(e["reason"]) > 20,
               "#{e["leg"]}/#{e["scenario"]} is excluded without a stated reason"

        assert e["mechanism"] in ~w(not_scored_by_frozen_set adr_003_auth_namespace)
      end
    end

    # Over BOTH legs since MES-75. It used to run over the client leg only,
    # mirroring a scope rule that excluded `auth/` on the client leg only, so
    # the asymmetry was carried identically by the rule and by its guard and
    # neither could catch the other. `in_scope?/2` now excludes the namespace on
    # both legs; this is the assertion that says so, rather than a comment.
    test "no in-scope scenario on EITHER leg is an auth/ one", %{manifest: manifest} do
      for leg <- ~w(server client) do
        offenders =
          manifest["scenarios"]
          |> Enum.filter(&(&1["leg"] == leg))
          |> Enum.map(& &1["scenario"])
          |> Enum.filter(&String.starts_with?(&1, "auth/"))

        assert offenders == [],
               "#{leg}: the auth/ namespace is out of 2.0.0 by ADR-003, in scope anyway: " <>
                 "#{inspect(offenders)}. Deriving scope from classification.class instead " <>
                 "readmits auth/resource-mismatch because it PASSES"
      end
    end
  end

  describe "T2 — the counts and the keys" do
    test "44 scenarios and 175 checks, 37/119 server and 7/56 client", %{manifest: manifest} do
      assert manifest["totals"]["scenarios"] == 44
      assert manifest["totals"]["checks"] == 175
      assert manifest["totals"]["by_leg"]["server"] == %{"scenarios" => 37, "checks" => 119}
      assert manifest["totals"]["by_leg"]["client"] == %{"scenarios" => 7, "checks" => 56}
    end

    test "the totals are a consequence of the rows, not a number beside them", %{
      manifest: manifest,
      rows: rows
    } do
      assert length(rows) == manifest["totals"]["checks"]
      assert length(manifest["scenarios"]) == manifest["totals"]["scenarios"]
    end

    test "every key is distinct, and shaped as the declared six fields", %{
      manifest: manifest,
      rows: rows
    } do
      keys = Enum.map(rows, & &1["key"])

      assert length(Enum.uniq(keys)) == length(keys),
             "keys collide: #{inspect(keys -- Enum.uniq(keys))}"

      assert manifest["check_key"]["fields"] == InScope.key_fields()
      assert Enum.all?(keys, &(length(&1) == 6))
    end

    # Tier 3, and named as such: the key is built FROM these fields by
    # `InScope.key_checks/3`, so this is the file agreeing with itself. It earns
    # its place by catching the one thing the census-driven tests structurally
    # cannot — a SUCCESS row's identity fields edited without its key, which no
    # `failed_checks` list mentions and no count moves.
    test "every row's key is its own six fields, not a value stored beside them", %{rows: rows} do
      drifted =
        Enum.reject(rows, fn row ->
          row["key"] == [
            row["leg"],
            row["scenario"],
            row["id"],
            row["name"],
            row["description"],
            row["discriminator"]
          ]
        end)

      assert drifted == [],
             "#{length(drifted)} rows carry a key that disagrees with their own fields: " <>
               inspect(Enum.map(drifted, &{&1["key"], &1["id"], &1["name"], &1["description"]}))
    end
  end

  describe "T3 — the ratified rule is carried verbatim" do
    test "the committed text is byte-equal to the module constant", %{manifest: manifest} do
      assert manifest["match_target_rule"]["text"] == InScope.match_target_rule()
    end

    test "the wording is the 'structurally unreachable' one, not 'SKIPPED is excluded'", %{
      manifest: manifest
    } do
      note = manifest["match_target_rule"]["wording_note"]

      assert note =~ "structurally unreachable"
      assert note =~ "coverage gap" or note =~ "COVERAGE GAP"
    end

    test "A5 is named as the owner of the member set, here and in the arithmetic", %{
      manifest: manifest
    } do
      assert manifest["match_target_rule"]["member_set_owner"] == "MES-70 (A5)"
      assert manifest["arithmetic"]["owner"] == "MES-70 (A5)"
    end

    test "A1 fixes the total and leaves both denominator terms to A5", %{manifest: manifest} do
      assert manifest["arithmetic"]["total"] == 175
      assert manifest["arithmetic"]["in_denominator"] == nil
      assert manifest["arithmetic"]["out_of_denominator"] == nil
    end

    test "every row carries the status and errorMessage A5 needs to apply the rule", %{rows: rows} do
      assert Enum.all?(rows, &Map.has_key?(&1, "status"))
      assert Enum.all?(rows, &Map.has_key?(&1, "errorMessage"))
      assert Enum.all?(rows, &(&1["status"] in ~w(SUCCESS FAILURE SKIPPED WARNING INFO)))
    end
  end

  describe "T4 — the discriminator, and the residual it makes queryable" do
    test "every row's discriminator_source is one of the three declared rules", %{
      manifest: manifest,
      rows: rows
    } do
      declared = Enum.map(manifest["check_key"]["discriminator_rules"], & &1["rule"])

      assert Enum.sort(declared) == ~w(field_issue ordinal unique)
      assert Enum.all?(rows, &(&1["discriminator_source"] in declared))
    end

    test "rows claiming `unique` really are alone on the identifier tuple", %{rows: rows} do
      counts = Enum.frequencies_by(rows, &identity/1)

      for row <- rows, row["discriminator_source"] == "unique" do
        assert counts[identity(row)] == 1,
               "#{inspect(identity(row))} claims `unique` but appears " <>
                 "#{counts[identity(row)]} times"
      end
    end

    test "rows keyed by `field_issue` are tied, and their slugs are pairwise distinct", %{
      rows: rows
    } do
      tied = Enum.filter(rows, &(&1["discriminator_source"] == "field_issue"))
      counts = Enum.frequencies_by(rows, &identity/1)

      for {identity, group} <- Enum.group_by(tied, &identity/1) do
        assert counts[identity] > 1, "#{inspect(identity)} claims `field_issue` but is not tied"

        slugs = Enum.map(group, & &1["discriminator"])
        assert Enum.all?(slugs, &(&1 != ""))
        assert length(Enum.uniq(slugs)) == length(slugs)
      end
    end

    test "the per-source counts are 172 / 3 / 0, and rule 3 has no members", %{manifest: manifest} do
      assert manifest["check_key"]["rows_by_discriminator_source"] == %{
               "unique" => 172,
               "field_issue" => 3,
               "ordinal" => 0
             }
    end

    test "the residual is stated, and R5 is recorded as closed by construction", %{
      manifest: manifest
    } do
      by_id = Map.new(manifest["residual"], &{&1["id"], &1})

      assert Enum.sort(Map.keys(by_id)) == ~w(R1 R2 R3 R4 R5 R6)
      assert by_id["R5"]["status"] =~ "CLOSED"
      assert by_id["R6"]["status"] =~ "MES-72"
    end
  end

  describe "T5 — the manifest and bucket-0 agree, on keys AND on status" do
    @describetag :consistency

    # WHAT THIS IS, so its name does not imply more than it delivers.
    #
    # `bucket-0-2026-07-28.json` is GENERATED FROM this manifest — `mix
    # conformance.bucket_zero --manifest docs/conformance/in-scope-2026-07-28.json`
    # — so this is a CONSISTENCY join between two artefacts, one of which is
    # downstream of the other. It is NOT provenance and it is not tier 1: a
    # fabrication that regenerated both would agree, and neither file traces to
    # a run tree here.
    #
    # What it does buy, and why it is worth a test rather than a paragraph: the
    # key's six fields CONTAIN id, name and description, so bucket-0 pins the
    # identity and the status of all 175 rows including the 152 SUCCESS ones.
    # Those are exactly the rows tier 1 cannot reach, because a passing check
    # appears in no `failed_checks` list. Every defect this artefact has
    # actually suffered has been a single-file edit, and a single-file edit is
    # what this catches.
    #
    # `bucket_zero_test.exs` already holds the key SETS equal from A5's side.
    # This is stated from A1's side and adds per-row STATUS, which nothing held
    # before MES-75 — and status is the field A5's rule and C1's verdict pair
    # both read.
    test "the key sets are equal in both directions", %{
      rows: rows,
      bucket_zero: bucket_zero
    } do
      manifest_keys = MapSet.new(rows, & &1["key"])
      bucket_keys = MapSet.new(bucket_zero["checks"], & &1["key"])

      assert MapSet.difference(manifest_keys, bucket_keys) |> MapSet.to_list() == [],
             "keys in the manifest that bucket-0 does not address"

      assert MapSet.difference(bucket_keys, manifest_keys) |> MapSet.to_list() == [],
             "keys bucket-0 addresses that the manifest does not carry"
    end

    # Driven from BUCKET-0 and demanding a manifest row for each of its keys,
    # for the same reason T1's two are driven from the censuses: iterated over
    # the manifest instead, this is vacuously green on an empty one. Measured,
    # not assumed — written the other way round it was silent under the sweep's
    # EMPTY mutation while the key-set test above caught it.
    test "every row bucket-0 addresses is present, and agrees on status", %{
      rows: rows,
      bucket_zero: bucket_zero
    } do
      by_key = Map.new(rows, &{&1["key"], &1["status"]})

      disagreeing =
        for check <- bucket_zero["checks"],
            by_key[check["key"]] != check["status"],
            do: {check["key"], by_key[check["key"]], check["status"]}

      assert disagreeing == [],
             "#{length(disagreeing)} of bucket-0's #{length(bucket_zero["checks"])} rows are " <>
               "absent from the manifest or disagree on status " <>
               "{key, manifest, bucket-0}: #{inspect(disagreeing)}"
    end
  end

  describe "C1 — the key discriminates, and the rejected candidates do not" do
    test "keying on id alone loses 29 client rows and 2 server rows", %{rows: rows} do
      assert losses(rows, &{&1["leg"], &1["scenario"], &1["id"]}) == %{
               "client" => 29,
               "server" => 2
             }
    end

    test "keying on id+name+description still loses the server tie-group", %{rows: rows} do
      assert losses(rows, &identity/1) == %{"client" => 0, "server" => 2}
    end

    test "keying on the full key loses nothing — which is the point", %{rows: rows} do
      assert losses(rows, & &1["key"]) == %{"client" => 0, "server" => 0}
    end
  end

  describe "C2 — the comparison can go RED" do
    test "renaming one fieldIssue slug removes exactly one key and adds exactly one", %{
      rows: rows
    } do
      before = MapSet.new(rows, & &1["key"])

      mutated =
        rows
        |> Enum.map(fn row ->
          if row["discriminator_source"] == "field_issue" and
               row["discriminator"] == "missing-meta",
             do: put_in(row["key"], List.replace_at(row["key"], 5, "missing-meta-RENAMED")),
             else: row
        end)
        |> MapSet.new(& &1["key"])

      assert MapSet.size(MapSet.difference(before, mutated)) == 1
      assert MapSet.size(MapSet.difference(mutated, before)) == 1
    end

    test "a comparison that could not go red would pass this too", %{rows: rows} do
      # The negative half. Comparing the set to itself yields no difference, so
      # a "comparison" that only ever did that is green forever — the F2 defect.
      # This test exists to make the previous one's non-emptiness meaningful.
      keys = MapSet.new(rows, & &1["key"])
      assert MapSet.difference(keys, keys) |> MapSet.size() == 0
    end
  end

  describe "C3 — the rejected ordinal key re-points silently; this one does not" do
    test "one inserted row re-points every later row under a global-ordinal key", %{rows: rows} do
      scenario = Enum.filter(rows, &(&1["scenario"] == "server-stateless"))

      inserted = [
        %{"id" => "synthesised", "name" => "Synth", "description" => "appended by getChecks()"}
        | scenario
      ]

      before_ord = ordinal_keys(scenario)
      after_ord = ordinal_keys(inserted)

      repointed =
        for {k, v} <- after_ord, Map.has_key?(before_ord, k), before_ord[k] != v, do: k

      assert length(repointed) == length(scenario),
             "expected every one of the #{length(scenario)} pre-existing ordinal keys to " <>
               "address a different record; #{length(repointed)} did"
    end

    test "under this key the same insertion moves nothing and adds exactly one", %{rows: rows} do
      scenario = Enum.filter(rows, &(&1["scenario"] == "server-stateless"))
      before = MapSet.new(scenario, & &1["key"])

      added = [
        "server",
        "server-stateless",
        "synthesised",
        "Synth",
        "appended by getChecks()",
        ""
      ]

      after_set = MapSet.put(before, added)

      assert MapSet.subset?(before, after_set)
      assert MapSet.difference(after_set, before) |> MapSet.to_list() == [added]
    end
  end

  # --- helpers -------------------------------------------------------------

  defp rows(manifest) do
    Enum.flat_map(manifest["scenarios"], fn entry ->
      Enum.map(
        entry["checks"],
        &Map.merge(&1, %{"leg" => entry["leg"], "scenario" => entry["scenario"]})
      )
    end)
  end

  defp identity(row),
    do: {row["leg"], row["scenario"], row["id"], row["name"], row["description"]}

  # Shaped to equal the census's `checks` block exactly: all five statuses
  # present with an explicit zero, plus `total`. A distribution that omitted its
  # zeroes would compare unequal to a census that states them, and — worse —
  # would make a status vanishing from a scenario look like a key that was never
  # there rather than a count that moved.
  defp distribution(checks) do
    checks
    |> Enum.frequencies_by(& &1["status"])
    |> Enum.into(%{"SUCCESS" => 0, "FAILURE" => 0, "WARNING" => 0, "SKIPPED" => 0, "INFO" => 0})
    |> Map.put("total", length(checks))
  end

  # Rows a crosswalk keyed this way would silently absorb into another.
  defp losses(rows, keyer) do
    rows
    |> Enum.group_by(& &1["leg"])
    |> Map.new(fn {leg, list} ->
      {leg, length(list) - length(Enum.uniq(Enum.map(list, keyer)))}
    end)
  end

  # What the rejected candidate would produce: identity is a place.
  defp ordinal_keys(list) do
    list
    |> Enum.with_index(1)
    |> Map.new(fn {row, i} -> {i, {row["id"], row["name"], row["description"]}} end)
  end
end

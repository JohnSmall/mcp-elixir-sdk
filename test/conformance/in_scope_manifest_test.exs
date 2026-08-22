defmodule MCP.Conformance.InScopeManifestTest do
  @moduledoc """
  The frozen in-scope manifest is the artefact every ticket downstream of A1
  counts against. If it is wrong they are all wrong together, so these are the
  properties that must hold of the COMMITTED file — read from disk, not from a
  fixture this test also builds.

  ## What each test can actually fail on

  `T1` is the load-bearing one and the only one that survives `/tmp` being
  wiped: it compares the manifest to the committed CENSUSES, two files it does
  not write. Everything else is internal consistency, which a wrong-but-tidy
  manifest would satisfy.

  Stated plainly because a test suite's greenness is easy to over-read: **none
  of these proves the manifest was derived from the accepted RUN TREES**. Those
  are not committed, so the `checks_sha256` values are unverifiable once /tmp is
  cleared. That is residual R6, tracked as MES-72.

  ## The controls (C1-C3), and why they are here rather than in a run log

  A key that cannot be shown to discriminate is an assertion. Each control
  re-keys the manifest's OWN rows under a rejected candidate and demonstrates
  the failure mode, so the case against `details` and against global ordinal is
  a result rather than a paragraph. They need nothing outside this repository,
  so they keep discriminating long after the run trees are gone.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.InScope

  @manifest_path "docs/conformance/in-scope-2026-07-28.json"
  @censuses %{
    "server" => "docs/conformance/server-2026-07-28.json",
    "client" => "docs/conformance/client-2026-07-28.json"
  }

  setup_all do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()

    censuses =
      Map.new(@censuses, fn {leg, path} -> {leg, path |> File.read!() |> Jason.decode!()} end)

    %{manifest: manifest, censuses: censuses, rows: rows(manifest)}
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

    test "every scenario's check count equals the count the census records for it", %{
      manifest: manifest,
      censuses: censuses
    } do
      for entry <- manifest["scenarios"] do
        census = Map.fetch!(censuses, entry["leg"])
        scenario = Enum.find(census["scenarios"], &(&1["id"] == entry["scenario"]))

        assert scenario, "#{entry["leg"]}/#{entry["scenario"]} is not in the census at all"

        assert length(entry["checks"]) == scenario["checks"]["total"],
               "#{entry["leg"]}/#{entry["scenario"]}: manifest carries " <>
                 "#{length(entry["checks"])} rows, census records " <>
                 "#{scenario["checks"]["total"]}"
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

    test "the census and the manifest agree that no in-scope scenario is an auth/ one", %{
      manifest: manifest
    } do
      client = Enum.filter(manifest["scenarios"], &(&1["leg"] == "client"))

      refute Enum.any?(client, &String.starts_with?(&1["scenario"], "auth/")),
             "the auth/ namespace is out of 2.0.0 by ADR-003; deriving scope from " <>
               "classification.class instead readmits auth/resource-mismatch because it PASSES"
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

defmodule MCP.Conformance.BucketZeroTest do
  @moduledoc """
  Bucket 0's committed artefact — the out-of-denominator set every downstream
  bucket counts around.

  ## What each test can actually fail on

  `T1` and `T2` are the load-bearing pair and they are the price of decision 1.
  A5's term lives in A5's own artefact rather than in A1's manifest, which
  keeps a generated file from being hand-edited — but a split artefact is only
  safe if the two are joined by something that FAILS when they disagree. T1
  resolves every one of A5's tokens against A1's committed rows; T2 requires
  the totals and the key sets to be equal as sets. Invert either and the split
  becomes two files free to drift.

  `C1` is the one that can rule something out. Every other test here would
  still pass if the classifier simply read `status == "SKIPPED"` — the in-scope
  run happens to have exactly two SKIPPED rows and they happen to be the two
  members, so agreement with the truth is not evidence of a correct rule. C1
  re-runs the classifier over the null-exit0 control's ELEVEN SKIPPED rows and
  requires 2, where a SKIPPED-reader returns 11. That is the criterion's
  falsifiability, measured rather than claimed.

  ## What none of this establishes

  **Matchability, and nothing further.** Whether any ET-CC member actually
  claims one of the 173 is D2b's question. No assertion here says "matched",
  and T3 exists partly to keep the artefact's own wording honest about it.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.{BucketZero, MatchKey}

  @artefact_path "docs/conformance/bucket-0-2026-07-28.json"
  @manifest_path "docs/conformance/in-scope-2026-07-28.json"

  @rule "A check is a match target only if a conforming 2026-07-28 implementation can cause it to evaluate."

  setup_all do
    artefact = @artefact_path |> File.read!() |> Jason.decode!()
    manifest = @manifest_path |> File.read!() |> Jason.decode!()

    %{
      artefact: artefact,
      manifest: manifest,
      rows: artefact["checks"],
      a1_rows: MatchKey.rows_from_manifest(manifest)
    }
  end

  describe "T1 — every classified row addresses a row of A1's committed manifest" do
    test "every token resolves, and resolves uniquely", %{rows: rows, a1_rows: a1_rows} do
      unresolved =
        Enum.reject(rows, fn row ->
          MatchKey.resolve(row["token"], a1_rows) == {:ok, row["key"]}
        end)

      assert unresolved == [],
             "tokens that do not resolve to their own key: " <>
               inspect(Enum.map(unresolved, & &1["token"]))
    end

    test "the token is derived from the key, not stored beside it", %{rows: rows} do
      assert Enum.all?(rows, &(MatchKey.encode!(&1["key"]) == &1["token"]))
    end
  end

  describe "T2 — the cross-file join that earns the split from A1" do
    test "A5 and A1 agree on the total", %{artefact: artefact, manifest: manifest} do
      assert artefact["arithmetic"]["total"] == manifest["arithmetic"]["total"]
      assert artefact["arithmetic"]["total"] == length(artefact["checks"])
    end

    test "A5 and A1 agree on the key set exactly", %{rows: rows, a1_rows: a1_rows} do
      assert MapSet.new(rows, & &1["key"]) == MapSet.new(a1_rows)
    end

    test "the arithmetic reconciles, and it is 173 + 2", %{artefact: artefact} do
      a = artefact["arithmetic"]
      assert a["in_denominator"] + a["out_of_denominator"] == a["total"]
      assert {a["in_denominator"], a["out_of_denominator"], a["total"]} == {173, 2, 175}
    end

    test "A1's manifest is left byte-untouched: both denominator terms still nil", %{
      manifest: manifest
    } do
      assert manifest["arithmetic"]["in_denominator"] == nil
      assert manifest["arithmetic"]["out_of_denominator"] == nil
      assert manifest["arithmetic"]["owner"] == "MES-70 (A5)"
    end

    test "the two artefacts address the same harness build", %{
      artefact: artefact,
      manifest: manifest
    } do
      assert artefact["harness"]["sha256"] ==
               manifest["provenance"]["client"]["harness_dist_sha256"]

      assert artefact["harness"]["sha256"] ==
               manifest["provenance"]["server"]["harness_dist_sha256"]
    end
  end

  describe "T3 — the ratified sentence, carried and never paraphrased" do
    test "the rule is byte-equal to A1's and to the module's", %{
      artefact: artefact,
      manifest: manifest
    } do
      assert artefact["match_target_rule"]["text"] == @rule
      assert artefact["match_target_rule"]["text"] == manifest["match_target_rule"]["text"]
      assert BucketZero.rule() == @rule
    end

    test "the paraphrase appears only where it is being FORBIDDEN", %{artefact: artefact} do
      # A blanket "the phrase appears nowhere" would be the wrong test: it would
      # forbid the artefact from naming the paraphrase in order to rule it out,
      # which is exactly what the ratified wording note does. What must not
      # happen is the paraphrase being carried AS the rule.
      carried =
        artefact
        |> strings()
        |> Enum.filter(&String.contains?(&1, "SKIPPED is excluded"))
        |> Enum.reject(&(&1 =~ ~r/(NOT as|is not|Never rendered as)/))

      assert carried == [], "paraphrase carried without negation: #{inspect(carried)}"
      assert artefact["match_target_rule"]["text"] == @rule
    end

    test "the artefact says MATCHABLE and never claims MATCHED", %{artefact: artefact} do
      assert artefact["arithmetic"]["word"] == "MATCHABLE, never MATCHED"

      assert artefact["match_target_rule"]["establishes"] =~ "MATCHABILITY only"
    end
  end

  describe "C1 — the falsification control: the classifier is not reading SKIPPED" do
    setup %{artefact: artefact} do
      %{control: artefact["control"]}
    end

    test "the control is the same population as A1's eleven", %{
      control: control,
      manifest: manifest
    } do
      a1 =
        manifest["scenarios"]
        |> Enum.find(&(&1["scenario"] == "http-standard-headers"))
        |> Map.fetch!("checks")
        |> Enum.map(& &1["key"])

      assert MapSet.new(control["keys"]) == MapSet.new(a1)
      assert control["rows"] == 11
      assert control["statuses"] == %{"SKIPPED" => 11}
    end

    test "re-running the classifier over the control returns 2, not 11", %{control: control} do
      artefact = BucketZero.classify(as_manifest(control["keys"]), %{})

      assert artefact["arithmetic"]["out_of_denominator"] == 2
      assert artefact["arithmetic"]["in_denominator"] == 9

      naive = Enum.count(artefact["checks"], &(&1["status"] == "SKIPPED"))
      assert naive == 11, "the control must actually present eleven SKIPPED rows to discriminate"
    end

    test "the nine are classified as coverage gaps, by name", %{control: control} do
      artefact = BucketZero.classify(as_manifest(control["keys"]), %{})

      gaps =
        artefact["checks"]
        |> Enum.filter(&(&1["reason_code"] == "skip_reachable_optional_available"))
        |> Enum.map(& &1["name"])
        |> Enum.sort()

      assert length(gaps) == 9
      refute "ClientMcpMethodHeader_initialize" in gaps
      refute "ClientMcpMethodHeader_notifications_initialized" in gaps
    end
  end

  describe "T4 — the subset hypothesis, both directions with the zeros" do
    test "direction 1: no non-SKIPPED check is unmatchable", %{artefact: artefact} do
      d1 = artefact["subset_hypothesis"]["direction_1"]
      assert d1["count"] == 0
      assert d1["members"] == []
    end

    test "direction 2: no SKIPPED check is matchable ON THIS POPULATION", %{artefact: artefact} do
      d2 = artefact["subset_hypothesis"]["direction_2"]
      assert d2["count"] == 0
      assert d2["holds"]
      assert d2["result"] =~ "CONTINGENT"
    end

    test "the R3/R6 FAILUREs are named as tested candidates and are matchable", %{
      artefact: artefact,
      rows: rows
    } do
      r3_r6 = artefact["subset_hypothesis"]["direction_1"]["candidates_tested"]["r3_r6"]
      assert length(r3_r6) == 2

      named =
        Enum.filter(rows, &(&1["token"] in r3_r6))

      assert Enum.all?(named, & &1["matchable"])
      assert Enum.all?(named, &(&1["status"] == "FAILURE"))
    end

    test "the subscriptions/listen branch is recorded as having no row of its own", %{
      artefact: artefact
    } do
      not_a_member =
        artefact["subset_hypothesis"]["direction_1"]["candidates_tested"]["not_a_member"]

      assert not_a_member["what"] =~ "1153:22300"
      assert not_a_member["ruling"] =~ "NO ROW OF ITS OWN"
    end
  end

  describe "T5 — the skip vocabulary is complete by enumeration, not by sampling" do
    test "every token occurrence is classified, and the total is stated", %{artefact: artefact} do
      v = artefact["vocabulary"]
      assert length(v["token_sites"]) == v["token_site_totals"]["total"]
      assert v["token_site_totals"]["total"] == 29

      assert v["token_site_totals"]["emits_check"] + v["token_site_totals"]["emits_scenario"] +
               v["token_site_totals"]["compares"] + v["token_site_totals"]["message_only"] == 29
    end

    test "every flag producer and consumer is classified", %{artefact: artefact} do
      v = artefact["vocabulary"]
      assert length(v["flag_writes"]) == 9
      assert length(v["flag_reads"]) == 5
      assert length(v["flag_read_false_positives"]["addresses"]) == 2
    end

    test "every site carries the bytes at its address, not just the address", %{
      artefact: artefact
    } do
      sites =
        artefact["vocabulary"]["token_sites"] ++
          artefact["vocabulary"]["flag_writes"] ++ artefact["vocabulary"]["flag_reads"]

      assert Enum.all?(sites, &is_binary(&1["quote"]))
      assert Enum.all?(sites, &(&1["quote"] != ""))
    end

    test "the homonym is recorded as a homonym", %{artefact: artefact} do
      homonym =
        Enum.find(artefact["vocabulary"]["flag_writes"], &(&1["at"] == "1538:18221"))

      assert homonym["level"] == "homonym"
      assert homonym["site"] =~ "never read as a check verdict"
    end

    test "the scenario-level gate is answered as a result, not by silence", %{artefact: artefact} do
      gate = artefact["scenario_gate"]
      assert gate["result"] =~ "NONE of A1's 44"
      assert gate["contrast"] =~ "removedIn"
      assert gate["sites"] == ["2203:1021", "2210:828"]
    end
  end

  describe "T6 — the two members carry per-member evidence" do
    test "there are exactly two, and both are named", %{artefact: artefact} do
      names = Enum.map(artefact["members"], & &1["name"]) |> Enum.sort()

      assert names == [
               "ClientMcpMethodHeader_initialize",
               "ClientMcpMethodHeader_notifications_initialized"
             ]
    end

    test "each cites a harness source address and says what would make it evaluate", %{
      artefact: artefact
    } do
      for member <- artefact["members"] do
        assert member["harness_source"] =~ ~r/^\d+:\d+$/
        assert member["what_would_make_it_evaluate"] =~ "NON-conformant"
        assert member["what_would_make_it_leave_the_bucket"] =~ "nothing we can write"
        assert length(member["sources"]) >= 2
      end
    end

    test "member 2 states the limit of the cross-leg corroboration", %{artefact: artefact} do
      member =
        Enum.find(
          artefact["members"],
          &(&1["name"] == "ClientMcpMethodHeader_notifications_initialized")
        )

      assert member["corroboration_limit"] =~ "does NOT reach this member"
    end

    test "the withdrawn schema grep is cited nowhere", %{artefact: artefact} do
      json = Jason.encode!(artefact)
      refute String.contains?(json, "spec.types.js")
      refute String.contains?(json, "DRAFT-2026-v1")
    end
  end

  describe "T7 — every row carries a reason, and the reasons are a closed set" do
    test "no row is classified without one", %{rows: rows} do
      assert Enum.all?(rows, &(is_binary(&1["reason"]) and &1["reason"] != ""))
      assert Enum.all?(rows, &is_binary(&1["reason_code"]))
    end

    test "the reason codes are exactly the four the rule admits", %{rows: rows} do
      codes = rows |> Enum.map(& &1["reason_code"]) |> Enum.uniq() |> Enum.sort()

      assert codes == ["no_skip_site", "removed_by_spec", "skip_reachable_evaluated"]
    end

    test "matchable is false for exactly the bucket-0 rows", %{rows: rows} do
      assert Enum.count(rows, &(&1["matchable"] == false)) == 2
      assert Enum.all?(rows, &(&1["matchable"] == (&1["bucket"] != 0)))
    end

    test "every skip-reachable row names its site and its gate", %{rows: rows} do
      reachable = Enum.filter(rows, & &1["skip_site"])
      assert length(reachable) == 22
      assert Enum.all?(reachable, &(&1["skip_gate"] not in [nil, ""]))
      assert Enum.all?(reachable, &(&1["skip_site"] =~ ~r/^\d+:\d+$/))
    end
  end

  # Every string anywhere in the artefact, so a phrase test can look at the
  # sentence carrying it rather than at one flattened blob of JSON.
  defp strings(value) when is_map(value), do: value |> Map.values() |> Enum.flat_map(&strings/1)
  defp strings(value) when is_list(value), do: Enum.flat_map(value, &strings/1)
  defp strings(value) when is_binary(value), do: [value]
  defp strings(_value), do: []

  # The control's key set, shaped as a manifest so the REAL classifier runs over
  # it. Building a fixture of expected verdicts instead would test nothing.
  defp as_manifest(keys) do
    checks =
      Enum.map(keys, fn key ->
        %{"key" => key, "name" => Enum.at(key, 3), "status" => "SKIPPED", "errorMessage" => nil}
      end)

    %{
      "scenarios" => [
        %{"leg" => "client", "scenario" => "http-standard-headers", "checks" => checks}
      ],
      "arithmetic" => %{"total" => length(keys)},
      "match_target_rule" => %{"wording_note" => "control"}
    }
  end
end

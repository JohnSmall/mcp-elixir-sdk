defmodule MCP.Conformance.CrosswalkTest do
  @moduledoc """
  Units for the crosswalk's decision logic (MES-97, C1a), plus the committed
  artefact's internal consistency.

  The parts that need a **mutated tree** — every generator refusal, the empty
  crosswalk, the keying control on the real 173 — live in
  `conformance/controls/crosswalk_controls.exs`, because a file under `test/`
  that rewrites authored artefacts and re-runs whole builds would move the unit
  population MES-88's boundary sweep measures. What is here is what gate 5 can
  hold: the functions that decide, and the artefact's own arithmetic.

  ## The WARNING mapping is tested here BECAUSE it has no live instance

  `oc_verdict("WARNING")` fires on zero rows of C1a's population — both
  in-denominator WARNING checks are outside it. A rule with no live instance
  reads as exercised when it is not, so it is exercised here instead, and the
  artefact says in `verdict_mapping.warning_is_untested_by_live_data_here` that
  this is where its coverage comes from.
  """
  use ExUnit.Case, async: true

  alias MCP.Conformance.{Crosswalk, MatchKey}

  @key [
    "client",
    "request-metadata",
    "sep-2575-client-populates-meta",
    "ClientPopulatesMeta",
    "d",
    ""
  ]

  defp edge(axes, oc, et) do
    {:ok, e} =
      MatchKey.new_edge(%{
        member: %{module: "M", test: "t"},
        claim: "c",
        oc_key: @key,
        verdicts: %{oc: oc, et: et},
        axes: axes
      })

    e
  end

  defp ax(name, verdict), do: %{axis: name, verdict: verdict}

  describe "oc_verdict/1 — the run status a bucket is computed from" do
    test "SUCCESS is green and FAILURE is red, carrying nothing" do
      assert {:ok, :green, []} = Crosswalk.oc_verdict("SUCCESS")
      assert {:ok, :red, []} = Crosswalk.oc_verdict("FAILURE")
    end

    test "WARNING is green AND carries `warning: true` — visible, never laundered (D2)" do
      assert {:ok, :green, attrs} = Crosswalk.oc_verdict("WARNING")
      assert Keyword.get(attrs, :warning) == true
    end

    test "an unmappable status is REFUSED, not defaulted" do
      # SKIPPED reaching this function would mean a bucket-0 check leaked into
      # the join; a default of :red or :green would bury that.
      assert {:error, {:unmappable_status, "SKIPPED"}} = Crosswalk.oc_verdict("SKIPPED")
      assert {:error, {:unmappable_status, "INFO"}} = Crosswalk.oc_verdict("INFO")
      assert {:error, {:unmappable_status, nil}} = Crosswalk.oc_verdict(nil)
    end
  end

  describe "assign/1 — A3 §3's table, plus the escalation A3's table has no row for" do
    test "the six bucketing rows of the ratified table" do
      assert {"4a", [], nil} = Crosswalk.assign(edge([ax("a", :contradicts)], :red, :green))

      assert {"4b", [], nil} =
               Crosswalk.assign(edge([ax("a", :agrees), ax("b", :silent)], :red, :green))

      assert {"5", [], nil} = Crosswalk.assign(edge([ax("a", :agrees)], :green, :green))
      assert {"5", ["partial"], nil} = partial_5()
      assert {"3", [], nil} = Crosswalk.assign(edge([ax("a", :agrees)], :green, :red))
      assert {"6", [], nil} = Crosswalk.assign(edge([ax("a", :agrees)], :red, :red))
    end

    defp partial_5 do
      {b, attrs, e} = Crosswalk.assign(edge([ax("a", :agrees), ax("b", :silent)], :green, :green))
      {b, Enum.map(attrs, &Atom.to_string/1), e}
    end

    test "A3's two escalations return no bucket" do
      assert {nil, [], msg1} = Crosswalk.assign(edge([ax("a", :agrees)], :red, :green))
      assert msg1 =~ "divergent_despite_agreement"

      assert {nil, [], msg2} = Crosswalk.assign(edge([ax("a", :contradicts)], :green, :green))
      assert msg2 =~ "inconsistent_verdict_pair"
    end

    test "contradicts beats silent — 4a, never 4b, when an edge is both" do
      # The `:83` initialize case: contradicts on the code axis AND silent on
      # the status axis. A rule reading 'has an uncovered axis ⇒ 4b' would put
      # the epic's own worked 4a example in 4b.
      assert {"4a", [], nil} =
               Crosswalk.assign(
                 edge(
                   [ax("jsonrpc_error_code", :contradicts), ax("http_status", :silent)],
                   :red,
                   :green
                 )
               )
    end

    test "an ALL-SILENT edge escalates, where MatchKey alone would file it as bucket 5" do
      e = edge([ax("a", :silent), ax("b", :silent)], :green, :green)

      # What the ratified function alone does with it:
      assert {:ok, "5", [:partial]} = MatchKey.bucket(e)

      # What this module does instead, and why:
      assert {nil, [], msg} = Crosswalk.assign(e)
      assert msg =~ "no_axis_contact"
      assert msg =~ "covering zero"
    end

    test "one covered axis among silent ones is a PARTIAL, not a no-contact" do
      # The boundary of the rule above. Without this the escalation could be
      # swallowing every partial edge and the test above would not notice.
      assert {"5", [:partial], nil} =
               Crosswalk.assign(
                 edge([ax("a", :agrees), ax("b", :silent), ax("c", :silent)], :green, :green)
               )
    end
  end

  describe "axis_index/1 — one fact, one home (D4)" do
    test "merges disjoint decompositions" do
      a = %{
        "checks" => [%{"key" => ["s", "x", "c1", "N1", "d", ""], "axes" => [%{"axis" => "a1"}]}]
      }

      b = %{
        "checks" => [%{"key" => ["s", "x", "c2", "N2", "d", ""], "axes" => [%{"axis" => "a2"}]}]
      }

      assert {:ok, index} = Crosswalk.axis_index([a, b])
      assert map_size(index) == 2
      assert index[["s", "x", "c1", "N1", "d", ""]] == ["a1"]
    end

    test "REFUSES two artefacts decomposing the same check" do
      row = %{"key" => ["s", "x", "c1", "N1", "d", ""], "axes" => [%{"axis" => "a1"}]}
      a = %{"checks" => [row]}
      b = %{"checks" => [Map.put(row, "axes", [%{"axis" => "different"}])]}

      assert {:error, {:axis_artefacts_overlap, [["s", "x", "c1", "N1", "d", ""]]}} =
               Crosswalk.axis_index([a, b])
    end

    test "the refusal is on the KEY, so a same-key row with identical axes is still refused" do
      # Two owners agreeing today is still two owners; the defect is that when
      # they diverge nothing detects it.
      row = %{"key" => ["s", "x", "c1", "N1", "d", ""], "axes" => [%{"axis" => "a1"}]}

      assert {:error, {:axis_artefacts_overlap, _}} =
               Crosswalk.axis_index([%{"checks" => [row]}, %{"checks" => [row]}])
    end
  end

  describe "project/2 — a complement needs a universe" do
    test "bucket 1 is the declared members with no edge" do
      arg = %{population: ["m1", "m2", "m3"], with_edges: ["m1"]}
      assert {:ok, ["m2", "m3"]} = Crosswalk.project(:bucket_1, arg)
    end

    test "bucket 2 is the declared checks with no edge" do
      arg = %{population: ["c1", "c2"], with_edges: ["c1", "c2"]}
      assert {:ok, []} = Crosswalk.project(:bucket_2, arg)
    end

    test "REFUSES with no declared population" do
      assert {:error, :no_declared_population} =
               Crosswalk.project(:bucket_1, %{population: nil, with_edges: []})

      assert {:error, :no_declared_population} =
               Crosswalk.project(:bucket_2, %{population: nil, with_edges: []})
    end

    test "REFUSES with an EMPTY declared population — the vacuum (S9-15)" do
      assert {:error, :empty_population} =
               Crosswalk.project(:bucket_1, %{population: [], with_edges: []})

      assert {:error, :empty_population} =
               Crosswalk.project(:bucket_2, %{population: [], with_edges: []})
    end
  end

  describe "set_compare/2 — totality by set, not by arithmetic" do
    test "equal sets" do
      assert %{equal: true, missing: [], extra: []} =
               Crosswalk.set_compare(["a", "b"], ["b", "a"])
    end

    test "equal COUNTS over unequal sets is caught, and the two directions are separate" do
      assert %{equal: false, missing: ["b"], extra: ["c"]} =
               Crosswalk.set_compare(["a", "b"], ["a", "c"])
    end

    test "missing and extra are reported independently" do
      assert %{missing: ["b"], extra: []} = Crosswalk.set_compare(["a", "b"], ["a"])
      assert %{missing: [], extra: ["z"]} = Crosswalk.set_compare(["a"], ["a", "z"])
    end
  end

  describe "keying_control/1 — both directions, in A1's unit" do
    test "the obvious fields merge rows and the six-field key does not" do
      rows = [
        ["client", "s", "shared-id", "NameA", "desc one", ""],
        ["client", "s", "shared-id", "NameB", "desc two", ""],
        ["client", "s", "other-id", "NameA", "desc three", ""]
      ]

      k = Crosswalk.keying_control(rows)

      assert k["rows"] == 3
      assert k["by_check_id_alone"] == 1
      assert k["by_name_alone"] == 1
      assert k["by_a1s_six_field_key"] == 0
    end

    test "the measure is ROWS LOST — three rows collapsing to one is two lost, not one group" do
      rows = for n <- 1..3, do: ["client", "s", "same", "Name#{n}", "d#{n}", ""]
      assert Crosswalk.keying_control(rows)["by_check_id_alone"] == 2
    end
  end

  describe "check_population/2 — A3 §6's state-4 guard" do
    test "passes when every member carries a token" do
      assert :ok = Crosswalk.check_population(["m1", "m2"], ["m1", "m2", "m3"])
    end

    test "FAILS, naming the untagged members" do
      assert {:error, {:state_4_members, ["m2"]}} =
               Crosswalk.check_population(["m1", "m2"], ["m1"])
    end

    test "an empty population passes the guard — which is why it is not the only guard" do
      # Stated rather than left implicit: the state-4 guard cannot catch the
      # vacuum on its own, because a population with no members has no untagged
      # member either. The generator's own emptiness refusal is what catches it,
      # and the control drives that.
      assert :ok = Crosswalk.check_population([], [])
    end
  end

  # The committed artefact, held to what it asserts about itself. No harness
  # needed: every cell carries its key, its axes and its shape.
  describe "duplicate_edge_keys/1 — G14, the join's own key" do
    defp e(member, claim, tag),
      do: %{"member" => %{"register_key" => member}, "claim" => claim, "tag" => tag}

    test "a verbatim repeat is named, not counted" do
      edges = [e("m", "c", "t"), e("m2", "c2", "t2"), e("m", "c", "t")]
      assert Crosswalk.duplicate_edge_keys(edges) == [{"m", "c", "t"}]
    end

    test "all three fields are part of the key — differing in any one is not a duplicate" do
      for edge <- [e("m!", "c", "t"), e("m", "c!", "t"), e("m", "c", "t!")] do
        assert Crosswalk.duplicate_edge_keys([e("m", "c", "t"), edge]) == []
      end
    end

    test "a member legitimately bundling several claims is not a duplicate" do
      # A3 §1: a member bundling claims contributes several edges and they are
      # never collapsed. The guard must not fire on the thing the rule requires.
      assert Crosswalk.duplicate_edge_keys([e("m", "c1", "t"), e("m", "c2", "t")]) == []
    end

    test "it is empty on no edges, which is the only thing emptiness may mean here" do
      assert Crosswalk.duplicate_edge_keys([]) == []
    end
  end

  describe "select/2 — G15's external anchor, and it is fail-closed" do
    @selector %{
      "rows_at" => "rows",
      "key_field" => "key",
      "any_of" => [
        %{"field" => "tokens", "test" => "non_empty_list"},
        %{"field" => "contradicts_oc", "test" => "not_null"}
      ]
    }

    @source %{
      "rows" => [
        %{"key" => "a", "tokens" => ["oc:x"], "contradicts_oc" => nil},
        %{"key" => "b", "tokens" => [], "contradicts_oc" => %{"check" => "y"}},
        %{"key" => "c", "tokens" => [], "contradicts_oc" => nil},
        %{"key" => "d", "contradicts_oc" => nil}
      ]
    }

    test "any_of is a union, and the unselected rows are left out" do
      assert Crosswalk.select(@selector, @source) == {:ok, ["a", "b"]}
    end

    test "the result is sorted, so a source reordering is not a population change" do
      shuffled = %{"rows" => Enum.reverse(@source["rows"])}
      assert Crosswalk.select(@selector, shuffled) == {:ok, ["a", "b"]}
    end

    test "an unknown test REFUSES — a selector language that guesses is a selector that lies" do
      s = put_in(@selector, ["any_of"], [%{"field" => "tokens", "test" => "looks_right"}])
      assert {:error, {:unknown_selector_test, _}} = Crosswalk.select(s, @source)
    end

    test "an unknown test refuses even when another clause would have selected the row" do
      # Fail-closed means the bad clause decides, not the good one.
      s =
        put_in(@selector, ["any_of"], [
          %{"field" => "tokens", "test" => "non_empty_list"},
          %{"field" => "contradicts_oc", "test" => "vibes"}
        ])

      assert {:error, {:unknown_selector_test, _}} = Crosswalk.select(s, @source)
    end

    test "a rows path the source does not carry REFUSES rather than selecting nothing" do
      assert {:error, {:selector_names_no_such_rows, "nope"}} =
               Crosswalk.select(Map.put(@selector, "rows_at", "nope"), @source)
    end

    test "a key field a selected row does not carry REFUSES" do
      assert {:error, {:selector_key_field_is_not_a_string, "id"}} =
               Crosswalk.select(Map.put(@selector, "key_field", "id"), @source)
    end

    test "duplicate keys in the ANCHOR refuse — a silent merge hides the drop" do
      dupes = %{"rows" => @source["rows"] ++ [%{"key" => "a", "tokens" => ["oc:x"]}]}

      assert {:error, {:selector_source_has_duplicate_keys, ["a"]}} =
               Crosswalk.select(@selector, dupes)
    end

    test "a malformed selector refuses — including an empty any_of, which selects nothing" do
      for bad <- [%{}, %{"rows_at" => "rows"}, Map.put(@selector, "any_of", []), nil] do
        assert {:error, {:malformed_selector, ^bad}} = Crosswalk.select(bad, @source)
      end
    end
  end

  describe "declaration_mismatches/2 — G15b, the file's own numbers" do
    @declared %{
      "members" => 21,
      "members_with_edges" => 16,
      "members_declared_unmatched" => 5,
      "checks_addressed" => 14
    }

    test "agreement is the empty list" do
      assert Crosswalk.declaration_mismatches(@declared, @declared) == []
    end

    test "each of the four fields is checked, and named when it disagrees" do
      for field <- ~w(members members_with_edges members_declared_unmatched checks_addressed) do
        derived = Map.update!(@declared, field, &(&1 + 1))

        assert [%{"field" => ^field, "declared" => d, "derived" => a}] =
                 Crosswalk.declaration_mismatches(@declared, derived)

        assert a == d + 1
      end
    end

    test "an ABSENT declared field is a mismatch, not a pass" do
      # The weakness this replaces: C1a read the block for its `rule` string and
      # checked none of its numbers. A missing number must not read as agreement.
      assert [%{"field" => "members", "declared" => nil}] =
               Crosswalk.declaration_mismatches(Map.delete(@declared, "members"), @declared)
    end
  end

  describe "status_agreement/2 — G16, two sources compared by SET then per key" do
    @left %{["a"] => "SUCCESS", ["b"] => "FAILURE"}

    test "identical maps agree" do
      a = Crosswalk.status_agreement(@left, @left)
      assert a["agrees"]
      assert a["compared"] == 2
      assert a["disagreements"] == []
      assert a["key_sets"]["equal"]
    end

    test "a drifted status is named with BOTH values, so neither source is privileged" do
      a = Crosswalk.status_agreement(@left, %{@left | ["b"] => "SUCCESS"})

      refute a["agrees"]
      assert [%{"key" => ["b"], "left" => "FAILURE", "right" => "SUCCESS"}] = a["disagreements"]
    end

    test "different key sets fail even when both sides have the same COUNT" do
      a = Crosswalk.status_agreement(@left, %{["a"] => "SUCCESS", ["z"] => "FAILURE"})

      refute a["agrees"]
      refute a["key_sets"]["equal"]
      assert a["key_sets"]["missing"] == [["b"]]
      assert a["key_sets"]["extra"] == [["z"]]
      # and the shared key still agrees — the two limbs are independent
      assert a["disagreements"] == []
    end

    test "it names itself a CONSISTENCY pin (ruling 9)" do
      a = Crosswalk.status_agreement(@left, @left)
      assert a["what_this_is"] =~ "CONSISTENCY pin, not a correctness one"
      assert a["what_this_is"] =~ "same accepted harness run"
    end
  end

  describe "the committed crosswalk artefact" do
    setup do
      %{a: "docs/conformance/crosswalk-2026-07-28.json" |> File.read!() |> Jason.decode!()}
    end

    test "every cell re-validates through MatchKey — shape and tag re-derived, not trusted", %{
      a: a
    } do
      for cell <- a["cells"] do
        rebuilt = %{
          member: %{module: cell["member"]["module"], test: cell["member"]["test"]},
          claim: cell["claim"],
          oc_key: cell["oc_key"],
          tag: cell["tag"],
          verdicts: %{
            oc: String.to_existing_atom(cell["verdicts"]["oc"]),
            et: String.to_existing_atom(cell["verdicts"]["et"])
          },
          axes:
            Enum.map(
              cell["axes"],
              &%{axis: &1["axis"], verdict: String.to_existing_atom(&1["verdict"])}
            ),
          shape: String.to_existing_atom(cell["shape"])
        }

        assert :ok = MatchKey.validate_edge(rebuilt), cell["claim"]
      end
    end

    test "every cell's bucket is the one assign/1 gives its own verdict pair and shape", %{a: a} do
      for cell <- a["cells"] do
        e = %{
          axes:
            Enum.map(
              cell["axes"],
              &%{axis: &1["axis"], verdict: String.to_existing_atom(&1["verdict"])}
            ),
          verdicts: %{
            oc: String.to_existing_atom(cell["verdicts"]["oc"]),
            et: String.to_existing_atom(cell["verdicts"]["et"])
          },
          shape: String.to_existing_atom(cell["shape"])
        }

        {bucket, attrs, escalation} = Crosswalk.assign(e)
        assert bucket == cell["bucket"], cell["claim"]
        assert Enum.map(attrs, &Atom.to_string/1) == cell["bucket_attributes"]
        assert is_nil(escalation) == is_nil(cell["escalation"])
      end
    end

    test "a cell is bucketed XOR escalated — never both, never neither", %{a: a} do
      for cell <- a["cells"] do
        assert is_nil(cell["bucket"]) != is_nil(cell["escalation"]), cell["claim"]
      end
    end

    test "the arithmetic reconciles", %{a: a} do
      ar = a["arithmetic"]
      assert ar["edges"] == length(a["cells"])
      assert ar["edges"] == ar["bucketed"] + ar["escalated"]
      assert ar["members"] == ar["members_with_edges"] + ar["members_declared_unmatched"]
    end

    test "totality holds by SET, in both directions", %{a: a} do
      t = a["totality"]
      assert t["every_declared_member_appears"]["equal"]
      assert t["every_declared_member_appears"]["missing"] == []
      assert t["every_declared_member_appears"]["extra"] == []
      assert t["every_declared_check_appears"]["equal"]
      assert t["every_declared_check_appears"]["missing"] == []
      assert t["every_declared_check_appears"]["extra"] == []
    end

    test "bucket 1 is exactly the declared-unmatched members, by set", %{a: a} do
      declared = Enum.map(a["declared_unmatched"], & &1["member"]["register_key"])
      assert %{equal: true} = Crosswalk.set_compare(declared, a["buckets"]["bucket_1"]["members"])
    end

    test "bucket 2 is empty and says which universe it is empty over", %{a: a} do
      b2 = a["buckets"]["bucket_2"]
      assert b2["count"] == 0
      assert b2["checks"] == []
      assert b2["universe"] =~ "#{a["population"]["check_count"]} declared checks"
      assert b2["universe"] =~ "never all 173"
    end

    test "buckets 3 and 6 are zero because every ET verdict is green — the predicate, not the number",
         %{a: a} do
      assert Enum.all?(a["cells"], &(&1["verdicts"]["et"] == "green"))
      refute Map.has_key?(a["buckets"]["from_edges"], "3")
      refute Map.has_key?(a["buckets"]["from_edges"], "6")

      assert a["buckets"]["empty_by_construction"]["predicate_that_returned_zero"] =~
               "et_verdict green"
    end

    test "no two cells share a (member, claim, tag) triple — the merged row a wrong key would make",
         %{a: a} do
      triples = Enum.map(a["cells"], &{&1["member"]["register_key"], &1["claim"], &1["tag"]})
      assert length(triples) == length(Enum.uniq(triples))
    end

    test "the population is DECLARED, and the remainder is a third state with an owner", %{a: a} do
      p = a["population"]
      assert p["declared"]
      assert p["member_count"] == length(p["members"])
      assert p["check_count"] == length(p["checks"])
      assert p["outside_the_population"]["state"] == "not_yet_adjudicated"
      assert p["outside_the_population"]["et_cc_members"] == 281 - p["member_count"]
      assert p["outside_the_population"]["in_denominator_checks"] == 173 - p["check_count"]
      assert p["outside_the_population"]["owners"] =~ "MES-104"
      assert p["outside_the_population"]["owners"] =~ "MES-105"
    end

    test "the keying control ran BOTH directions and recorded a positive result", %{a: a} do
      k = a["keying_control"]
      assert k["by_a1s_six_field_key"] == 0
      assert k["by_check_id_alone"] > 0
      assert k["by_name_alone"] > 0
      assert k["measure"] =~ "ROWS LOST"
    end

    test "the WARNING mapping fires on zero rows here, and the artefact says so", %{a: a} do
      v = a["verdict_mapping"]
      assert v["warning_rows_in_this_population"] == 0
      assert Enum.all?(a["cells"], &(&1["verdicts"]["oc_warning"] == false))
      assert v["warning_is_untested_by_live_data_here"] =~ "ZERO rows"
      assert v["warning_residual"] =~ "CLIENT-leg"
    end

    test "every escalated cell is routed, with its reason and its shape", %{a: a} do
      esc = a["escalations"]
      assert esc["count"] == Enum.count(a["cells"], &(not is_nil(&1["escalation"])))
      assert esc["routed_to"] =~ "PM"

      for row <- esc["rows"] do
        assert row["escalation"] != nil
        assert row["tag"] != nil
        assert row["claim"] != nil
      end
    end

    test "every cell carries evidence — an address AND what is at it (ruling 7)", %{a: a} do
      for cell <- a["cells"] do
        assert is_binary(cell["evidence"])
        assert String.length(cell["evidence"]) > 40, cell["claim"]
        # a file:line address, and the assertion at it
        assert cell["evidence"] =~ ~r/\.exs:\d+/, cell["claim"]
      end
    end

    test "the artefact records that C3 falsification-tested it, and the BOUND on that", %{a: a} do
      # It said UNFALSIFIED until MES-99. Leaving that after C3 landed would be the
      # artefact understating its own trust; replacing it with a bare "falsified"
      # would overstate it. Both halves are asserted.
      assert a["trust_status"] =~ "FALSIFICATION-TESTED by C3 (MES-99) and STANDING"
      # "standing" and "proven" are different claims and the artefact must make the
      # weaker one. `UNFALSIFIED` here meant "not yet attempted", so the antonym had
      # to be spelled out rather than left to read as "found to be false".
      assert a["trust_status"] =~ "not proven"
      assert a["trust_status"] =~ "declared 21-member / 14-check slice and no further"
      assert a["trust_status"] =~ "CONSISTENCY pin, not a correctness claim"
      # The stale claim is the OPENING word, not the string anywhere: the new text
      # explains what `UNFALSIFIED` used to mean here, so a bare `refute =~` would
      # fire on the correction itself. This asserts what the field LEADS with.
      refute String.starts_with?(a["trust_status"], "UNFALSIFIED")

      x2 = Enum.find(a["residuals"], &(&1["id"] == "X2"))
      assert x2["text"] =~ "FALSIFICATION-TESTED by C3 (MES-99) and STANDING"
      assert x2["text"] =~ "not the same as proven"
      assert x2["text"] =~ "C1b (MES-104) and C1c (MES-105) own the rest"

      # X1 is what no refusal can reach, and C3 must not be read as having reached it.
      assert x2["text"] =~ "X1 is untouched"
    end

    test "the population records the selector it was checked against (G15)", %{a: a} do
      sel = a["population"]["selector"]

      # The anchor is EXTERNAL — that is the whole content of G15. A selector
      # naming the edges file would be circular by another route.
      assert sel["source"] == "docs/conformance/etcc-attribution.json"
      refute sel["source"] =~ "crosswalk-edges"
      assert sel["rows_at"] == "rows"
      assert sel["key_field"] == "key"
      assert sel["evaluated"] =~ "#{a["population"]["member_count"]} members denoted"
      assert sel["evaluated"] =~ "both"
    end

    test "the cross-source agreement is recorded, and named CONSISTENCY (G16)", %{a: a} do
      g = a["cross_source_agreement"]

      assert g["agrees"]
      assert g["compared"] == 175
      assert g["disagreements"] == []
      assert g["key_sets"]["equal"]
      assert g["what_this_is"] =~ "CONSISTENCY pin, not a correctness one"

      x6 = Enum.find(a["residuals"], &(&1["id"] == "X6"))
      assert x6["text"] =~ "CONSISTENCY pin"
      assert x6["text"] =~ "SAME accepted harness run"
    end

    test "no two cells share the join's key — G14's predicate, on the output", %{a: a} do
      # The generator refuses this on ITS path now (G14). This unit checks the
      # committed artefact, which is a different question: the refusal is about
      # what can be built, this is about what WAS built.
      triples =
        Enum.map(a["cells"], &{&1["member"]["register_key"], &1["claim"], &1["tag"]})

      assert Crosswalk.duplicate_edge_keys(
               Enum.map(a["cells"], fn c ->
                 %{"member" => c["member"], "claim" => c["claim"], "tag" => c["tag"]}
               end)
             ) == []

      assert length(Enum.uniq(triples)) == length(triples)
    end
  end
end

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

    test "a malformed selector refuses — no rows_at, no key_field, not a map" do
      for bad <- [%{}, %{"rows_at" => "rows"}, %{"key_field" => "key"}, nil] do
        assert {:error, {:malformed_selector, ^bad}} = Crosswalk.select(bad, @source)
      end
    end

    test "a selector with no combinator at the root refuses, naming the three" do
      assert {:error, {:selector_root_names_no_combinator, combinators}} =
               Crosswalk.select(Map.delete(@selector, "any_of"), @source)

      assert combinators == Crosswalk.combinators()
    end

    test "a selector naming TWO combinators at the root refuses rather than picking one" do
      # Whichever clause matched first would silently choose between two
      # different populations.
      assert {:error, {:selector_root_names_several_combinators, ["any_of", "all_of"]}} =
               Crosswalk.select(Map.put(@selector, "all_of", [%{}]), @source)
    end

    test "an EMPTY combinator list refuses — a vacuous all_of is true of every row" do
      for name <- Crosswalk.combinators() do
        sel = @selector |> Map.delete("any_of") |> Map.put(name, [])
        assert {:error, :selector_combinator_is_empty} = Crosswalk.select(sel, @source)
      end
    end

    test "a combinator whose value is not a list refuses" do
      assert {:error, {:selector_combinator_is_not_a_list, "nope"}} =
               Crosswalk.select(Map.put(@selector, "any_of", "nope"), @source)
    end

    test "a node that is not a map refuses" do
      assert {:error, {:selector_node_is_not_a_map, "leaf"}} =
               Crosswalk.select(Map.put(@selector, "any_of", ["leaf"]), @source)
    end
  end

  # MES-104 added `equals`, `all_of` and `none_of` — the least the client leg's
  # population needed and nothing more. Each gets a POSITIVE control (it denotes
  # the set claimed, set-compared against an independently computed one) and a
  # MUTATION (the predicate can go wrong and the difference is visible).
  describe "select/2 — the tests and combinators MES-104 added" do
    @rows [
      %{"key" => "a", "leg" => "client", "cg" => "CG7", "tokens" => []},
      %{"key" => "b", "leg" => "client", "cg" => nil, "tokens" => ["oc:x"]},
      %{"key" => "c", "leg" => "client", "cg" => "CG1", "tokens" => []},
      %{"key" => "d", "leg" => "server", "cg" => "CG7", "tokens" => ["oc:y"]},
      %{"key" => "e", "leg" => "none_determinable", "cg" => nil, "tokens" => []}
    ]
    @src %{"rows" => @rows}

    defp sel(node), do: Map.merge(%{"rows_at" => "rows", "key_field" => "key"}, node)

    defp expect(node, keys) do
      assert {:ok, got} = Crosswalk.select(sel(node), @src)
      assert got == keys
      got
    end

    test "equals — positive, and a wrong value denotes a different set" do
      expect(
        %{"any_of" => [%{"field" => "leg", "test" => "equals", "value" => "client"}]},
        ~w(a b c)
      )

      # MUTATION: the value alone decides, so a typo silently selects nothing.
      expect(%{"any_of" => [%{"field" => "leg", "test" => "equals", "value" => "clientt"}]}, [])
    end

    test "equals refuses a non-string value rather than comparing structures" do
      for v <- [1, nil, ["client"], %{}] do
        assert {:error, {:unknown_selector_test, _}} =
                 Crosswalk.select(
                   sel(%{"any_of" => [%{"field" => "leg", "test" => "equals", "value" => v}]}),
                   @src
                 )
      end
    end

    test "equals with no `value` at all refuses — an absent field is not a null one" do
      assert {:error, {:unknown_selector_test, _}} =
               Crosswalk.select(
                 sel(%{"any_of" => [%{"field" => "leg", "test" => "equals"}]}),
                 @src
               )
    end

    test "all_of is a CONJUNCTION — and behaving as any_of would be visible" do
      conj = [
        %{"field" => "leg", "test" => "equals", "value" => "client"},
        %{"field" => "cg", "test" => "equals", "value" => "CG7"}
      ]

      expect(%{"all_of" => conj}, ~w(a))

      # THE MUTATION THAT MATTERS: the same two nodes under `any_of` denote a
      # different set. On the real anchor the two differ by 78 members; here by
      # three rows, and the point is the same — a combinator silently behaving
      # as its sibling changes the population without changing the selector's
      # shape.
      expect(%{"any_of" => conj}, ~w(a b c d))
    end

    test "none_of is a NEGATION, and states the rule rather than enumerating the alternatives" do
      tagged = %{"field" => "tokens", "test" => "non_empty_list"}
      not_client = %{"none_of" => [%{"field" => "leg", "test" => "equals", "value" => "client"}]}

      expect(%{"all_of" => [tagged, not_client]}, ~w(d))

      # The enumeration that would denote the same set TODAY, and the mutation
      # that separates them: a new leg value joins `none_of[client]` and is
      # silently dropped by the enumeration.
      enumerated = %{
        "any_of" => [
          %{"field" => "leg", "test" => "equals", "value" => "server"},
          %{"field" => "leg", "test" => "equals", "value" => "none_determinable"}
        ]
      }

      expect(%{"all_of" => [tagged, enumerated]}, ~w(d))

      grown = %{"rows" => @rows ++ [%{"key" => "f", "leg" => "gateway", "tokens" => ["oc:z"]}]}

      assert {:ok, ~w(d f)} = Crosswalk.select(sel(%{"all_of" => [tagged, not_client]}), grown)
      assert {:ok, ~w(d)} = Crosswalk.select(sel(%{"all_of" => [tagged, enumerated]}), grown)
    end

    test "combinators NEST, and the exactly-one rule applies at every depth" do
      expect(
        %{
          "all_of" => [
            %{"field" => "leg", "test" => "equals", "value" => "client"},
            %{
              "any_of" => [
                %{"field" => "cg", "test" => "equals", "value" => "CG7"},
                %{"field" => "tokens", "test" => "non_empty_list"}
              ]
            }
          ]
        },
        ~w(a b)
      )

      assert {:error, {:selector_node_names_several_combinators, ["any_of", "all_of"]}} =
               Crosswalk.select(
                 sel(%{"all_of" => [%{"any_of" => [%{}], "all_of" => [%{}]}]}),
                 @src
               )
    end
  end

  # MES-104. `axes_exist/3`'s duplicate-axis clause was UNREACHABLE: the
  # preceding clause computed `named -- known`, and list subtraction removes one
  # occurrence per element, so a duplicate always left a residue and was
  # reported as an axis the decomposition does not contain — over an axis that
  # is plainly in it. Found by a control that asserts WHICH guard fires.
  describe "cell/4 — a duplicated axis is reported as a duplicate, not as an unknown one" do
    @known [
      "client",
      "sep-2322-client-request-state",
      "sep-2322-client-request-state-echoed",
      "MRTRClientRequestStateEchoed",
      "Client MUST echo back the exact value of requestState when retrying",
      ""
    ]

    defp dup_edge(axes) do
      %{
        "member" => %{"module" => "M", "test" => "t", "register_key" => "M/t"},
        "claim" => "c",
        "tag" => MatchKey.encode!(@known),
        "axes" => Enum.map(axes, &%{"axis" => &1, "verdict" => "agrees"}),
        "et_verdict" => "green",
        "evidence" => "e"
      }
    end

    defp build(axes, decomposition) do
      Crosswalk.cell(
        dup_edge(axes),
        [@known],
        %{@known => "SUCCESS"},
        %{@known => decomposition}
      )
    end

    test "a duplicate of a KNOWN axis is :axis_named_twice" do
      assert {:error, {:axis_named_twice, ["a", "a"]}} = build(~w(a a), ~w(a b))
    end

    test "a duplicate where the check has exactly ONE axis is also :axis_named_twice" do
      assert {:error, {:axis_named_twice, ["a", "a"]}} = build(~w(a a), ~w(a))
    end

    test "a genuinely unknown axis is still :axis_not_in_decomposition" do
      assert {:error, {:axis_not_in_decomposition, ["z"], ["a", "b"]}} = build(~w(a b z), ~w(a b))
    end

    test "an unknown axis named TWICE reports it ONCE, not twice" do
      assert {:error, {:axis_not_in_decomposition, ["z"], ["a"]}} = build(~w(a z z), ~w(a))
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

  describe "G21 — the population figures this generator's own prose states (CR-5)" do
    @artefact "docs/conformance/crosswalk-2026-07-28.json"

    setup do
      %{a: @artefact |> File.read!() |> Jason.decode!()}
    end

    test "a figure is digits with its noun within two words — and an identifier is not one" do
      assert [{68, "68 declared members"}] =
               Crosswalk.population_claims("the 68 declared members")

      assert [{39, "39-declared-check"}] =
               Crosswalk.population_claims("a 39-declared-check slice")

      # `MES-108 moved the check population` is not a claim of 108 checks. Without
      # the lookbehind the guard refused its own explanation of why it exists,
      # which is how this case was found rather than imagined.
      assert Crosswalk.population_claims("after MES-108 moved the check population") == []

      # The stated blind spots, asserted so they cannot be quietly lost: a figure
      # spelled as a word, and a figure without the noun it counts.
      assert Crosswalk.population_claims("C1b-i found five") == []
      assert Crosswalk.population_claims("never all 281") == []
    end

    test "authorship is decided against the INPUTS, not against a list the module keeps" do
      artefact = %{"mine" => "the 68 declared members", "theirs" => "over 175 manifest checks"}
      inputs = Crosswalk.string_set([%{"rows" => [%{"note" => "over 175 manifest checks"}]}])

      assert [{"mine", "the 68 declared members", [{68, _}]}] =
               Crosswalk.authored_statements(artefact, inputs)

      # POSITIVE CONTROL for the exclusion: the data string IS claim-bearing, so
      # a scan that reached nothing would produce the same one-row answer for the
      # wrong reason.
      assert length(Crosswalk.authored_statements(artefact, MapSet.new())) == 2
    end

    test "a figure the crosswalk does not hold is reported; one it holds is not" do
      statements = [{"trust_status", "a 48-member slice", [{48, "48-member"}]}]

      assert Crosswalk.unheld_figures(statements, MapSet.new([68, 39])) ==
               [{"trust_status", 48, "48-member"}]

      assert Crosswalk.unheld_figures(statements, MapSet.new([48])) == []
    end

    test "the phrase pin fires on a HELD figure in the wrong place" do
      a = %{"trust_status" => "the 39-member slice"}

      # 39 is a figure this run holds — the check population. Stated as the
      # MEMBER count it is still wrong, and `unheld_figures/2` cannot see it,
      # because a wrong held figure is a held figure.
      assert Crosswalk.unheld_figures(
               Crosswalk.authored_statements(a, MapSet.new()),
               MapSet.new([39, 68])
             ) == []

      assert Crosswalk.missing_phrases(a, [{"trust_status", "68-member"}]) ==
               [{"trust_status", "68-member"}]

      assert Crosswalk.missing_phrases(a, [{"trust_status", "39-member"}]) == []
    end

    test "an absent statement is a missing phrase, not a pass" do
      # The residual pins resolve a path through the residual's `id`. A reordered
      # or deleted residual yields a path that is not there, and fail-closed
      # means that reads as missing rather than as satisfied.
      assert Crosswalk.missing_phrases(%{}, [{"residuals.[].text", "anything"}]) ==
               [{"residuals.[].text", "anything"}]
    end

    test "the committed artefact carries the guard's report, and it makes no claim of its own",
         %{a: a} do
      report = a["population_statement_guard"]
      assert report =~ "every population figure this generator's own prose states"
      assert report =~ "THE UNIVERSE IS THE EMITTED ARTEFACT"

      # The block is written after the scan, so it must not itself state a
      # population figure — otherwise it would be part of what it attests.
      assert Crosswalk.population_claims(report) == []

      # And it states its own bounds rather than implying there are none.
      assert report =~ "BOUNDS:"
    end

    test "every figure the committed artefact's own prose states is one it holds", %{a: a} do
      # The whole guard, re-run here over the committed file against the figures
      # the file itself carries. It is the generator's verdict re-taken from the
      # artefact rather than read off it.
      held =
        MapSet.new([
          a["arithmetic"]["members"],
          a["arithmetic"]["members_with_edges"],
          a["arithmetic"]["members_declared_unmatched"],
          a["arithmetic"]["edges"],
          a["arithmetic"]["escalated"],
          length(a["population"]["declared_checks"]),
          length(a["population"]["checks"]),
          a["population"]["outside_the_population"]["et_cc_members"],
          a["population"]["outside_the_population"]["in_denominator_checks"],
          a["population"]["member_count"] +
            a["population"]["outside_the_population"]["et_cc_members"],
          a["buckets"]["bucket_1"]["count"],
          a["buckets"]["bucket_2"]["count"],
          a["claim_level_unmatched"]["count"],
          173,
          175
        ])

      held =
        Enum.reduce(a["population"]["files"], held, &MapSet.put(&2, &1["member_count"]))

      # MES-115: the per-file DECLARED-CHECK counts. The generator has held
      # these since C1c-i (`figures/7`'s `per_file_declared_checks`, which
      # records why); this reconstruction never did, and passed anyway because
      # the client file's 54 coincided with `length(population.checks)` and the
      # server file's 30 with `bucket_2`. C1c-ii moved both — checks-with-edges
      # to 60 and bucket 2 to 60 — and two correct, freshly-derived sentences
      # went red at once. Derived from the artefact, never written down, so this
      # moves with the population instead of pinning today's.
      held =
        a["population"]["files"]
        |> Enum.reduce(held, fn f, acc ->
          MapSet.put(acc, length(get_in(f, ["check_population", "checks"]) || []))
        end)

      # MES-109: the leg-totality figures. Taken from the files' own
      # `leg_totality` blocks and NOT hard-coded, so this reconstruction moves
      # with the artefact rather than pinning today's leg — a hand-written 107
      # here would make the unit pass by coincidence once the server leg lands.
      held =
        a["population"]["files"]
        |> Enum.filter(&get_in(&1, ["leg_totality", "declared"]))
        |> Enum.reduce(held, fn f, acc ->
          acc
          |> MapSet.put(get_in(f, ["leg_totality", "members"]))
          |> MapSet.put(
            get_in(f, ["leg_totality", "cover_not_partition", "in_more_than_one_slice"])
          )
        end)

      held =
        MapSet.union(
          held,
          MapSet.new([
            a["absence_search_guard"]["entries"],
            a["absence_search_guard"]["rows_checked"],
            a["absence_search_guard"]["rows_naming_a_registered_search"]
          ])
        )

      # MES-115: `crosswalk-edges-server.json` WAS MISSING from this list. C1c-i
      # opened that file and wired it into two control suites; this unit's copy
      # of the generator's input set was a third place and was not updated. The
      # omission is fail-SAFE in direction — a missing input makes MORE strings
      # count as this generator's own, never fewer — but it is still the wrong
      # set, and it made the unit refuse a figure the edges file itself states.
      inputs =
        Crosswalk.string_set(
          Enum.map(
            ~w(conformance/data/crosswalk-edges-client.json
               conformance/data/crosswalk-edges-server.json
               conformance/data/crosswalk-edges.json
               conformance/data/oc-axes-c1.json
               docs/conformance/oc-axes-2026-07-28.json
               docs/conformance/in-scope-2026-07-28.json
               docs/conformance/bucket-0-2026-07-28.json
               docs/conformance/etcc-register.json
               docs/conformance/etcc-attribution.json
               docs/conformance/oc-emitting-sites-2026-07-28.json),
            &(&1 |> File.read!() |> Jason.decode!())
          )
        )

      statements = Crosswalk.authored_statements(a, inputs)

      # POSITIVE CONTROL: the scan reached the statement CR-5 was raised about.
      # Without it a scan that read nothing would report this same clean zero.
      assert Enum.any?(statements, fn {path, _t, _c} -> path == "trust_status" end)
      assert length(statements) > 5

      assert Crosswalk.unheld_figures(statements, held) == []
    end
  end

  describe "select/2 — the `is_null` test MES-109 added, and the one decision in it" do
    # Deliberately NOT @rows above: the whole point of this leaf is what it does
    # with a row that does NOT CARRY the field, and every row up there carries
    # `cg`. A fixture that cannot express the case cannot test it.
    @null_rows [
      %{"key" => "a", "leg" => "client", "cg" => "CG7"},
      %{"key" => "b", "leg" => "client", "cg" => nil},
      %{"key" => "c", "leg" => "client"},
      %{"key" => "d", "leg" => "server", "cg" => nil}
    ]
    @null_src %{"rows" => @null_rows}

    defp nsel(node) do
      Map.merge(%{"rows_at" => "rows", "key_field" => "key"}, node)
    end

    test "POSITIVE — a field PRESENT and null is denoted" do
      assert {:ok, ~w(b d)} =
               Crosswalk.select(
                 nsel(%{"any_of" => [%{"field" => "cg", "test" => "is_null"}]}),
                 @null_src
               )
    end

    test "an ABSENT field is NOT denoted — this is the limb that is easy to leave out" do
      # Row "c" carries no `cg` key at all. Under `Map.get(row, f) == nil` it
      # would be denoted and the population would silently grow; under
      # `has_key? and == nil` it is not. Both readings agree on every other row
      # in this fixture, which is exactly why this case needs its own unit.
      {:ok, got} =
        Crosswalk.select(
          nsel(%{"any_of" => [%{"field" => "cg", "test" => "is_null"}]}),
          @null_src
        )

      refute "c" in got
    end

    test "a field NO row carries denotes NOTHING, not everything — fail-closed" do
      # The B2b-schema-change case, at fixture scale: if the anchor stopped
      # carrying the field the leaf names, the weaker reading would denote all
      # four rows and re-declare the population. This denotes none, so the
      # caller's set comparison goes red instead.
      assert {:ok, []} =
               Crosswalk.select(
                 nsel(%{"any_of" => [%{"field" => "no_such_field", "test" => "is_null"}]}),
                 @null_src
               )

      # And the weaker reading really would differ here — stated as an
      # assertion about the fixture so the unit above is a measurement rather
      # than a restatement of itself.
      assert Enum.count(@null_rows, &(Map.get(&1, "no_such_field") == nil)) == 4
    end

    test "it composes — `leg equals client AND cg is_null` is C1b-iii's own population" do
      assert {:ok, ~w(b)} =
               Crosswalk.select(
                 nsel(%{
                   "all_of" => [
                     %{"field" => "leg", "test" => "equals", "value" => "client"},
                     %{"field" => "cg", "test" => "is_null"}
                   ]
                 }),
                 @null_src
               )
    end

    test "`not_null` and `is_null` are not complements over rows that lack the field" do
      # Worth pinning because the names suggest they are. Over this fixture
      # `not_null` takes {a} plus row c (absent reads as... nothing, so it is
      # rejected) and `is_null` takes {b, d} — c is in NEITHER, which is the
      # behaviour a reader would not predict from the names alone.
      {:ok, nulls} =
        Crosswalk.select(
          nsel(%{"any_of" => [%{"field" => "cg", "test" => "is_null"}]}),
          @null_src
        )

      {:ok, not_nulls} =
        Crosswalk.select(
          nsel(%{"any_of" => [%{"field" => "cg", "test" => "not_null"}]}),
          @null_src
        )

      refute "c" in nulls
      refute "c" in not_nulls
      assert length(nulls) + length(not_nulls) == length(@null_rows) - 1
    end
  end

  describe "select/2 — the `starts_with` test MES-105 added, and its two fail-closed limbs" do
    # A fixture built to separate the cases the leaf has to get right, rather
    # than one that happens to be the shipped anchor. `b` is the EXTENDING
    # module — the case the trailing `/` exists for — and `e` carries a
    # non-string in the field the leaf reads.
    @prefix_rows [
      %{"key" => "MCP.Server.DispatchTest/test one", "leg" => "server"},
      %{"key" => "MCP.Server.DispatchTestExtra/test two", "leg" => "server"},
      %{"key" => "MCP.Server.DispatchTest/test three", "leg" => "client"},
      %{"key" => "MCP.Other.Test/test four", "leg" => "server"},
      %{"key" => "e", "leg" => "server", "module" => 7}
    ]
    @prefix_src %{"rows" => @prefix_rows}

    defp psel(node), do: Map.merge(%{"rows_at" => "rows", "key_field" => "key"}, node)

    test "POSITIVE — a prefix denotes exactly the rows whose field starts with it" do
      assert {:ok, ["MCP.Server.DispatchTest/test one", "MCP.Server.DispatchTest/test three"]} =
               Crosswalk.select(
                 psel(%{
                   "any_of" => [
                     %{
                       "field" => "key",
                       "test" => "starts_with",
                       "value" => "MCP.Server.DispatchTest/"
                     }
                   ]
                 }),
                 @prefix_src
               )
    end

    test "the trailing `/` REFUSES the extending module, and dropping it ADMITS it" do
      with_slash = fn v ->
        {:ok, got} =
          Crosswalk.select(
            psel(%{"any_of" => [%{"field" => "key", "test" => "starts_with", "value" => v}]}),
            @prefix_src
          )

        got
      end

      strict = with_slash.("MCP.Server.DispatchTest/")
      relaxed = with_slash.("MCP.Server.DispatchTest")

      # BOTH DIRECTIONS ON THE SAME FIXTURE. A fixture that failed to separate
      # them would show up as a green on either assertion alone.
      refute Enum.any?(strict, &String.starts_with?(&1, "MCP.Server.DispatchTestExtra/"))
      assert Enum.any?(relaxed, &String.starts_with?(&1, "MCP.Server.DispatchTestExtra/"))
      assert length(relaxed) == length(strict) + 1
    end

    test "an EMPTY prefix is REFUSED — it would be true of every row" do
      assert {:error, :selector_starts_with_prefix_is_empty} =
               Crosswalk.select(
                 psel(%{
                   "any_of" => [%{"field" => "key", "test" => "starts_with", "value" => ""}]
                 }),
                 @prefix_src
               )
    end

    test "a NON-STRING field value denotes nothing rather than matching or raising" do
      assert {:ok, []} =
               Crosswalk.select(
                 psel(%{
                   "any_of" => [%{"field" => "module", "test" => "starts_with", "value" => "M"}]
                 }),
                 @prefix_src
               )
    end

    test "a non-string `value` is refused as an unknown test, like `equals`" do
      assert {:error, {:unknown_selector_test, _}} =
               Crosswalk.select(
                 psel(%{
                   "any_of" => [%{"field" => "key", "test" => "starts_with", "value" => 7}]
                 }),
                 @prefix_src
               )
    end

    test "it composes — `leg equals server AND key starts_with` is C1c-i's own population" do
      assert {:ok, ["MCP.Server.DispatchTest/test one"]} =
               Crosswalk.select(
                 psel(%{
                   "all_of" => [
                     %{"field" => "leg", "test" => "equals", "value" => "server"},
                     %{
                       "any_of" => [
                         %{
                           "field" => "key",
                           "test" => "starts_with",
                           "value" => "MCP.Server.DispatchTest/"
                         }
                       ]
                     }
                   ]
                 }),
                 @prefix_src
               )
    end
  end

  describe "absence_entry_problems/3 — G23's decision logic" do
    @good %{
      "id" => "S01",
      "kind" => "no-oc-scenario",
      "subject" => "a client parsing one SSE event's text into fields",
      "pattern" => "(?i)server-sent",
      "hits" => 0,
      "population" => %{"kind" => "manifest_rows", "rows" => 175},
      "positive_controls" => [%{"term" => "(?i)\\bsse\\b", "hits" => 2}],
      "near_miss" => "server-sse-multiple-streams, and it is server-leg"
    }
    @tag_ok "oc:none/no-oc-scenario/sse-decode-all-fields"

    test "POSITIVE — a complete entry against a row whose slug it matches has no problems" do
      assert Crosswalk.absence_entry_problems(@tag_ok, "S01", @good) == []
    end

    test "each required field, removed one at a time, is reported BY NAME" do
      # One mutation per limb, and the assertion is on WHICH problem comes back.
      # "it returned something" would pass for a guard that reports the wrong
      # defect, which is the failure mode a bare `!= []` cannot see.
      for {mutate, expected} <- [
            {&Map.put(&1, "hits", 1), :entry_does_not_record_zero},
            {&Map.delete(&1, "population"), :entry_names_no_population},
            {&Map.put(&1, "pattern", ""), :entry_has_no_pattern},
            {&Map.delete(&1, "subject"), :entry_has_no_subject},
            {&Map.put(&1, "near_miss", ""), :entry_names_no_near_miss},
            {&Map.put(&1, "positive_controls", []), :entry_has_no_positive_control}
          ] do
        problems = Crosswalk.absence_entry_problems(@tag_ok, "S01", mutate.(@good))

        assert Enum.map(problems, &elem(&1, 0)) == [expected]
      end
    end

    test "the two `oc:none` slugs are kept apart — a fixture-case entry under a scenario row" do
      # A4 defines two slugs and the difference is the whole content of a
      # bucket-1 record: `no-oc-scenario` says the suite has no such check
      # anywhere, `no-oc-fixture-case` says the scenario exists and its fixture
      # holds no exercising case. An entry of one kind cited from a row of the
      # other merges them silently.
      fixture = %{@good | "kind" => "no-oc-fixture-case"}

      assert [
               {:entry_kind_is_not_the_rows_reason_slug, "S01", "no-oc-fixture-case",
                "no-oc-scenario"}
             ] =
               Crosswalk.absence_entry_problems(@tag_ok, "S01", fixture)

      # And the other direction, so the check is not one-sided.
      assert Crosswalk.absence_entry_problems(
               "oc:none/no-oc-fixture-case/mrtr-no-resolver",
               "S15",
               fixture
             ) == []
    end

    test "a tag that is not an `oc:none` token at all yields no slug, and that is a problem" do
      for tag <- [nil, "", "oc:client/tools_call/wire-schema-valid/WireSchemaValid", "nonsense"] do
        assert [{:entry_kind_is_not_the_rows_reason_slug, _, _, _}] =
                 Crosswalk.absence_entry_problems(tag, "S01", @good)
      end
    end

    test "a row's COPY of the subject or the near miss must be the entry's (D4)" do
      # The row carries prose copies because that prose is what a reviewer
      # reads, but a copy is a second home and two copies can disagree with
      # nothing noticing. MES-109 edited three near misses after measuring
      # them and had to edit each in two places, which is how this arrived.
      row = %{
        "the_search_that_found_none" => @good["subject"],
        "the_near_miss_that_is_not_a_counterpart" => @good["near_miss"]
      }

      assert Crosswalk.absence_entry_problems(@tag_ok, "S01", @good, row) == []

      for field <- ~w(the_search_that_found_none the_near_miss_that_is_not_a_counterpart) do
        drifted = Map.put(row, field, "something else entirely")

        assert [{:row_copy_has_drifted_from_the_entry, "S01", ^field}] =
                 Crosswalk.absence_entry_problems(@tag_ok, "S01", @good, drifted)
      end
    end

    test "a row carrying NO copy is unaffected — this is not a demand that every row copies" do
      assert Crosswalk.absence_entry_problems(@tag_ok, "S01", @good, %{}) == []
    end

    test "several defects at once are ALL reported, not just the first" do
      broken = @good |> Map.put("hits", 3) |> Map.put("near_miss", "") |> Map.delete("population")

      assert Enum.map(Crosswalk.absence_entry_problems(@tag_ok, "S01", broken), &elem(&1, 0)) == [
               :entry_does_not_record_zero,
               :entry_names_no_population,
               :entry_names_no_near_miss
             ]
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
      # MES-104: `every_declared_check_appears` was a set equality that held
      # TRIVIALLY — the declared set was derived from the tags the edges
      # carried, so both sides were the same list twice. Once the checks are
      # declared from outside the file the checks that do NOT appear are
      # bucket 2, which is the answer rather than a failure.
      c = t["every_declared_check_is_decomposed_and_accounted_for"]
      assert c["declared"] == c["with_an_edge"] + c["in_bucket_2"]
      assert c["in_bucket_2"] == a["buckets"]["bucket_2"]["count"]
      assert c["why_this_is_not_a_set_equality"] =~ "held"
      refute Map.has_key?(t, "every_declared_check_appears")
    end

    test "bucket 1 is exactly the declared-unmatched members, by set", %{a: a} do
      declared = Enum.map(a["declared_unmatched"], & &1["member"]["register_key"])
      assert %{equal: true} = Crosswalk.set_compare(declared, a["buckets"]["bucket_1"]["members"])
    end

    test "bucket 2 is NON-EMPTY for the first time, over a declared universe", %{a: a} do
      b2 = a["buckets"]["bucket_2"]

      assert b2["declared"]
      assert b2["count"] == length(b2["checks"])
      assert b2["count"] > 0, "bucket 2 was empty BY CONSTRUCTION until MES-104 (residual X8)"
      assert b2["universe"] =~ "#{a["population"]["declared_check_count"]} declared checks"
      assert b2["universe"] =~ "never all 173"

      # Every bucket-2 check is DECLARED and carries no edge — the two halves of
      # what the bucket means, asserted rather than taken from the count.
      declared = MapSet.new(a["population"]["declared_checks"])
      with_edges = MapSet.new(Enum.map(a["cells"], & &1["tag"]))

      for tag <- b2["checks"] do
        assert MapSet.member?(declared, tag)
        refute MapSet.member?(with_edges, tag)
      end
    end

    test "a check ADDRESSED but not DECLARED is neither bucket 2 nor not_yet_adjudicated",
         %{a: a} do
      outside = a["population"]["checks_addressed_outside_the_declared_check_population"]
      declared = MapSet.new(a["population"]["declared_checks"])
      b2 = MapSet.new(a["buckets"]["bucket_2"]["checks"])

      assert outside["count"] == length(outside["checks"])

      # THE SET, computed INDEPENDENTLY from the artefact's own two inputs. It
      # used to be enough to assert the population was non-empty and then loop
      # over it; MES-105 (C1c-i) emptied it — the three checks that were
      # addressed-but-not-declared were C1a's inherited server rows, and the
      # server file now DECLARES the scenario they land in — so the loop went
      # vacuous and the `> 0` went red. A test that is satisfied by an empty
      # loop is not a test, so the derivation itself is what is checked, and it
      # is checked at every size including this one.
      addressed = a["cells"] |> Enum.map(& &1["tag"]) |> Enum.uniq() |> MapSet.new()

      assert MapSet.size(addressed) > 0
      assert MapSet.size(declared) > 0
      assert MapSet.new(outside["checks"]) == MapSet.difference(addressed, declared)
      assert outside["count"] == MapSet.size(MapSet.difference(addressed, declared))

      for tag <- outside["checks"] do
        refute MapSet.member?(declared, tag)
        refute MapSet.member?(b2, tag)
        assert Enum.any?(a["cells"], &(&1["tag"] == tag))
      end
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
      assert p["declared_check_count"] == length(p["declared_checks"])
      assert p["outside_the_population"]["state"] == "not_yet_adjudicated"
      assert p["outside_the_population"]["et_cc_members"] == 281 - p["member_count"]

      # A check that carries an edge is adjudicated whether or not a file
      # DECLARES it, so the remainder is 173 minus the UNION and not minus
      # either one (MES-104).
      adjudicated = Enum.uniq(p["declared_checks"] ++ p["checks"])
      assert p["outside_the_population"]["in_denominator_checks"] == 173 - length(adjudicated)
      assert p["outside_the_population"]["owners"] =~ "C1c"
      assert p["outside_the_population"]["owners"] =~ "MES-105"

      # And it does not name the ticket that RENDERED it as still owing the
      # remainder. That is CR-1's defect (MES-104) and it recurred as CR-5 on
      # MES-108. Owners are written `<name> = <KEY> (...)`, so this asks the
      # structural question rather than exempting a phrase: NO owner entry may
      # be any C1b sub-ticket, because all three have landed and the client
      # leg they share is closed. Written as a pattern over the family rather
      # than as a list of the two that were wrong before, so the next render
      # cannot re-introduce the third.
      refute p["outside_the_population"]["owners"] =~ ~r/C1b-i+\s*=/
      refute p["outside_the_population"]["owners"] =~ ~r/MES-(104|108|109)\s*\(/

      # The prohibition has to be shown capable of firing, or it is a regex
      # nobody has seen match: the SAME pattern over the wording MES-108
      # shipped does match, so a green above is the artefact's and not the
      # pattern's.
      assert "C1b-iii = MES-109 (the client-leg members no CG covers); C1c = MES-105" =~
               ~r/C1b-i+\s*=/

      # Positive: the one ticket that IS still owed is named, with its key.
      assert p["outside_the_population"]["owners"] =~ ~r/C1c\s*=\s*MES-105/
    end

    # EVERY leg a file declares, not `the` one. This read `[f] = ...` until
    # MES-117, which was indistinguishable from correct while exactly one file
    # declared a leg and became a MatchError the moment the server leg closed.
    # The list is asserted non-empty and its contents named, so the generalised
    # form cannot pass vacuously over a run that declares none.
    test "every declared leg is TOTAL, and each cover's arithmetic closes", %{a: a} do
      fs = Enum.filter(a["population"]["files"], &get_in(&1, ["leg_totality", "declared"]))

      assert Enum.map(fs, &get_in(&1, ["leg_totality", "leg"])) |> Enum.sort() ==
               ["client", "server"]

      for f <- fs, do: assert_leg_total(f)
    end

    defp assert_leg_total(f) do
      t = f["leg_totality"]
      c = t["cover_not_partition"]

      assert t["members"] == f["member_count"]

      # A COVER, and the arithmetic that proves it is one rather than a
      # partition: the slices sum to more than the leg, and the excess IS the
      # overlap, because every overlapping member here sits in exactly two
      # slices. If one ever sat in three the identity would break, and that is
      # the point of asserting it rather than asserting `sum > distinct`.
      assert c["distinct"] == t["members"]
      assert c["sum_of_the_slices"] > c["distinct"]
      assert c["sum_of_the_slices"] - c["distinct"] == c["in_more_than_one_slice"]
      assert length(c["members"]) == c["in_more_than_one_slice"]

      # Every slice is named by a ticket and denotes something. A slice
      # denoting nothing would contribute nothing to the union and the cover
      # would hold without it — the sub-population equivalent of a guard
      # nobody calls.
      assert length(t["slices"]) > 1
      assert Enum.all?(t["slices"], &(&1["denotes"] > 0))
      assert Enum.all?(t["slices"], &(is_binary(&1["ticket"]) and &1["ticket"] != ""))

      # The leg really is the whole leg, checked against B2b here rather than
      # taken from the artefact's own word: the generator's G22b is a refusal
      # and this is the same comparison re-taken from outside it.
      rows =
        "docs/conformance/etcc-attribution.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("rows")
        |> Enum.filter(&(&1["leg"] == t["leg"]))
        |> Enum.map(& &1["key"])

      assert rows != []
      assert Crosswalk.set_compare(rows, f["members"]).equal
    end

    test "a file that declares no leg says so, rather than reporting a pass", %{a: a} do
      # The optionality has to be exercised on real data or it is untested
      # branch. `crosswalk-edges.json` holds three server members that are NOT
      # the server leg, so claiming totality there would be false rather than
      # missing.
      others = Enum.reject(a["population"]["files"], &get_in(&1, ["leg_totality", "declared"]))

      assert others != []
      assert Enum.all?(others, &(&1["leg_totality"]["result"] =~ "NOT ASSERTED"))
    end

    test "every bucket-1 row names a search, and the registry's reach is stated", %{a: a} do
      g = a["absence_search_guard"]

      assert g["rows_checked"] == a["buckets"]["bucket_1"]["count"]

      assert Enum.all?(
               a["declared_unmatched"],
               &(&1["the_search_that_found_none"] not in [nil, ""])
             )

      # The registry limb reaches fewer rows than the prose limb, and the
      # artefact says by how much rather than letting the green imply parity.
      assert g["rows_naming_a_registered_search"] <= g["rows_checked"]
      assert g["registry_limb_reach"] =~ "rows carrying a `search_id`"

      # Every id a row names resolves, and every entry is named — checked on
      # the OUTPUT, which is a different question from the generator refusing
      # to build one that does not.
      named =
        a["declared_unmatched"]
        |> Enum.map(& &1["search_id"])
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      # The edges files are read OFF THE ARTEFACT's own population block rather
      # than listed here. A hard-coded pair silently stopped covering the
      # registry when MES-105 added a third file: the ids it collected were the
      # client leg's alone, and the set comparison below then compared 19
      # entries against 36 named ids and went red for the right reason by
      # accident. Deriving the list means a fourth file is inside this test
      # without anyone remembering to add it.
      entries =
        a["population"]["files"]
        |> Enum.map(& &1["path"])
        |> Enum.flat_map(&((&1 |> File.read!() |> Jason.decode!())["absence_searches"] || []))

      assert length(a["population"]["files"]) > 1

      assert MapSet.new(entries, & &1["id"]) == named
      assert Enum.all?(entries, &(&1["hits"] == 0))

      assert Enum.all?(
               entries,
               &(Crosswalk.absence_entry_problems(nil, &1["id"], &1)
                 |> Enum.map(fn p -> elem(p, 0) end) == [:entry_kind_is_not_the_rows_reason_slug])
             )
    end

    test "every `oc:none` slug in live use has a registered search behind it", %{a: a} do
      slugs =
        a["declared_unmatched"]
        |> Enum.map(&(&1["tag"] |> String.split("/") |> Enum.at(1)))
        |> Enum.frequencies()

      # DERIVED, not listed. The slug set was exactly two until MES-105 (C1c-i),
      # which needed three kinds of zero on the server leg and could not have
      # said so through a test asserting the pair. What is asserted is the
      # PROPERTY that made the pair worth asserting: more than one slug is in
      # use, none is unused, and every one has a registered search declaring it
      # as its `kind` — so a slug cannot be invented for a row without a
      # measurement behind it.
      kinds =
        a["population"]["files"]
        |> Enum.map(& &1["path"])
        |> Enum.flat_map(&((&1 |> File.read!() |> Jason.decode!())["absence_searches"] || []))
        |> Enum.map(& &1["kind"])
        |> Enum.uniq()
        |> Enum.sort()

      assert map_size(slugs) > 1
      assert Enum.all?(Map.values(slugs), &(&1 > 0))
      assert Map.keys(slugs) |> Enum.sort() == kinds
    end

    test "the keying control ran BOTH directions and recorded a positive result", %{a: a} do
      k = a["keying_control"]
      assert k["by_a1s_six_field_key"] == 0
      assert k["by_check_id_alone"] > 0
      assert k["by_name_alone"] > 0
      assert k["measure"] =~ "ROWS LOST"
    end

    # REWRITTEN AT MES-115. It used to assert `warning_rows_in_this_population ==
    # 0` and that the artefact's prose said "ZERO rows". Both were true for four
    # tickets and stopped being true the moment C1c-ii declared
    # `IgnoreUnexpectedParams` — one of the suite's only two in-denominator
    # WARNING checks — and landed an edge on it. A unit pinning today's count is
    # the same defect as prose pinning it, one layer down, so what is asserted
    # now is the INVARIANT: the count is the number of WARNING-status cells,
    # whatever that number is, and the prose the generator derives agrees with
    # which side of zero it falls. That the mapping is EXERCISED rather than
    # merely implemented is shown by
    # `crosswalk_falsification_controls.exs warning_mapping`, which also shows
    # it discriminating; this unit only pins the arithmetic.
    test "the WARNING count is DERIVED from the cells, and the prose agrees with it", %{a: a} do
      v = a["verdict_mapping"]
      flagged = Enum.filter(a["cells"], & &1["verdicts"]["oc_warning"])

      assert v["warning_rows_in_this_population"] == length(flagged)

      # and the flag is the STATUS, not a synonym for "not red"
      for cell <- a["cells"] do
        assert cell["verdicts"]["oc_warning"] ==
                 (cell["verdicts"]["oc_status_at_accepted_run"] == "WARNING")
      end

      # every flagged cell is mapped GREEN — that is the whole of D2
      assert Enum.all?(flagged, &(&1["verdicts"]["oc"] == "green"))

      if flagged == [] do
        assert v["warning_live_data"] =~ "NOT EXERCISED"
      else
        assert v["warning_live_data"] =~ "EXERCISED on #{length(flagged)} cell"
        assert v["warning_live_data"] =~ "WHAT THAT DOES NOT ESTABLISH"
      end

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
        # `.ex` as well as `.exs`: a DOCTEST's source is the lib file the
        # doctest is written in, and C1b-i's population contains four.
        assert cell["evidence"] =~ ~r/\.exs?:\d+/, cell["claim"]
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
      # CR-5 on MES-108. This line asserted the LITERAL `48-member /
      # 29-declared-check slice` — the module constant against itself. It passed
      # while the same artefact's arithmetic said 68 and 39, and it is what made
      # the recurrence invisible: a unit that compares a statement to the
      # statement cannot fail. The pair is now taken from the artefact's own
      # derivation, so the assertion CAN fail, and does the moment the prose
      # stops following the population.
      members = a["arithmetic"]["members"]
      checks = length(a["population"]["declared_checks"])
      assert a["trust_status"] =~ "#{members}-member / #{checks}-declared-check slice"

      # And the decomposition is gone rather than re-written: "C1a's 21 plus
      # CG7's 27" enumerated the slice in a way that excluded MES-108's 20, and
      # a fresh decomposition would be a third literal rotting the same way.
      refute a["trust_status"] =~ "48-member"
      refute a["trust_status"] =~ ~r/C1a's 21|CG7's 27/
      assert a["trust_status"] =~ "CONSISTENCY pin, not a correctness claim"
      # The stale claim is the OPENING word, not the string anywhere: the new text
      # explains what `UNFALSIFIED` used to mean here, so a bare `refute =~` would
      # fire on the correction itself. This asserts what the field LEADS with.
      refute String.starts_with?(a["trust_status"], "UNFALSIFIED")

      x2 = Enum.find(a["residuals"], &(&1["id"] == "X2"))
      assert x2["text"] =~ "FALSIFICATION-TESTED by C3 (MES-99) and STANDING"
      assert x2["text"] =~ "not the same as proven"
      # It read "C1b-ii, C1b-iii and C1c (MES-105) own the rest" while C1b-ii
      # was rendering it — CR-1's other half (MES-104), recurring as CR-5. The
      # owners live in one place and the residual points at it.
      assert x2["text"] =~ "`population.outside_the_population.owners` names"
      refute x2["text"] =~ "C1b-ii, C1b-iii and C1c (MES-105) own the rest"
      # MES-104's four new refusals and MES-108's are named, not summarised as
      # "more guards".
      for g <- ~w(G17 G18 G19 G20 G21), do: assert(x2["text"] =~ g)

      # X1 is what no refusal can reach, and C3 must not be read as having reached it.
      assert x2["text"] =~ "X1 is untouched"
    end

    test "EVERY file records the selector it was checked against (G15)", %{a: a} do
      files = a["population"]["files"]
      assert length(files) > 1, "MES-104 made --edges repeatable; one file would not exercise it"

      for f <- files do
        sel = f["selector"]

        # The anchor is EXTERNAL — that is the whole content of G15. A selector
        # naming the edges file would be circular by another route.
        assert sel["source"] == "docs/conformance/etcc-attribution.json"
        refute sel["source"] =~ "crosswalk-edges"
        assert sel["rows_at"] == "rows"
        assert sel["key_field"] == "key"
        assert sel["evaluated"] =~ "#{f["member_count"]} members denoted"
        assert sel["evaluated"] =~ "both"
      end
    end

    test "the files' declared populations are DISJOINT — one member, one home (G17)", %{a: a} do
      files = a["population"]["files"]

      for {f, i} <- Enum.with_index(files), g <- Enum.drop(files, i + 1) do
        shared = MapSet.intersection(MapSet.new(f["members"]), MapSet.new(g["members"]))
        assert MapSet.size(shared) == 0, "#{f["path"]} and #{g["path"]} share #{inspect(shared)}"
      end

      # And the union is the population, by SET rather than by the sum.
      union = files |> Enum.flat_map(& &1["members"]) |> Enum.sort()
      assert %{equal: true} = Crosswalk.set_compare(union, a["population"]["members"])
    end

    test "a file may declare a CHECK population, and one here does not", %{a: a} do
      files = a["population"]["files"]

      declaring = Enum.filter(files, &(&1["check_population"] != nil))
      silent = Enum.filter(files, &(&1["check_population"] == nil))

      assert declaring != [], "bucket 2 needs a declared universe to be answerable at all"
      assert silent != [], "a file that declares none must still be admissible"

      for f <- declaring do
        sel = f["check_population"]["selector"]
        assert sel["source"] == "docs/conformance/oc-emitting-sites-2026-07-28.json"
        refute sel["source"] =~ "crosswalk-edges"
        assert sel["evaluated"] =~ "axis-decomposed (G19)"
        assert length(f["check_population"]["checks"]) == length(f["declared_checks"])
      end

      for f <- silent, do: assert(f["declared_checks"] == [])
    end

    test "the state-4 guard records that it is ENTAILED, and G20 records what is not", %{a: a} do
      p = a["population"]

      # A green from a guard that cannot fire is not evidence, and the artefact
      # has to say which kind of green it is (residual X7).
      assert p["state_4_guard"] =~ "ENTAILED BY G15a AND THEREFORE UNABLE TO FIRE"
      assert p["inherited_tokens_guard"] =~ "G20"

      x7 = Enum.find(a["residuals"], &(&1["id"] == "X7"))
      assert x7["text"] =~ "ENTAILED BY G15a"
      assert x7["text"] =~ "vacuum guard is what fires"
    end

    test "the axis spans are checked against the locator, and rejections are counted (G18)",
         %{a: a} do
      g = a["axis_span_provenance"]

      assert g["checked_against"] == "docs/conformance/oc-emitting-sites-2026-07-28.json"
      assert g["rows"] == g["locator_row"] + g["locator_row_rejected"]
      assert g["locator_row"] > 0
      assert g["locator_row_rejected"] > 0, "a guard with no live rejection is a promise"
      assert g["what_this_does_not_establish"] =~ "RIGHT one"
    end

    test "claim-level unmatched rows are escalated, and every one names its search", %{a: a} do
      c = a["claim_level_unmatched"]

      assert c["count"] == length(c["rows"])
      assert c["count"] > 0
      assert c["routed_to"] =~ "the PM"

      with_edges = MapSet.new(Enum.map(a["cells"], & &1["member"]["register_key"]))

      for row <- c["rows"] do
        # The record is only admissible against a member that HAS an edge — a
        # member with none is state 3 whole and belongs in bucket 1.
        assert MapSet.member?(with_edges, row["member"]["register_key"])
        assert String.length(row["the_search_that_found_none"]) > 80
        assert is_binary(row["owner"]) and row["owner"] != ""
        assert is_binary(row["from"])
      end
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

defmodule MCP.Conformance.LocatorTest do
  @moduledoc """
  Units for the `check_id -> emitting site -> excerpt` traversal (MES-97, C1a).

  **These run on synthetic fixtures, deliberately.** The traversal's decisions
  are the thing under test and every one of them can be posed in twenty bytes
  of JavaScript; driving them through the real 810 KB build would test the
  build as much as the rule, and would couple gate 5 to a `/tmp` artefact that
  is committed nowhere.

  The live cross-check — A3's 13 hand-cut excerpts, re-derived byte-identical —
  lives in `conformance/controls/crosswalk_controls.exs`, which **refuses**
  rather than skipping when the harness is absent. The committed artefact's own
  internal consistency is checked here, because that needs no harness: the
  artefact carries its bytes.

  ## What these units cannot establish

  That the traversal is right about the REAL build. A synthetic fixture proves
  the rule discriminates; only the positive control against A3 proves it agrees
  with the hand answer, and only on 13 of 173 rows.
  """
  use ExUnit.Case, async: true

  alias MCP.Conformance.Locator

  doctest MCP.Conformance.Locator

  describe "the ladder" do
    test "names five rungs, in the order they are tried" do
      assert Locator.ladder() == [
               :id_literal_pair,
               :id_literal_site,
               :id_bound_variable,
               :id_table_value,
               :id_template_prefix
             ]
    end

    test "rung 1 — the id literal adjacent to THIS ROW's own name, as a call argument" do
      h = Locator.index("await a(`my-check`,`MyCheck`,`desc`,()=>({details:{}}))")
      assert {:id_literal_pair, [_], %{}} = Locator.resolve(h, "my-check", "MyCheck")
    end

    test "rung 1 — the same, as an `id:`/`name:` property pair" do
      h = Locator.index("t.push({id:`my-check`,name:`MyCheck`,status:`SUCCESS`})")
      assert {:id_literal_pair, [_], %{}} = Locator.resolve(h, "my-check", "MyCheck")
    end

    test "rung 2 — an emitting site whose NAME is computed pins the check, not the row" do
      h = Locator.index("e.push({id:`my-check`,name:`Prefix_${t}`,status:`SUCCESS`})")
      assert {:id_literal_site, [_], %{}} = Locator.resolve(h, "my-check", "Prefix_tools_list")
    end

    test "rung 3 — an id bound through a BARE literal (MES-76's CONSTANT case)" do
      h = Locator.index("var Za=`my-check`,Qa=[];t.push({id:Za,name:`MyCheck`,status:`SUCCESS`})")

      assert {:id_bound_variable, [_], %{"binding" => "Za"}} =
               Locator.resolve(h, "my-check", "MyCheck")
    end

    test "rung 3 — an id bound through a TERNARY, which MES-76's rule as written misses" do
      js =
        "let c=s?`other-check`:`my-check`;this.checks.push({id:c,name:`Computed_${t}`,status:`SUCCESS`})"

      h = Locator.index(js)

      assert {:id_bound_variable, [_], %{"binding" => "c"}} =
               Locator.resolve(h, "my-check", "Computed_x")
    end

    test "rung 4 — an id taken from a lookup table, pinned to the row by the table ENTRY" do
      js =
        "var Ua={k_one:`my-check`,k_two:`other`};for(let[e,t]of Object.entries(Ua)){this.checks.push({id:t,name:`Row_${e}`,status:`SUCCESS`})}"

      h = Locator.index(js)

      assert {:id_table_value, [_], meta} = Locator.resolve(h, "my-check", "Row_k_one")
      assert meta["table"] == "Ua"
      assert meta["table_key"] == "k_one"
      assert meta["row_key_matches"]
      assert Locator.pin_level(:id_table_value, meta) == :row

      # The row-level claim's evidence is the ENTRY, and the entry's bytes must
      # carry the row's own key. The SITE's bytes do not and cannot: it is a
      # loop emitting `Row_${e}` (ruling 7 — the bytes must support the address).
      assert meta["table_entry"]["bytes"] == "k_one:`my-check`"
      [from, to] = meta["table_entry"]["byte_span"]
      assert Locator.bytes(h, {from, to}) == "k_one:`my-check`"
      assert String.contains?(meta["table_entry"]["bytes"], "k_one")
    end

    test "rung 4 — a SIBLING key pins the LOOP, not the row (MES-97 CR finding)" do
      # Two rows share one id, so the id literal occurs once and the row whose
      # own key is not the one that resolved has no row-naming address at all.
      js =
        "var Ua={k_one:`my-check`};for(let[e,t]of Object.entries(Ua)){this.checks.push({id:t,name:`Row_${e}`,status:`SUCCESS`})}"

      h = Locator.index(js)

      assert {:id_table_value, [site], meta} = Locator.resolve(h, "my-check", "Row_somethingelse")
      refute meta["row_key_matches"]

      # The rung is unchanged; what it PINS is not. This is the whole finding:
      # the level is a function of the rung AND the metadata.
      assert Locator.pin_level(:id_table_value, meta) == :loop

      # And the reason, on the bytes: the site does not contain this row's suffix.
      refute String.contains?(Locator.bytes(h, Locator.excerpt(h, site)), "somethingelse")
    end

    test "rung 5 — the id does not occur and its literal prefix heads a template" do
      h = Locator.index("await a(`my-check-${t}`,`MyCheck${t}`,`desc`,()=>({}))")

      assert {:id_template_prefix, [_], %{"literal_prefix" => "my-check"}} =
               Locator.resolve(h, "my-check-ping", "MyCheckping")
    end

    test "unresolved is RETURNED, never guessed at" do
      h = Locator.index("let x = 1; // nothing here names a check")
      assert {:unresolved, [], %{}} = Locator.resolve(h, "my-check", "MyCheck")
    end
  end

  # MES-97 CR finding: `rung_pins` said ROW for six rows whose own metadata said
  # the address that resolved them names a sibling. The level is a function of
  # the rung AND its metadata, and these units hold it to that.
  describe "pin_level/2 — what a resolution actually addresses" do
    test "each rung's level, including the one that depends on the metadata" do
      assert Locator.pin_level(:id_literal_pair, %{}) == :row
      assert Locator.pin_level(:id_literal_site, %{}) == :check
      assert Locator.pin_level(:id_bound_variable, %{"binding" => "Za"}) == :check
      assert Locator.pin_level(:id_table_value, %{"row_key_matches" => true}) == :row
      assert Locator.pin_level(:id_table_value, %{"row_key_matches" => false}) == :loop
      assert Locator.pin_level(:id_template_prefix, %{}) == :loop
      assert Locator.pin_level(:unresolved, %{}) == :none
    end

    test "the rung alone does not determine the level — the two id_table_value cases differ" do
      # Stated as its own unit because it is the property the first cut broke:
      # a `pins(rung)` keyed on the rung alone CANNOT express this and so was
      # wrong for six of the ten rows, in the direction that over-claims.
      refute Locator.pin_level(:id_table_value, %{"row_key_matches" => true}) ==
               Locator.pin_level(:id_table_value, %{"row_key_matches" => false})
    end

    test "absent metadata is not read as a row-level pin" do
      # Fail-closed: a metadata map that does not say the key matches is not a
      # map that says it does.
      assert Locator.pin_level(:id_table_value, %{}) == :loop
    end

    test "every rung the ladder declares has a level" do
      # Totality by set comparison, not by counting the clauses above.
      for rung <- Locator.ladder() ++ [:unresolved] do
        assert Locator.pin_level(rung, %{}) in [:row, :check, :loop, :none]
      end
    end
  end

  # The two hazards that made the ladder wrong on the real build before the
  # structural tests went in. Both are regressions waiting to happen, and both
  # fail TOWARD a conclusion — they return an answer rather than nothing.
  describe "the structural tests, which are what stop a grep failing toward its conclusion" do
    test "an ARRAY of check ids is not a call argument, however much it looks like one" do
      # `Ha=[`a`,`my-check`,`b`]` — the id is followed by ",`" exactly as a call
      # argument is. Reading it as an emitting site resolved a real check to its
      # own membership list.
      js = "var Ha=[`first-check`,`my-check`,`last-check`];"
      h = Locator.index(js)

      refute match?({:id_literal_pair, _, _}, Locator.resolve(h, "my-check", "MyCheck"))
      refute match?({:id_literal_site, _, _}, Locator.resolve(h, "my-check", "MyCheck"))
    end

    test "the same id IS a call argument when it is actually inside a call" do
      # The positive half: without this the test above would pass over a rule
      # that simply never resolved anything.
      js = "f(`roots`,`my-check`,`MyCheck`);"
      h = Locator.index(js)
      assert {:id_literal_pair, [_], %{}} = Locator.resolve(h, "my-check", "MyCheck")
    end

    test "a template prefix that is NOT at an emitting site does not resolve" do
      # The real failure: dropping segments until the grep hits reached the bare
      # prefix `sep`, in the harness's own scaffolding, 70 KB from any check.
      js = "function scaffold(e){return{check:`my-${e}-todo`}}"
      h = Locator.index(js)
      assert {:unresolved, [], %{}} = Locator.resolve(h, "my-check-ping", "MyCheckping")
    end

    test "and DOES resolve when the template head sits at an emitting site" do
      js =
        "function scaffold(e){return{check:`my-${e}-todo`}};a(`my-check-${t}`,`N${t}`,`d`,()=>({}))"

      h = Locator.index(js)

      assert {:id_template_prefix, [_], %{"literal_prefix" => "my-check"}} =
               Locator.resolve(h, "my-check-ping", "Nping")
    end
  end

  describe "the excerpt rule, in stated precedence" do
    test "a call form carries its callee, and stops at the matching close" do
      js = "x;await a(`my-check`,`MyCheck`,`d`,()=>({details:{a:(1)}}));y"
      h = Locator.index(js)
      {_, [site], _} = Locator.resolve(h, "my-check", "MyCheck")

      assert {from, to} = Locator.excerpt(h, site)
      cut = Locator.bytes(h, {from, to})
      assert String.starts_with?(cut, "a(`my-check`")
      assert String.ends_with?(cut, "}))")
    end

    test "a `getChecks(){` method beats the check object literal inside it" do
      # Precedence, not innermost-first: an object literal is PRODUCED by the
      # construct around it, and A3 cut the client-leg row at the method.
      js = "class S{getChecks(){let e=1;return[{id:`my-check`,name:`MyCheck`,status:`SUCCESS`}]}}"
      h = Locator.index(js)
      {_, [site], _} = Locator.resolve(h, "my-check", "MyCheck")

      cut = Locator.bytes(h, Locator.excerpt(h, site))
      assert String.starts_with?(cut, "getChecks(){")
      assert String.contains?(cut, "my-check")
    end

    test "a bare `{id:…}` object literal is the fallback when there is no producer" do
      js = "async run(e){let a={id:`my-check`,name:`MyCheck`,status:`SUCCESS`};return a}"
      h = Locator.index(js)
      {_, [site], _} = Locator.resolve(h, "my-check", "MyCheck")

      cut = Locator.bytes(h, Locator.excerpt(h, site))
      assert String.starts_with?(cut, "{id:`my-check`")
      assert String.ends_with?(cut, "}")
    end
  end

  describe "the scanner" do
    test "brackets inside strings and templates do not move the balance" do
      js = ~S|f(`my-check`,`MyCheck`,"a ( b { c", 'd ) e }', `g ) h`)|
      h = Locator.index(js)
      {_, [site], _} = Locator.resolve(h, "my-check", "MyCheck")

      cut = Locator.bytes(h, Locator.excerpt(h, site))
      assert String.ends_with?(cut, "`g ) h`)")
    end

    test "`${}` nesting inside a template is tracked" do
      js = "a(`my-check-${t?`x${y}`:`z`}`,`N${t}`,`d`,()=>({}))"
      h = Locator.index(js)
      assert {:id_template_prefix, [_], _} = Locator.resolve(h, "my-check-ping", "Nping")
    end

    test "char_offset undoes UTF-8, and a byte offset used as a char offset would be wrong" do
      h = Locator.index("ααα(`my-check`,`MyCheck`)")
      assert Locator.char_offset(h, 0) == 0
      # three two-byte characters: byte 6 is character 3.
      assert Locator.char_offset(h, 6) == 3
      refute Locator.char_offset(h, 6) == 6
    end
  end

  describe "positive_control/2" do
    test "passes when the mechanical cut reproduces the recorded span AND bytes" do
      js = "x;await a(`my-check`,`MyCheck`,`d`,()=>({}));y"
      h = Locator.index(js)
      {from, to} = Locator.excerpt(h, hd(elem(Locator.resolve(h, "my-check", "MyCheck"), 1)))

      artefact = %{
        "checks" => [
          %{
            "key" => ["server", "s", "my-check", "MyCheck", "d", ""],
            "emitting_site" => %{"dist_byte_span" => [from, to]},
            "evaluator_excerpt" => Locator.bytes(h, {from, to})
          }
        ]
      }

      assert {:ok, 1} = Locator.positive_control(h, artefact)
    end

    test "fails when the recorded SPAN moves" do
      js = "x;await a(`my-check`,`MyCheck`,`d`,()=>({}));y"
      h = Locator.index(js)
      {from, to} = Locator.excerpt(h, hd(elem(Locator.resolve(h, "my-check", "MyCheck"), 1)))

      artefact = %{
        "checks" => [
          %{
            "key" => ["server", "s", "my-check", "MyCheck", "d", ""],
            "emitting_site" => %{"dist_byte_span" => [from + 1, to]},
            "evaluator_excerpt" => Locator.bytes(h, {from, to})
          }
        ]
      }

      assert {:error, [%{check_id: "my-check"}]} = Locator.positive_control(h, artefact)
    end

    test "fails when the recorded BYTES change and the span does not — the case a span-only compare misses" do
      js = "x;await a(`my-check`,`MyCheck`,`d`,()=>({}));y"
      h = Locator.index(js)
      {from, to} = Locator.excerpt(h, hd(elem(Locator.resolve(h, "my-check", "MyCheck"), 1)))

      artefact = %{
        "checks" => [
          %{
            "key" => ["server", "s", "my-check", "MyCheck", "d", ""],
            "emitting_site" => %{"dist_byte_span" => [from, to]},
            "evaluator_excerpt" => Locator.bytes(h, {from, to}) <> "!"
          }
        ]
      }

      assert {:error, [_]} = Locator.positive_control(h, artefact)
    end
  end

  # The committed artefact, checked for the properties it ASSERTS about itself.
  # No harness needed: it carries the bytes it cites, which is the whole reason
  # it carries them.
  describe "the committed oc-emitting-sites artefact" do
    setup do
      %{
        a: "docs/conformance/oc-emitting-sites-2026-07-28.json" |> File.read!() |> Jason.decode!()
      }
    end

    test "is 173 in-denominator rows and resolves every one", %{a: a} do
      assert a["totals"]["rows"] == 173
      assert length(a["rows"]) == 173
      assert a["totals"]["unresolved"] == 0
      assert a["totals"]["rows_with_no_site"] == 0
      refute Enum.any?(a["rows"], &(&1["rung"] == "unresolved"))
    end

    test "every row carries at least one site with a span AND the bytes at it", %{a: a} do
      for row <- a["rows"] do
        assert row["sites"] != [], row["check_id"]

        for site <- row["sites"] do
          assert [from, to] = site["byte_span"]
          assert is_binary(site["bytes"])
          assert byte_size(site["bytes"]) == to - from
          assert [_, _] = site["char_span"]
        end
      end
    end

    test "the ladder histogram sums to the row count and uses only declared rungs", %{a: a} do
      per = a["ladder"]["per_rung"]
      assert Enum.sum(Map.values(per)) == 173
      declared = Enum.map(Locator.ladder(), &Atom.to_string/1)
      assert Enum.all?(Map.keys(per), &(&1 in declared))
    end

    # S9-14: the artefact exists to keep three measurements apart, so the three
    # blocks must agree with the rows they are computed from.
    test "each of the three predicates agrees with the rows", %{a: a} do
      p = a["predicates"]
      rows = a["rows"]

      assert p["occurs_at_all"]["over_the_173_rows"]["no"] ==
               Enum.count(rows, &(&1["check_id_occurrences"] == 0))

      assert p["reached_by_a_bare_grep"]["over_the_173_rows"]["reaches"] ==
               Enum.count(rows, & &1["reached_by_bare_grep"])

      assert p["distinct_check_ids"]["over_the_173_rows"] ==
               rows |> Enum.map(& &1["check_id"]) |> Enum.uniq() |> length()
    end

    test "the three predicates return DIFFERENT numbers — which is why they are three", %{a: a} do
      p = a["predicates"]
      occurs = p["occurs_at_all"]["over_a3s_13_rows"]["no"]
      reach = p["reached_by_a_bare_grep"]["over_a3s_13_rows"]["does_not"]
      ids = p["distinct_check_ids"]["over_a3s_13_rows"]

      # The S9-14 correction, as an assertion rather than a paragraph: the "6"
      # is reach-the-site over ROWS, and occur-at-all is 5 over DISTINCT IDS.
      assert reach == 6
      assert occurs == 5
      assert ids == 11
      refute occurs == reach
    end

    test "`reached_by_bare_grep` is exactly the first two rungs, and nothing else", %{a: a} do
      for row <- a["rows"] do
        assert row["reached_by_bare_grep"] ==
                 row["rung"] in ["id_literal_pair", "id_literal_site"]
      end
    end

    test "a row that reaches by a bare grep has a NON-ZERO occurrence count", %{a: a} do
      # The converse does not hold and must not be asserted: 22 rows occur and
      # do not reach. That asymmetry is the whole finding.
      reaching = Enum.filter(a["rows"], & &1["reached_by_bare_grep"])
      assert Enum.all?(reaching, &(&1["check_id_occurrences"] > 0))

      assert Enum.count(
               a["rows"],
               &(&1["check_id_occurrences"] > 0 and not &1["reached_by_bare_grep"])
             ) == 22
    end

    # --- the pin levels, which is where the first cut of this artefact lied ---

    test "NO row claims a row-level pin while its own metadata refutes one", %{a: a} do
      # The invariant the generator refuses on, asserted here too so a gate-5
      # run catches it without the harness. This is the exact state CR found.
      mispinned =
        Enum.filter(a["rows"], fn r ->
          r["rung_pin_level"] == "row" and Map.get(r["rung_detail"], "row_key_matches") == false
        end)

      assert mispinned == [],
             "row-level claims with row_key_matches == false: " <>
               Enum.map_join(mispinned, ", ", & &1["name"])
    end

    test "each row's recorded level is the one pin_level/2 computes for it", %{a: a} do
      for row <- a["rows"] do
        rung = String.to_existing_atom(row["rung"])

        assert row["rung_pin_level"] == to_string(Locator.pin_level(rung, row["rung_detail"])),
               row["name"]
      end
    end

    test "the six sibling-keyed table rows are recorded at LOOP, and are six", %{a: a} do
      table = Enum.filter(a["rows"], &(&1["rung"] == "id_table_value"))
      {row_level, loop_level} = Enum.split_with(table, &(&1["rung_pin_level"] == "row"))

      assert length(table) == 10
      assert length(row_level) == 4
      assert length(loop_level) == 6
      assert Enum.all?(loop_level, &(&1["rung_detail"]["row_key_matches"] == false))
      assert Enum.all?(row_level, & &1["rung_detail"]["row_key_matches"])

      # And the coarser level is not a drop: every one still has its site.
      assert Enum.all?(loop_level, &(&1["sites"] != []))
    end

    test "a row-level table pin carries the ENTRY's bytes, and they name the row", %{a: a} do
      # Ruling 7 on the row-level claim specifically: the SITE's bytes are the
      # loop's and name no row, so the row-level claim rests on the entry.
      for row <- a["rows"],
          row["rung"] == "id_table_value",
          row["rung_pin_level"] == "row" do
        entry = row["rung_detail"]["table_entry"]
        [from, to] = entry["byte_span"]
        assert byte_size(entry["bytes"]) == to - from
        assert String.contains?(entry["bytes"], row["rung_detail"]["table_key"])
        assert String.contains?(entry["bytes"], row["check_id"])
        assert String.ends_with?(row["name"], row["rung_detail"]["table_key"])

        # The negative half: the emitting site does NOT name this row. Without
        # it, "the entry names the row" would not show why the entry is needed.
        refute Enum.any?(
                 row["sites"],
                 &String.contains?(&1["bytes"], row["rung_detail"]["table_key"])
               )
      end
    end

    test "the pin-level histogram agrees with the rows and sums to 173", %{a: a} do
      per = a["ladder"]["per_pin_level"]
      assert Enum.sum(Map.values(per)) == 173
      assert per == Enum.frequencies_by(a["rows"], & &1["rung_pin_level"])
      assert Map.keys(per) -- ["row", "check", "loop", "none"] == []
    end

    test "counting row-level pins BY RUNG would over-state it by exactly 6", %{a: a} do
      by_rung = Enum.count(a["rows"], &(&1["rung"] in ["id_literal_pair", "id_table_value"]))
      by_level = Enum.count(a["rows"], &(&1["rung_pin_level"] == "row"))
      assert by_rung - by_level == 6
    end
  end
end

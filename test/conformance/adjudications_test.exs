defmodule MCP.Conformance.AdjudicationsTest do
  @moduledoc """
  **Guard 32 in gate 5**: the committed adjudication records audit clean
  against their views, the walk root is pinned, and the decision logic is
  tested unit by unit.

  The first describe block runs `Adjudications.audit/1` over the REAL tree.
  Everything after it drives `audit/1` over small synthetic inputs, because the
  real tree can only exhibit the cases it happens to contain. The end-to-end
  plants against the real record are in
  `conformance/controls/adjudications_controls.exs`.

  It moves the suite's unit population, which dirties condition (b) of the
  end-of-sprint boundary-liveness skip. Declared, not hidden.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.Adjudications, as: A

  @d4a "docs/conformance/adjudications/adjudication-D4a-2026-07-28.json"
  @d4b "docs/conformance/adjudications/adjudication-D4b-2026-07-28.json"
  @v4b "docs/conformance/buckets/bucket-4b-2026-07-28.json"
  @d2b "docs/conformance/adjudications/adjudication-D2b-2026-07-28.json"
  @v2b "docs/conformance/buckets/bucket-2b-2026-07-28.json"
  @v5b "docs/conformance/buckets/bucket-5b-2026-07-28.json"
  @d2ai "docs/conformance/adjudications/adjudication-D2a-i-2026-07-28.json"
  @v2a "docs/conformance/buckets/bucket-2a-2026-07-28.json"
  # D2a-i's slice of bucket 2a, pinned literally (MES-129 brief: gate 5 pins the
  # selector and requires the section to EQUAL its result, both ways).
  @d2ai_selector %{"field" => "tag", "segment" => 1, "starts_with" => "input-required-result-"}
  @ves "docs/conformance/buckets/escalated-2026-07-28.json"
  @locator "docs/conformance/oc-emitting-sites-2026-07-28.json"
  @in_scope "docs/conformance/in-scope-2026-07-28.json"
  # The predicate bucket 2b's population sentence must be, verbatim (MES-111
  # point 1; the anchor is etcc-register.md §12, cited in the D2b record).
  @population_sentence "OC check with no ET-CC member match"
  @crosswalk "docs/conformance/crosswalk-2026-07-28.json"

  setup_all do
    inputs = A.load()
    %{inputs: inputs, result: A.audit(inputs)}
  end

  describe "the committed tree" do
    test "audits clean", %{result: %{defects: defects}} do
      assert defects == [], Enum.map_join(defects, "\n", &A.format_defect/1)
    end

    # PM condition on MES-126 (29406): the walk root is PINNED, so a narrowed
    # walk cannot pass silently over records it no longer sees.
    test "the walk root is docs/conformance/adjudications/*.json" do
      assert A.walk_root() == {"docs/conformance/adjudications", "*.json"}
    end

    # The universe is read independently of the guard's own walk, so a walk that
    # drops a file differs from it.
    test "the walk visits every .json in the directory, read independently",
         %{inputs: inputs, result: %{report: r}} do
      independent =
        case File.ls("docs/conformance/adjudications") do
          {:ok, names} ->
            names
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.map(&("docs/conformance/adjudications/" <> &1))
            |> Enum.sort()

          {:error, :enoent} ->
            []
        end

      assert inputs.walk == independent
      assert r["records_visited"] == length(independent)
    end

    test "once any record is visited, rows are visited too", %{result: %{report: r}} do
      if r["records_visited"] > 0, do: assert(r["rows_visited"] > 0)
    end

    test "D4a's record closes bucket 4a and the escalated view", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4a]

      assert for(s <- record["sections"], do: {s["view"], s["closure"]}) == [
               {"docs/conformance/buckets/bucket-4a-2026-07-28.json", "closed"},
               {"docs/conformance/buckets/escalated-2026-07-28.json", "closed"}
             ]
    end

    test "D4b's record closes bucket 4b", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]

      assert for(s <- record["sections"], do: {s["view"], s["closure"], s["owner"]}) == [
               {@v4b, "closed", "MES-127"}
             ]
    end

    # PM ratification on MES-127 (29430, Q1): extend_test where the unit reaches
    # the HTTP seam (StreamableHTTPStatelessTest), accept_bound below it.
    test "D4b's dispositions are the ratified ones, per edge", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]
      [%{"rows" => rows}] = record["sections"]

      by_module =
        rows
        |> Enum.map(&{&1["member"] |> String.split("/") |> hd(), &1["disposition"]})
        |> Enum.frequencies()

      assert by_module == %{
               {"MCP.Transport.StreamableHTTPStatelessTest", "extend_test"} => 2,
               {"MCP.Server.DispatchTest", "accept_bound"} => 2,
               {"MCP.Server.SubscriptionsDispatchTest", "accept_bound"} => 2
             }
    end

    # PM ratification on MES-127 (29430, Q4): R2 is REFERENCED, not re-routed.
    # Every D4b row points at a real D4a row that routes R2 as fix_sdk.
    test "each D4b row's R2 pointer resolves to D4a's fix_sdk row", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]
      [%{"rows" => rows}] = record["sections"]

      for r <- rows do
        ptr = r["root_cause"]["adjudicated_at"]
        assert r["root_cause"]["id"] == "R2"
        assert r["disposition"] != "fix_sdk"
        {:ok, target} = inputs.records[ptr["record"]]

        [hit] =
          for s <- target["sections"],
              s["view"] == ptr["view"],
              t <- s["rows"],
              A.key(t) == [ptr["member"], ptr["claim"], ptr["tag"]],
              do: t

        assert hit["disposition"] == "fix_sdk" and hit["disposition"] == ptr["disposition_there"]
        assert hit["root_cause"]["id"] == "R2"
      end
    end

    # PM ratification on MES-127 (29430, Q3): the standing (red, green, :full)
    # escalation, divergent_despite_agreement, is a record NEGATIVE. G32 does not
    # check it, so gate 5 RECOMPUTES it from the crosswalk: recorded == measured.
    test "D4b's divergent_despite_agreement zero is measured, not held", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]
      [neg] = Enum.filter(record["negatives"], &(&1["id"] == "divergent_despite_agreement"))
      crosswalk = @crosswalk |> File.read!() |> Jason.decode!()

      matching =
        Enum.count(crosswalk["cells"], fn c ->
          c["verdicts"]["oc"] == "red" and c["verdicts"]["et"] == "green" and c["shape"] == "full"
        end)

      escalated =
        Enum.count(
          crosswalk["escalations"]["rows"],
          &String.contains?(&1["escalation"], "divergent_despite_agreement")
        )

      assert neg["count"] == %{
               "cells_matching" => matching,
               "cells_in_universe" => length(crosswalk["cells"]),
               "escalation_rows_with_this_reason" => escalated
             }
    end

    test "D2b's record closes bucket 2b", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2b]

      assert for(s <- record["sections"], do: {s["view"], s["closure"], s["owner"]}) == [
               {@v2b, "closed", "MES-128"}
             ]
    end

    # PM ratification on MES-128 (29444, Q1): per check, the disposition and the
    # level the missing test would be built at.
    test "D2b's dispositions and build levels are the ratified ones, per check",
         %{inputs: inputs} do
      by_check =
        for r <- d2b_rows(inputs), into: %{} do
          {r["tag"] |> String.split("/") |> List.last(), {r["disposition"], r["build_level"]}}
        end

      nine =
        for c <- ~w(colon_in_name control_char_name non_ascii_name space_in_name empty_header
                    array_header null_header duplicate_diff_case duplicate_same_case),
            into: %{},
            do: {"ClientRejectsInvalidTool_invalid_" <> c, {"extend_to_match", "mock_transport"}}

      assert by_check ==
               Map.merge(nine, %{
                 "ClientMcpMethodHeader_prompts_get" => {"extend_to_match", "live_http"},
                 "ClientMcpMethodHeader_resources_read" => {"extend_to_match", "live_http"},
                 "ClientDeclaresElicitationCapability" => {"build_test", "pure_unit"},
                 "MRTRClientJsonRpcIdDifferent" => {"extend_to_match", "mock_transport"},
                 "MRTRClientParallelIsolation" => {"build_test", "mock_transport"},
                 "DefaultResultTypeComplete" => {"build_test", "mock_transport"}
               })
    end

    # PM ratification on MES-128 (29444, Q2 (b)): the substitute echo. G32's
    # citation_drift holds the bytes; this holds what they SAY: the cited name is
    # the row's check and its status at the accepted run was SUCCESS. It guards
    # the adjudication's premise, not the view (the record says so).
    test "each D2b row cites its own check as SUCCESS at the accepted run", %{inputs: inputs} do
      rows = d2b_rows(inputs)
      assert rows != []

      for r <- rows do
        c = r["oc_status_at_accepted_run"]
        assert c["file"] == @in_scope
        assert A.verify(c, inputs.source_fun) == :ok
        name = r["tag"] |> String.split("/") |> List.last()

        assert Regex.run(~r/"name": "([^"]+)",\s*"status": "([A-Z]+)"/, c["bytes"],
                 capture: :all_but_first
               ) == [name, "SUCCESS"],
               name
      end
    end

    test "the D2b substitute-echo pin refuses another check's line and a non-SUCCESS status",
         %{inputs: inputs} do
      [r1, r2 | _] = d2b_rows(inputs)
      swapped = Map.put(r1, "oc_status_at_accepted_run", r2["oc_status_at_accepted_run"])
      name = r1["tag"] |> String.split("/") |> List.last()
      [cited, _] = status_echo(swapped)
      refute cited == name

      failed =
        update_in(
          r1,
          ["oc_status_at_accepted_run", "bytes"],
          &String.replace(&1, "SUCCESS", "FAILURE")
        )

      assert status_echo(failed) == [name, "FAILURE"]
    end

    # MES-111 point 1, owned by MES-128: bucket 2b's population sentence is the
    # predicate verbatim, and the record never renders a check here as lacking a
    # test (a check may be covered outside ET-CC). Quoted `bytes` are exempt:
    # they are other files' text, and the anchor itself quotes the rule.
    test "rendering guard: D2b's and D2a-i's population sentences are the predicate verbatim",
         %{inputs: inputs} do
      for f <- [@d2b, @d2ai] do
        {:ok, record} = inputs.records[f]
        assert rendering_defects(record) == [], f
        assert A.verify(record["rendering_guard"]["anchor"], inputs.source_fun) == :ok
        assert record["rendering_guard"]["anchor"]["bytes"] =~ @population_sentence
      end
    end

    test "rendering guard: goes red on 'untested', and on a paraphrase", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2b]

      at = fn rec, sentence ->
        put_in(rec, ["sections", Access.at(0), "population_sentence"], sentence)
      end

      assert rendering_defects(at.(record, "OC check with no ET-CC member match (untested)")) !=
               []

      assert rendering_defects(at.(record, "Untested OC checks")) != []
      assert rendering_defects(at.(record, "OC checks with no ET-CC test")) != []

      prose = put_in(record, ["what_bucket_2b_is"], "These checks are UNTESTED.")
      assert rendering_defects(prose) != []

      quoted = put_in(record, ["rendering_guard", "anchor", "bytes"], "never \"untested\"")
      assert rendering_defects(quoted) == []
    end

    # A2d: the matched client checks reconcile with 5b and the escalations, by
    # arithmetic AND by set comparison, over a universe read from the locator,
    # not from the 2b view. recorded == measured.
    test "D2b's client-universe negative is measured, not held", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2b]
      [neg] = Enum.filter(record["negatives"], &(&1["id"] == "client_universe_reconciles"))

      universe =
        for r <- json(@locator)["rows"], r["leg"] == "client", do: r["token"]

      cells = for c <- json(@crosswalk)["cells"], client?(c["tag"]), do: c["tag"]
      matched = MapSet.new(cells)
      in_2b = for r <- json(@v2b)["rows"], do: r["tag"]
      rows_5b = for r <- json(@v5b)["rows"], do: r["tag"]
      esc = for r <- json(@ves)["rows"], client?(r["tag"]), do: r["tag"]
      set_2b = MapSet.new(in_2b)
      set_5b = MapSet.new(rows_5b)
      set_u = MapSet.new(universe)

      assert length(universe) == MapSet.size(set_u)

      assert neg["count"] == %{
               "client_universe" => length(universe),
               "bucket_2b" => length(in_2b),
               "matched_client_checks" => MapSet.size(matched),
               "client_cells" => length(cells),
               "bucket_5b_rows" => length(rows_5b),
               "bucket_5b_distinct_checks" => MapSet.size(set_5b),
               "escalated_client_rows" => length(esc),
               "escalated_client_checks" => esc |> MapSet.new() |> MapSet.size()
             }

      relations = %{
        "bucket_2b_and_matched_disjoint" => MapSet.disjoint?(set_2b, matched),
        "bucket_2b_union_matched_equals_universe" => MapSet.union(set_2b, matched) == set_u,
        "matched_equals_bucket_5b_checks" => matched == set_5b,
        "escalated_client_checks_within_bucket_5b" => MapSet.subset?(MapSet.new(esc), set_5b)
      }

      assert neg["set_relations"] == relations
      assert Enum.all?(Map.values(relations))
      assert length(rows_5b) + length(esc) == length(cells)
      assert length(in_2b) + MapSet.size(matched) == length(universe)
    end

    # The two MRTR negatives' universe: every resolver-configured unit under
    # test/. A new one moves this and forces the negatives to be re-examined.
    test "D2b's MRTR negatives' universe is measured, by file", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2b]

      [neg] =
        Enum.filter(
          record["negatives"],
          &(&1["id"] == "no_unit_runs_a_concurrent_call_beside_an_mrtr_flow")
        )

      # Built, not written, so this file does not count itself.
      needle = "on_input_required" <> ":"

      measured =
        for f <- Path.wildcard("test/**/*.exs"),
            n = f |> File.read!() |> String.split(needle) |> length() |> Kernel.-(1),
            n > 0,
            into: %{},
            do: {f, n}

      assert neg["universe_by_file"] == measured
      assert length(neg["units"]) == measured |> Map.values() |> Enum.sum()
    end

    # --- D2a-i (MES-129): the MRTR slice of bucket 2a, an OPEN section ---

    test "D2a-i's record holds one OPEN section on bucket 2a, owned by MES-130", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2ai]

      assert for(s <- record["sections"], do: {s["view"], s["closure"], s["owner"]}) == [
               {@v2a, "open", "MES-130"}
             ]
    end

    # The brief: the slice is declared by a selector over the view, so the
    # D2a-i / D2a-ii partition is checkable and not hand-listed. G32 cannot see
    # a selector; this holds it, both ways.
    test "D2a-i's selector is the pinned one, and its rows EQUAL the selector's result",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2ai]
      assert Map.take(record["selector"], ~w(field segment starts_with)) == @d2ai_selector
      assert selector_equality(d2ai_rows(inputs), json(@v2a)["rows"]) == :ok
    end

    test "the selector equality refuses a non-MRTR 2a row and a dropped MRTR row",
         %{inputs: inputs} do
      rows = d2ai_rows(inputs)
      view_rows = json(@v2a)["rows"]
      [other | _] = Enum.reject(view_rows, &(&1 in selected(view_rows, @d2ai_selector)))
      planted = rows ++ [%{"member" => nil, "claim" => nil, "tag" => other["tag"]}]

      assert {:error, {:rows_differ, [[nil, nil, tag]], []}} =
               selector_equality(planted, view_rows)

      assert tag == other["tag"]
      refute String.starts_with?(Enum.at(String.split(tag, "/"), 1), "input-required-result-")

      [first | rest] = rows
      assert {:error, {:rows_differ, [], [dropped]}} = selector_equality(rest, view_rows)
      assert dropped == A.key(first)
    end

    # PM ratification on MES-129 (29460, Q1 and Q3): per check, the disposition
    # and the level.
    test "D2a-i's dispositions and build levels are the ratified ones, per check",
         %{inputs: inputs} do
      by_check =
        for r <- d2ai_rows(inputs), into: %{} do
          [_, scenario, _, name] = String.split(r["tag"], "/")
          {{scenario, name}, {r["disposition"], r["build_level"]}}
        end

      ir = &("input-required-result-" <> &1)
      extend = {"extend_to_match", "plug"}
      blocked = {"blocked_on_sdk_gap", "plug"}

      green_wsv =
        for s <- ~w(basic-elicitation basic-list-roots basic-sampling capability-check
                    ignore-extra-params missing-input-response multi-round
                    multiple-input-requests result-type tampered-state
                    unsupported-methods validate-input),
            into: %{},
            do: {{ir.(s), "WireSchemaValid"}, extend}

      assert by_check ==
               Map.merge(green_wsv, %{
                 {ir.("basic-elicitation"), "InputRequiredResultElicitationIncomplete"} => extend,
                 {ir.("basic-elicitation"), "InputRequiredResultElicitationComplete"} => extend,
                 {ir.("basic-sampling"), "InputRequiredResultSamplingIncomplete"} => extend,
                 {ir.("basic-sampling"), "InputRequiredResultSamplingComplete"} => extend,
                 {ir.("basic-list-roots"), "InputRequiredResultListRootsIncomplete"} => extend,
                 {ir.("basic-list-roots"), "InputRequiredResultListRootsComplete"} => extend,
                 {ir.("multiple-input-requests"), "InputRequiredResultMultipleInputsIncomplete"} =>
                   extend,
                 {ir.("multiple-input-requests"), "InputRequiredResultMultipleInputsComplete"} =>
                   extend,
                 {ir.("multi-round"), "InputRequiredResultMultiRoundR2"} => extend,
                 {ir.("multi-round"), "InputRequiredResultMultiRoundR3"} => extend,
                 {ir.("capability-check"), "RespectClientCapabilities"} => extend,
                 {ir.("unsupported-methods"), "NotOnUnsupportedRequests"} =>
                   {"extend_to_match", "pure_unit"},
                 {ir.("non-tool-request"), "InputRequiredResultNonToolIncomplete"} => blocked,
                 {ir.("non-tool-request"), "WireSchemaValid"} => blocked,
                 {ir.("tampered-state"), "RejectTamperedState"} => blocked,
                 {ir.("missing-input-response"), "InputRequiredResultMissingResponseRerequests"} =>
                   blocked,
                 {ir.("validate-input"), "ValidateInputResponses"} => blocked,
                 {ir.("validate-input"), "ErrorOnProtocolError"} => blocked
               })
    end

    # The substitute echo, as D2b's, with the window widened to the scenario line
    # because the name and status lines recur (WireSchemaValid, once per
    # scenario). The FAILURE rows are exactly the non-tool pair, both blocked.
    test "each D2a-i row cites its own check's status at the accepted run", %{inputs: inputs} do
      rows = d2ai_rows(inputs)
      assert length(rows) == 30

      statuses =
        for r <- rows do
          c = r["oc_status_at_accepted_run"]
          assert c["file"] == @in_scope
          assert A.verify(c, inputs.source_fun) == :ok
          [_, scenario, _, name] = String.split(r["tag"], "/")
          assert [^scenario, ^name, status] = census_echo(r), r["tag"]
          {scenario, name, status, r["disposition"]}
        end

      failed = for {s, n, "FAILURE", d} <- statuses, do: {s, n, d}

      assert Enum.sort(failed) == [
               {"input-required-result-non-tool-request", "InputRequiredResultNonToolIncomplete",
                "blocked_on_sdk_gap"},
               {"input-required-result-non-tool-request", "WireSchemaValid", "blocked_on_sdk_gap"}
             ]

      assert Enum.frequencies_by(statuses, &elem(&1, 2)) == %{"SUCCESS" => 28, "FAILURE" => 2}
    end

    test "the D2a-i status pin refuses another scenario's window and a changed status",
         %{inputs: inputs} do
      rows = d2ai_rows(inputs)
      wsv = Enum.filter(rows, &String.ends_with?(&1["tag"], "/WireSchemaValid"))
      [w1, w2 | _] = wsv
      swapped = Map.put(w1, "oc_status_at_accepted_run", w2["oc_status_at_accepted_run"])
      [scenario, "WireSchemaValid", _] = census_echo(swapped)
      refute scenario == Enum.at(String.split(w1["tag"], "/"), 1)

      flipped =
        update_in(
          w1,
          ["oc_status_at_accepted_run", "bytes"],
          &String.replace(&1, "SUCCESS", "FAILURE")
        )

      assert [_, _, "FAILURE"] = census_echo(flipped)
    end

    # PM ratification on MES-129 (29460, Q2): why_green is REQUIRED where the
    # status is SUCCESS and the disposition is blocked_on_sdk_gap.
    test "why_green is present, and holds its bytes, on every SUCCESS blocked row",
         %{inputs: inputs} do
      owed = Enum.filter(d2ai_rows(inputs), &why_green_owed?/1)

      assert owed |> Enum.map(&(&1["tag"] |> String.split("/") |> List.last())) |> Enum.sort() ==
               ~w(ErrorOnProtocolError InputRequiredResultMissingResponseRerequests RejectTamperedState ValidateInputResponses)

      assert why_green_defects(d2ai_rows(inputs), inputs.source_fun) == []
    end

    test "the why_green pin refuses a SUCCESS blocked row without it", %{inputs: inputs} do
      rows = d2ai_rows(inputs)
      [r | _] = Enum.filter(rows, &why_green_owed?/1)
      planted = Enum.map(rows, &if(&1 == r, do: Map.delete(&1, "why_green"), else: &1))
      assert why_green_defects(planted, inputs.source_fun) == [r["tag"]]
    end

    # PM ruling on MES-129 (29468, B1, superseding 29460's set): every row
    # whose remedy cannot land until D4a's inputRequests object-shape fix lands
    # points at D4a's ONE fix_sdk row, by its derived key, so the fix is counted
    # once. Every row that does not carry it has its reading recorded, so the
    # criterion and the set are held against each other in both directions.
    test "each D2a-i depends_on_fix resolves to D4a's fix_sdk row, on exactly the pinned rows",
         %{inputs: inputs} do
      rows = d2ai_rows(inputs)
      {carrying, rest} = Enum.split_with(rows, &Map.has_key?(&1, "depends_on_fix"))
      name = &(&1["tag"] |> String.split("/") |> List.last())

      names = carrying |> Enum.map(name) |> Enum.frequencies()

      assert names == %{
               "WireSchemaValid" => 13,
               "InputRequiredResultElicitationIncomplete" => 1,
               "InputRequiredResultElicitationComplete" => 1,
               "InputRequiredResultMultiRoundR2" => 1,
               "InputRequiredResultMultiRoundR3" => 1,
               "RejectTamperedState" => 1,
               "InputRequiredResultSamplingIncomplete" => 1,
               "InputRequiredResultSamplingComplete" => 1,
               "InputRequiredResultListRootsIncomplete" => 1,
               "InputRequiredResultListRootsComplete" => 1,
               "InputRequiredResultMultipleInputsIncomplete" => 1,
               "InputRequiredResultMultipleInputsComplete" => 1
             }

      {:ok, record} = inputs.records[@d2ai]
      not_carrying = record["depends_on_fix_statement"]["not_carrying"]
      assert rest |> Enum.map(name) |> Enum.sort() == not_carrying |> Map.keys() |> Enum.sort()
      assert Enum.all?(Map.values(not_carrying), &(is_binary(&1) and &1 != ""))

      for r <- carrying do
        ptr = r["depends_on_fix"]
        assert r["disposition"] != "fix_sdk"
        {:ok, target} = inputs.records[ptr["record"]]

        [hit] =
          for s <- target["sections"],
              s["view"] == ptr["view"],
              t <- s["rows"],
              A.key(t) == [ptr["member"], ptr["claim"], ptr["tag"]],
              do: t

        assert hit["disposition"] == "fix_sdk" and ptr["disposition_there"] == "fix_sdk"
        assert hit["root_cause"]["id"] == ptr["root_cause_there"]
      end
    end

    # PM ratification on MES-129 (29460, Q1, the tightening): each gap is owned
    # by MES-43 and cited in this tree by address and bytes.
    test "each blocked D2a-i row names MES-43 and cites its gap's record here", %{inputs: inputs} do
      for r <- d2ai_rows(inputs), r["disposition"] == "blocked_on_sdk_gap" do
        gap = r["sdk_gap"]
        assert gap["owner"] == "MES-43"
        assert gap["owner_record"] =~ ~r/^MES-43 (body|comment 29459)/
        assert A.verify(gap["record"], inputs.source_fun) == :ok

        assert gap["record"]["file"] in ~w(docs/sprint_4_issues.md conformance/request_state.ex)
      end
    end

    # CR findings B2 (29467) and B3 (29471) on MES-129, both accepted by the PM
    # (29468, 29472): the continuation-drop fix alone unblocks neither
    # ErrorOnProtocolError nor ValidateInputResponses, because MES-43 comment
    # 29464's validator covers a null AND a malformed inputResponses. Each row
    # names BOTH MES-43 records and its remedy states both preconditions.
    test "D2a-i's ErrorOnProtocolError and ValidateInputResponses name both MES-43 gaps",
         %{inputs: inputs} do
      suffixes = ["/ErrorOnProtocolError", "/ValidateInputResponses"]
      rows = for r <- d2ai_rows(inputs), String.ends_with?(r["tag"], suffixes), do: r
      assert length(rows) == length(suffixes)

      for r <- rows do
        assert r["sdk_gap"]["owner_record"] =~ "comment 29459"
        assert r["sdk_gap"]["owner_record"] =~ "comment 29464"
        assert r["remedy"] =~ "29459"
        assert r["remedy"] =~ "29464"
      end
    end

    # The closure rule (PM, MES-129 comment 29472): every landing condition a
    # remedy states is one of the records the row cites, and every cited record
    # is a condition the remedy states. lands_when is derived here from the
    # cited records alone, then held against the record's lands_when and against
    # the remedy's tokens, both ways.
    test "D2a-i's remedies state exactly the landing conditions their rows cite",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2ai]
      conds = record["landing_conditions"]["conditions"]
      rows = d2ai_rows(inputs)

      for r <- rows do
        derived =
          for {id, c} <- conds,
              (c["owner_record_phrase"] && r["sdk_gap"] &&
                 String.contains?(r["sdk_gap"]["owner_record"], c["owner_record_phrase"])) ||
                (id == "d4a_fix_sdk" and Map.has_key?(r, "depends_on_fix")),
              do: id

        assert r["lands_when"] == Enum.sort(derived), r["tag"]

        for {id, c} <- conds do
          assert String.contains?(r["remedy"], c["remedy_token"]) == id in r["lands_when"],
                 "#{r["tag"]}: #{id}"
        end
      end

      # The population the rule governs: every blocked row and every
      # depends_on_fix row, and no other.
      governed =
        for r <- rows,
            r["disposition"] == "blocked_on_sdk_gap" or Map.has_key?(r, "depends_on_fix"),
            do: r["tag"]

      assert Enum.sort(governed) == Enum.sort(for r <- rows, r["lands_when"] != [], do: r["tag"])

      # No condition in the catalog is dead.
      used = rows |> Enum.flat_map(& &1["lands_when"]) |> MapSet.new()
      assert used == MapSet.new(Map.keys(conds))
    end

    # CR finding B5 (29477) on MES-129, accepted by the PM (29478): the closure
    # unit above derives through the record's own catalogue, so the catalogue
    # is pinned here literally, as the selector is. A condition added to the
    # record, with rows and remedies to match, fails this pin until it is edited.
    test "D2a-i's landing-condition catalogue is exactly the pinned one", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2ai]

      pinned =
        for {id, c} <- record["landing_conditions"]["conditions"],
            into: %{},
            do: {id, {c["owner_record_phrase"], c["remedy_token"]}}

      assert pinned == %{
               "mes43_gap1" => {"'Gap 1 —", "(MES-43 body, Gap 1)"},
               "mes43_gap2" => {"'Gap 2 —", "(MES-43 body, Gap 2)"},
               "mes43_29459_first_bullet" =>
                 {"comment 29459, first bullet", "(MES-43 comment 29459, first bullet)"},
               "mes43_29464" => {"comment 29464", "(MES-43 comment 29464)"},
               "d4a_fix_sdk" => {nil, "depends_on_fix"}
             }
    end

    # CR finding B4 (29477) on MES-129 and PM ruling 29478, option (i): the
    # owning measurement attributes NonToolIncomplete to Gap 1 alone, and the
    # non-tool generic validator's remedy bypasses complete/1, so the overwrite
    # is its root_cause_record and not one of its landing conditions.
    test "D2a-i's non-tool pair lands on Gap 1, not on the resultType overwrite",
         %{inputs: inputs} do
      by_name = Map.new(d2ai_rows(inputs), &{&1["tag"], &1})
      ir = &"oc:server/input-required-result-non-tool-request/#{&1}"

      nt = by_name[ir.("sep-2322-non-tool-incomplete/InputRequiredResultNonToolIncomplete")]
      ws = by_name[ir.("wire-schema-valid/WireSchemaValid")]

      assert nt["lands_when"] == ["mes43_gap1"]
      assert ws["lands_when"] == ["d4a_fix_sdk", "mes43_gap1"]

      rcr = ws["root_cause"]["root_cause_record"]
      assert rcr["owner_record"] =~ "comment 29459, second bullet"
      assert A.verify(rcr["record"], inputs.source_fun) == :ok
      assert A.verify(rcr["code"], inputs.source_fun) == :ok
    end

    # The generic validator's rows are one validator repeated, reported apart
    # from the substantive ones, grouped by the emitting site the LOCATOR
    # records for each check.
    test "D2a-i's emitting-site grouping is measured from the locator", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2ai]
      tags = MapSet.new(d2ai_rows(inputs), & &1["tag"])
      sites = for r <- json(@locator)["rows"], r["token"] in tags, do: {r["token"], r["sites"]}
      assert length(sites) == MapSet.size(tags)

      {generic, substantive} =
        Enum.split_with(sites, fn {_, ss} ->
          Enum.map(ss, & &1["byte_span"]) == [[325_368, 325_721]]
        end)

      e = record["emitting_sites"]
      assert e["repeated_generic_validator"]["site_byte_span"] == [325_368, 325_721]
      assert e["repeated_generic_validator"]["rows"] == length(generic)
      assert Enum.all?(generic, fn {t, _} -> String.ends_with?(t, "/WireSchemaValid") end)
      assert e["substantive"]["rows"] == length(substantive)

      assert e["substantive"]["scenarios"] ==
               substantive
               |> Enum.map(fn {t, _} -> Enum.at(String.split(t, "/"), 1) end)
               |> Enum.uniq()
               |> length()
    end

    # A7: a green a null server also earns is not evidence. Recomputed from the
    # null-implementation control: a check passed the null run iff it is not
    # among the scenario's failed checks, the scenario's SUCCESS count is its
    # total less its failures, and it is the generic validator or the scenario
    # failed nothing (a check emitted only after another passes cannot be the
    # unnamed SUCCESS where that other failed).
    test "the D2a-i rows carrying null_passability are exactly those the null control passes",
         %{inputs: inputs} do
      null = json("docs/conformance/server-2026-07-28-null-control.json")["scenarios"]

      passed? = fn scenario, name ->
        [sc] =
          Enum.filter(null, &String.starts_with?(&1["artefact_dir"] || "", "server-#{scenario}-"))

        failed = for f <- sc["failed_checks"] || [], do: f["name"]
        c = sc["checks"]

        c["SUCCESS"] >= 1 and c["SUCCESS"] == c["total"] - length(failed) and name not in failed and
          (name == "WireSchemaValid" or failed == [])
      end

      rows = d2ai_rows(inputs)

      for r <- rows do
        [_, scenario, _, name] = String.split(r["tag"], "/")
        assert Map.has_key?(r, "null_passability") == passed?.(scenario, name), r["tag"]

        if c = get_in(r, ["null_passability", "null_control"]) do
          assert A.verify(c, inputs.source_fun) == :ok
          assert c["bytes"] =~ ~s("artefact_dir": "server-#{scenario}-)
        end
      end

      assert Enum.count(rows, &Map.has_key?(&1, "null_passability")) == 16
    end

    # A2d: the MRTR universe from the LOCATOR (not the 2a view) is this slice
    # and the checks carrying an edge, disjointly. recorded == measured.
    test "D2a-i's MRTR-universe negative is measured, not held", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2ai]
      [neg] = Enum.filter(record["negatives"], &(&1["id"] == "mrtr_universe_reconciles"))

      universe =
        for r <- json(@locator)["rows"],
            r["leg"] == "server",
            String.starts_with?(r["scenario"], "input-required-result-"),
            do: r["token"]

      slice = MapSet.new(d2ai_rows(inputs), & &1["tag"])

      edged =
        for c <- json(@crosswalk)["cells"], c["tag"] in universe, into: MapSet.new(), do: c["tag"]

      escalated =
        for r <- json(@ves)["rows"], r["tag"] in universe, into: MapSet.new(), do: r["tag"]

      set_u = MapSet.new(universe)
      assert length(universe) == MapSet.size(set_u)

      assert neg["count"] == %{
               "mrtr_universe" => length(universe),
               "slice" => MapSet.size(slice),
               "matched" => MapSet.size(edged),
               "matched_escalated" => MapSet.size(escalated)
             }

      relations = %{
        "slice_and_matched_disjoint" => MapSet.disjoint?(slice, edged),
        "slice_union_matched_equals_universe" => MapSet.union(slice, edged) == set_u
      }

      assert neg["set_relations"] == relations
      assert Enum.all?(Map.values(relations))
      assert MapSet.subset?(escalated, edged)
    end

    # The covered_elsewhere universe, recomputed from the register: every
    # non-ET-CC row whose test body touches MRTR. A new such unit moves this
    # and forces the "none" readings to be re-examined.
    test "D2a-i's covered-elsewhere universe is measured from the register", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2ai]
      [neg] = Enum.filter(record["negatives"], &(&1["id"] == "covered_elsewhere_universe"))
      assert neg["units"] == mrtr_non_etcc_units()
      assert neg["units"] != []

      for r <- d2ai_rows(inputs),
          u <- r["covered_elsewhere"]["units"] || [],
          do: assert(u["register_key"] in neg["units"])
    end

    # PM ratification on MES-129 (29460, condition (b)): the check the harness
    # emits only after the non-tool incomplete check passes is absent from the
    # population, and the record says so.
    test "InputRequiredResultNonToolComplete is in neither the locator nor bucket 2a",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2ai]

      assert Enum.any?(
               record["negatives"],
               &(&1["id"] == "non_tool_complete_is_not_in_the_population")
             )

      absent = "InputRequiredResultNonToolComplete"
      refute Enum.any?(json(@locator)["rows"], &(&1["name"] == absent))
      refute Enum.any?(json(@v2a)["rows"], &String.ends_with?(&1["tag"], "/" <> absent))
    end

    # MES-120's K1: a record under docs/conformance/ is inside G31, and a file
    # added after G31's baseline may carry no pending figure.
    for record <- [@d4a, @d4b, @d2b, @d2ai] do
      test "#{Path.basename(record)} is hand_authored to G31 and has no pending figure" do
        universe = "conformance/figures/universe.json" |> File.read!() |> Jason.decode!()
        ledger = "conformance/figures/ledger.json" |> File.read!() |> Jason.decode!()

        assert universe["files"][unquote(record)] == "hand_authored"
        assert Enum.filter(ledger["pending"], &(&1["file"] == unquote(record))) == []

        assert Enum.any?(
                 ledger["entries"],
                 &(&1["file"] == unquote(record) and &1["class"] == "measured")
               )
      end
    end

    # G32 verifies the citations inside SECTIONS. A record's top-level
    # citations (D4a's decision_row, D4b's a3_ruling) are held here instead.
    test "every repository citation outside a record's sections holds its bytes",
         %{inputs: inputs} do
      found =
        for {file, {:ok, doc}} <- inputs.records,
            c <- A.collect(Map.delete(doc, "sections")),
            do: {file, c}

      assert found != []

      for {file, c} <- found,
          do: assert(A.verify(c, inputs.source_fun) == :ok, "#{file}: #{inspect(c["file"])}")
    end

    # A partial answer to MES-135's K1 (G32 binds a row's KEY, not its content).
    # This ties each row's et_test to the row's member: the cited window lies
    # inside the member's own test in the member's own module. It does NOT tie
    # the check citation to the tag.
    #
    # Scoped to rows with a member (PM ratification on MES-128, 29444, Q3): a
    # bucket-2 row has no member and no et_test. The pin after it holds the
    # scoping: the rows it skips are EXACTLY bucket 2b's and, since MES-129, the
    # rows of bucket 2a that D2a-i's selector admits, each in its own record, so
    # no bucket-4 row can be skipped silently.
    test "every row's et_test lies inside the member's own test", %{inputs: inputs} do
      {owned, _skipped} = ownership_split(inputs.records)
      assert owned != []

      for {_, _, r} <- owned,
          do: assert(et_test_owner(r, inputs.source_fun) == :ok, inspect(A.key(r)))
    end

    test "the rows the ownership check skips are exactly bucket 2b's and D2a-i's slice, each in its own record",
         %{inputs: inputs} do
      assert skip_pin(inputs.records) == :ok
    end

    test "the skip pin refuses a member-less row planted into D4a's section", %{inputs: inputs} do
      planted =
        update_in(inputs.records[@d4a], fn {:ok, doc} ->
          {:ok,
           update_in(doc, ["sections", Access.at(0), "rows"], fn [r | _] = rows ->
             rows ++ [Map.put(r, "member", nil)]
           end)}
        end)

      assert {:error, {:skipped_rows_differ, extra, []}} = skip_pin(planted.records)
      assert [{@d4a, _, [nil | _]}] = extra
    end

    # The ownership check above supersedes this one (it requires the window to
    # lie inside the member's own test, compared by equality on the qualified
    # name). Kept as the literal form of the ratified wording, D4b only; its
    # `ends_with?` is a suffix match, not equality (CR N1).
    test "every D4b row's et_test quotes the member's test line itself", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]
      [%{"rows" => rows}] = record["sections"]

      for r <- rows do
        [_, name] = Regex.run(~r/^\s*test "((?:[^"\\]|\\.)*)"/m, r["et_test"]["bytes"])
        assert String.ends_with?(r["member"], name)
      end
    end

    test "the et_test self-check refuses a row whose member is a sibling test",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]
      [%{"rows" => [r1, _, r3 | _]}] = record["sections"]

      assert et_test_owner(r1, inputs.source_fun) == :ok
      swapped = Map.put(r1, "member", r3["member"])
      assert {:error, _} = et_test_owner(swapped, inputs.source_fun)
      renamed = Map.update!(r1, "member", &(&1 <> " (renamed)"))
      assert {:error, _} = et_test_owner(renamed, inputs.source_fun)
    end

    # CR's P5 probe (MES-127 review 29435, B1): a window past the owning test's
    # `end` quotes no test code, and was admitted as the preceding test before
    # the self-check found the test's own closing line.
    test "the et_test self-check refuses a window past the owning test's end",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]
      [%{"rows" => [r1, _, r3 | _]}] = record["sections"]

      for {r, file, [from, to]} <- [
            {r1, "test/mcp/transport/streamable_http_stateless_test.exs", [92, 96]},
            {r3, "test/mcp/server/dispatch_test.exs", [96, 98]}
          ] do
        {:ok, src} = inputs.source_fun.(file)
        bytes = src |> String.split("\n") |> Enum.slice((from - 1)..(to - 1)) |> Enum.join("\n")
        refute bytes =~ ~r/^\s*test "/m
        plant = put_in(r, ["et_test"], %{"file" => file, "lines" => [from, to], "bytes" => bytes})

        assert {:error, {:window_outside_test, last}} = et_test_owner(plant, inputs.source_fun)
        assert last < to
      end
    end

    test "the et_test self-check refuses a window straddling two tests", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]
      [%{"rows" => [r1 | _]}] = record["sections"]
      plant = put_in(r1, ["et_test", "lines"], [88, 100])

      assert et_test_owner(plant, inputs.source_fun) == {:error, :window_crosses_a_test}
    end

    test "the et_test self-check ends a nested test at its own `end`, a one-line test at its line" do
      src = """
      defmodule M do
        describe "d" do
          test "block" do
            fn -> :x end
          end
        end

        test "one", do: assert(true)
        @tag :x
      end
      """

      source_fun = fn "test/src.exs" -> {:ok, src} end

      at = fn member, lines ->
        et_test_owner(
          %{
            "member" => "M/" <> member,
            "et_test" => %{"file" => "test/src.exs", "lines" => lines}
          },
          source_fun
        )
      end

      assert at.("test d block", [4, 5]) == :ok
      assert at.("test d block", [4, 6]) == {:error, {:window_outside_test, 5}}
      assert at.("test one", [8, 8]) == :ok
      assert at.("test one", [8, 9]) == {:error, {:window_outside_test, 8}}
    end

    # MES-126 ratified the first five; MES-127 (29430, Q1) added extend_test and
    # accept_bound; MES-128 (29444, Q1) added extend_to_match and build_test;
    # MES-129 (29460, Q1) added blocked_on_sdk_gap.
    test "the closed disposition set is the one MES-126, MES-127, MES-128 and MES-129 ratified" do
      assert A.dispositions() ==
               ~w(fix_sdk fix_conformance_adapter keep_design_publish_bound po_decision_required suite_defect_upstream extend_test accept_bound extend_to_match build_test blocked_on_sdk_gap)

      assert A.build_levels() == ~w(pure_unit mock_transport plug live_http)
    end
  end

  # The innermost `test "…"` at or above the window's first line owns the
  # window. No other test line may start inside the window, and the owner's own
  # closing line must be at or after the window's last line: for a block test
  # that is the first later line equal to the test's indent followed by `end`
  # (so a nested `describe`'s shallower `end`, and any deeper `end` inside the
  # body, are not taken for it); for a one-line `, do:` test it is the test line
  # itself, so a window reaching past that line is refused (fail-closed, even
  # for a `do:` body continued onto later lines). The owner must be the
  # member's test (qualified by its `describe` when nested), in a file that
  # defines the member's module.
  @test_line ~r/^(\s*)test "((?:[^"\\]|\\.)*)"/
  @one_line_test ~r/,\s*do:/
  @describe_line ~r/^  describe "((?:[^"\\]|\\.)*)"/

  defp et_test_owner(row, source_fun) do
    %{"file" => file, "lines" => [from, to]} = row["et_test"]
    [module, member_test] = String.split(row["member"], "/", parts: 2)
    {:ok, src} = source_fun.(file)
    lines = src |> String.split("\n") |> Enum.with_index(1)
    tests = for {l, i} <- lines, m = Regex.run(@test_line, l), do: {i, m}

    with {i, [_, indent, name]} <- tests |> Enum.filter(&(elem(&1, 0) <= from)) |> List.last(),
         true <- Enum.all?(tests, fn {j, _} -> j <= i or j > to end) || :window_crosses_a_test,
         last when is_integer(last) <- test_end(lines, i, indent) || :test_end_not_found,
         true <- to <= last || {:window_outside_test, last},
         describe <- describe_above(lines, i, indent),
         expected = Enum.join(["test", describe, unescape(name)] |> Enum.reject(&is_nil/1), " "),
         true <- expected == member_test || {:names, expected},
         true <- String.contains?(src, "defmodule #{module} do") || :module do
      :ok
    else
      other -> {:error, other}
    end
  end

  # {owned, skipped}, each a list of {record, view, row}: a row with no member
  # has no test to own its et_test.
  defp ownership_split(records) do
    all =
      for {file, {:ok, doc}} <- records,
          s <- doc["sections"],
          r <- s["rows"],
          do: {file, s["view"], r}

    Enum.split_with(all, fn {_, _, r} -> not is_nil(r["member"]) end)
  end

  defp skip_pin(records) do
    {_, skipped} = ownership_split(records)
    got = Enum.sort(for {f, v, r} <- skipped, do: {f, v, A.key(r)})

    want =
      Enum.sort(
        for(vr <- json(@v2b)["rows"], do: {@d2b, @v2b, A.key(vr)}) ++
          for(vr <- selected(json(@v2a)["rows"], @d2ai_selector), do: {@d2ai, @v2a, A.key(vr)})
      )

    if got == want,
      do: :ok,
      else: {:error, {:skipped_rows_differ, got -- want, want -- got}}
  end

  defp d2b_rows(inputs) do
    {:ok, record} = inputs.records[@d2b]
    [%{"rows" => rows}] = record["sections"]
    rows
  end

  defp d2ai_rows(inputs) do
    {:ok, record} = inputs.records[@d2ai]
    [%{"rows" => rows}] = record["sections"]
    rows
  end

  defp selected(view_rows, %{"field" => f, "segment" => i, "starts_with" => p}) do
    Enum.filter(view_rows, fn r ->
      r[f] |> String.split("/") |> Enum.at(i) |> Kernel.||("") |> String.starts_with?(p)
    end)
  end

  defp selector_equality(rows, view_rows) do
    got = rows |> Enum.map(&A.key/1) |> Enum.sort()
    want = view_rows |> selected(@d2ai_selector) |> Enum.map(&A.key/1) |> Enum.sort()

    if got == want,
      do: :ok,
      else: {:error, {:rows_differ, got -- want, want -- got}}
  end

  # [scenario, name, status] read out of the cited census window.
  defp census_echo(row) do
    b = row["oc_status_at_accepted_run"]["bytes"]
    # The window opens on the key's scenario line.
    [scenario] = Regex.run(~r/\A\s*"([^"]+)",/, b, capture: :all_but_first)

    [name, status] =
      Regex.run(~r/"name": "([^"]+)",\s*"status": "([A-Z]+)"/, b, capture: :all_but_first)

    [scenario, name, status]
  end

  defp why_green_owed?(r) do
    r["disposition"] == "blocked_on_sdk_gap" and List.last(census_echo(r)) == "SUCCESS"
  end

  # The tags of owed rows whose why_green is absent, carries no statement, or
  # carries no citation that holds its bytes.
  defp why_green_defects(rows, source_fun) do
    for r <- rows, why_green_owed?(r), not why_green_ok?(r["why_green"], source_fun), do: r["tag"]
  end

  defp why_green_ok?(%{"statement" => s} = w, source_fun) when is_binary(s) and s != "" do
    cites = A.collect(w)
    cites != [] and Enum.all?(cites, &(A.verify(&1, source_fun) == :ok))
  end

  defp why_green_ok?(_, _), do: false

  @mrtr_needle ~r/input_required|inputRequests|requestState|inputResponses|RequestState|on_input_required/

  # Non-ET-CC register rows whose body (its line to the next register row in
  # the same file) matches the needle. Sorted keys.
  defp mrtr_non_etcc_units do
    json("docs/conformance/etcc-register.json")["rows"]
    |> Enum.group_by(& &1["file"])
    |> Enum.flat_map(fn {file, rows} -> mrtr_non_etcc_units(file, rows) end)
    |> Enum.sort()
  end

  defp mrtr_non_etcc_units(file, rows) do
    src = file |> File.read!() |> String.split("\n")
    starts = rows |> Enum.map(& &1["line"]) |> Enum.sort()

    for r <- rows,
        r["label"] != "ET-CC",
        stop = Enum.find(starts, length(src) + 1, &(&1 > r["line"])) - 1,
        body = src |> Enum.slice((r["line"] - 1)..(stop - 1)//1) |> Enum.join("\n"),
        Regex.match?(@mrtr_needle, body),
        do: r["key"]
  end

  defp status_echo(row),
    do:
      Regex.run(
        ~r/"name": "([^"]+)",\s*"status": "([A-Z]+)"/,
        row["oc_status_at_accepted_run"]["bytes"],
        capture: :all_but_first
      )

  # The section's population sentence must EQUAL the predicate, and no prose leaf
  # of the record may say "untested" (case-insensitive). Leaves under a `bytes`
  # key are quotations of other files and are exempt.
  defp rendering_defects(record) do
    sentence =
      for s <- record["sections"],
          s["population_sentence"] != @population_sentence,
          do: {:population_sentence, s["population_sentence"]}

    sentence ++ for leaf <- prose_leaves(record), leaf =~ ~r/untested/i, do: {:untested, leaf}
  end

  defp prose_leaves(m) when is_map(m),
    do: Enum.flat_map(m, fn {k, v} -> if k == "bytes", do: [], else: prose_leaves(v) end)

  defp prose_leaves(l) when is_list(l), do: Enum.flat_map(l, &prose_leaves/1)
  defp prose_leaves(s) when is_binary(s), do: [s]
  defp prose_leaves(_), do: []

  defp json(path), do: path |> File.read!() |> Jason.decode!()
  defp client?(tag), do: String.starts_with?(tag, "oc:client/")

  defp test_end(lines, i, indent) do
    {head, _} = Enum.at(lines, i - 1)

    if Regex.match?(@one_line_test, head) do
      i
    else
      lines
      |> Enum.drop(i)
      |> Enum.find_value(fn {l, j} -> String.trim_trailing(l) == indent <> "end" && j end)
    end
  end

  defp describe_above(_lines, _i, "  "), do: nil

  defp describe_above(lines, i, "    ") do
    lines
    |> Enum.take(i - 1)
    |> Enum.reverse()
    |> Enum.find_value(fn {l, _} ->
      case Regex.run(@describe_line, l),
        do: (
          [_, d] -> unescape(d)
          nil -> nil
        )
    end)
  end

  defp unescape(s), do: String.replace(s, ~S(\"), ~S("))

  # --- synthetic inputs ---------------------------------------------------------

  @view "docs/conformance/buckets/bucket-x.json"
  @rec "docs/conformance/adjudications/adjudication-X.json"
  @src "test/src.exs"

  defp view_row(member, claim, tag, extra \\ %{}) do
    Map.merge(
      %{
        "member" => %{"register_key" => member},
        "claim" => claim,
        "tag" => tag,
        "shape" => "contradicting",
        "verdicts" => %{"et" => "green", "oc" => "red"},
        "bucket" => "x"
      },
      extra
    )
  end

  defp row(vr, overrides \\ %{}) do
    Map.merge(
      %{
        "member" => vr["member"]["register_key"],
        "claim" => vr["claim"],
        "tag" => vr["tag"],
        "echo" => A.echo(vr),
        "et_test" => %{"file" => @src, "lines" => [2, 2], "bytes" => "assert x == 1"},
        "check" => %{"requires" => "x"},
        "root_cause" => "R0",
        "if_conformance_fixed" => [],
        "disposition" => "fix_sdk",
        "rationale" => "r"
      },
      overrides
    )
  end

  defp inputs(view_rows, sections, opts \\ []) do
    %{
      walk: [@rec],
      records: %{
        @rec =>
          Keyword.get(
            opts,
            :record,
            {:ok,
             %{
               "schema" => "adjudication-record/1",
               "authored_by_hand" => true,
               "sections" => sections
             }}
          )
      },
      views: %{
        @view =>
          {:ok,
           %{"schema" => Keyword.get(opts, :view_schema, "bucket-view/1"), "rows" => view_rows}}
      },
      source_fun: fn
        @src -> {:ok, "line one\n  assert   x == 1\nline three\n"}
        _ -> {:error, :enoent}
      end
    }
  end

  defp section(rows, closure \\ "closed", extra \\ %{}),
    do: Map.merge(%{"view" => @view, "closure" => closure, "rows" => rows}, extra)

  defp kinds(inputs), do: inputs |> A.audit() |> Map.fetch!(:defects) |> Enum.map(& &1.kind)

  defp a, do: view_row("M/a", "claim a", "oc:t1")
  defp b, do: view_row("M/a", "claim b", "oc:t1")

  describe "the key" do
    test "is the same triple from a view row and from a record row" do
      assert A.key(a()) == ["M/a", "claim a", "oc:t1"]
      assert A.key(row(a())) == A.key(a())
    end

    test "a component the row does not carry is nil" do
      assert A.key(%{"tag" => "oc:t"}) == [nil, nil, "oc:t"]
    end

    test "two edges sharing a member are two keys" do
      refute A.key(a()) == A.key(b())
    end
  end

  describe "set equality, both ways" do
    test "positive: every edge adjudicated once is clean" do
      assert kinds(inputs([a(), b()], [section([row(a()), row(b())])])) == []
    end

    test "missing: a closed section that omits an edge" do
      assert kinds(inputs([a(), b()], [section([row(a())])])) == [:missing]
    end

    test "an open section may omit an edge, and must name an owner" do
      assert kinds(inputs([a(), b()], [section([row(a())], "open", %{"owner" => "MES-1"})])) == []
      assert kinds(inputs([a(), b()], [section([row(a())], "open")])) == [:open_without_owner]
    end

    test "missing fires when ANY bound section is closed" do
      sections = [section([row(a())], "open", %{"owner" => "MES-1"}), section([], "closed")]
      assert kinds(inputs([a(), b()], sections)) == [:missing]
    end

    test "phantom: an edge the view does not project, even in an open section" do
      ghost = row(a(), %{"claim" => "no such claim"})

      assert :phantom in kinds(
               inputs([a()], [section([row(a()), ghost], "open", %{"owner" => "M"})])
             )
    end

    test "duplicate: one edge adjudicated twice across sections" do
      sections = [
        section([row(a())], "open", %{"owner" => "M"}),
        section([row(a())], "open", %{"owner" => "N"})
      ]

      assert kinds(inputs([a()], sections)) == [:duplicate]
    end

    test "view_key_collision: a view whose rows do not key uniquely is refused" do
      assert kinds(inputs([a(), a()], [section([row(a())])])) == [:view_key_collision]
    end

    test "unknown_view: a section bound to something that is not a view" do
      assert kinds(inputs([a()], [section([row(a())])], view_schema: "other/1")) == [
               :unknown_view
             ]
    end
  end

  describe "rows" do
    test "disposition_outside_set" do
      assert kinds(inputs([a()], [section([row(a(), %{"disposition" => "wontfix"})])])) ==
               [:disposition_outside_set]
    end

    test "extend_test and accept_bound are in the set" do
      assert kinds(inputs([a()], [section([row(a(), %{"disposition" => "extend_test"})])])) == []

      bounded = row(a(), %{"disposition" => "accept_bound", "bound" => "code only, at this seam"})
      assert kinds(inputs([a()], [section([bounded])])) == []
    end

    # MES-127 (29430, Q2): an accept_bound row states its bound as one line.
    test "bound_missing: an accept_bound row without a single-line, non-empty bound" do
      for bound <- [:absent, nil, "", "   ", "two\nlines", "a\r\nb", 7] do
        r = row(a(), %{"disposition" => "accept_bound"})
        r = if bound == :absent, do: r, else: Map.put(r, "bound", bound)
        assert kinds(inputs([a()], [section([r])])) == [:bound_missing], inspect(bound)
      end
    end

    test "extend_to_match and build_test are in the set, with a level and a remedy" do
      built = %{"build_level" => "mock_transport", "remedy" => "add one assertion"}
      target = %{"extend_target" => %{"reading" => "the unit"}}

      assert kinds(
               inputs([a()], [
                 section([row(a(), Map.merge(built, %{"disposition" => "build_test"}))])
               ])
             ) == []

      assert kinds(
               inputs([a()], [
                 section([
                   row(
                     a(),
                     built |> Map.merge(target) |> Map.put("disposition", "extend_to_match")
                   )
                 ])
               ])
             ) == []
    end

    # MES-128 (29444, Q1): both bucket-2 codes carry build_level and a one-line
    # remedy; extend_to_match also names the unit it extends. Shape only.
    test "build_level_missing: a bucket-2 row without a level, a remedy or a target" do
      good = %{
        "build_level" => "pure_unit",
        "remedy" => "one line",
        "extend_target" => %{"reading" => "the unit"}
      }

      for disp <- ~w(extend_to_match build_test),
          {field, bad} <- [
            {"build_level", :absent},
            {"build_level", "unit"},
            {"build_level", nil},
            {"remedy", :absent},
            {"remedy", ""},
            {"remedy", "two\nlines"},
            {"remedy", 7}
          ] do
        r = row(a(), Map.put(good, "disposition", disp))
        r = if bad == :absent, do: Map.delete(r, field), else: Map.put(r, field, bad)

        assert kinds(inputs([a()], [section([r])])) == [:build_level_missing],
               "#{disp} #{field}=#{inspect(bad)}"
      end

      no_target =
        row(a(), good |> Map.delete("extend_target") |> Map.put("disposition", "extend_to_match"))

      assert kinds(inputs([a()], [section([no_target])])) == [:build_level_missing]

      # build_test needs no target, and no other code needs a level.
      assert kinds(
               inputs([a()], [
                 section([
                   row(a(), %{
                     "disposition" => "build_test",
                     "build_level" => "plug",
                     "remedy" => "x"
                   })
                 ])
               ])
             ) == []

      assert kinds(inputs([a()], [section([row(a(), %{"disposition" => "fix_sdk"})])])) == []
    end

    # MES-129 (29460, Q1): a blocked_on_sdk_gap row carries a level, a remedy
    # and an sdk_gap naming the owning ticket, its record there, and a citation
    # of the gap here. Shape only.
    defp gap,
      do: %{
        "owner" => "MES-43",
        "owner_record" => "MES-43 body, Gap 1",
        "record" => %{"file" => @src, "lines" => [2, 2], "bytes" => "assert x == 1"}
      }

    defp blocked(extra \\ %{}) do
      row(
        a(),
        Map.merge(
          %{
            "disposition" => "blocked_on_sdk_gap",
            "build_level" => "plug",
            "remedy" => "build the unit with the fix",
            "sdk_gap" => gap()
          },
          extra
        )
      )
    end

    test "blocked_on_sdk_gap is in the set, with a level, a remedy and an sdk_gap" do
      assert kinds(inputs([a()], [section([blocked()])])) == []
    end

    test "sdk_gap_missing: a blocked row without a well-shaped sdk_gap" do
      for bad <- [
            :absent,
            nil,
            "MES-43",
            Map.delete(gap(), "owner"),
            Map.put(gap(), "owner", "mes-43"),
            Map.put(gap(), "owner", "MES-43 and more"),
            Map.delete(gap(), "owner_record"),
            Map.put(gap(), "owner_record", ""),
            Map.put(gap(), "owner_record", "two\nlines"),
            Map.delete(gap(), "record"),
            Map.put(gap(), "record", "docs/sprint_4_issues.md:4410")
          ] do
        r =
          if bad == :absent,
            do: Map.delete(blocked(), "sdk_gap"),
            else: blocked(%{"sdk_gap" => bad})

        assert kinds(inputs([a()], [section([r])])) == [:sdk_gap_missing], inspect(bad)
      end
    end

    test "a blocked row's sdk_gap record is a citation, held by citation_drift" do
      # A record with no line window is refused by shape AND, being a
      # malformed citation, by citation_drift: neither masks the other.
      no_lines = Map.put(gap(), "record", %{"file" => @src, "bytes" => "x"})

      assert kinds(inputs([a()], [section([blocked(%{"sdk_gap" => no_lines})])])) ==
               [:sdk_gap_missing, :citation_drift]

      stale = put_in(gap(), ["record", "lines"], [3, 3])

      assert kinds(inputs([a()], [section([blocked(%{"sdk_gap" => stale})])])) == [
               :citation_drift
             ]
    end

    test "build_level_missing extends to blocked_on_sdk_gap; an sdk_gap on another code is not required" do
      assert kinds(inputs([a()], [section([Map.delete(blocked(), "build_level")])])) ==
               [:build_level_missing]

      assert kinds(inputs([a()], [section([Map.delete(blocked(), "remedy")])])) ==
               [:build_level_missing]

      assert kinds(inputs([a()], [section([Map.delete(blocked(), "extend_target")])])) == []
      assert kinds(inputs([a()], [section([row(a(), %{"disposition" => "fix_sdk"})])])) == []
    end

    test "a bound on a row that is not accept_bound is not required" do
      assert kinds(inputs([a()], [section([row(a(), %{"disposition" => "fix_sdk"})])])) == []
    end

    test "bad_row: a missing field is named" do
      [d] =
        inputs([a()], [section([Map.delete(row(a()), "rationale")])])
        |> A.audit()
        |> Map.get(:defects)

      assert d.kind == :bad_row and d.detail =~ "rationale"
    end

    test "echo_drift: the view's verdict moved under an unchanged key" do
      moved = Map.put(a(), "verdicts", %{"et" => "green", "oc" => "green"})
      assert kinds(inputs([moved], [section([row(a())])])) == [:echo_drift]
    end

    test "an escalated row needs whose_defect and a cause_slug naming the view's cause" do
      esc =
        view_row("M/e", "c", "oc:e", %{"escalation_reason" => "r", "escalation_cause" => "slug"})

      ok =
        row(esc, %{
          "whose_defect" => "suite",
          "cause_slug" => %{"view" => "slug", "verdict" => "confirmed"}
        })

      assert kinds(inputs([esc], [section([ok])])) == []

      assert kinds(inputs([esc], [section([row(esc)])])) == [:bad_row, :bad_row, :bad_row]

      wrong = put_in(ok, ["cause_slug", "view"], "other")
      assert kinds(inputs([esc], [section([wrong])])) == [:echo_drift]

      corrected = put_in(ok, ["cause_slug", "verdict"], "corrected")
      assert kinds(inputs([esc], [section([corrected])])) == [:bad_row]
    end
  end

  describe "citations" do
    test "equality of the squashed line window, not containment" do
      assert A.verify(%{"file" => @src, "lines" => [2, 2], "bytes" => "assert x == 1"}, src()) ==
               :ok

      assert {:error, _} =
               A.verify(%{"file" => @src, "lines" => [2, 2], "bytes" => "x == 1"}, src())

      assert {:error, _} =
               A.verify(%{"file" => @src, "lines" => [1, 2], "bytes" => "assert x == 1"}, src())
    end

    test "a window past the end, or a path outside the repository, is refused" do
      assert {:error, msg} = A.verify(%{"file" => @src, "lines" => [9, 9], "bytes" => "x"}, src())
      assert msg =~ "past the end"

      real = A.load()
      assert {:error, :outside_repository} = real.source_fun.("../etc/passwd")
      assert {:error, :outside_repository} = real.source_fun.("/etc/passwd")
    end

    test "citation_drift names the row; a malformed citation is refused, not uncounted" do
      stale =
        row(a(), %{"et_test" => %{"file" => @src, "lines" => [3, 3], "bytes" => "assert x == 1"}})

      assert kinds(inputs([a()], [section([stale])])) == [:citation_drift]

      odd = row(a(), %{"et_test" => %{"bytes" => "assert x == 1"}})
      assert kinds(inputs([a()], [section([odd])])) == [:citation_drift]
    end

    test "a harness citation is counted, not verified, in gate 5" do
      h = %{"harness_sha256" => "abc", "byte_span" => [1, 2], "bytes" => "x"}
      %{report: r, defects: []} = A.audit(inputs([a()], [section([row(a(), %{"check" => h})])]))
      assert r["harness_citations_not_verified_in_gate_5"] == 1
      assert r["citations_verified"] == 1
    end
  end

  describe "records and reach" do
    test "bad_record and unreadable, and a record that yields no rows also fails reach" do
      assert kinds(inputs([a()], [], record: {:ok, %{"schema" => "x"}})) == [:bad_record, :reach]
      assert kinds(inputs([a()], [], record: {:error, "nope"})) == [:unreadable, :reach]
    end

    test "a visited record with zero rows is refused" do
      assert kinds(inputs([], [section([], "open", %{"owner" => "M"})])) == [:reach]
    end

    test "an empty directory reports zero and refuses nothing" do
      %{report: r, defects: []} =
        A.audit(%{walk: [], records: %{}, views: %{}, source_fun: fn _ -> {:error, :x} end})

      assert r["records_visited"] == 0 and r["rows_visited"] == 0
    end
  end

  defp src do
    fn
      @src -> {:ok, "line one\n  assert   x == 1\nline three\n"}
      _ -> {:error, :enoent}
    end
  end
end

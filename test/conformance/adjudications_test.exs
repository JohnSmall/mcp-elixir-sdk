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
  @d2aii "docs/conformance/adjudications/adjudication-D2a-ii-2026-07-28.json"
  # D2a-ii's slice, the literal complement of D2a-i's (MES-130 brief; PM 29491).
  @d2aii_selector %{
    "field" => "tag",
    "segment" => 1,
    "not_starts_with" => "input-required-result-"
  }
  # D2a-ii's covered-elsewhere needle, pinned here and required to equal the
  # record's: the stimuli, headers and result members its checks send or read.
  @d2aii_needle ~r{ttlMs|cacheScope|prompts/get|resources/templates|completion/complete|send_progress|progressToken|notifications/progress|list_changed|listChanged|-32_021|-32021|-32_020|mcp-protocol-version|MCP-Protocol-Version|resources/subscribe|resources/unsubscribe|"origin"|"host"|blob|logLevel}
  @v4a "docs/conformance/buckets/bucket-4a-2026-07-28.json"
  @v5a "docs/conformance/buckets/bucket-5a-2026-07-28.json"
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

    # MES-136: the PO's ruling (MES-126 comment 29509) made D4a's four PO rows
    # fix_sdk, each citing the ruling and its MES-43 comment 29510 bullet, and
    # resolved the decision_row. Per edge: disposition, root cause, questions.
    test "D4a's dispositions are the ruled ones, per edge", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4a]
      [%{"rows" => rows}, _escalated] = record["sections"]

      got =
        for r <- rows do
          ruling = r["ruling"]

          if ruling do
            assert {ruling["ruled_at"], ruling["answer"], ruling["owner"]} ==
                     {"MES-126 comment 29509", "YES", "MES-43"}

            assert ruling["owner_record"] =~ ~r/\AMES-43 comment 29510, the R[16] \/ Q/
          end

          {r["member"] |> String.split("/") |> hd(), r["tag"] |> String.split("/") |> List.last(),
           r["disposition"], r["root_cause"]["id"], ruling && ruling["questions"]}
        end

      assert got == [
               {"MCP.Server.DispatchTest", "HttpServerMethodNotFound404initialize", "fix_sdk",
                "R6", ["Q3"]},
               {"MCP.Transport.StreamableHTTPStatelessTest",
                "HttpServerMethodNotFound404initialize", "fix_sdk", "R6", ["Q3"]},
               {"MCP.Server.DispatchTest", "RequestMetaInvalid", "fix_sdk", "R1", ["Q1a", "Q1b"]},
               {"MCP.Transport.StreamableHTTPStatelessTest", "RequestMetaInvalid", "fix_sdk",
                "R1", ["Q1a", "Q1b"]},
               {"MCP.Transport.SubscriptionsStreamTest", "HttpServerMethodNotFound404", "fix_sdk",
                "R2", nil}
             ]

      resolved = record["decision_row"]["resolved"]

      assert {resolved["ruled_at"], resolved["answers"], resolved["disposition"],
              resolved["owner"]} ==
               {"MES-126 comment 29509", %{"Q2" => "YES", "Q3" => "YES"}, "fix_sdk", "MES-43"}
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
    test "rendering guard: D2b's, D2a-i's and D2a-ii's population sentences are the predicate verbatim",
         %{inputs: inputs} do
      for f <- [@d2b, @d2ai] do
        {:ok, record} = inputs.records[f]
        assert rendering_defects(record) == [], f
        assert A.verify(record["rendering_guard"]["anchor"], inputs.source_fun) == :ok
        assert record["rendering_guard"]["anchor"]["bytes"] =~ @population_sentence
      end

      # D2a-ii keeps D2a-i's anchor by reference (PM 29491, F3) and cites the
      # view's own title, whose wording it records rather than resolves.
      {:ok, ii} = inputs.records[@d2aii]
      assert rendering_defects(ii) == []
      assert ii["rendering_guard"]["anchor_ref"] =~ "D2a-i's rendering_guard.anchor"
      assert A.verify(ii["rendering_guard"]["view_title"], inputs.source_fun) == :ok
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
      assert selector_equality(d2ai_rows(inputs), json(@v2a)["rows"], @d2ai_selector) == :ok
    end

    test "the selector equality refuses a non-MRTR 2a row and a dropped MRTR row",
         %{inputs: inputs} do
      rows = d2ai_rows(inputs)
      view_rows = json(@v2a)["rows"]
      [other | _] = Enum.reject(view_rows, &(&1 in selected(view_rows, @d2ai_selector)))
      planted = rows ++ [%{"member" => nil, "claim" => nil, "tag" => other["tag"]}]

      assert {:error, {:rows_differ, [[nil, nil, tag]], []}} =
               selector_equality(planted, view_rows, @d2ai_selector)

      assert tag == other["tag"]
      refute String.starts_with?(Enum.at(String.split(tag, "/"), 1), "input-required-result-")

      [first | rest] = rows

      assert {:error, {:rows_differ, [], [dropped]}} =
               selector_equality(rest, view_rows, @d2ai_selector)

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
        assert r["lands_when"] == d2ai_derived(r, conds), r["tag"]

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

    # --- D2a-ii (MES-130): the rest of bucket 2a, a CLOSED section ---

    test "D2a-ii's record holds one CLOSED section on bucket 2a", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      assert for(s <- record["sections"], do: {s["view"], s["closure"]}) == [{@v2a, "closed"}]
    end

    # The MES-130 brief: the slice is declared by the complement of D2a-i's
    # selector, pinned literally, and the section EQUALS its result both ways.
    test "D2a-ii's selector is the pinned one, and its rows EQUAL the selector's result",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      assert Map.take(record["selector"], ~w(field segment not_starts_with)) == @d2aii_selector
      assert selector_equality(d2aii_rows(inputs), json(@v2a)["rows"], @d2aii_selector) == :ok
    end

    # The two selectors PARTITION the view: computed over the view, disjoint,
    # with union equal to the view. And no tag can satisfy both, because they
    # test the same segment against the same prefix, one negated.
    test "the D2a-i and D2a-ii selectors partition bucket 2a, and the sections meet them",
         %{inputs: inputs} do
      view_rows = json(@v2a)["rows"]
      assert partition(d2ai_rows(inputs), d2aii_rows(inputs), view_rows) == :ok

      i = selected(view_rows, @d2ai_selector) |> MapSet.new(&A.key/1)
      ii = selected(view_rows, @d2aii_selector) |> MapSet.new(&A.key/1)
      assert MapSet.disjoint?(i, ii)
      assert MapSet.union(i, ii) == MapSet.new(view_rows, &A.key/1)
      assert MapSet.size(i) == 30 and MapSet.size(ii) == 48

      assert @d2ai_selector["starts_with"] == @d2aii_selector["not_starts_with"]
      assert @d2ai_selector["segment"] == @d2aii_selector["segment"]
      assert @d2ai_selector["field"] == @d2aii_selector["field"]
    end

    test "the partition refuses a row planted into both slices, and a view row in neither",
         %{inputs: inputs} do
      view_rows = json(@v2a)["rows"]
      i = d2ai_rows(inputs)
      [ii_first | ii_rest] = ii = d2aii_rows(inputs)

      assert partition(i ++ [ii_first], ii, view_rows) == {:error, {:overlap, [A.key(ii_first)]}}
      assert partition(i, ii_rest, view_rows) == {:error, {:gap, [A.key(ii_first)]}}

      # ...and each selector-equality unit names the same row.
      assert {:error, {:rows_differ, [k], []}} =
               selector_equality(i ++ [ii_first], view_rows, @d2ai_selector)

      assert k == A.key(ii_first)

      assert {:error, {:rows_differ, [], [^k]}} =
               selector_equality(ii_rest, view_rows, @d2aii_selector)
    end

    # PM ratification on MES-130 (29491): per check, the disposition and the level.
    test "D2a-ii's dispositions and build levels are the ratified ones, per check",
         %{inputs: inputs} do
      got =
        for r <- d2aii_rows(inputs), into: %{} do
          [_ | rest] = String.split(r["tag"], "/")
          {Enum.join(rest, "/"), {r["disposition"], r["build_level"]}}
        end

      ss = &("server-stateless/sep-2575-" <> &1)
      blocked = {"blocked_on_sdk_gap", "plug"}
      # MES-136: the PO's ruling (MES-126 29509) moved the seven PO rows to
      # blocked_on_sdk_gap, plug where R2 is a condition (PM ratification 29534, Q2).
      ruled_unit = {"blocked_on_sdk_gap", "pure_unit"}
      ext = &{"extend_to_match", &1}
      build = &{"build_test", &1}

      wsv =
        for {s, level} <- [
              {"caching", "plug"},
              {"completion-complete", "mock_transport"},
              {"prompts-get-embedded-resource", "mock_transport"},
              {"prompts-get-simple", "mock_transport"},
              {"prompts-get-with-args", "mock_transport"},
              {"prompts-get-with-image", "mock_transport"},
              {"prompts-list", "mock_transport"},
              {"resources-list", "mock_transport"},
              {"resources-read-binary", "plug"},
              {"resources-read-text", "plug"},
              {"resources-templates-read", "plug"},
              {"sep-2164-resource-not-found", "mock_transport"},
              {"tools-call-audio", "mock_transport"},
              {"tools-call-error", "mock_transport"},
              {"tools-call-mixed-content", "mock_transport"},
              {"tools-list", "plug"}
            ],
            into: %{},
            do: {s <> "/wire-schema-valid/WireSchemaValid", ext.(level)}

      assert got ==
               wsv
               |> Map.merge(%{
                 "tools-call-with-progress/wire-schema-valid/WireSchemaValid" => build.("plug"),
                 ss.("http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-meta") =>
                   blocked,
                 ss.(
                   "http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-protocol-version"
                 ) => blocked,
                 ss.(
                   "http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-client-capabilities"
                 ) => blocked,
                 ss.("request-meta-invalid-missing-protocol-version/RequestMetaInvalid") =>
                   ruled_unit,
                 ss.("request-meta-invalid-missing-client-capabilities/RequestMetaInvalid") =>
                   ruled_unit,
                 ss.("server-unsupported-version-error/ServerUnsupportedVersionError") =>
                   ruled_unit,
                 ss.("http-server-unsupported-version-400/HttpServerUnsupportedVersion400") =>
                   blocked,
                 ss.(
                   "http-server-method-not-found-404-resources-subscribe/HttpServerMethodNotFound404resourcessubscribe"
                 ) => blocked,
                 ss.(
                   "http-server-method-not-found-404-resources-unsubscribe/HttpServerMethodNotFound404resourcesunsubscribe"
                 ) => blocked,
                 ss.("missing-capability-http-400/MissingCapabilityHttp400") => blocked,
                 ss.("server-rejects-undeclared-capability/ServerRejectsUndeclaredCapability") =>
                   blocked,
                 ss.("http-server-header-mismatch-400/HttpServerHeaderMismatch400") => blocked,
                 "sep-2164-resource-not-found/sep-2164-data-uri/ResourcesNotFoundDataUri" =>
                   {"blocked_on_sdk_gap", "mock_transport"},
                 "caching/sep-2549-prompts-list-caching-hints/PromptsListCachingHints" =>
                   ext.("plug"),
                 "caching/sep-2549-resources-list-caching-hints/ResourcesListCachingHints" =>
                   ext.("plug"),
                 "caching/sep-2549-resources-templates-list-caching-hints/ResourcesTemplatesListCachingHints" =>
                   ext.("plug"),
                 "caching/sep-2549-resources-read-caching-hints/ResourcesReadCachingHints" =>
                   ext.("plug"),
                 "dns-rebinding-protection/localhost-host-valid-accepted/LocalhostHostAccepted" =>
                   ext.("plug"),
                 "prompts-get-with-args/prompts-get-with-args/PromptsGetWithArgs" =>
                   ext.("mock_transport"),
                 "resources-read-binary/resources-read-binary/ResourcesReadBinary" =>
                   ext.("mock_transport"),
                 "resources-templates-read/resources-templates-read/ResourcesTemplateRead" =>
                   ext.("mock_transport"),
                 "sep-2164-resource-not-found/sep-2164-no-empty-contents/ResourcesNotFoundNoEmptyContents" =>
                   ext.("mock_transport"),
                 "server-sse-multiple-streams/server-accepts-multiple-post-streams/ServerAcceptsMultiplePostStreams" =>
                   ext.("live_http"),
                 "server-sse-multiple-streams/server-sse-streams-functional/ServerSSEStreamsFunctional" =>
                   build.("live_http"),
                 ss.(
                   "http-server-no-independent-requests-on-stream/HttpServerNoIndependentRequestsOnStream"
                 ) => build.("plug"),
                 ss.("server-declares-prompts-in-discover/ServerDeclaresPromptsInDiscover") =>
                   ext.("pure_unit"),
                 ss.("server-no-log-without-loglevel/ServerNoLogWithoutLogLevel") =>
                   build.("plug"),
                 ss.(
                   "server-sends-prompts-list-changed-on-subscription/ServerSendsPromptsListChangedOnSubscription"
                 ) => ext.("live_http"),
                 ss.(
                   "server-sends-tools-list-changed-on-subscription/ServerSendsToolsListChangedOnSubscription"
                 ) => ext.("live_http"),
                 "tools-call-with-progress/tools-call-with-progress/ToolsCallWithProgress" =>
                   build.("plug"),
                 "tools-list/tools-name-format/ToolsNameFormat" => ext.("plug")
               })
    end

    # The status premise: the census window from the scenario line through the
    # status line (the discriminator line inside it when the tag carries one).
    # The red rows are exactly the blocked rows; DataUri is the WARNING.
    test "each D2a-ii row cites its own check's status at the accepted run", %{inputs: inputs} do
      rows = d2aii_rows(inputs)
      assert length(rows) == 48

      statuses =
        for r <- rows do
          c = r["oc_status_at_accepted_run"]
          assert c["file"] == @in_scope
          assert A.verify(c, inputs.source_fun) == :ok
          [_, scenario, _, name_disc] = String.split(r["tag"], "/")
          [name | disc] = String.split(name_disc, "#")
          assert [^scenario, ^name, status] = census_echo(r), r["tag"]
          for d <- disc, do: assert(c["bytes"] =~ ~s("#{d}"\n), r["tag"])
          {r["disposition"], status}
        end

      assert Enum.frequencies(statuses) == %{
               {"blocked_on_sdk_gap", "FAILURE"} => 12,
               {"blocked_on_sdk_gap", "WARNING"} => 1,
               {"extend_to_match", "SUCCESS"} => 30,
               {"build_test", "SUCCESS"} => 5
             }

      [warn] = for r <- rows, List.last(census_echo(r)) == "WARNING", do: r["tag"]
      assert String.ends_with?(warn, "/ResourcesNotFoundDataUri")
    end

    # The brief: for every SUCCESS, record whether the SDK earned it or the
    # adapter did (why_green). A null-passable green says so and is no evidence.
    test "every SUCCESS D2a-ii row carries why_green, and its citations hold", %{inputs: inputs} do
      rows = d2aii_rows(inputs)
      green = Enum.filter(rows, &(List.last(census_echo(&1)) == "SUCCESS"))
      assert length(green) == 35
      assert d2aii_why_green_defects(rows, inputs.source_fun) == []

      assert green |> Enum.map(& &1["why_green"]["earned_by"]) |> Enum.frequencies() ==
               %{"sdk" => 10, "adapter" => 8, "none_null_passable" => 17}

      for r <- green,
          r["why_green"]["earned_by"] == "none_null_passable",
          do: assert(Map.has_key?(r, "null_passability"), r["tag"])
    end

    test "the D2a-ii why_green pin refuses a SUCCESS row without it, or with an unknown earner",
         %{inputs: inputs} do
      rows = d2aii_rows(inputs)
      [r | _] = Enum.filter(rows, &(List.last(census_echo(&1)) == "SUCCESS"))
      dropped = Enum.map(rows, &if(&1 == r, do: Map.delete(&1, "why_green"), else: &1))
      assert d2aii_why_green_defects(dropped, inputs.source_fun) == [r["tag"]]

      renamed =
        Enum.map(rows, &if(&1 == r, do: put_in(&1, ["why_green", "earned_by"], "luck"), else: &1))

      assert d2aii_why_green_defects(renamed, inputs.source_fun) == [r["tag"]]
    end

    # MES-130 29500, B1: ServerSSEStreamsFunctional was committed as earned_by
    # sdk with an adapter citation only, and the pin above admitted it. Every
    # SDK green now cites lib/; the committed shape is planted back and refused.
    test "an SDK-earned green must cite code under lib/, and SSEFunctional as committed is refused",
         %{inputs: inputs} do
      rows = d2aii_rows(inputs)
      sdk = Enum.filter(rows, &(get_in(&1, ["why_green", "earned_by"]) == "sdk"))
      assert length(sdk) == 10

      for r <- sdk,
          do: assert(Enum.any?(A.collect(r["why_green"]), &(&1["file"] =~ ~r/^lib\//)), r["tag"])

      [r] = Enum.filter(sdk, &String.ends_with?(&1["tag"], "/ServerSSEStreamsFunctional"))
      as_committed = Map.update!(r, "why_green", &Map.take(&1, ~w(earned_by statement adapter)))

      assert A.collect(as_committed["why_green"]) |> Enum.map(& &1["file"]) == [
               "conformance/server_adapter.exs"
             ]

      planted = Enum.map(rows, &if(&1 == r, do: as_committed, else: &1))
      assert d2aii_why_green_defects(planted, inputs.source_fun) == [r["tag"]]
    end

    # PM ratification on MES-130 (29491, Q1 and Q2): the R2 criterion, stated
    # once and applied to every row. The carrying rows point at D4a's ONE
    # fix_sdk R2 row by derived key, and every other row is read in not_carrying.
    test "each D2a-ii depends_on_fix resolves to D4a's fix_sdk R2 row, on exactly the pinned rows",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      rows = d2aii_rows(inputs)
      {carrying, rest} = Enum.split_with(rows, &Map.has_key?(&1, "depends_on_fix"))
      name = &(&1["tag"] |> String.split("/") |> List.last())

      assert carrying |> Enum.map(name) |> Enum.sort() ==
               Enum.sort(~w(
                 HttpServerMetaInvalid400#missing-meta
                 HttpServerMetaInvalid400#missing-protocol-version
                 HttpServerMetaInvalid400#missing-client-capabilities
                 HttpServerUnsupportedVersion400
                 HttpServerMethodNotFound404resourcessubscribe
                 HttpServerMethodNotFound404resourcesunsubscribe
                 MissingCapabilityHttp400
                 HttpServerHeaderMismatch400
               ))

      statement = record["depends_on_fix_statement"]
      not_carrying = statement["not_carrying"]

      assert rest |> Enum.map(& &1["tag"]) |> Enum.sort() ==
               not_carrying |> Map.keys() |> Enum.sort()

      assert Enum.all?(Map.values(not_carrying), &(is_binary(&1) and &1 != ""))
      assert statement["input_requests_criterion"]["carrying"] == []

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
        assert hit["root_cause"]["id"] == "R2" and ptr["root_cause_there"] == "R2"
      end
    end

    # MES-136: the PO ruled Q1a, Q1b, Q2 and Q3 YES (MES-126 comment 29509), and
    # MES-43 carries the fixes (comment 29510). Each ruled row records the
    # ruling by address and still points at D4a's R1 rows by derived key, now
    # fix_sdk there, or at D4a's decision_row, now resolved there. Its
    # owner_record is its sdk_gap's.
    test "each D2a-ii ruled row cites the ruling, and its pointer resolves in D4a's record",
         %{inputs: inputs} do
      {:ok, d4a} = inputs.records[@d4a]
      ruled = for r <- d2aii_rows(inputs), Map.has_key?(r, "ruling"), do: r
      assert length(ruled) == 7

      qs =
        for r <- ruled, into: %{} do
          p = r["ruling"]
          assert r["disposition"] == "blocked_on_sdk_gap"

          assert {p["ruled_at"], p["answer"], p["owner"]} ==
                   {"MES-126 comment 29509", "YES", "MES-43"}

          assert p["owner_record"] == r["sdk_gap"]["owner_record"]
          assert p["owner_record"] =~ ~r/\AMES-43 comment 29510, the R[13] \/ Q/

          for ptr <- p["rows"] || [] do
            [hit] =
              for s <- d4a["sections"],
                  s["view"] == ptr["view"],
                  t <- s["rows"],
                  A.key(t) == [ptr["member"], ptr["claim"], ptr["tag"]],
                  do: t

            assert hit["disposition"] == "fix_sdk" and ptr["disposition_there"] == "fix_sdk"
            assert hit["ruling"]["ruled_at"] == p["ruled_at"]
            assert hit["root_cause"]["id"] == "R1" and ptr["root_cause_there"] == "R1"
          end

          if dr = p["decision_row"] do
            assert dr["record"] == @d4a and dr["field"] == "decision_row"
            assert dr["citation"] == d4a["decision_row"]["stated_at"]
            assert A.verify(dr["citation"], inputs.source_fun) == :ok
            resolved = d4a["decision_row"]["resolved"]
            assert {resolved["ruled_at"], resolved["disposition"]} == {p["ruled_at"], "fix_sdk"}
            assert resolved["answers"]["Q2"] == "YES"
          end

          assert (p["rows"] || []) != [] or p["decision_row"] != nil

          {r["tag"] |> String.split("/") |> Enum.drop(2) |> Enum.join("/"),
           {p["questions"], p["either"] == true}}
        end

      assert qs == %{
               "sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-meta" =>
                 {["Q1a", "Q1b"], true},
               "sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-protocol-version" =>
                 {["Q1a"], false},
               "sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-client-capabilities" =>
                 {["Q1b"], false},
               "sep-2575-request-meta-invalid-missing-protocol-version/RequestMetaInvalid" =>
                 {["Q1a"], false},
               "sep-2575-request-meta-invalid-missing-client-capabilities/RequestMetaInvalid" =>
                 {["Q1b"], false},
               "sep-2575-server-unsupported-version-error/ServerUnsupportedVersionError" =>
                 {["Q2"], false},
               "sep-2575-http-server-unsupported-version-400/HttpServerUnsupportedVersion400" =>
                 {["Q2"], false}
             }
    end

    # PM ratification on MES-130 (29491, Q2, Q3 and the R5/DataUri ruling): the
    # owners, and each gap cited in this tree by address and bytes.
    test "each blocked D2a-ii row names its ratified owner and cites its gap's record here",
         %{inputs: inputs} do
      owners =
        for r <- d2aii_rows(inputs), r["disposition"] == "blocked_on_sdk_gap", into: %{} do
          gap = r["sdk_gap"]
          assert A.verify(gap["record"], inputs.source_fun) == :ok

          {r["tag"] |> String.split("/") |> Enum.drop(2) |> Enum.join("/"),
           {gap["owner"], gap["record"]["file"]}}
        end

      # Keyed on the tag after its scenario, not its last segment: the two
      # RequestMetaInvalid rows share the last segment (MES-136, 29534).
      ss = &("sep-2575-" <> &1)
      sprint4 = {"MES-43", "docs/sprint_4_issues.md"}
      discover = {"MES-43", "lib/mcp/server/dispatch.ex"}

      assert owners == %{
               ss.(
                 "http-server-method-not-found-404-resources-subscribe/HttpServerMethodNotFound404resourcessubscribe"
               ) => sprint4,
               ss.(
                 "http-server-method-not-found-404-resources-unsubscribe/HttpServerMethodNotFound404resourcesunsubscribe"
               ) => sprint4,
               ss.("missing-capability-http-400/MissingCapabilityHttp400") => sprint4,
               ss.("server-rejects-undeclared-capability/ServerRejectsUndeclaredCapability") =>
                 sprint4,
               "sep-2164-data-uri/ResourcesNotFoundDataUri" => sprint4,
               ss.("http-server-header-mismatch-400/HttpServerHeaderMismatch400") =>
                 {"MES-62", "docs/conformance/report-2026-07-28.md"},
               ss.("http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-meta") =>
                 discover,
               ss.(
                 "http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-protocol-version"
               ) => discover,
               ss.(
                 "http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-client-capabilities"
               ) => discover,
               ss.("http-server-unsupported-version-400/HttpServerUnsupportedVersion400") =>
                 discover,
               ss.("request-meta-invalid-missing-protocol-version/RequestMetaInvalid") =>
                 discover,
               ss.("request-meta-invalid-missing-client-capabilities/RequestMetaInvalid") =>
                 discover,
               ss.("server-unsupported-version-error/ServerUnsupportedVersionError") => discover
             }
    end

    # The closure rule, applied to D2a-ii with its own catalogue. lands_when is
    # derived from the cited records alone (sdk_gap.owner_record, read with the
    # row's ruling where a condition names ruled questions, and depends_on_fix),
    # then held against lands_when and the remedy's tokens, both
    # ways; every comment an owner_record names must be a catalogued phrase, and
    # every catalogued phrase it names must derive a condition for the row.
    test "D2a-ii's remedies state exactly the landing conditions their rows cite",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      conds = record["landing_conditions"]["conditions"]
      assert d2aii_closure_defects(d2aii_rows(inputs), conds) == []
    end

    test "D2a-ii's landing-condition catalogue is exactly the pinned one", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]

      pinned =
        for {id, c} <- record["landing_conditions"]["conditions"],
            into: %{},
            do:
              {id,
               {c["owner_record_phrase"], c["depends_on_fix_tag"], c["ruled_questions"],
                c["either"] == true, c["remedy_token"]}}

      r2 =
        "oc:server/server-stateless/sep-2575-http-server-method-not-found-404/HttpServerMethodNotFound404"

      assert pinned == %{
               "d4a_fix_sdk_r2" =>
                 {"comment 29410 (a)", r2, nil, false, "(D4a fix_sdk R2, depends_on_fix)"},
               "mes43_29490" => {"comment 29490", nil, nil, false, "(MES-43 comment 29490)"},
               "mes62_r4" => {"MES-62 body", nil, nil, false, "(MES-62 body, R4)"},
               "mes43_29510_q1a" =>
                 {"comment 29510", nil, ["Q1a"], false, "(MES-43 29510, R1 / Q1a)"},
               "mes43_29510_q1b" =>
                 {"comment 29510", nil, ["Q1b"], false, "(MES-43 29510, R1 / Q1b)"},
               "mes43_29510_q1a_or_q1b" =>
                 {"comment 29510", nil, ["Q1a", "Q1b"], true, "(MES-43 29510, R1 / Q1a or Q1b)"},
               "mes43_29510_q2" =>
                 {"comment 29510", nil, ["Q2"], false, "(MES-43 29510, R3 / Q2)"}
             }
    end

    # MES-136, the dead-condition rule (MES-129 round 3): the four PO-question
    # ids lost their users to the ruling (MES-126 29509) and left the catalogue.
    # Each, reinstated as it stood at 5794619, is refused as unused. The entries
    # are held byte-exact from that commit's record (git show
    # 5794619:docs/conformance/adjudications/adjudication-D2a-ii-2026-07-28.json,
    # landing_conditions.conditions), statement included (CR 29538 N1).
    @retired_po_conditions %{
      "po_q1a" => %{
        "owner" => "PO",
        "po_questions" => ["Q1a"],
        "remedy_token" => "(PO Q1a, MES-126 29420)",
        "statement" =>
          "The PO answers Q1a YES or discover-only: a missing _meta or protocolVersion is -32602 on server/discover."
      },
      "po_q1b" => %{
        "owner" => "PO",
        "po_questions" => ["Q1b"],
        "remedy_token" => "(PO Q1b, MES-126 29420)",
        "statement" =>
          "The PO answers Q1b YES or discover-only: a missing clientCapabilities is -32602 on server/discover."
      },
      "po_q1a_or_q1b" => %{
        "owner" => "PO",
        "po_questions" => ["Q1a", "Q1b"],
        "either" => true,
        "remedy_token" => "(PO Q1a or Q1b, MES-126 29420)",
        "statement" =>
          "The PO answers Q1a or Q1b affirmatively: either makes a request with no _meta a rejection."
      },
      "po_q2" => %{
        "owner" => "PO",
        "po_questions" => ["Q2"],
        "remedy_token" => "(PO Q2, MES-126 29407)",
        "statement" =>
          "The PO answers Q2 YES: server/discover rejects an unsupported version with -32022 carrying data.supported and data.requested."
      }
    }

    test "each retired PO-question condition is refused as unused once reinstated",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      conds = record["landing_conditions"]["conditions"]
      rows = d2aii_rows(inputs)

      for {id, c} <- @retired_po_conditions do
        refute Map.has_key?(conds, id)

        assert d2aii_closure_defects(rows, Map.put(conds, id, c)) == [
                 {:catalogue, {:unused, [id]}}
               ],
               id
      end
    end

    # MES-136 (PM ratification 29534, Q1 (a)): the four 29510 conditions share
    # one owner_record phrase, so derives?/3 tells them apart by the row's
    # ruling. A row whose ruling names Q1a while lands_when says the Q1b id is
    # refused: the ruling derives the Q1a id. The unplanted row is the control.
    test "the D2a-ii closure refuses a ruling that disagrees with lands_when", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      conds = record["landing_conditions"]["conditions"]
      rows = d2aii_rows(inputs)

      [q1b] =
        for r <- rows,
            String.ends_with?(r["tag"], "missing-client-capabilities/RequestMetaInvalid"),
            do: r

      assert q1b["lands_when"] == ["mes43_29510_q1b"]
      planted = put_in(q1b, ["ruling", "questions"], ["Q1a"])
      got = d2aii_closure_defects([planted], conds)

      assert {q1b["tag"], {:lands_when, ["mes43_29510_q1a"], ["mes43_29510_q1b"]}} in got
      assert d2aii_closure_defects([q1b], Map.take(conds, ["mes43_29510_q1b"])) == []
    end

    # MES-136 (PM ratification 29534, Q1 (b)): the missing-meta row, whose
    # ruling is Q1a and Q1b with either, derives only the either-id, never the
    # single-question ids.
    test "the missing-meta row derives only the either-id of the 29510 conditions",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      conds = record["landing_conditions"]["conditions"]

      [meta] =
        for r <- d2aii_rows(inputs),
            String.ends_with?(r["tag"], "HttpServerMetaInvalid400#missing-meta"),
            do: r

      assert derived_conditions(meta, conds) == ["d4a_fix_sdk_r2", "mes43_29510_q1a_or_q1b"]
    end

    # MES-136 correction round 1 (CR 29538 B1, PM 29539): an owner_record that
    # names a catalogued phrase must derive a condition carrying it, so the
    # ruled_questions clause cannot let a row cite 29510 and land on none of its
    # conditions. P0 is row 25 unchanged, the control; P1 deletes its ruling and
    # strips its Q1b id and token; P2 sets its ruling's questions to [Q3], which
    # no condition names. Held at the closure unit's own entry point.
    test "the D2a-ii closure refuses an owner_record phrase that derives no condition",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      conds = record["landing_conditions"]["conditions"]
      rows = d2aii_rows(inputs)

      [row25] =
        for r <- rows,
            String.ends_with?(r["tag"], "HttpServerMetaInvalid400#missing-client-capabilities"),
            do: r

      assert row25["lands_when"] == ["d4a_fix_sdk_r2", "mes43_29510_q1b"]
      assert row25["sdk_gap"]["owner_record"] =~ "comment 29510"

      stripped =
        row25
        |> Map.put("lands_when", ["d4a_fix_sdk_r2"])
        |> Map.update!("remedy", &String.replace(&1, "(MES-43 29510, R1 / Q1b)", ""))

      p1 = Map.delete(stripped, "ruling")
      p2 = put_in(stripped, ["ruling", "questions"], ["Q3"])
      plant = fn p -> Enum.map(rows, &if(&1 == row25, do: p, else: &1)) end

      assert d2aii_closure_defects(plant.(row25), conds) == []

      for p <- [p1, p2] do
        assert d2aii_closure_defects(plant.(p), conds) == [
                 {row25["tag"], {:owner_record_not_derived, "comment 29510"}}
               ]
      end
    end

    # PM 29539: the owner_record clause over EVERY adjudication record. A record
    # with a catalogue runs it through its own derivation; a record without one
    # must cite no sdk_gap, or its owner_records would escape the rule. The
    # (row, catalogued phrase) pairs checked are counted and pinned per record.
    test "every owner_record phrase in every record derives a condition", %{inputs: inputs} do
      derivations = %{
        @d2ai => &d2ai_derived/2,
        @d2aii => &derived_conditions/2
      }

      checked =
        for f <- [@d4a, @d4b, @d2b, @d2ai, @d2aii], into: %{} do
          {:ok, record} = inputs.records[f]

          gapped =
            for s <- record["sections"],
                r <- s["rows"],
                is_binary(get_in(r, ["sdk_gap", "owner_record"])),
                do: r

          case get_in(record, ["landing_conditions", "conditions"]) do
            nil ->
              assert gapped == [], f
              {f, 0}

            conds ->
              derive = Map.fetch!(derivations, f)

              pairs =
                for r <- gapped do
                  owner_record = r["sdk_gap"]["owner_record"]

                  assert owner_record_not_derived(owner_record, conds, derive.(r, conds)) == [],
                         r["tag"]

                  conds
                  |> Enum.map(fn {_, c} -> c["owner_record_phrase"] end)
                  |> Enum.filter(&(is_binary(&1) and String.contains?(owner_record, &1)))
                  |> Enum.uniq()
                  |> length()
                end

              {f, Enum.sum(pairs)}
          end
        end

      assert checked == %{@d4a => 0, @d4b => 0, @d2b => 0, @d2ai => 8, @d2aii => 13}
    end

    # Deliverable (4): each new catalogue entry is refused once removed, and the
    # closure refuses an owner_record naming an uncatalogued record and a remedy
    # missing its token. Each plant names the row it reddens.
    test "the D2a-ii closure refuses a removed condition, an uncatalogued record, a missing token",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      conds = record["landing_conditions"]["conditions"]
      rows = d2aii_rows(inputs)

      for id <- Map.keys(conds) do
        users = for r <- rows, id in r["lands_when"], do: r["tag"]
        assert users != [], id
        got = d2aii_closure_defects(rows, Map.delete(conds, id))

        assert Enum.sort(Enum.uniq(for {t, _} <- got, t != :catalogue, do: t)) == Enum.sort(users),
               id
      end

      [blocked | _] =
        for r <- rows,
            is_binary(get_in(r, ["sdk_gap", "owner_record"])),
            r["sdk_gap"]["owner_record"] =~ "comment 29490",
            do: r

      stray =
        Enum.map(rows, fn r ->
          if r == blocked,
            do:
              update_in(
                r,
                ["sdk_gap", "owner_record"],
                &(&1 <> " See also MES-43 comment 29999.")
              ),
            else: r
        end)

      assert {blocked["tag"], {:uncatalogued, ["comment 29999"]}} in d2aii_closure_defects(
               stray,
               conds
             )

      tokenless =
        Enum.map(rows, fn r ->
          if r == blocked,
            do: Map.update!(r, "remedy", &String.replace(&1, "(MES-43 comment 29490)", "")),
            else: r
        end)

      assert {blocked["tag"], {:token, "mes43_29490"}} in d2aii_closure_defects(tokenless, conds)

      unused = Map.put(conds, "dead_condition", %{"remedy_token" => "(nobody)"})
      assert {:catalogue, {:unused, ["dead_condition"]}} in d2aii_closure_defects(rows, unused)
    end

    test "D2a-ii's emitting-site grouping is measured from the locator", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      tags = MapSet.new(d2aii_rows(inputs), & &1["tag"])
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

    # A7, by the amended rule (PM ratification on MES-130, 29491, Q5), over BOTH
    # slices: D2a-i's 16 come out unchanged, and every emission reading is used
    # by a scenario the counts alone cannot place, and by no other.
    test "null_passability over both slices is exactly what the amended rule computes",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      readings = record["null_control_statement"]["emission_readings"]
      null = json("docs/conformance/server-2026-07-28-null-control.json")["scenarios"]
      loc = for r <- json(@locator)["rows"], r["leg"] == "server", do: r

      {placed, needs_reading} = null_placements(null, loc, readings)

      assert needs_reading |> MapSet.new() == readings |> Map.keys() |> MapSet.new()

      for {rows, want} <- [{d2ai_rows(inputs), 16}, {d2aii_rows(inputs), 21}] do
        for r <- rows do
          [_, scenario, _, name_disc] = String.split(r["tag"], "/")
          [name | _] = String.split(name_disc, "#")
          passed = name in Map.fetch!(placed, scenario)
          assert Map.has_key?(r, "null_passability") == passed, r["tag"]

          if c = get_in(r, ["null_passability", "null_control"]) do
            assert A.verify(c, inputs.source_fun) == :ok
            assert c["bytes"] =~ ~s("artefact_dir": "server-#{scenario}-)
          end
        end

        assert Enum.count(rows, &Map.has_key?(&1, "null_passability")) == want
      end
    end

    test "the amended null rule refuses a reading that does not reconcile, and a missing one",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      readings = record["null_control_statement"]["emission_readings"]
      null = json("docs/conformance/server-2026-07-28-null-control.json")["scenarios"]
      loc = for r <- json(@locator)["rows"], r["leg"] == "server", do: r

      {placed, _} = null_placements(null, loc, readings)
      assert "WireSchemaValid" in placed["caching"]

      # Without caching's reading, its SUCCESS cannot be placed: no claim at all.
      {bare, _} = null_placements(null, loc, Map.delete(readings, "caching"))
      assert bare["caching"] == []

      # A reading that moves the SKIPPED onto the validator places the wrong row.
      wrong = put_in(readings, ["caching", "not_success"], %{"WireSchemaValid" => "SKIPPED"})
      {moved, _} = null_placements(null, loc, wrong)
      assert moved["caching"] == ["ResourcesReadCachingHints"]

      # A reading whose counts do not reconcile is no placement.
      skew = put_in(readings, ["tools-list", "not_emitted"], [])
      {skewed, _} = null_placements(null, loc, skew)
      assert skewed["tools-list"] == []
    end

    # A2d: the server universe from the LOCATOR (not a bucket view) reconciles
    # with bucket 2a and the matched checks, by arithmetic AND by set.
    test "D2a-ii's server-universe negative is measured, not held", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      [neg] = Enum.filter(record["negatives"], &(&1["id"] == "server_universe_reconciles"))

      u =
        for r <- json(@locator)["rows"], r["leg"] == "server", into: MapSet.new(), do: r["token"]

      server = fn view ->
        for r <- json(view)["rows"],
            String.starts_with?(r["tag"], "oc:server/"),
            into: MapSet.new(),
            do: r["tag"]
      end

      [a4, b4, a5, esc, two] = Enum.map([@v4a, @v4b, @v5a, @ves, @v2a], server)
      matched = Enum.reduce([a4, b4, a5, esc], &MapSet.union/2)

      cells =
        for c <- json(@crosswalk)["cells"],
            String.starts_with?(c["tag"], "oc:server/"),
            into: MapSet.new(),
            do: c["tag"]

      i = MapSet.new(d2ai_rows(inputs), & &1["tag"])
      ii = MapSet.new(d2aii_rows(inputs), & &1["tag"])

      assert neg["count"] == %{
               "server_universe" => MapSet.size(u),
               "bucket_2a" => MapSet.size(two),
               "d2a_i" => MapSet.size(i),
               "d2a_ii" => MapSet.size(ii),
               "matched" => MapSet.size(matched),
               "bucket_4a" => MapSet.size(a4),
               "bucket_4b" => MapSet.size(b4),
               "bucket_5a" => MapSet.size(a5),
               "escalated" => MapSet.size(esc),
               "overlap_4a_4b" => MapSet.size(MapSet.intersection(a4, b4))
             }

      assert MapSet.size(u) == MapSet.size(two) + MapSet.size(matched)

      assert MapSet.size(matched) ==
               MapSet.size(a4) + MapSet.size(b4) + MapSet.size(a5) + MapSet.size(esc) -
                 MapSet.size(MapSet.intersection(a4, b4))

      relations = %{
        "bucket_2a_and_matched_disjoint" => MapSet.disjoint?(two, matched),
        "bucket_2a_union_matched_equals_universe" => MapSet.union(two, matched) == u,
        "matched_equals_crosswalk_server_cells" => matched == cells,
        "slices_partition_bucket_2a" => MapSet.union(i, ii) == two and MapSet.disjoint?(i, ii)
      }

      assert neg["set_relations"] == relations
      assert Enum.all?(Map.values(relations))
      assert neg["overlap"] == a4 |> MapSet.intersection(b4) |> Enum.sort()
    end

    # The covered_elsewhere universe, recomputed from the register with the
    # needle pinned HERE, not read from the record it checks.
    test "D2a-ii's covered-elsewhere universe is measured from the register", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d2aii]
      [neg] = Enum.filter(record["negatives"], &(&1["id"] == "covered_elsewhere_universe"))
      assert neg["needle"] == Regex.source(@d2aii_needle)
      assert neg["units"] == non_etcc_units(@d2aii_needle)
      assert length(neg["units"]) == 36

      for r <- d2aii_rows(inputs),
          u <- r["covered_elsewhere"]["units"] || [] do
        assert u["register_key"] in neg["units"]
        assert A.verify(u["test"], inputs.source_fun) == :ok
      end
    end

    # MES-120's K1: a record under docs/conformance/ is inside G31, and a file
    # added after G31's baseline may carry no pending figure.
    for record <- [@d4a, @d4b, @d2b, @d2ai, @d2aii] do
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

    test "the rows the ownership check skips are exactly bucket 2b's and both bucket-2a slices, each in its own record",
         %{inputs: inputs} do
      assert skip_pin(inputs.records) == :ok
      {_, skipped} = ownership_split(inputs.records)
      assert length(skipped) == 15 + 30 + 48
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
          for(vr <- selected(json(@v2a)["rows"], @d2ai_selector), do: {@d2ai, @v2a, A.key(vr)}) ++
          for(vr <- selected(json(@v2a)["rows"], @d2aii_selector), do: {@d2aii, @v2a, A.key(vr)})
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

  defp d2aii_rows(inputs) do
    {:ok, record} = inputs.records[@d2aii]
    [%{"rows" => rows}] = record["sections"]
    rows
  end

  # :ok, or the keys in BOTH slices, or the view keys in NEITHER. Computed over
  # the view, so a row the view does not project cannot hide in either answer.
  defp partition(i_rows, ii_rows, view_rows) do
    i = MapSet.new(i_rows, &A.key/1)
    ii = MapSet.new(ii_rows, &A.key/1)
    view = MapSet.new(view_rows, &A.key/1)

    cond do
      not MapSet.disjoint?(i, ii) ->
        {:error, {:overlap, i |> MapSet.intersection(ii) |> Enum.sort()}}

      MapSet.union(i, ii) != view ->
        {:error, {:gap, view |> MapSet.difference(MapSet.union(i, ii)) |> Enum.sort()}}

      true ->
        :ok
    end
  end

  @earners ~w(sdk adapter none_null_passable)

  # The tags of SUCCESS rows whose why_green is absent, names no known earner,
  # carries no statement, or (for an SDK or adapter green) carries no citation
  # that holds its bytes. An SDK green must also cite code under lib/: a claim
  # that the SDK earned it is a claim about the SDK's bytes (MES-130 29500, B1).
  defp d2aii_why_green_defects(rows, source_fun) do
    for r <- rows,
        List.last(census_echo(r)) == "SUCCESS",
        not d2aii_why_green_ok?(r["why_green"], source_fun),
        do: r["tag"]
  end

  defp d2aii_why_green_ok?(%{"earned_by" => e, "statement" => s} = w, source_fun)
       when e in @earners and is_binary(s) and s != "" do
    cites = A.collect(w)

    Enum.all?(cites, &(A.verify(&1, source_fun) == :ok)) and
      (e == "none_null_passable" or cites != []) and
      (e != "sdk" or Enum.any?(cites, &String.starts_with?(&1["file"] || "", "lib/")))
  end

  defp d2aii_why_green_ok?(_, _), do: false

  # The closure rule over a catalogue: [{tag, why}] for every row whose derived
  # conditions differ from lands_when, whose remedy's tokens differ from
  # lands_when, whose owner_record names a comment no catalogue phrase is, whose
  # owner_record names a catalogued phrase none of whose conditions is derived
  # (so the derivation cannot ignore an owner_record: 29491 Q2, kept true by
  # MES-136 correction round 1 after CR 29538 B1), or that is governed
  # (blocked, po or depends_on_fix) exactly when lands_when is empty; plus
  # {:catalogue, {:unused, ids}} for conditions no row uses.
  defp d2aii_closure_defects(rows, conds) do
    used = rows |> Enum.flat_map(& &1["lands_when"]) |> MapSet.new()
    unused = for id <- Map.keys(conds), id not in used, do: id
    catalogue = if unused == [], do: [], else: [{:catalogue, {:unused, Enum.sort(unused)}}]
    Enum.flat_map(rows, &closure_row_defects(&1, conds)) ++ catalogue
  end

  defp closure_row_defects(r, conds) do
    owner_record = get_in(r, ["sdk_gap", "owner_record"])
    lw = r["lands_when"]

    derived = derived_conditions(r, conds)

    tokens =
      for {id, c} <- conds,
          String.contains?(r["remedy"] || "", c["remedy_token"]) != id in lw,
          do: {r["tag"], {:token, id}}

    uncat = uncatalogued(owner_record, conds)

    not_derived =
      for p <- owner_record_not_derived(owner_record, conds, derived),
          do: {r["tag"], {:owner_record_not_derived, p}}

    governed =
      r["disposition"] in ~w(blocked_on_sdk_gap po_decision_required) or
        Map.has_key?(r, "depends_on_fix")

    List.flatten([
      if(Enum.sort(derived) == lw,
        do: [],
        else: [{r["tag"], {:lands_when, Enum.sort(derived), lw}}]
      ),
      tokens,
      if(uncat == [], do: [], else: [{r["tag"], {:uncatalogued, uncat}}]),
      not_derived,
      if(governed == (lw != []), do: [], else: [{r["tag"], :ungoverned}])
    ])
  end

  # Every comment an owner_record names must be some condition's phrase.
  defp uncatalogued(nil, _conds), do: []

  defp uncatalogued(owner_record, conds) do
    phrases = for {_, c} <- conds, do: c["owner_record_phrase"]

    ~r/comment \d+(?: \([a-z]\))?/
    |> Regex.scan(owner_record)
    |> List.flatten()
    |> Enum.reject(&(&1 in phrases))
  end

  # D2a-i's derivation (MES-129 29472): phrase containment, and d4a_fix_sdk by
  # the depends_on_fix pointer.
  defp d2ai_derived(r, conds) do
    Enum.sort(
      for {id, c} <- conds,
          (c["owner_record_phrase"] && r["sdk_gap"] &&
             String.contains?(r["sdk_gap"]["owner_record"], c["owner_record_phrase"])) ||
            (id == "d4a_fix_sdk" and Map.has_key?(r, "depends_on_fix")),
          do: id
    )
  end

  # The catalogued phrases an owner_record names for which no condition carrying
  # that phrase is derived. Phrase containment derived every such condition
  # until ruled_questions narrowed it (MES-136); this restores "the derivation
  # cannot ignore an owner_record" for any record's catalogue and derivation.
  defp owner_record_not_derived(nil, _conds, _derived), do: []

  defp owner_record_not_derived(owner_record, conds, derived) do
    conds
    |> Enum.filter(fn {_, c} ->
      is_binary(c["owner_record_phrase"]) and
        String.contains?(owner_record, c["owner_record_phrase"])
    end)
    |> Enum.group_by(fn {_, c} -> c["owner_record_phrase"] end, &elem(&1, 0))
    |> Enum.reject(fn {_, ids} -> Enum.any?(ids, &(&1 in derived)) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp derived_conditions(r, conds) do
    owner_record = get_in(r, ["sdk_gap", "owner_record"])

    conds
    |> Enum.filter(fn {_, c} -> derives?(r, c, owner_record) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  # A condition naming ruled_questions shares its owner_record phrase with its
  # siblings (MES-136: four ids on MES-43 comment 29510), so the phrase derives
  # it only on a row whose ruling names exactly those questions, either or not.
  defp derives?(r, c, owner_record) do
    ruling = r["ruling"]

    (is_binary(c["owner_record_phrase"]) and is_binary(owner_record) and
       String.contains?(owner_record, c["owner_record_phrase"]) and
       (not is_list(c["ruled_questions"]) or
          (is_map(ruling) and ruling["questions"] == c["ruled_questions"] and
             ruling["either"] == true == (c["either"] == true)))) or
      (is_binary(c["depends_on_fix_tag"]) and
         get_in(r, ["depends_on_fix", "tag"]) == c["depends_on_fix_tag"])
  end

  # The amended null rule (MES-130, 29491 Q5): {scenario => the checks the null
  # run passed, scenarios the counts cannot place without a reading}. A reading
  # that does not reconcile with the census places nothing.
  defp null_placements(null, loc, readings) do
    results =
      json(@v2a)["rows"]
      |> Enum.map(&Enum.at(String.split(&1["tag"], "/"), 1))
      |> Enum.uniq()
      |> Enum.map(&null_placement(&1, null, loc, Map.get(readings, &1, %{})))

    {Map.new(results, fn {s, p, _} -> {s, p} end), for({s, _, true} <- results, do: s)}
  end

  defp null_placement(s, null, loc, rd) do
    [sc] = Enum.filter(null, &String.starts_with?(&1["artefact_dir"] || "", "server-#{s}-"))
    names = for r <- loc, r["scenario"] == s, do: r["name"]
    failed = for f <- sc["failed_checks"] || [], do: f["name"]
    placed = place(sc["checks"], names, failed, rd["not_emitted"] || [], rd["not_success"] || %{})
    {s, placed || [], place(sc["checks"], names, failed, [], %{}) == nil}
  end

  defp place(c, names, failed, not_emitted, not_success) do
    candidates = ((names -- failed) -- not_emitted) -- Map.keys(not_success)
    other = for k <- ~w(SKIPPED INFO), c[k] > 0, into: %{}, do: {k, c[k]}

    if length(names) - length(not_emitted) == c["total"] and
         length(failed) == c["FAILURE"] + c["WARNING"] and
         Enum.frequencies(Map.values(not_success)) == other and
         length(candidates) == c["SUCCESS"],
       do: Enum.uniq(candidates)
  end

  defp selected(view_rows, %{"field" => f, "segment" => i, "starts_with" => p}) do
    Enum.filter(view_rows, fn r ->
      r[f] |> String.split("/") |> Enum.at(i) |> Kernel.||("") |> String.starts_with?(p)
    end)
  end

  defp selected(view_rows, %{"field" => f, "segment" => i, "not_starts_with" => p}) do
    Enum.reject(view_rows, fn r ->
      r[f] |> String.split("/") |> Enum.at(i) |> Kernel.||("") |> String.starts_with?(p)
    end)
  end

  defp selector_equality(rows, view_rows, selector) do
    got = rows |> Enum.map(&A.key/1) |> Enum.sort()
    want = view_rows |> selected(selector) |> Enum.map(&A.key/1) |> Enum.sort()

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
  defp mrtr_non_etcc_units, do: non_etcc_units(@mrtr_needle)

  defp non_etcc_units(needle) do
    json("docs/conformance/etcc-register.json")["rows"]
    |> Enum.group_by(& &1["file"])
    |> Enum.flat_map(fn {file, rows} -> non_etcc_units(file, rows, needle) end)
    |> Enum.sort()
  end

  defp non_etcc_units(file, rows, needle) do
    src = file |> File.read!() |> String.split("\n")
    starts = rows |> Enum.map(& &1["line"]) |> Enum.sort()

    for r <- rows,
        r["label"] != "ET-CC",
        stop = Enum.find(starts, length(src) + 1, &(&1 > r["line"])) - 1,
        body = src |> Enum.slice((r["line"] - 1)..(stop - 1)//1) |> Enum.join("\n"),
        Regex.match?(needle, body),
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

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
  alias Mix.Tasks.Conformance.Adjudications, as: Render

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

  # MES-135 K1-R2 (CR 29680): the AUDITED set of row pairs whose contents (every
  # field but member, claim, tag and echo) exchange and still audit CLEAN. At
  # MES-135 CR ran all 5778 pairs of the 108 committed rows through A.audit and
  # found 481 CLEAN pairs in 8 cliques. At MES-138 (R3-1) the literal below is
  # pasted from the output of `mix run conformance/controls/adjudications_controls.exs
  # swap-audit`, never from the unit's own computed set: all 9453 pairs of the
  # 138 committed rows, 0 no-ops, 482 CLEAN, exactly the pairs within these 9
  # cliques (30, 9, 3, 3, 2, 2, 2, 2, 2 rows: 435 + 36 + 3 + 3 + 5 * 1 = 482).
  # The one new pair is D1's two ExtensionsTest doctests of one directive. At
  # MES-141 `swap-audit touching` the D1-server-i record audited its 8892 pairs,
  # 0 no-ops, 55 CLEAN: one new clique of 11, the for-generated W-1 rows, which
  # share one generated test's window (the shared-anchor residual), appended as
  # printed; the 482 untouched pairs are kept (fixture − audited: 0). Ids
  # are `{record basename, member, tag}`; the cliques are the set, written
  # compactly.
  @k1r_stateless "MCP.Transport.StreamableHTTPStatelessTest/test initialize is gone → -32022; ping/logging.setLevel → -32601"
  @k1r_dispatch "MCP.Server.DispatchTest/test ping and logging/setLevel are removed → method not found (-32601)"
  @k1r_clean_cliques [
    [
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-basic-elicitation/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-basic-list-roots/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-basic-sampling/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-capability-check/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-ignore-extra-params/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-missing-input-response/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-multi-round/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-multiple-input-requests/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-non-tool-request/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-result-type/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-tampered-state/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-unsupported-methods/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-i-2026-07-28.json", nil,
       "oc:server/input-required-result-validate-input/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/caching/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/completion-complete/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/prompts-get-embedded-resource/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/prompts-get-simple/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/prompts-get-with-args/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/prompts-get-with-image/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/prompts-list/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/resources-list/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/resources-read-binary/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/resources-read-text/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/resources-templates-read/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/sep-2164-resource-not-found/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/tools-call-audio/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/tools-call-error/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/tools-call-mixed-content/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/tools-call-with-progress/wire-schema-valid/WireSchemaValid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/tools-list/wire-schema-valid/WireSchemaValid"}
    ],
    [
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-charset/ClientRejectsInvalidTool_invalid_colon_in_name"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-charset/ClientRejectsInvalidTool_invalid_control_char_name"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-charset/ClientRejectsInvalidTool_invalid_non_ascii_name"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-charset/ClientRejectsInvalidTool_invalid_space_in_name"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-not-empty/ClientRejectsInvalidTool_invalid_empty_header"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-primitive-only/ClientRejectsInvalidTool_invalid_array_header"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-primitive-only/ClientRejectsInvalidTool_invalid_null_header"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-unique/ClientRejectsInvalidTool_invalid_duplicate_diff_case"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-invalid-tool-headers/sep-2243-x-mcp-header-unique/ClientRejectsInvalidTool_invalid_duplicate_same_case"}
    ],
    [
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-client-capabilities"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-meta"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-protocol-version"}
    ],
    [
      {"adjudication-D4a-2026-07-28.json", @k1r_stateless,
       "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-initialize/HttpServerMethodNotFound404initialize"},
      {"adjudication-D4b-2026-07-28.json", @k1r_stateless,
       "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-logging-setlevel/HttpServerMethodNotFound404loggingsetLevel"},
      {"adjudication-D4b-2026-07-28.json", @k1r_stateless,
       "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-ping/HttpServerMethodNotFound404ping"}
    ],
    [
      {"adjudication-D1-nd-CU-2026-07-28.json",
       "MCP.Protocol.ExtensionsTest/doctest MCP.Protocol.Extensions.from_meta/1 (8)",
       "oc:none/no-oc-scenario/extensions-doctest-inbound-read"},
      {"adjudication-D1-nd-CU-2026-07-28.json",
       "MCP.Protocol.ExtensionsTest/doctest MCP.Protocol.Extensions.from_meta/1 (9)",
       "oc:none/no-oc-scenario/extensions-doctest-nil-envelope"}
    ],
    [
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-resources-subscribe/HttpServerMethodNotFound404resourcessubscribe"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-resources-unsubscribe/HttpServerMethodNotFound404resourcesunsubscribe"}
    ],
    [
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/server-stateless/sep-2575-request-meta-invalid-missing-client-capabilities/RequestMetaInvalid"},
      {"adjudication-D2a-ii-2026-07-28.json", nil,
       "oc:server/server-stateless/sep-2575-request-meta-invalid-missing-protocol-version/RequestMetaInvalid"}
    ],
    [
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-standard-headers/sep-2243-client-includes-standard-headers/ClientMcpMethodHeader_prompts_get"},
      {"adjudication-D2b-2026-07-28.json", nil,
       "oc:client/http-standard-headers/sep-2243-client-includes-standard-headers/ClientMcpMethodHeader_resources_read"}
    ],
    [
      {"adjudication-D4b-2026-07-28.json", @k1r_dispatch,
       "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-logging-setlevel/HttpServerMethodNotFound404loggingsetLevel"},
      {"adjudication-D4b-2026-07-28.json", @k1r_dispatch,
       "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-ping/HttpServerMethodNotFound404ping"}
    ],
    [
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value array survives to the wire",
       "oc:none/no-oc-scenario/structured-content-array-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value empty array survives to the wire",
       "oc:none/no-oc-scenario/structured-content-empty-array-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value empty object survives to the wire",
       "oc:none/no-oc-scenario/structured-content-empty-object-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value empty string survives to the wire",
       "oc:none/no-oc-scenario/structured-content-empty-string-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value false survives to the wire",
       "oc:none/no-oc-scenario/structured-content-false-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value float survives to the wire",
       "oc:none/no-oc-scenario/structured-content-float-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value null survives to the wire",
       "oc:none/no-oc-scenario/structured-content-null-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value object survives to the wire",
       "oc:none/no-oc-scenario/structured-content-object-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value string survives to the wire",
       "oc:none/no-oc-scenario/structured-content-string-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value true survives to the wire",
       "oc:none/no-oc-scenario/structured-content-true-survives"},
      {"adjudication-D1-server-i-2026-07-28.json",
       "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value zero survives to the wire",
       "oc:none/no-oc-scenario/structured-content-zero-survives"}
    ]
  ]
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

    # MES-126's per-ticket pin (cited in MES-135's body as :63-70; at :92-98 by
    # 91a3320). Since MES-135 a dropped section is refused by G32 itself
    # (owed_unadjudicated); this stays as the literal of D4a's two closures.
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
        for f <- records_in_dir("."), into: %{} do
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

      # Pinned for the records that carry landing conditions; every other record
      # is walked with no edit here and must check nothing (MES-135 N3).
      assert Map.take(checked, [@d2ai, @d2aii]) == %{@d2ai => 8, @d2aii => 13}
      assert checked |> Map.drop([@d2ai, @d2aii]) |> Map.values() |> Enum.uniq() == [0]
      assert Map.keys(checked) == inputs.walk
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
    # MES-135 N3: derived from the directory, so a new record is walked here
    # without anyone editing a list.
    for record <-
          "docs/conformance/adjudications"
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(&("docs/conformance/adjudications/" <> &1))
          |> Enum.sort() do
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

    # MES-135 (29433(a); PM Q4) moved this into G32: it now walks every
    # citation in the whole record, so the gate-5 unit that held the top-level
    # ones (MES-127) is entailed and re-cut. What stays is the population.
    # MES-138 added one outside the rows: the claim-unmatched section's
    # handed_over_from.view_label. MES-139 adds none outside the rows; inside
    # them, 35 et_test (repository) and 39 harness (12 oc_counterpart sites,
    # 12 predicates, 15 near misses). MES-140 adds none outside the rows;
    # inside them, 36 et_test and 1 doctest_body (repository) and 15 harness
    # (3 oc_counterpart sites, 3 predicates, 9 near misses). MES-141 adds,
    # outside the rows, 1 repository (unscored_server_scenarios.listed_at) and
    # 12 harness (5 in unscored_server_scenarios.sites, 7 in
    # wire_schema_valid.sites; both from correction round 1, 29914); inside
    # them, 39 et_test (repository) and 190 harness (137 in oc_counterpart: 35
    # sites, 35 predicates, 32 probes and 35 inside `also`; 44 in oc_unscored;
    # 2 near misses; 7 in unscored_near_miss). MES-142 adds, outside the rows,
    # 1 repository (known_limits.at) and 8 harness (unscored_server_scenarios.sites);
    # inside them, 37 et_test (repository) and 100 harness (94 in oc_counterpart:
    # 22 sites, 22 predicates, 20 probes and 30 inside `also`; 4 in oc_unscored;
    # 2 near misses).
    test "G32 walks the citations outside the rows: 12 repository and 28 harness at this tip",
         %{inputs: inputs, result: %{report: r}} do
      outside =
        for {_, {:ok, doc}} <- inputs.records,
            c <-
              A.collect(%{doc | "sections" => Enum.map(doc["sections"], &Map.delete(&1, "rows"))}),
            do: c

      assert Enum.count(outside, &Map.has_key?(&1, "lines")) == 12
      assert Enum.count(outside, &Map.has_key?(&1, "harness_sha256")) == 28

      assert r["repo_citations_found"] == 600 and
               r["harness_citations_not_verified_in_gate_5"] == 629
    end

    test "G32 refuses a drifted top-level citation, with no edge key", %{inputs: inputs} do
      {:ok, doc} = inputs.records[@d4a]
      [c | _] = A.collect(Map.delete(doc, "sections")) |> Enum.filter(&Map.has_key?(&1, "lines"))
      shifted = %{c | "lines" => Enum.map(c["lines"], &(&1 + 1))}

      planted =
        put_in(
          inputs.records[@d4a],
          {:ok, Map.new(doc, fn {k, v} -> {k, replace_citation(v, c, shifted)} end)}
        )

      assert [%{kind: :citation_drift, file: @d4a, key: nil}] = A.audit(planted).defects
    end

    # MES-135 K1 moved MES-127's gate-5 ownership check into G32
    # (et_test_foreign), so the gate-5 copy and its skip pin are re-cut: G32
    # now requires, of EVERY row, that a member row's et_test lies inside the
    # member's own test and that a member-less row carries `et_test: null`.
    # What stays here is the population the tie runs over, at this tip.
    # MES-138 added 30 member rows (21 bucket-1, 9 claim-unmatched); MES-139
    # adds 35 (bucket-1); MES-140 adds 36 (bucket-1); MES-141 adds 39 (bucket-1,
    # eleven of them for-generated, owned under Q-C); MES-142 adds 37 (bucket-1).
    test "the et_test tie's population: 192 member rows, 93 member-less rows with et_test null",
         %{inputs: inputs} do
      rows = for {_, {:ok, doc}} <- inputs.records, s <- doc["sections"], r <- s["rows"], do: r
      {owned, memberless} = Enum.split_with(rows, &is_binary(&1["member"]))

      assert length(owned) == 192 and length(memberless) == 93
      assert Enum.all?(memberless, &is_nil(&1["et_test"]))
      assert Enum.all?(owned, &(A.et_test_owner(&1, inputs.source_fun) == :ok))
    end

    # MES-135 K1-R (CR 29672): a KNOWN RESIDUAL, pinned so that a later
    # tightening of the check tie turns this unit red and is seen. On a
    # bucket-2 row the check tie is the only tie (no member, so et_test null;
    # echo {}; no R<n> root cause), and check_foreign accepts ANY locator site
    # of the token, which sites are shared. So two D2a-ii rows can exchange
    # every field but member, claim, tag and echo, and G32 audits CLEAN.
    test "KNOWN RESIDUAL: two bucket-2 rows exchanging every field but the key and echo audit CLEAN",
         %{inputs: inputs} do
      tags = ~w(oc:server/caching/wire-schema-valid/WireSchemaValid
                oc:server/tools-call-with-progress/wire-schema-valid/WireSchemaValid)

      keep = ~w(member claim tag echo)
      rows = d2aii_rows(inputs)
      [a, b] = Enum.map(tags, fn t -> Enum.find(rows, &(&1["tag"] == t)) end)

      # Not a no-op: the two rows differ on what is exchanged.
      assert {a["disposition"], b["disposition"]} == {"extend_to_match", "build_test"}
      differs = for k <- Map.keys(a) -- keep, a[k] != b[k], do: k

      assert differs ==
               ~w(check disposition extend_target null_passability oc_status_at_accepted_run remedy root_cause why_green)

      assert Enum.all?(
               [a, b],
               &(is_nil(&1["member"]) and is_nil(&1["et_test"]) and &1["echo"] == %{})
             )

      swap = fn x, y -> Map.merge(y, Map.take(x, keep)) end

      planted =
        update_in(inputs.records[@d2aii], fn {:ok, doc} ->
          {:ok,
           update_in(doc, ["sections", Access.at(0), "rows"], fn rs ->
             Enum.map(rs, fn
               ^a -> swap.(a, b)
               ^b -> swap.(b, a)
               r -> r
             end)
           end)}
        end)

      assert planted.records[@d2aii] != inputs.records[@d2aii]
      assert A.audit(planted).defects == []
    end

    # The figures the moduledoc's K1-R/K1-R2 residual states, measured here so
    # that they cannot go stale silently: a moved figure means the moduledoc
    # moves. The CLEAN-swap set is computed by its predicate, over EVERY
    # committed row: (a) the check tie does not separate them (each row's check
    # spans overlap a site of the other's token, or both rows are `oc:none/`),
    # and (b) the et_test tie does not separate them (both nil, or each row's
    # et_test is owned by the other's member). It is asserted EQUAL, as a set
    # of pairs, to the audited set @k1r_clean_cliques records. Auditing each
    # exchange here instead (all 9453 pairs at MES-138) takes about 14 minutes
    # at 32-way, so that sweep runs off gate 5, as the controls' `swap-audit`
    # mode, and the predicate is what gate 5 re-runs. Any row, tie or wording
    # change that moves the set turns this red, whichever side it moves, and
    # the failure prints the difference both ways.
    test "K1-R/K1-R2's figures: 11 of 143 sites shared, 82 of 173 tokens only on shared sites, 60 rows (48 bucket-2) tie only through one; the CLEAN-swap set equals the audited 537 pairs (477 bucket-2 + 60 member)",
         %{inputs: inputs} do
      {:ok, loc} = inputs.locator
      ov = fn [p, q], [r, t] -> max(p, r) < min(q, t) end

      by_site =
        for {t, ss} <- loc, s <- ss, reduce: %{} do
          acc -> Map.update(acc, s, MapSet.new([t]), &MapSet.put(&1, t))
        end

      shared = for {s, ts} <- by_site, MapSet.size(ts) > 1, into: MapSet.new(), do: s
      assert {MapSet.size(shared), map_size(by_site)} == {11, 143}

      assert {Enum.count(loc, fn {_, ss} -> ss != [] and Enum.all?(ss, &(&1 in shared)) end),
              map_size(loc)} == {82, 173}

      spans = fn r ->
        for c <- A.collect(r["check"]), Map.has_key?(c, "harness_sha256"), do: c["byte_span"]
      end

      ties? = fn r, tag ->
        Enum.any?(spans.(r), fn s -> Enum.any?(Map.get(loc, tag, []), &ov.(s, &1)) end)
      end

      rows =
        for {f, {:ok, doc}} <- inputs.records,
            s <- doc["sections"],
            r <- s["rows"],
            do: {s["view"], {Path.basename(f), r["member"], r["tag"]}, r}

      only_shared =
        for {v, _, r} <- rows,
            sites =
              Enum.filter(Map.get(loc, r["tag"], []), fn st ->
                Enum.any?(spans.(r), &ov.(&1, st))
              end),
            sites != [] and Enum.all?(sites, &(&1 in shared)),
            do: v

      assert length(rows) == 285 and Enum.count(rows, &(elem(&1, 0) =~ "/bucket-2")) == 93
      assert {length(only_shared), Enum.count(only_shared, &(&1 =~ "/bucket-2"))} == {60, 48}

      # The ids name rows uniquely, so a pair of ids is a pair of rows.
      ids = Enum.map(rows, &elem(&1, 1))
      assert length(Enum.uniq(ids)) == 285

      # (a) the check tie does not separate them: mutual through the locator, or
      # both rows on no OC check (`oc:none/`, no span either way; MES-138).
      none? = fn r -> String.starts_with?(r["tag"], "oc:none/") end

      # (b) the et_test tie does not separate them: both member-less, or each
      # row's et_test is owned by the OTHER row's member (the same member test,
      # or two doctests of one directive; MES-138 S2a).
      owned? = fn et, member ->
        A.et_test_owner(%{"member" => member, "et_test" => et}, inputs.source_fun) == :ok
      end

      et_same? = fn x, y ->
        case {x["member"], y["member"]} do
          {nil, nil} ->
            true

          {a, b} when is_binary(a) and is_binary(b) ->
            owned?.(x["et_test"], b) and owned?.(y["et_test"], a)

          _ ->
            false
        end
      end

      mutual =
        for {{_, i, x}, n} <- Enum.with_index(rows),
            {{_, j, y}, m} <- Enum.with_index(rows),
            n < m,
            (ties?.(x, y["tag"]) and ties?.(y, x["tag"])) or (none?.(x) and none?.(y)),
            do: {MapSet.new([i, j]), et_same?.(x, y)}

      computed = for {pair, true} <- mutual, into: MapSet.new(), do: pair

      audited =
        for clique <- @k1r_clean_cliques,
            i <- clique,
            j <- clique,
            i < j,
            into: MapSet.new(),
            do: MapSet.new([i, j])

      # Every audited id is a committed row: a typo cannot shrink the set silently.
      assert Enum.all?(List.flatten(@k1r_clean_cliques), &(&1 in ids))
      assert MapSet.size(audited) == 537
      # On failure, the difference both ways, not the two whole sets (R3-1 (b)).
      assert {MapSet.difference(computed, audited), MapSet.difference(audited, computed)} ==
               {MapSet.new(), MapSet.new()}

      # MES-139's 35 oc:none rows pair through (a) with the 30 oc:none rows
      # before them and with each other: 35 * 30 + C(35, 2) = 1645 more mutual
      # pairs (986 -> 2631), every one separated by the et_test tie, so the
      # CLEAN set stays 482 (swap-audit touching the record: 5425 pairs, 0 CLEAN).
      # MES-140's 36 add 36 * 65 + C(36, 2) = 2970 more (2631 -> 5601), every
      # one separated by the et_test tie: its one doctest's directive line is
      # shared by no committed row, so the CLEAN set stays 482. MES-141's 39 add
      # 39 * 101 + C(39, 2) = 4680 more (5601 -> 10281); the et_test tie
      # separates all but the 55 within the eleven for-generated W-1 rows, which
      # share one window (482 -> 537). MES-142's 37 add 37 * 140 + C(37, 2) = 5846
      # more (10281 -> 16127), every one separated by the et_test tie (no two of
      # its members share a test window), so the CLEAN set stays 537.
      assert {length(mutual), length(mutual) - MapSet.size(computed)} == {16_127, 15_590}

      member_pairs = Enum.filter(computed, fn p -> Enum.all?(p, &is_binary(elem(&1, 1))) end)

      assert {MapSet.size(computed) - length(member_pairs), length(member_pairs)} == {477, 60}
      member_rows = member_pairs |> Enum.flat_map(&MapSet.to_list/1) |> Enum.uniq()

      assert {length(member_rows), Enum.frequencies(Enum.map(member_rows, &elem(&1, 0))),
              member_rows |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()} ==
               {18,
                %{
                  "adjudication-D1-nd-CU-2026-07-28.json" => 2,
                  "adjudication-D1-server-i-2026-07-28.json" => 11,
                  "adjudication-D4a-2026-07-28.json" => 1,
                  "adjudication-D4b-2026-07-28.json" => 4
                },
                Enum.sort([
                  @k1r_stateless,
                  @k1r_dispatch,
                  "MCP.Protocol.ExtensionsTest/doctest MCP.Protocol.Extensions.from_meta/1 (8)",
                  "MCP.Protocol.ExtensionsTest/doctest MCP.Protocol.Extensions.from_meta/1 (9)"
                  | for(
                      l <-
                        ~w(false true zero float string array object null) ++
                          ["empty string", "empty array", "empty object"],
                      do:
                        "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value " <>
                          l <> " survives to the wire"
                    )
                ])}
    end

    # MES-135 K1-R2 (CR 29680): the member half of the residual, pinned like
    # K1-R's. The et_test tie asks only that the window lie in the row's OWN
    # member's test; D4a's initialize row and D4b's ping row share one member
    # test, and their check ties are mutual, so the cross-record exchange of
    # every field but the key and echo audits CLEAN.
    test "KNOWN RESIDUAL: D4a's initialize row and D4b's ping row, on one member test, exchange every field but the key and echo across records and audit CLEAN",
         %{inputs: inputs} do
      keep = ~w(member claim tag echo)

      init =
        "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-initialize/HttpServerMethodNotFound404initialize"

      ping =
        "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-ping/HttpServerMethodNotFound404ping"

      find = fn file, tag ->
        {:ok, doc} = inputs.records[file]

        [r] =
          for s <- doc["sections"],
              r <- s["rows"],
              r["member"] == @k1r_stateless and r["tag"] == tag,
              do: r

        r
      end

      {a, b} = {find.(@d4a, init), find.(@d4b, ping)}

      # Not a no-op: the two rows differ on what is exchanged.
      assert {a["disposition"], b["disposition"]} == {"fix_sdk", "extend_test"}
      differs = for k <- Enum.uniq(Map.keys(a) ++ Map.keys(b)) -- keep, a[k] != b[k], do: k
      assert Enum.all?(~w(check disposition et_test root_cause), &(&1 in differs))

      swap = fn x, y -> Map.merge(y, Map.take(x, keep)) end

      put = fn inputs, file, from, to ->
        update_in(inputs.records[file], fn {:ok, doc} ->
          {:ok,
           update_in(doc["sections"], fn ss ->
             Enum.map(ss, fn s ->
               Map.update!(s, "rows", fn rs -> Enum.map(rs, &if(&1 == from, do: to, else: &1)) end)
             end)
           end)}
        end)
      end

      planted = inputs |> put.(@d4a, a, swap.(a, b)) |> put.(@d4b, b, swap.(b, a))

      assert planted.records[@d4a] != inputs.records[@d4a]
      assert planted.records[@d4b] != inputs.records[@d4b]
      assert A.audit(planted).defects == []
    end

    test "G32 refuses a member-less row that keeps an et_test, planted into D4a (et_test_foreign)",
         %{inputs: inputs} do
      planted =
        update_in(inputs.records[@d4a], fn {:ok, doc} ->
          {:ok,
           update_in(doc, ["sections", Access.at(0), "rows"], fn [r | rest] ->
             [Map.put(r, "member", nil) | rest]
           end)}
        end)

      kinds = planted |> A.audit() |> Map.fetch!(:defects) |> Enum.map(& &1.kind)
      assert :et_test_foreign in kinds
    end

    # G32's et_test_foreign supersedes this one (it requires the window to
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

      assert A.et_test_owner(r1, inputs.source_fun) == :ok
      swapped = Map.put(r1, "member", r3["member"])
      assert {:error, _} = A.et_test_owner(swapped, inputs.source_fun)
      renamed = Map.update!(r1, "member", &(&1 <> " (renamed)"))
      assert {:error, _} = A.et_test_owner(renamed, inputs.source_fun)
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

        assert {:error, {:window_outside_test, last}} = A.et_test_owner(plant, inputs.source_fun)
        assert last < to
      end
    end

    test "the et_test self-check refuses a window straddling two tests", %{inputs: inputs} do
      {:ok, record} = inputs.records[@d4b]
      [%{"rows" => [r1 | _]}] = record["sections"]
      plant = put_in(r1, ["et_test", "lines"], [88, 100])

      assert A.et_test_owner(plant, inputs.source_fun) == {:error, :window_crosses_a_test}
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
        A.et_test_owner(
          %{
            "member" => "M/" <> member,
            "et_test" => %{"file" => "test/src.exs", "lines" => lines, "bytes" => ""}
          },
          source_fun
        )
      end

      assert at.("test d block", [4, 5]) == :ok
      assert at.("test d block", [4, 6]) == {:error, {:window_outside_test, 5}}
      assert at.("test one", [8, 8]) == :ok
      assert at.("test one", [8, 9]) == {:error, {:window_outside_test, 8}}
    end

    # MES-138: a doctest member's window is its `doctest Target` directive line.
    test "the et_test self-check owns a doctest member by its directive line, and nothing else" do
      src = """
      defmodule M do
        use ExUnit.Case
        doctest Some.Target, import: true
        doctest Other.Target

        test "t" do
          assert true
        end
      end
      """

      source_fun = fn "test/src.exs" -> {:ok, src} end

      at = fn member, lines ->
        A.et_test_owner(
          %{
            "member" => member,
            "et_test" => %{"file" => "test/src.exs", "lines" => lines, "bytes" => ""}
          },
          source_fun
        )
      end

      dt = "M/doctest Some.Target.f/1 (3)"
      assert at.(dt, [3, 3]) == :ok
      assert at.("M/doctest Other.Target.g/2 (1)", [4, 4]) == :ok
      # Another directive's line, a two-line window, the wrong module, a test line.
      assert at.(dt, [4, 4]) == {:error, {:not_the_directive, "Some.Target"}}
      assert at.(dt, [3, 4]) == {:error, :doctest_window_is_one_line}
      assert at.("N/doctest Some.Target.f/1 (3)", [3, 3]) == {:error, :module}
      assert at.(dt, [6, 6]) == {:error, {:not_the_directive, "Some.Target"}}
      # A test member is still owned by its test, never by a directive.
      assert at.("M/test t", [7, 7]) == :ok
      assert {:error, _} = at.("M/test t", [3, 3])
    end

    # MES-141 Q-C ([authored 29813 | ratified 29816]): a test generated by
    # `for {label, _} <- [LITERAL list]` whose name interpolates the label is
    # owned under each name the literal list expands to, and under no other.
    # Every refusal names its guard.
    test "the et_test self-check owns a for-generated test under each expanded name, and refuses the rest by name" do
      src = ~S"""
      defmodule M do
        describe "d" do
          for {label, v} <- [{"a", 1}, {"b c", 2}] do
            test "#{label} ok", _ctx do
              assert unquote(v) > 0
            end
          end

          for {label, v} <- @cases do
            test "#{label} attr" do
              assert unquote(v)
            end
          end

          for {label, v} <- [{"a", 1}] do
            test "fixed name" do
              assert unquote(v)
            end
          end

          for {label, v} <- [{"a", 1}] do
            test "#{label} #{v} both" do
              assert true
            end
          end

          for {label, v} <- [{"a", 1}, {label_var(), 2}] do
            test "#{label} computed" do
              assert unquote(v)
            end
          end
        end

        for {label, _} <- [{"top", 1}] do
          test "#{label} level" do
            assert true
          end
        end
      end
      """

      source_fun = fn "test/src.exs" -> {:ok, src} end

      at = fn member, lines ->
        A.et_test_owner(
          %{
            "member" => "M/" <> member,
            "et_test" => %{"file" => "test/src.exs", "lines" => lines, "bytes" => ""}
          },
          source_fun
        )
      end

      # The positive case: both expanded names, qualified by the describe; and
      # a top-level generator, qualified by nothing.
      assert at.("test d a ok", [4, 6]) == :ok
      assert at.("test d b c ok", [4, 6]) == :ok
      assert at.("test top level", [35, 37]) == :ok
      # A label absent from the literal list: the expansion is named.
      assert at.("test d z ok", [4, 6]) == {:error, {:names, ["test d a ok", "test d b c ok"]}}
      # The unexpanded template is not a name either.
      assert {:error, {:names, _}} = at.(~S"test d #{label} ok", [4, 6])
      # A non-literal generator: a module attribute, and a list with a computed label.
      assert at.("test d a attr", [10, 12]) == {:error, :generator_not_literal}
      assert at.("test d a computed", [28, 30]) == {:error, :generator_not_literal}
      # A name without the interpolation, and one interpolating another binding.
      assert at.("test d fixed name", [16, 18]) == {:error, :name_does_not_interpolate_label}
      assert at.("test d a 1 both", [22, 24]) == {:error, :name_interpolates_other_than_label}
      # The window rules are unchanged: past the test's own `end` is refused.
      assert at.("test d a ok", [4, 7]) == {:error, {:window_outside_test, 6}}
    end

    # MES-126 ratified the first five; MES-127 (29430, Q1) added extend_test and
    # accept_bound; MES-128 (29444, Q1) added extend_to_match and build_test;
    # MES-129 (29460, Q1) added blocked_on_sdk_gap; MES-138 (29693, Q1) added
    # the D1 family.
    test "the closed disposition set is the one MES-126, MES-127, MES-128, MES-129 and MES-138 ratified" do
      assert A.dispositions() ==
               ~w(fix_sdk fix_conformance_adapter keep_design_publish_bound po_decision_required suite_defect_upstream extend_test accept_bound extend_to_match build_test blocked_on_sdk_gap genuine_extra_coverage redundant not_a_conformance_claim wrong_against_spec)

      assert A.build_levels() == ~w(pure_unit mock_transport plug live_http)
    end

    # MES-138 (29693, Q1-Q4): the D1 catalogues are pinned here, not declared
    # by the records they govern (MES-129 rule 3).
    test "the D1 catalogues are pinned: the family, its views, its routes, the echo fields, the view schemas" do
      assert A.d1_dispositions() ==
               ~w(genuine_extra_coverage redundant not_a_conformance_claim wrong_against_spec)

      assert A.d1_dispositions() -- A.dispositions() == []

      assert A.d1_views() == [
               "docs/conformance/buckets/bucket-1-2026-07-28.json",
               "docs/conformance/buckets/claim-unmatched-2026-07-28.json"
             ]

      assert A.routes() == %{"redundant" => "A3", "not_a_conformance_claim" => "A2"}

      assert A.echo_fields() ==
               ~w(shape verdicts bucket escalation_reason escalation_cause cg search_id the_search_that_found_none)

      assert A.view_schemas() == ~w(bucket-view/1 escalated-view/1 claim-unmatched-view/1)

      # Each D1 view is a real view file whose schema the guard admits.
      for v <- A.d1_views(), do: assert(json(v)["schema"] in A.view_schemas())
    end
  end

  # MES-135 K2 + N3: the universe of views owed a record, declared from the
  # bucket views directory, never from the records.
  describe "the universe of views owed a record" do
    @owed_views ~w(bucket-1 bucket-2a bucket-2b bucket-3 bucket-4a bucket-4b bucket-5a bucket-5b bucket-6 claim-unmatched escalated)
    # MES-138 closed claim-unmatched and deleted its @pending line.
    @closed_views ~w(bucket-2a bucket-2b bucket-4a bucket-4b claim-unmatched escalated)

    test "the anchor, the exclusions, the pending catalogue and the scan skip are pinned" do
      assert A.anchor() == {"docs/conformance/buckets", "*.json"}

      assert A.not_owed() |> Map.keys() |> Enum.sort() == [
               "docs/conformance/buckets/bucket-0-2026-07-28.json",
               "docs/conformance/buckets/roll-up-2026-07-28.json"
             ]

      assert Enum.all?(Map.values(A.not_owed()), &(is_binary(&1) and &1 != ""))

      assert A.pending() == %{
               "docs/conformance/buckets/bucket-1-2026-07-28.json" => "MES-143",
               "docs/conformance/buckets/bucket-3-2026-07-28.json" => "MES-144",
               "docs/conformance/buckets/bucket-5a-2026-07-28.json" => "MES-148",
               "docs/conformance/buckets/bucket-5b-2026-07-28.json" => "MES-146",
               "docs/conformance/buckets/bucket-6-2026-07-28.json" => "MES-144"
             }

      assert A.scan_population() == ~w(ls-files -z --cached --others --exclude-standard)
      # The file owed_unadjudicated's message tells an adding ticket to edit (B2).
      assert File.regular?(A.source_path())

      assert A.module_info(:compile)[:source]
             |> to_string()
             |> String.ends_with?("/" <> A.source_path())

      assert A.policy() == %{not_owed: A.not_owed(), pending: A.pending()}
    end

    test "the anchor listing is the directory, read independently of the guard",
         %{inputs: inputs} do
      {:ok, names} = File.ls("docs/conformance/buckets")

      independent =
        names
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&("docs/conformance/buckets/" <> &1))
        |> Enum.sort()

      assert inputs.anchor == independent
      assert length(independent) == 13
    end

    # Held both ways: the listing minus the exclusions EQUALS closed ∪ pending,
    # and the two are disjoint.
    test "owed = listing − exclusions = closed ⊔ pending, at this tip",
         %{inputs: inputs, result: %{report: r}} do
      short = fn v -> v |> Path.basename("-2026-07-28.json") end
      owed = inputs.anchor -- Map.keys(A.not_owed())

      assert Enum.map(owed, short) == @owed_views
      assert r["owed"] == length(owed)
      assert Enum.map(r["closed"], short) == @closed_views
      assert r["pending"] == A.pending()
      assert MapSet.disjoint?(MapSet.new(r["closed"]), MapSet.new(Map.keys(r["pending"])))
      assert Enum.sort(r["closed"] ++ Map.keys(r["pending"])) == owed
    end

    # The printed figure is asserted, not just printed.
    test "the task prints owed 11 — closed 6, pending 5, with each pending view's ticket",
         %{result: %{report: r}} do
      assert Render.views(r) ==
               "owed 11 — closed 6, pending 5: bucket-1 (MES-143), bucket-3 (MES-144), bucket-5a (MES-148), bucket-5b (MES-146), bucket-6 (MES-144)"

      assert Render.render(r, []) =~ "views         " <> Render.views(r)
    end

    test "no record lies outside the walk and nothing strays in the walk root",
         %{inputs: inputs} do
      assert inputs.outside == {:ok, []}
      assert inputs.strays == []
    end

    test "in a copied tree: an eleventh record is walked; a dropped section, a record outside the walk, a wrong schema and a stray are refused",
         %{} do
      tmp = copied_tree()
      on_exit(fn -> File.rm_rf!(tmp) end)

      real = A.load().source_fun
      load = fn -> %{A.load(root: tmp) | source_fun: real} end

      kinds = fn ->
        load.() |> A.audit() |> Map.fetch!(:defects) |> Enum.map(&{&1.kind, &1.file})
      end

      assert kinds.() == []
      assert records_in_dir(tmp) == records_in_dir(".")

      sixth = "docs/conformance/adjudications/adjudication-Z-2026-07-28.json"

      File.write!(
        Path.join(tmp, sixth),
        Jason.encode!(%{
          "schema" => A.schema(),
          "authored_by_hand" => true,
          "ticket" => "MES-148",
          "sections" => [
            %{
              "view" => "docs/conformance/buckets/bucket-5a-2026-07-28.json",
              "closure" => "open",
              "owner" => "MES-148",
              "rows" => []
            }
          ]
        })
      )

      assert kinds.() == []
      assert load.() |> A.audit() |> get_in([:report, "records_visited"]) == 11
      assert sixth in records_in_dir(tmp)
      File.rm!(Path.join(tmp, sixth))

      # W2: D4a's escalated section dropped.
      d4a = Path.join(tmp, @d4a)
      original = File.read!(d4a)
      doc = Jason.decode!(original)

      File.write!(
        d4a,
        Jason.encode!(
          Map.update!(doc, "sections", &Enum.reject(&1, fn s -> s["view"] =~ "escalated" end))
        )
      )

      assert kinds.() == [{:owed_unadjudicated, @ves}]
      File.write!(d4a, original)

      outside = "docs/conformance/adjudication-D4a-copy.json"
      File.write!(Path.join(tmp, outside), original)
      assert kinds.() == [{:record_outside_walk, outside}]
      File.rm!(Path.join(tmp, outside))

      wrong = "docs/conformance/adjudications/adjudication-W-2026-07-28.json"

      File.write!(
        Path.join(tmp, wrong),
        Jason.encode!(Map.put(doc, "schema", "adjudication-record/0"))
      )

      assert kinds.() == [{:bad_record, wrong}]
      File.rm!(Path.join(tmp, wrong))

      nested = "docs/conformance/adjudications/nested"
      File.mkdir_p!(Path.join(tmp, nested))
      File.write!(Path.join([tmp, nested, "adjudication-N.json"]), original)
      stray = "docs/conformance/adjudications/adjudication-S.jsn"
      File.write!(Path.join(tmp, stray), original)

      assert kinds.() == [
               {:stray_in_walk_root, "docs/conformance/adjudications/adjudication-S.jsn"},
               {:stray_in_walk_root, nested},
               {:record_outside_walk, nested <> "/adjudication-N.json"}
             ]
    end

    # MES-135 B1: the scan population is the files git would commit. A record
    # under a git-ignored path is not committed unless force-added, so while it
    # is only ignored it is not refused (CR 29671's plant, which went red at one
    # seat only); force-added, it is tracked, and scanned and refused. An
    # untracked-and-not-ignored record, and a tracked one, are still refused.
    # A root git cannot list is refused, not skipped.
    test "record_outside_walk scans the files git would commit: ignored is not scanned, untracked and tracked are refused, no work tree is refused",
         %{} do
      tmp = copied_tree()
      on_exit(fn -> File.rm_rf!(tmp) end)
      real = A.load().source_fun
      kinds = fn root -> %{A.load(root: root) | source_fun: real} |> A.audit() |> kinds_of() end
      {:ok, d4b} = File.read(@d4b)

      assert kinds.(tmp) == []

      ignored = "tmp/MCP.Conformance.SomeTest/leftover/record.json"
      File.mkdir_p!(Path.join(tmp, Path.dirname(ignored)))
      File.write!(Path.join(tmp, ignored), d4b)
      assert {"", 0} = System.cmd("git", ["-C", tmp, "check-ignore", "-q", ignored])
      assert kinds.(tmp) == []

      untracked = "docs/conformance/adjudication-D4b-copy.json"
      File.write!(Path.join(tmp, untracked), d4b)
      assert kinds.(tmp) == [{:record_outside_walk, untracked}]

      {_, 0} = System.cmd("git", ["-C", tmp, "add", untracked])

      assert {^untracked <> "\n", 0} =
               System.cmd("git", ["-C", tmp, "ls-files", "--cached", untracked])

      assert kinds.(tmp) == [{:record_outside_walk, untracked}]

      File.rm_rf!(Path.join(tmp, ".git"))

      assert [%{kind: :record_outside_walk, file: ".", detail: detail}] =
               %{A.load(root: tmp) | source_fun: real} |> A.audit() |> Map.fetch!(:defects)

      assert detail =~ "cannot be listed"
      assert detail =~ "refused, not skipped"

      sub = Path.join(tmp, "docs")
      {_, 0} = System.cmd("git", ["init", "-q", tmp])
      assert {:error, why} = A.outside(sub)
      assert why =~ "is not the top level of a git work tree"
    end
  end

  # A copy of the adjudications and buckets directories, the locator and the
  # .gitignore, OUTSIDE the clone (seats share one checkout), made a git work
  # tree of its own with nothing committed: the committed tree's files are
  # untracked-and-not-ignored there, which the scan population includes.
  defp copied_tree do
    tmp = Path.join(System.tmp_dir!(), "mes135-g32-#{System.unique_integer([:positive])}")

    for d <- ["docs/conformance/adjudications", "docs/conformance/buckets"] do
      File.mkdir_p!(Path.join(tmp, d))
      File.cp_r!(d, Path.join(tmp, d))
    end

    File.cp!(A.locator_path(), Path.join(tmp, A.locator_path()))
    File.cp!(".gitignore", Path.join(tmp, ".gitignore"))
    {_, 0} = System.cmd("git", ["init", "-q", tmp])
    tmp
  end

  defp kinds_of(%{defects: ds}), do: Enum.map(ds, &{&1.kind, &1.file})

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

  defp replace_citation(c, c, new), do: new

  defp replace_citation(m, c, new) when is_map(m),
    do: Map.new(m, fn {k, v} -> {k, replace_citation(v, c, new)} end)

  defp replace_citation(l, c, new) when is_list(l), do: Enum.map(l, &replace_citation(&1, c, new))
  defp replace_citation(x, _c, _new), do: x

  # Every record in the directory, listed independently of the guard's walk
  # (MES-135 N3). The per-record G31 units list it inline, at compile time.
  defp records_in_dir(root) do
    dir = Path.join(root, "docs/conformance/adjudications")

    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(&("docs/conformance/adjudications/" <> &1))
    |> Enum.sort()
  end

  defp client?(tag), do: String.starts_with?(tag, "oc:client/")

  # --- synthetic inputs ---------------------------------------------------------

  @view "docs/conformance/buckets/bucket-x.json"
  @rec "docs/conformance/adjudications/adjudication-X.json"
  @src "test/src.exs"
  # The members' own tests, for K1's et_test tie: "M/test a" and "M/test e".
  @owner_src "test/owner.exs"
  @owner_body """
  defmodule M do
    test "a" do
      assert x == 1
    end

    test "e" do
      assert e == 1
    end
  end
  """
  @owner_lines %{"M/test a" => [3, 3], "M/test e" => [7, 7]}
  @owner_bytes %{"M/test a" => "assert x == 1", "M/test e" => "assert e == 1"}
  # The synthetic locator: each synthetic tag is emitted at [0, 10].
  @locator %{"oc:t1" => [[0, 10]], "oc:e" => [[0, 10]]}
  @harness %{"harness_sha256" => "abc", "byte_span" => [0, 5], "bytes" => "x"}

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
        "et_test" => %{
          "file" => @owner_src,
          "lines" => @owner_lines[vr["member"]["register_key"]],
          "bytes" => @owner_bytes[vr["member"]["register_key"]]
        },
        "check" => %{"requires" => "x", "predicate" => @harness},
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
               "ticket" => "MES-1",
               "sections" => sections
             }}
          )
      },
      anchor: [@view],
      strays: [],
      outside: {:ok, []},
      locator: {:ok, @locator},
      views: %{
        @view =>
          {:ok,
           %{"schema" => Keyword.get(opts, :view_schema, "bucket-view/1"), "rows" => view_rows}}
      },
      source_fun: fn
        @src -> {:ok, "line one\n  assert   x == 1\nline three\n"}
        @owner_src -> {:ok, @owner_body}
        _ -> {:error, :enoent}
      end
    }
  end

  @rec2 "docs/conformance/adjudications/adjudication-Y.json"

  defp two_records(view_rows, sections1, sections2) do
    base = inputs(view_rows, sections1)

    rec = fn ss ->
      {:ok,
       %{
         "schema" => "adjudication-record/1",
         "authored_by_hand" => true,
         "ticket" => "MES-1",
         "sections" => ss
       }}
    end

    %{base | walk: [@rec, @rec2], records: %{@rec => rec.(sections1), @rec2 => rec.(sections2)}}
  end

  defp section(rows, closure \\ "closed", extra \\ %{}),
    do: Map.merge(%{"view" => @view, "closure" => closure, "rows" => rows}, extra)

  # The synthetic view is owed. Unless a closed section binds it, it is pending
  # on MES-1, the synthetic records' ticket, so the units below exercise the
  # set and row clauses and the universe clauses have units of their own.
  defp audit(inputs) do
    closed? =
      Enum.any?(inputs.records, fn
        {_, {:ok, %{"sections" => ss}}} when is_list(ss) ->
          Enum.any?(ss, &(is_map(&1) and &1["view"] == @view and &1["closure"] == "closed"))

        _ ->
          false
      end)

    A.audit(inputs, %{not_owed: %{}, pending: if(closed?, do: %{}, else: %{@view => "MES-1"})})
  end

  defp kinds(inputs), do: inputs |> audit() |> Map.fetch!(:defects) |> Enum.map(& &1.kind)

  defp a, do: view_row("M/test a", "claim a", "oc:t1")
  defp b, do: view_row("M/test a", "claim b", "oc:t1")

  describe "the key" do
    test "is the same triple from a view row and from a record row" do
      assert A.key(a()) == ["M/test a", "claim a", "oc:t1"]
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
               inputs([a()], [section([row(a()), ghost], "open", %{"owner" => "MES-1"})])
             )
    end

    test "duplicate: one edge adjudicated twice across sections" do
      sections = [
        section([row(a())], "open", %{"owner" => "MES-1"}),
        section([row(a())], "open", %{"owner" => "MES-1"})
      ]

      assert kinds(inputs([a()], sections)) == [:duplicate]
    end

    # MES-135 K3: two records each closing a disjoint half of one view pass
    # duplicate (the halves are disjoint) and missing (the union is complete).
    test "closure_not_exclusive: two closed sections over disjoint halves, naming both files" do
      two = two_records([a(), b()], [section([row(a())])], [section([row(b())])])
      %{defects: ds} = audit(two)

      assert Enum.map(ds, &{&1.kind, &1.file}) == [
               {:closure_not_exclusive, @rec},
               {:closure_not_exclusive, @rec2}
             ]

      assert Enum.all?(ds, &(&1.detail =~ @rec and &1.detail =~ @rec2))
    end

    test "closure_not_exclusive: one closed section and an open one is the split view, clean" do
      two =
        two_records([a(), b()], [section([row(a())], "open", %{"owner" => "MES-1"})], [
          section([row(b())])
        ])

      assert audit(two).defects == []
    end

    # MES-135 F7: set defects were attributed to the view's FIRST section's file.
    test "missing is attributed to the closing section's file, not the first section's" do
      two =
        two_records([a(), b()], [section([row(a())], "open", %{"owner" => "MES-1"})], [
          section([])
        ])

      assert [%{kind: :missing, file: @rec2}] = audit(two).defects
    end

    test "duplicate is attributed to every file holding the key" do
      two =
        two_records([a()], [section([row(a())], "open", %{"owner" => "MES-1"})], [
          section([row(a())])
        ])

      assert Enum.map(audit(two).defects, &{&1.kind, &1.file}) == [
               {:duplicate, @rec},
               {:duplicate, @rec2}
             ]
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

  describe "the universe, unit by unit (MES-135 K2)" do
    @v0 "docs/conformance/buckets/bucket-0.json"
    @vo "docs/conformance/buckets/bucket-o.json"
    @none %{not_owed: %{}, pending: %{}}

    defp u_kinds(inputs, policy),
      do: inputs |> A.audit(policy) |> Map.fetch!(:defects) |> Enum.map(&{&1.kind, &1.file})

    test "owed_unadjudicated: an owed view no closed section binds, not pending" do
      i = %{inputs([a()], [section([row(a())])]) | anchor: [@view, @vo]}
      assert u_kinds(i, @none) == [{:owed_unadjudicated, @vo}]
      assert u_kinds(i, %{@none | pending: %{@vo => "MES-9"}}) == []
      assert u_kinds(i, %{@none | not_owed: %{@vo => "why"}}) == []
    end

    test "an owed view bound only by an OPEN section is still owed" do
      i = inputs([a()], [section([row(a())], "open", %{"owner" => "MES-1"})])
      assert u_kinds(i, @none) == [{:owed_unadjudicated, @view}]
    end

    test "pending_but_closed: a closed view still named in @pending" do
      i = inputs([a()], [section([row(a())])])
      assert u_kinds(i, %{@none | pending: %{@view => "MES-1"}}) == [{:pending_but_closed, @rec}]
    end

    test "catalogue_names_absent_view: either catalogue naming a view the listing lacks" do
      i = inputs([a()], [section([row(a())])])

      assert u_kinds(i, %{@none | not_owed: %{@v0 => "why"}}) == [
               {:catalogue_names_absent_view, @v0}
             ]

      assert u_kinds(i, %{@none | pending: %{@v0 => "MES-9"}}) == [
               {:catalogue_names_absent_view, @v0}
             ]
    end

    test "catalogue_names_absent_view: @pending naming an excluded view" do
      i = %{inputs([a()], [section([row(a())])]) | anchor: [@view, @v0]}
      policy = %{not_owed: %{@v0 => "why"}, pending: %{@v0 => "MES-9"}}
      assert u_kinds(i, policy) == [{:catalogue_names_absent_view, @v0}]
    end

    test "bound_to_excluded: a section binding a view that is not owed" do
      i = inputs([a()], [section([row(a())])])
      assert u_kinds(i, %{@none | not_owed: %{@view => "why"}}) == [{:bound_to_excluded, @rec}]
    end

    test "bound_outside_anchor: a section binding a view the listing lacks" do
      i = %{inputs([a()], [section([row(a())])]) | anchor: [@vo]}
      policy = %{@none | pending: %{@vo => "MES-9"}}
      assert u_kinds(i, policy) == [{:bound_outside_anchor, @rec}]
    end

    test "owner_mismatch: an open section owned by a ticket that does not close its view" do
      open = fn owner -> section([row(a())], "open", %{"owner" => owner}) end
      pending = %{@none | pending: %{@view => "MES-1"}}

      assert u_kinds(inputs([a()], [open.("MES-1")]), pending) == []
      assert u_kinds(inputs([a()], [open.("MES-2")]), pending) == [{:owner_mismatch, @rec}]

      # Once closed, the owner is the closing record's ticket.
      closed = two_records([a(), b()], [open.("MES-1")], [section([row(b())])])
      assert u_kinds(closed, @none) == []

      assert u_kinds(
               put_in(
                 closed.records[@rec2],
                 {:ok, put_in(elem(closed.records[@rec2], 1), ["ticket"], "MES-7")}
               ),
               @none
             ) ==
               [{:owner_mismatch, @rec}]
    end

    test "owner_mismatch: a closing record with no ticket is judged, not skipped" do
      closed =
        two_records([a(), b()], [section([row(a())], "open", %{"owner" => "MES-1"})], [
          section([row(b())])
        ])

      {:ok, doc} = closed.records[@rec2]
      untick = put_in(closed.records[@rec2], {:ok, Map.delete(doc, "ticket")})
      assert u_kinds(untick, @none) == [{:owner_mismatch, @rec}]
    end

    test "empty_closure_unwarranted: a closed empty section over an empty view that does not say why" do
      empty = fn view -> put_in(inputs([], [section([])]).views[@view], {:ok, view}) end

      stated = %{
        "schema" => "bucket-view/1",
        "rows" => [],
        "count" => 0,
        "emptiness_reason" => %{"code" => "by_construction"}
      }

      # A zero-row closure is still a visited record with no rows, so reach fires too.
      assert u_kinds(empty.(stated), @none) == [{:reach, ""}]

      for bad <- [
            Map.delete(stated, "emptiness_reason"),
            %{stated | "emptiness_reason" => %{}},
            %{stated | "count" => 3}
          ] do
        assert u_kinds(empty.(bad), @none) == [{:empty_closure_unwarranted, @rec}, {:reach, ""}]
      end
    end

    test "stray_in_walk_root and record_outside_walk are refused from the inputs" do
      i = %{
        inputs([a()], [section([row(a())])])
        | strays: ["x/y.jsn"],
          outside: {:ok, ["z.json"]}
      }

      assert u_kinds(i, @none) == [
               {:stray_in_walk_root, "x/y.jsn"},
               {:record_outside_walk, "z.json"}
             ]
    end
  end

  describe "content tied to the key, unit by unit (MES-135 K1)" do
    test "et_test_foreign: a member row citing another test, or no citation" do
      other =
        row(a(), %{
          "et_test" => %{"file" => @owner_src, "lines" => [7, 7], "bytes" => "assert e == 1"}
        })

      assert kinds(inputs([a()], [section([other])])) == [:et_test_foreign]

      prose = row(a(), %{"et_test" => "the test that sends x"})
      assert kinds(inputs([a()], [section([prose])])) == [:et_test_foreign]

      none = row(a(), %{"et_test" => nil})
      assert kinds(inputs([a()], [section([none])])) == [:et_test_foreign]
    end

    test "et_test_foreign: a member-less row must carry et_test null" do
      m = view_row(nil, nil, "oc:t1") |> Map.delete("member")
      ok = row(m, %{"member" => nil, "et_test" => nil})
      assert kinds(inputs([m], [section([ok])])) == []

      kept =
        row(m, %{
          "member" => nil,
          "et_test" => %{"file" => @owner_src, "lines" => [3, 3], "bytes" => "assert x == 1"}
        })

      assert kinds(inputs([m], [section([kept])])) == [:et_test_foreign]
    end

    test "check_foreign: no harness span under check overlaps the tag's own sites" do
      far = row(a(), %{"check" => %{"predicate" => %{@harness | "byte_span" => [20, 30]}}})
      assert kinds(inputs([a()], [section([far])])) == [:check_foreign]

      prose = row(a(), %{"check" => %{"requires" => "x", "predicate" => "the validator"}})
      assert kinds(inputs([a()], [section([prose])])) == [:check_foreign]

      # Touching is not overlapping: spans are half-open.
      touch = row(a(), %{"check" => %{"predicate" => %{@harness | "byte_span" => [10, 12]}}})
      assert kinds(inputs([a()], [section([touch])])) == [:check_foreign]
    end

    test "check_foreign: a tag that is not a locator token" do
      t = view_row("M/test a", "claim a", "oc:t9")
      assert kinds(inputs([t], [section([row(t)])])) == [:check_foreign]
    end

    test "check_foreign: an oc:none/ row cites no harness span under check" do
      n = view_row("M/test a", "claim a", "oc:none/x/CG1")
      assert kinds(inputs([n], [section([row(n, %{"check" => %{"requires" => "x"}})])])) == []
      assert kinds(inputs([n], [section([row(n)])])) == [:check_foreign]
    end

    test "root_cause_foreign: an R<n> whose stated_at does not carry **R<n>**" do
      cite = fn b -> %{"file" => @src, "lines" => [2, 2], "bytes" => b} end
      stated = %{"file" => @src, "lines" => [2, 2], "bytes" => "assert x == 1"}
      src = fn -> {:ok, "line one\n| **R6** the cause |\nline three\n"} end

      i = fn rc ->
        base = inputs([a()], [section([row(a(), %{"root_cause" => rc})])])

        %{
          base
          | source_fun: fn
              @src -> src.()
              f -> base.source_fun.(f)
            end
        }
      end

      assert kinds(i.(%{"id" => "R6", "stated_at" => cite.("| **R6** the cause |")})) == []

      assert kinds(i.(%{"id" => "R1", "stated_at" => cite.("| **R6** the cause |")})) == [
               :root_cause_foreign
             ]

      assert kinds(i.(%{"id" => "R1"})) == [:root_cause_foreign]

      assert kinds(i.(%{"id" => "R1", "stated_at" => "the report says so"})) == [
               :root_cause_foreign
             ]

      # A cause that is not an R<n> has nothing to tie to.
      assert kinds(i.(%{"id" => "suite_slug", "stated_at" => stated})) == [:citation_drift]
      assert kinds(i.(%{"id" => "suite_slug"})) == []
    end

    test "the ties' anchors are pinned" do
      assert A.locator_path() == "docs/conformance/oc-emitting-sites-2026-07-28.json"
      assert A.no_oc_prefix() == "oc:none/"
      assert Regex.source(A.r_id()) == "\\AR[0-9]+\\z"

      assert A.echo(%{"cg" => "CG1", "tag" => "t", "shape" => "s"}) == %{
               "cg" => "CG1",
               "shape" => "s"
             }
    end

    test "echo holds cg: a bucket-1-shaped view row re-projected under an unchanged key" do
      n = view_row("M/test a", "claim a", "oc:none/x/CG1", %{"cg" => "CG1"})
      r = row(n, %{"check" => %{"requires" => "x"}})
      moved = %{n | "cg" => "CG2"}
      assert kinds(inputs([n], [section([r])])) == []
      assert kinds(inputs([moved], [section([r])])) == [:echo_drift]
    end

    test "an unreadable locator is refused, and every OC row fails to tie" do
      i = %{inputs([a()], [section([row(a())])]) | locator: {:error, "gone"}}
      assert kinds(i) == [:unreadable, :check_foreign]
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
        |> audit()
        |> Map.get(:defects)

      assert d.kind == :bad_row and d.detail =~ "rationale"
    end

    test "echo_drift: the view's verdict moved under an unchanged key" do
      moved = Map.put(a(), "verdicts", %{"et" => "green", "oc" => "green"})
      assert kinds(inputs([moved], [section([row(a())])])) == [:echo_drift]
    end

    test "an escalated row needs whose_defect and a cause_slug naming the view's cause" do
      esc =
        view_row("M/test e", "c", "oc:e", %{
          "escalation_reason" => "r",
          "escalation_cause" => "slug"
        })

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

  # --- the D1-nd+CU record (MES-138) --------------------------------------------
  #
  # MES-129's rules, applied from the start: the derived set is held to its
  # criterion both ways over the whole view; the counts are the rows'
  # enumeration; the routes equal the routed rows both ways; and every assert
  # the record says it read resolves to an assert at that line.

  @d1 "docs/conformance/adjudications/adjudication-D1-nd-CU-2026-07-28.json"
  @d1ci "docs/conformance/adjudications/adjudication-D1-client-i-2026-07-28.json"
  @d1cii "docs/conformance/adjudications/adjudication-D1-client-ii-2026-07-28.json"
  @d1si "docs/conformance/adjudications/adjudication-D1-server-i-2026-07-28.json"
  @d1sii "docs/conformance/adjudications/adjudication-D1-server-ii-2026-07-28.json"
  @v1 "docs/conformance/buckets/bucket-1-2026-07-28.json"
  @vcu "docs/conformance/buckets/claim-unmatched-2026-07-28.json"
  @assert_word ~r/\b(assert|refute|assert_receive|refute_receive)\b/

  defp d1_section(inputs, view) do
    {:ok, record} = inputs.records[@d1]
    Enum.find(record["sections"], &(&1["view"] == view))
  end

  describe "the D1-nd+CU record (MES-138)" do
    test "bucket-1's section EQUALS the view rows whose member is none_determinable, over all 195; the 174 others are on a leg",
         %{inputs: inputs} do
      leg =
        for r <- json("docs/conformance/etcc-attribution.json")["rows"],
            into: %{},
            do: {r["key"], r["leg"]}

      {:ok, view} = inputs.views[@v1]
      assert length(view["rows"]) == 195

      {nd, others} =
        Enum.split_with(view["rows"], &(leg[&1["member"]["register_key"]] == "none_determinable"))

      section = d1_section(inputs, @v1)
      assert {section["closure"], section["owner"]} == {"open", "MES-143"}
      assert MapSet.new(section["rows"], &A.key/1) == MapSet.new(nd, &A.key/1)
      assert length(section["rows"]) == 21

      # The rows outside the slice, each with its recorded reading: a leg.
      assert Enum.frequencies_by(others, &leg[&1["member"]["register_key"]]) ==
               %{"server" => 103, "client" => 71}
    end

    test "the claim-unmatched section closes the view and records the hand-over from MES-133",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@vcu]
      section = d1_section(inputs, @vcu)

      assert {section["closure"], section["owner"]} == {"closed", "MES-138"}
      assert MapSet.new(section["rows"], &A.key/1) == MapSet.new(view["rows"], &A.key/1)
      assert length(section["rows"]) == 9

      h = section["handed_over_from"]
      assert h["ticket"] == "MES-133" and h["why"] =~ "29609 Q4"
      assert h["view_label"]["file"] == @vcu
      assert h["view_label"]["bytes"] =~ ~s|"adjudication_owner": "MES-133 (D1)"|
      assert view["adjudication_owner"] == "MES-133 (D1)"
    end

    test "every row is one of the D1 family; the counts are the rows' enumeration, per section",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1]

      for {name, view} <- [{"bucket_1_none_determinable", @v1}, {"claim_unmatched", @vcu}] do
        rows = d1_section(inputs, view)["rows"]
        assert Enum.all?(rows, &(&1["disposition"] in A.d1_dispositions()))

        enumerated =
          rows
          |> Enum.group_by(& &1["disposition"], & &1["tag"])
          |> Map.new(fn {d, tags} -> {d, %{"count" => length(tags), "tags" => tags}} end)

        assert record["counts"][name] == enumerated, name
      end

      counts =
        for {name, c} <- record["counts"],
            into: %{},
            do: {name, Map.new(c, fn {d, v} -> {d, v["count"]} end)}

      # Per verdict, negatives included: no redundant row and, since the N5
      # ruling [authored 29707 N5 | ratified 29708], no wrong_against_spec row,
      # in either section.
      assert counts == %{
               "bucket_1_none_determinable" => %{
                 "genuine_extra_coverage" => 17,
                 "not_a_conformance_claim" => 4
               },
               "claim_unmatched" => %{
                 "genuine_extra_coverage" => 3,
                 "not_a_conformance_claim" => 6
               }
             }
    end

    test "the routes equal the routed rows, both ways, and the unused route is named",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1]
      rows = for s <- record["sections"], r <- s["rows"], do: r
      routed = Enum.filter(rows, &Map.has_key?(&1, "routed_to"))

      # Every routed row is a routed disposition, and every such row is routed.
      assert Enum.all?(routed, &Map.has_key?(A.routes(), &1["disposition"]))

      assert Enum.filter(rows, &Map.has_key?(A.routes(), &1["disposition"])) == routed

      by_owner = Enum.frequencies_by(routed, &{&1["routed_to"]["owner"], &1["routed_to"]["to"]})

      assert by_owner ==
               Map.new(record["routing"], &{{&1["owner"], &1["to"]}, &1["rows"]})

      assert by_owner == %{{"MES-153", "A2"} => 10}

      # MES-153 comment 29700 lists the four rows routed at a361a0f as items
      # 1-4, in record order. The six the N5 ruling re-routed (29708) are
      # items 1-6 of MES-153 comment 29716, in record order; its item 7 was
      # withdrawn (MES-153 comment 29722) when the claim-grain ruling
      # [authored 29721 B-A | ratified 29723] made that row genuine.
      second = &"MES-153 comment 29716, item #{&1}"

      assert Enum.map(routed, &{&1["tag"], &1["routed_to"]["owner_record"]}) == [
               {"oc:none/no-oc-scenario/extensions-and-experimental-stay-separate", second.(1)},
               {"oc:none/no-oc-scenario/extensions-inbound-not-validated", second.(2)},
               {"oc:none/no-oc-scenario/notification-framing-encode", second.(3)},
               {"oc:none/no-oc-scenario/sse-codec-round-trip", second.(4)},
               {"oc:none/no-oc-scenario/CG7-exclusion-is-logged",
                "MES-153 comment 29700, item 1"},
               {"oc:none/no-oc-scenario/CG7-non-tools-call-carries-no-headers-opt",
                "MES-153 comment 29700, item 2"},
               {"oc:none/no-oc-scenario/CG1-no-mcp-name-without-a-name-target", second.(5)},
               {"oc:none/no-oc-scenario/MES-115-retry-identity-re-resolved", second.(6)},
               {"oc:none/no-oc-scenario/MES-117-default-caching-policy-values",
                "MES-153 comment 29700, item 3"},
               {"oc:none/no-axis-contact/AC7-identity-factory-not-invoked-on-rejected-origin",
                "MES-153 comment 29700, item 4"}
             ]

      assert [%{"owner" => "MES-152", "to" => "A3"}] =
               Enum.map(record["unused_routes"], &Map.take(&1, ~w(owner to)))

      refute Enum.any?(routed, &(&1["routed_to"]["owner"] == "MES-152"))
    end

    # PM 29708, item B1: the N5 ruling [authored 29707 N5 | ratified 29708]
    # decides not_a_conformance_claim against wrong_against_spec by ONE
    # counterfactual, applied to every row. The both-ways equality of the
    # not-a-claim set and the firing set runs over EVERY D1 record since
    # MES-139 ("every D1 record in the directory", below); MES-138's own
    # figures stay here.
    test "MES-138's figures: 30 rows, 10 of them firing, none wrong_against_spec; its unit covers its two views",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1]
      rows = for s <- record["sections"], r <- s["rows"], do: r
      assert length(rows) == 30
      assert Enum.count(rows, & &1["counterfactual"]["conforming_sdk_can_fail"]) == 10
      refute Enum.any?(rows, &(&1["disposition"] == "wrong_against_spec"))

      # PM 29717: host values are the recorded alternative grain.
      assert is_map(record["counterfactual"]["fires_on_another_grain"])

      # PM 29723: the claim-unmatched view asks of the claim alone.
      unit = record["counterfactual"]["unit"]
      assert Map.keys(unit) == Enum.sort([@v1, @vcu])
      assert unit[@vcu] =~ ~r/\Athe claim: /
    end

    test "every assert a row says it read is an assert at that line; a whole-test window lists them all",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1]

      for s <- record["sections"], r <- s["rows"] do
        assert r["asserts_read"] != [], r["tag"]

        read =
          for entry <- r["asserts_read"],
              [_, file, line, text] <- [Regex.run(~r/\A(test\/[^:]+):(\d+) — (.*)\z/s, entry)] do
            {:ok, src} = inputs.source_fun.(file)

            at =
              src |> String.split("\n") |> Enum.at(String.to_integer(line) - 1) |> String.trim()

            assert at == text and at =~ @assert_word, entry
            {file, String.to_integer(line)}
          end

        # A generator pattern filters what it cannot match: nothing may be dropped.
        assert length(read) == length(r["asserts_read"]) or
                 match?(%{"lines" => [l, l]}, r["et_test"]),
               r["tag"]

        case r["et_test"] do
          %{"lines" => [l, l]} ->
            # A doctest: its body is the @doc example, cited in doctest_body.
            assert r["doctest_body"]["file"] == "lib/mcp/protocol/extensions.ex"
            assert read == []

          %{"file" => f, "lines" => [from, to]} ->
            {:ok, src} = inputs.source_fun.(f)

            in_window =
              for {line, i} <- src |> String.split("\n") |> Enum.with_index(1),
                  i in from..to,
                  line =~ @assert_word,
                  do: {f, i}

            # Every assert in the cited window was read; a bucket-1 window is
            # the whole test, so there the two are equal.
            assert in_window -- read == [], r["tag"]
            if s["view"] == @v1, do: assert(read == in_window, r["tag"])
        end
      end
    end
  end

  # --- the D1-client-i record (MES-139; authored 29729, ratified 29731) -------
  #
  # The slice is declared by a JOIN selector, not a hand list: a view row's leg
  # is not a field of the row but of the member's etcc-attribution.json row, so
  # D2a-ii's field selector cannot express it (29731, Q4). Pinned literally here,
  # and held both ways over the whole view.

  @d1ci_selector %{
    "join" => "docs/conformance/etcc-attribution.json",
    "on" => "member.register_key",
    "leg" => "client",
    "module_in" => ["MCP.ClientTest", "MCP.ClientToolSchemasTest"]
  }

  defp d1ci_rows(inputs) do
    {:ok, record} = inputs.records[@d1ci]
    [section] = record["sections"]
    section["rows"]
  end

  defp leg_of do
    for r <- json("docs/conformance/etcc-attribution.json")["rows"],
        into: %{},
        do: {r["key"], r["leg"]}
  end

  defp join_selected(view_rows, legs, %{"leg" => leg, "module_in" => mods}) do
    Enum.filter(
      view_rows,
      &(legs[&1["member"]["register_key"]] == leg and &1["member"]["module"] in mods)
    )
  end

  # MES-140 (29765 Q1, ratified 29766): the complement, so a client test module
  # added later falls in a slice rather than outside both.
  defp join_selected(view_rows, legs, %{"leg" => leg, "module_not_in" => mods}) do
    Enum.filter(
      view_rows,
      &(legs[&1["member"]["register_key"]] == leg and &1["member"]["module"] not in mods)
    )
  end

  defp join_equality(section_rows, view_rows, selector) do
    want = view_rows |> join_selected(leg_of(), selector) |> MapSet.new(&A.key/1)
    got = MapSet.new(section_rows, &A.key/1)

    if want == got,
      do: :ok,
      else: {:error, {MapSet.difference(got, want), MapSet.difference(want, got)}}
  end

  describe "the D1-client-i record (MES-139)" do
    test "the section EQUALS the join selector's rows, both ways, over all 195; the 160 others carry a leg and module",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1ci]
      [section] = record["sections"]
      {:ok, view} = inputs.views[@v1]
      assert length(view["rows"]) == 195

      assert {section["view"], section["closure"], section["owner"]} == {@v1, "open", "MES-143"}
      assert section["slice"]["selector"] == @d1ci_selector
      assert join_equality(section["rows"], view["rows"], @d1ci_selector) == :ok
      assert length(section["rows"]) == 35

      # The rows outside the slice, each with its recorded reading.
      legs = leg_of()
      inside = join_selected(view["rows"], legs, @d1ci_selector)
      others = view["rows"] -- inside

      assert Enum.frequencies_by(inside, & &1["member"]["module"]) ==
               %{"MCP.ClientTest" => 24, "MCP.ClientToolSchemasTest" => 11}

      assert Enum.frequencies_by(others, &legs[&1["member"]["register_key"]]) ==
               %{"server" => 103, "none_determinable" => 21, "client" => 36}
    end

    test "the join equality refuses one added non-slice row and one dropped slice row",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@v1]
      rows = d1ci_rows(inputs)
      inside = join_selected(view["rows"], leg_of(), @d1ci_selector)
      [other | _] = view["rows"] -- inside

      assert {:error, {added, none}} =
               join_equality(
                 rows ++ [%{other | "member" => other["member"]["register_key"]}],
                 view["rows"],
                 @d1ci_selector
               )

      assert {MapSet.to_list(added), none} == {[A.key(other)], MapSet.new()}

      [first | rest] = rows
      assert {:error, {none, dropped}} = join_equality(rest, view["rows"], @d1ci_selector)
      assert {none, MapSet.to_list(dropped)} == {MapSet.new(), [A.key(first)]}
    end

    test "every row is one of the D1 family; the counts are the rows' enumeration, negatives included",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1ci]
      rows = d1ci_rows(inputs)
      assert Enum.all?(rows, &(&1["disposition"] in A.d1_dispositions()))

      enumerated =
        rows
        |> Enum.group_by(& &1["disposition"], & &1["tag"])
        |> Map.new(fn {d, tags} -> {d, %{"count" => length(tags), "tags" => tags}} end)

      assert record["counts"] == %{"bucket_1_client_i" => enumerated}

      assert Map.new(enumerated, fn {d, v} -> {d, v["count"]} end) == %{
               "genuine_extra_coverage" => 9,
               "redundant" => 12,
               "not_a_conformance_claim" => 13,
               "wrong_against_spec" => 1
             }
    end

    test "the routes equal the routed rows, both ways; both routes are used",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1ci]
      rows = d1ci_rows(inputs)
      routed = Enum.filter(rows, &Map.has_key?(&1, "routed_to"))

      assert Enum.filter(rows, &Map.has_key?(A.routes(), &1["disposition"])) == routed

      by_owner = Enum.frequencies_by(routed, &{&1["routed_to"]["owner"], &1["routed_to"]["to"]})
      assert by_owner == Map.new(record["routing"], &{{&1["owner"], &1["to"]}, &1["rows"]})
      assert by_owner == %{{"MES-152", "A3"} => 12, {"MES-153", "A2"} => 13}
      assert record["unused_routes"] == []

      # The PM's routing comments (29750): MES-152 comment 29747 lists the 12
      # redundant rows as items 1-12, and MES-153 comment 29748 the 13
      # not-a-claim rows as items 1-13, each in record order.
      a3 = &"MES-152 comment 29747, item #{&1}"
      a2 = &"MES-153 comment 29748, item #{&1}"

      assert Enum.map(routed, &{&1["tag"], &1["routed_to"]["owner_record"]}) == [
               {"oc:none/no-oc-fixture-case/mrtr-no-resolver-returns-result-as-is", a2.(1)},
               {"oc:none/no-oc-scenario/client-discover-probe-error-path", a2.(2)},
               {"oc:none/no-oc-scenario/CG2-non-struct-caps-discarded", a3.(1)},
               {"oc:none/no-oc-scenario/CG2-bad-caps-does-not-kill-client", a2.(3)},
               {"oc:none/no-oc-scenario/CG2-declared-extension-stamped", a3.(2)},
               {"oc:none/no-oc-scenario/CG2-stamped-into-discover-probe", a3.(3)},
               {"oc:none/no-oc-scenario/CG2-key-omitted-when-nothing-declared", a3.(4)},
               {"oc:none/no-oc-scenario/CG2-malformed-advertisement-verbatim", a2.(4)},
               {"oc:none/no-oc-scenario/CG2-invalid-identifier-dropped", a3.(5)},
               {"oc:none/no-oc-scenario/CG2-unencodable-settings-dropped", a3.(6)},
               {"oc:none/no-oc-scenario/client-transport-close-notifies-pending", a2.(5)},
               {"oc:none/no-oc-scenario/client-request-timeout", a2.(6)},
               {"oc:none/no-oc-scenario/client-notification-to-fun-handler", a2.(7)},
               {"oc:none/no-oc-scenario/client-notification-to-pid-handler", a2.(8)},
               {"oc:none/no-oc-scenario/CG7-cache-miss-warn-once", a3.(7)},
               {"oc:none/no-oc-scenario/client-32020-only-on-tools-call", a2.(9)},
               {"oc:none/no-oc-fixture-case/CG7-header-mismatch-recovery", a3.(8)},
               {"oc:none/no-oc-scenario/client-32020-failed-refresh-surfaces-original", a2.(10)},
               {"oc:none/no-oc-scenario/client-32020-recovery-is-one-shot", a2.(11)},
               {"oc:none/no-oc-scenario/client-survives-malformed-tools-list", a2.(12)},
               {"oc:none/no-oc-scenario/CG7-malformed-tools-list-result", a3.(9)},
               {"oc:none/no-oc-scenario/CG7-malformed-refresh-result", a3.(10)},
               {"oc:none/no-oc-fixture-case/CG7-tools-list-pagination", a3.(11)},
               {"oc:none/no-oc-fixture-case/CG7-tools-list-pagination", a3.(12)},
               {"oc:none/no-axis-contact/CG7-excluded-tool-called-anyway-mirrors-nothing",
                a2.(13)}
             ]

      # The wrong_against_spec row carries no route (29735): its remedy is
      # remediation's, recorded by the PM in the register.
      assert [w] = Enum.filter(rows, &(&1["disposition"] == "wrong_against_spec"))
      refute Map.has_key?(w, "routed_to")
    end

    test "every assert a row says it read is an assert at that line, and each whole-test window lists them all",
         %{inputs: inputs} do
      for r <- d1ci_rows(inputs) do
        %{"file" => f, "lines" => [from, to]} = r["et_test"]
        {:ok, src} = inputs.source_fun.(f)
        lines = String.split(src, "\n")

        read =
          for entry <- r["asserts_read"],
              [_, file, line, text] <- [Regex.run(~r/\A(test\/[^:]+):(\d+) — (.*)\z/s, entry)] do
            at = lines |> Enum.at(String.to_integer(line) - 1) |> String.trim()
            assert file == f and at == text and at =~ @assert_word, entry
            {file, String.to_integer(line)}
          end

        assert length(read) == length(r["asserts_read"]) and read != [], r["tag"]

        in_window =
          for {line, i} <- Enum.with_index(lines, 1),
              i in from..to,
              line =~ @assert_word,
              do: {f, i}

        assert read == in_window, r["tag"]
      end
    end

    # Q5-Q7 [authored 29733/29734 | ratified 29735]: a member asserting an
    # axis of an in-scope check, directly or by entailment, is redundant, and
    # its counterpart is the full match where there is one.
    test "the redundant rows: each counterpart and its predicate, the entailed four, and the two that do not fire",
         %{inputs: inputs} do
      red = Enum.filter(d1ci_rows(inputs), &(&1["disposition"] == "redundant"))
      short = &(&1["tag"] |> String.split("/") |> List.last())

      by_token =
        red
        |> Enum.group_by(& &1["oc_counterpart"]["token"], short)
        |> Map.new(fn {t, tags} -> {t |> String.split("/") |> List.last(), Enum.sort(tags)} end)

      assert by_token == %{
               "ClientPopulatesMeta" =>
                 Enum.sort(~w(CG2-non-struct-caps-discarded CG2-declared-extension-stamped
                    CG2-stamped-into-discover-probe CG2-key-omitted-when-nothing-declared
                    CG2-invalid-identifier-dropped CG2-unencodable-settings-dropped)),
               "ClientCustomHeader_Region" =>
                 Enum.sort(~w(CG7-cache-miss-warn-once CG7-header-mismatch-recovery
                    CG7-malformed-tools-list-result CG7-malformed-refresh-result)),
               "ClientSupportsCustomHeaders" => [
                 "CG7-tools-list-pagination",
                 "CG7-tools-list-pagination"
               ]
             }

      predicates = %{
        "ClientPopulatesMeta" =>
          "let s=i?.[`io.modelcontextprotocol/clientInfo`],c=i?.[`io.modelcontextprotocol/clientCapabilities`],l=a&&c",
        "ClientCustomHeader_Region" => "this.checkParamHeader(e,`Region`,i.region,`string`)",
        "ClientSupportsCustomHeaders" =>
          "Object.keys(e.headers).some(e=>e.startsWith(`mcp-param-`))"
      }

      for r <- red do
        oc = r["oc_counterpart"]
        name = oc["token"] |> String.split("/") |> List.last()
        assert oc["predicate"]["bytes"] == predicates[name], short.(r)

        assert byte_size(oc["predicate"]["bytes"]) ==
                 Enum.reduce(oc["predicate"]["byte_span"], &-/2)

        # Q7: a Region row also names ClientSupportsCustomHeaders.
        if name == "ClientCustomHeader_Region",
          do: assert(oc["why_a3_missed"] =~ "ClientSupportsCustomHeaders", short.(r))
      end

      # Q6: the entailed four cite the crosswalk's own entailment precedent.
      entailed =
        for r <- red,
            r["oc_counterpart"]["why_a3_missed"] =~ "entails its presence",
            do: short.(r)

      assert Enum.sort(entailed) ==
               Enum.sort(~w(CG2-declared-extension-stamped CG2-stamped-into-discover-probe
                  CG2-invalid-identifier-dropped CG2-unencodable-settings-dropped))

      # Each cites the two precedent lines, and each cited line carries the
      # precedent it is cited for.
      xw = "conformance/data/crosswalk-edges-client.json" |> File.read!() |> String.split("\n")

      for r <- red, short.(r) in entailed do
        cited =
          Regex.scan(~r/crosswalk-edges-client\.json:(\d+)/, r["oc_counterpart"]["why_a3_missed"],
            capture: :all_but_first
          )
          |> Enum.map(fn [n] -> Enum.at(xw, String.to_integer(n) - 1) end)

        assert length(cited) == 2, short.(r)
        assert Enum.at(cited, 0) =~ ~s("evidence": "client_test.exs:153 — )
        assert Enum.at(cited, 1) =~ ~s("evidence": "capabilities_test.exs:98 — )
        assert Enum.all?(cited, &(&1 =~ "entail")), short.(r)
      end

      # Q5: the reading is recorded honestly; two redundant rows do not fire.
      quiet = for r <- red, not r["counterfactual"]["conforming_sdk_can_fail"], do: r["member"]
      assert length(quiet) == 2

      assert Enum.at(quiet, 0) =~
               ~r/a string result likewise, and it leaves the tool caches untouched\z/

      assert Enum.at(quiet, 1) =~
               ~r/a cursor-BEARING page MERGES, so paging does not discard earlier pages\z/
    end

    test "the one wrong_against_spec row cancels an id the client never issued",
         %{inputs: inputs} do
      [w] = Enum.filter(d1ci_rows(inputs), &(&1["disposition"] == "wrong_against_spec"))
      assert w["tag"] == "oc:none/no-oc-scenario/client-sends-cancelled-notification"

      assert w["spec"] == %{
               "url" =>
                 "https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/cancellation",
               "quote" => "Cancellation notifications **MUST** only reference requests that:"
             }

      # The id cancelled, and the first id the client issues.
      assert w["et_test"]["bytes"] =~ "Client.cancel(client, 42, "
      {:ok, client} = inputs.source_fun.("lib/mcp/client.ex")
      assert client |> String.split("\n") |> Enum.at(270) == "      next_id: 1,"
    end

    test "the genuine rows each say which ground they hold, and the record carries the Q5 and Q8 rulings",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1ci]
      genuine = Enum.filter(d1ci_rows(inputs), &(&1["disposition"] == "genuine_extra_coverage"))

      grounds =
        Enum.frequencies_by(genuine, fn r ->
          {r["protects"] =~ "OC's null-passable ground",
           r["protects"] =~ "behaviour the client suite never drives"}
        end)

      assert grounds == %{{true, false} => 8, {false, true} => 1}

      cf = record["counterfactual"]

      assert cf["incidental_traffic"]["provenance"] ==
               "[authored 29733/29734 | ratified 29735, Q8]"

      assert cf["precedence"]["provenance"] == "[authored 29733/29734 | ratified 29735, Q5]"
    end
  end

  # --- the D1-client-ii record (MES-140; plan 29764/29765, ratified 29766) -----
  #
  # The slice is the COMPLEMENT of MES-139's modules on the client leg
  # (module_not_in, Q1 of 29765, ratified 29766), pinned literally and held
  # both ways over the whole view. Together the two selectors must PARTITION
  # the view's client-leg rows; a refusal control shows the partition check
  # naming an overlap and a gap.

  @d1cii_selector %{
    "join" => "docs/conformance/etcc-attribution.json",
    "on" => "member.register_key",
    "leg" => "client",
    "module_not_in" => ["MCP.ClientTest", "MCP.ClientToolSchemasTest"]
  }

  defp d1cii_rows(inputs) do
    {:ok, record} = inputs.records[@d1cii]
    [section] = record["sections"]
    section["rows"]
  end

  # `:ok` when the slices are pairwise disjoint and their union is `universe`;
  # otherwise the first failure, naming the keys.
  defp partition(slices, universe) do
    keys = Enum.map(slices, &MapSet.new(&1, fn r -> A.key(r) end))
    all = MapSet.new(universe, &A.key/1)

    overlap =
      for {a, i} <- Enum.with_index(keys),
          {b, j} <- Enum.with_index(keys),
          i < j,
          k <- MapSet.intersection(a, b),
          into: MapSet.new(),
          do: k

    union = Enum.reduce(keys, MapSet.new(), &MapSet.union/2)

    cond do
      overlap != MapSet.new() ->
        {:error, {:overlap, overlap}}

      MapSet.difference(all, union) != MapSet.new() ->
        {:error, {:gap, MapSet.difference(all, union)}}

      MapSet.difference(union, all) != MapSet.new() ->
        {:error, {:outside, MapSet.difference(union, all)}}

      true ->
        :ok
    end
  end

  describe "the D1-client-ii record (MES-140)" do
    test "the section EQUALS the complement selector's rows, both ways, over all 195; the 159 others carry a leg and module",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1cii]
      [section] = record["sections"]
      {:ok, view} = inputs.views[@v1]
      assert length(view["rows"]) == 195

      assert {section["view"], section["closure"], section["owner"]} == {@v1, "open", "MES-143"}
      assert section["slice"]["selector"] == @d1cii_selector
      assert join_equality(section["rows"], view["rows"], @d1cii_selector) == :ok
      assert length(section["rows"]) == 36 and section["slice"]["rows"] == 36

      legs = leg_of()
      inside = join_selected(view["rows"], legs, @d1cii_selector)
      others = view["rows"] -- inside

      assert Enum.frequencies_by(inside, & &1["member"]["module"]) == %{
               "MCP.Transport.SSETest" => 10,
               "MCP.Protocol.HeaderMirrorTest" => 6,
               "MCP.Protocol.CapabilitiesTest" => 5,
               "MCP.ClientDefectsTest" => 4,
               "MCP.ProtocolTest" => 3,
               "MCP.Transport.RoutingHeadersTest" => 3,
               "MCP.ClientConformanceTest" => 2,
               "MCP.Protocol.ErrorTest" => 2,
               "MCP.Protocol.Messages.DiscoverTest" => 1
             }

      assert Enum.frequencies_by(others, &legs[&1["member"]["register_key"]]) ==
               %{"server" => 103, "none_determinable" => 21, "client" => 35}
    end

    test "the join equality refuses one added non-slice row and one dropped slice row",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@v1]
      rows = d1cii_rows(inputs)
      inside = join_selected(view["rows"], leg_of(), @d1cii_selector)

      # A client row of MES-139's slice: the one kind a complement could wrongly admit.
      [other | _] = join_selected(view["rows"], leg_of(), @d1ci_selector)
      refute other in inside

      assert {:error, {added, none}} =
               join_equality(
                 rows ++ [%{other | "member" => other["member"]["register_key"]}],
                 view["rows"],
                 @d1cii_selector
               )

      assert {MapSet.to_list(added), none} == {[A.key(other)], MapSet.new()}

      [first | rest] = rows
      assert {:error, {none, dropped}} = join_equality(rest, view["rows"], @d1cii_selector)
      assert {none, MapSet.to_list(dropped)} == {MapSet.new(), [A.key(first)]}
    end

    test "MES-139's and MES-140's selectors, and their two sections, PARTITION the view's 71 client-leg rows",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@v1]
      legs = leg_of()
      client = Enum.filter(view["rows"], &(legs[&1["member"]["register_key"]] == "client"))
      assert length(client) == 71

      i = join_selected(view["rows"], legs, @d1ci_selector)
      ii = join_selected(view["rows"], legs, @d1cii_selector)
      assert {length(i), length(ii)} == {35, 36}
      assert partition([i, ii], client) == :ok

      # The committed sections, not only the selectors.
      assert partition([d1ci_rows(inputs), d1cii_rows(inputs)], client) == :ok
    end

    test "the partition check names an overlap, a gap and a row outside the leg",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@v1]
      legs = leg_of()
      client = Enum.filter(view["rows"], &(legs[&1["member"]["register_key"]] == "client"))
      [i, ii] = [d1ci_rows(inputs), d1cii_rows(inputs)]

      # Positive limb on these inputs, so each refusal below is the plant's.
      assert partition([i, ii], client) == :ok

      [x | _] = ii
      assert partition([i ++ [x], ii], client) == {:error, {:overlap, MapSet.new([A.key(x)])}}

      [y | rest] = i
      assert partition([rest, ii], client) == {:error, {:gap, MapSet.new([A.key(y)])}}

      [z | _] = Enum.filter(view["rows"], &(legs[&1["member"]["register_key"]] == "server"))
      z = %{z | "member" => z["member"]["register_key"]}
      assert partition([i, ii ++ [z]], client) == {:error, {:outside, MapSet.new([A.key(z)])}}
    end

    test "every row is one of the D1 family; the counts are the rows' enumeration, negatives included",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1cii]
      rows = d1cii_rows(inputs)
      assert Enum.all?(rows, &(&1["disposition"] in A.d1_dispositions()))

      enumerated =
        rows
        |> Enum.group_by(& &1["disposition"], & &1["tag"])
        |> Map.new(fn {d, tags} -> {d, %{"count" => length(tags), "tags" => tags}} end)

      assert record["counts"] == %{"bucket_1_client_ii" => enumerated}

      assert Map.new(enumerated, fn {d, v} -> {d, v["count"]} end) == %{
               "genuine_extra_coverage" => 21,
               "redundant" => 3,
               "not_a_conformance_claim" => 11,
               "wrong_against_spec" => 1
             }
    end

    test "the routes equal the routed rows, both ways; both routes are used",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1cii]
      rows = d1cii_rows(inputs)
      routed = Enum.filter(rows, &Map.has_key?(&1, "routed_to"))

      assert Enum.filter(rows, &Map.has_key?(A.routes(), &1["disposition"])) == routed

      by_owner = Enum.frequencies_by(routed, &{&1["routed_to"]["owner"], &1["routed_to"]["to"]})
      assert by_owner == Map.new(record["routing"], &{{&1["owner"], &1["to"]}, &1["rows"]})
      assert by_owner == %{{"MES-152", "A3"} => 3, {"MES-153", "A2"} => 11}
      assert record["unused_routes"] == []

      # The PM's routing comments (29776): MES-152 comment 29774 lists the 3
      # redundant rows as items 1-3, and MES-153 comment 29775 the 8
      # not-a-claim rows as items 1-8, each in record order. The correction
      # round's three (B1 of 29796, ratified 29799) are MES-153 comment 29798's
      # items 1-3, in record order.
      a3 = &"MES-152 comment 29774, item #{&1}"
      a2 = &"MES-153 comment 29775, item #{&1}"
      b1 = &"MES-153 comment 29798, item #{&1}"

      assert Enum.map(routed, &{&1["tag"], &1["routed_to"]["owner_record"]}) == [
               {"oc:none/no-oc-scenario/CG2-outbound-meta", a3.(1)},
               {"oc:none/no-axis-contact/D-3-no-retry-when-no-offered-version-is-supported",
                a2.(1)},
               {"oc:none/no-axis-contact/D-3-no-retry-when-supported-data-is-unusable", a2.(2)},
               {"oc:none/no-axis-contact/D-3-no-retry-on-a-non-32022-error", a2.(3)},
               {"oc:none/no-axis-contact/D-3-retry-completes-after-32022", a3.(2)},
               {"oc:none/no-oc-scenario/CG2-encode-keeps-the-two-apart", a2.(4)},
               {"oc:none/no-oc-fixture-case/CG7-static-reachability", b1.(1)},
               {"oc:none/no-oc-fixture-case/CG7-integer-safe-range", a2.(5)},
               {"oc:none/no-oc-fixture-case/CG7-non-map-arguments", a2.(6)},
               {"oc:none/no-oc-fixture-case/CG7-nested-path-exact", b1.(2)},
               {"oc:none/no-oc-fixture-case/CG7-no-raw-crlf-across-all-headers", b1.(3)},
               {"oc:none/no-oc-fixture-case/CG1-notification-carries-mcp-method", a2.(7)},
               {"oc:none/no-oc-fixture-case/CG7-cache-miss-no-mirroring", a3.(3)},
               {"oc:none/no-oc-scenario/sse-decode-all-fields", a2.(8)}
             ]

      # The wrong_against_spec row carries no route (29735): its remedy is
      # remediation's, recorded by the PM in the register.
      assert [w] = Enum.filter(rows, &(&1["disposition"] == "wrong_against_spec"))
      refute Map.has_key?(w, "routed_to")
    end

    test "every assert a row says it read is an assert at that line, each whole-test window lists them all, and the doctest cites its body",
         %{inputs: inputs} do
      for r <- d1cii_rows(inputs) do
        %{"file" => f, "lines" => [from, to]} = r["et_test"]
        {:ok, src} = inputs.source_fun.(f)
        lines = String.split(src, "\n")

        read =
          for entry <- r["asserts_read"],
              [_, file, line, text] <- [Regex.run(~r/\A(test\/[^:]+):(\d+) — (.*)\z/s, entry)] do
            at = lines |> Enum.at(String.to_integer(line) - 1) |> String.trim()
            assert file == f and at == text and at =~ @assert_word, entry
            {file, String.to_integer(line)}
          end

        in_window =
          for {line, i} <- Enum.with_index(lines, 1),
              i in from..to,
              line =~ @assert_word,
              do: {f, i}

        if from == to do
          # The one doctest: its window is the directive, its body the @doc
          # example, and its expected value is the assertion.
          assert r["member"] ==
                   "MCP.Protocol.HeaderMirrorTest/doctest MCP.Protocol.HeaderMirror.encode_value/1 (4)"

          assert {read, in_window} == {[], []}

          assert %{"file" => "lib/mcp/protocol/header_mirror.ex", "lines" => [169, 170]} =
                   r["doctest_body"]

          assert r["asserts_read"] == [
                   "lib/mcp/protocol/header_mirror.ex:169-170 — the doctest example (its expected value is the assertion)"
                 ]
        else
          assert length(read) == length(r["asserts_read"]) and read != [], r["tag"]
          assert read == in_window, r["tag"]
        end
      end
    end

    # Q5-Q7 [authored 29733/29734 | ratified 29735]: a member asserting an
    # axis of an in-scope check, directly or by entailment, is redundant, and
    # its counterpart is the full match where there is one.
    test "the redundant rows: each counterpart and its predicate, the one entailed, and all three fire",
         %{inputs: inputs} do
      red = Enum.filter(d1cii_rows(inputs), &(&1["disposition"] == "redundant"))
      short = &(&1["tag"] |> String.split("/") |> List.last())

      assert Map.new(red, &{short.(&1), &1["oc_counterpart"]["token"]}) == %{
               "CG2-outbound-meta" =>
                 "oc:client/request-metadata/sep-2575-client-populates-meta/ClientPopulatesMeta",
               "D-3-retry-completes-after-32022" =>
                 "oc:client/request-metadata/sep-2575-client-populates-meta/ClientPopulatesMeta",
               "CG7-cache-miss-no-mirroring" =>
                 "oc:client/http-standard-headers/sep-2243-client-includes-standard-headers/ClientMcpNameHeader_tools_call"
             }

      predicates = %{
        "CG2-outbound-meta" =>
          "let s=i?.[`io.modelcontextprotocol/clientInfo`],c=i?.[`io.modelcontextprotocol/clientCapabilities`],l=a&&c",
        "D-3-retry-completes-after-32022" =>
          "let i=r.params?._meta,a=i?.[`io.modelcontextprotocol/protocolVersion`]",
        "CG7-cache-miss-no-mirroring" => "a?a!==i&&o.push(`Mcp-Name header value"
      }

      for r <- red do
        oc = r["oc_counterpart"]
        assert oc["predicate"]["bytes"] == predicates[short.(r)], short.(r)

        assert byte_size(oc["predicate"]["bytes"]) ==
                 Enum.reduce(oc["predicate"]["byte_span"], &-/2)

        # Redundant takes precedence (Q5); each reading is recorded, and all fire.
        assert r["counterfactual"]["conforming_sdk_can_fail"], short.(r)
      end

      # Q6: the entailed one cites the crosswalk's two precedent lines, and each
      # cited line carries the precedent it is cited for.
      [entailed] =
        for r <- red, r["oc_counterpart"]["why_a3_missed"] =~ "entails its presence", do: r

      assert short.(entailed) == "CG2-outbound-meta"
      xw = "conformance/data/crosswalk-edges-client.json" |> File.read!() |> String.split("\n")

      cited =
        Regex.scan(
          ~r/crosswalk-edges-client\.json:(\d+)/,
          entailed["oc_counterpart"]["why_a3_missed"],
          capture: :all_but_first
        )
        |> Enum.map(fn [n] -> Enum.at(xw, String.to_integer(n) - 1) end)

      assert length(cited) == 2
      assert Enum.at(cited, 0) =~ ~s("evidence": "client_test.exs:153 — )
      assert Enum.at(cited, 1) =~ ~s("evidence": "capabilities_test.exs:98 — )
      assert Enum.all?(cited, &(&1 =~ "entail"))

      # Q7: the Mcp-Name row is a FULL match, and the crosswalk carries its
      # sibling's identical claim as an edge at routing_headers_test.exs:350.
      [name] = Enum.filter(red, &(short.(&1) == "CG7-cache-miss-no-mirroring"))
      assert name["rationale"] =~ "both agree, the full match"

      assert File.read!("conformance/data/crosswalk-edges-client.json") =~
               ~s("evidence": "routing_headers_test.exs:350 — `assert headers[\\"mcp-name\\"] == \\"test_custom_headers\\"`)
    end

    test "the one wrong_against_spec row POSTs a JSON-RPC response, which the client MUST NOT send",
         %{inputs: inputs} do
      [w] = Enum.filter(d1cii_rows(inputs), &(&1["disposition"] == "wrong_against_spec"))
      assert w["tag"] == "oc:none/no-oc-scenario/CG1-methodless-carries-no-routing-headers"

      assert w["spec"] == %{
               "url" =>
                 "https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http",
               "quote" => "The client **MUST NOT** send JSON-RPC _responses_."
             }

      # The message sent carries an id and a result and no method: a response.
      assert w["et_test"]["bytes"] =~
               ~s(:ok = HTTPClient.send_message(transport, %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}\))
    end

    test "the genuine rows each say which ground they hold",
         %{inputs: inputs} do
      genuine = Enum.filter(d1cii_rows(inputs), &(&1["disposition"] == "genuine_extra_coverage"))

      grounds =
        Enum.frequencies_by(genuine, fn r ->
          cond do
            r["protects"] =~ "no in-scope check scores our SSE parser" -> :sse_parser_unscored
            r["protects"] =~ "OC's null-passable ground" -> :null_passable
            true -> :unreached_input
          end
        end)

      assert grounds == %{sse_parser_unscored: 9, null_passable: 10, unreached_input: 2}
    end
  end

  # --- the D1-server-i record (MES-141; plan 29806/29807, ratified 29808) ------
  #
  # The first of three server-leg slices. MES-141 pins all three selectors now
  # (Q2 of 29807, ratified 29808): MES-142's by module, MES-143's as the
  # complement of the other two's modules. Together they must PARTITION the
  # view's 103 server-leg rows at 39/37/27; a refusal control names an
  # overlap, a gap and a row outside the leg, and a module moved across the
  # selectors is shown red.

  @d1si_selector %{
    "join" => "docs/conformance/etcc-attribution.json",
    "on" => "member.register_key",
    "leg" => "server",
    "module_in" => ["MCP.Server.ExtensionsNegotiationTest", "MCP.Server.JsonSchema202012Test"]
  }

  @d1sii_selector %{
    "join" => "docs/conformance/etcc-attribution.json",
    "on" => "member.register_key",
    "leg" => "server",
    "module_in" => [
      "MCP.Server.SubscriptionsDispatchTest",
      "MCP.Transport.SSETest",
      "MCP.Transport.StreamableHTTPStatelessTest",
      "MCP.Transport.SubscriptionsStreamTest"
    ]
  }

  @d1siii_selector %{
    "join" => "docs/conformance/etcc-attribution.json",
    "on" => "member.register_key",
    "leg" => "server",
    "module_not_in" => [
      "MCP.Server.ExtensionsNegotiationTest",
      "MCP.Server.JsonSchema202012Test",
      "MCP.Server.SubscriptionsDispatchTest",
      "MCP.Transport.SSETest",
      "MCP.Transport.StreamableHTTPStatelessTest",
      "MCP.Transport.SubscriptionsStreamTest"
    ]
  }

  defp d1si_rows(inputs) do
    {:ok, record} = inputs.records[@d1si]
    [section] = record["sections"]
    section["rows"]
  end

  defp server_rows(view_rows, legs),
    do: Enum.filter(view_rows, &(legs[&1["member"]["register_key"]] == "server"))

  describe "the D1-server-i record (MES-141)" do
    test "the section EQUALS the join selector's rows, both ways, over all 195; the 156 others carry a leg and module",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1si]
      [section] = record["sections"]
      {:ok, view} = inputs.views[@v1]
      assert length(view["rows"]) == 195

      assert {section["view"], section["closure"], section["owner"]} == {@v1, "open", "MES-143"}
      assert section["slice"]["selector"] == @d1si_selector
      assert join_equality(section["rows"], view["rows"], @d1si_selector) == :ok
      assert length(section["rows"]) == 39 and section["slice"]["rows"] == 39

      # Every one held: the Q-C admission leaves nothing outside the record.
      refute Map.has_key?(record, "not_yet_held")

      legs = leg_of()
      inside = join_selected(view["rows"], legs, @d1si_selector)
      others = view["rows"] -- inside

      assert Enum.frequencies_by(inside, & &1["member"]["module"]) ==
               %{
                 "MCP.Server.JsonSchema202012Test" => 23,
                 "MCP.Server.ExtensionsNegotiationTest" => 16
               }

      assert Enum.frequencies_by(others, &legs[&1["member"]["register_key"]]) ==
               %{"server" => 64, "none_determinable" => 21, "client" => 71}
    end

    test "the join equality refuses one added non-slice row and one dropped slice row",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@v1]
      rows = d1si_rows(inputs)
      inside = join_selected(view["rows"], leg_of(), @d1si_selector)

      # A server row of MES-142's slice: the kind a leg-only selector would admit.
      [other | _] = join_selected(view["rows"], leg_of(), @d1sii_selector)
      refute other in inside

      assert {:error, {added, none}} =
               join_equality(
                 rows ++ [%{other | "member" => other["member"]["register_key"]}],
                 view["rows"],
                 @d1si_selector
               )

      assert {MapSet.to_list(added), none} == {[A.key(other)], MapSet.new()}

      [first | rest] = rows
      assert {:error, {none, dropped}} = join_equality(rest, view["rows"], @d1si_selector)
      assert {none, MapSet.to_list(dropped)} == {MapSet.new(), [A.key(first)]}
    end

    test "the three pinned selectors PARTITION the view's 103 server-leg rows at 39/37/27, and MES-141's section meets its own",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@v1]
      legs = leg_of()
      server = server_rows(view["rows"], legs)
      assert length(server) == 103

      [i, ii, iii] =
        for sel <- [@d1si_selector, @d1sii_selector, @d1siii_selector],
            do: join_selected(view["rows"], legs, sel)

      assert {length(i), length(ii), length(iii)} == {39, 37, 27}
      assert partition([i, ii, iii], server) == :ok

      # The complement is of exactly the other two selectors' modules.
      assert @d1siii_selector["module_not_in"] ==
               Enum.sort(@d1si_selector["module_in"] ++ @d1sii_selector["module_in"])

      # SSETest also has client and none_determinable rows: the leg conjunct
      # is load-bearing in MES-142's selector, and dropping it admits them.
      sse = Enum.filter(view["rows"], &(&1["member"]["module"] == "MCP.Transport.SSETest"))

      assert Enum.frequencies_by(sse, &legs[&1["member"]["register_key"]]) ==
               %{"server" => 8, "client" => 10, "none_determinable" => 1}

      # The committed section, not only the selector.
      assert partition([d1si_rows(inputs), ii, iii], server) == :ok
    end

    test "the server partition check names an overlap, a gap and a row outside the leg, and a moved module goes red",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@v1]
      legs = leg_of()
      server = server_rows(view["rows"], legs)
      sel = &join_selected(view["rows"], legs, &1)
      [i, ii, iii] = Enum.map([@d1si_selector, @d1sii_selector, @d1siii_selector], sel)

      # Positive limb on these inputs, so each refusal below is the plant's.
      assert partition([i, ii, iii], server) == :ok

      [x | _] = ii

      assert partition([i ++ [x], ii, iii], server) ==
               {:error, {:overlap, MapSet.new([A.key(x)])}}

      [y | rest] = iii
      assert partition([i, ii, rest], server) == {:error, {:gap, MapSet.new([A.key(y)])}}

      [z | _] = Enum.filter(view["rows"], &(legs[&1["member"]["register_key"]] == "client"))
      z = %{z | "member" => z["member"]["register_key"]}

      assert partition([i ++ [z], ii, iii], server) ==
               {:error, {:outside, MapSet.new([A.key(z)])}}

      # Move one module across: SSETest copied into MES-141's selector overlaps
      # MES-142's; taken out of MES-142's and left out of the complement, it is
      # a gap; moved wholesale, the partition survives but the pinned counts do not.
      mod = "MCP.Transport.SSETest"
      sse = MapSet.new(Enum.filter(ii, &(&1["member"]["module"] == mod)), &A.key/1)
      i_plus = sel.(%{@d1si_selector | "module_in" => [mod | @d1si_selector["module_in"]]})
      ii_minus = sel.(%{@d1sii_selector | "module_in" => @d1sii_selector["module_in"] -- [mod]})

      assert partition([i_plus, ii, iii], server) == {:error, {:overlap, sse}}
      assert partition([i, ii_minus, iii], server) == {:error, {:gap, sse}}
      assert partition([i_plus, ii_minus, iii], server) == :ok
      refute {length(i_plus), length(ii_minus), length(iii)} == {39, 37, 27}
    end

    test "every row is one of the D1 family; the counts are the rows' enumeration, negatives included",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1si]
      rows = d1si_rows(inputs)
      assert Enum.all?(rows, &(&1["disposition"] in A.d1_dispositions()))

      enumerated =
        rows
        |> Enum.group_by(& &1["disposition"], & &1["tag"])
        |> Map.new(fn {d, tags} -> {d, %{"count" => length(tags), "tags" => tags}} end)

      assert record["counts"] == %{"bucket_1_server_i" => enumerated}

      assert Map.new(enumerated, fn {d, v} -> {d, v["count"]} end) == %{
               "genuine_extra_coverage" => 2,
               "redundant" => 35,
               "not_a_conformance_claim" => 1,
               "wrong_against_spec" => 1
             }
    end

    test "the routes equal the routed rows, both ways, numbered in record order; the wrong row carries none",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1si]
      rows = d1si_rows(inputs)
      routed = Enum.filter(rows, &Map.has_key?(&1, "routed_to"))

      assert Enum.filter(rows, &Map.has_key?(A.routes(), &1["disposition"])) == routed

      by_owner = Enum.frequencies_by(routed, &{&1["routed_to"]["owner"], &1["routed_to"]["to"]})
      assert by_owner == Map.new(record["routing"], &{{&1["owner"], &1["to"]}, &1["rows"]})
      assert by_owner == %{{"MES-152", "A3"} => 35, {"MES-153", "A2"} => 1}
      assert record["unused_routes"] == []

      # The PM's routing comments (29889): MES-152 comment 29887 lists the 35
      # redundant rows as items 1-35, and MES-153 comment 29888 the one
      # not-a-claim row as item 1, each in record order.
      a3 = &"MES-152 comment 29887, item #{&1}"
      a2 = &"MES-153 comment 29888, item #{&1}"

      assert Enum.map(routed, &{&1["tag"], &1["routed_to"]["owner_record"]}) == [
               {"oc:none/no-oc-scenario/extensions-offer-no-error", a3.(1)},
               {"oc:none/no-oc-scenario/extensions-offer-discover-unaffected", a3.(2)},
               {"oc:none/no-oc-scenario/extensions-offer-tools-list-unaffected", a3.(3)},
               {"oc:none/no-oc-scenario/extensions-offer-malformed-declaration", a2.(1)},
               {"oc:none/no-oc-scenario/extensions-config-non-object-value", a3.(4)},
               {"oc:none/no-oc-scenario/extensions-config-unencodable-dropped", a3.(5)},
               {"oc:none/no-oc-scenario/extensions-config-non-object-encoding-dropped", a3.(6)},
               {"oc:none/no-oc-scenario/extensions-config-valid-declaration-silent", a3.(7)},
               {"oc:none/no-oc-scenario/extensions-absent-by-default", a3.(8)},
               {"oc:none/no-oc-scenario/extensions-empty-declaration-absent", a3.(9)},
               {"oc:none/no-oc-scenario/extensions-declared-appears-verbatim", a3.(10)},
               {"oc:none/no-oc-scenario/extensions-invalid-identifier-dropped", a3.(11)},
               {"oc:none/no-oc-scenario/extensions-declaration-fixed-at-build", a3.(12)},
               {"oc:none/no-oc-scenario/content-list-is-never-injected-into", a3.(13)},
               {"oc:none/no-oc-scenario/extras-camelcase-key-named-not-silent", a3.(14)},
               {"oc:none/no-oc-scenario/extras-non-boolean-is-error-named", a3.(15)},
               {"oc:none/no-oc-scenario/structured-content-present-nil-is-json-null", a3.(16)},
               {"oc:none/no-oc-scenario/structured-content-absent-stays-absent", a3.(17)},
               {"oc:none/no-oc-scenario/structured-content-array-survives", a3.(18)},
               {"oc:none/no-oc-scenario/structured-content-empty-array-survives", a3.(19)},
               {"oc:none/no-oc-scenario/structured-content-empty-object-survives", a3.(20)},
               {"oc:none/no-oc-scenario/structured-content-empty-string-survives", a3.(21)},
               {"oc:none/no-oc-scenario/structured-content-false-survives", a3.(22)},
               {"oc:none/no-oc-scenario/structured-content-float-survives", a3.(23)},
               {"oc:none/no-oc-scenario/structured-content-null-survives", a3.(24)},
               {"oc:none/no-oc-scenario/structured-content-object-survives", a3.(25)},
               {"oc:none/no-oc-scenario/structured-content-string-survives", a3.(26)},
               {"oc:none/no-oc-scenario/structured-content-true-survives", a3.(27)},
               {"oc:none/no-oc-scenario/structured-content-zero-survives", a3.(28)},
               {"oc:none/no-oc-server-check/schema-2020-12-explicit-dialect-carried", a3.(29)},
               {"oc:none/no-oc-server-check/schema-2020-12-composition-keywords", a3.(30)},
               {"oc:none/no-oc-server-check/schema-2020-12-conditional-keywords", a3.(31)},
               {"oc:none/no-oc-server-check/schema-2020-12-reference-keywords", a3.(32)},
               {"oc:none/no-oc-server-check/schema-2020-12-whole-fixture-intact", a3.(33)},
               {"oc:none/no-oc-server-check/schema-2020-12-validation-keywords", a3.(34)},
               {"oc:none/no-oc-scenario/tool-arguments-delivered-unchanged", a3.(35)}
             ]

      assert [w] = Enum.filter(rows, &(&1["disposition"] == "wrong_against_spec"))
      refute Map.has_key?(w, "routed_to")
    end

    test "every assert a row says it read is an assert at that line, and each window lists them all",
         %{inputs: inputs} do
      for r <- d1si_rows(inputs) do
        %{"file" => f, "lines" => [from, to]} = r["et_test"]
        {:ok, src} = inputs.source_fun.(f)
        lines = String.split(src, "\n")

        read =
          for entry <- r["asserts_read"],
              [_, file, line, text] <- [Regex.run(~r/\A(test\/[^:]+):(\d+) — (.*)\z/s, entry)] do
            at = lines |> Enum.at(String.to_integer(line) - 1) |> String.trim()
            assert file == f and at == text and at =~ @assert_word, entry
            {file, String.to_integer(line)}
          end

        in_window =
          for {line, i} <- Enum.with_index(lines, 1),
              i in from..to,
              line =~ @assert_word,
              do: {f, i}

        assert length(read) == length(r["asserts_read"]) and read != [], r["tag"]
        assert read == in_window, r["tag"]
      end
    end

    # Q-C [authored 29813 | ratified 29816]: the generated W-1 members are held,
    # one row per label of the literal list, all sharing the one generated
    # test's window (the shared-anchor residual the swap audit records).
    test "the eleven generated W-1 rows are the literal list's labels, one window, each firing at :217",
         %{inputs: inputs} do
      prefix =
        "MCP.Server.JsonSchema202012Test/test W-1 — a handler can emit structuredContent, and it may be any JSON value "

      gen = Enum.filter(d1si_rows(inputs), &(&1["et_test"]["lines"] == [209, 219]))

      assert gen |> Enum.map(&String.trim_leading(&1["member"], prefix)) |> Enum.sort() ==
               Enum.sort(
                 for l <-
                       ~w(false true zero float string array object null) ++
                         ["empty string", "empty array", "empty object"],
                     do: l <> " survives to the wire"
               )

      for r <- gen do
        assert A.et_test_owner(r, inputs.source_fun) == :ok
        assert r["disposition"] == "redundant"
        assert r["counterfactual"]["reading"] =~ "fails at json_schema_2020_12_test.exs:217."
      end
    end

    # M9 (hop A figure 32, corrected at hop B): the measured figure is the 39
    # less the rows it names as not red, and those are exactly the rows whose
    # reading does not cite basic/index.mdx:380-382.
    test "M9's measured figure equals the rows whose reading cites the -32602 gate, both ways",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1si]
      rows = d1si_rows(inputs)
      [m9] = Enum.filter(record["mutations"], &(&1["id"] == "M9"))
      m = m9["measured"]

      cites =
        for r <- rows, r["counterfactual"]["reading"] =~ "basic/index.mdx:380-382", do: r["tag"]

      not_red = for r <- rows, r["tag"] not in cites, do: r["tag"]

      assert Enum.sort(m["slice_members_not_red"]) == Enum.sort(not_red)
      assert m["slice_members_red"] == length(cites)
      assert {m["slice_members_red"], m["slice_members"]} == {33, 39}
      assert m["slice_members_red"] + length(m["slice_members_not_red"]) == length(rows)
    end
  end

  # --- the D1-server-ii record (MES-142; plan 29941/29943/29944, ratified 29945) --
  #
  # The second of three server-leg slices, declared by the selector MES-141
  # pinned for it (@d1sii_selector). Verdicts as measured at hop A and made the
  # hop-B contract by 29950 (Q6), then moved by correction round 1 (PM 29962,
  # Q-R1: the listen-request-parses member is not a claim under M18):
  # 22 redundant, 15 not_a_conformance_claim, 0 genuine_extra_coverage,
  # 0 wrong_against_spec.

  defp d1sii_rows(inputs) do
    {:ok, record} = inputs.records[@d1sii]
    [section] = record["sections"]
    section["rows"]
  end

  defp d1sii_mutation(record, id) do
    [m] = Enum.filter(record["mutations"], &(&1["id"] == id))
    m
  end

  # The one `<name>_test.exs:N` a firing reading names, as "<basename>:N".
  defp fired_at(row) do
    [[base, n]] =
      Regex.scan(~r/\b([\w-]+_test\.exs):(\d+)\b/, row["counterfactual"]["reading"],
        capture: :all_but_first
      )

    "#{base}:#{n}"
  end

  # The line of the innermost `for ... do` or `capture_log(fn ->` inside
  # [from, line) whose block is still open at `line`; nil when there is none.
  defp enclosing_block(lines, from, line) do
    openers =
      for {l, i} <- Enum.with_index(lines, 1),
          i >= from and i < line,
          l =~ ~r/^\s*for .* do$/ or l =~ ~r/capture_log\(fn ->$/,
          do: {i, l |> String.length() |> Kernel.-(String.length(String.trim_leading(l)))}

    openers
    |> Enum.filter(fn {i, indent} ->
      close =
        Enum.find_value(Enum.with_index(lines, 1), fn {l, j} ->
          (j > i and l =~ ~r/^\s*end\)?$/ and
             String.length(l) - String.length(String.trim_leading(l)) == indent) && j
        end)

      close > line
    end)
    |> Enum.map(&elem(&1, 0))
    |> List.last()
  end

  # MES-141's @assert_word, plus `assert_raise`: the no-residue member's
  # firing line (:311) is one, and the word boundary in @assert_word stops at
  # its underscore.
  @d1sii_assert_word ~r/\b(assert|refute|assert_receive|refute_receive|assert_raise)\b/

  # Pinned here, not declared by the record: report §7's five limits this slice
  # has no member of, each with the terms searched for it (case-insensitive).
  @absent_limits %{
    "MRTR `tools/call`-only" => ["input_required", "requestState", "mrtr"],
    "4xx JSON-RPC error discarded by the client" => ["discard"],
    "no server-side `Mcp-Param-*` validation" => ["mcp-param"],
    "HTTP/2 exposure" => ["http2", "http/2"],
    "`accept-encoding: identity`" => ["accept-encoding"]
  }

  describe "the D1-server-ii record (MES-142)" do
    test "the section EQUALS the join selector's rows, both ways, over all 195; the 158 others carry a leg and module",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1sii]
      [section] = record["sections"]
      {:ok, view} = inputs.views[@v1]
      assert length(view["rows"]) == 195

      assert {section["view"], section["closure"], section["owner"]} == {@v1, "open", "MES-143"}
      assert section["slice"]["selector"] == @d1sii_selector
      assert join_equality(section["rows"], view["rows"], @d1sii_selector) == :ok
      assert length(section["rows"]) == 37 and section["slice"]["rows"] == 37
      refute Map.has_key?(record, "not_yet_held")

      legs = leg_of()
      inside = join_selected(view["rows"], legs, @d1sii_selector)
      others = view["rows"] -- inside

      assert Enum.frequencies_by(inside, & &1["member"]["module"]) == %{
               "MCP.Server.SubscriptionsDispatchTest" => 11,
               "MCP.Transport.StreamableHTTPStatelessTest" => 9,
               "MCP.Transport.SubscriptionsStreamTest" => 9,
               "MCP.Transport.SSETest" => 8
             }

      assert Enum.frequencies_by(others, &legs[&1["member"]["register_key"]]) ==
               %{"server" => 66, "none_determinable" => 21, "client" => 71}

      # The same four modules' rows the leg conjunct excludes, enumerated.
      excluded =
        for r <- others,
            r["member"]["module"] in @d1sii_selector["module_in"],
            do: {r["member"]["module"], legs[r["member"]["register_key"]]}

      assert Enum.frequencies(excluded) == %{
               {"MCP.Transport.SSETest", "client"} => 10,
               {"MCP.Transport.SSETest", "none_determinable"} => 1,
               {"MCP.Transport.SubscriptionsStreamTest", "none_determinable"} => 1
             }
    end

    test "the join equality refuses one added non-slice row and one dropped slice row",
         %{inputs: inputs} do
      {:ok, view} = inputs.views[@v1]
      rows = d1sii_rows(inputs)
      inside = join_selected(view["rows"], leg_of(), @d1sii_selector)

      # A server row of MES-141's slice: the kind a leg-only selector would admit.
      [other | _] = join_selected(view["rows"], leg_of(), @d1si_selector)
      refute other in inside

      assert {:error, {added, none}} =
               join_equality(
                 rows ++ [%{other | "member" => other["member"]["register_key"]}],
                 view["rows"],
                 @d1sii_selector
               )

      assert {MapSet.to_list(added), none} == {[A.key(other)], MapSet.new()}

      [first | rest] = rows
      assert {:error, {none, dropped}} = join_equality(rest, view["rows"], @d1sii_selector)
      assert {none, MapSet.to_list(dropped)} == {MapSet.new(), [A.key(first)]}
    end

    test "every row is one of the D1 family; the counts are the rows' enumeration, negatives included",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1sii]
      rows = d1sii_rows(inputs)
      assert Enum.all?(rows, &(&1["disposition"] in A.d1_dispositions()))

      enumerated =
        Map.new(A.d1_dispositions(), fn d ->
          tags = for r <- rows, r["disposition"] == d, do: r["tag"]
          {d, %{"count" => length(tags), "tags" => tags}}
        end)

      assert record["counts"] == %{"bucket_1_server_ii" => enumerated}

      assert Map.new(enumerated, fn {d, v} -> {d, v["count"]} end) == %{
               "genuine_extra_coverage" => 0,
               "redundant" => 22,
               "not_a_conformance_claim" => 15,
               "wrong_against_spec" => 0
             }

      # No genuine row: the only readings that do not fire are two redundant
      # rows' (redundant takes precedence, 29735 Q5). The hop-A genuine row
      # (29961 Q-R1) fires under M18, at its own :89, and protects nothing now.
      assert for(r <- rows, !r["counterfactual"]["conforming_sdk_can_fail"], do: r["tag"]) == [
               "oc:none/no-oc-scenario/absent-notifications--32602",
               "oc:none/no-oc-scenario/listen-id-echoed-uncoerced"
             ]

      assert Enum.all?(
               rows,
               &(&1["counterfactual"]["conforming_sdk_can_fail"] or
                   &1["disposition"] == "redundant")
             )

      [lr] = Enum.filter(rows, &(&1["tag"] == "oc:none/no-oc-scenario/listen-request-parses"))
      assert lr["disposition"] == "not_a_conformance_claim"
      assert fired_at(lr) == "subscriptions_dispatch_test.exs:89"
      assert fired_at(lr) in d1sii_mutation(record, "M18")["reddens"]
      refute Map.has_key?(lr, "protects")
    end

    test "the routes equal the routed rows, both ways, numbered in record order; every row is routed",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1sii]
      rows = d1sii_rows(inputs)
      routed = Enum.filter(rows, &Map.has_key?(&1, "routed_to"))

      assert Enum.filter(rows, &Map.has_key?(A.routes(), &1["disposition"])) == routed

      by_owner = Enum.frequencies_by(routed, &{&1["routed_to"]["owner"], &1["routed_to"]["to"]})
      assert by_owner == Map.new(record["routing"], &{{&1["owner"], &1["to"]}, &1["rows"]})
      assert by_owner == %{{"MES-152", "A3"} => 22, {"MES-153", "A2"} => 15}
      assert record["unused_routes"] == []

      # The PM's routing comments (29956): MES-152 comment 29954 lists the 22
      # redundant rows as items 1-22, in record order, and stands. Correction
      # round 1 (29962) added the listen-request-parses member to MES-153 in its
      # record position; MES-153 comment 29973 supersedes 29955 in full and
      # lists the 15 not-a-claim rows as items 1-15, in record order (29974).
      a3 = &"MES-152 comment 29954, item #{&1}"
      a2 = &"MES-153 comment 29973, item #{&1}"

      assert Enum.map(routed, &{&1["tag"], &1["routed_to"]["owner_record"]}) == [
               {"oc:none/no-oc-scenario/absent-notifications--32602", a3.(1)},
               {"oc:none/no-oc-scenario/empty-filter-is-legal", a2.(1)},
               {"oc:none/no-oc-scenario/close-response-shape", a2.(2)},
               {"oc:none/no-oc-scenario/listen-id-echoed-uncoerced", a3.(2)},
               {"oc:none/no-oc-scenario/listen-request-parses", a2.(3)},
               {"oc:none/no-oc-scenario/ack-omits-refused-type", a3.(3)},
               {"oc:none/no-oc-scenario/ack-equals-enforced-set", a3.(4)},
               {"oc:none/no-oc-scenario/uri-filter-key-style", a3.(5)},
               {"oc:none/no-oc-scenario/ack-omits-unauthorized-uri", a3.(6)},
               {"oc:none/no-oc-scenario/handler-refusal--32603", a3.(7)},
               {"oc:none/no-oc-scenario/refusals-above-the-handler", a3.(8)},
               {"oc:none/no-oc-scenario/sse-frame-all-fields", a2.(4)},
               {"oc:none/no-oc-scenario/sse-frame-empty-data", a2.(5)},
               {"oc:none/no-oc-scenario/sse-frame-event-type-and-data", a2.(6)},
               {"oc:none/no-oc-scenario/sse-frame-data-only", a2.(7)},
               {"oc:none/no-oc-scenario/sse-frame-multiline-folding", a2.(8)},
               {"oc:none/no-oc-scenario/sse-message-frame", a2.(9)},
               {"oc:none/no-oc-scenario/sse-message-event-id", a2.(10)},
               {"oc:none/no-oc-scenario/sse-message-custom-event-type", a2.(11)},
               {"oc:none/no-oc-scenario/verb-405-allow-POST", a2.(12)},
               {"oc:none/no-oc-scenario/collector-start-failure", a3.(9)},
               {"oc:none/no-oc-scenario/identity-factory-raises-yields-500", a3.(10)},
               {"oc:none/no-oc-server-check/McpName-vs-params-name", a3.(11)},
               {"oc:none/no-oc-scenario/malformed-body--32700", a2.(13)},
               {"oc:none/no-oc-scenario/no-residue-after-raise", a3.(12)},
               {"oc:none/no-oc-server-check/McpMethod-vs-method", a3.(13)},
               {"oc:none/no-oc-server-check/McpName-vs-params-uri", a3.(14)},
               {"oc:none/no-oc-scenario/two-instance-round-robin", a3.(15)},
               {"oc:none/no-oc-scenario/stream-start-failure", a3.(16)},
               {"oc:none/no-oc-scenario/no-cross-instance-delivery", a3.(17)},
               {"oc:none/no-oc-scenario/close-asymmetry-response-first", a3.(18)},
               {"oc:none/no-oc-scenario/close-frame-decision", a2.(14)},
               {"oc:none/no-oc-scenario/idle-stream-emits-comments", a3.(19)},
               {"oc:none/no-oc-scenario/sse-comment-is-a-bare-colon", a2.(15)},
               {"oc:none/no-oc-scenario/collector-lifetime-ends-first", a3.(20)},
               {"oc:none/no-oc-scenario/listen-refused-above-handler", a3.(21)},
               {"oc:none/no-oc-scenario/sse-response-headers", a3.(22)}
             ]

      # With no genuine row, every row is routed.
      assert routed == rows
    end

    test "every assert a row says it read is an assert at that line, and each window lists them all",
         %{inputs: inputs} do
      for r <- d1sii_rows(inputs) do
        %{"file" => f, "lines" => [from, to]} = r["et_test"]
        {:ok, src} = inputs.source_fun.(f)
        lines = String.split(src, "\n")

        read =
          for entry <- r["asserts_read"],
              [_, file, line, text] <- [Regex.run(~r/\A(test\/[^:]+):(\d+) — (.*)\z/s, entry)] do
            at = lines |> Enum.at(String.to_integer(line) - 1) |> String.trim()
            assert file == f and at == text and at =~ @d1sii_assert_word, entry
            {file, String.to_integer(line)}
          end

        in_window =
          for {line, i} <- Enum.with_index(lines, 1),
              i in from..to,
              line =~ @d1sii_assert_word,
              # A comment is not an assert (the round-robin member's :350).
              not String.starts_with?(String.trim_leading(line), "#"),
              do: {f, i}

        assert length(read) == length(r["asserts_read"]) and read != [], r["tag"]
        assert read == in_window, r["tag"]
      end
    end

    # Every firing line was MEASURED (29938 item 3): the line a firing reading
    # names is an assert in the row's window and is among the lines its
    # mutation reddened, as the record lists them. Where ExUnit reports the
    # (test) frame at an enclosing `for` or capture_log, the reading names the
    # failing assert inside it, and the row says so in `exunit_frame`: the set
    # of rows carrying it EQUALS the set whose named line is so enclosed.
    test "each firing line is an assert its mutation reddened; the enclosed-frame rows are exactly the rows that say so",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1sii]
      rows = d1sii_rows(inputs)
      firing = Enum.filter(rows, & &1["counterfactual"]["conforming_sdk_can_fail"])
      assert length(firing) == 35

      reddened =
        for m <- record["mutations"],
            l <- (m["reddens"] || []) ++ (m["also_reddens_in_slice"] || []),
            [at] = Regex.run(~r/\A[\w-]+_test\.exs:\d+/, l),
            into: MapSet.new(),
            do: at

      enclosed =
        for r <- firing, into: %{} do
          %{"file" => f, "lines" => [from, to]} = r["et_test"]
          {:ok, src} = inputs.source_fun.(f)
          lines = String.split(src, "\n")
          [_, n] = String.split(fired_at(r), ":")
          n = String.to_integer(n)

          assert n in from..to and Enum.at(lines, n - 1) =~ @d1sii_assert_word, r["tag"]

          assert fired_at(r) in reddened,
                 "#{r["tag"]}: #{fired_at(r)} was reddened by no mutation"

          {r["tag"], {enclosing_block(lines, from, n), n}}
        end

      said =
        for r <- firing, f = r["counterfactual"]["exunit_frame"], into: %{} do
          {r["tag"], {f["reported_at"], f["failing_assert"]}}
        end

      assert said == Map.reject(enclosed, fn {_, {at, _}} -> is_nil(at) end)

      assert said == %{
               "oc:none/no-oc-scenario/verb-405-allow-POST" => {271, 278},
               "oc:none/no-oc-scenario/stream-start-failure" => {559, 566},
               "oc:none/no-oc-scenario/collector-lifetime-ends-first" => {595, 600}
             }

      # And the enclosing kind is the opener's.
      for r <- firing, f = r["counterfactual"]["exunit_frame"] do
        {:ok, src} = inputs.source_fun.(r["et_test"]["file"])
        opener = src |> String.split("\n") |> Enum.at(f["reported_at"] - 1)
        kind = if opener =~ "capture_log", do: "capture_log", else: "for"
        assert f["enclosing"] == kind, r["tag"]
      end
    end

    test "the enclosed-frame detector sees a capture_log and a for, and not a line after either closes",
         %{inputs: inputs} do
      {:ok, src} = inputs.source_fun.("test/mcp/transport/subscriptions_stream_test.exs")
      lines = String.split(src, "\n")
      assert enclosing_block(lines, 588, 600) == 595
      # :623 is after the capture_log closes at :617.
      assert enclosing_block(lines, 588, 623) == nil

      {:ok, src} = inputs.source_fun.("test/mcp/transport/streamable_http_stateless_test.exs")
      lines = String.split(src, "\n")
      assert enclosing_block(lines, 266, 278) == 271
      assert enclosing_block(lines, 284, 292) == nil
    end

    # PM 29945 Q2: M9 stays MES-141's; M9h and M9f are their own mutations, and
    # #27 cites each mutation's line under its own name, never one merged line.
    test "the M9 family's measured figures equal the rows whose firing line each reddened",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1sii]
      rows = d1sii_rows(inputs)
      [m9, m9h, m9f, m10] = Enum.map(~w(M9 M9h M9f M10), &d1sii_mutation(record, &1))

      line_under = fn r, id ->
        (r["counterfactual"]["firing_lines_by_mutation"] || %{})[id] || fired_at(r)
      end

      red_under = fn m ->
        for r <- rows,
            r["counterfactual"]["conforming_sdk_can_fail"],
            r["counterfactual"]["reading"] =~ "basic/index.mdx:380-382",
            line_under.(r, m["id"]) in m["reddens"],
            do: r["tag"]
      end

      for {m, n} <- [{m9, 14}, {m9h, 19}, {m9f, 20}] do
        assert length(red_under.(m)) == n and m["measured"]["slice_members_red"] == n, m["id"]
        assert length(m["reddens"]) == n, m["id"]
      end

      # M9's not-red list is the complement, both ways.
      assert Enum.sort(m9["measured"]["slice_members_not_red"]) ==
               Enum.sort(Enum.map(rows, & &1["tag"]) -- red_under.(m9))

      # Each widening is a superset: M9 < M9h < M9f, and M9f adds only #23.
      assert red_under.(m9) -- red_under.(m9h) == []
      assert red_under.(m9h) -- red_under.(m9f) == []

      assert red_under.(m9f) -- red_under.(m9h) == [
               "oc:none/no-oc-server-check/McpName-vs-params-name"
             ]

      [uri] =
        Enum.filter(rows, &(&1["tag"] == "oc:none/no-oc-server-check/McpName-vs-params-uri"))

      assert uri["counterfactual"]["firing_lines_by_mutation"] == %{
               "M9" => "streamable_http_stateless_test.exs:122",
               "M9h" => "streamable_http_stateless_test.exs:121",
               "M9f" => "streamable_http_stateless_test.exs:118",
               "M10" => "streamable_http_stateless_test.exs:121"
             }

      for {id, at} <- uri["counterfactual"]["firing_lines_by_mutation"] do
        assert at in d1sii_mutation(record, id)["reddens"], id
      end

      # M10 (Q3): a second reading on exactly the rows it reddens, owned by
      # MES-155, and every one of them already redundant.
      m10_rows =
        for r <- rows, s <- r["second_readings"] || [], s["mutation"] == "M10", do: {r, s}

      assert length(m10_rows) == 13 and m10["measured"]["slice_members_red"] == 13

      assert Enum.sort(
               for {r, s} <- m10_rows,
                   do: "#{Path.basename(r["et_test"]["file"])}:#{s["fails_at"]}"
             ) ==
               Enum.sort(m10["reddens"])

      assert Enum.all?(m10_rows, fn {r, s} ->
               r["disposition"] == "redundant" and s["remediation_owner"] == "MES-155"
             end)
    end

    # CR 29960 B1, PM 29962: M18 enforces basic/index.mdx:380-382 in the filter
    # parser. It reddens the listen-request-parses member at :89 (its firing
    # line), the empty-filter member at :166 (a second reading), and otherwise
    # only redundant rows' own M9 lines.
    test "M18's figures equal its lines; beyond its two readings it reddens only redundant rows' M9 lines",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1sii]
      rows = d1sii_rows(inputs)
      [m9, m18] = Enum.map(~w(M9 M18), &d1sii_mutation(record, &1))

      assert m18["reddens"] == ["subscriptions_dispatch_test.exs:89"]
      red = m18["reddens"] ++ m18["also_reddens_in_slice"]
      assert length(red) == m18["measured"]["slice_members_red"]
      assert m18["measured"]["slice_members_red"] == 13
      assert m18["measured"]["module_tests_red"] == 42

      at = fn r, n -> "#{Path.basename(r["et_test"]["file"])}:#{n}" end

      # Each reddened line is inside exactly one row's window.
      owners =
        for l <- red do
          [base, n] = String.split(l, ":")
          n = String.to_integer(n)

          [r] =
            Enum.filter(rows, fn r ->
              %{"file" => f, "lines" => [from, to]} = r["et_test"]
              Path.basename(f) == base and n in from..to
            end)

          {r, l}
        end

      [{lr, _}, {ef, _} | rest] = owners
      assert lr["tag"] == "oc:none/no-oc-scenario/listen-request-parses"
      assert ef["tag"] == "oc:none/no-oc-scenario/empty-filter-is-legal"
      assert [%{"mutation" => "M18", "fails_at" => 166}] = ef["second_readings"]
      assert at.(ef, 166) in m18["also_reddens_in_slice"]

      for {r, l} <- rest do
        assert r["disposition"] == "redundant" and l in m9["reddens"], r["tag"]
      end
    end

    # N3 (CR 29961; PM 29962, answering 29945 Q2's "with its diff"): every
    # recorded mutation carries its exact edits, each `old` still occurs
    # exactly once in its lib/ file at this tree, and M9's edits are MES-141's
    # byte for byte. MES-141's record carries its M9 only as prose, so its edits
    # are pinned here from the spec MES-141 ran (/tmp/mes141m/m9all.json, the
    # file CR compared in 29961 item 2).
    @mes141_m9_edits [
      %{
        "file" => "lib/mcp/server/dispatch.ex",
        "old" =>
          "    handle_request(method, id, params, seal_stream_sink(ctx, method), config)\n",
        "new" =>
          "    meta = (is_map(params) && params[\"_meta\"]) || %{}\n\n" <>
            "    if not (is_map(meta) and Map.has_key?(meta, \"io.modelcontextprotocol/protocolVersion\") and\n" <>
            "              Map.has_key?(meta, \"io.modelcontextprotocol/clientCapabilities\")),\n" <>
            "       do: reply(id, Error.invalid_params(\"missing required _meta field\"), config),\n" <>
            "       else: handle_request(method, id, params, seal_stream_sink(ctx, method), config)\n"
      }
    ]

    test "every recorded mutation carries its exact edits, and M9's are MES-141's byte for byte",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1sii]
      ms = record["mutations"]

      assert Enum.map(ms, & &1["id"]) ==
               ~w(M9 M9h M9f M10 M11 M12 M13 M14 M15 M16 M17 M18)

      for m <- ms do
        assert m["edits"] != [], m["id"]

        for %{"file" => f, "old" => old, "new" => new} = e <- m["edits"] do
          assert map_size(e) == 3 and String.starts_with?(f, "lib/"), m["id"]
          assert old != new, m["id"]
          # The file `lib` names is the file the edits change.
          assert String.contains?(m["lib"], f), m["id"]
          {:ok, src} = inputs.source_fun.(f)
          assert length(String.split(src, old)) == 2, "#{m["id"]}: #{f}"
        end
      end

      assert d1sii_mutation(record, "M9")["edits"] == @mes141_m9_edits

      # M9h and M9f are M9 widened: their first edit is M9's.
      for id <- ~w(M9h M9f) do
        assert hd(d1sii_mutation(record, id)["edits"]) == hd(@mes141_m9_edits), id
      end
    end

    test "report §7's limits: two have members, named on their rows; the other five have none, by a search that reaches §7",
         %{inputs: inputs} do
      {:ok, record} = inputs.records[@d1sii]
      rows = d1sii_rows(inputs)
      kl = record["known_limits"]
      assert kl["at"]["file"] == "docs/conformance/report-2026-07-28.md"
      assert kl["at"]["lines"] == [326, 326]
      section7 = kl["at"]["bytes"]

      with_limit = for r <- rows, r["known_limit"], do: {r["tag"], r["known_limit"]["limit"]}

      assert with_limit == [
               {"oc:none/no-oc-scenario/refusals-above-the-handler",
                "`subscriptions/listen` server-HTTP-only"},
               {"oc:none/no-oc-scenario/two-instance-round-robin", "`server/discover` ungated"}
             ]

      for {_, limit} <- with_limit, do: assert(section7 =~ limit)

      for r <- rows, l = r["known_limit"] do
        assert l["at"] == "docs/conformance/report-2026-07-28.md:326"
        %{"lines" => [from, to]} = r["et_test"]

        for [n] <- Regex.scan(~r/_test\.exs:(\d+)/, l["member_part"], capture: :all_but_first),
            do: assert(String.to_integer(n) in from..to, r["tag"])
      end

      # The record's search catalogue is the pinned one.
      assert kl["absent_limit_search"] == @absent_limits

      hits =
        for {limit, terms} <- @absent_limits, into: %{} do
          re = Regex.compile!(Enum.map_join(terms, "|", &Regex.escape/1), "i")
          # Reach: the terms find the §7 row they stand for.
          assert section7 =~ re, limit
          {limit, for(r <- rows, r["et_test"]["bytes"] =~ re, do: r["tag"])}
        end

      # The two hits, hand-checked, and neither is the limit: a comment that
      # our SSE parser discards comment lines (subscriptions_stream_test.exs:388)
      # and a driver discarding a notification, logged (:623). No client
      # discards a 4xx in either.
      assert hits == %{
               "MRTR `tools/call`-only" => [],
               "4xx JSON-RPC error discarded by the client" => [
                 "oc:none/no-oc-scenario/idle-stream-emits-comments",
                 "oc:none/no-oc-scenario/collector-lifetime-ends-first"
               ],
               "no server-side `Mcp-Param-*` validation" => [],
               "HTTP/2 exposure" => [],
               "`accept-encoding: identity`" => []
             }

      refute Enum.any?(rows, &(&1["et_test"]["bytes"] =~ ~r/initialize/i))
      assert section7 =~ ~r/initialize/i
    end
  end

  # --- every D1 record in the directory (MES-139; authored 29729, ratified 29731) --
  #
  # MES-138's both-ways unit, generalised: it runs over every record the walk
  # derives from the directory (MES-135: never a hand-held list) and every row
  # in a section bound to a D1 view, so a future D1 record is held without an
  # edit here. G32 holds the reading's SHAPE (counterfactual_missing); this
  # holds it too, as a belt, and holds what G32 does not: the reading agrees
  # with the disposition (29731, Q2), and a firing reading's line lies inside
  # the row's own et_test window (29731, Q3).

  # Pinned here, independently of the guard's module attributes.
  @fires_cite ~r/\b([\w-]+_test\.exs):(\d+)\b/
  @none_can ~r/\ANone can: .*(\.mdx|\.ts|§)/u

  # The lines of every `setup do ... end` block (two-space describe, four-space
  # setup) inside the describe that encloses `line` of `file`; [] at top level.
  defp describe_setup_lines(inputs, file, line) do
    {:ok, src} = inputs.source_fun.(file)
    lines = src |> String.split("\n") |> Enum.with_index(1)
    above = lines |> Enum.take(line) |> Enum.reverse()

    case Enum.find(above, &(elem(&1, 0) =~ ~r/^  describe "/)) do
      nil -> []
      {_, d} -> setup_lines(lines, d, closing_line(lines, d, "  end"))
    end
  end

  defp setup_lines(lines, d, d_end) do
    for {l, j} <- lines,
        j > d and j < d_end and l =~ ~r/^    setup( .*)? do$/,
        k <- j..closing_line(lines, j, "    end"),
        do: k
  end

  # The first line after `from` that is exactly `closing`.
  defp closing_line(lines, from, closing) do
    Enum.find_value(lines, fn {l, j} -> (j > from and String.trim_trailing(l) == closing) && j end)
  end

  defp d1_records(inputs) do
    for path <- inputs.walk,
        {:ok, rec} = inputs.records[path],
        sections = Enum.filter(rec["sections"], &(&1["view"] in A.d1_views())),
        sections != [],
        do: {path, rec, sections}
  end

  describe "every D1 record in the directory (MES-139)" do
    test "the unit runs over every D1 record and row the walk finds, and no fewer",
         %{inputs: inputs} do
      recs = d1_records(inputs)
      rows = for {_, _, ss} <- recs, s <- ss, r <- s["rows"], do: r

      # Reach, so the unit cannot pass over an empty set.
      assert Enum.map(recs, &elem(&1, 0)) == [@d1ci, @d1cii, @d1, @d1si, @d1sii]
      assert length(rows) == 177

      # Independently of d1_records/1: every row of every record bound to a D1
      # view carries a D1 disposition, and every D1 disposition sits in one.
      all =
        for path <- inputs.walk,
            {:ok, rec} = inputs.records[path],
            s <- rec["sections"],
            r <- s["rows"],
            do: {s["view"] in A.d1_views(), r["disposition"] in A.d1_dispositions()}

      assert Enum.count(all, &(&1 == {true, true})) == length(rows)
      assert Enum.filter(all, &(elem(&1, 0) != elem(&1, 1))) == []
    end

    test "every D1 row records one reading of the right shape; a firing one cites a line inside its own et_test",
         %{inputs: inputs} do
      for {path, _, ss} <- d1_records(inputs), s <- ss, r <- s["rows"] do
        at = "#{Path.basename(path)} #{inspect(A.key(r))}"
        cf = r["counterfactual"]
        assert is_map(cf), at
        assert is_boolean(cf["conforming_sdk_can_fail"]), at
        assert is_binary(cf["reading"]) and String.trim(cf["reading"]) != "", at
        refute cf["reading"] =~ ~r/[\r\n]/, at

        if cf["conforming_sdk_can_fail"] do
          cites = Regex.scan(@fires_cite, cf["reading"], capture: :all_but_first)
          assert cites != [], at
          %{"file" => f, "lines" => [from, to]} = r["et_test"]

          for [base, n] <- cites do
            assert base == Path.basename(f), "#{at}: #{base} is not #{f}"
            n = String.to_integer(n)

            # MES-141 Q-D ([authored 29813 | ratified 29816]): where the member
            # fails in its describe's setup, before any test-body frame exists,
            # the setup line is admitted, and only when the reading says so and
            # the line lies in a `setup` block of the describe enclosing the window.
            assert n in from..to or
                     (cf["reading"] =~ "in the describe setup" and
                        n in describe_setup_lines(inputs, f, from)),
                   "#{at}: :#{n} outside #{from}..#{to}"
          end
        else
          assert cf["reading"] =~ @none_can, at
        end
      end
    end

    # Amended by the Q5 ruling [authored 29733/29734 | ratified 29735]: the
    # restriction was "non-wrong_against_spec rows" (29731, Q2); it is now
    # "non-wrong_against_spec AND non-redundant rows". A member with a missed
    # edge is not truly a bucket-1 member, so redundant takes precedence and
    # its reading, firing or not, is recorded honestly without deciding the row.
    test "per record, the not-a-claim set EQUALS the rows whose reading fires, both ways, outside wrong_against_spec and redundant",
         %{inputs: inputs} do
      for {path, _, ss} <- d1_records(inputs) do
        rows =
          for s <- ss,
              r <- s["rows"],
              r["disposition"] not in ~w(wrong_against_spec redundant),
              do: r

        fires =
          for r <- rows,
              r["counterfactual"]["conforming_sdk_can_fail"],
              into: MapSet.new(),
              do: A.key(r)

        not_a_claim =
          for r <- rows,
              r["disposition"] == "not_a_conformance_claim",
              into: MapSet.new(),
              do: A.key(r)

        assert MapSet.difference(fires, not_a_claim) == MapSet.new(), path
        assert MapSet.difference(not_a_claim, fires) == MapSet.new(), path
      end
    end

    test "every D1 record states the question, its provenances, and one unit per D1 view it binds",
         %{inputs: inputs} do
      for {path, rec, ss} <- d1_records(inputs) do
        cf = rec["counterfactual"]
        assert cf["question"] == "could a conforming SDK fail this unit?", path
        assert cf["provenance"] == "[authored 29707 N5 | ratified 29708]", path
        assert cf["grain_provenance"] == "[authored 29713 | ratified 29717]", path
        assert cf["unit_provenance"] == "[authored 29721 B-A | ratified 29723]", path

        assert Map.keys(cf["unit"]) == ss |> Enum.map(& &1["view"]) |> Enum.uniq() |> Enum.sort(),
               path

        if cf["unit"][@v1], do: assert(cf["unit"][@v1] =~ ~r/\Athe member: /, path)
        if cf["unit"][@vcu], do: assert(cf["unit"][@vcu] =~ ~r/\Athe claim: /, path)
      end
    end
  end

  # --- the D1 family, unit by unit (MES-138; authored 29691, ratified 29693) -----

  @d1v "docs/conformance/buckets/bucket-1-2026-07-28.json"

  # The synthetic inputs, bound to a D1 view path instead of the neutral one.
  defp d1_inputs(view_rows, rows, view \\ @d1v) do
    base = inputs(view_rows, [section(rows)])
    {:ok, rec} = base.records[@rec]

    %{
      base
      | anchor: [view],
        views: %{view => base.views[@view]},
        records: %{
          @rec => {:ok, %{rec | "sections" => [section(rows, "closed", %{"view" => view})]}}
        }
    }
  end

  defp d1_kinds(inputs),
    do:
      inputs
      |> A.audit(%{not_owed: %{}, pending: %{}})
      |> Map.fetch!(:defects)
      |> Enum.map(& &1.kind)

  # An oc:none/ view row, and a D1 row over it with no harness span under check.
  # Like a real bucket-1 view row, it carries no shape, verdicts or bucket.
  defp nd,
    do:
      "M/test a"
      |> view_row(nil, "oc:none/no-oc-scenario/x", %{"cg" => nil})
      |> Map.drop(~w(shape verdicts bucket))

  # Every D1 row records one counterfactual reading (MES-139; authored 29729,
  # ratified 29731), so the well-formed synthetic row carries one.
  @reading %{"conforming_sdk_can_fail" => false, "reading" => "None can: schema.ts:1 says so."}

  defp d1_row(disp, extra) do
    row(
      nd(),
      Map.merge(
        %{
          "check" => %{"requires" => "none"},
          "disposition" => disp,
          "counterfactual" => @reading
        },
        extra
      )
    )
  end

  @routed %{"owner" => "MES-152", "owner_record" => "the MES-152 routing comment"}
  @counterpart %{
    "token" => "oc:e",
    "site" => %{"harness_sha256" => "abc", "byte_span" => [2, 4], "bytes" => "x"},
    "why_a3_missed" => "one line"
  }
  @spec_cite %{
    "url" => "https://modelcontextprotocol.io/specification/2026-07-28/basic",
    "quote" => "one verbatim line"
  }

  defp good_d1 do
    [
      d1_row("genuine_extra_coverage", %{"protects" => "stdio framing, which OC never drives"}),
      d1_row("redundant", %{
        "oc_counterpart" => @counterpart,
        "routed_to" => Map.put(@routed, "to", "A3")
      }),
      d1_row("not_a_conformance_claim", %{
        "routed_to" => %{@routed | "owner" => "MES-153"} |> Map.put("to", "A2")
      }),
      d1_row("wrong_against_spec", %{"spec" => @spec_cite})
    ]
  end

  describe "the D1 family, unit by unit (MES-138)" do
    test "each of the four, well formed, in a section bound to a D1 view: CLEAN" do
      for r <- good_d1() do
        assert d1_kinds(d1_inputs([nd()], [r])) == [], r["disposition"]
      end
    end

    test "a claim-unmatched-view/1 view is admitted, and each of the four is CLEAN over it" do
      cu = "docs/conformance/buckets/claim-unmatched-2026-07-28.json"
      vr = view_row("M/test a", "claim a", "oc:none/no-oc-scenario/x")

      for r <- good_d1() do
        r = Map.merge(r, %{"claim" => "claim a", "echo" => A.echo(vr)})
        i = d1_inputs([vr], [r], cu)
        i = put_in(i.views[cu], {:ok, %{"schema" => "claim-unmatched-view/1", "rows" => [vr]}})
        assert d1_kinds(i) == [], r["disposition"]
      end
    end

    test "the refusals name G32 and the kind" do
      [g | _] = good_d1()

      [line] =
        d1_inputs([nd()], [Map.delete(g, "protects")])
        |> A.audit(%{not_owed: %{}, pending: %{}})
        |> Map.fetch!(:defects)
        |> Enum.map(&A.format_defect/1)

      assert line =~ ~r/^G32 protects_missing — /
    end

    test "protects_missing: a genuine_extra_coverage row without a one-line protects" do
      [g | _] = good_d1()

      for bad <- [:absent, nil, "", "  ", "two\nlines", 7] do
        r = if bad == :absent, do: Map.delete(g, "protects"), else: Map.put(g, "protects", bad)
        assert d1_kinds(d1_inputs([nd()], [r])) == [:protects_missing], inspect(bad)
      end
    end

    test "counterpart_missing: a redundant row without a tied, explained oc_counterpart" do
      [_, red | _] = good_d1()

      for {label, oc} <- [
            {"absent", :absent},
            {"not a map", "oc:e"},
            {"token not in the locator", %{@counterpart | "token" => "oc:nope"}},
            {"token absent", Map.delete(@counterpart, "token")},
            {"site absent", Map.delete(@counterpart, "site")},
            {"site a repository citation",
             %{
               @counterpart
               | "site" => %{"file" => @src, "lines" => [2, 2], "bytes" => "assert x == 1"}
             }},
            {"site off every locator site",
             put_in(@counterpart, ["site", "byte_span"], [20, 30])},
            {"site on ANOTHER token's site only",
             %{@counterpart | "token" => "oc:t1"} |> put_in(["site", "byte_span"], [20, 30])},
            {"why_a3_missed absent", Map.delete(@counterpart, "why_a3_missed")},
            {"why_a3_missed two lines", %{@counterpart | "why_a3_missed" => "a\nb"}}
          ] do
        r =
          if oc == :absent,
            do: Map.delete(red, "oc_counterpart"),
            else: Map.put(red, "oc_counterpart", oc)

        assert d1_kinds(d1_inputs([nd()], [r])) == [:counterpart_missing], label
      end
    end

    test "routed_to_missing: a redundant or not_a_conformance_claim row without its own route" do
      [_, red, nac | _] = good_d1()

      for {r, to, wrong_to} <- [{red, "A3", "A2"}, {nac, "A2", "A3"}],
          {label, routed} <- [
            {"absent", :absent},
            {"the other route", r["routed_to"] |> Map.put("to", wrong_to)},
            {"no to", Map.delete(r["routed_to"], "to")},
            {"owner not a ticket key", %{r["routed_to"] | "owner" => "someone"}},
            {"owner_record two lines", %{r["routed_to"] | "owner_record" => "a\nb"}},
            {"owner_record absent", Map.delete(r["routed_to"], "owner_record")}
          ] do
        planted =
          if routed == :absent,
            do: Map.delete(r, "routed_to"),
            else: Map.put(r, "routed_to", routed)

        assert d1_kinds(d1_inputs([nd()], [planted])) == [:routed_to_missing],
               "#{r["disposition"]} (#{to}): #{label}"
      end
    end

    test "spec_citation_missing: a wrong_against_spec row without a 2026-07-28 URL and a one-line quote" do
      [_, _, _, w] = good_d1()

      for {label, spec} <- [
            {"absent", :absent},
            {"not a map", "https://modelcontextprotocol.io/specification/2026-07-28"},
            {"another revision",
             %{
               @spec_cite
               | "url" => "https://modelcontextprotocol.io/specification/2025-11-25/basic"
             }},
            {"a lookalike revision",
             %{@spec_cite | "url" => "https://modelcontextprotocol.io/specification/2026-07-280"}},
            {"http",
             %{@spec_cite | "url" => "http://modelcontextprotocol.io/specification/2026-07-28"}},
            {"quote absent", Map.delete(@spec_cite, "quote")},
            {"quote two lines", %{@spec_cite | "quote" => "a\nb"}}
          ] do
        r = if spec == :absent, do: Map.delete(w, "spec"), else: Map.put(w, "spec", spec)
        assert d1_kinds(d1_inputs([nd()], [r])) == [:spec_citation_missing], label
      end
    end

    test "disposition_outside_view: a D1 code outside a D1 view, and a non-D1 code in one" do
      # Both ways (29693, Q3).
      for r <- good_d1() do
        assert kinds(
                 inputs([a()], [
                   section([row(a(), Map.drop(r, ~w(member claim tag echo et_test check)))])
                 ])
               ) ==
                 [:disposition_outside_view],
               r["disposition"]
      end

      for disp <- A.dispositions() -- A.d1_dispositions() do
        extra = %{
          "bound" => "b",
          "build_level" => "pure_unit",
          "remedy" => "r",
          "extend_target" => %{"reading" => "u"},
          "sdk_gap" => %{
            "owner" => "MES-1",
            "owner_record" => "o",
            "record" => %{"file" => @src, "lines" => [2, 2], "bytes" => "assert x == 1"}
          }
        }

        assert d1_kinds(d1_inputs([nd()], [d1_row(disp, extra)])) == [:disposition_outside_view],
               disp
      end

      # A code outside the closed set is disposition_outside_set's alone.
      assert d1_kinds(d1_inputs([nd()], [d1_row("wontfix", %{})])) == [:disposition_outside_set]
    end

    test "counterfactual_missing: a D1 row without a reading of the ratified shape (MES-139)" do
      for g <- good_d1(),
          {label, cf} <- [
            {"absent", :absent},
            {"not a map", "None can: schema.ts:1"},
            {"boolean a string", %{@reading | "conforming_sdk_can_fail" => "false"}},
            {"boolean absent", Map.delete(@reading, "conforming_sdk_can_fail")},
            {"reading absent", Map.delete(@reading, "reading")},
            {"reading blank", %{@reading | "reading" => "  "}},
            {"reading two lines", %{@reading | "reading" => "None can: schema.ts:1\nsays so"}},
            {"None can: with no spec cite", %{@reading | "reading" => "None can: plainly."}},
            {"spec cite, not opening None can:",
             %{@reading | "reading" => "schema.ts:1 requires it"}},
            {"firing, test:12 (N7)",
             %{"conforming_sdk_can_fail" => true, "reading" => "An SDK fails test:12."}},
            {"firing, my_test:12",
             %{"conforming_sdk_can_fail" => true, "reading" => "An SDK fails my_test:12."}},
            {"firing, a None can: reading",
             %{"conforming_sdk_can_fail" => true, "reading" => "None can: schema.ts:1"}}
          ] do
        r =
          if cf == :absent,
            do: Map.delete(g, "counterfactual"),
            else: Map.put(g, "counterfactual", cf)

        assert d1_kinds(d1_inputs([nd()], [r])) == [:counterfactual_missing],
               "#{g["disposition"]}: #{label}"
      end

      # A firing reading naming `<name>_test.exs:N` is admitted; MES-138's
      # gate-5 regex admitted "test:12" too, which the tightened one does not.
      [g | _] = good_d1()
      firing = %{"conforming_sdk_can_fail" => true, "reading" => "An SDK fails x_test.exs:12."}
      assert d1_kinds(d1_inputs([nd()], [Map.put(g, "counterfactual", firing)])) == []
      assert "fails test:12." =~ ~r/(test|test\.exs):\d+/
      refute "fails test:12." =~ @fires_cite

      # The message names the rule.
      [line] =
        d1_inputs([nd()], [Map.delete(g, "counterfactual")])
        |> A.audit(%{not_owed: %{}, pending: %{}})
        |> Map.fetch!(:defects)
        |> Enum.map(&A.format_defect/1)

      assert line =~
               ~r/^G32 counterfactual_missing — .*needs `counterfactual` with a boolean `conforming_sdk_can_fail` and a one-line `reading`/

      # A non-D1 row carries no reading and is not asked for one.
      assert kinds(inputs([a()], [section([row(a())])])) == []
    end

    test "the new echo fields: a re-run search under an unchanged key is echo_drift" do
      vr = Map.merge(nd(), %{"search_id" => "ND01", "the_search_that_found_none" => "s"})
      [g | _] = good_d1()
      r = Map.put(g, "echo", A.echo(vr))

      assert r["echo"] == %{
               "cg" => nil,
               "search_id" => "ND01",
               "the_search_that_found_none" => "s"
             }

      assert d1_kinds(d1_inputs([vr], [r])) == []

      for {f, v} <- [{"search_id", "ND02"}, {"the_search_that_found_none", "t"}] do
        assert d1_kinds(d1_inputs([Map.put(vr, f, v)], [r])) == [:echo_drift], f
      end
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
        row(a(), %{
          "if_conformance_fixed" => [
            %{"file" => @src, "lines" => [3, 3], "bytes" => "assert x == 1"}
          ]
        })

      assert kinds(inputs([a()], [section([stale])])) == [:citation_drift]

      odd = row(a(), %{"if_conformance_fixed" => [%{"bytes" => "assert x == 1"}]})
      assert kinds(inputs([a()], [section([odd])])) == [:citation_drift]
    end

    # MES-135 (29451; PM 29663 Q3): bytes that recur in the file.
    test "citation_ambiguous: recurring bytes need a verified occurrence" do
      twice = "defmodule M do\n  x = 1\n  y = 2\n  x = 1\nend\n"

      at = fn cite ->
        base = inputs([a()], [section([row(a(), %{"if_conformance_fixed" => [cite]})])])

        kinds(%{
          base
          | source_fun: fn
              "test/twice.exs" -> {:ok, twice}
              f -> base.source_fun.(f)
            end
        })
      end

      c = fn line, extra ->
        Map.merge(
          %{"file" => "test/twice.exs", "lines" => [line, line], "bytes" => "x = 1"},
          extra
        )
      end

      assert A.occurrences(c.(4, %{}), fn _ -> {:ok, twice} end) == [2, 4]
      assert at.(c.(4, %{})) == [:citation_ambiguous]
      assert at.(c.(4, %{"occurrence" => 2})) == []
      assert at.(c.(4, %{"occurrence" => 1})) == [:citation_ambiguous]
      assert at.(c.(2, %{"occurrence" => 1})) == []

      # Unique bytes need no occurrence, but one that is carried is held.
      unique = %{"file" => "test/twice.exs", "lines" => [3, 3], "bytes" => "y = 2"}
      assert at.(unique) == []
      assert at.(Map.put(unique, "occurrence", 2)) == [:citation_ambiguous]
    end

    test "citation_ambiguous: a window that recurs only by a blank-line shift is still ambiguous" do
      src = "a\n\nb\n\n"
      cite = %{"file" => "f", "lines" => [2, 3], "bytes" => "b"}
      assert A.occurrences(cite, fn _ -> {:ok, src} end) == [2, 3]
    end

    test "the three committed occurrence citations are the pinned ones", %{inputs: inputs} do
      got =
        for {f, {:ok, doc}} <- inputs.records,
            c <- A.collect(doc),
            Map.has_key?(c, "occurrence"),
            do: {Path.basename(f), c["file"], c["lines"], c["occurrence"]}

      assert Enum.sort(got) == [
               {"adjudication-D2a-i-2026-07-28.json", "conformance/server_handler.ex", [433, 445],
                2},
               {"adjudication-D2b-2026-07-28.json", "test/mcp/protocol/capabilities_test.exs",
                [64, 64], 2},
               {"adjudication-D4b-2026-07-28.json",
                "test/mcp/server/subscriptions_dispatch_test.exs", [389, 389], 1}
             ]
    end

    test "a harness citation is counted, not verified, in gate 5" do
      h = %{"harness_sha256" => "abc", "byte_span" => [1, 2], "bytes" => "x"}
      %{report: r, defects: []} = audit(inputs([a()], [section([row(a(), %{"check" => h})])]))
      assert r["harness_citations_not_verified_in_gate_5"] == 1
      assert r["repo_citations_found"] == 1 and r["repo_citations_holding"] == 1
    end

    # MES-135 K5: `citations_verified` counted citations FOUND, so a refused run
    # still printed "N repository citations verified". The report now counts
    # found and holding apart, and the task prints a verified count only when the
    # audit is clean.
    test "a refused run prints no verified-count claim; a clean one does" do
      clean = audit(inputs([a()], [section([row(a())])]))
      assert clean.defects == []
      assert Render.render(clean.report, clean.defects) =~ "1 repository citations verified"

      drifted =
        row(a(), %{
          "if_conformance_fixed" => [%{"file" => @src, "lines" => [1, 1], "bytes" => "x"}]
        })

      refused = audit(inputs([a()], [section([drifted])]))
      assert Enum.map(refused.defects, & &1.kind) == [:citation_drift]
      # The row's own et_test holds; the planted one drifts.
      assert refused.report["repo_citations_found"] == 2
      assert refused.report["repo_citations_holding"] == 1

      out = Render.render(refused.report, refused.defects)
      refute out =~ "verified"
      assert out =~ "2 repository citations found, 1 drifted"
      assert out =~ "a refused run verifies nothing"
      assert out =~ "G32 citation_drift"
    end

    test "a malformed citation is refused but is not counted as a repository citation" do
      odd = row(a(), %{"if_conformance_fixed" => [%{"bytes" => "assert x == 1"}]})
      %{report: r} = audit(inputs([a()], [section([odd])]))
      # One: the row's own et_test. The malformed one is in neither count.
      assert r["repo_citations_found"] == 1 and r["repo_citations_holding"] == 1
    end
  end

  describe "records and reach" do
    test "bad_record and unreadable, and a record that yields no rows also fails reach" do
      assert kinds(inputs([a()], [], record: {:ok, %{"schema" => "x"}})) == [:bad_record, :reach]
      assert kinds(inputs([a()], [], record: {:error, "nope"})) == [:unreadable, :reach]
    end

    test "a visited record with zero rows is refused" do
      assert kinds(inputs([], [section([], "open", %{"owner" => "MES-1"})])) == [:reach]
    end

    test "an empty directory reports zero and refuses nothing" do
      %{report: r, defects: []} =
        A.audit(
          %{
            walk: [],
            records: %{},
            views: %{},
            anchor: [],
            strays: [],
            outside: {:ok, []},
            locator: {:ok, %{}},
            source_fun: fn _ -> {:error, :x} end
          },
          %{not_owed: %{}, pending: %{}}
        )

      assert r["records_visited"] == 0 and r["rows_visited"] == 0
    end

    # MES-135 K2: with an owed view in the anchor, an empty directory is refused.
    test "an empty directory with an owed, unpending view is refused, naming the view" do
      empty = %{
        walk: [],
        records: %{},
        views: %{},
        anchor: [@view],
        strays: [],
        outside: {:ok, []},
        locator: {:ok, %{}},
        source_fun: fn _ -> {:error, :x} end
      }

      assert [%{kind: :owed_unadjudicated, file: @view}] =
               A.audit(empty, %{not_owed: %{}, pending: %{}}).defects

      assert A.audit(empty, %{not_owed: %{}, pending: %{@view => "MES-1"}}).defects == []
    end
  end

  defp src do
    fn
      @src -> {:ok, "line one\n  assert   x == 1\nline three\n"}
      _ -> {:error, :enoent}
    end
  end
end

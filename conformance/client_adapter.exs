#!/usr/bin/env elixir
# MCP Conformance Client Adapter — 2026-07-28 stateless core.
#
# The harness (`conformance client --command ...`) starts a mock server per
# scenario, then spawns THIS script with the server URL appended as the last
# argv and the scenario in the environment:
#
#   MCP_CONFORMANCE_SCENARIO          the scenario name
#   MCP_CONFORMANCE_PROTOCOL_VERSION  the wire version ("2026-07-28" here)
#   MCP_CONFORMANCE_CONTEXT           JSON `{name: <scenario>, ...}`, and ONLY
#                                     for the one scenario that supplies one
#                                     (`http-custom-headers`)
#
# Usage:
#   mix run conformance/client_adapter.exs <server_url>
#
# ## The adapter is not a runner; it is the measurement instrument
#
# Read `getChecks()` on each scenario at `@modelcontextprotocol/conformance@0.2.0-alpha.11`
# and an un-exercised check does **not** fail uniformly:
#
#   * `http-standard-headers` pushes SKIPPED for a method never exercised —
#     free, and outside the denominator entirely.
#   * `http-custom-headers`, `http-invalid-tool-headers` and `request-metadata`
#     push **FAILURE** for a declared check never emitted.
#
# So a *correct* client driven by a thin adapter scores FAILURE on scenarios it
# would have passed. Each clause below therefore drives a definite list of
# calls, and that list is an acceptance criterion rather than a convenience.
#
# Where a scenario's checks are NEGATIVE — "the client MUST NOT have called
# this" — the list is DERIVED from what the SDK returned rather than named
# here. A named list satisfies a negative check whatever the SDK did: measured,
# not argued (a raw :httpc client with no MCP SDK in it scored 11/11 on
# `http-invalid-tool-headers`, and so did this adapter with the SDK's exclusion
# disabled). Deriving it is what lets such a scenario go red.
#
# ## Exit code discipline — deliberate, and the opposite of papering over
#
# The harness's reducer fails a scenario on `exitCode !== 0` unless the
# scenario sets `allowClientError` (only `http-invalid-tool-headers` does), and
# that disjunct is evaluated *independently of every check*. A non-zero exit
# therefore fails the scenario INSTEAD of the checks, hiding what the checks
# would have said.
#
# So an unrecognised scenario logs loudly to stderr and exits **0**, letting the
# fail-closed checks be the thing that decides. Non-zero is reserved for a
# genuine adapter crash — which keeps a self-consistency failure of ours
# distinguishable, on the result sheet, from a conformance failure.
#
# The 25 scored `auth/*` scenarios land on that clause: this SDK has no OAuth
# client surface, so they are named empties, not silent absences.

defmodule MCP.Conformance.ClientAdapter do
  @moduledoc false

  alias MCP.Client

  alias MCP.Protocol.Capabilities.{
    ClientCapabilities,
    ElicitationCapabilities,
    RootCapabilities,
    SamplingCapabilities
  }

  # Every scenario the frozen 2026-07-28 requirement set scores on the client
  # leg and this adapter drives. The other 25 (`auth/*`) are enumerated in the
  # report as empties with their reason.
  @driven ~w(
    tools_call
    request-metadata
    sep-2322-client-request-state
    http-standard-headers
    http-custom-headers
    http-invalid-tool-headers
    json-schema-ref-no-deref
    json-schema-2020-12-preservation
  )

  def run do
    server_url = List.last(System.argv()) || raise "Server URL required as last argument"
    scenario = System.get_env("MCP_CONFORMANCE_SCENARIO") || ""

    IO.puts("Scenario: #{scenario}")
    IO.puts("Server URL: #{server_url}")

    if scenario in @driven do
      run_scenario(scenario, server_url)
      IO.puts("Scenario '#{scenario}' completed")
    else
      not_driven(scenario)
    end
  end

  # --- Scenarios -----------------------------------------------------------

  # Drives: server/discover, tools/list, tools/call `add_numbers` with BOTH
  # arguments numeric — the check reads `typeof a === "number"`, so a stringly
  # typed argument fails a scenario the SDK is fine at.
  defp run_scenario("tools_call", url) do
    with_client(url, fn client ->
      drive("server/discover", fn -> Client.connect(client) end)
      drive("tools/list", fn -> Client.list_tools(client) end)

      drive("tools/call add_numbers", fn ->
        Client.call_tool(client, "add_numbers", %{"a" => 2, "b" => 40})
      end)
    end)
  end

  # The mock rejects the FIRST request with -32022 and only marks
  # `sep-2575-client-retry-supported-version` SUCCESS once a LATER request
  # carries 2026-07-28 in both the header and `_meta`. The check starts as
  # WARNING, and a WARNING fails the scenario, so *something* must follow the
  # rejected request.
  #
  # CORRECTION (MES-24, measured — this file used to say "the retry is
  # mandatory", and that is false). Our client does NOT retry: the transport
  # discards a JSON-RPC error body carried on a 400, so the -32022 recovery in
  # `MCP.Client` is never reached over Streamable HTTP (escalated as a genuine
  # SDK gap; see the MES-24 entry in `docs/sprint_4_issues.md`). The SUCCESS
  # comes from the fixture's re-evaluation rule firing on the NEXT request the
  # adapter makes, not on a retry of the rejected one.
  #
  # So this scenario's 8/8 is contingent on `drive/2` carrying on past a failed
  # `connect/1`. A consumer that stops at a failed connect scores 7 SUCCESS +
  # 1 WARNING = FAILED. The carry-on policy is deliberate (see `drive/2`), but
  # it is a DRIVE POLICY, not an SDK property, and the report names it as its
  # own axis rather than letting the 8/8 read as eight tested behaviours.
  defp run_scenario("request-metadata", url) do
    with_client(url, fn client ->
      drive("server/discover", fn -> Client.connect(client) end)
      drive("tools/list", fn -> Client.list_tools(client) end)
      drive("tools/call any_tool", fn -> Client.call_tool(client, "any_tool", %{}) end)
    end)
  end

  # Four tools, four distinct client obligations (SEP-2322):
  #   test_mrtr_echo_state     echo requestState verbatim; new JSON-RPC id on retry
  #   test_mrtr_no_state       server sent none -> client MUST NOT include the key
  #   test_mrtr_unrelated      a call between rounds MUST NOT carry either field
  #   test_mrtr_no_result_type absent resultType defaults to "complete" -> no retry
  # All four must be called: each check is fail-closed when never emitted.
  defp run_scenario("sep-2322-client-request-state", url) do
    with_client(url, fn client ->
      drive("server/discover", fn -> Client.connect(client) end)
      drive("tools/list", fn -> Client.list_tools(client) end)

      Enum.each(
        ~w(test_mrtr_echo_state test_mrtr_unrelated test_mrtr_no_state test_mrtr_no_result_type),
        fn tool -> drive("tools/call #{tool}", fn -> Client.call_tool(client, tool, %{}) end) end
      )
    end)
  end

  # The fixture watches eight methods for `Mcp-Method` and three for
  # `Mcp-Name`. Two of the eight — `initialize` and `notifications/initialized`
  # — do not exist in the stateless core and legitimately SKIP. The remaining
  # SIX are all driven, because a scenario whose every check is SKIPPED scores
  # PASS with a denominator of ZERO: a hollow pass that settles nothing.
  defp run_scenario("http-standard-headers", url) do
    with_client(url, fn client ->
      drive("server/discover", fn -> Client.connect(client) end)
      drive("tools/list", fn -> Client.list_tools(client) end)
      drive("tools/call test_headers", fn -> Client.call_tool(client, "test_headers", %{}) end)

      resources = drive("resources/list", fn -> Client.list_resources(client) end)

      drive("resources/read", fn ->
        Client.read_resource(client, first_resource_uri(resources))
      end)

      drive("prompts/list", fn -> Client.list_prompts(client) end)
      drive("prompts/get test_prompt", fn -> Client.get_prompt(client, "test_prompt", %{}) end)
    end)
  end

  # The ONLY scenario in the alpha.11 catalogue that supplies a context. Its
  # `toolCalls` are taken verbatim — the fixture compares each `Mcp-Param-*`
  # header against the argument value it sent, so an argument invented here
  # would test the adapter rather than the encoder.
  #
  # `tools/list` first, and not as a formality: mirroring is driven by the
  # tool's `inputSchema`, so a call made before the schema cache is populated
  # sends no `Mcp-Param-*` headers at all.
  defp run_scenario("http-custom-headers", url) do
    tool_calls = context_tool_calls()

    with_client(url, fn client ->
      drive("server/discover", fn -> Client.connect(client) end)
      drive("tools/list", fn -> Client.list_tools(client) end)

      Enum.each(tool_calls, fn %{"name" => name} = call ->
        drive("tools/call #{name}", fn ->
          Client.call_tool(client, name, Map.get(call, "arguments", %{}))
        end)
      end)
    end)
  end

  # Ten tools carry an invalid `x-mcp-header`; `valid_tool` does not. The
  # client MUST exclude the ten and keep the one.
  #
  # The drive is DERIVED from the listing `list_tools/1` returned — every tool
  # it kept is called, and nothing else. That derivation is the whole substance
  # of the scenario, because ten of its eleven checks are
  # `calledTools.has(name) ? FAILURE : SUCCESS`: pure negatives. A hard-coded
  # `"valid_tool"` here scores 11/11 for a client that never looked at the
  # listing at all — CR measured exactly that with a raw `:httpc` control and
  # no MCP SDK in it. Derived, a regression in CG7's exclusion CALLS an invalid
  # tool and the scenario goes red, which is the only thing that makes an
  # 11/11 evidence about `MCP.Client` rather than about this file.
  defp run_scenario("http-invalid-tool-headers", url) do
    with_client(url, fn client ->
      drive("server/discover", fn -> Client.connect(client) end)
      kept = kept_tools(drive("tools/list", fn -> Client.list_tools(client) end))

      IO.puts(:stderr, "tools kept: #{inspect(Enum.map(kept, &Map.get(&1, "name")))}")
      IO.puts(:stderr, "tools excluded: #{inspect(Client.excluded_tools(client))}")

      Enum.each(kept, fn tool ->
        name = Map.get(tool, "name")

        drive("tools/call #{name}", fn ->
          Client.call_tool(client, name, required_arguments(tool))
        end)
      end)
    end)
  end

  # A tool whose `inputSchema` carries a `$ref` at a network URI. The check is
  # negative — the canary must NOT be fetched — but it is fail-closed on
  # `tools/list` never arriving, so the listing is the whole of the drive.
  defp run_scenario("json-schema-ref-no-deref", url) do
    with_client(url, fn client ->
      drive("server/discover", fn -> Client.connect(client) end)
      drive("tools/list", fn -> Client.list_tools(client) end)
    end)
  end

  # `not_scored` in the frozen 2026-07-28 set (`added-after-release`), so
  # driving it moves NO figure. Driven anyway, because it is the only scenario
  # in the alpha.11 catalogue that measures CLIENT-SIDE JSON Schema 2020-12
  # preservation (SEP-1613/2106) — the counterpart to MES-17's server-side
  # work, which earns no scoring credit either. Left undriven it would fail as
  # an unnamed empty and read on the sheet exactly like a measured gap.
  #
  # The fixture's own instructions: list tools, then echo the focal tool's
  # `inputSchema` back verbatim as the `schema` argument of `json_schema_echo`.
  # The two names are the fixture's protocol; the SCHEMA is taken from whatever
  # `list_tools/1` handed us, so a keyword the client strips while parsing is
  # exactly what this scenario reports.
  defp run_scenario("json-schema-2020-12-preservation", url) do
    with_client(url, fn client ->
      drive("server/discover", fn -> Client.connect(client) end)
      tools = kept_tools(drive("tools/list", fn -> Client.list_tools(client) end))
      schema = input_schema_of(tools, "json_schema_2020_12_tool")

      IO.puts(
        :stderr,
        "echoing inputSchema keys: #{inspect(schema |> Map.keys() |> Enum.sort())}"
      )

      drive("tools/call json_schema_echo", fn ->
        Client.call_tool(client, "json_schema_echo", %{"schema" => schema})
      end)
    end)
  end

  # --- Not driven ----------------------------------------------------------

  defp not_driven(scenario) do
    IO.puts(:stderr, """
    NOT DRIVEN: scenario #{inspect(scenario)} has no clause in this adapter.

    Exiting 0 on purpose. The harness reducer fails a scenario on a non-zero
    exit independently of every check, which would hide what the checks would
    have said; exiting 0 lets the fail-closed checks decide and keeps a
    non-zero exit meaning "the adapter crashed".

    If this is an auth/* scenario it is an EMPTY, not a failure to run: this
    SDK has no OAuth client surface (no token acquisition, no metadata
    discovery, no WWW-Authenticate handling), so there is nothing to drive.
    """)
  end

  # --- Plumbing ------------------------------------------------------------

  # Every call in every scenario goes through here, and the policy is uniform
  # and scenario-blind ON PURPOSE: run the call, name the outcome on stderr,
  # and CARRY ON whether it succeeded or not.
  #
  # Two reasons, neither of them "make the number nicer":
  #
  #   1. A raise here aborts the whole drive, so one failed call silently costs
  #      every check the LATER calls would have emitted — and those checks are
  #      fail-closed, so they are scored as though the client failed them. The
  #      failure would then be attributed to the SDK rather than to the adapter
  #      giving up, which is the one confusion this ticket exists to prevent.
  #   2. A crash also exits non-zero, and the reducer fails a scenario on
  #      `exitCode !== 0` INDEPENDENTLY of every check — so the exit code would
  #      decide the verdict INSTEAD of the checks, hiding what they said.
  #
  # This is not error-swallowing: every `{:error, _}` is printed with the call
  # that produced it, the harness saves stderr next to `checks.json`, and the
  # report lists every error the run produced beside the check table. An error
  # here is EVIDENCE, and it is reported as such — a scenario that goes green
  # over a logged error is reported with that error, not as a clean pass.
  defp drive(label, fun) do
    case fun.() do
      {:ok, value} ->
        IO.puts(:stderr, "DRIVE ok    #{label}")
        value

      {:error, reason} ->
        IO.puts(:stderr, "DRIVE ERROR #{label}: #{inspect(reason, limit: 10)}")
        nil

      other ->
        IO.puts(:stderr, "DRIVE ok    #{label} -> #{inspect(other, limit: 5)}")
        other
    end
  end

  defp with_client(url, fun) do
    {:ok, client} = start_client(url)

    try do
      fun.(client)
    after
      Client.close(client)
    end
  end

  defp start_client(url) do
    Client.start_link(
      transport: {MCP.Transport.StreamableHTTP.Client, url: url, headers: []},
      client_info: %{name: "mcp_elixir_sdk_conformance", version: "1.0.0"},
      # Declared because this adapter genuinely provides all three: the
      # `:on_input_required` resolver below answers elicitation-, sampling- and
      # roots-shaped input requests. `request-metadata` scores each of these
      # SKIPPED when absent and SUCCESS when present-and-an-object — they check
      # the SHAPE of a declaration, not the capability behind it, and the
      # report says so rather than letting three cheap SUCCESSes read as three
      # tested capabilities.
      client_capabilities: %ClientCapabilities{
        roots: %RootCapabilities{},
        sampling: %SamplingCapabilities{},
        elicitation: %ElicitationCapabilities{}
      },
      on_input_required: &resolve_inputs/1
    )
  end

  # MRTR resolver (SEP-2322). `inputRequests` is a map of
  # `key => %{"method" => ..., "params" => ...}`; the retry carries
  # `inputResponses` under the same keys. Each response is the result the named
  # method would have produced over the removed held-open path.
  defp resolve_inputs(input_requests) when is_map(input_requests) do
    Map.new(input_requests, fn {key, request} ->
      {key, response_for(Map.get(request, "method"), Map.get(request, "params"))}
    end)
  end

  defp resolve_inputs(_), do: %{}

  defp response_for("elicitation/create", params) do
    %{
      "resultType" => "complete",
      "action" => "accept",
      "content" => elicited_content(params)
    }
  end

  defp response_for("sampling/createMessage", _params) do
    %{
      "resultType" => "complete",
      "role" => "assistant",
      "content" => %{"type" => "text", "text" => "Conformance test response"},
      "model" => "conformance-test",
      "stopReason" => "endTurn"
    }
  end

  defp response_for("roots/list", _params) do
    %{
      "resultType" => "complete",
      "roots" => [%{"uri" => "file:///conformance", "name" => "conformance"}]
    }
  end

  defp response_for(_method, _params), do: %{"resultType" => "complete"}

  # Fill every property the requested schema declares, typed from the schema so
  # a boolean field does not come back as the string "true".
  defp elicited_content(%{"requestedSchema" => %{"properties" => props}}) when is_map(props) do
    Map.new(props, fn {name, spec} -> {name, sample_value(Map.get(spec, "type"))} end)
  end

  defp elicited_content(_params), do: %{}

  defp sample_value("boolean"), do: true
  defp sample_value("integer"), do: 1
  defp sample_value("number"), do: 1
  defp sample_value(_), do: "conformance"

  defp context_tool_calls do
    with raw when is_binary(raw) <- System.get_env("MCP_CONFORMANCE_CONTEXT"),
         {:ok, %{"toolCalls" => calls}} when is_list(calls) <- Jason.decode(raw) do
      calls
    else
      _ ->
        raise "http-custom-headers requires MCP_CONFORMANCE_CONTEXT with toolCalls; " <>
                "got #{inspect(System.get_env("MCP_CONFORMANCE_CONTEXT"))}"
    end
  end

  defp first_resource_uri(%{"resources" => [%{"uri" => uri} | _]}), do: uri

  # A resources/list that produced nothing usable must still leave a
  # resources/read on the wire — the Mcp-Name check for that method is only
  # SKIPPED when the method is never sent, and skipping it here would quietly
  # narrow the drive. The sentinel URI is obviously not from the fixture, so a
  # mismatch reads as "the listing failed", not as an encoder defect.
  defp first_resource_uri(other) do
    IO.puts(:stderr, "resources/list gave no usable uri (#{inspect(other, limit: 5)})")
    "file:///conformance/no-resource-listed"
  end

  defp kept_tools(%{"tools" => tools}) when is_list(tools), do: tools

  # A `tools/list` that produced nothing usable drives no calls. That is
  # fail-closed and correct: `ClientKeepsValidTool` then reports FAILURE, which
  # is what "the listing never arrived" should look like.
  defp kept_tools(other) do
    IO.puts(:stderr, "tools/list gave no usable listing (#{inspect(other, limit: 5)})")
    []
  end

  # Arguments typed from the tool's own schema rather than invented here, for
  # the same reason the drive is derived: whatever the listing carries is what
  # gets called. The fixture records only the tool NAME, so these values decide
  # nothing — but a tool the SDK should have excluded must still be callable
  # enough to reach the wire, or the mutation control recorded in the MES-24
  # entry (CG7 exclusion disabled -> 1/11 FAILED) could not go red.
  defp required_arguments(%{"inputSchema" => %{"properties" => props} = schema})
       when is_map(props) do
    schema
    |> Map.get("required", [])
    |> Enum.filter(&is_binary/1)
    |> Map.new(fn name -> {name, sample_value(get_in(props, [name, "type"]))} end)
  end

  defp required_arguments(_tool), do: %{}

  # No fallback schema: an empty map echoed for a listing that never arrived
  # would score the preservation checks FAILURE for the wrong reason, and the
  # stderr line is what tells them apart.
  defp input_schema_of(tools, name) do
    case Enum.find(tools, &(Map.get(&1, "name") == name)) do
      %{"inputSchema" => schema} when is_map(schema) ->
        schema

      other ->
        IO.puts(
          :stderr,
          "no usable inputSchema for #{inspect(name)} (#{inspect(other, limit: 5)})"
        )

        %{}
    end
  end
end

# MES-51 beacon. Provenance only, and deliberately the smallest possible edit to
# the measurement instrument: the logic lives in `MCP.Conformance.Beacon` (which
# IS gate-covered), this is the call site. It is a no-op unless the runner set
# MCP_CONFORMANCE_BEACON, it writes to a file and never to stdout, stderr or the
# wire, and it cannot raise or change an exit code. Without it, a run whose
# adapter never started is indistinguishable from having no implementation at
# all — MES-49 measured a null client at 2/32 to prove exactly that.
if Code.ensure_loaded?(MCP.Conformance.Beacon) do
  MCP.Conformance.Beacon.emit(:adapter, __ENV__.file)
end

MCP.Conformance.ClientAdapter.run()

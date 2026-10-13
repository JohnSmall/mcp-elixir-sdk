defmodule MCP.Server.RequiredMetaTypesTest do
  @moduledoc """
  MES-164 — a required per-request `_meta` field that is present with the
  wrong type is malformed like a missing one, and is rejected with -32602
  (basic/index.mdx:373-382), as HTTP 400 on Streamable HTTP.
  `io.modelcontextprotocol/protocolVersion` must be a string (schema.ts:76)
  and `io.modelcontextprotocol/clientCapabilities` an object (schema.ts:98);
  only the top-level type is judged. `data.invalid` names the wrong-typed keys
  beside MES-161's `data.missing`. A wrong-typed version is -32602, never
  -32022: that error's `data.requested` is itself a string (schema.ts:494-498).

  No check in the pinned harness build sends a wrong-typed `_meta` value, so
  every test here is `oc: :none` and gate 7 does not cover this work.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MCP.Protocol.Capabilities.ServerCapabilities
  alias MCP.Protocol.Messages.Request
  alias MCP.Protocol.Meta
  alias MCP.Protocol.Types.Implementation
  alias MCP.Server.{Connection, Dispatch, ToolContext}
  alias MCP.Test.{MockTransport, RequiredHeaders, StatelessHandler}
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @pv "io.modelcontextprotocol/protocolVersion"
  @cc "io.modelcontextprotocol/clientCapabilities"
  @full %{@pv => @version, @cc => %{}}

  defp config do
    {:ok, state} = StatelessHandler.init([])

    %{
      handler_module: StatelessHandler,
      handler_state: state,
      server_info: %Implementation{name: "mcp_elixir_sdk", version: "2.0.0"},
      capabilities: %ServerCapabilities{},
      instructions: nil
    }
  end

  defp params_for("tools/call", meta),
    do: %{"name" => "whoami", "arguments" => %{}, "_meta" => meta}

  defp params_for(_method, meta), do: %{"_meta" => meta}

  defp dispatch(method, meta, id \\ 7) do
    req = %Request{id: id, method: method, params: params_for(method, meta)}

    {:reply, resp, _} = Dispatch.dispatch(req, %ToolContext{request_id: id}, config())
    resp
  end

  defp plug_opts(extra),
    do: MCPPlug.init([server_mod: StatelessHandler, enable_json_response: true] ++ extra)

  # The standard headers come from the SDK client's derivation; the version
  # header is then pinned to the supported version, so a non-string body
  # version meets a present, valid MCP-Protocol-Version.
  defp post(params, id, method \\ "tools/list", extra \\ []) do
    message = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

    conn =
      :post
      |> conn("http://localhost/", Jason.encode!(message))
      |> RequiredHeaders.put_json(message)
      |> put_req_header("mcp-protocol-version", @version)
      |> put_req_header("accept", "application/json")
      |> put_req_header("origin", "http://localhost")
      |> MCPPlug.call(plug_opts(extra))

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp stdio_reply(message) do
    {:ok, server} =
      Connection.start_link(transport: {MockTransport, []}, handler: {StatelessHandler, []})

    transport = Connection.transport(server)
    MockTransport.inject(transport, message)
    reply = await_sent(transport, 100)
    Connection.close(server)
    reply
  end

  defp await_sent(_transport, 0), do: nil

  defp await_sent(transport, tries) do
    case MockTransport.last_sent(transport) do
      nil ->
        Process.sleep(10)
        await_sent(transport, tries - 1)

      reply ->
        reply
    end
  end

  defp invalid!(resp, keys) do
    assert resp["error"]["code"] == -32_602
    assert resp["error"]["data"] == %{"invalid" => keys}
    resp
  end

  # --- Dispatch (the stdio and in-process path) ---

  @tag oc: :none
  @tag oc_reason:
         "a numeric protocolVersion: the pinned harness sends only string versions (2026-07-28, v999.0.0), so no OC check probes a wrong-typed one"
  test "a numeric protocolVersion → -32602 invalid [protocolVersion], not -32022" do
    for method <- ["server/discover", "tools/list"] do
      resp = dispatch(method, %{@pv => 20_260_728, @cc => %{}})
      assert resp["id"] == 7
      invalid!(resp, [@pv])
    end
  end

  @tag oc: :none
  @tag oc_reason:
         "an array, object or boolean protocolVersion: the pinned harness sends only string versions, so no OC check probes one"
  test "an array, object or boolean protocolVersion → -32602 invalid [protocolVersion]" do
    for value <- [[@version], %{}, true] do
      resp = dispatch("tools/list", %{@pv => value, @cc => %{}})
      assert resp["id"] == 7, inspect(value)
      invalid!(resp, [@pv])
    end
  end

  @tag oc: :none
  @tag oc_reason:
         "a non-object clientCapabilities: the pinned harness sends only objects ({}, {sampling: {}}, elicitation/extensions objects), so no OC check probes one"
  test "a string, array, number or boolean clientCapabilities → -32602 invalid [clientCapabilities]" do
    for value <- ["x", [], 5, false], method <- ["server/discover", "tools/list", "tools/call"] do
      resp = dispatch(method, %{@pv => @version, @cc => value})
      assert resp["id"] == 7, inspect({method, value})
      invalid!(resp, [@cc])
    end
  end

  @tag oc: :none
  @tag oc_reason:
         "both required keys wrong-typed, or one missing and one wrong-typed: no OC check sends a wrong-typed _meta value"
  test "both wrong-typed → invalid names both; missing plus wrong-typed → both data keys" do
    "tools/list" |> dispatch(%{@pv => 1, @cc => "x"}) |> invalid!([@pv, @cc])

    resp = dispatch("tools/list", %{@cc => "x"})
    assert resp["error"]["code"] == -32_602
    assert resp["error"]["data"] == %{"missing" => [@pv], "invalid" => [@cc]}
  end

  @tag oc: :none
  @tag oc_reason:
         "the correct-type control and the empty-string version (type-correct, so -32022, MES-164 Q2) on tools/list; no OC check sends an empty version"
  test "well-typed values are served; an empty-string version is type-correct and keeps -32022" do
    for caps <- [%{}, %{"elicitation" => %{}}] do
      resp = dispatch("tools/list", %{@pv => @version, @cc => caps})
      refute Map.has_key?(resp, "error"), inspect(caps)
      assert is_list(resp["result"]["tools"])
    end

    resp = dispatch("tools/list", %{@pv => "", @cc => %{}})
    assert resp["error"]["code"] == -32_022
    assert resp["error"]["data"]["requested"] == ""
  end

  # --- stdio, end to end over the Connection driver ---

  @tag oc: :none
  @tag oc_reason:
         "the stdio driver: the official suite has no stdio server leg, and no OC check sends a wrong-typed _meta value"
  test "stdio: a wrong-typed required value gets a -32602 reply carrying the id" do
    for {meta, key} <- [
          {%{@pv => 20_260_728, @cc => %{}}, @pv},
          {%{@pv => @version, @cc => "x"}, @cc}
        ] do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 31,
        "method" => "tools/list",
        "params" => %{"_meta" => meta}
      }

      reply = stdio_reply(message)
      assert reply["id"] == 31, inspect(meta)
      invalid!(reply, [key])
    end

    message = %{
      "jsonrpc" => "2.0",
      "id" => 32,
      "method" => "tools/list",
      "params" => %{"_meta" => @full}
    }

    reply = stdio_reply(message)
    assert reply["id"] == 32
    assert is_list(reply["result"]["tools"])
  end

  # --- Streamable HTTP: 400, -32602 ---

  @tag oc: :none
  @tag oc_reason:
         "a numeric body version with MCP-Protocol-Version present (MES-164 Q5): the pinned harness sends only string versions"
  test "HTTP: a numeric body version with the header present → 400, -32602, not -32020 or -32022" do
    {status, body} = post(%{"_meta" => %{@pv => 20_260_728, @cc => %{}}}, 201)
    assert status == 400
    assert body["id"] == 201
    invalid!(body, [@pv])
  end

  @tag oc: :none
  @tag oc_reason:
         "a non-object clientCapabilities on HTTP: the pinned harness sends only objects, so HttpServerMetaInvalid400 never probes one"
  test "HTTP: a string or array clientCapabilities → 400, -32602 invalid [clientCapabilities]" do
    for value <- ["x", []] do
      {status, body} = post(%{"_meta" => %{@pv => @version, @cc => value}}, 202)
      assert status == 400, inspect(value)
      assert body["id"] == 202
      invalid!(body, [@cc])
    end
  end

  @tag oc: :none
  @tag oc_reason:
         "both wrong-typed, or missing plus wrong-typed, on HTTP: no OC check sends a wrong-typed _meta value"
  test "HTTP: both wrong-typed → 400 invalid both; missing plus wrong-typed → 400 with both keys" do
    {status, body} = post(%{"_meta" => %{@pv => 1, @cc => "x"}}, 203)
    assert status == 400
    assert body["id"] == 203
    invalid!(body, [@pv, @cc])

    {status, body} = post(%{"_meta" => %{@cc => "x"}}, 204)
    assert status == 400
    assert body["id"] == 204
    assert body["error"]["code"] == -32_602
    assert body["error"]["data"] == %{"missing" => [@pv], "invalid" => [@cc]}
  end

  @tag oc: :none
  @tag oc_reason:
         "the correct-type control on HTTP tools/list: the regression limb of the type gate, not an OC probe"
  test "HTTP: a well-typed request is served (200)" do
    {status, body} = post(%{"_meta" => %{@pv => @version, @cc => %{"elicitation" => %{}}}}, 205)
    assert status == 200
    assert body["id"] == 205
    assert is_list(body["result"]["tools"])
  end

  @tag oc: :none
  @tag oc_reason:
         "the -32602 path's readable id (MES-157 30426): HttpServerErrorJsonrpcId sends only numeric ids, so no OC check sends an object id"
  test "HTTP: the -32602 carries id null for an object id, missing or wrong-typed; a number is echoed" do
    for meta <- [%{@pv => @version, @cc => "x"}, %{@pv => @version}] do
      {status, body} = post(%{"_meta" => meta}, %{"a" => 1})
      assert status == 400, inspect(meta)
      assert body["error"]["code"] == -32_602
      assert Map.has_key?(body, "id")
      assert body["id"] == nil
    end

    {status, body} = post(%{"_meta" => %{@pv => @version, @cc => "x"}}, 206)
    assert status == 400
    assert body["id"] == 206
  end

  @tag oc: :none
  @tag oc_reason:
         "the order is this SDK's stated pipeline (MES-161 Q4); the harness runs a static identity, so no OC check reaches the factory"
  test "HTTP: a wrong-typed value is refused before the handler_opts factory" do
    test_pid = self()

    recording = [
      handler_opts: fn _conn ->
        send(test_pid, :factory_ran)
        []
      end
    ]

    {status, body} =
      post(%{"_meta" => %{@pv => @version, @cc => "x"}}, 207, "tools/list", recording)

    assert status == 400
    assert body["id"] == 207
    assert body["error"]["code"] == -32_602
    refute_received :factory_ran

    {status, _body} = post(%{"_meta" => @full}, 208, "tools/list", recording)
    assert status == 200
    assert_received :factory_ran
  end

  # --- Missing-only requests: the complete response is unchanged from 8eb03d4 (Q6) ---

  @tag oc: :none
  @tag oc_reason:
         "the missing-only response pinned whole as the 8eb03d4 literal (MES-164 Q6, CR F1); RequestMetaInvalid checks only the code"
  test "Dispatch: a missing-only request's complete response is byte-for-byte MES-161's" do
    cases = [
      {%{}, [@pv, @cc]},
      {%{"_meta" => %{}}, [@pv, @cc]},
      {%{"_meta" => %{@cc => %{}}}, [@pv]},
      {%{"_meta" => %{@pv => @version}}, [@cc]}
    ]

    for {params, missing} <- cases do
      req = %Request{id: 41, method: "tools/list", params: params}
      {:reply, resp, _} = Dispatch.dispatch(req, %ToolContext{request_id: 41}, config())

      assert resp == %{
               "jsonrpc" => "2.0",
               "id" => 41,
               "error" => %{
                 "code" => -32_602,
                 "message" => "Invalid params",
                 "data" => %{"missing" => missing}
               }
             },
             inspect(params)
    end
  end

  @tag oc: :none
  @tag oc_reason:
         "the missing-only HTTP response pinned whole as the 8eb03d4 literal (MES-164 Q6, CR F1); HttpServerMetaInvalid400 checks only the status"
  test "HTTP: a missing-only request's complete 400 response is byte-for-byte MES-161's" do
    cases = [
      {%{}, [@pv, @cc]},
      {%{"_meta" => %{}}, [@pv, @cc]},
      {%{"_meta" => %{@cc => %{}}}, [@pv]},
      {%{"_meta" => %{@pv => @version}}, [@cc]}
    ]

    for {params, missing} <- cases do
      {status, body} = post(params, 42)
      assert status == 400, inspect(params)

      assert body == %{
               "jsonrpc" => "2.0",
               "id" => 42,
               "error" => %{
                 "code" => -32_602,
                 "message" => "Invalid params",
                 "data" => %{"missing" => missing}
               }
             },
             inspect(params)
    end
  end

  # --- The guard and the functions agree ---

  @tag oc: :none
  @tag oc_reason:
         "an SDK-internal invariant (the guard and the functions agree); no wire behaviour"
  test "Meta.is_malformed_required/1 agrees with Meta.required_problems/1; null is never wrong-typed" do
    require Meta

    inputs = [
      nil,
      %{},
      %{"_meta" => nil},
      %{"_meta" => "x"},
      %{"_meta" => %{}},
      %{"_meta" => %{@pv => nil, @cc => nil}},
      %{"_meta" => %{@pv => @version}},
      %{"_meta" => %{@cc => "x"}},
      %{"_meta" => %{@pv => 1, @cc => %{}}},
      %{"_meta" => %{@pv => @version, @cc => []}},
      %{"_meta" => %{@pv => [], @cc => 5}},
      %{"_meta" => %{@pv => "", @cc => %{}}},
      %{"_meta" => @full}
    ]

    for params <- inputs do
      guarded = if Meta.is_malformed_required(params), do: true, else: false
      assert guarded == (Meta.required_problems(params) != %{}), inspect(params)

      meta = if is_map(params) and is_map(params["_meta"]), do: params["_meta"], else: %{}

      for key <- Meta.wrong_typed_required(params) do
        refute is_nil(Map.get(meta, key)), inspect(params)
      end
    end

    assert Meta.required_problems(%{"_meta" => %{@pv => @version}}) == %{"missing" => [@cc]}
    assert Meta.required_problems(%{"_meta" => @full}) == %{}
  end
end

defmodule MCP.Server.RequiredMetaTest do
  @moduledoc """
  MES-161 — a request missing a required per-request `_meta` field
  (`io.modelcontextprotocol/protocolVersion` or
  `io.modelcontextprotocol/clientCapabilities`) is malformed and is rejected
  with -32602 (basic/index.mdx:380-382), as HTTP 400 on Streamable HTTP. A
  version that is present but unsupported keeps -32022. The routing-header
  check (-32020) is judged first.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test
  import Plug.Conn

  alias MCP.Protocol.Capabilities.ServerCapabilities
  alias MCP.Protocol.Messages.{Notification, Request}
  alias MCP.Protocol.Meta
  alias MCP.Protocol.Types.Implementation
  alias MCP.Server.Dispatch
  alias MCP.Server.ToolContext
  alias MCP.Test.{RequiredHeaders, StatelessHandler}
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @pv "io.modelcontextprotocol/protocolVersion"
  @cc "io.modelcontextprotocol/clientCapabilities"
  @ci "io.modelcontextprotocol/clientInfo"
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

  defp dispatch(method, params, id \\ 7) do
    req = %Request{id: id, method: method, params: params}

    {:reply, resp, _} = Dispatch.dispatch(req, %ToolContext{request_id: id}, config())
    resp
  end

  defp plug_opts(extra),
    do: MCPPlug.init([server_mod: StatelessHandler, enable_json_response: true] ++ extra)

  defp post(params, id, method \\ "server/discover", headers \\ [], extra \\ []) do
    message = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

    base =
      :post
      |> conn("http://localhost/", Jason.encode!(message))
      |> RequiredHeaders.put_json(message)
      |> put_req_header("accept", "application/json")
      |> put_req_header("origin", "http://localhost")

    conn = Enum.reduce(headers, base, fn {k, v}, c -> put_req_header(c, k, v) end)
    conn = MCPPlug.call(conn, plug_opts(extra))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  # --- Dispatch: -32602 on every transport, server/discover included ---

  @tag oc:
         "oc:server/server-stateless/sep-2575-request-meta-invalid-missing-meta/RequestMetaInvalid"
  test "no _meta at all → -32602 naming both keys, with the request id" do
    resp = dispatch("server/discover", %{})
    assert resp["id"] == 7
    assert resp["error"]["code"] == -32_602
    assert resp["error"]["data"]["missing"] == [@pv, @cc]
  end

  @tag oc:
         "oc:server/server-stateless/sep-2575-request-meta-invalid-missing-protocol-version/RequestMetaInvalid"
  test "_meta without protocolVersion → -32602, not -32022" do
    resp = dispatch("server/discover", %{"_meta" => %{@cc => %{}}})
    assert resp["error"]["code"] == -32_602
    assert resp["error"]["data"]["missing"] == [@pv]
  end

  @tag oc:
         "oc:server/server-stateless/sep-2575-request-meta-invalid-missing-client-capabilities/RequestMetaInvalid"
  test "_meta without clientCapabilities → -32602, on a version-gated route too" do
    for method <- ["server/discover", "tools/list"] do
      resp = dispatch(method, %{"_meta" => %{@pv => @version}})
      assert resp["error"]["code"] == -32_602
      assert resp["error"]["data"]["missing"] == [@cc]
    end
  end

  @tag oc:
         "oc:server/server-stateless/sep-2575-request-meta-client-info-optional/RequestMetaClientInfoOptional"
  test "clientInfo is not required: a request without it is served" do
    resp = dispatch("tools/list", %{"_meta" => @full})
    refute Map.has_key?(resp, "error")
    assert is_list(resp["result"]["tools"])
  end

  @tag oc: :none
  @tag oc_reason: "a null value counts as missing (plan Q5); no OC probe sends a null _meta value"
  test "a null required value is missing; a non-map _meta is missing every key" do
    resp = dispatch("tools/list", %{"_meta" => %{@pv => @version, @cc => nil}})
    assert resp["error"]["code"] == -32_602
    assert resp["error"]["data"]["missing"] == [@cc]

    resp = dispatch("tools/list", %{"_meta" => "not a map"})
    assert resp["error"]["data"]["missing"] == [@pv, @cc]
  end

  @tag oc: :none
  @tag oc_reason:
         "-32022 for a present-but-unsupported version: ServerUnsupportedVersionError is FAILURE live (discover has no -32022 gate; MES-163)"
  test "a present but unsupported version keeps -32022" do
    resp = dispatch("tools/list", %{"_meta" => %{@pv => "1999-01-01", @cc => %{}}})
    assert resp["error"]["code"] == -32_022
  end

  @tag oc: :none
  @tag oc_reason:
         "the removed methods' exemption is SDK policy (their stateless answers); no OC check probes initialize/ping without _meta"
  test "removed methods keep their stateless answers without _meta" do
    assert dispatch("initialize", %{})["error"]["code"] == -32_022
    assert dispatch("ping", %{})["error"]["code"] == -32_601
    assert dispatch("logging/setLevel", %{"level" => "info"})["error"]["code"] == -32_601
  end

  @tag oc: :none
  @tag oc_reason:
         "notifications carry no id and get no reply; the rule is stated for requests and no OC check probes it"
  test "a notification missing _meta is not answered" do
    note = %Notification{method: "notifications/cancelled", params: %{"requestId" => 1}}
    assert {:noreply, _} = Dispatch.dispatch(note, %ToolContext{}, config())
  end

  @tag oc: :none
  @tag oc_reason:
         "an SDK-internal invariant (the guard and the function agree); no wire behaviour"
  test "Meta.is_missing_required/1 agrees with Meta.missing_required/1" do
    require Meta

    inputs = [
      nil,
      %{},
      %{"_meta" => nil},
      %{"_meta" => "x"},
      %{"_meta" => %{}},
      %{"_meta" => %{@pv => @version}},
      %{"_meta" => %{@cc => %{}}},
      %{"_meta" => %{@pv => nil, @cc => %{}}},
      %{"_meta" => %{@pv => @version, @cc => nil}},
      %{"_meta" => @full},
      %{"_meta" => Map.put(@full, @ci, %{"name" => "c", "version" => "1"})}
    ]

    for params <- inputs do
      guarded = if Meta.is_missing_required(params), do: true, else: false
      assert guarded == (Meta.missing_required(params) != []), inspect(params)
    end

    assert Meta.required_keys() == [@pv, @cc]
  end

  # --- Streamable HTTP: 400, -32602, the request id ---

  @tag oc:
         "oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-meta"
  test "HTTP: no _meta → 400, -32602, id echoed" do
    {status, body} = post(%{}, 101)
    assert status == 400
    assert body["id"] == 101
    assert body["error"]["code"] == -32_602
  end

  @tag oc:
         "oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-protocol-version"
  test "HTTP: no protocolVersion → 400, -32602" do
    {status, body} = post(%{"_meta" => %{@cc => %{}}}, 102)
    assert status == 400
    assert body["id"] == 102
    assert body["error"]["code"] == -32_602
  end

  @tag oc: [
         "oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-client-capabilities",
         "oc:server/server-stateless/sep-2575-http-server-error-jsonrpc-id/HttpServerErrorJsonrpcId"
       ]
  test "HTTP: no clientCapabilities → 400, -32602, the error carries the request id" do
    {status, body} = post(%{"_meta" => %{@pv => @version}}, 104)
    assert status == 400
    assert body["jsonrpc"] == "2.0"
    assert body["id"] == 104
    assert body["error"]["code"] == -32_602
    assert body["error"]["data"]["missing"] == [@cc]
  end

  @tag oc: :none
  @tag oc_reason:
         "-32020 before -32602 is this SDK's stated order (MES-161 Q4); HttpServerHeaderMismatch400 sends a full _meta, so no OC check probes the order"
  test "HTTP: a routing-header mismatch is judged before the missing _meta" do
    {status, body} = post(%{}, 5, "tools/list", [{"mcp-method", "resources/list"}])
    assert status == 400
    assert body["error"]["code"] == -32_020
  end

  @tag oc: :none
  @tag oc_reason:
         "a well-formed request still reaches the handler; the regression limb of the gate"
  test "HTTP: a well-formed request is served (200)" do
    {status, body} = post(%{"_meta" => @full}, 9, "tools/list")
    assert status == 200
    assert is_list(body["result"]["tools"])
  end

  @tag oc: :none
  @tag oc_reason:
         "the order is this SDK's stated pipeline (MES-161 Q4); the harness runs a static identity, so no OC check reaches the factory"
  test "HTTP: the _meta check runs before the handler_opts factory" do
    test_pid = self()

    recording = [
      handler_opts: fn _conn ->
        send(test_pid, :factory_ran)
        []
      end
    ]

    {status, body} = post(%{"_meta" => %{@pv => @version}}, 105, "tools/list", [], recording)
    assert status == 400
    assert body["id"] == 105
    assert body["error"]["code"] == -32_602
    refute_received :factory_ran

    # The positive limb: the same factory does run for a well-formed request.
    {status, _body} = post(%{"_meta" => @full}, 106, "tools/list", [], recording)
    assert status == 200
    assert_received :factory_ran
  end

  @tag oc: :none
  @tag oc_reason:
         "a raising factory is a deployment fault no OC scenario can plant (MES-161 Q4 order); the harness runs a static identity"
  test "HTTP: a raising factory does not hide the -32602 or its id" do
    raising = [handler_opts: fn _conn -> raise "factory boom" end]

    {status, body} = post(%{"_meta" => %{@pv => @version}}, 107, "tools/list", [], raising)
    assert status == 400
    assert body["id"] == 107
    assert body["error"]["code"] == -32_602
    assert body["error"]["data"]["missing"] == [@cc]

    # The positive limb: for a well-formed request the factory's failure is the answer.
    {{status, body}, log} =
      with_log(fn -> post(%{"_meta" => @full}, 108, "tools/list", [], raising) end)

    assert status == 500
    assert log =~ "handler_opts factory failed"
    assert body["error"]["code"] == -32_603
  end
end

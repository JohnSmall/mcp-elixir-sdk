defmodule MCP.Transport.ClientSentResponseTest do
  @moduledoc """
  MES-168 — a client MUST NOT send a JSON-RPC response: the body of a POST is
  "a single JSON-RPC _request_ or _notification_" (`streamable-http.mdx:80-81`),
  and on stdio the client "MUST NOT write JSON-RPC _responses_"
  (`stdio.mdx:36-37`). The stateless core sends no server→client request for a
  response to answer, so the Plug refuses one as an invalid request (HTTP 400,
  -32600) before identity resolution or dispatch, and the stdio driver drops it.
  Before MES-168 the Plug passed the decoded `%Response{}` to
  `MCP.Server.Dispatch.dispatch/3`, which has no clause for it: a
  `FunctionClauseError` and an uncontrolled 500.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MCP.Server.Connection
  alias MCP.Test.{MockTransport, StatelessHandler}
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @full %{
    "io.modelcontextprotocol/protocolVersion" => @version,
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  defp post(message, headers) do
    base =
      :post
      |> conn("http://localhost/", Jason.encode!(message))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("origin", "http://localhost")

    conn =
      headers
      |> Enum.reduce(base, fn {k, v}, c -> put_req_header(c, k, v) end)
      |> MCPPlug.call(MCPPlug.init(server_mod: StatelessHandler, enable_json_response: true))

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp invalid_request!({status, body}) do
    assert status == 400
    assert body["error"]["code"] == -32_600
    body
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check POSTs a JSON-RPC response; searched the pinned dist (a10085d0) for one"
  test "a result response → 400 / -32600 with its id, not a FunctionClauseError" do
    body = invalid_request!(post(%{"jsonrpc" => "2.0", "id" => 7, "result" => %{}}, []))
    assert body["id"] == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check POSTs a JSON-RPC response; searched the pinned dist (a10085d0) for one"
  test "an error response → 400 / -32600 with its id" do
    message = %{"jsonrpc" => "2.0", "id" => "r1", "error" => %{"code" => -1, "message" => "x"}}
    body = invalid_request!(post(message, []))
    assert body["id"] == "r1"
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check POSTs a JSON-RPC response; searched the pinned dist (a10085d0) for one"
  test "a response that also names a method, with matching headers, is still refused" do
    message = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => %{},
      "method" => "tools/list",
      "params" => %{"_meta" => @full}
    }

    headers = [{"mcp-protocol-version", @version}, {"mcp-method", "tools/list"}]
    assert invalid_request!(post(message, headers))["id"] == 1
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check POSTs a JSON-RPC response; searched the pinned dist (a10085d0) for one"
  test "a response with a null id → 400 / -32600 with a null id" do
    body = invalid_request!(post(%{"jsonrpc" => "2.0", "id" => nil, "result" => %{}}, []))
    assert body["id"] == nil
  end

  @tag oc: :none
  @tag oc_reason: "the stdio limb: no OC scenario drives the stdio transport"
  test "over stdio a response is dropped, nothing is sent, and the next request is answered" do
    {:ok, pid} =
      Connection.start_link(transport: {MockTransport, []}, handler: {StatelessHandler, []})

    transport = Connection.transport(pid)
    MockTransport.inject(transport, %{"jsonrpc" => "2.0", "id" => 7, "result" => %{}})

    MockTransport.inject(transport, %{
      "jsonrpc" => "2.0",
      "id" => 8,
      "method" => "tools/list",
      "params" => %{"_meta" => @full}
    })

    # The request's reply is the first and only message: the response produced none.
    assert [%{"id" => 8, "result" => %{"tools" => _}}] = wait_for_sent(transport)
    assert Process.alive?(pid)
  end

  # Event-driven, bounded at 30 s (MES-191): it returns at the first sent message.
  defp wait_for_sent(transport), do: MockTransport.wait_for_sent(transport, 1)
end

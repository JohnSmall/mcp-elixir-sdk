defmodule MCP.Transport.StreamableHTTP.RequiredHeadersTest do
  @moduledoc """
  MES-155 — every Streamable HTTP POST carries `MCP-Protocol-Version` and
  `Mcp-Method`, and `Mcp-Name` when the method has a name target
  (`streamable-http.mdx:252-253`, `:280-281`, `:288-293`). A missing one, or a
  header version that contradicts the body's `_meta` version, fails header
  validation (`:622-625`): HTTP 400, -32020.

  Requests here are built header by header, deliberately NOT through
  `MCP.Test.RequiredHeaders` (which derives headers from the SDK client's
  `build_headers/2`), so these tests do not share the client's header logic.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MCP.Test.StatelessHandler
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @pv "io.modelcontextprotocol/protocolVersion"
  @cc "io.modelcontextprotocol/clientCapabilities"
  @full %{@pv => @version, @cc => %{}}

  defp plug_opts,
    do: MCPPlug.init(server_mod: StatelessHandler, enable_json_response: true)

  # `headers` are exactly the MCP headers sent — nothing is added for the caller.
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
      |> MCPPlug.call(plug_opts())

    {conn.status, if(conn.resp_body == "", do: nil, else: Jason.decode!(conn.resp_body))}
  end

  defp request(method, params, id \\ 1),
    do: %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

  defp header_error!({status, body}) do
    assert status == 400
    assert body["error"]["code"] == -32_020
    body["error"]
  end

  @tag oc: [
         "oc:server/http-header-validation/sep-2243-server-reject-invalid-headers/ServerRejectsMissingMethodHeader",
         "oc:server/http-header-validation/sep-2243-server-reject-error-code/ServerRejectsMissingMethodHeaderErrorCode"
       ]
  test "a POST without Mcp-Method → 400 / -32020" do
    error =
      request("tools/list", %{"_meta" => @full})
      |> post([{"mcp-protocol-version", @version}])
      |> header_error!()

    assert error["data"] =~ "Mcp-Method"
  end

  @tag oc: [
         "oc:server/http-header-validation/sep-2243-server-reject-invalid-headers/ServerRejectsMissingNameHeader",
         "oc:server/http-header-validation/sep-2243-server-reject-error-code/ServerRejectsMissingNameHeaderErrorCode"
       ]
  test "tools/call without Mcp-Name → 400 / -32020" do
    error =
      request("tools/call", %{"name" => "echo", "arguments" => %{}, "_meta" => @full})
      |> post([{"mcp-protocol-version", @version}, {"mcp-method", "tools/call"}])
      |> header_error!()

    assert error["data"] =~ "Mcp-Name"
  end

  @tag oc: :none
  @tag oc_reason:
         "the harness probes a missing Mcp-Name on tools/call only; resources/read and prompts/get are this SDK's reading of :288-293"
  test "resources/read and prompts/get without Mcp-Name → 400 / -32020" do
    for {method, params} <- [
          {"resources/read", %{"uri" => "file:///a.txt"}},
          {"prompts/get", %{"name" => "greet"}}
        ] do
      error =
        request(method, Map.put(params, "_meta", @full))
        |> post([{"mcp-protocol-version", @version}, {"mcp-method", method}])
        |> header_error!()

      assert error["data"] =~ "Mcp-Name"
    end
  end

  @tag oc: :none
  @tag oc_reason:
         "no check in the pinned harness build omits MCP-Protocol-Version on a server-leg POST"
  test "a POST without MCP-Protocol-Version → 400 / -32020" do
    error =
      request("tools/list", %{"_meta" => @full})
      |> post([{"mcp-method", "tools/list"}])
      |> header_error!()

    assert error["data"] == "missing required header MCP-Protocol-Version"
  end

  @tag oc: :none
  @tag oc_reason:
         "the missing-version limb alone: no header and no body version, so the equality limb cannot answer; no OC check omits both"
  test "a POST without MCP-Protocol-Version and without a body version → 400 / -32020, not -32602" do
    error =
      request("tools/list", %{"_meta" => %{@cc => %{}}})
      |> post([{"mcp-method", "tools/list"}])
      |> header_error!()

    assert error["data"] == "missing required header MCP-Protocol-Version"
  end

  @tag oc:
         "oc:server/server-stateless/sep-2575-http-server-header-mismatch-400/HttpServerHeaderMismatch400"
  test "a header version that contradicts the body's _meta version → 400 / -32020, not -32022" do
    error =
      request("server/discover", %{"_meta" => %{@pv => "v999.0.0", @cc => %{}}})
      |> post([{"mcp-protocol-version", @version}, {"mcp-method", "server/discover"}])
      |> header_error!()

    assert error["data"] =~ "MCP-Protocol-Version"
  end

  @tag oc: :none
  @tag oc_reason:
         "no check in the pinned harness build posts a notification without the standard headers"
  test "a notification POST without the headers → 400 / -32020; with them it is accepted" do
    note = %{
      "jsonrpc" => "2.0",
      "method" => "notifications/cancelled",
      "params" => %{"requestId" => 1, "_meta" => @full}
    }

    note |> post([]) |> header_error!()

    {status, _} =
      post(note, [{"mcp-protocol-version", @version}, {"mcp-method", "notifications/cancelled"}])

    assert status == 202
  end

  @tag oc: :none
  @tag oc_reason:
         "-32020 before -32602 is this SDK's stated pipeline order; no OC check sends both faults at once"
  test "a missing header is judged before a missing _meta" do
    request("tools/list", %{})
    |> post([{"mcp-protocol-version", @version}])
    |> header_error!()
  end

  @tag oc: :none
  @tag oc_reason:
         "the equality limb's skip condition; no OC check sends a header version with no body version"
  test "with every header present and no body version, the _meta gate answers -32602" do
    {status, body} =
      request("tools/list", %{"_meta" => %{@cc => %{}}})
      |> post([{"mcp-protocol-version", @version}, {"mcp-method", "tools/list"}])

    assert status == 400
    assert body["error"]["code"] == -32_602
  end

  @tag oc: :none
  @tag oc_reason:
         "a non-object _meta reaches the -32602 path instead of raising; no OC check sends one"
  test "a non-object _meta does not crash the header check" do
    {status, body} =
      request("tools/list", %{"_meta" => "not-an-object"})
      |> post([{"mcp-protocol-version", @version}, {"mcp-method", "tools/list"}])

    assert status == 400
    assert body["error"]["code"] == -32_602
  end

  @tag oc: :none
  @tag oc_reason:
         "a non-object JSON body raised BadMapError before MES-155; no OC check sends one"
  test "a JSON body that is not an object → 400 / -32600, no crash" do
    {status, body} = post([1], [])
    assert status == 400
    assert body["error"]["code"] == -32_600
  end

  @tag oc: :none
  @tag oc_reason: "the regression limb: a method with no name target needs no Mcp-Name"
  test "tools/list with MCP-Protocol-Version and Mcp-Method only → 200" do
    {status, body} =
      request("tools/list", %{"_meta" => @full})
      |> post([{"mcp-protocol-version", @version}, {"mcp-method", "tools/list"}])

    assert status == 200
    assert is_list(body["result"]["tools"])
  end
end

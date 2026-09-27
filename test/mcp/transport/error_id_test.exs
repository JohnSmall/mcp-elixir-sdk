defmodule MCP.Transport.StreamableHTTP.ErrorIdTest do
  @moduledoc """
  MES-157 — every JSON-RPC error body the Streamable HTTP Plug writes itself
  carries an `id`: the request's, where it can be read, and `null` only where it
  cannot (`basic/index.mdx:103`). A readable id is a string or a number in an
  object body; anything else is not one.

  Each unit asserts the `id` KEY, not just its value: before MES-157 the key was
  absent, and `body["id"] == nil` holds for an absent key too.

  No OC check measures these paths. `HttpServerErrorJsonrpcId` checks the id
  only on the -32602 `_meta` probes and on Dispatch's errors; with a wrong id on
  every body built here it stays SUCCESS (MES-157 plan 30422, mx2). So every unit
  is `oc: :none`.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test
  import Plug.Conn

  alias MCP.Test.{StatelessHandler, SubscribingHandler}
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @pv "io.modelcontextprotocol/protocolVersion"
  @cc "io.modelcontextprotocol/clientCapabilities"
  @full %{@pv => @version, @cc => %{}}
  @std [{"mcp-protocol-version", @version}, {"mcp-method", "tools/list"}]

  defp plug_opts(extra \\ []),
    do: MCPPlug.init([server_mod: StatelessHandler, enable_json_response: true] ++ extra)

  # `headers` are exactly the MCP headers sent — nothing is added for the caller.
  defp post_raw(body, headers, opts \\ plug_opts()) do
    base =
      :post
      |> conn("http://localhost/", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("origin", "http://localhost")

    conn =
      headers
      |> Enum.reduce(base, fn {k, v}, c -> put_req_header(c, k, v) end)
      |> MCPPlug.call(opts)

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp post(message, headers, opts \\ plug_opts()),
    do: post_raw(Jason.encode!(message), headers, opts)

  defp request(method, params, id \\ 7),
    do: %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

  defp error_with_id!({status, body}, expected_status, code) do
    assert status == expected_status
    assert body["jsonrpc"] == "2.0"
    assert body["error"]["code"] == code
    assert Map.has_key?(body, "id"), "error body has no id key: #{inspect(body)}"
    body["id"]
  end

  # --- -32700 / -32600: no id readable ---

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32700 parse error → id null" do
    assert post_raw("{not json", @std) |> error_with_id!(400, -32_700) == nil
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32600 on an array (batch) body → id null, though an element has id 7" do
    body = Jason.encode!([request("tools/list", %{"_meta" => @full})])
    assert post_raw(body, @std) |> error_with_id!(400, -32_600) == nil
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32600 on a string body → id null" do
    assert post_raw(~s("x"), @std) |> error_with_id!(400, -32_600) == nil
  end

  # --- -32600: an object body, id readable ---

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32600 on jsonrpc \"1.0\" with id 7 → id 7" do
    message = %{request("tools/list", %{"_meta" => @full}) | "jsonrpc" => "1.0"}
    assert post(message, @std) |> error_with_id!(400, -32_600) == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32600 on an object with an id and no method → that id" do
    message = %{"jsonrpc" => "2.0", "id" => 7}

    assert post(message, [{"mcp-protocol-version", @version}]) |> error_with_id!(400, -32_600) ==
             7
  end

  # --- -32020: every limb, id readable ---

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 missing MCP-Protocol-Version → id 7" do
    result = post(request("tools/list", %{"_meta" => @full}), [{"mcp-method", "tools/list"}])
    assert error_with_id!(result, 400, -32_020) == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 missing Mcp-Method → id 7" do
    result =
      post(request("tools/list", %{"_meta" => @full}), [{"mcp-protocol-version", @version}])

    assert error_with_id!(result, 400, -32_020) == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 missing Mcp-Name on tools/call → id 7" do
    result =
      request("tools/call", %{"name" => "echo", "arguments" => %{}, "_meta" => @full})
      |> post([{"mcp-protocol-version", @version}, {"mcp-method", "tools/call"}])

    assert error_with_id!(result, 400, -32_020) == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 header version contradicting the _meta version → id 7" do
    result = post(request("tools/list", %{"_meta" => %{@full | @pv => "2025-11-25"}}), @std)
    assert error_with_id!(result, 400, -32_020) == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 Mcp-Method mismatch → id 7" do
    result =
      request("tools/list", %{"_meta" => @full})
      |> post([{"mcp-protocol-version", @version}, {"mcp-method", "prompts/list"}])

    assert error_with_id!(result, 400, -32_020) == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 Mcp-Name mismatch → id 7" do
    result =
      request("tools/call", %{"name" => "echo", "arguments" => %{}, "_meta" => @full})
      |> post([
        {"mcp-protocol-version", @version},
        {"mcp-method", "tools/call"},
        {"mcp-name", "other"}
      ])

    assert error_with_id!(result, 400, -32_020) == 7
  end

  # --- -32020: the id's type decides readability ---

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 with a string id → that string" do
    result =
      post(request("tools/list", %{"_meta" => @full}, "req-abc"), [{"mcp-method", "tools/list"}])

    assert error_with_id!(result, 400, -32_020) == "req-abc"
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 on a notification (no id) → id null" do
    message = %{"jsonrpc" => "2.0", "method" => "notifications/x"}
    assert post(message, []) |> error_with_id!(400, -32_020) == nil
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "-32020 with an object id → id null (not a readable id)" do
    message = request("tools/list", %{"_meta" => @full}, %{"a" => 1})
    assert post(message, []) |> error_with_id!(400, -32_020) == nil
  end

  # --- -32603 + HTTP 500: id readable ---

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "500 when the handler_opts factory raises → id 7" do
    opts = plug_opts(handler_opts: fn _conn -> raise "boom" end)

    {result, _log} =
      with_log(fn -> post(request("tools/list", %{"_meta" => @full}), @std, opts) end)

    assert error_with_id!(result, 500, -32_603) == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "500 when the notification collector cannot start → id 7" do
    opts = plug_opts(collector_start: fn -> {:error, :nope} end)

    {result, _log} =
      with_log(fn -> post(request("tools/list", %{"_meta" => @full}), @std, opts) end)

    assert error_with_id!(result, 500, -32_603) == 7
  end

  @tag oc: :none
  @tag oc_reason:
         "HttpServerErrorJsonrpcId probes no send_json_error path (MES-157 30422 mx2 stays SUCCESS)"
  test "500 when the subscription stream cannot start → the request's id" do
    opts =
      MCPPlug.init(
        server_mod: SubscribingHandler,
        handler_opts: [owner: self(), identity: "alice"],
        stream_start: fn _conn -> {:error, %RuntimeError{message: "socket gone"}} end
      )

    message =
      request(
        "subscriptions/listen",
        %{"_meta" => @full, "notifications" => %{"toolsListChanged" => true}},
        "wont-start"
      )

    {result, _log} =
      with_log(fn ->
        post(
          message,
          [{"mcp-protocol-version", @version}, {"mcp-method", "subscriptions/listen"}],
          opts
        )
      end)

    assert error_with_id!(result, 500, -32_603) == "wont-start"
  end
end

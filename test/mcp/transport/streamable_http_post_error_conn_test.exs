defmodule MCP.Transport.StreamableHTTP.PostErrorConnTest do
  @moduledoc """
  MES-213 — every error reply `handle_post/2` sends after the body is read
  goes out on the conn `read_body/2` returned, over **real HTTP** (Bandit).

  While the read sat inside the `with`, its rebinding of `conn` did not reach
  the `else`, so these branches answered on the pre-read conn. Bandit 1.13
  refuses a stale conn ("Guard against stale conn reuse", #668) and the client
  got a bare 500 with an empty body. `Plug.Test`'s adapter does not enforce the
  contract, so a plug-unit test cannot see this: only a socket can.

  The other post-read branches already have socket-level tests that went red
  on the bump: `factory_failed` (`streamable_http_ac_test.exs`, AC8),
  `routing_mismatch` (`streamable_http_error_reply_test.exs`) and
  `invalid_request` (`subscriptions_stream_test.exs`, R4). This file covers
  the four that had none.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MCP.Test.{RequiredHeaders, StatelessHandler}
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @base_headers [
    {"content-type", "application/json"},
    {"accept", "application/json"},
    {"origin", "http://localhost"}
  ]

  @tag oc: "oc:none/no-oc-scenario/malformed-body--32700"
  test "a body that is not JSON is a 400 / -32700 JSON-RPC error, not an empty 500" do
    resp = post_raw(start_instance(), "{not json", @base_headers)

    assert resp.status == 400
    assert resp.body["error"]["code"] == -32_700
  end

  @tag oc:
         "oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400#missing-meta"
  test "a request with no _meta is a 400 / -32602 JSON-RPC error, not an empty 500" do
    body = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
    resp = post_raw(start_instance(), body, @base_headers ++ RequiredHeaders.for_body(body))

    assert resp.status == 400
    assert resp.body["id"] == 1
    assert resp.body["error"]["code"] == -32_602
  end

  @tag oc: "oc:none/no-oc-scenario/collector-start-failure"
  test "a collector that fails to start is a 500 / -32603 JSON-RPC error, not an empty 500" do
    url = start_instance(collector_start: fn -> {:error, :injected} end)
    body = rpc("tools/list", %{})

    {resp, _log} =
      with_log(fn -> post_raw(url, body, @base_headers ++ RequiredHeaders.for_body(body)) end)

    assert resp.status == 500
    assert resp.body["id"] == 1
    assert resp.body["error"]["code"] == -32_603
  end

  @tag oc: :none
  @tag oc_reason:
         "a JSON body that is not an object (the catch-all branch): the pinned harness never sends one, so no OC check corresponds"
  test "a JSON body that is not an object is a 400 / -32600 JSON-RPC error, not an empty 500" do
    resp = post_raw(start_instance(), "[1]", @base_headers)

    assert resp.status == 400
    assert resp.body["error"]["code"] == -32_600
  end

  # --- harness ---

  defp start_instance(extra_opts \\ []) do
    # Port 0, read back once bound (MES-215).

    plug_opts =
      MCPPlug.init(
        Keyword.merge([server_mod: StatelessHandler, enable_json_response: true], extra_opts)
      )

    {bandit, port} =
      MCP.Test.Listener.bandit!(plug: {MCPPlug, plug_opts}, port: 0, ip: {127, 0, 0, 1})

    on_exit(fn -> Process.exit(bandit, :normal) end)
    "http://127.0.0.1:#{port}"
  end

  # MES-215: no port-picking helper here. Every listener in this file binds
  # port 0 through MCP.Test.Listener.bandit!/2, which reads back the port the OS
  # assigned, so no port is chosen before it is bound: the window in which
  # another socket could take it (:eaddrinuse) does not exist. RC3 in
  # listener_port_race_test.exs holds the whole test tree to that.
  # It replaced a per-file probe that closed its socket before the bind.

  defp rpc(method, params) do
    meta = %{
      "io.modelcontextprotocol/protocolVersion" => @version,
      "io.modelcontextprotocol/clientCapabilities" => %{}
    }

    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" => Map.put(params, "_meta", meta)
    })
  end

  # `retry: false`: a 500 must be measured once, not retried by `Req`.
  defp post_raw(url, body, headers) do
    {:ok, resp} = Req.post(url, body: body, headers: headers, retry: false)
    resp
  end
end

defmodule MCP.Transport.StreamableHTTPErrorReplyTest do
  @moduledoc """
  MES-189: a JSON-RPC error carried on an HTTP 4xx/5xx, over real Streamable
  HTTP (Bandit on 127.0.0.1).

  Before this ticket the client transport turned every status other than
  200/201/202 into `{:error, {:http_error, status, body}}`, so `MCP.Client`
  failed the caller with `:transport_send_failed`. A server's correct
  400 / `-32022`, `-32020` or `-32602`, or 404 / `-32601`, never reached the
  caller as `%MCP.Protocol.Error{}`. That meant the client's one-shot version
  retry and its `tools/list` refresh never ran over HTTP. MES-163 proved them
  only over the in-process bridge.

  Now, a 4xx/5xx answering a POSTed **request** whose body is a JSON object
  with an `error` member and the request's own `id` is delivered exactly as a
  200 JSON reply would be. Every other answer keeps `:http_error`, which is
  what the named CONTROLS below pin.

  The first three tests run against the SDK's own server. The rest use
  `MCP.Test.HTTPErrorStubPlug`, which can force a status, header or body.
  """
  use ExUnit.Case, async: false

  alias MCP.Protocol.Error
  alias MCP.Test.HeaderStrippingPlug
  alias MCP.Test.HTTPErrorReplyHandler
  alias MCP.Test.HTTPErrorStubPlug
  alias MCP.Transport.StreamableHTTP.Client, as: HTTPClient
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @origin [{"origin", "http://localhost"}]

  describe "against the SDK's own server" do
    @tag oc:
           "oc:client/request-metadata/sep-2575-client-retry-supported-version/ClientRetrySupportedVersion"
    test "400 / -32022 is retried once with the server's version, in header and _meta, and answered" do
      url = start_sdk_server(strip_first_name: false)
      client = start_client(url, protocol_version: "2025-11-25", headers: @origin)

      assert {:ok, %{"tools" => [%{"name" => "echo"}]}} = MCP.Client.list_tools(client)

      # The header is recorded here. The body's `_meta` version is proved by the
      # server: it ANSWERED, so Dispatch's version gate passed (the body says
      # 2026-07-28) and the Plug's header-equals-body check passed (no -32020).
      assert_received {:posted, "tools/list", "2025-11-25", false}
      assert_received {:posted, "tools/list", "2026-07-28", false}
      refute_received {:posted, _, _, _}
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client scenario answers a tools/call with -32020, so the refresh is never exercised"
    test "400 / -32020 on tools/call is refreshed via tools/list, retried once and answered" do
      url = start_sdk_server(strip_first_name: true)
      client = start_client(url, headers: @origin)

      assert {:ok, %{"content" => [%{"text" => "ok"}]}} = MCP.Client.call_tool(client, "echo")

      # Exactly one request was altered (the first tools/call). The refresh and
      # the retry passed through the front Plug untouched.
      assert_received {:posted, "tools/call", "2026-07-28", true}
      assert_received {:posted, "tools/list", "2026-07-28", false}
      assert_received {:posted, "tools/call", "2026-07-28", false}
      refute_received {:posted, _, _, _}
    end

    @tag oc: :none
    @tag oc_reason: "no OC client check observes a 404 / -32601 reaching the caller"
    test "404 / -32601 reaches the caller as the exact %Error{}" do
      url = start_sdk_server(strip_first_name: false)
      client = start_client(url, headers: @origin)

      assert {:error,
              %Error{code: -32_601, message: "Method not found", data: "handle_list_prompts"}} =
               MCP.Client.list_prompts(client)
    end
  end

  describe "against a stub that forces the answer" do
    @tag oc: :none
    @tag oc_reason: "no OC client check observes a 400 / -32602 reaching the caller"
    test "400 / -32602 reaches the caller as the exact %Error{}" do
      client =
        stub_client(fn %{"id" => id} ->
          json(400, error_reply(id, -32_602, "Invalid params", %{"field" => "name"}))
        end)

      assert {:error,
              %Error{code: -32_602, message: "Invalid params", data: %{"field" => "name"}}} =
               MCP.Client.call_tool(client, "x")
    end

    @tag oc: :none
    @tag oc_reason: "no OC client check sends a malformed error member on a 4xx"
    test "a 4xx whose error member is malformed fails the caller at once with :malformed_response" do
      client =
        stub_client(fn %{"id" => id} ->
          json(400, %{"jsonrpc" => "2.0", "id" => id, "error" => "oops"})
        end)

      assert {:error, {:malformed_response, %Error{}}} = MCP.Client.call_tool(client, "x")
    end

    @tag oc: :none
    @tag oc_reason: "no OC client check sends a reply carrying both result and error on a 4xx"
    test "a 4xx carrying both result and error fails the caller at once with :malformed_response" do
      client =
        stub_client(fn %{"id" => id} ->
          json(400, Map.put(error_reply(id, -32_602, "Invalid params"), "result", %{}))
        end)

      assert {:error, {:malformed_response, %Error{}}} = MCP.Client.call_tool(client, "x")
    end

    @tag oc: :none
    @tag oc_reason:
           "the OC request-metadata mock rejects only the first request, so a repeated -32022 is never sent"
    test "a repeated 400 / -32022 reaches the caller after exactly one retry, with no loop" do
      client =
        stub_client(
          fn %{"id" => id} ->
            json(
              400,
              error_reply(id, -32_022, "Unsupported protocol version", %{
                "supported" => ["2026-07-28"],
                "requested" => "2026-07-28"
              })
            )
          end,
          :all
        )

      assert {:error, %Error{code: -32_022}} = MCP.Client.list_tools(client)
      assert_received {:stub_posted, %{"method" => "tools/list"}}
      assert_received {:stub_posted, %{"method" => "tools/list"}}
      refute_received {:stub_posted, _}
    end

    @tag oc: :none
    @tag oc_reason: "no OC client check sends a content-coded 4xx"
    test "a 4xx with a non-identity content-encoding is refused by the encoding guard, not decoded" do
      client =
        stub_client(fn %{"id" => id} ->
          json(400, error_reply(id, -32_602, "Invalid params"), [{"content-encoding", "gzip"}])
        end)

      assert {:error, {:transport_send_failed, {:unexpected_content_encoding, "gzip"}}} =
               MCP.Client.call_tool(client, "x")
    end

    @tag oc: :none
    @tag oc_reason: "no OC client check sends a 4xx with a literal identity content-encoding"
    test "a 4xx with a literal identity content-encoding (left undecoded by Req) is delivered" do
      client =
        stub_client(fn %{"id" => id} ->
          json(400, error_reply(id, -32_602, "Invalid params"), [{"content-encoding", "identity"}])
        end)

      assert {:error, %Error{code: -32_602, message: "Invalid params"}} =
               MCP.Client.call_tool(client, "x")
    end
  end

  # CONTROLS: green before and after MES-189. Each one pins a shape that must
  # keep today's `:http_error`, and then shows the client is still alive by
  # completing a later request.
  describe "CONTROL: every other answer keeps :http_error" do
    @tag oc: :none
    @tag oc_reason: "control; no OC client check sends a 4xx naming a different id"
    test "CONTROL: an error naming a different id" do
      assert_http_error(400, fn %{"id" => id} ->
        json(400, error_reply(id + 1000, -32_602, "Invalid params"))
      end)
    end

    @tag oc: :none
    @tag oc_reason: "control; no OC client check observes the client's handling of an id-null 4xx"
    test "CONTROL: an error with a null id" do
      assert_http_error(400, fn _ -> json(400, error_reply(nil, -32_602, "Invalid params")) end)
    end

    @tag oc: :none
    @tag oc_reason: "control; no OC client check sends a non-JSON 4xx body"
    test "CONTROL: a non-JSON text/plain body" do
      assert_http_error(400, fn _ -> {400, [{"content-type", "text/plain"}], "Bad Request"} end)
    end

    @tag oc: :none
    @tag oc_reason: "control; no OC client check sends a JSON array on a 4xx"
    test "CONTROL: a JSON array" do
      assert_http_error(400, fn %{"id" => id} ->
        json(400, [error_reply(id, -32_602, "Invalid params")])
      end)
    end

    @tag oc: :none
    @tag oc_reason: "control; no OC client check sends a JSON null on a 4xx"
    test "CONTROL: a JSON null" do
      assert_http_error(400, fn _ -> {400, [{"content-type", "application/json"}], "null"} end)
    end

    @tag oc: :none
    @tag oc_reason: "control; no OC client check sends a 4xx object without an error member"
    test "CONTROL: an object naming the id but carrying no error member" do
      assert_http_error(400, fn %{"id" => id} ->
        json(400, %{"jsonrpc" => "2.0", "id" => id, "detail" => "nope"})
      end)
    end

    @tag oc: :none
    @tag oc_reason: "control; no OC client check sends a 5xx HTML page"
    test "CONTROL: a 503 HTML page" do
      assert_http_error(503, fn _ ->
        {503, [{"content-type", "text/html"}], "<html><body>Service Unavailable</body></html>"}
      end)
    end

    @tag oc: :none
    @tag oc_reason: "control; no OC client check sends a matching error on a non-error 2xx status"
    test "CONTROL: a matching error on a 203, outside the 400-599 range" do
      assert_http_error(203, fn %{"id" => id} ->
        json(203, error_reply(id, -32_602, "Invalid params"))
      end)
    end

    @tag oc: :none
    @tag oc_reason:
           "control at the transport; no OC client check answers a notification with a 4xx"
    test "CONTROL: a notification POST answered with a 400 error returns :http_error and delivers nothing" do
      url =
        start_server(
          {HTTPErrorStubPlug,
           test: self(),
           respond: fn _ -> json(400, error_reply(nil, -32_600, "Invalid request")) end}
        )

      {:ok, transport} = HTTPClient.start_link(owner: self(), url: url)

      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/cancelled",
        "params" => %{"requestId" => 1}
      }

      assert {:error, {:http_error, 400, %{"error" => %{"code" => -32_600}}}} =
               HTTPClient.send_message(transport, notification)

      refute_received {:mcp_message, _}
      assert Process.alive?(transport)
    end
  end

  # --- Helpers ---

  defp assert_http_error(status, forced) do
    client = stub_client(forced)

    assert {:error, {:transport_send_failed, {:http_error, ^status, _body}}} =
             MCP.Client.call_tool(client, "x")

    assert Process.alive?(client)
    assert {:ok, %{"tools" => []}} = MCP.Client.list_tools(client)
  end

  # The forced answer is given to `tools/call` only, and `tools/list` gets a
  # plain 200, so a control can show the client still works. With `:all`, every
  # request gets the forced answer.
  defp stub_client(forced, scope \\ :tools_call) do
    respond = fn
      %{"method" => "tools/call"} = message -> forced.(message)
      message when scope == :all -> forced.(message)
      %{"id" => id} -> json(200, %{"jsonrpc" => "2.0", "id" => id, "result" => %{"tools" => []}})
    end

    url = start_server({HTTPErrorStubPlug, test: self(), respond: respond})
    start_client(url, request_timeout: 5_000)
  end

  defp start_sdk_server(opts) do
    plug =
      {HeaderStrippingPlug,
       test: self(),
       once: :ets.new(:mes189_once, [:public]),
       strip_first_name: Keyword.fetch!(opts, :strip_first_name),
       plug: MCPPlug.init(server_mod: HTTPErrorReplyHandler, enable_json_response: true)}

    start_server(plug)
  end

  defp start_server(plug) do
    port = free_port()

    {:ok, server} =
      Bandit.start_link(plug: plug, port: port, ip: {127, 0, 0, 1}, startup_log: false)

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :normal) end)
    "http://127.0.0.1:#{port}/"
  end

  defp start_client(url, opts) do
    {headers, opts} = Keyword.pop(opts, :headers, [])

    {:ok, client} =
      MCP.Client.start_link([transport: {HTTPClient, url: url, headers: headers}] ++ opts)

    client
  end

  defp error_reply(id, code, message, data \\ nil) do
    error = %{"code" => code, "message" => message}
    error = if data, do: Map.put(error, "data", data), else: error
    %{"jsonrpc" => "2.0", "id" => id, "error" => error}
  end

  defp json(status, body, headers \\ []),
    do: {status, [{"content-type", "application/json"} | headers], Jason.encode!(body)}

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end

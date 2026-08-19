defmodule MCP.ClientTest do
  @moduledoc """
  MES-9 — the stateless `MCP.Client`: no `initialize` handshake, ready by
  default, `server/discover` capability probe, per-request `_meta`, and MRTR
  client-retry. Driven in isolation via `MockTransport`.

  The 2025-11-25 server→client request handling (client-side sampling / roots /
  elicitation callbacks) is removed with the held-open request path (D-B); its
  replacement is the MRTR `:on_input_required` resolver, exercised below.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias MCP.Client
  alias MCP.Test.MockTransport

  @server_info %{"name" => "test-server", "version" => "1.0.0"}
  @server_capabilities %{
    "tools" => %{"listChanged" => true},
    "resources" => %{"listChanged" => true},
    "prompts" => %{"listChanged" => true}
  }

  defp wait_for_sent(transport, count, timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_sent(transport, count, deadline)
  end

  defp do_wait_for_sent(transport, count, deadline) do
    messages = MockTransport.sent_messages(transport)

    cond do
      length(messages) >= count ->
        messages

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Timed out waiting for #{count} messages, got #{length(messages)}")

      true ->
        Process.sleep(5)
        do_wait_for_sent(transport, count, deadline)
    end
  end

  defp start_client(opts \\ []) do
    {:ok, client} =
      Client.start_link(
        Keyword.merge(
          [transport: {MockTransport, []}, client_info: %{name: "test-client", version: "0.1.0"}],
          opts
        )
      )

    {client, Client.transport(client)}
  end

  # connect → one sent message (server/discover). Inject the discover result.
  defp do_connect(client, transport) do
    task = Task.async(fn -> Client.connect(client) end)
    [discover] = wait_for_sent(transport, 1)
    assert discover["method"] == "server/discover"

    MockTransport.inject(transport, %{
      "jsonrpc" => "2.0",
      "id" => discover["id"],
      "result" => %{
        "supportedVersions" => ["2026-07-28"],
        "capabilities" => @server_capabilities,
        "resultType" => "complete",
        "ttlMs" => 0,
        "cacheScope" => "public",
        "_meta" => %{"io.modelcontextprotocol/serverInfo" => @server_info}
      }
    })

    {:ok, result} = Task.await(task)
    assert result.server_info.name == "test-server"
    :ok
  end

  # The Nth request after connect is sent message index N (connect is 0).
  defp last_after_connect(transport, n) do
    messages = wait_for_sent(transport, 1 + n)
    List.last(messages)
  end

  describe "start_link/1" do
    test "starts ready by default (no handshake gate)" do
      {client, transport} = start_client()
      assert is_pid(client)
      assert is_pid(transport)
      assert Client.status(client) == :ready
    end
  end

  describe "connect/1 (server/discover)" do
    test "probes capabilities and returns server info" do
      {client, transport} = start_client()
      task = Task.async(fn -> Client.connect(client) end)

      [discover] = wait_for_sent(transport, 1)
      assert discover["method"] == "server/discover"

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => discover["id"],
        "result" => %{
          "supportedVersions" => ["2026-07-28"],
          "capabilities" => @server_capabilities,
          "resultType" => "complete",
          "ttlMs" => 0,
          "cacheScope" => "public",
          "_meta" => %{"io.modelcontextprotocol/serverInfo" => @server_info}
        }
      })

      {:ok, result} = Task.await(task)
      assert result.server_info.name == "test-server"
      assert result.server_capabilities.tools != nil
      assert result.protocol_version == "2026-07-28"
    end

    test "returns error on discover failure" do
      {client, transport} = start_client()
      task = Task.async(fn -> Client.connect(client) end)
      [discover] = wait_for_sent(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => discover["id"],
        "error" => %{"code" => -32_603, "message" => "Internal error"}
      })

      {:error, error} = Task.await(task)
      assert error.code == -32_603
    end
  end

  describe "per-request _meta" do
    test "every request carries protocolVersion + client identity/capabilities" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.list_tools(client) end)
      req = last_after_connect(transport, 1)

      meta = req["params"]["_meta"]
      assert meta["io.modelcontextprotocol/protocolVersion"] == "2026-07-28"
      assert meta["io.modelcontextprotocol/clientInfo"]["name"] == "test-client"
      assert is_map(meta["io.modelcontextprotocol/clientCapabilities"])

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req["id"],
        "result" => %{"tools" => []}
      })

      {:ok, _} = Task.await(task)
    end
  end

  describe "requests" do
    test "list_tools returns tools" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.list_tools(client) end)
      req = last_after_connect(transport, 1)
      assert req["method"] == "tools/list"

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req["id"],
        "result" => %{"tools" => [%{"name" => "echo"}]}
      })

      {:ok, result} = Task.await(task)
      assert hd(result["tools"])["name"] == "echo"
    end

    test "call_tool sends name and arguments" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.call_tool(client, "echo", %{"message" => "hi"}) end)
      req = last_after_connect(transport, 1)
      assert req["method"] == "tools/call"
      assert req["params"]["name"] == "echo"
      assert req["params"]["arguments"] == %{"message" => "hi"}

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req["id"],
        "result" => %{"content" => [%{"type" => "text", "text" => "hi"}]}
      })

      {:ok, result} = Task.await(task)
      assert hd(result["content"])["text"] == "hi"
    end

    test "call_tool surfaces an error response" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.call_tool(client, "bad", %{}) end)
      req = last_after_connect(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req["id"],
        "error" => %{"code" => -32_601, "message" => "Method not found"}
      })

      {:error, error} = Task.await(task)
      assert error.code == -32_601
    end

    test "read_resource sends the uri" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.read_resource(client, "file:///t.txt") end)
      req = last_after_connect(transport, 1)
      assert req["method"] == "resources/read"
      assert req["params"]["uri"] == "file:///t.txt"

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req["id"],
        "result" => %{"contents" => [%{"uri" => "file:///t.txt", "text" => "hello"}]}
      })

      {:ok, result} = Task.await(task)
      assert hd(result["contents"])["text"] == "hello"
    end

    test "get_prompt sends name and arguments" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.get_prompt(client, "greeting", %{"name" => "World"}) end)
      req = last_after_connect(transport, 1)
      assert req["method"] == "prompts/get"
      assert req["params"]["arguments"] == %{"name" => "World"}

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req["id"],
        "result" => %{
          "messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hi"}}]
        }
      })

      {:ok, result} = Task.await(task)
      assert length(result["messages"]) == 1
    end
  end

  describe "MRTR client retry" do
    test "an input_required result is transparently completed via :on_input_required" do
      {client, transport} =
        start_client(on_input_required: fn _requests -> [%{"name" => "Ada"}] end)

      do_connect(client, transport)

      task = Task.async(fn -> Client.call_tool(client, "needs_input", %{}) end)
      first = last_after_connect(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => first["id"],
        "result" => %{
          "resultType" => "input_required",
          "inputRequests" => [%{"kind" => "elicitation"}],
          "requestState" => "rs-1"
        }
      })

      # The client auto-retries carrying requestState + inputResponses.
      retry = last_after_connect(transport, 2)
      assert retry["method"] == "tools/call"
      assert retry["params"]["requestState"] == "rs-1"
      assert retry["params"]["inputResponses"] == [%{"name" => "Ada"}]

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => retry["id"],
        "result" => %{
          "resultType" => "complete",
          "content" => [%{"type" => "text", "text" => "hi Ada"}]
        }
      })

      {:ok, result} = Task.await(task)
      assert hd(result["content"])["text"] == "hi Ada"
    end

    test "without a resolver the input_required result is returned as-is" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.call_tool(client, "needs_input", %{}) end)
      req = last_after_connect(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req["id"],
        "result" => %{"resultType" => "input_required", "requestState" => "rs-1"}
      })

      {:ok, result} = Task.await(task)
      assert result["resultType"] == "input_required"
    end
  end

  describe "notifications" do
    test "dispatches to a pid handler" do
      {client, transport} = start_client(notification_handler: self())
      do_connect(client, transport)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "method" => "notifications/tools/list_changed"
      })

      assert_receive {:mcp_notification, "notifications/tools/list_changed", nil}, 1000
    end

    test "dispatches to a function handler" do
      test_pid = self()
      handler = fn method, params -> send(test_pid, {:notif, method, params}) end
      {client, transport} = start_client(notification_handler: handler)
      do_connect(client, transport)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "method" => "notifications/message",
        "params" => %{"level" => "info", "data" => "hello"}
      })

      assert_receive {:notif, "notifications/message", %{"level" => "info"}}, 1000
    end
  end

  describe "lifecycle" do
    test "close is idempotent" do
      {client, _transport} = start_client()
      assert :ok = Client.close(client)
      assert :ok = Client.close(client)
    end

    test "times out a pending request" do
      {client, transport} = start_client(request_timeout: 50)
      do_connect(client, transport)
      assert {:error, :timeout} = Client.list_tools(client, timeout: 200)
    end

    test "notifies pending requests when the transport closes" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.list_tools(client) end)
      wait_for_sent(transport, 2)
      send(client, {:mcp_transport_closed, :normal})

      assert {:error, {:transport_closed, :normal}} = Task.await(task)
      assert Client.status(client) == :closed
    end
  end

  describe "cancel/3" do
    test "sends a cancellation notification" do
      {client, transport} = start_client()
      do_connect(client, transport)

      Client.cancel(client, 42, "no longer needed")
      notification = last_after_connect(transport, 1)
      assert notification["method"] == "notifications/cancelled"
      assert notification["params"]["requestId"] == 42
      refute Map.has_key?(notification, "id")
    end
  end

  describe "pagination" do
    test "list_all_tools paginates through pages" do
      {client, transport} = start_client()
      do_connect(client, transport)

      task = Task.async(fn -> Client.list_all_tools(client) end)
      req1 = last_after_connect(transport, 1)
      refute req1["params"]["cursor"]

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req1["id"],
        "result" => %{"tools" => [%{"name" => "t1"}], "nextCursor" => "c1"}
      })

      req2 = last_after_connect(transport, 2)
      assert req2["params"]["cursor"] == "c1"

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => req2["id"],
        "result" => %{"tools" => [%{"name" => "t2"}]}
      })

      {:ok, tools} = Task.await(task)
      assert length(tools) == 2
    end
  end

  describe "server_capabilities/1 and server_info/1" do
    test "returns discovered capabilities and info" do
      {client, transport} = start_client()
      do_connect(client, transport)

      assert Client.server_capabilities(client).tools != nil
      assert Client.server_info(client).name == "test-server"
    end
  end

  describe "concurrent requests" do
    test "handles multiple concurrent requests" do
      {client, transport} = start_client()
      do_connect(client, transport)

      t1 = Task.async(fn -> Client.list_tools(client) end)
      t2 = Task.async(fn -> Client.list_resources(client) end)

      messages = wait_for_sent(transport, 3)

      messages
      |> Enum.filter(&(Map.has_key?(&1, "id") && &1["method"] != "server/discover"))
      |> Enum.each(fn req ->
        result =
          if req["method"] == "tools/list", do: %{"tools" => []}, else: %{"resources" => []}

        MockTransport.inject(transport, %{
          "jsonrpc" => "2.0",
          "id" => req["id"],
          "result" => result
        })
      end)

      assert {:ok, _} = Task.await(t1)
      assert {:ok, _} = Task.await(t2)
    end
  end

  # MES-16 — the client half of the SEP-2133 negotiation surface: what a client
  # stamps into its per-request `_meta`, and what it does with what a server
  # advertises.
  #
  # A7: positive controls, not caught regressions. `extensions` did not exist in
  # this codebase before MES-16, so nothing here can fail at a pre-fix SHA. T5
  # (omission) and T4 (presence) are each other's deliberately-wrong fixture:
  # they differ only in whether anything is declared, so neither can pass
  # trivially while the other holds.
  describe "extensions negotiation (SEP-2133) — T4, T5, T15" do
    alias MCP.Protocol.Capabilities.ClientCapabilities

    @extensions %{"io.modelcontextprotocol/tasks" => %{}}
    @capabilities_key "io.modelcontextprotocol/clientCapabilities"

    # T4. schema.ts:91-98 — the client's capabilities ride EVERY request's
    # `_meta`, per request, because there is no handshake to declare them once.
    test "T4 — a declared extension is stamped into every request's _meta" do
      {client, transport} =
        start_client(client_capabilities: %ClientCapabilities{extensions: @extensions})

      do_connect(client, transport)
      Task.async(fn -> Client.list_tools(client) end)
      request = last_after_connect(transport, 1)

      assert request["params"]["_meta"][@capabilities_key]["extensions"] == @extensions
    end

    test "T4 — and into the server/discover probe itself" do
      {client, transport} =
        start_client(client_capabilities: %ClientCapabilities{extensions: @extensions})

      Task.async(fn -> Client.connect(client) end)
      [discover] = wait_for_sent(transport, 1)

      assert discover["params"]["_meta"][@capabilities_key]["extensions"] == @extensions
    end

    # T5. Absent, not `{}` — the default client declares nothing at all.
    test "T5 — the key is omitted entirely when nothing is declared" do
      {client, transport} = start_client()

      Task.async(fn -> Client.connect(client) end)
      [discover] = wait_for_sent(transport, 1)

      capabilities = discover["params"]["_meta"][@capabilities_key]
      assert is_map(capabilities)
      refute Map.has_key?(capabilities, "extensions")
    end

    # Outbound validation applies on the client side too: the SDK's "we never
    # emit an identifier that violates schema.ts:779-780" guarantee has to hold
    # in both directions or it is not a guarantee.
    @tag :capture_log
    test "an invalid identifier is dropped on the way out; an all-invalid declaration vanishes" do
      {client, transport} =
        start_client(
          client_capabilities: %ClientCapabilities{
            extensions: %{"com.example/kept" => %{}, "no-prefix" => %{}}
          }
        )

      Task.async(fn -> Client.connect(client) end)
      [discover] = wait_for_sent(transport, 1)

      assert discover["params"]["_meta"][@capabilities_key]["extensions"] ==
               %{"com.example/kept" => %{}}

      {client2, transport2} =
        start_client(client_capabilities: %ClientCapabilities{extensions: %{"bad" => %{}}})

      Task.async(fn -> Client.connect(client2) end)
      [discover2] = wait_for_sent(transport2, 1)

      refute Map.has_key?(discover2["params"]["_meta"][@capabilities_key], "extensions")
    end

    # T15. The client direction of "handle the map correctly while supporting
    # zero": a server's advertised extensions must survive the round trip
    # instead of being silently discarded by `ServerCapabilities.from_map/1`,
    # which keeps only the keys it knows.
    test "T15 — a server's advertised extensions are surfaced, not discarded" do
      {client, transport} = start_client()
      task = Task.async(fn -> Client.connect(client) end)
      [discover] = wait_for_sent(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => discover["id"],
        "result" => %{
          "supportedVersions" => ["2026-07-28"],
          "capabilities" => Map.put(@server_capabilities, "extensions", @extensions),
          "resultType" => "complete",
          "ttlMs" => 0,
          "cacheScope" => "public",
          "_meta" => %{"io.modelcontextprotocol/serverInfo" => @server_info}
        }
      })

      {:ok, result} = Task.await(task)

      assert result.server_capabilities.extensions == @extensions
      assert Client.server_capabilities(client).extensions == @extensions
    end

    # Inbound is never validated: a server may advertise whatever it likes and
    # the client reports it verbatim rather than rewriting the peer's claim.
    test "a server's malformed advertisement is reported verbatim, not rewritten" do
      {client, transport} = start_client()
      task = Task.async(fn -> Client.connect(client) end)
      [discover] = wait_for_sent(transport, 1)

      malformed = %{"no-prefix" => %{}}

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => discover["id"],
        "result" => %{
          "supportedVersions" => ["2026-07-28"],
          "capabilities" => Map.put(@server_capabilities, "extensions", malformed),
          "resultType" => "complete",
          "ttlMs" => 0,
          "cacheScope" => "public",
          "_meta" => %{"io.modelcontextprotocol/serverInfo" => @server_info}
        }
      })

      {:ok, result} = Task.await(task)
      assert result.server_capabilities.extensions == malformed
    end

    # R-2 (round 1), the client half of the same property: nothing a consumer
    # puts in `:client_capabilities` may fail later than `start_link/1`. A
    # settings value the JSON encoder cannot handle used to survive
    # normalisation here too, and would then have failed when the transport
    # came to serialise the request — arbitrarily far from the launch config
    # that caused it. It is dropped at the seam, named in a warning, and the
    # request that follows is well-formed and encodable.
    @tag :capture_log
    test "an unencodable settings value never reaches the wire (dropped at start_link)" do
      {client, transport} =
        start_client(
          client_capabilities: %ClientCapabilities{
            extensions: %{"com.example/kept" => %{}, "com.example/tuple" => %{"t" => {1, 2}}}
          }
        )

      Task.async(fn -> Client.connect(client) end)
      [discover] = wait_for_sent(transport, 1)

      assert discover["params"]["_meta"][@capabilities_key]["extensions"] ==
               %{"com.example/kept" => %{}}

      assert is_binary(Jason.encode!(discover))
    end

    # R-8 (round 2). The round-1 guarantee was stated about `:client_capabilities`
    # and checked about `%ClientCapabilities{}`: the normalising clause matched
    # the struct and a catch-all passed EVERYTHING ELSE through untouched, into
    # state and then into `encode/1` on every request. So a plain map — which
    # the neighbouring `:client_info` option does accept, which is how a
    # consumer arrives at one — bypassed the seam entirely.
    #
    # This half is R-1's class: a MUST-violating identifier on the wire, no
    # drop, no warning. The value is now discarded whole and the default used,
    # so the identifier cannot appear.
    test "R-8 — a non-struct :client_capabilities is discarded, not passed through" do
      log =
        capture_log(fn ->
          {client, transport} =
            start_client(client_capabilities: %{"extensions" => %{"no-prefix" => %{}}})

          Task.async(fn -> Client.connect(client) end)
          [discover] = wait_for_sent(transport, 1)

          capabilities = discover["params"]["_meta"][@capabilities_key]
          assert capabilities == %{}
          refute Map.has_key?(capabilities, "extensions")
        end)

      # Discarding a consumer's whole capabilities value is a real loss, so the
      # warning has to say that rather than merely note a type mismatch.
      assert log =~ "`:client_capabilities`"
      assert log =~ "DISCARDED"
      assert log =~ "extensions"
    end

    # The other half of R-8, and the one that costs a process: `start_link/1`
    # accepted this and the FIRST request then raised `Protocol.UndefinedError`
    # out of `Jason` inside `with_meta/2`, killing the client — the deferred
    # failure the round-1 property exists to rule out, reachable through a
    # bypass of the code that implements it.
    @tag :capture_log
    test "R-8 — and the first request no longer kills the client" do
      {client, transport} =
        start_client(
          client_capabilities: %{"extensions" => %{"com.example/x" => %{"t" => {1, 2}}}}
        )

      Task.async(fn -> Client.connect(client) end)
      [discover] = wait_for_sent(transport, 1)

      assert is_binary(Jason.encode!(discover))
      assert Process.alive?(client)
      assert Client.status(client) == :ready
    end
  end
end

defmodule MCP.ClientDefectsTest do
  @moduledoc """
  MES-18 — the four client defects found while planning this ticket (D-1..D-4),
  each one on the path of a **scored** core client scenario.

  ## Evidence posture (A7)

  Two of these are **caught regressions**: T-D1 and T-D2 were written against
  the unfixed tree at `2829769`, run, and observed to FAIL for the stated
  reason. The other two are **positive controls** on paths that were latent —
  T-D4's mismatch was unreachable before CG1 gave the transport a reason to
  read the message, and T-D3's retry is new behaviour. Labelled per test so a
  control is never read as a caught regression.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias MCP.Client
  alias MCP.Test.MockTransport

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

  describe "D-1 — MRTR retry omits requestState when the server sent none (CAUGHT REGRESSION)" do
    @describetag :mes18

    # Scenario `sep-2322-client-request-state`, check
    # `sep-2322-client-no-state-omitted`. The harness asserts
    # `requestState !== undefined`; a JSON `null` satisfies that and FAILS the
    # check, so an unconditional `Map.put` of a nil value is non-conformant
    # even though it "looks" like an absent value from Elixir.
    #
    # OBSERVED AT 2829769, BEFORE THE FIX:
    #   Assertion with == failed
    #   code:  assert Map.has_key?(retry["params"], "requestState") == false
    #   left:  true
    #   right: false
    test "an absent server requestState produces a retry with NO requestState key" do
      {client, transport} =
        start_client(on_input_required: fn _requests -> %{"answer" => "42"} end)

      task = Task.async(fn -> Client.call_tool(client, "t", %{}) end)
      [call] = wait_for_sent(transport, 1)

      # InputRequiredResult carrying NO requestState — the server is not
      # obliged to send one (schema.ts: the field is optional).
      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => call["id"],
        "result" => %{
          "resultType" => "input_required",
          "inputRequests" => [%{"name" => "answer", "type" => "string"}]
        }
      })

      [_call, retry] = wait_for_sent(transport, 2)

      refute Map.has_key?(retry["params"], "requestState"),
             "retry params carried #{inspect(Map.get(retry["params"], "requestState"))} " <>
               "under a PRESENT requestState key; the client MUST NOT include the key at all"

      assert retry["params"]["inputResponses"] == %{"answer" => "42"}

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => retry["id"],
        "result" => %{"resultType" => "complete", "content" => []}
      })

      assert {:ok, %{"resultType" => "complete"}} = Task.await(task)
    end

    # The discriminating mutation: an explicit JSON `null` from the server is
    # the SAME wire fact as an absent field — no state was sent — so it must
    # produce the same absent key. This is the clause that would regress if
    # someone "fixed" D-1 with `if Map.has_key?(result, "requestState")`.
    test "an explicit null server requestState also produces NO requestState key" do
      {client, transport} =
        start_client(on_input_required: fn _requests -> %{} end)

      task = Task.async(fn -> Client.call_tool(client, "t", %{}) end)
      [call] = wait_for_sent(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => call["id"],
        "result" => %{
          "resultType" => "input_required",
          "requestState" => nil,
          "inputRequests" => []
        }
      })

      [_call, retry] = wait_for_sent(transport, 2)
      refute Map.has_key?(retry["params"], "requestState")

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => retry["id"],
        "result" => %{"resultType" => "complete", "content" => []}
      })

      assert {:ok, _} = Task.await(task)
    end

    # The other half of the property: when the server DOES send state, the
    # client MUST echo it. Positive control, and it is what stops the fix
    # from degenerating into "never send requestState".
    test "a server requestState is echoed verbatim on the retry (control)" do
      {client, transport} =
        start_client(on_input_required: fn _requests -> %{"a" => 1} end)

      task = Task.async(fn -> Client.call_tool(client, "t", %{}) end)
      [call] = wait_for_sent(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => call["id"],
        "result" => %{
          "resultType" => "input_required",
          "requestState" => "opaque-server-token",
          "inputRequests" => []
        }
      })

      [_call, retry] = wait_for_sent(transport, 2)
      assert retry["params"]["requestState"] == "opaque-server-token"

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => retry["id"],
        "result" => %{"resultType" => "complete", "content" => []}
      })

      assert {:ok, _} = Task.await(task)
    end
  end

  describe "D-2 — a failed transport send fails the call (CAUGHT REGRESSION)" do
    @describetag :mes18

    # `send_request/4` discarded `send_message/2`'s return value and registered
    # the request as pending regardless, so every send failure surfaced as
    # `{:error, :timeout}` after the full `request_timeout` with the real
    # reason visible only in a log line.
    #
    # OBSERVED AT 2829769, BEFORE THE FIX (with request_timeout: 200):
    #   match (=) failed
    #   code:  assert {:error, {:transport_send_failed, {:http_error, 400, _}}} =
    #            Client.call_tool(client, "t", %{})
    #   left:  {:error, {:transport_send_failed, {:http_error, 400, _}}}
    #   right: {:error, :timeout}
    test "the caller gets the transport's reason, not a timeout" do
      {client, _transport} =
        start_client(
          transport: {MockTransport, [send_result: {:error, {:http_error, 400, "nope"}}]},
          request_timeout: 200
        )

      assert {:error, {:transport_send_failed, {:http_error, 400, "nope"}}} =
               Client.call_tool(client, "t", %{})
    end

    # The mechanism, not just the symptom: a failed send must leave NO pending
    # request behind. Were it registered, the reply above would race a later
    # `{:request_timeout, id}` and reply twice to a dead caller.
    test "a failed send registers no pending request" do
      {client, _transport} =
        start_client(
          transport: {MockTransport, [send_result: {:error, :econnrefused}]},
          request_timeout: 100
        )

      assert {:error, {:transport_send_failed, :econnrefused}} = Client.list_tools(client)

      # Long enough for a stray timeout message to arrive if one were scheduled;
      # the client must still be alive and serving.
      Process.sleep(250)
      assert Process.alive?(client)
      assert Client.status(client) == :ready
    end

    test "a failed send on the MRTR retry path fails the original caller" do
      # The retry rides `resume_mrtr/5`, the other caller of `send_request/4`;
      # it had the same blind spot.
      {:ok, client} =
        Client.start_link(
          transport: {MockTransport, []},
          request_timeout: 200,
          on_input_required: fn _ -> %{} end
        )

      transport = Client.transport(client)
      task = Task.async(fn -> Client.call_tool(client, "t", %{}) end)
      [call] = wait_for_sent(transport, 1)

      :ok = MockTransport.set_send_result(transport, {:error, :closed_mid_flight})

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => call["id"],
        "result" => %{"resultType" => "input_required", "inputRequests" => []}
      })

      assert {:error, {:transport_send_failed, :closed_mid_flight}} = Task.await(task)
    end
  end

  describe "D-4 — the version header and _meta move in lockstep (POSITIVE CONTROL)" do
    @describetag :mes18

    # Latent before this ticket: the defaults agreed, so nothing diverged in
    # practice. It is a control on a MUST (`streamable-http.mdx:255-259`) and a
    # precondition of D-3 — after a retry changes the version, the header must
    # change with it.
    test "the transport derives mcp-protocol-version from the message's own _meta" do
      alias MCP.Transport.StreamableHTTP.Client, as: HTTPClient

      headers =
        HTTPClient.build_headers(
          %HTTPClient{protocol_version: "2026-07-28", extra_headers: []},
          %{
            "method" => "tools/list",
            "params" => %{"_meta" => %{"io.modelcontextprotocol/protocolVersion" => "1999-01-01"}}
          }
        )

      assert {"mcp-protocol-version", "1999-01-01"} in headers
    end

    test "it falls back to its configured default when the message carries no _meta version" do
      alias MCP.Transport.StreamableHTTP.Client, as: HTTPClient

      headers =
        HTTPClient.build_headers(
          %HTTPClient{protocol_version: "2026-07-28", extra_headers: []},
          %{"method" => "server/discover", "params" => %{}}
        )

      assert {"mcp-protocol-version", "2026-07-28"} in headers
    end
  end

  describe "D-3 — one-shot retry on -32022 (POSITIVE CONTROL)" do
    @describetag :mes18

    # Normative basis (C-1): `basic/versioning.mdx:69-71` at the pinned commit
    # 5f5440bb — "The client SHOULD select a mutually supported version from
    # the `supported` list and retry the request, or surface an error to the
    # user if no compatible version exists." A SHOULD, cited from the spec and
    # not from the harness check name `sep-2575-client-retry-supported-version`.
    test "a -32022 naming a version we support is retried exactly once" do
      {client, transport} = start_client()

      task = Task.async(fn -> Client.list_tools(client) end)
      [first] = wait_for_sent(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => first["id"],
        "error" => %{
          "code" => -32_022,
          "message" => "Unsupported protocol version",
          "data" => %{"supported" => ["2026-07-28"], "requested" => "2026-07-28"}
        }
      })

      [_first, retry] = wait_for_sent(transport, 2)
      assert retry["method"] == "tools/list"

      assert retry["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] ==
               "2026-07-28"

      # And it is ONE-shot: a second -32022 is surfaced, not retried again.
      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => retry["id"],
        "error" => %{
          "code" => -32_022,
          "message" => "Unsupported protocol version",
          "data" => %{"supported" => ["2026-07-28"], "requested" => "2026-07-28"}
        }
      })

      assert {:error, %MCP.Protocol.Error{code: -32_022}} = Task.await(task)
      assert length(MockTransport.sent_messages(transport)) == 2
    end

    test "a -32022 offering only versions we do not support is surfaced, never retried" do
      # ADR-003 sub-decision 5: this client is 2026-07-28 only and negotiates
      # down to nothing. The retry can never reach for 2025-11-25.
      {client, transport} = start_client()

      task = Task.async(fn -> Client.list_tools(client) end)
      [first] = wait_for_sent(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => first["id"],
        "error" => %{
          "code" => -32_022,
          "message" => "Unsupported protocol version",
          "data" => %{"supported" => ["2025-11-25", "2025-06-18"], "requested" => "2026-07-28"}
        }
      })

      assert {:error, %MCP.Protocol.Error{code: -32_022}} = Task.await(task)
      assert length(MockTransport.sent_messages(transport)) == 1
    end

    test "a -32022 with no usable data is surfaced, never retried" do
      {client, transport} = start_client()

      task = Task.async(fn -> Client.list_tools(client) end)
      [first] = wait_for_sent(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => first["id"],
        "error" => %{"code" => -32_022, "message" => "Unsupported protocol version"}
      })

      assert {:error, %MCP.Protocol.Error{code: -32_022}} = Task.await(task)
      assert length(MockTransport.sent_messages(transport)) == 1
    end

    test "the retry re-stamps the version chosen from `supported`" do
      # The client advertises something the server rejects; the server offers
      # 2026-07-28, which we do support, so the retry must carry THAT version
      # in `_meta` — not the originally-configured one.
      {client, transport} = start_client(protocol_version: "2026-07-28")

      task = Task.async(fn -> Client.list_tools(client) end)
      [first] = wait_for_sent(transport, 1)

      assert first["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] == "2026-07-28"

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => first["id"],
        "error" => %{
          "code" => -32_022,
          "message" => "Unsupported protocol version",
          "data" => %{"supported" => ["2026-07-28"], "requested" => "2026-07-28"}
        }
      })

      [_first, retry] = wait_for_sent(transport, 2)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => retry["id"],
        "result" => %{"tools" => []}
      })

      assert {:ok, %{"tools" => []}} = Task.await(task)
    end

    test "a non-32022 error is never retried" do
      {client, transport} = start_client()

      task = Task.async(fn -> Client.list_tools(client) end)
      [first] = wait_for_sent(transport, 1)

      MockTransport.inject(transport, %{
        "jsonrpc" => "2.0",
        "id" => first["id"],
        "error" => %{"code" => -32_601, "message" => "Method not found"}
      })

      assert {:error, %MCP.Protocol.Error{code: -32_601}} = Task.await(task)
      assert length(MockTransport.sent_messages(transport)) == 1
    end

    test "the retry is logged so an operator can see the version changed" do
      {client, transport} = start_client()

      log =
        capture_log(fn ->
          task = Task.async(fn -> Client.list_tools(client) end)
          [first] = wait_for_sent(transport, 1)

          MockTransport.inject(transport, %{
            "jsonrpc" => "2.0",
            "id" => first["id"],
            "error" => %{
              "code" => -32_022,
              "message" => "Unsupported protocol version",
              "data" => %{"supported" => ["2026-07-28"], "requested" => "2026-07-28"}
            }
          })

          [_first, retry] = wait_for_sent(transport, 2)

          MockTransport.inject(transport, %{
            "jsonrpc" => "2.0",
            "id" => retry["id"],
            "result" => %{"tools" => []}
          })

          assert {:ok, _} = Task.await(task)
        end)

      # The distinctive phrase, not a bare version string: this runs async and
      # `capture_log/1` captures the global logger.
      assert log =~ "one-shot retry of tools/list"
      assert log =~ "2026-07-28"
    end
  end
end

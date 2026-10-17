defmodule MCP.ClientMalformedReplyTest do
  @moduledoc """
  MES-197 — a reply `MCP.Protocol.decode_message/1` refuses (-32600) that still
  names a request this client has pending fails that caller at once, rather
  than leaving it to its request timeout (MES-190 Q6).

  A refused term ties to a caller when it is a map whose `"id"` is an integer
  in the pending map and it is not request-shaped: it has `"result"` or
  `"error"`, or it has no `"method"`. The caller gets
  `{:error, {:malformed_response, %Error{code: -32600}}}`, or, for the
  `tools/list` refresh a `-32020` triggers,
  `{:error, {:malformed_refresh_response, %Error{code: -32600}, original}}`.
  Every other refused term is logged and dropped, as before.

  No test here waits on a clock. Each refused term is followed by a valid reply
  for the same id, so a client that drops the term answers the caller with that
  reply instead, and the test sees the difference by order, not by time.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias MCP.Client
  alias MCP.Protocol.Error
  alias MCP.Test.MockTransport

  # The tied classes of the MES-197 census (plan part 1): A, B×3, C and G2.
  defp tied_terms(id) do
    [
      {"A an error member that is a string",
       %{"jsonrpc" => "2.0", "id" => id, "error" => "boom"}},
      {"B1 no jsonrpc member", %{"id" => id, "result" => %{}}},
      {"B2 jsonrpc 1.0",
       %{"jsonrpc" => "1.0", "id" => id, "error" => %{"code" => -1, "message" => "m"}}},
      {"B3 jsonrpc as a number", %{"jsonrpc" => 2.0, "id" => id, "result" => %{}}},
      {"C an id and nothing else", %{"jsonrpc" => "2.0", "id" => id}},
      {"G2 an id, a method and a malformed error",
       %{"jsonrpc" => "2.0", "id" => id, "method" => "x", "error" => "boom"}}
    ]
  end

  # The untied classes: D×6, E, F×4, G1 and H×2.
  defp untied_terms(id) do
    [
      {"D1 a JSON array holding the reply", [ok_reply(id)]},
      {"D2 a string", "x"},
      {"D3 a number", 5},
      {"D4 null", nil},
      {"D5 a foreign atom", :foo},
      {"D6 an atom-keyed map", %{jsonrpc: "2.0", id: id, error: "boom"}},
      {"E an id that is not pending", %{"jsonrpc" => "2.0", "id" => id + 100, "error" => "boom"}},
      {"F1 the id as a string",
       %{"jsonrpc" => "2.0", "id" => Integer.to_string(id), "error" => "boom"}},
      {"F2 the id as a float", %{"jsonrpc" => "2.0", "id" => id * 1.0, "error" => "boom"}},
      {"F3 a null id", %{"jsonrpc" => "2.0", "id" => nil, "error" => "boom"}},
      {"F4 the id in a list", %{"jsonrpc" => "2.0", "id" => [id], "error" => "boom"}},
      {"G1 request-shaped", %{"id" => id, "method" => "ping"}},
      {"H1 notification-shaped", %{"method" => "notifications/x"}},
      {"H2 no id and no method", %{"jsonrpc" => "2.0", "result" => %{}}}
    ]
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a refused JSON-RPC reply; read the 7 client-leg scenarios of in-scope-2026-07-28 and grepped the pinned dist (a10085d0)"
  test "N1 a refused reply naming a pending request fails that caller at once; the late reply is ignored" do
    outcomes =
      for {name, _} <- tied_terms(0) do
        {client, transport} = start_client()
        task = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
        [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)
        term = tied_term(name, id)

        {result, log} =
          with_log(fn ->
            MockTransport.inject(transport, term)
            MockTransport.inject(transport, ok_reply(id))
            result = Task.await(task, :infinity)
            settle(client, transport)
            result
          end)

        {name,
         {outcome(result), log =~ "failed to decode message", log =~ "unknown request id",
          next_request_answered?(client, transport, 2)}}
      end

    expected = for {name, _} <- tied_terms(0), do: {name, {:malformed_response, true, true, true}}
    assert outcomes == expected
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a refused JSON-RPC reply; read the 7 client-leg scenarios of in-scope-2026-07-28 and grepped the pinned dist (a10085d0)"
  test "N2 a refused reply that names no pending request is logged and dropped, and fails nobody" do
    outcomes =
      for {name, _} <- untied_terms(0) do
        {client, transport} = start_client()
        task = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
        [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)
        term = untied_term(name, id)

        {result, log} =
          with_log(fn ->
            MockTransport.inject(transport, term)
            MockTransport.inject(transport, ok_reply(id))
            result = Task.await(task, :infinity)
            settle(client, transport)
            result
          end)

        {name, {outcome(result), log =~ "failed to decode message", Process.alive?(client)}}
      end

    expected = for {name, _} <- untied_terms(0), do: {name, {:ok, true, true}}
    assert outcomes == expected
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a refused JSON-RPC reply; read the 7 client-leg scenarios of in-scope-2026-07-28 and grepped the pinned dist (a10085d0)"
  test "N3 with two requests pending, only the one the refused reply names fails" do
    {client, transport} = start_client()
    first = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    [%{"id" => first_id}] = MockTransport.wait_for_sent(transport, 1)
    second = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    [_, %{"id" => second_id}] = MockTransport.wait_for_sent(transport, 2)

    capture_log(fn ->
      MockTransport.inject(transport, refused(second_id))
      MockTransport.inject(transport, ok_reply(first_id))
      MockTransport.inject(transport, ok_reply(second_id))

      assert outcome(Task.await(second, :infinity)) == :malformed_response
      assert outcome(Task.await(first, :infinity)) == :ok
    end)
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a refused JSON-RPC reply; read the 7 client-leg scenarios of in-scope-2026-07-28 and grepped the pinned dist (a10085d0)"
  test "N4 the failed request's pending entry is removed and its timer cancelled" do
    {client, transport} = start_client()
    task = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)

    # Read-only white-box inspection: the timer is not observable from outside.
    %{timeout_ref: ref} = Map.fetch!(:sys.get_state(client).pending_requests, id)
    assert is_integer(Process.read_timer(ref))

    capture_log(fn ->
      MockTransport.inject(transport, refused(id))
      MockTransport.inject(transport, ok_reply(id))
      assert outcome(Task.await(task, :infinity)) == :malformed_response
      settle(client, transport)
    end)

    assert :sys.get_state(client).pending_requests == %{}
    assert Process.read_timer(ref) == false

    # A timeout message that had already been sent for the id finds nothing.
    send(client, {:request_timeout, id})
    assert Client.status(client) == :ready
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a refused JSON-RPC reply; read the 7 client-leg scenarios of in-scope-2026-07-28 and grepped the pinned dist (a10085d0)"
  test "N5 a refused reply to the -32020 refresh carries the original HeaderMismatch" do
    {client, transport} = start_client()

    capture_log(fn ->
      task = Task.async(fn -> Client.call_tool(client, "t", %{}, timeout: :infinity) end)
      [%{"id" => call_id}] = MockTransport.wait_for_sent(transport, 1)

      MockTransport.inject(transport, error_reply(call_id, -32_020, "Header mismatch"))

      [_, %{"id" => refresh_id, "method" => "tools/list"}] =
        MockTransport.wait_for_sent(transport, 2)

      MockTransport.inject(transport, refused(refresh_id))
      MockTransport.inject(transport, error_reply(refresh_id, -32_603, "Internal error"))

      assert {:error,
              {:malformed_refresh_response, %Error{code: -32_600, message: "Invalid request"},
               %Error{code: -32_020}}} = Task.await(task, :infinity)
    end)
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a refused JSON-RPC reply; read the 7 client-leg scenarios of in-scope-2026-07-28 and grepped the pinned dist (a10085d0)"
  test "N6 a refused reply to the -32022 version retry or the MRTR retry fails the caller" do
    {client, transport} = start_client()

    version_outcome =
      capture_and_return(fn ->
        task = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
        [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)

        MockTransport.inject(transport, %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{
            "code" => -32_022,
            "message" => "Unsupported protocol version",
            "data" => %{"supported" => ["2026-07-28"], "requested" => "2026-07-28"}
          }
        })

        [_, %{"id" => retry_id}] = MockTransport.wait_for_sent(transport, 2)
        MockTransport.inject(transport, refused(retry_id))
        MockTransport.inject(transport, ok_reply(retry_id))
        outcome(Task.await(task, :infinity))
      end)

    {client, transport} = start_client(on_input_required: fn _requests -> %{} end)

    mrtr_outcome =
      capture_and_return(fn ->
        task = Task.async(fn -> Client.call_tool(client, "t", %{}, timeout: :infinity) end)
        [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)

        MockTransport.inject(transport, %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => %{"resultType" => "input_required", "inputRequests" => %{}}
        })

        [_, %{"id" => retry_id, "method" => "tools/call"}] =
          MockTransport.wait_for_sent(transport, 2)

        # A complete 2026-07-28 result, as every resolver-configured unit sends
        # (D2b's resultType negative).
        MockTransport.inject(transport, refused(retry_id))

        MockTransport.inject(transport, %{
          "jsonrpc" => "2.0",
          "id" => retry_id,
          "result" => %{"resultType" => "complete", "content" => []}
        })

        outcome(Task.await(task, :infinity))
      end)

    assert {version_outcome, mrtr_outcome} == {:malformed_response, :malformed_response}
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a refused JSON-RPC reply; read the 7 client-leg scenarios of in-scope-2026-07-28 and grepped the pinned dist (a10085d0)"
  test "N7 over real HTTP, a refused reply in an SSE response fails the caller at once" do
    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, port} = :inet.port(listen)

    # One request, one response: the malformed reply, then a valid one, for the id
    # the client sent. Every wait is on a socket event, bounded by ExUnit's timeout.
    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen)
        %{"id" => id} = socket |> read_request() |> Jason.decode!()

        body =
          "event: message\ndata: #{Jason.encode!(refused(id))}\n\n" <>
            "event: message\ndata: #{Jason.encode!(ok_reply(id))}\n\n"

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n" <>
              "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <> body
          )

        :gen_tcp.close(socket)
      end)

    {:ok, client} =
      Client.start_link(
        transport: {MCP.Transport.StreamableHTTP.Client, url: "http://127.0.0.1:#{port}/"},
        client_info: %{name: "c", version: "0"}
      )

    {result, _log} = with_log(fn -> Client.list_prompts(client, timeout: :infinity) end)
    Task.await(server, :infinity)

    assert {outcome(result), Process.alive?(client)} == {:malformed_response, true}
  end

  defp start_client(opts \\ []) do
    {:ok, client} =
      Client.start_link(
        [transport: {MockTransport, []}, client_info: %{name: "c", version: "0"}] ++ opts
      )

    {client, Client.transport(client)}
  end

  defp tied_term(name, id), do: tied_terms(id) |> List.keyfind!(name, 0) |> elem(1)
  defp untied_term(name, id), do: untied_terms(id) |> List.keyfind!(name, 0) |> elem(1)

  defp refused(id), do: %{"jsonrpc" => "2.0", "id" => id, "error" => "boom"}
  defp ok_reply(id), do: %{"jsonrpc" => "2.0", "id" => id, "result" => %{"prompts" => []}}

  defp error_reply(id, code, message),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}

  defp outcome(
         {:error, {:malformed_response, %Error{code: -32_600, message: "Invalid request"}}}
       ),
       do: :malformed_response

  defp outcome({:ok, %{"prompts" => []}}), do: :ok
  defp outcome(other), do: other

  # Both injected messages have left the transport once it answers a call, and the
  # client has handled them once it answers one.
  defp settle(client, transport) do
    MockTransport.sent_messages(transport)
    Client.status(client)
  end

  defp next_request_answered?(client, transport, count) do
    task = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    sent = MockTransport.wait_for_sent(transport, count)
    MockTransport.inject(transport, ok_reply(List.last(sent)["id"]))
    outcome(Task.await(task, :infinity)) == :ok
  end

  defp capture_and_return(fun) do
    {result, _log} = with_log(fun)
    result
  end

  defp read_request(socket, acc \\ "") do
    case :binary.split(acc, "\r\n\r\n") do
      [head, body] ->
        length = content_length(head)
        if byte_size(body) >= length, do: body, else: read_more(socket, acc)

      [_] ->
        read_more(socket, acc)
    end
  end

  defp read_more(socket, acc) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    read_request(socket, acc <> data)
  end

  defp content_length(head) do
    case Regex.run(~r/^content-length:\s*(\d+)\s*$/im, head) do
      [_, length] -> String.to_integer(length)
      nil -> 0
    end
  end
end

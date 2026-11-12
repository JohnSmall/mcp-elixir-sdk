defmodule MCP.ClientNullIdErrorTest do
  @moduledoc """
  MES-211 — an error reply whose `id` is null (JSON-RPC 2.0 §5; this SDK's own
  stdio server sends one, ADR-004) is tied to the pending request when exactly
  one is pending, and fails that caller at once through the normal reply path.
  With none or several pending it is logged and ties to nobody, so every caller
  keeps its own timeout (PO ruling on MES-211, 35079).

  No pass path here waits on a clock. Where the transport allows it, each
  null-id reply is followed by a valid reply for the pending id, so a client
  that drops the null-id reply answers with that reply instead, and the test
  sees the difference by order, not by time.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias MCP.Client
  alias MCP.Protocol.Error
  alias MCP.Test.MockTransport

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends a client a null-id error while one request is pending outside an HTTP 400/500 reply; grepped the pinned dist (a10085d0): its 5 id:null sites are all 400/500 bodies"
  test "N1 with one request pending, a null-id error fails that caller at once" do
    {client, transport} = start_client()
    task = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)

    log =
      capture_log(fn ->
        MockTransport.inject(transport, null_id_error())
        MockTransport.inject(transport, ok_reply(id))
        send(self(), {:result, Task.await(task, :infinity)})
        settle(client, transport)
      end)

    assert_received {:result, {:error, %Error{code: -32_700, message: "Parse error"}}}
    assert log =~ "response for unknown request id=#{id}"
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends a client a null-id error while requests are pending outside an HTTP 400/500 reply; grepped the pinned dist (a10085d0): its 5 id:null sites are all 400/500 bodies"
  test "N2 with two requests pending, a null-id error fails neither and is logged" do
    {client, transport} = start_client()
    t1 = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    [%{"id" => id1}] = MockTransport.wait_for_sent(transport, 1)
    t2 = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    [_, %{"id" => id2}] = MockTransport.wait_for_sent(transport, 2)

    log =
      capture_log(fn ->
        MockTransport.inject(transport, null_id_error())
        MockTransport.inject(transport, ok_reply(id1))
        MockTransport.inject(transport, ok_reply(id2))
        send(self(), {:results, Task.await_many([t1, t2], :infinity)})
      end)

    assert_received {:results, [{:ok, %{"prompts" => []}}, {:ok, %{"prompts" => []}}]}

    assert log =~
             "error reply with a null id (-32700: Parse error) ties to no request: 2 pending"
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends a client an unsolicited null-id error; grepped the pinned dist (a10085d0): its 5 id:null sites are all HTTP 400/500 bodies answering a request"
  test "N3 with nothing pending, a null-id error is logged and the client keeps serving" do
    {client, transport} = start_client()

    log =
      capture_log(fn ->
        MockTransport.inject(transport, null_id_error())
        settle(client, transport)
      end)

    assert log =~ "ties to no request: 0 pending"
    task = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)
    MockTransport.inject(transport, ok_reply(id))
    assert {:ok, %{"prompts" => []}} = Task.await(task, :infinity)
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends a client a null id beside a result; grepped the pinned dist (a10085d0): its 5 id:null sites all carry an error member"
  test "N4 a null id beside a result is not a §5 reply and ties to nobody" do
    {client, transport} = start_client()
    task = Task.async(fn -> Client.list_prompts(client, timeout: :infinity) end)
    [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)

    log =
      capture_log(fn ->
        MockTransport.inject(transport, %{"jsonrpc" => "2.0", "id" => nil, "result" => %{}})
        MockTransport.inject(transport, ok_reply(id))
        send(self(), {:result, Task.await(task, :infinity)})
      end)

    assert_received {:result, {:ok, %{"prompts" => []}}}
    assert log =~ "response for unknown request id=nil"
  end

  @tag :tmp_dir
  @tag oc: :none
  @tag oc_reason:
         "no OC check drives a client over stdio; grepped the pinned dist (a10085d0): its 5 id:null sites are all HTTP 400/500 bodies"
  test "S1 over the stdio transport, a null-id error fails the one pending caller", %{
    tmp_dir: tmp_dir
  } do
    # The child records its pid, answers the first line with a null-id error and
    # then reads to EOF: it holds stdout open until the client closes stdin, so
    # only the tie can answer the caller, and it exits with the client. A
    # dropped reply fails at the 10 s request timeout; the pass path is
    # immediate.
    script = ~S"""
    printf '%s\n' "$$" > "$1/child.pid"
    read -r line
    printf '%s\n' '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}'
    while read -r line; do :; done
    """

    {:ok, client} =
      Client.start_link(
        transport: {MCP.Transport.Stdio, command: "/bin/sh", args: ["-c", script, "sh", tmp_dir]},
        client_info: %{name: "c", version: "0"},
        request_timeout: 10_000
      )

    {result, _log} = with_log(fn -> Client.list_prompts(client, timeout: :infinity) end)
    GenServer.stop(client)
    assert {:error, %Error{code: -32_700, message: "Parse error"}} = result
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check answers a client with a 200 JSON null-id error; grepped the pinned dist (a10085d0): its 5 id:null sites are res.status(400/500).json or writeHead(400) bodies"
  test "H1 over real HTTP, a 200 JSON null-id error fails the one pending caller" do
    # A 200 application/json body reaches MCP.Client as it is: the transport ties
    # only 4xx/5xx bodies (MES-206). One body carries one message, so a dropped
    # reply fails at the 10 s request timeout; the pass path is immediate.
    port = serve("application/json", Jason.encode!(null_id_error()))

    {result, _log} =
      with_log(fn ->
        port
        |> http_client(request_timeout: 10_000)
        |> Client.list_prompts(timeout: :infinity)
      end)

    assert {:error, %Error{code: -32_700, message: "Parse error"}} = result
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check answers a client with an SSE null-id error; grepped the pinned dist (a10085d0): its 5 id:null sites are res.status(400/500).json or writeHead(400) bodies"
  test "H2 over real HTTP, a null-id error in a 200 SSE response fails the caller before the valid reply" do
    port =
      serve("text/event-stream", fn id ->
        "event: message\ndata: #{Jason.encode!(null_id_error())}\n\n" <>
          "event: message\ndata: #{Jason.encode!(ok_reply(id))}\n\n"
      end)

    {result, _log} =
      with_log(fn -> port |> http_client([]) |> Client.list_prompts(timeout: :infinity) end)

    assert {:error, %Error{code: -32_700, message: "Parse error"}} = result
  end

  defp start_client do
    {:ok, client} =
      Client.start_link(transport: {MockTransport, []}, client_info: %{name: "c", version: "0"})

    {client, Client.transport(client)}
  end

  defp http_client(port, opts) do
    {:ok, client} =
      Client.start_link(
        [
          transport: {MCP.Transport.StreamableHTTP.Client, url: "http://127.0.0.1:#{port}/"},
          client_info: %{name: "c", version: "0"}
        ] ++ opts
      )

    client
  end

  # A stub server on the suite's one binder (port 0, read back once bound;
  # MES-215). `body` is a binary, or a function of the id the client sent.
  defp serve(content_type, body) do
    respond = fn %{"id" => id} ->
      {200, [{"content-type", content_type}], if(is_function(body, 1), do: body.(id), else: body)}
    end

    {server, port} =
      MCP.Test.Listener.bandit!(
        plug: {MCP.Test.HTTPErrorStubPlug, test: self(), respond: respond},
        port: 0,
        ip: {127, 0, 0, 1},
        startup_log: false
      )

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :normal) end)
    port
  end

  defp null_id_error,
    do: %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32_700, "message" => "Parse error"}
    }

  defp ok_reply(id), do: %{"jsonrpc" => "2.0", "id" => id, "result" => %{"prompts" => []}}

  # Both injected messages have left the transport once it answers a call, and the
  # client has handled them once it answers one.
  defp settle(client, transport) do
    MockTransport.sent_messages(transport)
    Client.status(client)
  end
end

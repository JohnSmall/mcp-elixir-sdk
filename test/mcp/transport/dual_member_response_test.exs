defmodule MCP.Transport.DualMemberResponseTest do
  @moduledoc """
  MES-199 — a JSON-RPC response carrying both a `result` and an `error`
  member. JSON-RPC 2.0 §5: "Either the result member or error member MUST be
  included, but both members MUST NOT be included." Before MES-199
  `MCP.Protocol.decode_message/1` built a `%Response{}` holding both, and the
  Client let the error win: the caller got the server's error, the result
  vanished, and a `-32022` in that position even started the version retry.

  The decoder now refuses a `result` key beside a non-null `error` with
  -32600, before it looks at the error's shape, so a result beside a malformed
  error gets this rule too. Each caller already controls a refusal: the Plug
  answers 400 by the readable id, the Connection logs and drops it, and the
  Client fails the pending caller at once with `{:malformed_response, error}`
  (MES-197). `error: null` is still read as an absent member (MES-190 Q5), and
  an id with neither member is refused as before.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test
  import Plug.Conn

  alias MCP.{Client, Protocol}
  alias MCP.Protocol.Error
  alias MCP.Protocol.Messages.Response
  alias MCP.Server.Connection
  alias MCP.Test.{MockTransport, StatelessHandler}
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @rule "a JSON-RPC response must not carry both a result and an error member"

  @refused {:error, %Error{code: -32_600, message: "Invalid request", data: @rule}}

  @full %{
    "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  @error %{"code" => -1, "message" => "m"}

  # MES-190's eight malformed error members.
  @malformed [
    {"a string", "boom"},
    {"an empty object", %{}},
    {"code only", %{"code" => -1}},
    {"message only", %{"message" => "x"}},
    {"a list", [1]},
    {"a string code", %{"code" => "x", "message" => "m"}},
    {"a float code", %{"code" => -1.5, "message" => "m"}},
    {"a non-string message", %{"code" => -1, "message" => 5}}
  ]

  # One of each class whose outcome MES-199 changes: D1 with a map and with a
  # null result, and D2.
  @dual [
    {"a result and a well-formed error", %{"tools" => []}, @error},
    {"a null result and a well-formed error", nil, @error},
    {"a result and a malformed error", %{"tools" => []}, "boom"}
  ]

  defp dual(id, result, error),
    do: %{"jsonrpc" => "2.0", "id" => id, "result" => result, "error" => error}

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends or POSTs a JSON-RPC reply carrying both a result and an error member; searched the pinned dist (a10085d0)"
  test "T1 decode_message/1 refuses a response carrying both a result and an error member" do
    outcomes = [
      {"a result map", Protocol.decode_message(dual(1, %{}, @error))},
      {"a null result", Protocol.decode_message(dual(1, nil, @error))},
      {"with a method key too",
       Protocol.decode_message(Map.put(dual(1, %{}, @error), "method", "tools/list"))},
      {"the JSON text",
       Protocol.decode(~s({"jsonrpc":"2.0","id":1,"result":{},"error":{"code":-1,"message":"m"}}))}
    ]

    assert outcomes == [
             {"a result map", @refused},
             {"a null result", @refused},
             {"with a method key too", @refused},
             {"the JSON text", @refused}
           ]
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends or POSTs a JSON-RPC reply carrying both a result and an error member; searched the pinned dist (a10085d0)"
  test "T2 a result beside a malformed error gets the dual-member rule, not the error-shape rule" do
    outcomes =
      for {name, error} <- @malformed, do: {name, Protocol.decode_message(dual(1, %{}, error))}

    assert outcomes == for({name, _} <- @malformed, do: {name, @refused})
  end

  @tag oc: :none
  @tag oc_reason: "a control: no OC check sends a JSON-RPC message with an id and neither member"
  test "T3 CONTROL: an id with neither member is refused -32600, as today" do
    assert {:error, %Error{code: -32_600, message: "Invalid request", data: nil}} ==
             Protocol.decode_message(%{"jsonrpc" => "2.0", "id" => 1})
  end

  @tag oc: :none
  @tag oc_reason: "a control: no OC check sends a JSON-RPC reply with error null beside a result"
  test "T4 CONTROL: error null beside a result, and a result alone, still decode as a success" do
    success = {:ok, %Response{id: 1, result: %{}, error: nil}}

    assert Protocol.decode_message(dual(1, %{}, nil)) == success

    assert Protocol.decode_message(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}) ==
             success
  end

  @tag oc: :none
  @tag oc_reason: "the stdio limb: no OC scenario drives the stdio transport"
  test "T5 over stdio a dual-member reply is dropped with a logged refusal; the Connection lives and answers the next request" do
    Process.flag(:trap_exit, true)

    outcomes =
      for {name, result, error} <- @dual do
        {:ok, pid} =
          Connection.start_link(transport: {MockTransport, []}, handler: {StatelessHandler, []})

        transport = Connection.transport(pid)

        log =
          capture_log([level: :warning], fn ->
            MockTransport.inject(transport, dual(7, result, error))

            MockTransport.inject(transport, %{
              "jsonrpc" => "2.0",
              "id" => 8,
              "method" => "tools/list",
              "params" => %{"_meta" => @full}
            })

            MockTransport.await_sent(transport, 1)
          end)

        # Liveness and the reply are one element, the logged refusal another,
        # so a failure names which of the two it was.
        answered =
          case {Process.alive?(pid), sent(transport)} do
            {true, [%{"id" => 8, "result" => %{"tools" => _}}]} -> :only_the_reply
            other -> other
          end

        {name, {answered, log =~ "failed to decode message" and log =~ @rule}}
      end

    assert outcomes == for({name, _, _} <- @dual, do: {name, {:only_the_reply, true}})
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends or POSTs a JSON-RPC reply carrying both a result and an error member; searched the pinned dist (a10085d0)"
  test "T6 over HTTP a dual-member POST is answered 400 / -32600 by its id, with the rule as data" do
    outcomes = for {name, result, error} <- @dual, do: {name, post(dual(1, result, error))}

    expected = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "error" => %{"code" => -32_600, "message" => "Invalid request", "data" => @rule}
    }

    assert outcomes == for({name, _, _} <- @dual, do: {name, {400, expected}})
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends or POSTs a JSON-RPC reply carrying both a result and an error member; searched the pinned dist (a10085d0)"
  test "T7 the client fails the pending caller at once on a dual-member reply, and lives" do
    outcomes =
      for {name, result, error} <- @dual do
        {client, transport} = start_client()
        task = Task.async(fn -> Client.list_tools(client, timeout: :infinity) end)
        [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)

        # A valid reply for the same id follows, so a client that let either
        # member through answers with it or with the error: seen by order.
        reply =
          capture_and_return(fn ->
            MockTransport.inject(transport, dual(id, result, error))
            MockTransport.inject(transport, ok_reply(id))
            reply = Task.await(task, :infinity)
            settle(client, transport)
            reply
          end)

        {name, {reply, Process.alive?(client)}}
      end

    expected = {{:error, {:malformed_response, elem(@refused, 1)}}, true}
    assert outcomes == for({name, _, _} <- @dual, do: {name, expected})
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a JSON-RPC reply carrying both a result and a -32022 error; searched the pinned dist (a10085d0)"
  test "T8 a dual-member -32022 reply fails the caller and sends no version retry" do
    {client, transport} = start_client()
    task = Task.async(fn -> Client.list_tools(client, timeout: :infinity) end)
    [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)

    unsupported = %{
      "code" => -32_022,
      "message" => "Unsupported protocol version",
      "data" => %{"supported" => ["2026-07-28"], "requested" => "1999-01-01"}
    }

    {sent_ids, reply} =
      capture_and_return(fn ->
        MockTransport.inject(transport, dual(id, %{"tools" => []}, unsupported))
        MockTransport.inject(transport, ok_reply(id))
        settle(client, transport)

        # Whatever the client sent after the original is a retry; answering it
        # lets the caller finish either way, so no clock decides the outcome.
        sent_ids = Enum.map(MockTransport.sent_messages(transport), & &1["id"])
        for retry_id <- tl(sent_ids), do: MockTransport.inject(transport, ok_reply(retry_id))
        {sent_ids, Task.await(task, :infinity)}
      end)

    assert {sent_ids, reply} == {[id], {:error, {:malformed_response, elem(@refused, 1)}}}
  end

  @tag oc: :none
  @tag oc_reason:
         "a control: no OC check sends the client a JSON-RPC reply carrying both a result and an error member; searched the pinned dist (a10085d0)"
  test "T9 CONTROL: a dual-member reply for an id not pending gets no reply; the client lives and its caller is untouched" do
    {client, transport} = start_client()
    task = Task.async(fn -> Client.list_tools(client, timeout: :infinity) end)
    [%{"id" => id}] = MockTransport.wait_for_sent(transport, 1)

    reply =
      capture_and_return(fn ->
        MockTransport.inject(transport, dual(id + 100, %{"tools" => []}, @error))
        MockTransport.inject(transport, ok_reply(id))
        reply = Task.await(task, :infinity)
        settle(client, transport)
        reply
      end)

    assert {reply, Process.alive?(client), length(MockTransport.sent_messages(transport))} ==
             {{:ok, %{"tools" => []}}, true, 1}
  end

  defp start_client do
    {:ok, client} =
      Client.start_link(transport: {MockTransport, []}, client_info: %{name: "c", version: "0"})

    {client, Client.transport(client)}
  end

  defp ok_reply(id), do: %{"jsonrpc" => "2.0", "id" => id, "result" => %{"tools" => []}}

  # Both injected messages have left the transport once it answers a call, and the
  # client has handled them once it answers one.
  defp settle(client, transport) do
    MockTransport.sent_messages(transport)
    Client.status(client)
  end

  defp capture_and_return(fun) do
    {result, _log} = with_log(fun)
    result
  end

  defp post(message) do
    conn =
      :post
      |> conn("http://localhost/", Jason.encode!(message))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("origin", "http://localhost")
      |> MCPPlug.call(MCPPlug.init(server_mod: StatelessHandler, enable_json_response: true))

    {conn.status, Jason.decode!(conn.resp_body)}
  rescue
    e -> {:raised, e.__struct__}
  end

  defp sent(transport) do
    MockTransport.sent_messages(transport)
  catch
    :exit, _ -> :exited
  end
end

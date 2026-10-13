defmodule MCP.Transport.MalformedErrorMemberTest do
  @moduledoc """
  MES-190 — a JSON-RPC response whose `error` member is malformed. JSON-RPC 2.0
  §5 requires the member to be "an Object as defined in section 5.1", whose
  `code` "MUST be an integer" and whose `message` is "A String". Before MES-190
  `MCP.Protocol.decode_message/1` handed any such member to
  `MCP.Protocol.Error.from_map/1`, which has one clause: a member that is not
  an object with `code` and `message` raised `FunctionClauseError`, killing the
  stdio `MCP.Server.Connection`, giving an uncontrolled HTTP 500 and killing
  `MCP.Client`. One with the keys but the wrong types decoded into an
  `%Error{}` that breaks its own `@type`.

  The decoder now answers every malformed member with -32600, and each caller
  already controls that: the Plug answers 400 by the readable id (MES-168's
  refusal), and the Connection and the Client log and drop it. A dropped reply
  leaves a client caller to its request timeout (PM ruling MES-190 Q6).
  `error: null` is still read as an absent member (Q5).
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

  @full %{
    "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  # Five shapes `from_map/1` cannot match, then three with the keys but the
  # wrong types.
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

  defp response(id, error), do: %{"jsonrpc" => "2.0", "id" => id, "error" => error}

  defp decode_outcome(message) do
    case Protocol.decode_message(message) do
      {:error, %Error{code: code}} -> {:error, code}
      {:ok, decoded} -> {:ok, decoded.__struct__}
    end
  rescue
    e -> {:raised, e.__struct__}
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends a malformed JSON-RPC error member; searched the pinned dist (a10085d0)"
  test "decode_message/1 answers -32600 for every malformed error member and never raises" do
    outcomes = for {name, error} <- @malformed, do: {name, decode_outcome(response(1, error))}
    assert outcomes == for({name, _} <- @malformed, do: {name, {:error, -32_600}})
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends a malformed JSON-RPC error member; searched the pinned dist (a10085d0)"
  test "a JSON code of 1.0 decodes as a float and is malformed, not coerced to 1" do
    json = ~s({"jsonrpc":"2.0","id":1,"error":{"code":1.0,"message":"m"}})
    assert {:ok, %{"error" => %{"code" => code}}} = Jason.decode(json)
    assert is_float(code)
    assert {:error, %Error{code: -32_600}} = Protocol.decode(json)
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends a malformed JSON-RPC error member; searched the pinned dist (a10085d0)"
  test "a well-formed error member, and error null, decode exactly as before" do
    assert {:ok, %Response{id: 1, result: nil, error: error}} =
             Protocol.decode_message(
               response(1, %{"code" => -1, "message" => "m", "data" => [2]})
             )

    assert error == %Error{code: -1, message: "m", data: [2]}

    assert {:ok, %Response{error: %Error{code: -32_601, message: "x", data: nil}}} =
             Protocol.decode_message(response("a", %{"code" => -32_601, "message" => "x"}))

    assert {:ok, %Response{id: 1, result: nil, error: nil}} =
             Protocol.decode_message(response(1, nil))

    assert {:ok, %Response{result: %{}, error: nil}} =
             Protocol.decode_message(%{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{},
               "error" => nil
             })
  end

  @tag oc: :none
  @tag oc_reason: "the stdio limb: no OC scenario drives the stdio transport"
  test "over stdio each malformed member is dropped, the Connection lives and answers the next request" do
    Process.flag(:trap_exit, true)

    outcomes =
      for {name, error} <- @malformed do
        {:ok, pid} =
          Connection.start_link(transport: {MockTransport, []}, handler: {StatelessHandler, []})

        transport = Connection.transport(pid)

        capture_log(fn ->
          MockTransport.inject(transport, response(7, error))

          MockTransport.inject(transport, %{
            "jsonrpc" => "2.0",
            "id" => 8,
            "method" => "tools/list",
            "params" => %{"_meta" => @full}
          })

          wait_for(fn -> sent(transport) != [] end)
        end)

        # The request's reply is observed through the same capture, so an
        # empty capture (a dead Connection) cannot pass for "sent nothing".
        case {Process.alive?(pid), sent(transport)} do
          {true, [%{"id" => 8, "result" => %{"tools" => _}}]} -> {name, :only_the_reply}
          {alive?, sent} -> {name, {alive?, sent}}
        end
      end

    assert outcomes == for({name, _} <- @malformed, do: {name, :only_the_reply})
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check POSTs a malformed JSON-RPC error member; searched the pinned dist (a10085d0)"
  test "over HTTP each malformed member is answered 400 / -32600 with id 1" do
    outcomes = for {name, error} <- @malformed, do: {name, post(response(1, error))}

    expected = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "error" => %{"code" => -32_600, "message" => "Invalid request"}
    }

    assert outcomes == for({name, _} <- @malformed, do: {name, {400, expected}})
  end

  @tag oc: :none
  @tag oc_reason:
         "no OC check sends the client a malformed JSON-RPC error member; searched the pinned dist (a10085d0)"
  test "the client drops each malformed reply, lives, and its caller ends at the request timeout" do
    Process.flag(:trap_exit, true)

    outcomes =
      for {name, error} <- @malformed do
        {:ok, client} =
          Client.start_link(
            transport: {MockTransport, []},
            client_info: %{name: "c", version: "0"},
            request_timeout: 100
          )

        transport = Client.transport(client)

        {result, _log} = with_log(fn -> answer(client, transport, error) end)

        {name, {Process.alive?(client), result}}
      end

    assert outcomes == for({name, _} <- @malformed, do: {name, {true, {:error, :timeout}}})

    # The control: a well-formed error reply still reaches its caller.
    {:ok, client} =
      Client.start_link(transport: {MockTransport, []}, client_info: %{name: "c", version: "0"})

    assert {:error, %Error{code: -1, message: "m", data: nil}} =
             answer(client, Client.transport(client), %{"code" => -1, "message" => "m"})
  end

  defp answer(client, transport, error) do
    task =
      Task.async(fn ->
        try do
          Client.list_tools(client, timeout: 2_000)
        catch
          :exit, {{kind, _stack}, _call} -> {:caller_exit, kind}
          :exit, reason -> {:caller_exit, reason}
        end
      end)

    wait_for(fn -> MockTransport.sent_messages(transport) != [] end)
    %{"id" => id} = MockTransport.last_sent(transport)
    MockTransport.inject(transport, response(id, error))
    Task.await(task, 3_000)
  end

  defp post(message) do
    conn =
      :post
      |> conn("http://localhost/", Jason.encode!(message))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("origin", "http://localhost")
      |> MCPPlug.call(MCPPlug.init(server_mod: StatelessHandler, enable_json_response: true))

    # `data` carries the decoder's reason as text; the status, code, message
    # and id are the contract asserted.
    {conn.status, update_in(Jason.decode!(conn.resp_body), ["error"], &Map.delete(&1, "data"))}
  rescue
    e -> {:raised, e.__struct__}
  end

  defp sent(transport) do
    MockTransport.sent_messages(transport)
  catch
    :exit, _ -> :exited
  end

  defp wait_for(fun, tries \\ 100) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        :timeout

      true ->
        Process.sleep(10)
        wait_for(fun, tries - 1)
    end
  end
end

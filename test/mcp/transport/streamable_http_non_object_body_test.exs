defmodule MCP.Transport.StreamableHTTPNonObjectBodyTest do
  @moduledoc """
  MES-204: a 200 JSON body that is valid JSON but not an object, over real
  Streamable HTTP (Bandit on 127.0.0.1).

  Req decodes an `application/json` body before the transport sees it, so an
  array, a number, a boolean or `null` arrived as a list, a number, a boolean
  or `nil`. `deliver_json_response/2` had a clause for a map and one for a
  binary only, so the transport raised `FunctionClauseError`, and the linked
  `MCP.Client` died with every caller it held. A body Req leaves undecoded (an
  `application/json-seq` type, say) was decoded by the transport and delivered
  as `{:mcp_message, term}`; the client dropped it, having no id to tie it to,
  and the caller waited out its request timeout.

  Now both fail the sending caller at once with
  `{:transport_send_failed, {:non_object_json_body, term}}`, and the client
  serves the next request.

  The transport POSTs inside its own `handle_call/3`, so two requests on one
  client are never on the wire together. "Concurrent" here means at the API: B
  is called while A's POST is held open by the stub, and is queued at the
  client when A's answer arrives.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MCP.Test.HTTPErrorStubPlug
  alias MCP.Transport.StreamableHTTP.Client, as: HTTPClient

  describe "a 200 body that is not a JSON object fails only its own caller" do
    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "N1 an array" do
      assert_refused_at_once("application/json", "[]", [])
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "N2 an integer" do
      assert_refused_at_once("application/json", "1", 1)
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "N3 a float" do
      assert_refused_at_once("application/json", "1.5", 1.5)
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "N4 true" do
      assert_refused_at_once("application/json", "true", true)
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "N5 false" do
      assert_refused_at_once("application/json", "false", false)
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "N6 null" do
      assert_refused_at_once("application/json", "null", nil)
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "N7 an array under a JSON type Req leaves undecoded (the transport decodes it)" do
      assert_refused_at_once("application/json-seq", "[]", [])
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "N8 a 10k-element array is refused and its log line stays bounded" do
      items = for i <- 1..10_000, do: String.duplicate("x", 115) <> pad(i)
      body = Jason.encode!(items)

      log =
        capture_log([level: :warning], fn ->
          assert {:error, {:transport_send_failed, {:non_object_json_body, ^items}}} =
                   refused_call("application/json", body)
        end)

      assert [line] =
               log |> String.split("\n") |> Enum.filter(&(&1 =~ "JSON body is not an object"))

      # Bounded, the line names 20 items cut to 100 bytes each. Inspect's
      # defaults name several times as many items, whole, and overrun the bound.
      assert byte_size(line) <= 4_096, "log line is #{byte_size(line)} bytes"
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC client check answers a request with a non-object JSON body; searched the client-leg check ids in crosswalk-edges-client.json and grepped the pinned harness dist (sha256 a10085d0)"
    test "CONTROL C1 a JSON string body is still decoded again and refused as :json_decode_error" do
      capture_log(fn ->
        assert {:error, {:transport_send_failed, {:json_decode_error, %Jason.DecodeError{}}}} =
                 refused_call("application/json", ~s("s"))
      end)
    end
  end

  # --- Helpers ---

  # A (prompts/list) gets the forced body; B (tools/list) is called while A's
  # POST is held, and is answered normally once A has been.
  defp assert_refused_at_once(content_type, body, decoded) do
    capture_log(fn -> held_round(content_type, body, decoded) end)
  end

  defp held_round(content_type, body, decoded) do
    {client, transport, plug} = start_held(content_type, body)

    a = Task.async(fn -> call(fn -> MCP.Client.list_prompts(client) end) end)
    plug_pid = receive_holding(plug)

    b = Task.async(fn -> call(fn -> MCP.Client.list_tools(client) end) end)
    await_queued(client)
    send(plug_pid, :release)

    # 5 s against a 30 s request timeout: the refusal is at once, not a timeout.
    assert {:ok, {:error, {:transport_send_failed, {:non_object_json_body, ^decoded}}}} =
             Task.yield(a, 5_000) || Task.shutdown(a, :brutal_kill)

    assert {:ok, {:ok, %{"tools" => []}}} =
             Task.yield(b, 5_000) || Task.shutdown(b, :brutal_kill)

    assert Process.alive?(client)
    assert Process.alive?(transport)
    assert MCP.Client.transport(client) == transport
  end

  # One refused request, not held, for the cases that need no second caller.
  defp refused_call(content_type, body) do
    url = start_server(fn _message -> {200, [{"content-type", content_type}], body} end)
    {client, _transport} = start_client(url)
    call(fn -> MCP.Client.list_prompts(client) end)
  end

  defp start_held(content_type, body) do
    test = self()
    plug = make_ref()

    respond = fn
      %{"method" => "prompts/list"} ->
        send(test, {plug, :holding, self()})

        receive do
          :release -> {200, [{"content-type", content_type}], body}
        end

      %{"id" => id} ->
        reply = %{"jsonrpc" => "2.0", "id" => id, "result" => %{"tools" => []}}
        {200, [{"content-type", "application/json"}], Jason.encode!(reply)}
    end

    {client, transport} = start_client(start_server(respond))
    {client, transport, plug}
  end

  defp receive_holding(plug) do
    receive do
      {^plug, :holding, pid} -> pid
    after
      5_000 -> flunk("the stub never received A's POST")
    end
  end

  # B's call is in the client's mailbox while the client is blocked on A's POST.
  defp await_queued(client, tries \\ 500) do
    case Process.info(client, :message_queue_len) do
      {:message_queue_len, n} when n >= 1 ->
        :ok

      _ when tries > 0 ->
        receive after: (10 -> await_queued(client, tries - 1))

      _ ->
        flunk("B's call never reached the client")
    end
  end

  # A caller's exit is a result here, so that on the pre-fix tree a red reads as
  # the assertion it failed rather than as a crash of the test process.
  defp call(fun) do
    fun.()
  catch
    :exit, reason -> {:exit, reason}
  end

  defp start_server(respond) do
    {server, port} =
      MCP.Test.Listener.bandit!(
        plug: {HTTPErrorStubPlug, test: self(), respond: respond},
        port: 0,
        ip: {127, 0, 0, 1},
        startup_log: false
      )

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :normal) end)
    "http://127.0.0.1:#{port}/"
  end

  # Supervised, not linked: on the pre-fix tree the client dies, and the test
  # must survive to report why.
  defp start_client(url) do
    spec =
      Supervisor.child_spec(
        {MCP.Client, transport: {HTTPClient, url: url}, request_timeout: 30_000},
        restart: :temporary
      )

    client = start_supervised!(spec)
    {client, MCP.Client.transport(client)}
  end

  defp pad(i), do: i |> Integer.to_string() |> String.pad_leading(5, "0")
end

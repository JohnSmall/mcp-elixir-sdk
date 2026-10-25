defmodule MCP.Transport.StdioInvalidLineTest do
  @moduledoc """
  MES-210 — a stdio server answers a line it cannot serve. JSON-RPC 2.0 §5: a
  message that is not JSON gets -32700 Parse error, and JSON that is not a
  request object gets -32600 Invalid request, each with a `null` id when no id
  can be read. Before MES-210 the stdio server logged both and sent nothing.

  -32700 comes from the stdio transport's server path, the only place the bytes
  are seen; -32600 from `MCP.Server.Connection`, where the decoded term is
  classified. An object's readable id (a string or a number) is echoed, as the
  Plug does (MES-157). A malformed *response* is still dropped and logged
  (MES-199, MES-190): a server answers no reply.

  S1 and S2 run the SDK's own server in a subprocess, started under `env -i`
  so it inherits no credential, and read its stdout byte for byte. C1 and C2
  drive the Connection in-process.
  """
  use ExUnit.Case, async: false

  alias MCP.Server.Connection
  alias MCP.Test.{MockTransport, StatelessHandler}

  @server Path.expand("../../support/stdio_server.exs", __DIR__)
  @project_dir Path.expand("../../..", __DIR__)

  @version "2026-07-28"
  @full %{
    "io.modelcontextprotocol/protocolVersion" => @version,
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  @not_json "the line is not valid JSON"
  @not_object "the message must be a single JSON-RPC request or notification object"
  @no_member "a JSON-RPC message must carry a method, or a result or an error"
  @bad_version "Missing or invalid jsonrpc version"
  @dual "a JSON-RPC response must not carry both a result and an error member"
  @error_shape "a JSON-RPC error member must be an object with an integer code and a string message"

  # Bounded for a loaded host: the subprocess compiles nothing, but `mix run`
  # still boots a VM. Each read returns at the first line that arrives; the
  # per-test bound sits above it, so a slow boot fails as a timeout row.
  @line_timeout 90_000
  @moduletag timeout: 180_000

  defp list_request(id),
    do: %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "tools/list",
      "params" => %{"_meta" => @full}
    }

  defp parse_error,
    do: %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32_700, "message" => "Parse error", "data" => @not_json}
    }

  defp invalid(id, data),
    do: %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => -32_600, "message" => "Invalid request", "data" => data}
    }

  # --- The subprocess: the SDK as a stdio server, under env -i ---

  defp start_server do
    env =
      ["HOME", "MIX_HOME", "HEX_HOME", "PATH", "LANG"]
      |> Enum.flat_map(fn name ->
        case System.get_env(name) do
          nil -> []
          value -> ["#{name}=#{value}"]
        end
      end)

    args =
      ["-i"] ++
        env ++
        [
          "MIX_ENV=test",
          "MIX_BUILD_PATH=#{Path.join(@project_dir, "_build/test")}",
          System.find_executable("mix"),
          "run",
          "--no-start",
          @server
        ]

    Port.open({:spawn_executable, System.find_executable("env")}, [
      :binary,
      :exit_status,
      :use_stdio,
      {:line, 1_000_000},
      {:cd, @project_dir},
      {:args, args}
    ])
  end

  # Every stdout line up to and including the reply carrying `last_id`, or up
  # to the subprocess's exit: whatever arrived, so a failure shows it.
  defp read_until(port, last_id, acc \\ []) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        acc = [line | acc]

        case Jason.decode(line) do
          {:ok, %{"id" => ^last_id, "result" => _}} -> Enum.reverse(acc)
          _ -> read_until(port, last_id, acc)
        end

      {^port, {:data, {:noeol, line}}} ->
        read_until(port, last_id, [{:noeol, line} | acc])

      {^port, {:exit_status, status}} ->
        Enum.reverse([{:exit_status, status} | acc])
    after
      @line_timeout -> Enum.reverse([:timeout | acc])
    end
  end

  defp exchange(lines, last_id) do
    port = start_server()

    try do
      Port.command(port, Enum.map(lines, &[&1, "\n"]))
      got = read_until(port, last_id)
      refute_received {^port, {:exit_status, _}}
      got
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp decoded(lines), do: Enum.map(lines, &decode_line/1)

  defp decode_line(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, map} -> map
      {:error, _} -> {:not_json, line}
    end
  end

  defp decode_line(other), do: other

  # Every line before the last, decoded, and what the last one was: the reply
  # to the closing request, or whatever arrived instead (an exit, a timeout).
  defp outcome(got) do
    [last | before] = got |> decoded() |> Enum.reverse()
    {Enum.reverse(before), answered(last)}
  end

  defp answered(%{"id" => 9, "result" => %{"tools" => _}}), do: :answered
  defp answered(other), do: other

  @tag oc: :none
  @tag oc_reason: "the stdio limb: no OC scenario drives the stdio transport"
  test "S1 over a real pipe each unparseable line gets one -32700 line with a null id, and the server answers the next request" do
    unparseable = [
      "not json",
      ~s({"jsonrpc":"2.0","id":1,),
      "   ",
      <<0xFF, 0xFE, " bad">>,
      "{} x",
      "{}{}"
    ]

    # A lone "\r" is sent first and answered by nothing: the io server reads
    # "\r\n" as a line end, so it arrives empty and the reader drops it, as it
    # drops every empty line (MES-210 census, measured at build).
    got = exchange(["\r" | unparseable] ++ [Jason.encode!(list_request(9))], 9)

    expected = List.duplicate(parse_error(), length(unparseable))

    assert outcome(got) == {expected, :answered}
  end

  @tag oc: :none
  @tag oc_reason: "the stdio limb: no OC scenario drives the stdio transport"
  test "S2 over a real pipe each invalid JSON line gets one -32600 line, by its readable id or null, and the server answers the next request" do
    rows = [
      {"[1,2]", invalid(nil, @not_object)},
      {"[]", invalid(nil, @not_object)},
      {"42", invalid(nil, @not_object)},
      {~s("s"), invalid(nil, @not_object)},
      {"null", invalid(nil, @not_object)},
      {~s({"id":3,"method":"tools/list"}), invalid(3, @bad_version)},
      {~s({"jsonrpc":"2.0"}), invalid(nil, @no_member)},
      {~s({"jsonrpc":"2.0","id":4}), invalid(4, @no_member)},
      # A method beside a result or an error is not a reply: it is refused, not
      # dropped (MES-210 r1, CR F1).
      {~s({"jsonrpc":"1.0","id":77,"method":"x","result":{}}), invalid(77, @bad_version)},
      {~s({"jsonrpc":"2.0","id":78,"method":"x","result":{},"error":{"code":1,"message":"m"}}),
       invalid(78, @dual)},
      {~s({"jsonrpc":"2.0","id":79,"method":"x","error":"boom"}), invalid(79, @error_shape)}
    ]

    got = exchange(Enum.map(rows, &elem(&1, 0)) ++ [Jason.encode!(list_request(9))], 9)

    assert outcome(got) == {Enum.map(rows, &elem(&1, 1)), :answered}
  end

  # --- In-process: the Connection's refusal, row by row ---

  defp connection_outcome(message) do
    {:ok, pid} =
      Connection.start_link(transport: {MockTransport, []}, handler: {StatelessHandler, []})

    transport = Connection.transport(pid)
    MockTransport.inject(transport, message)
    MockTransport.inject(transport, list_request(8))

    # The reply to id 8 is always sent, and it is sent after whatever the
    # injected message produced, so waiting for it bounds the whole exchange.
    sent = await_reply(transport, 8)

    {Process.alive?(pid), sent}
  end

  defp await_reply(transport, id, count \\ 1) do
    case MockTransport.await_sent(transport, count) do
      {:ok, sent} ->
        if Enum.any?(sent, &match?(%{"id" => ^id, "result" => _}, &1)),
          do: sent,
          else: await_reply(transport, id, count + 1)

      other ->
        other
    end
  end

  @tag oc: :none
  @tag oc_reason:
         "the in-process limb of a stdio refusal: no OC scenario drives an owner-based transport"
  test "C1 the Connection answers each invalid message with one -32600, by its readable id or null, and stays up" do
    rows = [
      {[1, 2], invalid(nil, @not_object)},
      {[], invalid(nil, @not_object)},
      {42, invalid(nil, @not_object)},
      {"s", invalid(nil, @not_object)},
      {true, invalid(nil, @not_object)},
      {nil, invalid(nil, @not_object)},
      {%{"id" => 3, "method" => "tools/list"}, invalid(3, @bad_version)},
      {%{"jsonrpc" => "1.0", "id" => "a", "method" => "x"}, invalid("a", @bad_version)},
      {%{"jsonrpc" => 2.0, "method" => "x"}, invalid(nil, @bad_version)},
      {%{"jsonrpc" => "1.0", "id" => %{}, "method" => "x"}, invalid(nil, @bad_version)},
      {%{"jsonrpc" => "2.0"}, invalid(nil, @no_member)},
      {%{"jsonrpc" => "2.0", "id" => 4}, invalid(4, @no_member)},
      {%{"jsonrpc" => "2.0", "id" => nil}, invalid(nil, @no_member)},
      # A method beside a result or an error is not a reply: it is refused, not
      # dropped (MES-210 r1, CR F1).
      {%{"jsonrpc" => "1.0", "id" => 77, "method" => "x", "result" => %{}},
       invalid(77, @bad_version)},
      {%{
         "jsonrpc" => "2.0",
         "id" => 78,
         "method" => "x",
         "result" => %{},
         "error" => %{"code" => 1, "message" => "m"}
       }, invalid(78, @dual)},
      {%{"jsonrpc" => "2.0", "id" => 79, "method" => "x", "error" => "boom"},
       invalid(79, @error_shape)}
    ]

    outcomes =
      for {message, error} <- rows do
        case connection_outcome(message) do
          {true, [^error, %{"id" => 8, "result" => %{"tools" => _}}]} -> {message, :refused}
          other -> {message, other}
        end
      end

    assert outcomes == for({message, _} <- rows, do: {message, :refused})
  end

  @tag oc: :none
  @tag oc_reason: "a control: no OC scenario sends a JSON-RPC reply to a server"
  test "C2 CONTROL: a reply, malformed or not, is dropped and only the next request is answered" do
    rows = [
      %{"jsonrpc" => "2.0", "id" => 7, "result" => %{}},
      %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "result" => %{},
        "error" => %{"code" => 1, "message" => "x"}
      },
      %{"jsonrpc" => "2.0", "id" => 7, "error" => %{"code" => "1", "message" => "x"}},
      %{"jsonrpc" => "2.0", "id" => 7, "error" => "boom"},
      %{"jsonrpc" => "1.0", "id" => 7, "result" => %{}},
      %{"id" => 7, "error" => %{"code" => 1, "message" => "x"}}
    ]

    outcomes =
      for message <- rows do
        case connection_outcome(message) do
          {true, [%{"id" => 8, "result" => %{"tools" => _}}]} -> {message, :dropped}
          other -> {message, other}
        end
      end

    assert outcomes == for(message <- rows, do: {message, :dropped})
  end
end

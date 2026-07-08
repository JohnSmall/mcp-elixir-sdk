defmodule MCP.Transport.StreamableHTTPHandlerOptsTest do
  @moduledoc """
  MES-3 — the `handler_opts` request-identity seam on
  `MCP.Transport.StreamableHTTP.Plug`.

  Covers the Reviewer's 8-case matrix (1:1 mapping in the test names):

    1. Default parity (`[]` and omitted behave as before).
    2. Factory evaluated exactly once at `initialize`.
    3. Identity bound at init is reused across later same-session requests.
    4. Static form reaches `Handler.init/1`.
    5. Factory-wins precedence (documented `Keyword.merge` contract + base-composing factory).
    6. Direct `MCP.Server.start_link(handler: {mod, opts})` path unchanged.
    7. PreStarted carries static handler opts only (no conn / no factory).
    8. Factory raises / returns a non-keyword → HTTP 500 / -32603, no session started.
  """
  use ExUnit.Case, async: false

  import Plug.Test
  import ExUnit.CaptureLog

  alias MCP.Transport.StreamableHTTP
  alias MCP.Transport.StreamableHTTP.Server, as: HTTPTransport

  # --- Test handler: records the opts it was initialised with ---

  defmodule RecordingHandler do
    @behaviour MCP.Server.Handler

    @impl true
    def init(opts) do
      if pid = Keyword.get(opts, :test_pid), do: send(pid, {:handler_init, opts})
      {:ok, %{opts: opts}}
    end

    @impl true
    def handle_list_tools(_cursor, state) do
      tools = [
        %{
          "name" => "whoami",
          "description" => "Returns the identity bound into handler state",
          "inputSchema" => %{"type" => "object", "properties" => %{}}
        }
      ]

      {:ok, tools, nil, state}
    end

    @impl true
    def handle_call_tool("whoami", _args, state) do
      identity = state.opts |> Keyword.get(:identity) |> inspect()
      {:ok, [%{"type" => "text", "text" => identity}], state}
    end

    def handle_call_tool(name, _args, state) do
      {:error, -32_602, "Unknown tool: #{name}", state}
    end
  end

  # --- Helpers ---

  defp find_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # `handler_opts` — pass `:omit` to leave the option out entirely.
  defp start_server(handler_opts) do
    port = find_free_port()

    base = [
      server_mod: RecordingHandler,
      server_opts: [server_info: %{name: "ho-test", version: "1.0.0"}],
      enable_json_response: true,
      session_id_generator: fn -> UUID.uuid4() end
    ]

    opts =
      if handler_opts == :omit,
        do: base,
        else: Keyword.put(base, :handler_opts, handler_opts)

    plug_opts = StreamableHTTP.Plug.init(opts)

    {:ok, bandit} =
      Bandit.start_link(
        plug: {StreamableHTTP.Plug, plug_opts},
        port: port,
        ip: {127, 0, 0, 1}
      )

    {"http://127.0.0.1:#{port}", bandit}
  end

  defp start_client(url) do
    {:ok, client} =
      MCP.Client.start_link(
        transport: {StreamableHTTP.Client, url: url},
        client_info: %{name: "ho-client", version: "1.0.0"}
      )

    client
  end

  defp initialize_conn do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-11-25",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "raw", "version" => "1.0"}
        }
      })

    :post
    |> conn("http://localhost/", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
  end

  # --- Case 1: default parity ---

  describe "case 1 — default parity" do
    test "omitted handler_opts behaves exactly as today" do
      {url, _bandit} = start_server(:omit)
      client = start_client(url)

      assert {:ok, _} = MCP.Client.connect(client)
      assert {:ok, tools} = MCP.Client.list_tools(client)
      assert Enum.any?(tools["tools"], &(&1["name"] == "whoami"))

      MCP.Client.close(client)
    end

    test "handler_opts: [] behaves exactly as today" do
      {url, _bandit} = start_server([])
      client = start_client(url)

      assert {:ok, _} = MCP.Client.connect(client)
      assert {:ok, _} = MCP.Client.list_tools(client)

      MCP.Client.close(client)
    end
  end

  # --- Case 2: factory evaluated exactly once ---

  test "case 2 — factory is evaluated exactly once, at initialize" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    factory = fn _conn ->
      Agent.update(counter, &(&1 + 1))
      [identity: :bob]
    end

    {url, _bandit} = start_server(factory)
    client = start_client(url)

    assert {:ok, _} = MCP.Client.connect(client)
    assert {:ok, _} = MCP.Client.call_tool(client, "whoami", %{})
    assert {:ok, _} = MCP.Client.call_tool(client, "whoami", %{})
    assert {:ok, _} = MCP.Client.list_tools(client)

    assert Agent.get(counter, & &1) == 1

    MCP.Client.close(client)
  end

  # --- Case 3: identity reused across later same-session requests ---

  test "case 3 — identity bound at init is reused across later same-session requests" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    # Returns a *different* value each time it runs — so a stable result across
    # requests proves the factory ran once and the identity was reused.
    factory = fn _conn ->
      n = Agent.get_and_update(counter, fn c -> {c + 1, c + 1} end)
      [identity: {:call, n}]
    end

    {url, _bandit} = start_server(factory)
    client = start_client(url)

    assert {:ok, _} = MCP.Client.connect(client)
    assert {:ok, r1} = MCP.Client.call_tool(client, "whoami", %{})
    assert {:ok, r2} = MCP.Client.call_tool(client, "whoami", %{})

    assert hd(r1["content"])["text"] == "{:call, 1}"
    assert hd(r2["content"])["text"] == "{:call, 1}"
    assert Agent.get(counter, & &1) == 1

    MCP.Client.close(client)
  end

  # --- Case 4: static form reaches Handler.init/1 ---

  test "case 4 — static handler_opts reaches Handler.init/1" do
    test_pid = self()
    {url, _bandit} = start_server(identity: :alice, test_pid: test_pid)
    client = start_client(url)

    assert {:ok, _} = MCP.Client.connect(client)
    assert_receive {:handler_init, opts}, 2_000
    assert Keyword.get(opts, :identity) == :alice

    assert {:ok, res} = MCP.Client.call_tool(client, "whoami", %{})
    assert hd(res["content"])["text"] == ":alice"

    MCP.Client.close(client)
  end

  # --- Case 5: factory-wins precedence ---

  test "case 5 — factory-wins precedence (documented merge contract + base-composing factory)" do
    # (a) The documented precedence contract: on key conflict, the factory
    # (overlay) wins; unrelated base keys survive.
    base = [region: "eu", identity: :default]
    merged = Keyword.merge(base, identity: :alice)
    assert Keyword.get(merged, :identity) == :alice
    assert Keyword.get(merged, :region) == "eu"

    # (b) A factory that composes a base internally: request-derived key wins,
    # base key preserved — as observed at Handler.init/1.
    test_pid = self()

    factory = fn _conn ->
      Keyword.merge([region: "eu", identity: :default, test_pid: test_pid], identity: :alice)
    end

    {url, _bandit} = start_server(factory)
    client = start_client(url)

    assert {:ok, _} = MCP.Client.connect(client)
    assert_receive {:handler_init, opts}, 2_000
    assert Keyword.get(opts, :identity) == :alice
    assert Keyword.get(opts, :region) == "eu"

    MCP.Client.close(client)
  end

  # --- Case 6: direct MCP.Server.start_link path unchanged ---

  test "case 6 — direct MCP.Server.start_link(handler: {mod, opts}) forwards opts unchanged" do
    test_pid = self()
    {:ok, transport_pid} = HTTPTransport.start_link(owner: self(), session_id: "s6")

    {:ok, server} =
      MCP.Server.start_link(
        handler: {RecordingHandler, [identity: :carol, test_pid: test_pid]},
        transport: {StreamableHTTP.PreStarted, pid: transport_pid}
      )

    assert_receive {:handler_init, opts}, 2_000
    assert Keyword.get(opts, :identity) == :carol

    MCP.Server.close(server)
  end

  # --- Case 7: PreStarted carries static opts only ---

  test "case 7 — PreStarted carries static handler opts only (no conn / no factory at this layer)" do
    test_pid = self()
    {:ok, transport_pid} = HTTPTransport.start_link(owner: self(), session_id: "s7")

    # No conn exists at the PreStarted layer; the Plug resolves any factory
    # upstream, so only a static keyword ever reaches here.
    {:ok, server} =
      MCP.Server.start_link(
        handler: {RecordingHandler, [region: "us", test_pid: test_pid]},
        transport: {StreamableHTTP.PreStarted, pid: transport_pid}
      )

    assert_receive {:handler_init, opts}, 2_000
    assert Keyword.get(opts, :region) == "us"

    MCP.Server.close(server)
  end

  # --- Case 8: factory error handling ---

  describe "case 8 — factory error handling" do
    test "a factory that raises → HTTP 500 / -32603, no session started, non-leaking data" do
      config =
        StreamableHTTP.Plug.init(
          server_mod: RecordingHandler,
          handler_opts: fn _conn -> raise "boom secret token=abc123" end,
          enable_json_response: true,
          session_id_generator: fn -> "fixed" end
        )

      {conn, log} = with_log(fn -> StreamableHTTP.Plug.call(initialize_conn(), config) end)

      assert conn.status == 500

      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == -32_603
      assert body["error"]["message"] == "Internal error"
      # Non-leaking: the controlled message reaches the client, not the raised
      # reason — while the full detail is logged server-side.
      assert body["error"]["data"] == "handler_opts factory error"
      refute conn.resp_body =~ "abc123"
      assert log =~ "handler_opts factory failed"

      # Nothing orphaned: no session row was inserted.
      assert :ets.tab2list(config.sessions) == []
    end

    test "a factory that returns a non-keyword → HTTP 500 / -32603, no session started" do
      config =
        StreamableHTTP.Plug.init(
          server_mod: RecordingHandler,
          handler_opts: fn _conn -> %{not: "a keyword"} end,
          enable_json_response: true,
          session_id_generator: fn -> "fixed" end
        )

      {conn, _log} = with_log(fn -> StreamableHTTP.Plug.call(initialize_conn(), config) end)

      assert conn.status == 500
      assert Jason.decode!(conn.resp_body)["error"]["code"] == -32_603
      assert :ets.tab2list(config.sessions) == []
    end

    test "static non-keyword / bad handler_opts fails fast at Plug.init/1 (ArgumentError)" do
      assert_raise ArgumentError, ~r/handler_opts must be a keyword list/, fn ->
        StreamableHTTP.Plug.init(server_mod: RecordingHandler, handler_opts: [1, 2, 3])
      end

      assert_raise ArgumentError, ~r/handler_opts must be a keyword list/, fn ->
        StreamableHTTP.Plug.init(server_mod: RecordingHandler, handler_opts: "nope")
      end
    end
  end
end

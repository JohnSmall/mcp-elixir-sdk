defmodule MCP.Transport.SelfCompatibilityTest do
  @moduledoc """
  MES-18 / W2 — this SDK's own client talking to this SDK's own server, over a
  tool name that is not header-safe.

  ## Why this exists

  Before this ticket the two halves disagreed about whether a feature existed:
  the server validated `Mcp-Name` (`plug.ex:874-883`) and the client never sent
  it, so the server's comparison was dead code. CG1 brings it to life — and the
  spec requires the client to **encode** a non-header-safe name
  (`streamable-http.mdx:486-492`) and the server to **decode** before comparing
  (`:501-504`). Our server compared raw. Shipping CG1 without W2 would have
  made our own conformant client be refused by our own server with `-32020`,
  deterministically, on any non-ASCII tool or prompt name or resource URI.

  ## Evidence posture (A7)

  The first test is the one **discriminating** case in this file: it fails at
  the moment CG1 lands without W2 (`-32020 Header mismatch` instead of a
  result), which is exactly the regression W2 exists to prevent. It is a
  regression against an intermediate state rather than against `2829769`,
  where the client sent no header at all and the case was unreachable — so it
  is labelled as a **reachability control**, not as a caught regression on
  `main`.

  The `-32020` negative controls below are what stop W2 from degenerating into
  "stop comparing": a genuinely mismatched header must still be rejected.
  """
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias MCP.Protocol.HeaderMirror
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @meta %{"io.modelcontextprotocol/protocolVersion" => @version}

  defmodule Handler do
    @moduledoc false
    @behaviour MCP.Server.Handler

    # A tool whose name is legitimate but NOT header-safe. Tool names are only
    # SHOULD-constrained to header-safe characters (`streamable-http.mdx:486`),
    # so this server is conformant and the client must cope.
    @tool_name "天気_get"

    def tool_name, do: @tool_name

    @impl true
    def init(_opts), do: {:ok, %{}}

    @impl true
    def handle_list_tools(_cursor, _ctx, state) do
      {:ok, [%{"name" => @tool_name, "inputSchema" => %{"type" => "object"}}], nil, state}
    end

    @impl true
    def handle_call_tool(@tool_name, _args, _ctx, state) do
      {:ok, [%{"type" => "text", "text" => "sunny"}], state}
    end

    def handle_call_tool(_name, _args, _ctx, state) do
      {:ok, [%{"type" => "text", "text" => "unknown tool"}], true, state}
    end
  end

  defp opts, do: MCPPlug.init(server_mod: Handler, enable_json_response: true)

  defp post(message, headers) do
    base =
      :post
      |> conn("http://localhost/", Jason.encode!(message))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("origin", "http://localhost")

    headers
    |> Enum.reduce(base, fn {k, v}, c -> put_req_header(c, k, v) end)
    |> MCPPlug.call(opts())
  end

  defp call_tool_message(name) do
    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => name, "_meta" => @meta}
    }
  end

  defp body(conn), do: Jason.decode!(conn.resp_body)

  test "REACHABILITY CONTROL: an encoded Mcp-Name is decoded before comparison, so our own client is not self-rejected" do
    name = Handler.tool_name()
    # Exactly what the client now puts on the wire for this name.
    header = HeaderMirror.encode_value(name)
    assert String.starts_with?(header, "=?base64?")

    conn =
      post(call_tool_message(name), [
        {"mcp-method", "tools/call"},
        {"mcp-name", header},
        {"mcp-protocol-version", @version}
      ])

    assert conn.status == 200
    refute Map.has_key?(body(conn), "error")
    assert %{"content" => [%{"text" => "sunny"}]} = body(conn)["result"]
  end

  test "NEGATIVE CONTROL: an encoded header naming a DIFFERENT tool is still -32020" do
    # W2 must not become "stop comparing". This encodes a name the body does
    # not carry; decoding is what makes the mismatch visible.
    conn =
      post(call_tool_message(Handler.tool_name()), [
        {"mcp-method", "tools/call"},
        {"mcp-name", HeaderMirror.encode_value("другой_инструмент")},
        {"mcp-protocol-version", @version}
      ])

    assert conn.status == 400
    assert body(conn)["error"]["code"] == -32_020
  end

  test "NEGATIVE CONTROL: a PLAIN mismatched header is still -32020" do
    conn =
      post(call_tool_message("weather"), [
        {"mcp-method", "tools/call"},
        {"mcp-name", "not_weather"},
        {"mcp-protocol-version", @version}
      ])

    assert conn.status == 400
    assert body(conn)["error"]["code"] == -32_020
  end

  test "a plain header matching a plain name still passes — decoding leaves it alone" do
    conn =
      post(call_tool_message("unknown_but_matching"), [
        {"mcp-method", "tools/call"},
        {"mcp-name", "unknown_but_matching"},
        {"mcp-protocol-version", @version}
      ])

    # The routing check passed (no -32020); the handler's own "unknown tool"
    # answer is what comes back, which is the point: the header stopped being
    # the thing that failed.
    assert conn.status == 200
    refute body(conn)["error"]["code"] == -32_020
  end

  test "a sentinel-shaped header that is not valid Base64 is compared as-is, not crashed on" do
    conn =
      post(call_tool_message("weather"), [
        {"mcp-method", "tools/call"},
        {"mcp-name", "=?base64?!!!not-base64!!!?="},
        {"mcp-protocol-version", @version}
      ])

    assert conn.status == 400
    assert body(conn)["error"]["code"] == -32_020
  end

  test "END TO END: our client calls our server's non-header-safe tool over real HTTP" do
    # The whole loop — client encodes, server decodes, tool runs. This is the
    # test that would have caught the self-incompatibility as a shipped bug.
    port = free_port()

    {:ok, server} =
      Bandit.start_link(
        plug: {MCPPlug, opts()},
        port: port,
        ip: {127, 0, 0, 1},
        startup_log: false
      )

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :normal) end)

    {:ok, client} =
      MCP.Client.start_link(
        transport:
          {MCP.Transport.StreamableHTTP.Client,
           url: "http://127.0.0.1:#{port}/", headers: [{"origin", "http://localhost"}]}
      )

    assert {:ok, %{"tools" => [%{"name" => name}]}} = MCP.Client.list_tools(client)
    assert name == Handler.tool_name()

    assert {:ok, %{"content" => [%{"text" => "sunny"}]}} = MCP.Client.call_tool(client, name)
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end

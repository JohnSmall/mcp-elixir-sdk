defmodule MCP.Transport.RequestBodyLimitTest do
  @moduledoc """
  MES-169 — a POST body longer than the Plug's read limit is refused HTTP 413
  (RFC 9110 §15.5.14) with a JSON-RPC -32600 whose `id` is `null`: nothing past
  the limit was read, so no id is readable (basic/index.mdx:103). Before
  MES-169 `Plug.Conn.read_body/2`'s `{:more, partial, conn}` matched no clause
  of `handle_post/2`'s `with`: a `WithClauseError` and a bare 500 with no body.
  The limit is `:max_body_length`, default 8_000_000 (Plug's own default).
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MCP.Test.StatelessHandler
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @version "2026-07-28"
  @default_limit 8_000_000

  # A tools/list request padded to exactly `size` bytes, so the boundary is the
  # byte count of the body and nothing else.
  defp body_of(size, id \\ 1) do
    envelope = fn pad ->
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => "tools/list",
        "params" => %{
          "_meta" => %{
            "io.modelcontextprotocol/protocolVersion" => @version,
            "io.modelcontextprotocol/clientCapabilities" => %{}
          },
          "pad" => pad
        }
      })
    end

    body = envelope.(String.duplicate("a", size - byte_size(envelope.(""))))
    ^size = byte_size(body)
    body
  end

  defp post(size, opts) do
    :post
    |> conn("http://localhost/", body_of(size))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> put_req_header("origin", "http://localhost")
    |> put_req_header("mcp-protocol-version", @version)
    |> put_req_header("mcp-method", "tools/list")
    |> MCPPlug.call(MCPPlug.init([server_mod: StatelessHandler] ++ opts))
  end

  defp accepted!(conn) do
    assert conn.status == 200
    assert get_resp_header(conn, "connection") == []
    assert %{"id" => 1, "result" => %{"tools" => [_ | _]}} = Jason.decode!(conn.resp_body)
  end

  defp too_large!(conn, limit) do
    assert conn.status == 413
    assert ["application/json" <> _] = get_resp_header(conn, "content-type")
    assert get_resp_header(conn, "connection") == []

    assert %{"jsonrpc" => "2.0", "id" => nil, "error" => error} = Jason.decode!(conn.resp_body)
    assert error["code"] == -32_600
    assert error["data"] == "request body exceeds #{limit} bytes"
  end

  describe "the default limit (8_000_000 bytes)" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a body near any size limit; searched the pinned dist (a10085d0) for one"
    test "a body exactly at the limit is read and dispatched" do
      accepted!(post(@default_limit, enable_json_response: true))
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a body near any size limit; searched the pinned dist (a10085d0) for one"
    test "one byte over → 413 / -32600, id null; not a WithClauseError" do
      too_large!(post(@default_limit + 1, enable_json_response: true), @default_limit)
    end
  end

  describe "a configured :max_body_length" do
    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a body near any size limit; searched the pinned dist (a10085d0) for one"
    test "a body exactly at a lower limit is accepted" do
      accepted!(post(1024, enable_json_response: true, max_body_length: 1024))
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a body near any size limit; searched the pinned dist (a10085d0) for one"
    test "one byte over a lower limit → 413 / -32600 naming that limit" do
      too_large!(post(1025, enable_json_response: true, max_body_length: 1024), 1024)
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a body near any size limit; searched the pinned dist (a10085d0) for one"
    test "in SSE mode the refusal is still a JSON 413, not a stream" do
      too_large!(post(1025, max_body_length: 1024), 1024)
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a body near any size limit; searched the pinned dist (a10085d0) for one"
    test "a limit that is not a positive integer is refused at init" do
      for bad <- [0, -1, 1.5, "1024", nil] do
        assert_raise ArgumentError, ~r/:max_body_length must be a positive integer/, fn ->
          MCPPlug.init(server_mod: StatelessHandler, max_body_length: bad)
        end
      end
    end
  end

  describe "over a real HTTP/1.1 socket (Bandit)" do
    setup do
      plug =
        MCPPlug.new(
          server_mod: StatelessHandler,
          enable_json_response: true,
          max_body_length: 1024
        )

      server = start_supervised!({Bandit, plug: plug, port: 0, ip: :loopback, startup_log: false})
      {:ok, {_, port}} = ThousandIsland.listener_info(server)
      %{port: port}
    end

    # The timeout below bounds a failure; no assertion passes on one. Keep-alive
    # is shown by a second response on the same socket (MES-169 A1).
    @bound 5_000

    defp connect(port) do
      {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      on_exit(fn -> :gen_tcp.close(sock) end)
      sock
    end

    defp send_post(sock, body) do
      head =
        "POST / HTTP/1.1\r\nhost: localhost\r\norigin: http://localhost\r\n" <>
          "content-type: application/json\r\naccept: application/json\r\n" <>
          "mcp-protocol-version: #{@version}\r\nmcp-method: tools/list\r\n" <>
          "content-length: #{byte_size(body)}\r\n\r\n"

      :ok = :gen_tcp.send(sock, [head, body])
    end

    # One whole response, framed by its content-length: {head, decoded body}.
    defp read_response(sock, acc \\ "") do
      with [head, rest] <- String.split(acc, "\r\n\r\n", parts: 2),
           [_, length] <- Regex.run(~r/\r\ncontent-length: (\d+)\r\n/i, head <> "\r\n"),
           true <- byte_size(rest) >= String.to_integer(length) do
        {head, Jason.decode!(rest)}
      else
        _ ->
          {:ok, data} = :gen_tcp.recv(sock, 0, @bound)
          read_response(sock, acc <> data)
      end
    end

    # The second request proves the socket survived: a refusal that closed it,
    # or one whose unread bytes were taken for the next request, fails here.
    defp answered!(sock, id) do
      send_post(sock, body_of(1024, id))
      {head, body} = read_response(sock)
      assert head =~ ~r/\AHTTP\/1\.1 200 /
      assert %{"id" => ^id, "result" => %{"tools" => [_ | _]}} = body
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a body near any size limit; searched the pinned dist (a10085d0) for one"
    test "over the limit → 413 with the JSON-RPC body, and the socket answers the next request",
         %{port: port} do
      sock = connect(port)
      send_post(sock, body_of(2048))
      {head, body} = read_response(sock)

      assert head =~ ~r/\AHTTP\/1\.1 413 /
      assert head =~ ~r/\r\ncontent-type: application\/json/i
      refute head =~ ~r/\r\nconnection: close/i

      assert %{"jsonrpc" => "2.0", "id" => nil, "error" => error} = body
      assert error["code"] == -32_600
      assert error["data"] == "request body exceeds 1024 bytes"

      answered!(sock, 2)
    end

    @tag oc: :none
    @tag oc_reason:
           "no OC check sends a body near any size limit; searched the pinned dist (a10085d0) for one"
    test "at the limit → 200, and a second request on the same socket is answered", %{
      port: port
    } do
      sock = connect(port)
      answered!(sock, 1)
      answered!(sock, 2)
    end
  end
end

defmodule MCP.Transport.StreamableHTTP.ClientTest do
  @moduledoc """
  CR-11 (MES-27) regression coverage for the Streamable HTTP **client**
  transport's content-coding handling — the first test to drive the client path
  at all (A6-3).

  The SDK sends `accept-encoding: identity` and does not decode compressed
  response bodies (req's decompression is opt-in and unbounded — a
  decompression-bomb DoS, `EEF-CVE-2026-49755`). A peer that returns a
  `content-encoding` other than `identity` anyway (permitted but discouraged by
  RFC 9110 §12.5.3 — a SHOULD, not a MUST) must be **failed cleanly** with a
  coding-naming error, not mis-decoded into `{:json_decode_error, …}`.
  """
  use ExUnit.Case, async: false

  alias MCP.Transport.StreamableHTTP.Client

  defmodule ProbePlug do
    @moduledoc false
    import Plug.Conn

    # opts is the Agent holding the last observed accept-encoding.
    def init(agent), do: agent

    def call(conn, agent) do
      Agent.update(agent, fn _ -> get_req_header(conn, "accept-encoding") end)
      {ct, ce_list, body} = response_for(conn.request_path)
      conn = put_resp_header(conn, "content-type", ct)
      # Append each content-encoding as its OWN field line (put_resp_header would
      # dedupe). This lets a route emit duplicate content-encoding lines, the CR-12
      # wire form (RFC 9110 §5.3) the first-value-only guard walked past.
      conn = %{
        conn
        | resp_headers: conn.resp_headers ++ Enum.map(ce_list, &{"content-encoding", &1})
      }

      send_resp(conn, 200, body)
    end

    @json Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{"ok" => true}})

    # content-type, content-encoding value list (one entry per field line), body
    defp response_for("/gzip-json"), do: {"application/json", ["gzip"], :zlib.gzip(@json)}

    defp response_for("/gzip-sse"),
      do: {"text/event-stream", ["gzip"], :zlib.gzip("data: " <> @json <> "\n\n")}

    defp response_for("/identity-json"), do: {"application/json", ["identity"], @json}
    defp response_for("/plain-json"), do: {"application/json", [], @json}
    # CR-12: two separate content-encoding field lines, both orderings.
    defp response_for("/dup-identity-gzip"),
      do: {"application/json", ["identity", "gzip"], :zlib.gzip(@json)}

    defp response_for("/dup-gzip-identity"),
      do: {"application/json", ["gzip", "identity"], :zlib.gzip(@json)}
  end

  setup do
    port = free_port()
    {:ok, agent} = Agent.start_link(fn -> :unset end)

    {:ok, server} =
      Bandit.start_link(
        plug: {ProbePlug, agent},
        port: port,
        ip: {127, 0, 0, 1},
        startup_log: false
      )

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :normal) end)
    %{agent: agent, port: port}
  end

  defp start_client(port, path) do
    {:ok, pid} = Client.start_link(owner: self(), url: "http://127.0.0.1:#{port}#{path}")
    pid
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  test "CR-11.1: the client sends `accept-encoding: identity`", %{agent: agent, port: port} do
    pid = start_client(port, "/plain-json")
    Client.send_message(pid, %{"jsonrpc" => "2.0", "id" => 1})
    assert Agent.get(agent, & &1) == ["identity"]
  end

  test "CR-11.2/11.3: a gzip-coded JSON response fails cleanly and names the coding", %{
    port: port
  } do
    pid = start_client(port, "/gzip-json")
    # DISCRIMINATING: the exact structured error, not merely `{:error, _}`. At the
    # pre-fix SHA this returns `{:error, {:json_decode_error, …}}`, so this match
    # fails there — the fail-then-pass discriminator (A7/A7a).
    assert {:error, {:unexpected_content_encoding, "gzip"}} =
             Client.send_message(pid, %{"jsonrpc" => "2.0", "id" => 1})
  end

  test "A6-8: the guard covers the SSE path too (gzip text/event-stream)", %{port: port} do
    pid = start_client(port, "/gzip-sse")

    assert {:error, {:unexpected_content_encoding, "gzip"}} =
             Client.send_message(pid, %{"jsonrpc" => "2.0", "id" => 1})
  end

  test "A6-11: `content-encoding: identity` is legal and does NOT error", %{port: port} do
    pid = start_client(port, "/identity-json")
    assert :ok = Client.send_message(pid, %{"jsonrpc" => "2.0", "id" => 1})
    assert_receive {:mcp_message, %{"result" => %{"ok" => true}}}, 2_000
  end

  test "A6-11: an absent content-encoding does NOT error (conformant peer)", %{port: port} do
    pid = start_client(port, "/plain-json")
    assert :ok = Client.send_message(pid, %{"jsonrpc" => "2.0", "id" => 1})
    assert_receive {:mcp_message, %{"result" => %{"ok" => true}}}, 2_000
  end

  # CR-12 (RFC 9110 §5.3/§8.4): duplicate content-encoding field lines are
  # semantically identical to the comma form. `identity` then `gzip` on separate
  # lines is the natural applied order; at a6bd999 (first-value-only) it produced
  # {:json_decode_error, …} — byte-identical to pre-fix. This is the DISCRIMINATING
  # sixth test; it FAILS at a6bd999.
  test "CR-12: duplicate lines identity-then-gzip fail cleanly, not json_decode", %{port: port} do
    pid = start_client(port, "/dup-identity-gzip")

    assert {:error, {:unexpected_content_encoding, "gzip"}} =
             Client.send_message(pid, %{"jsonrpc" => "2.0", "id" => 1})
  end

  # The other ordering — caught by luck at a6bd999 (gzip is the first value), but
  # asserted so a future refactor cannot silently drop it (both orderings covered).
  test "CR-12: duplicate lines gzip-then-identity fail cleanly", %{port: port} do
    pid = start_client(port, "/dup-gzip-identity")

    assert {:error, {:unexpected_content_encoding, "gzip"}} =
             Client.send_message(pid, %{"jsonrpc" => "2.0", "id" => 1})
  end
end

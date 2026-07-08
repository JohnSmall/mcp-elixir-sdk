defmodule MCP.Transport.StreamableHTTP.ACTest do
  @moduledoc """
  MES-5 — EMFA consumer-acceptance criteria AC1–AC8 for the `handler_opts`
  seam, as named ExUnit tests (1:1 with the AC contract).

  The **assertions** are EMFA's; only the request plumbing is adapted to the
  real SDK source:

    * public Plug option is `server_mod:` (not `handler:`);
    * the server is `:waiting` until a `notifications/initialized` notification
      flips it to `:ready` (`server.ex:426-442`), so `initialize/2` sends that
      notification before any `tools/call`;
    * non-localhost origin is rejected with HTTP **403**.

  AC1/AC2/AC4/AC5/AC8 also have coverage in
  `streamable_http_handler_opts_test.exs` (MES-3); the genuinely-new depth here
  is **AC3** (arg cannot override bound identity), **AC6** (session isolation),
  and **AC7** (localhost enforcement preserved; factory not invoked on reject).
  """
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureLog

  alias MCP.Test.EchoHandler
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @init_body Jason.encode!(%{
               "jsonrpc" => "2.0",
               "id" => 1,
               "method" => "initialize",
               "params" => %{
                 "protocolVersion" => "2025-11-25",
                 "capabilities" => %{},
                 "clientInfo" => %{"name" => "ac", "version" => "1.0"}
               }
             })

  @initialized_body Jason.encode!(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

  # --- framing helpers (adapted from the SDK's own transport tests) ---

  defp init_opts(extra) do
    MCPPlug.init(
      [
        server_mod: EchoHandler,
        enable_json_response: true,
        session_id_generator: fn -> UUID.uuid4() end
      ] ++ extra
    )
  end

  defp build_post(body, headers, mutate) do
    base =
      :post
      |> conn("http://localhost/", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    headers
    |> Enum.reduce(base, fn {k, v}, c -> put_req_header(c, k, v) end)
    |> mutate.()
  end

  # POST initialize (running any `mutate` to set conn.assigns), read the
  # session id, then send `notifications/initialized` to reach :ready.
  defp initialize(plug_opts, mutate \\ & &1) do
    conn = build_post(@init_body, [{"origin", "http://localhost"}], mutate) |> MCPPlug.call(plug_opts)
    sid = session_id(conn)

    if sid do
      build_post(@initialized_body, [{"origin", "http://localhost"}, {"mcp-session-id", sid}], & &1)
      |> MCPPlug.call(plug_opts)
    end

    {conn, sid}
  end

  defp call(plug_opts, sid, name, args, mutate \\ & &1) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call",
        "params" => %{"name" => name, "arguments" => args}
      })

    build_post(body, [{"origin", "http://localhost"}, {"mcp-session-id", sid}], mutate)
    |> MCPPlug.call(plug_opts)
  end

  defp session_id(conn) do
    case get_resp_header(conn, "mcp-session-id") do
      [sid | _] -> sid
      [] -> nil
    end
  end

  defp tool_text(conn) do
    conn.resp_body
    |> Jason.decode!()
    |> get_in(["result", "content"])
    |> hd()
    |> Map.get("text")
  end

  # --- AC1 — static opts through the Plug ---

  test "AC1 — static handler_opts flow through the plug to the handler" do
    opts = init_opts(handler_opts: [identity: "PM"])
    {_c, sid} = initialize(opts)
    assert tool_text(call(opts, sid, "whoami", %{})) == "PM"
  end

  # --- AC2 — factory reads conn.assigns set by an upstream plug ---

  test "AC2 — factory handler_opts capture conn.assigns from the upstream pipeline" do
    opts = init_opts(handler_opts: fn conn -> [identity: conn.assigns[:role]] end)
    {_c, sid} = initialize(opts, fn conn -> assign(conn, :role, "CODE_CREATOR") end)
    assert tool_text(call(opts, sid, "whoami", %{})) == "CODE_CREATOR"
  end

  # --- AC3 — bound identity is state; a tool ARG cannot override it (NEW) ---

  test "AC3 — a tool-arg identity does NOT override the bound identity" do
    opts = init_opts(handler_opts: fn conn -> [identity: conn.assigns[:role]] end)
    {_c, sid} = initialize(opts, fn conn -> assign(conn, :role, "REVIEWER") end)

    text = tool_text(call(opts, sid, "whoami_with_arg", %{"identity" => "PM"}))
    assert text == "REVIEWER"
  end

  # --- AC4 — no handler_opts → unchanged behaviour ---

  test "AC4 — absent handler_opts is backward compatible (identity empty)" do
    opts = init_opts([])
    {_c, sid} = initialize(opts)
    assert tool_text(call(opts, sid, "whoami", %{})) == ""
  end

  # --- AC5 — factory runs once at initialize; later calls reuse bound state ---

  test "AC5 — identity is bound per-session at initialize, not re-derived per call" do
    opts = init_opts(handler_opts: fn conn -> [identity: conn.assigns[:role]] end)
    {_c, sid} = initialize(opts, fn conn -> assign(conn, :role, "PM") end)

    # A later call on the same session carries a DIFFERENT assign — the value
    # bound at initialize must still win.
    text = tool_text(call(opts, sid, "whoami", %{}, fn conn -> assign(conn, :role, "REVIEWER") end))
    assert text == "PM"
  end

  # --- AC6 — session isolation (NEW) ---

  test "AC6 — concurrent sessions get independent bound identities" do
    opts = init_opts(handler_opts: fn conn -> [identity: conn.assigns[:role]] end)
    {_a, sid_a} = initialize(opts, fn c -> assign(c, :role, "PM") end)
    {_b, sid_b} = initialize(opts, fn c -> assign(c, :role, "REVIEWER") end)

    assert sid_a != sid_b
    assert tool_text(call(opts, sid_a, "whoami", %{})) == "PM"
    assert tool_text(call(opts, sid_b, "whoami", %{})) == "REVIEWER"
  end

  # --- AC7 — localhost enforcement preserved; factory NOT invoked (NEW) ---

  test "AC7 — non-localhost origin is rejected with handler_opts set; factory not invoked" do
    test_pid = self()

    opts =
      init_opts(
        handler_opts: fn _conn ->
          send(test_pid, :factory_ran)
          [identity: "PM"]
        end
      )

    conn =
      :post
      |> conn("http://localhost/", @init_body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("origin", "http://evil.example")
      |> MCPPlug.call(opts)

    assert conn.status == 403
    # The origin check fires before routing, so the factory closure never runs.
    refute_receive :factory_ran, 200
  end

  # --- AC8 — factory failure mode: non-keyword fails the session cleanly ---
  # (PreStarted static-only, and factory-raises, are covered in MES-3
  #  streamable_http_handler_opts_test.exs cases 7 and 8.)

  test "AC8 — a factory that returns a non-keyword fails the session cleanly" do
    opts = init_opts(handler_opts: fn _conn -> :not_a_keyword end)

    {conn, _log} =
      with_log(fn ->
        :post
        |> conn("http://localhost/", @init_body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("origin", "http://localhost")
        |> MCPPlug.call(opts)
      end)

    assert conn.status == 500
    assert Jason.decode!(conn.resp_body)["error"]["code"] == -32_603
    # No server started with a garbage identity: no session row was inserted.
    assert :ets.tab2list(opts.sessions) == []
  end
end

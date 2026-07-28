defmodule MCP.Server.DispatchTest do
  use ExUnit.Case, async: true

  alias MCP.Protocol.Capabilities.ServerCapabilities
  alias MCP.Protocol.Messages.{Notification, Request}
  alias MCP.Protocol.Types.Implementation
  alias MCP.Server.Dispatch
  alias MCP.Server.ToolContext
  alias MCP.Test.StatelessHandler

  @version "2026-07-28"

  defp config do
    {:ok, state} = StatelessHandler.init([])

    %{
      handler_module: StatelessHandler,
      handler_state: state,
      server_info: %Implementation{name: "mcp_elixir_sdk", version: "2.0.0"},
      capabilities: %ServerCapabilities{},
      instructions: nil
    }
  end

  defp ctx(identity \\ nil), do: %ToolContext{request_id: 1, identity: identity}

  defp meta(version \\ @version), do: %{"io.modelcontextprotocol/protocolVersion" => version}

  defp req(method, params), do: %Request{id: 1, method: method, params: params}

  defp call_tool(name, args, identity) do
    params = %{"name" => name, "arguments" => args, "_meta" => meta()}
    {:reply, resp, _state} = Dispatch.dispatch(req("tools/call", params), ctx(identity), config())
    resp
  end

  defp tool_text(resp), do: resp["result"]["content"] |> hd() |> Map.get("text")

  # --- MC-1: per-request context reaches the callback ---

  test "MC-1 — context identity reaches tools/call" do
    assert tool_text(call_tool("whoami", %{}, "PM")) == "PM"
  end

  test "MC-1 — context reaches a non-tool path (prompts/get)" do
    params = %{"name" => "who", "arguments" => %{}, "_meta" => meta()}
    {:reply, resp, _} = Dispatch.dispatch(req("prompts/get", params), ctx("REVIEWER"), config())
    text = resp["result"]["messages"] |> hd() |> get_in(["content", "text"])
    assert text == "REVIEWER"
  end

  # --- MC-4: a model-supplied identity arg NEVER reaches ctx.identity ---

  test "MC-4 — tool-arg identity does not override ctx.identity (spoof dropped)" do
    assert tool_text(call_tool("whoami_with_arg", %{"identity" => "spoof"}, "REAL")) == "REAL"
  end

  test "MC-4 — with no pipeline identity, a spoof arg still yields empty (never spoof)" do
    text = tool_text(call_tool("whoami_with_arg", %{"identity" => "spoof"}, nil))
    assert text == ""
    refute text == "spoof"
  end

  test "MC-4 — prompts/get: a competing arguments.identity does not override ctx.identity (AC3′)" do
    params = %{"name" => "who", "arguments" => %{"identity" => "spoof"}, "_meta" => meta()}
    {:reply, resp, _} = Dispatch.dispatch(req("prompts/get", params), ctx("REVIEWER"), config())
    text = resp["result"]["messages"] |> hd() |> get_in(["content", "text"])
    assert text == "REVIEWER"
    refute text == "spoof"
  end

  # --- MC-3: per-request isolation ---

  test "MC-3 — concurrent requests see their own identity; no leakage" do
    assert tool_text(call_tool("whoami", %{}, "PM")) == "PM"
    assert tool_text(call_tool("whoami", %{}, "REVIEWER")) == "REVIEWER"
  end

  # --- Removed methods: stateless behaviour, no legacy path ---

  test "initialize is removed → UnsupportedProtocolVersion (-32022)" do
    {:reply, resp, _} = Dispatch.dispatch(req("initialize", %{}), ctx(), config())
    assert resp["error"]["code"] == -32_022
  end

  test "ping and logging/setLevel are removed → method not found (-32601)" do
    {:reply, ping_resp, _} = Dispatch.dispatch(req("ping", %{}), ctx(), config())

    {:reply, log_resp, _} =
      Dispatch.dispatch(req("logging/setLevel", %{"level" => "info"}), ctx(), config())

    assert ping_resp["error"]["code"] == -32_601
    assert log_resp["error"]["code"] == -32_601
  end

  # --- Per-request version gate ---

  test "request without a protocolVersion _meta fails fast (-32022)" do
    {:reply, resp, _} =
      Dispatch.dispatch(req("tools/call", %{"name" => "whoami"}), ctx("PM"), config())

    assert resp["error"]["code"] == -32_022
  end

  test "old-shape (2025-11-25) version fails fast (-32022)" do
    params = %{"name" => "whoami", "arguments" => %{}, "_meta" => meta("2025-11-25")}
    {:reply, resp, _} = Dispatch.dispatch(req("tools/call", params), ctx("PM"), config())
    assert resp["error"]["code"] == -32_022
  end

  # --- server/discover: no version gate; schema-shaped result ---

  test "server/discover: schema shape (supportedVersions + CacheableResult fields; serverInfo in _meta)" do
    {:reply, resp, _} = Dispatch.dispatch(req("server/discover", %{}), ctx(), config())
    result = resp["result"]

    assert result["supportedVersions"] == [@version]
    assert result["resultType"] == "complete"
    assert result["ttlMs"] == 0
    assert result["cacheScope"] == "public"
    assert result["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "mcp_elixir_sdk"
    # the pre-fix (wrong) shape must be gone
    refute Map.has_key?(result, "protocolVersions")
    refute Map.has_key?(result, "serverInfo")
  end

  # --- MC-1 depth: context reaches ALL EIGHT identity-capable callbacks ---

  test "MC-1 depth — the per-request context reaches all eight identity-capable callbacks" do
    id = "PM"

    checks = [
      {"tools/list", %{}, fn r -> get_in(r, ["tools", Access.at(0), "boundIdentity"]) end},
      {"tools/call", %{"name" => "whoami", "arguments" => %{}},
       fn r -> get_in(r, ["content", Access.at(0), "text"]) end},
      {"resources/list", %{}, fn r -> get_in(r, ["resources", Access.at(0), "name"]) end},
      {"resources/read", %{"uri" => "mem://res"},
       fn r -> get_in(r, ["contents", Access.at(0), "text"]) end},
      {"resources/templates/list", %{},
       fn r -> get_in(r, ["resourceTemplates", Access.at(0), "name"]) end},
      {"prompts/list", %{}, fn r -> get_in(r, ["prompts", Access.at(0), "description"]) end},
      {"prompts/get", %{"name" => "who", "arguments" => %{}},
       fn r -> get_in(r, ["messages", Access.at(0), "content", "text"]) end},
      {"completion/complete", %{"ref" => %{}, "argument" => %{}},
       fn r -> get_in(r, ["completion", "values", Access.at(0)]) end}
    ]

    for {method, extra, extract} <- checks do
      params = Map.put(extra, "_meta", meta())
      {:reply, resp, _} = Dispatch.dispatch(req(method, params), ctx(id), config())
      assert extract.(resp["result"]) == id, "context identity did not reach #{method}"
    end
  end

  test "F3 — a handler missing the required context arity is a contract error (method-not-found), not a silent legacy call" do
    defmodule NoCtxHandler do
      @behaviour MCP.Server.Handler
      def init(_), do: {:ok, %{}}
      # only the legacy 2-arity form — NOT the stateless context arity
      def handle_list_tools(_cursor, state), do: {:ok, [], nil, state}
    end

    cfg = %{config() | handler_module: NoCtxHandler}
    params = %{"_meta" => meta()}
    {:reply, resp, _} = Dispatch.dispatch(req("tools/list", params), ctx("PM"), cfg)
    assert resp["error"]["code"] == -32_601
  end

  # --- notifications are SDK-internal no-ops ---

  test "notifications/initialized is tolerated as a no-op (handshake removed)" do
    notif = %Notification{method: "notifications/initialized", params: nil}
    assert {:noreply, _state} = Dispatch.dispatch(notif, ctx(), config())
  end
end

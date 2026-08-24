# L2 — direct establishment of ruling A's antecedent, per boundary DIRECTION.
#
#     mix run conformance/etcc_l2_probe.exs
#
# L1 (the redness proxy) answers "does mutating this boundary redden a unit outside
# its own tests?". Its silence is ambiguous: it means EITHER "no lib/ call site routes
# this boundary to a transport" OR "one does and no test asserts it". L2 removes the
# ambiguity by driving the real lib/ entry points and printing the BYTES they produce.
#
# Run once unmutated to get the baseline, then once per boundary-direction mutation.
# A scenario whose bytes MOVE under a mutation is a lib/ call site routing that
# boundary to a transport, so ruling A's antecedent is FALSE and the boundary is LIVE.
# A boundary no scenario moves is DEAD *by this instrument* — which is why the DEAD
# verdicts also carry an enumerated call-site chain in `etcc-boundaries.json`.
#
# MES-81 round 4, PM correction contract comment 26059 item 1: L2 runs on EVERY
# boundary whose live count is zero, mechanically, and its result is recorded on every
# boundary including the ones that stay dead.
defmodule MCP.Conformance.L2Probe do
  @moduledoc false
  @behaviour MCP.Server.Handler

  alias MCP.Protocol
  alias MCP.Protocol.Capabilities.ServerCapabilities

  alias MCP.Protocol.Types.Content.{
    AudioContent,
    EmbeddedResource,
    ImageContent,
    ResourceLink,
    TextContent
  }

  alias MCP.Protocol.Messages.{Notification, Request}
  alias MCP.Protocol.Types.{Implementation, Prompt, Resource, ResourceContents, Tool}
  alias MCP.Server.{Dispatch, ToolContext}
  alias MCP.Transport.SSE

  @version "2026-07-28"

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_list_tools(_cursor, _ctx, state) do
    {:ok, [%Tool{name: "t", description: "d", input_schema: %{"type" => "object"}}], nil, state}
  end

  @impl true
  def handle_list_resources(_cursor, _ctx, state) do
    {:ok, [%Resource{uri: "file:///a", name: "a", mime_type: "text/plain"}], nil, state}
  end

  @impl true
  def handle_read_resource(_uri, _ctx, state) do
    {:ok, [%ResourceContents{uri: "file:///r", text: "z", mime_type: "text/plain"}], state}
  end

  @impl true
  def handle_list_prompts(_cursor, _ctx, state) do
    {:ok, [%Prompt{name: "p", description: "d"}], nil, state}
  end

  @impl true
  def handle_get_prompt(_name, _args, _ctx, state) do
    {:ok, %{"messages" => [%{"role" => "user", "content" => %TextContent{text: "hello"}}]}, state}
  end

  @impl true
  def handle_call_tool(name, _args, _ctx, state), do: {:ok, content_for(name), %{}, state}

  defp content_for("text"), do: [%TextContent{text: "hello"}]
  defp content_for("image"), do: [%ImageContent{data: "AAA", mime_type: "image/png"}]
  defp content_for("audio"), do: [%AudioContent{data: "BBB", mime_type: "audio/wav"}]
  defp content_for("link"), do: [%ResourceLink{uri: "file:///x", name: "x"}]

  defp content_for("embedded"),
    do: [%EmbeddedResource{resource: %ResourceContents{uri: "file:///r", text: "z"}}]

  defp config do
    {:ok, state} = init([])

    %{
      handler_module: __MODULE__,
      handler_state: state,
      server_info: %Implementation{name: "probe", version: "0"},
      capabilities: %ServerCapabilities{tools: %{}, resources: %{}, prompts: %{}},
      instructions: nil
    }
  end

  defp meta, do: %{"io.modelcontextprotocol/protocolVersion" => @version}

  defp dispatched(method, params) do
    req = %Request{id: 1, method: method, params: Map.put(params, "_meta", meta())}

    case Dispatch.dispatch(req, %ToolContext{request_id: 1}, config()) do
      {:reply, resp, _} -> Jason.encode!(resp)
      other -> inspect(other)
    end
  end

  defp call(tool), do: dispatched("tools/call", %{"name" => tool, "arguments" => %{}})

  @doc "scenario => the bytes a real lib/ path puts on the wire (or the decoded value)."
  def scenarios do
    %{
      "server/discover" => dispatched("server/discover", %{}),
      "tools/list" => dispatched("tools/list", %{}),
      "resources/list" => dispatched("resources/list", %{}),
      "resources/read" => dispatched("resources/read", %{"uri" => "file:///r"}),
      "prompts/list" => dispatched("prompts/list", %{}),
      "prompts/get" => dispatched("prompts/get", %{"name" => "p", "arguments" => %{}}),
      "tools/call text" => call("text"),
      "tools/call image" => call("image"),
      "tools/call audio" => call("audio"),
      "tools/call link" => call("link"),
      "tools/call embedded" => call("embedded"),
      "error response (unknown method)" => dispatched("no/such/method", %{}),
      "SSE frame of a notification" =>
        SSE.encode_message(
          Jason.decode!(Jason.encode!(Notification.new("notifications/message")))
        ),
      "decode_message of a wire error" =>
        inspect(
          Protocol.decode_message(%{
            "jsonrpc" => "2.0",
            "id" => 1,
            "error" => %{"code" => -32_601, "message" => "nope", "data" => "d"}
          })
        ),
      "decode_message of a wire result" =>
        inspect(
          Protocol.decode_message(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{"ok" => true}})
        )
    }
  end
end

MCP.Conformance.L2Probe.scenarios()
|> Enum.sort()
|> Enum.each(fn {k, v} -> IO.puts(k <> "\t" <> inspect(v)) end)

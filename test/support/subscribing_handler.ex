defmodule MCP.Test.SubscribingHandler do
  @moduledoc """
  Test handler implementing the `subscriptions/listen` callbacks.

  It hands its `ctx.stream_sink` to the `:owner` pid given at `init/1` so a test
  can drive emissions from outside the request process — which is also the
  realistic shape, since a real handler's change events arrive from somewhere
  other than the request that opened the stream.

  Two deliberate refusals, so the honoured subset is never trivially equal to
  the requested one:

    * `promptsListChanged` is **never** honoured. A client asking for it must
      see it absent from the acknowledgment.
    * `resourceSubscriptions` is honoured only for URIs under
      `mem://allowed/`, and only when the caller's identity is not
      `"restricted"` — the open-time authorization decision, expressed the way
      the design says it should be: by narrowing the returned subset rather
      than by a separate hook.

  Identity `"denied"` refuses the whole subscription with an error, exercising
  the `{:error, code, message, state}` return. It hands the sink to the owner
  **before** refusing, which is the shape a refusal test needs: the point of
  F1 is that a handler which has already been given a live sink is told when
  that sink dies, and a handler that never captured one cannot show it.

  Two round-2 probes, both id-triggered so the ordinary paths are untouched:
  `"raise-in-listen"` captures the sink and then raises inside
  `handle_listen/3`; `"exit-in-teardown"` exits inside `handle_listen_closed/3`
  for a reason of the handler's own.
  """
  @behaviour MCP.Server.Handler

  alias MCP.Server.ToolContext

  @allowed_uri_prefix "mem://allowed/"

  @impl true
  def init(opts), do: {:ok, %{owner: Keyword.get(opts, :owner)}}

  @impl true
  def supported_subscriptions do
    ["toolsListChanged", "promptsListChanged", "resourcesListChanged", "resourceSubscriptions"]
  end

  @impl true
  def handle_listen(_filter, %ToolContext{identity: "denied"} = ctx, state) do
    notify(state, {:listen_refusing, ctx.request_id, ctx.stream_sink, ctx.identity})
    {:error, -32_603, "subscriptions are not available to this principal", state}
  end

  # Correction round 2 (review R1, PROBE A): a handler that captures the sink
  # and THEN raises. The sink is handed to the owner first, because the point
  # of the probe is that a raise leaves someone holding a live sink — a handler
  # that never captured one cannot show it.
  def handle_listen(_filter, %ToolContext{request_id: "raise-in-listen"} = ctx, state) do
    notify(state, {:listen_raising, ctx.request_id, ctx.stream_sink, ctx.identity})
    raise "handle_listen/3 blew up after capturing the sink"
  end

  def handle_listen(filter, %ToolContext{} = ctx, state) do
    honoured =
      filter
      |> Map.delete("promptsListChanged")
      |> narrow_uris(ctx.identity)

    notify(state, {:listen_opened, ctx.request_id, honoured, ctx.stream_sink, ctx.identity})

    # A subscription whose id is "eager" emits BEFORE returning — i.e. before
    # the acknowledgment can possibly have been written. The ack-first ordering
    # rule (schema.ts:1386-1392) is only meaningfully tested against a handler
    # that does this; a test that emits after handle_listen/3 has returned is
    # racing the ack rather than ordering against it.
    if ctx.request_id == "eager" do
      ToolContext.stream(ctx, "notifications/tools/list_changed", %{})
    end

    # A subscription whose id is "collector-probe" emits a REQUEST-SCOPED
    # notification through `ctx.reply_sink` — which is a live collector push at
    # this instant — and hands that same sink to the owner. That lets a test
    # show both halves of the collector/stream lifetime property: the collector
    # was alive HERE (the driver drains one notification and warns about it),
    # and is gone by the time the stream is live (the very same sink then
    # exits with :noproc).
    if ctx.request_id == "collector-probe" do
      ToolContext.log(ctx, "info", "request-scoped, emitted during handle_listen/3")
      notify(state, {:listen_reply_sink, ctx.request_id, ctx.reply_sink})
    end

    {:ok, honoured, state}
  end

  # Correction round 2 (review R3): a teardown callback that fails for its OWN
  # reasons — a call to a process the handler owns and has lost, not to
  # anything the SDK gave it. It reports that it ran before exiting, so a test
  # can tell "the callback faulted and the response survived" from "the
  # callback never ran".
  @impl true
  def handle_listen_closed("exit-in-teardown" = subscription_id, %ToolContext{} = ctx, state) do
    notify(state, {:listen_closed, subscription_id, ctx.identity})
    GenServer.call(:mcp_test_handler_process_that_does_not_exist, :anything)
  end

  def handle_listen_closed(subscription_id, %ToolContext{} = ctx, state) do
    notify(state, {:listen_closed, subscription_id, ctx.identity})

    # Reports what a handler emitting from teardown actually gets. Until
    # correction round 1 `ctx.reply_sink` was still bound here, to a collector
    # the driver had already stopped, so this EXITED with :noproc instead of
    # being dropped.
    emitted =
      try do
        {:returned, ToolContext.log(ctx, "info", "emitting from teardown"),
         ToolContext.stream(ctx, "notifications/tools/list_changed", %{})}
      catch
        kind, reason -> {kind, reason}
      end

    notify(state, {:listen_closed_emit, subscription_id, emitted, ctx.reply_sink})
    :ok
  end

  # Open-time authorization: a URI this principal may not observe is simply
  # absent from the honoured subset, and the acknowledgment reports it.
  defp narrow_uris(filter, identity) do
    case Map.get(filter, "resourceSubscriptions") do
      uris when is_list(uris) ->
        case Enum.filter(uris, &permitted_uri?(&1, identity)) do
          [] -> Map.delete(filter, "resourceSubscriptions")
          kept -> Map.put(filter, "resourceSubscriptions", kept)
        end

      _ ->
        filter
    end
  end

  defp permitted_uri?(_uri, "restricted"), do: false
  defp permitted_uri?(uri, _identity), do: String.starts_with?(uri, @allowed_uri_prefix)

  @doc "The URI prefix this handler will watch, for tests to build URIs from."
  def allowed_uri_prefix, do: @allowed_uri_prefix

  # --- Ordinary request-path callbacks, so the same handler serves both paths ---

  @impl true
  def handle_list_tools(_cursor, %ToolContext{}, state), do: {:ok, [], nil, state}

  @impl true
  def handle_list_resources(_cursor, %ToolContext{}, state), do: {:ok, [], nil, state}

  @impl true
  def handle_list_prompts(_cursor, %ToolContext{}, state), do: {:ok, [], nil, state}

  # Emits a request-scoped notification through reply_sink and reports what its
  # stream_sink was, so sink separation can be asserted from a non-listen
  # request rather than assumed.
  @impl true
  def handle_call_tool("emit_request_scoped", _args, %ToolContext{} = ctx, state) do
    ToolContext.log(ctx, "info", "request-scoped, belongs on the response stream")
    result = ToolContext.stream(ctx, "notifications/tools/list_changed", %{})
    {:ok, [%{"type" => "text", "text" => inspect(result)}], state}
  end

  def handle_call_tool(_name, _args, %ToolContext{}, state) do
    {:error, -32_602, "unknown tool", state}
  end

  defp notify(%{owner: owner}, message) when is_pid(owner), do: send(owner, message)
  defp notify(_state, _message), do: :ok
end

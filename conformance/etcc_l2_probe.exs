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
  alias MCP.Server.{Connection, Dispatch, ToolContext}
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
  # MES-178. Three scenarios drive the paths no dispatched scenario reaches: a handler
  # notification through `MCP.Server.Connection`'s `reply_sink/1` to its transport, the
  # same notification through the HTTP Plug's `NotificationCollector` into an SSE body,
  # and a notification framed onto a real pipe by `MCP.Transport.Stdio`. And every
  # scenario now runs in its OWN monitored process: one that raises (or whose linked
  # process dies) under a mutation is written as `{:raised, "<Module>"}` instead of
  # killing the whole run. Before MES-178 one raise — `Error (decode)`'s, in
  # `decode_message of a wire error` — left no output file at all, and the sweep could
  # only abort. New code sits BELOW the lines other records cite (`:46`, G33), so their
  # pinned bytes do not move.
  @behaviour MCP.Transport

  def handle_call_tool("notify", _args, ctx, state) do
    # Emitted through the per-request sink, which is the path under test. The reply's
    # content is EMPTY on purpose, so no content encoder can move these scenarios.
    :ok = ctx.reply_sink.("notifications/message", %{"level" => "info", "data" => "etcc"})
    {:ok, [], %{}, state}
  end

  def handle_call_tool(name, _args, _ctx, state), do: {:ok, content_for(name), %{}, state}

  # MCP.Transport, as a CAPTURE transport for the Connection scenario: `start_link/1`
  # hands back the scenario's own process, so whatever `Connection` sends its transport
  # arrives there as a message. What is measured is Connection's call into
  # `transport_module.send_message/2` — the boundary — not a real transport's framing.
  @impl MCP.Transport
  def start_link(opts), do: {:ok, Keyword.fetch!(opts, :sink)}

  @impl MCP.Transport
  def send_message(pid, message) do
    send(pid, {:etcc_captured, message})
    :ok
  end

  @impl MCP.Transport
  def send_message(pid, message, _opts), do: send_message(pid, message)

  @impl MCP.Transport
  def close(_pid), do: :ok

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

  # MES-174. Every required per-request `_meta` key, and the SHOULD one too. Until
  # MES-174 this sent only `protocolVersion`; MES-161 then made `clientCapabilities`
  # required, and all 12 scenarios routed through dispatch came back as one and the same
  # `-32602` reply — no mutation behind dispatch could move a byte, so every L2 silence
  # on those paths was vacuous. `BoundarySweep.check_probe_baseline!/1` now refuses a
  # baseline in that shape, so a future required key cannot blind the probe silently.
  defp meta do
    %{
      "io.modelcontextprotocol/protocolVersion" => @version,
      "io.modelcontextprotocol/clientInfo" => %{"name" => "etcc-l2-probe", "version" => "0"},
      "io.modelcontextprotocol/clientCapabilities" => %{}
    }
  end

  defp dispatched(method, params) do
    req = %Request{id: 1, method: method, params: Map.put(params, "_meta", meta())}

    case Dispatch.dispatch(req, %ToolContext{request_id: 1}, config()) do
      {:reply, resp, _} -> Jason.encode!(resp)
      other -> inspect(other)
    end
  end

  defp call(tool), do: dispatched("tools/call", %{"name" => tool, "arguments" => %{}})

  defp notify_request do
    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "notify", "arguments" => %{}, "_meta" => meta()}
    }
  end

  # Only the frames without an `id` — the notifications. The reply frame is another
  # direction's business, and keeping it out is what lets each of these three scenarios
  # move under its own boundary's mutation alone.
  defp notifications_only(maps), do: Enum.reject(maps, &Map.has_key?(&1, "id"))

  # MCP.Server.Connection: a handler notification through `reply_sink/1` to the transport.
  defp via_connection do
    {:ok, server} =
      Connection.start_link(
        transport: {__MODULE__, [sink: self()]},
        handler: {__MODULE__, []},
        server_info: %Implementation{name: "probe", version: "0"}
      )

    send(server, {:mcp_message, notify_request()})
    sent = captured([])
    Connection.close(server)
    sent |> notifications_only() |> Enum.map_join(" | ", &Jason.encode!/1)
  end

  defp captured(acc) do
    receive do
      {:etcc_captured, %{"id" => _} = reply} -> Enum.reverse([reply | acc])
      {:etcc_captured, message} -> captured([message | acc])
    after
      5_000 -> Enum.reverse([%{"timeout" => true} | acc])
    end
  end

  # MCP.Server.NotificationCollector: the same notification through the real HTTP Plug in
  # SSE mode. The payloads are taken off the frames by splitting each line at its first
  # ": ", NOT by `SSE`'s decoder and not by field name, so an SSE framing mutation (a
  # renamed field) leaves this value alone; `SSE frame of a notification` measures that.
  defp via_plug_sse do
    opts =
      MCP.Transport.StreamableHTTP.Plug.init(server_mod: __MODULE__, enable_json_response: false)

    message = notify_request()

    # The required request headers, written out rather than built by the SDK client's
    # `build_headers/2`: that goes through `HeaderMirror`, and a HeaderMirror mutation
    # would then move this scenario too (measured on MES-178 before this change).
    headers = [
      {"mcp-protocol-version", @version},
      {"mcp-method", "tools/call"},
      {"mcp-name", "notify"}
    ]

    request = Plug.Test.conn(:post, "http://localhost/", Jason.encode!(message))

    [
      {"content-type", "application/json"},
      {"accept", "application/json, text/event-stream"},
      {"origin", "http://localhost"} | headers
    ]
    |> Enum.reduce(request, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
    |> MCP.Transport.StreamableHTTP.Plug.call(opts)
    |> then(fn c -> "#{c.status} " <> Enum.join(sse_notifications(c.resp_body), " | ") end)
  end

  defp sse_notifications(body) do
    body
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case String.split(line, ": ", parts: 2) do
        [_field, "{" <> _ = json] -> [json]
        _ -> []
      end
    end)
    |> Enum.reject(&Map.has_key?(Jason.decode!(&1), "id"))
  end

  # MCP.Transport.Stdio: a notification framed onto a real pipe (`cat`) and read back.
  defp via_stdio do
    {:ok, t} =
      MCP.Transport.Stdio.start_link(
        owner: self(),
        command: System.find_executable("cat"),
        args: []
      )

    :ok =
      MCP.Transport.Stdio.send_message(t, %{
        "jsonrpc" => "2.0",
        "method" => "notifications/message",
        "params" => %{"level" => "info"}
      })

    read =
      receive do
        {:mcp_message, m} -> Jason.encode!(m)
      after
        5_000 -> "timeout"
      end

    MCP.Transport.Stdio.close(t)
    read
  end

  # Each scenario in its own monitored, UNLINKED process. Its value comes back as a
  # message sent before the process ends, so it always arrives ahead of the :DOWN. No
  # value means the scenario raised, threw, exited, or a process linked to it died: the
  # marker names the exception module only, so it is the same bytes on every run.
  defp isolated(fun) do
    parent = self()
    tag = make_ref()
    {pid, mon} = spawn_monitor(fn -> send(parent, {tag, fun.()}) end)

    receive do
      {:DOWN, ^mon, :process, ^pid, reason} ->
        receive do
          {^tag, value} -> value
        after
          0 -> {:raised, raised(reason)}
        end
    after
      60_000 ->
        Process.exit(pid, :kill)
        {:raised, "timeout"}
    end
  end

  defp raised({%{__exception__: true, __struct__: mod}, _stack}), do: inspect(mod)
  defp raised({{:nocatch, _}, _stack}), do: "throw"
  defp raised(_reason), do: "exit"

  @doc """
  scenario => the bytes a real lib/ path puts on the wire (or the decoded value), or
  `{:raised, "<Module>"}` for a scenario that did not return one (see `isolated/1`).
  """
  def scenarios, do: Map.new(thunks(), fn {k, f} -> {k, isolated(f)} end)

  @doc "scenario => the zero-arity function that produces it."
  def thunks do
    %{
      "server/discover" => fn -> dispatched("server/discover", %{}) end,
      "tools/list" => fn -> dispatched("tools/list", %{}) end,
      "resources/list" => fn -> dispatched("resources/list", %{}) end,
      "resources/read" => fn -> dispatched("resources/read", %{"uri" => "file:///r"}) end,
      "prompts/list" => fn -> dispatched("prompts/list", %{}) end,
      "prompts/get" => fn -> dispatched("prompts/get", %{"name" => "p", "arguments" => %{}}) end,
      "tools/call text" => fn -> call("text") end,
      "tools/call image" => fn -> call("image") end,
      "tools/call audio" => fn -> call("audio") end,
      "tools/call link" => fn -> call("link") end,
      "tools/call embedded" => fn -> call("embedded") end,
      "error response (unknown method)" => fn -> dispatched("no/such/method", %{}) end,
      "SSE frame of a notification" => fn ->
        SSE.encode_message(
          Jason.decode!(Jason.encode!(Notification.new("notifications/message")))
        )
      end,
      "decode_message of a wire error" => fn ->
        inspect(
          Protocol.decode_message(%{
            "jsonrpc" => "2.0",
            "id" => 1,
            "error" => %{"code" => -32_601, "message" => "nope", "data" => "d"}
          })
        )
      end,
      "decode_message of a wire result" => fn ->
        inspect(
          Protocol.decode_message(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{"ok" => true}})
        )
      end,
      "Connection notification to its transport" => &via_connection/0,
      "Plug SSE body notification (NotificationCollector)" => &via_plug_sse/0,
      "Stdio pipe frame of a notification" => &via_stdio/0
    }
  end
end

# MES-88, PM scope addition 8 (MES-81 `26071`). The scenario lines used to go to
# stdout — where the compiler's "Compiling 1 file (.ex)" and "Generated ... app" lines
# land as well. In a mutation sweep the step before EVERY probe run changes `lib/`, so
# those two lines are present on every mutated run and absent on the baseline, and a
# naive `diff` of two raw runs reports a difference that is NOT a moved scenario. That
# trap sits directly on AC1's path.
#
# Filtering the chatter out by prefix would be a workaround — it would still be reading
# a stream two writers share. Taking an output PATH removes it: chatter keeps stdout,
# scenarios go to the file, and the diff is over the file.
#
#     mix run conformance/etcc_l2_probe.exs            # scenarios to stdout, as before
#     mix run conformance/etcc_l2_probe.exs OUT_PATH   # scenarios to OUT_PATH
#
# The no-argument form is byte-identical to the pre-MES-88 behaviour, so anything that
# reads the old stdout form still works.
scenarios = MCP.Conformance.L2Probe.scenarios()

rendered =
  scenarios
  |> Enum.sort()
  |> Enum.map_join(fn {k, v} -> k <> "\t" <> inspect(v) <> "\n" end)

case System.argv() do
  [path | _] ->
    File.write!(path, rendered)

    IO.puts("[etcc-l2-probe] wrote #{path} (#{map_size(scenarios)} scenarios)")

  [] ->
    IO.write(rendered)
end

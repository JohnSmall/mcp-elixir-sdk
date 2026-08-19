defmodule MCP.Client do
  @moduledoc """
  MCP client for the 2026-07-28 stateless core.

  A GenServer that manages a connection to an MCP server via a pluggable
  transport. There is **no `initialize` handshake and no session** (SEP-2575 /
  SEP-2567): the client is usable as soon as it starts, discovers the server's
  capabilities via `server/discover`, and stamps the per-request `_meta`
  (`io.modelcontextprotocol/{protocolVersion,clientInfo,clientCapabilities}`)
  onto every request so any stateless instance can service it.

  ## Usage

      {:ok, client} = MCP.Client.start_link(
        transport: {MCP.Transport.StreamableHTTP.Client, url: "http://localhost:8080"},
        client_info: %{name: "my_app", version: "1.0.0"}
      )

      {:ok, info}  = MCP.Client.connect(client)          # server/discover probe
      {:ok, tools} = MCP.Client.list_tools(client)
      {:ok, out}   = MCP.Client.call_tool(client, "my_tool", %{"arg" => "val"})

  ## Multi Round-Trip Requests (SEP-2322)

  If a `tools/call` result comes back with `resultType: "input_required"`, the
  client fulfils the requested inputs via the optional `:on_input_required`
  callback and **retries** the original request carrying `requestState` and
  `inputResponses`; only the final `complete` result is returned to the caller.
  Without a resolver, the `InputRequiredResult` is returned as-is.

  ## Options

    * `:transport` — `{module, opts}` transport spec (started here, owner = self)
    * `:client_info` — `%Implementation{}` or `%{name:, version:}`
    * `:client_capabilities` — a `%ClientCapabilities{}` (advertised in
      `_meta`), and **only** that struct. Note the asymmetry with its
      neighbour `:client_info`, which also accepts a plain map: anything here
      that is not a `%ClientCapabilities{}` is **discarded whole** with a
      `Logger.warning` naming what was lost, and the default
      `%ClientCapabilities{}` is used. Converting a map instead would have to
      drop silently whatever it did not recognise, and a silent drop is the one
      thing this option is not allowed to do.
      Its `:extensions` (SEP-2133, schema.ts:785) are validated on the way out
      by `MCP.Protocol.Extensions.normalise/2` — anything it cannot put on the
      wire is dropped here and named in a `Logger.warning`, never deferred to
      a request. This SDK implements no extension, so the field is empty unless
      you declare one you implement.
    * `:protocol_version` — advertised version (default: the stateless core's)
    * `:notification_handler` — pid or `(method, params -> any)` for server
      notifications
    * `:on_input_required` — `(input_requests -> input_responses)` MRTR resolver
    * `:request_timeout` — default request timeout in ms (default: 30_000)
  """

  use GenServer

  require Logger

  alias MCP.Protocol
  alias MCP.Protocol.Capabilities.ClientCapabilities
  alias MCP.Protocol.Extensions
  alias MCP.Protocol.Messages.{Discover, MRTR, Notification, Request, Response}
  alias MCP.Protocol.Methods
  alias MCP.Protocol.Types.Implementation

  @default_request_timeout 30_000
  @protocol_version "2026-07-28"

  defstruct [
    :transport_module,
    :transport_pid,
    :server_capabilities,
    :server_info,
    :client_info,
    :client_capabilities,
    :protocol_version,
    :status,
    :notification_handler,
    :on_input_required,
    :pending_requests,
    :next_id,
    :request_timeout
  ]

  # --- Public API ---

  @doc "Starts the client GenServer and its transport."
  def start_link(opts) do
    {gen_opts, client_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, client_opts, gen_opts)
  end

  @doc """
  Probes the server via `server/discover` (the stateless replacement for the
  removed `initialize` handshake).

  Returns `{:ok, %{server_info:, server_capabilities:, protocol_version:,
  instructions:}}`.
  """
  def connect(client, timeout \\ 60_000) do
    GenServer.call(client, :connect, timeout)
  end

  @doc "Lists available tools. Options: `:cursor`, `:timeout`."
  def list_tools(client, opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout)
    GenServer.call(client, {:list_tools, opts}, timeout || @default_request_timeout)
  end

  @doc "Calls a tool. Transparently completes MRTR round-trips when a resolver is set."
  def call_tool(client, name, arguments \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    GenServer.call(client, {:call_tool, name, arguments}, timeout || @default_request_timeout)
  end

  @doc "Lists available resources. Options: `:cursor`, `:timeout`."
  def list_resources(client, opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout)
    GenServer.call(client, {:list_resources, opts}, timeout || @default_request_timeout)
  end

  @doc "Reads a resource by URI."
  def read_resource(client, uri, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    GenServer.call(client, {:read_resource, uri}, timeout || @default_request_timeout)
  end

  @doc "Lists resource templates. Options: `:cursor`, `:timeout`."
  def list_resource_templates(client, opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout)
    GenServer.call(client, {:list_resource_templates, opts}, timeout || @default_request_timeout)
  end

  @doc "Lists available prompts. Options: `:cursor`, `:timeout`."
  def list_prompts(client, opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout)
    GenServer.call(client, {:list_prompts, opts}, timeout || @default_request_timeout)
  end

  @doc "Gets a specific prompt by name with optional arguments."
  def get_prompt(client, name, arguments \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    GenServer.call(client, {:get_prompt, name, arguments}, timeout || @default_request_timeout)
  end

  @doc "Requests a completion."
  def complete(client, ref, argument, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    GenServer.call(client, {:complete, ref, argument}, timeout || @default_request_timeout)
  end

  @doc "Closes the client and its transport."
  def close(client) do
    GenServer.call(client, :close)
  catch
    :exit, _ -> :ok
  end

  @doc "Cancels a pending request by ID (sends `notifications/cancelled`)."
  def cancel(client, request_id, reason \\ nil) do
    GenServer.cast(client, {:cancel_request, request_id, reason})
  end

  @doc "Returns the transport pid (testing convenience)."
  def transport(client), do: GenServer.call(client, :get_transport)

  @doc "Returns the current client status (`:ready` or `:closed`)."
  def status(client), do: GenServer.call(client, :get_status)

  @doc "Returns the discovered server capabilities (after `connect/1`)."
  def server_capabilities(client), do: GenServer.call(client, :get_server_capabilities)

  @doc "Returns the discovered server info (after `connect/1`)."
  def server_info(client), do: GenServer.call(client, :get_server_info)

  # --- Pagination helpers ---

  @doc "Lists all tools, paginating automatically."
  def list_all_tools(client, opts \\ []), do: list_all(client, :list_tools, :tools, opts)

  @doc "Lists all resources, paginating automatically."
  def list_all_resources(client, opts \\ []),
    do: list_all(client, :list_resources, :resources, opts)

  @doc "Lists all resource templates, paginating automatically."
  def list_all_resource_templates(client, opts \\ []),
    do: list_all(client, :list_resource_templates, :resource_templates, opts)

  @doc "Lists all prompts, paginating automatically."
  def list_all_prompts(client, opts \\ []), do: list_all(client, :list_prompts, :prompts, opts)

  # --- GenServer callbacks ---

  @impl GenServer
  def init(opts) do
    {transport_spec, opts} = Keyword.pop!(opts, :transport)

    state = %__MODULE__{
      client_info: build_client_info(Keyword.get(opts, :client_info, default_info())),
      client_capabilities:
        build_client_capabilities(Keyword.get(opts, :client_capabilities, %ClientCapabilities{})),
      protocol_version: Keyword.get(opts, :protocol_version, @protocol_version),
      status: :ready,
      notification_handler: Keyword.get(opts, :notification_handler),
      on_input_required: Keyword.get(opts, :on_input_required),
      pending_requests: %{},
      next_id: 1,
      request_timeout: Keyword.get(opts, :request_timeout, @default_request_timeout)
    }

    case start_transport(transport_spec) do
      {:ok, module, pid} -> {:ok, %{state | transport_module: module, transport_pid: pid}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:connect, _from, %{status: :closed} = state),
    do: {:reply, {:error, :closed}, state}

  def handle_call(:connect, from, state) do
    send_rpc(state, from, Methods.discover(), %{}, {:discover})
  end

  # Introspection + close work in any state (including :closed) and must precede
  # the closed-guard below, which only rejects RPC operations.
  def handle_call(:close, _from, state), do: do_close(state)
  def handle_call(:get_transport, _from, state), do: {:reply, state.transport_pid, state}
  def handle_call(:get_status, _from, state), do: {:reply, state.status, state}

  def handle_call(:get_server_capabilities, _from, state),
    do: {:reply, state.server_capabilities, state}

  def handle_call(:get_server_info, _from, state), do: {:reply, state.server_info, state}

  def handle_call(_request, _from, %{status: :closed} = state),
    do: {:reply, {:error, :closed}, state}

  def handle_call({:list_tools, opts}, from, state),
    do: send_rpc(state, from, Methods.tools_list(), cursor_params(opts))

  def handle_call({:call_tool, name, arguments}, from, state),
    do:
      send_rpc(
        state,
        from,
        Methods.tools_call(),
        name_args(name, arguments),
        {:tool_call, name, arguments}
      )

  def handle_call({:list_resources, opts}, from, state),
    do: send_rpc(state, from, Methods.resources_list(), cursor_params(opts))

  def handle_call({:read_resource, uri}, from, state),
    do: send_rpc(state, from, Methods.resources_read(), %{"uri" => uri})

  def handle_call({:list_resource_templates, opts}, from, state),
    do: send_rpc(state, from, Methods.resources_templates_list(), cursor_params(opts))

  def handle_call({:list_prompts, opts}, from, state),
    do: send_rpc(state, from, Methods.prompts_list(), cursor_params(opts))

  def handle_call({:get_prompt, name, arguments}, from, state),
    do: send_rpc(state, from, Methods.prompts_get(), name_args(name, arguments))

  def handle_call({:complete, ref, argument}, from, state),
    do:
      send_rpc(state, from, Methods.completion_complete(), %{"ref" => ref, "argument" => argument})

  @impl GenServer
  def handle_cast({:cancel_request, request_id, reason}, %{status: :ready} = state) do
    params = %{"requestId" => request_id}
    params = if reason, do: Map.put(params, "reason", reason), else: params
    send_notification(state, Methods.cancelled(), params)
    {:noreply, state}
  end

  def handle_cast({:cancel_request, _id, _reason}, state), do: {:noreply, state}

  # --- Incoming messages ---

  @impl GenServer
  def handle_info({:mcp_message, message}, state) do
    case Protocol.decode_message(message) do
      {:ok, %Response{} = response} ->
        handle_response(response, state)

      {:ok, %Notification{} = notification} ->
        handle_notification(notification, state)

      # The stateless server makes no server→client requests (input rides MRTR).
      {:ok, %Request{}} ->
        {:noreply, state}

      {:error, error} ->
        Logger.warning("MCP Client: failed to decode message: #{inspect(error)}")
        {:noreply, state}
    end
  end

  def handle_info({:mcp_transport_closed, reason}, state) do
    Enum.each(state.pending_requests, fn {_id, %{from: from, timeout_ref: ref}} ->
      cancel_timeout(ref)
      GenServer.reply(from, {:error, {:transport_closed, reason}})
    end)

    {:noreply, %{state | status: :closed, pending_requests: %{}}}
  end

  def handle_info({:request_timeout, id}, state) do
    case Map.pop(state.pending_requests, id) do
      {%{from: from}, pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_requests: pending}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("MCP Client: unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.transport_pid && state.status != :closed do
      state.transport_module.close(state.transport_pid)
    end
  catch
    _, _ -> :ok
  end

  # --- Response handling ---

  defp handle_response(%Response{id: id} = response, state) do
    case Map.pop(state.pending_requests, id) do
      {%{from: from, timeout_ref: ref, kind: kind}, pending} ->
        cancel_timeout(ref)
        finish_response(response, from, kind, %{state | pending_requests: pending})

      {nil, _} ->
        Logger.warning("MCP Client: response for unknown request id=#{inspect(id)}")
        {:noreply, state}
    end
  end

  # server/discover result → capability probe reply.
  defp finish_response(%Response{error: error}, from, {:discover}, state) when error != nil do
    GenServer.reply(from, {:error, error})
    {:noreply, state}
  end

  defp finish_response(%Response{result: result}, from, {:discover}, state) do
    discover = Discover.Result.from_map(result)

    state = %{
      state
      | server_capabilities: discover.capabilities,
        server_info: discover.server_info
    }

    GenServer.reply(
      from,
      {:ok,
       %{
         server_info: discover.server_info,
         server_capabilities: discover.capabilities,
         protocol_version: List.first(discover.supported_versions) || state.protocol_version,
         instructions: discover.instructions
       }}
    )

    {:noreply, state}
  end

  # tools/call result → complete transparently through MRTR when input is required.
  defp finish_response(%Response{error: error} = _resp, from, _kind, state) when error != nil do
    GenServer.reply(from, {:error, error})
    {:noreply, state}
  end

  defp finish_response(%Response{result: result}, from, {:tool_call, name, arguments}, state) do
    if input_required?(result) and is_function(state.on_input_required, 1) do
      resume_mrtr(result, from, name, arguments, state)
    else
      GenServer.reply(from, {:ok, result})
      {:noreply, state}
    end
  end

  defp finish_response(%Response{result: result}, from, _kind, state) do
    GenServer.reply(from, {:ok, result})
    {:noreply, state}
  end

  defp input_required?(result), do: Map.get(result, "resultType") == MRTR.result_type()

  # Fulfil the requested inputs and retry the original tools/call carrying the
  # server's requestState + the resolved inputResponses (SEP-2322).
  defp resume_mrtr(result, from, name, arguments, state) do
    responses = state.on_input_required.(Map.get(result, "inputRequests"))

    params =
      name
      |> name_args(arguments)
      |> Map.put("requestState", Map.get(result, "requestState"))
      |> Map.put("inputResponses", responses)
      |> with_meta(state)

    {id, state} = next_id(state)
    send_request(state, id, Methods.tools_call(), params)
    timeout_ref = schedule_timeout(id, state.request_timeout)
    {:noreply, put_pending(state, id, from, timeout_ref, {:tool_call, name, arguments})}
  end

  # --- Notifications ---

  defp handle_notification(%Notification{method: method, params: params}, state) do
    dispatch_notification(state.notification_handler, method, params)
    {:noreply, state}
  end

  defp dispatch_notification(nil, method, _params),
    do: Logger.debug("MCP Client: unhandled notification: #{method}")

  defp dispatch_notification(pid, method, params) when is_pid(pid),
    do: send(pid, {:mcp_notification, method, params})

  defp dispatch_notification(fun, method, params) when is_function(fun, 2),
    do: fun.(method, params)

  # --- Sending ---

  defp send_rpc(state, from, method, params, kind \\ :call) do
    {id, state} = next_id(state)
    send_request(state, id, method, with_meta(params, state))
    timeout_ref = schedule_timeout(id, state.request_timeout)
    {:noreply, put_pending(state, id, from, timeout_ref, kind)}
  end

  # Every request carries the per-request _meta the stateless server needs in
  # place of the removed handshake (SEP-2575): protocol version + client
  # identity/capabilities. `server/discover` also carries it harmlessly.
  defp with_meta(params, state) do
    meta = %{
      "io.modelcontextprotocol/protocolVersion" => state.protocol_version,
      "io.modelcontextprotocol/clientInfo" => encode(state.client_info),
      "io.modelcontextprotocol/clientCapabilities" => encode(state.client_capabilities)
    }

    Map.put(params, "_meta", meta)
  end

  defp send_request(state, id, method, params) do
    state.transport_module.send_message(
      state.transport_pid,
      encode(Request.new(id, method, params))
    )
  end

  defp send_notification(state, method, params) do
    state.transport_module.send_message(
      state.transport_pid,
      encode(Notification.new(method, params))
    )
  end

  defp encode(struct), do: Jason.decode!(Jason.encode!(struct))

  defp put_pending(state, id, from, timeout_ref, kind) do
    pending =
      Map.put(state.pending_requests, id, %{from: from, timeout_ref: timeout_ref, kind: kind})

    %{state | pending_requests: pending}
  end

  defp next_id(state), do: {state.next_id, %{state | next_id: state.next_id + 1}}
  defp schedule_timeout(id, ms), do: Process.send_after(self(), {:request_timeout, id}, ms)
  defp cancel_timeout(ref), do: Process.cancel_timer(ref)

  defp cursor_params(opts) do
    if cursor = Keyword.get(opts, :cursor), do: %{"cursor" => cursor}, else: %{}
  end

  defp name_args(name, arguments) do
    params = %{"name" => name}
    if arguments && arguments != %{}, do: Map.put(params, "arguments", arguments), else: params
  end

  defp start_transport({module, opts}) do
    case module.start_link([{:owner, self()} | opts]) do
      {:ok, pid} -> {:ok, module, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  # Outbound extension declarations are validated here, at the one seam where a
  # consumer's `:client_capabilities` becomes something this SDK puts on the
  # wire. Invalid identifiers are dropped and an empty result becomes absent,
  # exactly as `MCP.Server.Config.build/2` does for the server's own
  # declaration — the SDK's outbound guarantee has to hold in both directions
  # or it is not a guarantee. Inbound declarations are never touched.
  defp build_client_capabilities(%ClientCapabilities{} = capabilities) do
    normalised =
      Extensions.normalise(capabilities.extensions,
        source: "MCP.Client.start_link/1 `:client_capabilities` extensions"
      )

    %{capabilities | extensions: normalised}
  end

  # Anything else is DISCARDED, loudly (MES-16 round 2, R-8). This clause used
  # to be `do: capabilities` — a pass-through, which meant a non-struct
  # `:client_capabilities` went into state untouched and straight to `encode/1`
  # on every request. Both halves of the round-1 property failed on that path:
  # a MUST-violating identifier reached the wire with no drop and no warning,
  # and an unencodable settings value let `start_link/1` succeed and then
  # killed the client on its FIRST request — the deferred failure the property
  # exists to rule out.
  #
  # A consumer is led here by the neighbour eleven lines below: `:client_info`
  # accepts `%Implementation{}` OR a plain map, so a plain map looks like the
  # house style. Mirroring that leniency was the tempting repair and is NOT
  # what this does. `%Implementation{}` has two fields a map can supply in
  # full; `%ClientCapabilities{}` has five, and a conversion that kept the keys
  # it recognised and dropped the rest would trade a known loud failure for a
  # fresh silent one. So: discard, warn, name what was lost, carry on with the
  # default — drop/warn/never raise/never defer, one level up from
  # `Extensions.normalise/2` and the same posture.
  defp build_client_capabilities(other) do
    Logger.warning(
      "MCP client capabilities — MCP.Client.start_link/1 `:client_capabilities`: expected a " <>
        "%MCP.Protocol.Capabilities.ClientCapabilities{}, got " <>
        "#{inspect(other, limit: 5, printable_limit: 120)}. The WHOLE value is DISCARDED and " <>
        "NOTHING it declared (roots, sampling, elicitation, experimental, extensions) is " <>
        "advertised; the default %ClientCapabilities{} is used instead. Unlike `:client_info`, " <>
        "this option does not accept a plain map."
    )

    %ClientCapabilities{}
  end

  defp build_client_info(%Implementation{} = impl), do: impl

  defp build_client_info(map) when is_map(map) do
    %Implementation{
      name: Map.get(map, :name) || Map.get(map, "name", "mcp_elixir_sdk"),
      version: Map.get(map, :version) || Map.get(map, "version", "1.0.0")
    }
  end

  defp default_info, do: %{name: "mcp_elixir_sdk", version: "1.0.0"}

  defp do_close(state) do
    if state.transport_pid, do: state.transport_module.close(state.transport_pid)
    {:stop, :normal, :ok, %{state | status: :closed}}
  catch
    _, _ -> {:stop, :normal, :ok, %{state | status: :closed}}
  end

  defp list_all(client, operation, items_key, opts),
    do: do_list_all(client, operation, items_key, opts, nil, [])

  defp do_list_all(client, operation, items_key, opts, cursor, acc) do
    call_opts = if cursor, do: Keyword.put(opts, :cursor, cursor), else: opts

    case apply_list_operation(client, operation, call_opts) do
      {:ok, result} ->
        items = Map.get(result, Atom.to_string(items_key), [])
        new_acc = acc ++ items

        case Map.get(result, "nextCursor") do
          nil -> {:ok, new_acc}
          next_cursor -> do_list_all(client, operation, items_key, opts, next_cursor, new_acc)
        end

      {:error, _} = error ->
        error
    end
  end

  defp apply_list_operation(client, :list_tools, opts), do: list_tools(client, opts)
  defp apply_list_operation(client, :list_resources, opts), do: list_resources(client, opts)

  defp apply_list_operation(client, :list_resource_templates, opts),
    do: list_resource_templates(client, opts)

  defp apply_list_operation(client, :list_prompts, opts), do: list_prompts(client, opts)
end

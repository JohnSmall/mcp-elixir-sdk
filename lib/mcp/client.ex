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
    * `:client_capabilities` — `%ClientCapabilities{}` (advertised in `_meta`)
    * `:protocol_version` — advertised version (default: the stateless core's)
    * `:notification_handler` — pid or `(method, params -> any)` for server
      notifications
    * `:on_input_required` — `(input_requests -> input_responses)` MRTR resolver
    * `:request_timeout` — default request timeout in ms (default: 30_000)
    * `:tool_schema_limit` — maximum cached tool schemas (default: 1,024)
  """

  use GenServer

  require Logger

  alias MCP.Protocol
  alias MCP.Protocol.Capabilities.ClientCapabilities
  alias MCP.Protocol.Error
  alias MCP.Protocol.Messages.{Discover, MRTR, Notification, Request, Response}
  alias MCP.Protocol.Methods
  alias MCP.Protocol.ToolRouting
  alias MCP.Protocol.Types.Implementation

  @default_request_timeout 30_000
  @max_tool_refresh_pages 32
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
    :tool_schema_index,
    :tool_schema_order,
    :tool_schema_limit,
    :pending_requests,
    :next_id,
    :request_timeout
  ]

  # --- Public API ---

  @doc "Starts the client GenServer and its transport."
  def start_link(opts) do
    {gen_opts, client_opts} = Keyword.split(opts, [:name])

    case validate_tool_schema_limit(client_opts) do
      :ok -> GenServer.start_link(__MODULE__, client_opts, gen_opts)
      {:error, reason} -> {:error, reason}
    end
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

  @doc """
  Calls a tool. Transparently completes MRTR round-trips when a resolver is set.

  Options: `:timeout` and `:input_schema`. The latter supplies the selected
  tool's input schema explicitly for routing-header derivation.
  """
  def call_tool(client, name, arguments \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    input_schema = Keyword.get(opts, :input_schema)

    GenServer.call(
      client,
      {:call_tool, name, arguments, input_schema},
      timeout || @default_request_timeout
    )
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
    tool_schema_limit = Keyword.get(opts, :tool_schema_limit, 1_024)

    if is_integer(tool_schema_limit) and tool_schema_limit >= 0 do
      init_with_schema_limit(opts, tool_schema_limit)
    else
      {:stop, {:invalid_tool_schema_limit, tool_schema_limit}}
    end
  end

  defp init_with_schema_limit(opts, tool_schema_limit) do
    {transport_spec, opts} = Keyword.pop!(opts, :transport)

    state = %__MODULE__{
      client_info: build_client_info(Keyword.get(opts, :client_info, default_info())),
      client_capabilities: Keyword.get(opts, :client_capabilities, %ClientCapabilities{}),
      protocol_version: Keyword.get(opts, :protocol_version, @protocol_version),
      status: :ready,
      notification_handler: Keyword.get(opts, :notification_handler),
      on_input_required: Keyword.get(opts, :on_input_required),
      tool_schema_index: %{},
      tool_schema_order: [],
      tool_schema_limit: tool_schema_limit,
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
    do: send_rpc(state, from, Methods.tools_list(), cursor_params(opts), :tools_list)

  def handle_call({:call_tool, name, arguments, input_schema}, from, state) do
    case selected_descriptors(state, name, input_schema) do
      {:ok, descriptors, state} ->
        send_rpc(
          state,
          from,
          Methods.tools_call(),
          name_args(name, arguments),
          {:tool_call, name, arguments, false, descriptors},
          routing_headers: descriptors
        )

      {:error, reason} ->
        {:reply, {:error, {:invalid_input_schema, reason}}, state}
    end
  end

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

  # A recognized custom-header mismatch can mean the cached schema is stale.
  # Refresh once, then retry the original call with the newly selected descriptors.
  defp finish_response(
         %Response{error: error},
         from,
         {:tool_call, name, arguments, false, descriptors},
         state
       )
       when error != nil do
    if recognized_custom_header_mismatch?(error, descriptors) do
      send_rpc(
        state,
        from,
        Methods.tools_list(),
        %{},
        {:tool_header_refresh, name, arguments, error, new_refresh_state(state)}
      )
    else
      GenServer.reply(from, {:error, error})
      {:noreply, state}
    end
  end

  # tools/call result → complete transparently through MRTR when input is required.
  defp finish_response(%Response{error: error} = _resp, from, _kind, state) when error != nil do
    GenServer.reply(from, {:error, error})
    {:noreply, state}
  end

  defp finish_response(
         %Response{result: result},
         from,
         {:tool_call, name, arguments, refresh_attempted?, descriptors},
         state
       ) do
    if input_required?(result) and is_function(state.on_input_required, 1) do
      resume_mrtr(result, from, name, arguments, refresh_attempted?, descriptors, state)
    else
      GenServer.reply(from, {:ok, result})
      {:noreply, state}
    end
  end

  defp finish_response(
         %Response{result: result},
         from,
         {:tool_header_refresh, name, arguments, original_error, refresh},
         state
       ) do
    case tools_from_result(result) do
      {:ok, tools} ->
        state = cache_tools(state, tools)

        case Enum.find(tools, &(Map.get(&1, "name") == name)) do
          nil ->
            continue_tool_refresh(
              result,
              from,
              name,
              arguments,
              original_error,
              refresh,
              state
            )

          selected_tool ->
            state = cache_tools(state, [selected_tool])
            {descriptors, state} = cached_descriptors(state, name)

            send_rpc(
              state,
              from,
              Methods.tools_call(),
              name_args(name, arguments),
              {:tool_call, name, arguments, true, descriptors},
              routing_headers: descriptors
            )
        end

      {:error, reason} ->
        GenServer.reply(from, {:error, {:invalid_tools_result, reason}})
        {:noreply, state}
    end
  end

  defp finish_response(%Response{result: result}, from, :tools_list, state) do
    case tools_from_result(result) do
      {:ok, tools} ->
        state = cache_tools(state, tools)
        GenServer.reply(from, {:ok, Map.put(result, "tools", tools)})
        {:noreply, state}

      {:error, reason} ->
        GenServer.reply(from, {:error, {:invalid_tools_result, reason}})
        {:noreply, state}
    end
  end

  defp finish_response(%Response{result: result}, from, _kind, state) do
    GenServer.reply(from, {:ok, result})
    {:noreply, state}
  end

  defp valid_header_annotation_locations?(%{"name" => name} = tool) when is_binary(name) do
    valid? =
      case Map.fetch(tool, "inputSchema") do
        {:ok, %{"type" => "object"} = schema} ->
          match?({:ok, _descriptors}, ToolRouting.descriptors(schema))

        _missing_or_invalid ->
          false
      end

    unless valid? do
      Logger.warning(
        "MCP Client: excluding tool #{inspect(name)}: invalid inputSchema or x-mcp-header annotation"
      )
    end

    valid?
  end

  defp valid_header_annotation_locations?(tool) do
    Logger.warning("MCP Client: excluding malformed tool catalog entry: #{inspect(tool)}")
    false
  end

  defp tool_index_entry(%{"name" => name, "inputSchema" => schema}) do
    {:ok, descriptors} = ToolRouting.descriptors(schema)
    {name, descriptors}
  end

  defp cache_tools(state, tools) do
    Enum.reduce(tools, state, fn tool, acc ->
      {name, descriptors} = tool_index_entry(tool)
      order = Enum.reject(acc.tool_schema_order, &(&1 == name)) ++ [name]
      index = Map.put(acc.tool_schema_index, name, descriptors)
      trim_tool_index(%{acc | tool_schema_index: index, tool_schema_order: order})
    end)
  end

  defp trim_tool_index(state) when length(state.tool_schema_order) > state.tool_schema_limit do
    [evicted | order] = state.tool_schema_order

    %{
      state
      | tool_schema_index: Map.delete(state.tool_schema_index, evicted),
        tool_schema_order: order
    }
  end

  defp trim_tool_index(state), do: state

  defp cached_descriptors(state, name) do
    case Map.fetch(state.tool_schema_index, name) do
      {:ok, descriptors} ->
        order = Enum.reject(state.tool_schema_order, &(&1 == name)) ++ [name]
        {descriptors, %{state | tool_schema_order: order}}

      :error ->
        {[], state}
    end
  end

  defp selected_descriptors(state, name, nil) do
    {descriptors, state} = cached_descriptors(state, name)
    {:ok, descriptors, state}
  end

  defp selected_descriptors(state, _name, input_schema) do
    case ToolRouting.descriptors(input_schema) do
      {:ok, descriptors} -> {:ok, descriptors, state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp recognized_custom_header_mismatch?(error, _descriptors) do
    detail = error.data |> inspect() |> String.downcase()

    error.code == Error.header_mismatch_code() and
      String.contains?(detail, "mcp-param-")
  end

  defp tools_from_result(result) when is_map(result) do
    case Map.fetch(result, "tools") do
      {:ok, tools} when is_list(tools) ->
        {:ok, Enum.filter(tools, &valid_header_annotation_locations?/1)}

      {:ok, _invalid} ->
        {:error, :tools_must_be_a_list}

      :error ->
        {:error, :missing_tools}
    end
  end

  defp tools_from_result(_result), do: {:error, :result_must_be_an_object}

  defp new_refresh_state(state) do
    %{
      seen_cursors: MapSet.new(),
      pages_remaining: @max_tool_refresh_pages,
      deadline: System.monotonic_time(:millisecond) + state.request_timeout
    }
  end

  defp continue_tool_refresh(
         result,
         from,
         name,
         arguments,
         original_error,
         refresh,
         state
       ) do
    cursor = Map.get(result, "nextCursor")
    remaining_timeout = refresh.deadline - System.monotonic_time(:millisecond)

    if is_binary(cursor) and refresh.pages_remaining > 0 and remaining_timeout > 0 and
         not MapSet.member?(refresh.seen_cursors, cursor) and caller_alive?(from) do
      next_refresh = %{
        refresh
        | seen_cursors: MapSet.put(refresh.seen_cursors, cursor),
          pages_remaining: refresh.pages_remaining - 1
      }

      send_rpc_with_timeout(
        state,
        from,
        Methods.tools_list(),
        %{"cursor" => cursor},
        {:tool_header_refresh, name, arguments, original_error, next_refresh},
        [],
        remaining_timeout
      )
    else
      GenServer.reply(from, {:error, original_error})
      {:noreply, state}
    end
  end

  defp caller_alive?({pid, _tag}) when is_pid(pid), do: Process.alive?(pid)

  defp input_required?(result), do: Map.get(result, "resultType") == MRTR.result_type()

  # Fulfil the requested inputs and retry the original tools/call carrying the
  # server's requestState + the resolved inputResponses (SEP-2322).
  defp resume_mrtr(
         result,
         from,
         name,
         arguments,
         refresh_attempted?,
         descriptors,
         state
       ) do
    responses = state.on_input_required.(Map.get(result, "inputRequests"))

    params =
      name
      |> name_args(arguments)
      |> Map.put("requestState", Map.get(result, "requestState"))
      |> Map.put("inputResponses", responses)

    send_rpc(
      state,
      from,
      Methods.tools_call(),
      params,
      {:tool_call, name, arguments, refresh_attempted?, descriptors},
      routing_headers: descriptors
    )
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

  defp send_rpc(state, from, method, params, kind \\ :call, transport_opts \\ []) do
    send_rpc_with_timeout(
      state,
      from,
      method,
      params,
      kind,
      transport_opts,
      state.request_timeout
    )
  end

  defp send_rpc_with_timeout(state, from, method, params, kind, transport_opts, timeout) do
    {id, state} = next_id(state)

    case send_request(state, id, method, with_meta(params, state), transport_opts) do
      :ok ->
        timeout_ref = schedule_timeout(id, timeout)
        {:noreply, put_pending(state, id, from, timeout_ref, kind)}

      {:error, reason} ->
        GenServer.reply(from, {:error, reason})
        {:noreply, state}
    end
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

  defp send_request(state, id, method, params, opts) do
    message = encode(Request.new(id, method, params))

    if function_exported?(state.transport_module, :send_message, 3) do
      state.transport_module.send_message(state.transport_pid, message, opts)
    else
      state.transport_module.send_message(state.transport_pid, message)
    end
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

  defp build_client_info(%Implementation{} = impl), do: impl

  defp build_client_info(map) when is_map(map) do
    %Implementation{
      name: Map.get(map, :name) || Map.get(map, "name", "mcp_elixir_sdk"),
      version: Map.get(map, :version) || Map.get(map, "version", "1.0.0")
    }
  end

  defp default_info, do: %{name: "mcp_elixir_sdk", version: "1.0.0"}

  defp validate_tool_schema_limit(opts) do
    limit = Keyword.get(opts, :tool_schema_limit, 1_024)

    if is_integer(limit) and limit >= 0,
      do: :ok,
      else: {:error, {:invalid_tool_schema_limit, limit}}
  end

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

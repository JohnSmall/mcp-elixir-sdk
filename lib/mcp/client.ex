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

  `requestState` is echoed on the retry **only when the server sent one**: an
  absent field and an explicit `null` both mean "no state", and the client MUST
  NOT include the key in either case.

  ## Custom headers from tool parameters (SEP-2243)

  On the Streamable HTTP transport, a server may annotate `inputSchema`
  properties with `x-mcp-header` and the client **MUST** mirror those argument
  values into `Mcp-Param-*` headers. Three consequences worth knowing:

    * **`tools/list` populates a schema cache.** Mirroring needs the tool's
      `inputSchema`, so `call_tool/4` mirrors only for tools this client has
      listed. A cursor-less listing resets the cache; a cursor-bearing page
      merges into it, so `list_all_tools/2` accumulates rather than discarding.
    * **A miss is announced, not silent.** Calling a tool that was never listed
      sends no `Mcp-Param-*` headers and logs a warning naming the tool (once
      per name). If the server needs them it answers `-32020` HeaderMismatch,
      and the client then does what the spec prescribes: refresh via
      `tools/list` and retry the call once. The same recovery covers a cached
      schema that has gone **stale**, which has no local signal at all.
    * **Invalid tools are excluded.** A tool whose annotations violate the
      SEP-2243 constraints is dropped from `list_tools/2`'s result — a
      requirement, not a choice. Because that makes the list silently shorter,
      `excluded_tools/1` reports what went and why.

  ## Protocol version

  Every request carries the version in `_meta`, and the HTTP transport derives
  the `MCP-Protocol-Version` header from that same field, so the two cannot
  disagree. If a server answers `-32022` offering a version this SDK supports,
  the client selects it and retries **once**
  (`basic/versioning.mdx:69-71`); an offer containing nothing we implement is
  surfaced to the caller rather than negotiated down.

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
  alias MCP.Protocol.Error
  alias MCP.Protocol.Extensions
  alias MCP.Protocol.HeaderMirror
  alias MCP.Protocol.Messages.{Discover, MRTR, Notification, Request, Response}
  alias MCP.Protocol.Methods
  alias MCP.Protocol.Types.Implementation

  @default_request_timeout 30_000
  @protocol_version "2026-07-28"

  # Every protocol version this SDK implements. The stateless core is the only
  # one: ADR-003 sub-decision 5 declines a 2025-11-25 fallback, so a version
  # retry can only ever re-select the version we already speak.
  @supported_versions [@protocol_version]

  @protocol_version_meta_key "io.modelcontextprotocol/protocolVersion"

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
    :request_timeout,
    :tool_annotations,
    :excluded_tools,
    :mirror_misses_warned
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

  @doc """
  Tools dropped from the most recent `tools/list`, as `[{name, reason}]` sorted
  by name.

  A client using the Streamable HTTP transport **MUST** exclude a tool whose
  `x-mcp-header` annotations violate the SEP-2243 constraints
  (`server/tools.mdx:360-366`), so `list_tools/2` can legitimately return fewer
  tools than the server sent, with no error. The spec asks for a log line; this
  goes further and keeps the answer queryable, because an operator whose tool
  vanished should be able to **ask** where it went rather than grep for a line
  that may have scrolled away.

  Follows the same reset/merge rule as the schema cache: a cursor-less
  `tools/list` replaces the record, a cursor-bearing one adds to it.
  """
  @spec excluded_tools(GenServer.server()) :: [{String.t(), String.t()}]
  def excluded_tools(client), do: GenServer.call(client, :get_excluded_tools)

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
      request_timeout: Keyword.get(opts, :request_timeout, @default_request_timeout),
      tool_annotations: %{},
      excluded_tools: %{},
      mirror_misses_warned: MapSet.new()
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

  def handle_call(:get_excluded_tools, _from, state),
    do: {:reply, state.excluded_tools |> Enum.sort_by(&elem(&1, 0)), state}

  def handle_call(_request, _from, %{status: :closed} = state),
    do: {:reply, {:error, :closed}, state}

  def handle_call({:list_tools, opts}, from, state),
    do:
      send_rpc(
        state,
        from,
        Methods.tools_list(),
        cursor_params(opts),
        {:list_tools, Keyword.get(opts, :cursor)}
      )

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
      {%{timeout_ref: ref} = entry, pending} ->
        cancel_timeout(ref)
        route_response(response, entry, %{state | pending_requests: pending})

      {nil, _} ->
        Logger.warning("MCP Client: response for unknown request id=#{inspect(id)}")
        {:noreply, state}
    end
  end

  # An error response gets one chance to be recovered before it reaches the
  # caller. Both recoveries are spec SHOULDs, both are one-shot, and both are
  # tried in this one place so no kind-specific clause can miss them.
  #
  # First, though: a failed refresh must not replace the caller's answer with a
  # different question's error. They asked for a tools/call, and the true
  # answer is the server's -32020 — not "tools/list also failed".
  defp route_response(
         %Response{error: %Error{} = refresh_error},
         %{kind: {:refresh_for_retry, entry, original_error}},
         state
       ) do
    Logger.warning(
      "MCP Client: the tools/list refresh after -32020 itself failed " <>
        "(#{inspect(refresh_error.code)} #{refresh_error.message}); surfacing the original " <>
        "HeaderMismatch to the caller."
    )

    GenServer.reply(entry.from, {:error, original_error})
    {:noreply, state}
  end

  defp route_response(%Response{error: %Error{} = error}, entry, state) do
    cond do
      (version = retryable_version(error, entry, state)) != nil ->
        retry_with_version(entry, version, state)

      header_mismatch_retry?(error, entry) ->
        refresh_schemas_and_retry(entry, error, state)

      true ->
        GenServer.reply(entry.from, {:error, error})
        {:noreply, state}
    end
  end

  defp route_response(%Response{} = response, entry, state),
    do: finish_response(response, entry.from, entry.kind, state)

  # -32022 UnsupportedProtocolVersion. `basic/versioning.mdx:69-71`: "The client
  # SHOULD select a mutually supported version from the `supported` list and
  # retry the request, or surface an error to the user if no compatible version
  # exists." A SHOULD in the normative text — NOT an inference from the harness
  # check named `sep-2575-client-retry-supported-version`, which is evidence of
  # what is tested rather than of what is required.
  #
  # The selection is an intersection with what this SDK actually implements, so
  # ADR-003 sub-decision 5 is untouched: `@supported_versions` holds the
  # stateless core alone, and the retry can never reach for 2025-11-25 however
  # generous the server's `supported` list is. No compatible version means no
  # retry and the error goes to the caller, which is the same sentence's other
  # half.
  defp retryable_version(%Error{code: -32_022, data: %{"supported" => supported}}, entry, _state)
       when is_list(supported) do
    if entry.retries.version, do: nil, else: Enum.find(supported, &(&1 in @supported_versions))
  end

  defp retryable_version(_error, _entry, _state), do: nil

  defp retry_with_version(entry, version, state) do
    Logger.info(
      "MCP Client: server rejected protocol version " <>
        "#{inspect(state.protocol_version)} with -32022; selecting #{inspect(version)} from " <>
        "its supported list and issuing a one-shot retry of #{entry.method}."
    )

    state = %{state | protocol_version: version}

    dispatch(
      state,
      entry.from,
      entry.method,
      restamp_version(entry.params, version),
      entry.kind,
      %{entry.retries | version: true}
    )
  end

  # -32020 HeaderMismatch on a tools/call. `streamable-http.mdx:533-539`: the
  # client SHOULD call `tools/list` to check for changes to the tool's
  # `inputSchema`, then retry the original request with the appropriate
  # headers. This is the recovery for BOTH halves of the cache problem — a
  # schema we never had, and one that has gone stale — which is why the miss
  # path can afford not to list eagerly.
  defp header_mismatch_retry?(%Error{code: -32_020}, %{kind: {:tool_call, _, _}} = entry),
    do: not entry.retries.headers

  defp header_mismatch_retry?(_error, _entry), do: false

  defp refresh_schemas_and_retry(entry, error, state) do
    Logger.info(
      "MCP Client: -32020 HeaderMismatch on tools/call; refreshing the tool's inputSchema " <>
        "via tools/list and retrying once (streamable-http.mdx:533-539)."
    )

    # A cursor-less list, so it resets the cache rather than merging into it.
    # BOUND, stated rather than left implicit: this fetches the FIRST PAGE
    # ONLY. A tool that lives on a later page is not found, the retry goes out
    # unmirrored, and the server's second rejection reaches the caller —
    # correct, but one round trip more expensive than it needed to be.
    dispatch(
      state,
      entry.from,
      Methods.tools_list(),
      with_meta(%{}, state),
      {:refresh_for_retry, entry, error},
      %{version: false, headers: false}
    )
  end

  # server/discover result → capability probe reply.
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

  # tools/list result → validate the SEP-2243 annotations, drop the tools that
  # violate them, cache the rest, and reply with the filtered listing.
  defp finish_response(%Response{result: result}, from, {:list_tools, cursor}, state)
       when is_map(result) do
    {kept, annotations, excluded} = partition_tools(Map.get(result, "tools"))
    state = update_tool_cache(state, cursor, annotations, excluded)
    GenServer.reply(from, {:ok, Map.put(result, "tools", kept)})
    {:noreply, state}
  end

  # A `tools/list` answered with a non-object `result` (`"result": null` and
  # `"result": "oops"` both decode to a well-formed Response — `protocol.ex:63`
  # requires only the `result` KEY, not an object under it). Without this clause
  # the `Map.get/2` above raises `BadMapError` inside the GenServer, and a
  # remote peer would kill the client, every OTHER pending request and the
  # linked transport with one bad field. So: reply to the caller and stay up.
  #
  # The reply is an ERROR, not `{:ok, nil}`: the caller asked for a listing and
  # must be able to tell "the server sent something unusable" from "the server
  # has no tools". The malformed term rides along so the operator can see what
  # actually arrived.
  defp finish_response(%Response{result: result}, from, {:list_tools, _cursor}, state) do
    Logger.warning(
      "MCP Client: tools/list answered with a non-object result " <>
        "(#{inspect(result, limit: 5, printable_limit: 120)}); the listing cannot be " <>
        "validated or cached, so the request fails and the tool caches are left untouched."
    )

    GenServer.reply(from, {:error, {:malformed_result, result}})
    {:noreply, state}
  end

  # The refresh issued by the HeaderMismatch recovery: absorb the schemas, then
  # re-send the ORIGINAL tools/call, which now picks the fresh annotations up
  # through the normal send path.
  defp finish_response(
         %Response{result: result},
         _from,
         {:refresh_for_retry, entry, _error},
         state
       )
       when is_map(result) do
    {_kept, annotations, excluded} = partition_tools(Map.get(result, "tools"))
    state = update_tool_cache(state, nil, annotations, excluded)

    dispatch(state, entry.from, entry.method, entry.params, entry.kind, %{
      entry.retries
      | headers: true
    })
  end

  # M-5. The same non-object `result` as the tools/list clause above, on the
  # refresh this ticket's -32020 recovery introduced. Unguarded it raised
  # `BadMapError` inside the GenServer, so a server that answers a `tools/call`
  # with `-32020` and the follow-up `tools/list` with `"result": null` killed
  # the client and every other pending request — a path that does not exist on
  # `main` at all, unlike the pre-existing siblings (MES-42).
  #
  # WHICH ERROR THE CALLER SEES, chosen deliberately. Two rules pull opposite
  # ways here and both are satisfied rather than one being dropped:
  #
  #   * the failed-refresh clause at `route_response/3` surfaces the ORIGINAL
  #     -32020, because "tools/list also failed" answers a different question
  #     than the one the caller asked; and
  #   * "the refresh came back unusable" must not be indistinguishable from
  #     "the refresh found no tools" — which ends in a bare `-32020` from the
  #     server's second rejection, one round trip later.
  #
  # So the reply carries BOTH: a tag naming the refresh as malformed, the term
  # that arrived, and the caller's own true answer, the original HeaderMismatch.
  # A caller that only cares about the tool call still finds its `%Error{}`.
  # The tag differs from the tools/list clause's `:malformed_result` because
  # the situation differs — that one failed the request the caller made, this
  # one failed a request the client made on their behalf.
  #
  # The caches are left untouched for the M-1 reason: a garbage listing is not
  # a listing, and a cursor-less refresh RESETS the cache — absorbing this one
  # would wipe every good annotation on the strength of an unusable response.
  defp finish_response(
         %Response{result: result},
         _from,
         {:refresh_for_retry, entry, original_error},
         state
       ) do
    Logger.warning(
      "MCP Client: the tools/list refresh after -32020 answered with a non-object result " <>
        "(#{inspect(result, limit: 5, printable_limit: 120)}); the schemas cannot be " <>
        "refreshed, so the retry is abandoned, the tool caches are left untouched and the " <>
        "original HeaderMismatch is returned alongside the malformed term."
    )

    GenServer.reply(entry.from, {:error, {:malformed_refresh_result, result, original_error}})
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
      |> put_request_state(result)
      |> Map.put("inputResponses", responses)
      |> with_meta(state)

    dispatch(state, from, Methods.tools_call(), params, {:tool_call, name, arguments}, %{
      version: false,
      headers: false
    })
  end

  # The retry carries `requestState` **only when the server sent one** (D-1).
  # This was an unconditional `Map.put`, which put an Elixir `nil` — a PRESENT
  # key holding JSON `null` — whenever the server had sent no state. The
  # `sep-2322-client-no-state-omitted` check tests presence, not value
  # (`requestState !== undefined`), and JSON `null` decodes to JS `null`, which
  # is `!== undefined`; so the client failed a scored scenario the gap register
  # recorded as CONFORMANT.
  #
  # An explicit `null` from the server is treated the same as an absent field,
  # deliberately: both mean the server sent no state, and the check is about
  # whether the key is there.
  defp put_request_state(params, result) do
    case Map.get(result, "requestState") do
      nil -> params
      state -> Map.put(params, "requestState", state)
    end
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
    dispatch(state, from, method, with_meta(params, state), kind, %{
      version: false,
      headers: false
    })
  end

  # The one send path. A transport that refuses the message fails the CALLER,
  # here and now, with the transport's own reason (D-2): the previous code
  # discarded `send_message/2`'s return value and registered the request as
  # pending regardless, so a 400, a refused connection or a rejected
  # content-coding all surfaced as `{:error, :timeout}` after the full
  # `request_timeout` with the real reason only in a log line. It also matters
  # for conformance and not just ergonomics — a scenario that rejects the first
  # request and waits for a retry gets a 30-second stall instead, and a client
  # timeout fails a scenario outright.
  #
  # Nothing is registered as pending on a failed send, so no timeout is
  # scheduled for a request that was never sent and cannot be replied to twice.
  defp dispatch(state, from, method, params, kind, retries) do
    {id, state} = next_id(state)
    {opts, state} = send_opts(state, method, params)

    case send_request(state, id, method, params, opts) do
      :ok ->
        timeout_ref = schedule_timeout(id, state.request_timeout)

        {:noreply,
         put_pending(state, id, from, timeout_ref, kind, %{
           method: method,
           params: params,
           retries: retries
         })}

      {:error, reason} ->
        GenServer.reply(from, {:error, {:transport_send_failed, reason}})
        {:noreply, state}
    end
  end

  # `Mcp-Param-*` mirroring (SEP-2243) cannot be derived in the transport: it
  # needs the called tool's `inputSchema`, which only this process holds. The
  # headers are therefore computed here and handed down as per-message opts.
  defp send_opts(state, method, params) do
    if method == Methods.tools_call() do
      tool_call_opts(state, Map.get(params, "name"), Map.get(params, "arguments") || %{})
    else
      {[], state}
    end
  end

  defp tool_call_opts(state, name, arguments) when is_binary(name) do
    case Map.fetch(state.tool_annotations, name) do
      {:ok, annotations} ->
        {[headers: HeaderMirror.headers_for(annotations, arguments)], state}

      :error ->
        {[], warn_mirror_miss(state, name)}
    end
  end

  defp tool_call_opts(state, _name, _arguments), do: {[], state}

  # The cache-miss policy, stated rather than defaulted (MES-18 C-2). A caller
  # may legitimately call a tool it never listed — nothing in this SDK requires
  # `tools/list` first and the protocol is stateless — so a miss is a normal
  # event, not an error, and failing the call would break working code.
  #
  # We do NOT list implicitly: that would spend a round trip on every cold call
  # whether or not the tool has annotations. What we do instead is (a) say so,
  # once per tool name, so the omission is visible rather than silent — a
  # request with no `Mcp-Param-*` headers is otherwise indistinguishable on the
  # wire from a tool that has none — and (b) recover through the spec's own
  # path when it turns out to matter: a `-32020` HeaderMismatch triggers a
  # `tools/list` refresh and one retry (`streamable-http.mdx:533-539`). The
  # same mechanism covers a STALE cached schema, which is the other half of the
  # problem and has no local signal at all.
  defp warn_mirror_miss(state, name) do
    if MapSet.member?(state.mirror_misses_warned, name) do
      state
    else
      Logger.warning(
        "MCP Client: calling tool #{inspect(name)} with no cached inputSchema, so NO " <>
          "Mcp-Param-* headers were mirrored for it (SEP-2243). Call list_tools/2 first to " <>
          "mirror annotated arguments. Harmless on a transport without headers (e.g. stdio), " <>
          "and recoverable on HTTP: a -32020 HeaderMismatch triggers a refresh and one retry."
      )

      %{state | mirror_misses_warned: MapSet.put(state.mirror_misses_warned, name)}
    end
  end

  # Every request carries the per-request _meta the stateless server needs in
  # place of the removed handshake (SEP-2575): protocol version + client
  # identity/capabilities. `server/discover` also carries it harmlessly.
  defp with_meta(params, state) do
    meta = %{
      @protocol_version_meta_key => state.protocol_version,
      "io.modelcontextprotocol/clientInfo" => encode(state.client_info),
      "io.modelcontextprotocol/clientCapabilities" => encode(state.client_capabilities)
    }

    Map.put(params, "_meta", meta)
  end

  # Re-stamps only the version, leaving the rest of `_meta` as it was — used by
  # the -32022 retry, where everything but the version is unchanged.
  defp restamp_version(params, version) do
    meta = params |> Map.get("_meta", %{}) |> Map.put(@protocol_version_meta_key, version)
    Map.put(params, "_meta", meta)
  end

  defp send_request(state, id, method, params, opts) do
    send_via_transport(state, encode(Request.new(id, method, params)), opts)
  end

  # `send_message/3` is optional on the behaviour: a transport that does not
  # export it keeps working through `/2` and simply carries no per-message
  # options. That is what makes this an addition rather than a breaking change
  # for a third-party transport.
  defp send_via_transport(state, message, []),
    do:
      state.transport_module.send_message(
        state.transport_pid,
        message
      )

  defp send_via_transport(state, message, opts) do
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

  # The pending entry carries the request itself (method + params) as well as
  # the caller, because a retry has to re-send it: both recoveries — the -32022
  # version retry and the -32020 refresh — reconstruct the original request
  # from here rather than asking the caller to send it again.
  defp put_pending(state, id, from, timeout_ref, kind, request) do
    entry =
      Map.merge(request, %{from: from, timeout_ref: timeout_ref, kind: kind})

    %{state | pending_requests: Map.put(state.pending_requests, id, entry)}
  end

  # --- Tool schema cache and SEP-2243 exclusion ---

  # Splits a `tools/list` payload into the tools a caller may see, the
  # annotations to mirror for them, and the ones excluded with the reason.
  defp partition_tools(tools) when is_list(tools) do
    Enum.reduce(tools, {[], %{}, %{}}, fn tool, {kept, annotations, excluded} ->
      name = if is_map(tool), do: Map.get(tool, "name"), else: nil

      case HeaderMirror.validate_tool(tool) do
        {:ok, found} ->
          {[tool | kept], Map.put(annotations, name, found), excluded}

        {:error, reason} ->
          sentence = HeaderMirror.describe(reason)

          # SHOULD-level in the spec (`server/tools.mdx:362-364`): log the tool
          # name and the reason. `excluded_tools/1` keeps the same fact
          # queryable, because a dropped tool is a silent capability reduction
          # and a log line alone leaves the operator grepping.
          Logger.warning(
            "MCP Client: EXCLUDING tool #{inspect(name)} from tools/list — #{sentence}. " <>
              "A client on the Streamable HTTP transport MUST reject a tool definition whose " <>
              "x-mcp-header annotations are invalid (SEP-2243); the other tools are " <>
              "unaffected. See MCP.Client.excluded_tools/1."
          )

          {kept, annotations, Map.put(excluded, name, sentence)}
      end
    end)
    |> then(fn {kept, annotations, excluded} -> {Enum.reverse(kept), annotations, excluded} end)
  end

  defp partition_tools(_not_a_list), do: {[], %{}, %{}}

  # A cursor-bearing `tools/list` is a PAGE, not a listing: `list_all_tools/2`
  # walks `nextCursor`, so replacing the cache per response would leave it
  # holding only the last page. Reset on a cursor-less request, merge on a
  # cursor-bearing one.
  #
  # `mirror_misses_warned` shares the cache's GENERATION, so it resets here and
  # is left alone in the merge clause below. It records "we have already told
  # the operator about this name" — a statement about the CURRENT cache. When a
  # cursor-less listing replaces that cache, a tool the new listing does not
  # carry is a fresh omission the operator has not been told about, and without
  # this reset the sequence warn → list → list-without-it → call goes silent:
  # the one operator who missed the first line never gets another.
  defp update_tool_cache(state, nil, annotations, excluded),
    do: %{
      state
      | tool_annotations: annotations,
        excluded_tools: excluded,
        mirror_misses_warned: MapSet.new()
    }

  defp update_tool_cache(state, _cursor, annotations, excluded) do
    %{
      state
      | tool_annotations: Map.merge(state.tool_annotations, annotations),
        excluded_tools: Map.merge(state.excluded_tools, excluded)
    }
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

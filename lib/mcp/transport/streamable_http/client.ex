defmodule MCP.Transport.StreamableHTTP.Client do
  @moduledoc """
  Streamable HTTP client transport for MCP.

  Sends JSON-RPC messages via HTTP POST and receives responses as either
  `application/json` or `text/event-stream` (SSE).

  > #### It cannot consume a long-lived stream {: .warning}
  >
  > This transport parses a **complete** SSE body returned by a blocking
  > request, so it can read a batch of notifications followed by a response,
  > but it can never receive a second message on a stream that stays open. A
  > `subscriptions/listen` stream is therefore not consumable by this client —
  > incremental client-side streaming is **MES-38**. (It was MES-18's until
  > that ticket's sizing split it out: consuming a held-open stream needs a
  > second execution mode for this transport, because `handle_call/3` performs
  > the POST synchronously inside the GenServer and a held-open response would
  > block every other request on the same client.)
  >
  > An earlier version of this paragraph claimed the client "optionally opens a
  > GET SSE stream for server-initiated messages". It does not, and the server
  > no longer offers a GET endpoint to open.

  ## Options

    * `:owner` (required) — pid to receive `{:mcp_message, map}` and
      `{:mcp_transport_closed, reason}` messages
    * `:url` (required) — the MCP endpoint URL (e.g., "http://localhost:8080/mcp")
    * `:headers` — extra HTTP headers to include on all requests. **Static**,
      captured at `start_link/1`; for a credential that rotates use
      `:header_provider`.
    * `:header_provider` — a 0-arity function called **per request**, returning
      `[{name, value}]` to append to that request's headers. This is the
      rotating-bearer seam: a token that expires between requests cannot be
      supplied through `:headers`, which is read once. See
      "Header provider failure contract" below.
    * `:header_provider_timeout` — ms to wait for `:header_provider` before
      failing the request (default: 5_000)
    * `:protocol_version` — MCP protocol version used when a message carries no
      version of its own (default: the stateless core's)

  ## Routing headers (SEP-2243)

  Every POST carries `Mcp-Method`, and the three name-bearing methods carry
  `Mcp-Name` — `params.name` for `tools/call` and `prompts/get`, `params.uri`
  for `resources/read` (`streamable-http.mdx:286-292`). Both are **REQUIRED
  for compliance**; they let a gateway route without parsing the body.

  A name outside the header-safe set is carried with the Base64 sentinel
  (`streamable-http.mdx:486-492`) — tool and prompt names are only
  SHOULD-constrained to header-safe characters, so a non-ASCII name is
  legitimate and must still be routable.

  Both headers are derived from the **same message map** that is serialised
  into the body, inside one function call, so they cannot drift from it.

  > #### Do not put a routing header in `:headers` {: .warning}
  >
  > `:headers` entries are appended, not merged, so a caller-supplied
  > `mcp-method`/`mcp-name`/`mcp-protocol-version` produces two field lines for
  > that name. A server taking the first sees the SDK's; an intermediary taking
  > the last may see the caller's, and the two disagreeing is exactly what
  > `-32020` exists to catch. `start_link/1` logs a warning naming the header.

  ## Header provider failure contract

  The provider runs on the request path of a transport that `MCP.Client` links
  to, so an unhandled failure there would take the client down with it. It is
  therefore run in a **separate, unlinked process** (`spawn_monitor/1`) with a
  bounded wait, and every outcome is turned into a failed **request**, never a
  failed transport:

    * raise / throw / exit → `{:error, {:header_provider_failed, reason}}`
    * a return value that is not a list of `{binary, binary}` →
      `{:error, {:header_provider_failed, {:invalid_headers, term}}}`, with no
      partial use of a half-valid list
    * no answer within `:header_provider_timeout` →
      `{:error, {:header_provider_failed, :timeout}}`

  A hang is the case `try` cannot catch, and it is the one that matters most:
  `send_message/2` is a synchronous `GenServer.call`, so without a bound a
  hung provider would block this transport *and* `MCP.Client` behind it.

  > #### Not a `Task` — the link is the defect {: .warning}
  >
  > `Task.async/1` **links**, and this transport does not trap exits, so a
  > provider process killed outright (`Process.exit(pid, :kill)`, which `catch`
  > cannot intercept) would come back down the link and take the transport with
  > it — the exact outcome this contract promises cannot happen. That is
  > measured, not argued: swapping the `spawn_monitor/1` for `Task.async/1`
  > turns the killed-provider and hanging-provider tests red, both with
  > `** (EXIT ...) killed` reaching the test process through the link. Do not
  > "tidy" it back into a `Task`.

  ## Stateless (2026-07-28)

  There is **no session**: the client sends no `MCP-Session-Id` and issues no
  DELETE on close (SEP-2567). Every POST is self-contained — the per-request
  `_meta` (protocol version, client identity/capabilities) is placed on the
  JSON-RPC message by `MCP.Client`, so any server instance can service it.

  ## Content coding

  The client sets `accept-encoding: identity` (RFC 9110 §12.5.3 — a request's
  `Accept-Encoding`; `identity` means "no encoding") and **does not decode
  compressed response bodies**. Automatic decompression in the underlying HTTP
  library is opt-in and unbounded (a decompression-bomb DoS, `EEF-CVE-2026-49755`),
  so this SDK declines content coding rather than enabling it. MCP 2026-07-28's
  Streamable HTTP transport does not specify content coding.

  A response whose `content-encoding` (RFC 9110 §8.4) carries any coding other than
  `identity` — across all field lines, compared case-insensitively per §8.4.1 — is
  **failed cleanly** with `{:error, {:unexpected_content_encoding, coding}}`, not
  mis-decoded. Tolerating a literal `identity` in a response is deliberate leniency:
  §8.4 says `identity` SHOULD NOT appear in a response's `Content-Encoding`, so a
  compliant peer never sends it, but accepting it harms nothing. This is a
  deliberate, documented client limitation, **not** a claim that a compressing peer
  is non-conformant (honoring `Accept-Encoding` is a §12.5.3 SHOULD, not a MUST).
  (Bounded decompression as an opt-in is a possible future enhancement.)

  > #### Caller-supplied `accept-encoding` breaks the client {: .warning}
  >
  > A `:headers` entry is **appended** to the SDK's own headers, not merged over
  > them — so `headers: [{"accept-encoding", "gzip"}]` makes the client advertise
  > `identity, gzip`. A peer that honors it returns `gzip`, which the guard then
  > refuses to decode, **hard-failing every request**. Do not set `accept-encoding`
  > in `:headers`. (The security posture is unaffected — the guard still refuses to
  > decode — so this is a documented constraint, not a decode path.)
  """

  use GenServer

  require Logger

  alias MCP.Protocol.HeaderMirror
  alias MCP.Transport.SSE

  @behaviour MCP.Transport

  @protocol_version "2026-07-28"
  @protocol_version_meta_key "io.modelcontextprotocol/protocolVersion"
  @default_header_provider_timeout 5_000

  # Headers the SDK derives from the message itself. A caller-supplied copy of
  # any of these can only disagree with the body.
  @reserved_headers ~w(mcp-method mcp-name mcp-protocol-version)

  defstruct [
    :owner,
    :url,
    :protocol_version,
    :extra_headers,
    :header_provider,
    :header_provider_timeout,
    :sse_task
  ]

  # --- Public API (Transport behaviour) ---

  @impl MCP.Transport
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl MCP.Transport
  def send_message(pid, message) when is_map(message) do
    send_message(pid, message, [])
  end

  @impl MCP.Transport
  def send_message(pid, message, opts) when is_map(message) and is_list(opts) do
    GenServer.call(pid, {:send_message, message, opts}, 60_000)
  end

  @impl MCP.Transport
  def close(pid) do
    GenServer.call(pid, :close)
  catch
    :exit, _ -> :ok
  end

  # --- GenServer callbacks ---

  @impl GenServer
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    url = Keyword.fetch!(opts, :url)
    protocol_version = Keyword.get(opts, :protocol_version, @protocol_version)
    extra_headers = Keyword.get(opts, :headers, [])

    warn_on_reserved_headers(extra_headers)

    state = %__MODULE__{
      owner: owner,
      url: url,
      protocol_version: protocol_version,
      extra_headers: extra_headers,
      header_provider: Keyword.get(opts, :header_provider),
      header_provider_timeout:
        Keyword.get(opts, :header_provider_timeout, @default_header_provider_timeout)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:send_message, message, opts}, _from, state) do
    # Send HTTP POST with the JSON-RPC message
    case do_post(state, message, opts) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:close, _from, state) do
    do_close(state)
    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_info({:sse_event, event}, state) do
    # SSE event received from a background stream (GET or POST SSE response)
    case Map.get(event, :data) do
      nil ->
        {:noreply, state}

      "" ->
        # Priming event with empty data — ignore
        {:noreply, state}

      data ->
        case Jason.decode(data) do
          {:ok, decoded} ->
            send(state.owner, {:mcp_message, decoded})

          {:error, reason} ->
            Logger.warning(
              "MCP StreamableHTTP Client: failed to decode SSE data: #{inspect(reason)}"
            )
        end

        {:noreply, state}
    end
  end

  def handle_info({:sse_stream_closed, reason}, state) do
    Logger.debug("MCP StreamableHTTP Client: SSE stream closed: #{inspect(reason)}")
    {:noreply, %{state | sse_task: nil}}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Task completion message — ignore (we handle via :DOWN)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("MCP StreamableHTTP Client: unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    do_close(state)
    :ok
  end

  # --- Private helpers ---

  defp do_post(state, message, opts) do
    case request_headers(state, message, opts) do
      {:ok, headers} -> do_post_with_headers(state, message, headers)
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_post_with_headers(state, message, headers) do
    body = Jason.encode!(message)

    case Req.post(state.url, body: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}}
      when status in [200, 201] ->
        # The content-encoding guard sits before the content-type branch, so it
        # covers the JSON and SSE paths alike. When incremental stream reading
        # is added (MES-38) it must reuse this guard.
        case unexpected_content_encoding(resp_headers) do
          nil -> deliver_by_content_type(state, resp_headers, resp_body)
          coding -> reject_content_encoding(coding)
        end

      {:ok, %Req.Response{status: 202}} ->
        # Accepted (notification/response acknowledged)
        {:ok, state}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.warning("MCP StreamableHTTP Client: HTTP #{status}: #{inspect(resp_body)}")

        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        Logger.warning("MCP StreamableHTTP Client: POST failed: #{inspect(reason)}")

        {:error, reason}
    end
  end

  # The full header list for one request: the SDK's own, the routing headers
  # derived from this message, the per-message `:headers` opt (Mcp-Param-*),
  # the static `:headers`, and finally the provider's.
  defp request_headers(state, message, opts) do
    case provider_headers(state) do
      {:ok, provided} ->
        {:ok,
         build_headers(state, message) ++
           Keyword.get(opts, :headers, []) ++ state.extra_headers ++ provided}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The SDK-derived headers for one message: content negotiation, the protocol
  version, and the SEP-2243 routing headers.

  Public so that the version/`_meta` lockstep can be asserted directly rather
  than inferred from a captured request; it is not part of the transport
  contract.
  """
  @spec build_headers(t :: %__MODULE__{}, message :: map()) :: [{String.t(), String.t()}]
  def build_headers(state, message) do
    [
      {"content-type", "application/json"},
      {"accept", "application/json, text/event-stream"},
      # Request no content coding. `identity` is a synonym for "no encoding"
      # (RFC 9110 §12.5.3); the SDK does not decode compressed response bodies
      # (req's decompression is opt-in and unbounded — a decompression-bomb DoS,
      # EEF-CVE-2026-49755), so it declines coding rather than enabling it.
      {"accept-encoding", "identity"},
      # The header value MUST match the body's
      # `_meta["io.modelcontextprotocol/protocolVersion"]`, or the server
      # rejects with 400 + HeaderMismatch (streamable-http.mdx:255-259). It is
      # therefore READ OFF THE MESSAGE rather than from the transport's own
      # config: with two sources of truth the two could diverge, and after a
      # -32022 retry changes the version, the header has to change with it.
      # The configured version remains the fallback for a message that carries
      # no `_meta` version of its own.
      {"mcp-protocol-version", message_protocol_version(message) || state.protocol_version}
    ] ++ routing_headers(message)
  end

  # SEP-2243 (`streamable-http.mdx:286-292`). `Mcp-Method` on every POST that
  # carries a method — requests and notifications alike, per "All requests".
  # `Mcp-Name` only for the three name-bearing methods; the mapping is the
  # mirror of the server's `routing_target/2` in `MCP.Transport.StreamableHTTP.Plug`.
  # The duplication is deliberate and noted rather than extracted: the two are
  # the same rule read from opposite ends of the wire, and a shared helper
  # would let one side's change silently move the other's.
  defp routing_headers(message) when is_map(message) do
    case Map.get(message, "method") do
      method when is_binary(method) ->
        [{"mcp-method", method}] ++ name_header(method, Map.get(message, "params"))

      _ ->
        []
    end
  end

  defp routing_headers(_message), do: []

  defp name_header(method, params) when is_map(params) do
    case routing_target(method, params) do
      target when is_binary(target) -> [{"mcp-name", HeaderMirror.encode_value(target)}]
      _ -> []
    end
  end

  defp name_header(_method, _params), do: []

  defp routing_target("tools/call", params), do: Map.get(params, "name")
  defp routing_target("prompts/get", params), do: Map.get(params, "name")
  defp routing_target("resources/read", params), do: Map.get(params, "uri")
  defp routing_target(_method, _params), do: nil

  defp message_protocol_version(%{"params" => %{"_meta" => meta}}) when is_map(meta) do
    case Map.get(meta, @protocol_version_meta_key) do
      version when is_binary(version) -> version
      _ -> nil
    end
  end

  defp message_protocol_version(_message), do: nil

  # --- Rotating credentials ---

  defp provider_headers(%{header_provider: nil}), do: {:ok, []}

  # Run in a SEPARATE, UNLINKED process with a bounded wait.
  #
  # Unlinked and not `Task.async/1` on purpose. `Task.async/1` links, and this
  # transport does not trap exits, so a provider process killed outright would
  # take the transport down through the link — the exact outcome the contract
  # promises cannot happen. `catch` covers raise/throw/exit; only an unlinked
  # process also covers a kill.
  #
  # A bound is required because a HANG is the failure `try` cannot catch at
  # all, and `send_message/2` is a synchronous `GenServer.call`: without it a
  # hung provider blocks this transport for the full 60s call timeout and
  # `MCP.Client` behind it.
  #
  # The `receive` is SELECTIVE — on our own ref and monitor only — so it cannot
  # swallow an unrelated message from this GenServer's mailbox.
  defp provider_headers(%{header_provider: fun} = state) when is_function(fun, 0) do
    parent = self()
    ref = make_ref()
    {pid, monitor} = spawn_monitor(fn -> send(parent, {ref, safely_call(fun)}) end)

    receive do
      {^ref, {:ok, result}} ->
        Process.demonitor(monitor, [:flush])
        validate_provider_headers(result)

      {^ref, {:error, reason}} ->
        Process.demonitor(monitor, [:flush])
        provider_error(reason)

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        provider_error({:exit, reason})
    after
      state.header_provider_timeout ->
        Process.demonitor(monitor, [:flush])
        Process.exit(pid, :kill)
        provider_error(:timeout)
    end
  end

  defp provider_headers(%{header_provider: other}),
    do: provider_error({:not_a_zero_arity_function, other})

  defp safely_call(fun) do
    {:ok, fun.()}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp validate_provider_headers(headers) when is_list(headers) do
    if Enum.all?(headers, &match?({name, value} when is_binary(name) and is_binary(value), &1)) do
      {:ok, headers}
    else
      provider_error({:invalid_headers, headers})
    end
  end

  defp validate_provider_headers(other), do: provider_error({:invalid_headers, other})

  defp provider_error(reason) do
    Logger.warning(
      "MCP StreamableHTTP Client: :header_provider failed (#{inspect(reason, limit: 5)}). " <>
        "THIS REQUEST fails; the transport is unaffected."
    )

    {:error, {:header_provider_failed, reason}}
  end

  defp warn_on_reserved_headers(headers) when is_list(headers) do
    reserved =
      headers
      |> Enum.flat_map(fn
        {name, _value} when is_binary(name) -> [String.downcase(name)]
        _ -> []
      end)
      |> Enum.filter(&(&1 in @reserved_headers))

    if reserved != [] do
      Logger.warning(
        "MCP StreamableHTTP Client: :headers contains #{inspect(reserved)}, which the SDK " <>
          "derives from each message. `:headers` entries are APPENDED, not merged, so this " <>
          "sends two field lines for that name and an intermediary taking the caller's may " <>
          "disagree with the body — the mismatch -32020 exists to catch. Remove it."
      )
    end
  end

  defp warn_on_reserved_headers(_headers), do: :ok

  defp get_content_type(headers) do
    get_header(headers, "content-type") || ""
  end

  # Returns the non-`identity` content coding(s) on a response as a string, or
  # `nil` when the body carries no coding — `content-encoding` absent, empty, or
  # `identity` (RFC 9110 §8.4 defines the `Content-Encoding` response header;
  # §8.4.1 makes codings case-insensitive; §5.3 makes multiple field lines
  # semantically identical to the comma form). It therefore reads **every** value
  # for the header (not just the first) and flattens the comma form within each —
  # `identity` and `gzip` on separate lines is the natural applied order and must
  # be caught exactly like `identity, gzip` on one line.
  defp unexpected_content_encoding(headers) do
    codings =
      headers
      |> get_header_values("content-encoding")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.downcase(&1) == "identity"))

    case codings do
      [] -> nil
      list -> Enum.join(list, ", ")
    end
  end

  # All values for a header. Req represents headers as `%{name => [values]}`, one
  # element per field line. Separate from `get_header/2` (first-value-wins), which
  # is shared with `content-type` where a single value is the right reading.
  defp get_header_values(headers, name) do
    case headers do
      %{^name => values} when is_list(values) -> values
      _ -> []
    end
  end

  defp get_header(headers, name) do
    # Req returns headers as a map of %{name => [values]}
    case headers do
      %{^name => [value | _]} -> value
      _ -> nil
    end
  end

  defp deliver_by_content_type(state, resp_headers, body) do
    content_type = get_content_type(resp_headers)

    cond do
      String.contains?(content_type, "text/event-stream") ->
        # Parse SSE events from the response body
        parse_sse_body(state, body)

      String.contains?(content_type, "application/json") ->
        # Single JSON response
        deliver_json_response(state, body)

      true ->
        Logger.warning("MCP StreamableHTTP Client: unexpected content-type: #{content_type}")
        {:ok, state}
    end
  end

  # The SDK sends `accept-encoding: identity` (build_headers/1) and does not decode
  # response bodies. A peer that returns a content coding anyway — permitted but
  # discouraged by RFC 9110 §12.5.3, a SHOULD not a MUST — is failed cleanly with a
  # coding-naming error rather than mis-decoded into a confusing `:json_decode_error`.
  defp reject_content_encoding(coding) do
    Logger.warning(
      "MCP StreamableHTTP Client: unexpected content-encoding #{inspect(coding)} " <>
        "(the SDK sends accept-encoding: identity and does not decode response bodies)"
    )

    {:error, {:unexpected_content_encoding, coding}}
  end

  defp parse_sse_body(state, body) when is_binary(body) do
    # Parse complete SSE body (from a non-streaming response)
    {events, _parser} = SSE.feed(SSE.new_parser(), body)

    Enum.each(events, fn event ->
      case Map.get(event, :data) do
        nil -> :ok
        "" -> :ok
        data -> deliver_decoded(state.owner, data)
      end
    end)

    {:ok, state}
  end

  defp deliver_json_response(state, body) when is_map(body) do
    send(state.owner, {:mcp_message, body})
    {:ok, state}
  end

  defp deliver_json_response(state, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        send(state.owner, {:mcp_message, decoded})
        {:ok, state}

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end

  defp deliver_decoded(owner, data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} ->
        send(owner, {:mcp_message, decoded})

      {:error, reason} ->
        Logger.warning(
          "MCP StreamableHTTP Client: failed to decode JSON from SSE: #{inspect(reason)}"
        )
    end
  end

  defp do_close(_state) do
    # Stateless: no session to terminate, so no DELETE is issued (SEP-2567).
    :ok
  end
end

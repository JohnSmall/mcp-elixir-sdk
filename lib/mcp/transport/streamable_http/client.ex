defmodule MCP.Transport.StreamableHTTP.Client do
  @moduledoc """
  Streamable HTTP client transport for MCP.

  Sends JSON-RPC messages via HTTP POST and receives responses as either
  `application/json` or `text/event-stream` (SSE). Optionally opens a
  GET SSE stream for server-initiated messages.

  ## Options

    * `:owner` (required) — pid to receive `{:mcp_message, map}` and
      `{:mcp_transport_closed, reason}` messages
    * `:url` (required) — the MCP endpoint URL (e.g., "http://localhost:8080/mcp")
    * `:headers` — extra HTTP headers to include on all requests
    * `:protocol_version` — MCP protocol version (default: the stateless core's)

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

  alias MCP.Transport.SSE

  @behaviour MCP.Transport

  @protocol_version "2026-07-28"

  defstruct [
    :owner,
    :url,
    :protocol_version,
    :extra_headers,
    :sse_task
  ]

  # --- Public API (Transport behaviour) ---

  @impl MCP.Transport
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl MCP.Transport
  def send_message(pid, message) when is_map(message) do
    GenServer.call(pid, {:send_message, message}, 60_000)
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

    state = %__MODULE__{
      owner: owner,
      url: url,
      protocol_version: protocol_version,
      extra_headers: extra_headers
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:send_message, message}, _from, state) do
    # Send HTTP POST with the JSON-RPC message
    case do_post(state, message) do
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

  defp do_post(state, message) do
    headers = build_headers(state)
    body = Jason.encode!(message)

    case Req.post(state.url, body: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}}
      when status in [200, 201] ->
        # The content-encoding guard sits before the content-type branch, so it
        # covers the JSON and SSE paths alike (the GET SSE stream is unimplemented;
        # when added it must reuse this guard).
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

  defp build_headers(state) do
    [
      {"content-type", "application/json"},
      {"accept", "application/json, text/event-stream"},
      # Request no content coding. `identity` is a synonym for "no encoding"
      # (RFC 9110 §12.5.3); the SDK does not decode compressed response bodies
      # (req's decompression is opt-in and unbounded — a decompression-bomb DoS,
      # EEF-CVE-2026-49755), so it declines coding rather than enabling it.
      {"accept-encoding", "identity"},
      {"mcp-protocol-version", state.protocol_version}
    ] ++ state.extra_headers
  end

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

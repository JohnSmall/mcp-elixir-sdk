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
  """

  use GenServer

  require Logger

  alias MCP.Protocol.ToolRouting
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

    case reserved_extra_header(extra_headers) do
      nil ->
        state = %__MODULE__{
          owner: owner,
          url: url,
          protocol_version: protocol_version,
          extra_headers: extra_headers
        }

        {:ok, state}

      name ->
        {:stop, {:reserved_extra_header, name}}
    end
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
    case build_headers(state, message, opts) do
      {:ok, headers} -> post(state, message, headers)
      {:error, _reason} = error -> error
    end
  end

  defp post(state, message, headers) do
    body = Jason.encode!(message)

    case Req.post(state.url, body: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}}
      when status in [200, 201] ->
        content_type = get_content_type(resp_headers)

        cond do
          String.contains?(content_type, "text/event-stream") ->
            # Parse SSE events from the response body
            parse_sse_body(state, resp_body)

          String.contains?(content_type, "application/json") ->
            # Single JSON response
            deliver_json_response(state, resp_body)

          true ->
            Logger.warning("MCP StreamableHTTP Client: unexpected content-type: #{content_type}")

            {:ok, state}
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

  defp build_headers(state, message, opts) do
    with {:ok, custom_headers} <-
           custom_routing_headers(message, Keyword.get(opts, :routing_headers, [])) do
      {:ok,
       [
         {"content-type", "application/json"},
         {"accept", "application/json, text/event-stream"},
         {"mcp-protocol-version", request_protocol_version(message, state.protocol_version)}
       ] ++ routing_headers(message) ++ custom_headers ++ state.extra_headers}
    end
  end

  defp request_protocol_version(message, fallback) do
    get_in(message, ["params", "_meta", "io.modelcontextprotocol/protocolVersion"]) || fallback
  end

  defp routing_headers(%{"method" => method} = message) do
    [{"mcp-method", method}] ++ routing_name_header(method, Map.get(message, "params"))
  end

  defp routing_headers(_message), do: []

  defp routing_name_header(method, params) when is_map(params) do
    target =
      case method do
        "tools/call" -> Map.get(params, "name")
        "prompts/get" -> Map.get(params, "name")
        "resources/read" -> Map.get(params, "uri")
        _method -> nil
      end

    if target, do: [{"mcp-name", encode_header_value(target)}], else: []
  end

  defp routing_name_header(_method, _params), do: []

  defp custom_routing_headers(%{"params" => %{"arguments" => arguments}}, descriptors)
       when is_map(arguments) do
    Enum.reduce_while(descriptors, {:ok, []}, fn descriptor, {:ok, headers} ->
      name = "mcp-param-#{String.downcase(descriptor.header)}"

      case ToolRouting.argument_value(arguments, descriptor) do
        :missing ->
          {:cont, {:ok, headers}}

        {:ok, value} ->
          {:cont, {:ok, headers ++ [{name, encode_header_value(value)}]}}

        {:error, reason} ->
          {:halt, {:error, {:invalid_routing_argument, name, reason}}}
      end
    end)
  end

  defp custom_routing_headers(_message, _descriptors), do: {:ok, []}

  defp encode_header_value(value) when is_binary(value) do
    if plain_header_value?(value) do
      value
    else
      "=?base64?#{Base.encode64(value)}?="
    end
  end

  defp plain_header_value?(value) do
    safe_bytes? =
      value
      |> :binary.bin_to_list()
      |> Enum.all?(&(&1 == 0x09 or &1 in 0x20..0x7E))

    safe_bytes? and value == String.trim(value) and not sentinel_shaped?(value)
  end

  defp sentinel_shaped?(value) do
    String.starts_with?(value, "=?base64?") and String.ends_with?(value, "?=")
  end

  defp reserved_extra_header(headers) do
    Enum.find_value(headers, fn
      {name, _value} when is_binary(name) -> if reserved_header?(name), do: name
      _header -> nil
    end)
  end

  defp reserved_header?(name) do
    normalized = String.downcase(name)

    normalized in [
      "content-type",
      "accept",
      "mcp-protocol-version",
      "mcp-method",
      "mcp-name"
    ] or String.starts_with?(normalized, "mcp-param-")
  end

  defp get_content_type(headers) do
    get_header(headers, "content-type") || ""
  end

  defp get_header(headers, name) do
    # Req returns headers as a map of %{name => [values]}
    case headers do
      %{^name => [value | _]} -> value
      _ -> nil
    end
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

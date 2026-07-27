defmodule MCP.Server.ToolContext do
  @moduledoc """
  Per-request context passed to identity-capable handler callbacks.

  In the 2026-07-28 stateless core this struct is **the per-request handler
  context** (the D2 identity-threading design's `ToolContext` successor): it is
  constructed once per request by the stateless dispatch (`MCP.Server.Dispatch`)
  and handed to every identity-capable callback, carrying a first-class
  `:identity` field.

  ## The `:identity` field (security-critical)

  `:identity` holds the caller principal established by the **authenticated
  transport pipeline** — for HTTP, resolved per request from `conn`; for
  stdio/in-process, resolved once at launch (PO Comment B). It is populated by
  the transport/dispatch **before** the handler runs and is **never** derived
  from the JSON-RPC `params`/`arguments`. Handlers MUST read the caller identity
  from `ctx.identity`, never from a model-supplied argument.

  Beyond identity, the struct also provides an API for handlers to interact with
  the server while a request is in flight — sending notifications (logging,
  progress) and making server-to-client requests (sampling, elicitation).

  ## Example

      def handle_call_tool("my_tool", args, ctx, state) do
        ToolContext.log(ctx, "info", "Starting tool execution")
        ToolContext.send_progress(ctx, 0, 100)

        # Request LLM sampling from the client
        {:ok, result} = ToolContext.request_sampling(ctx, %{
          "messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}],
          "maxTokens" => 100
        })

        ToolContext.send_progress(ctx, 100, 100)
        {:ok, [%{"type" => "text", "text" => "Done"}], state}
      end
  """

  defstruct [:server_pid, :request_id, :meta, :identity]

  @type t :: %__MODULE__{
          server_pid: pid() | nil,
          request_id: term(),
          meta: map() | nil,
          identity: term() | nil
        }

  @doc """
  Sends a JSON-RPC notification to the client during tool execution.

  The notification is routed through the MCP server and delivered
  to the client on the same SSE stream as the tool call response.
  """
  @spec send_notification(t(), String.t(), map()) :: :ok
  def send_notification(%__MODULE__{} = ctx, method, params) do
    GenServer.call(ctx.server_pid, {:context_notify, ctx.request_id, method, params})
  end

  @doc """
  Sends a server-to-client JSON-RPC request and waits for the response.

  Used for sampling, elicitation, and other bidirectional operations
  during tool execution. The request is routed to the client on the
  same SSE stream, and the client responds via a new POST.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  @spec request(t(), String.t(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def request(%__MODULE__{} = ctx, method, params, timeout \\ 60_000) do
    GenServer.call(ctx.server_pid, {:context_request, ctx.request_id, method, params}, timeout)
  end

  @doc """
  Sends a log notification to the client.

  Convenience wrapper around `send_notification/3` for logging.
  """
  @spec log(t(), String.t(), term(), String.t() | nil) :: :ok
  def log(%__MODULE__{} = ctx, level, data, logger \\ nil) do
    params = %{"level" => level, "data" => data}
    params = if logger, do: Map.put(params, "logger", logger), else: params
    send_notification(ctx, "notifications/message", params)
  end

  @doc """
  Sends a progress notification to the client.

  Uses the `progressToken` from `_meta` if available.
  """
  @spec send_progress(t(), number(), number() | nil) :: :ok
  def send_progress(%__MODULE__{} = ctx, progress, total \\ nil) do
    token = get_progress_token(ctx)

    params = %{"progressToken" => token, "progress" => progress}
    params = if total, do: Map.put(params, "total", total), else: params
    send_notification(ctx, "notifications/progress", params)
  end

  @doc """
  Sends a `sampling/createMessage` request to the client.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  @spec request_sampling(t(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def request_sampling(%__MODULE__{} = ctx, params, timeout \\ 60_000) do
    request(ctx, "sampling/createMessage", params, timeout)
  end

  @doc """
  Sends an `elicitation/create` request to the client.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  @spec request_elicitation(t(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def request_elicitation(%__MODULE__{} = ctx, params, timeout \\ 60_000) do
    request(ctx, "elicitation/create", params, timeout)
  end

  defp get_progress_token(%__MODULE__{meta: meta}) when is_map(meta) do
    Map.get(meta, "progressToken", 0)
  end

  defp get_progress_token(_ctx), do: 0
end

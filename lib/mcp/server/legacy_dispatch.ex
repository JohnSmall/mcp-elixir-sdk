defmodule MCP.Server.LegacyDispatch do
  @moduledoc """
  Version-isolated dispatcher for the stateful MCP 2025-11-25 protocol era.

  The connection/session owner enforces the initialize state machine. This
  module adapts legacy request envelopes to the immutable, context-bearing
  handler contract used by the 2026 runtime and removes 2026-only result
  members from responses sent to older peers.
  """

  alias MCP.Protocol.Messages.{Initialize, Request}
  alias MCP.Server.{Dispatch, ToolContext}

  @protocol_version "2025-11-25"
  @stateless_meta_keys [
    "io.modelcontextprotocol/protocolVersion",
    "io.modelcontextprotocol/clientInfo",
    "io.modelcontextprotocol/clientCapabilities"
  ]
  @stateless_result_keys ["resultType", "ttlMs", "cacheScope"]

  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version

  @spec initialize(Request.t(), map()) :: {:ok, map(), Initialize.Params.t()} | {:error, map()}
  def initialize(%Request{id: id, params: params}, config) do
    initialize = Initialize.Params.from_map(params || %{})

    if initialize.protocol_version == @protocol_version do
      result =
        Initialize.Result.to_map(%Initialize.Result{
          protocol_version: @protocol_version,
          capabilities: config.capabilities,
          server_info: config.server_info,
          instructions: config.instructions
        })

      {:ok, success(id, result), initialize}
    else
      {:error,
       error(id, -32_022, "Unsupported protocol version", %{
         "requested" => initialize.protocol_version,
         "supported" => [@protocol_version, Dispatch.protocol_version()]
       })}
    end
  rescue
    exception in [ArgumentError, KeyError, FunctionClauseError] ->
      {:error, error(id, -32_602, "Invalid params", Exception.message(exception))}
  end

  @spec dispatch(Request.t(), ToolContext.t(), map()) ::
          {:reply, map()} | {:input_required, map(), term()}
  def dispatch(%Request{id: id, method: "ping"}, _ctx, _config), do: {:reply, success(id, %{})}

  def dispatch(
        %Request{id: id, method: "resources/subscribe", params: params},
        context,
        config
      ),
      do:
        legacy_callback(
          id,
          :handle_subscribe,
          [Map.get(params || %{}, "uri", "")],
          context,
          config
        )

  def dispatch(
        %Request{id: id, method: "resources/unsubscribe", params: params},
        context,
        config
      ),
      do:
        legacy_callback(
          id,
          :handle_unsubscribe,
          [Map.get(params || %{}, "uri", "")],
          context,
          config
        )

  def dispatch(%Request{id: id, method: "logging/setLevel", params: params}, context, config),
    do:
      legacy_callback(
        id,
        :handle_set_log_level,
        [Map.get(params || %{}, "level", "info")],
        context,
        config
      )

  def dispatch(%Request{} = request, %ToolContext{} = context, config) do
    params = request.params || %{}
    meta = params |> Map.get("_meta", %{}) |> Map.drop(@stateless_meta_keys)

    adapted_params =
      if meta == %{} do
        Map.delete(params, "_meta")
      else
        Map.put(params, "_meta", meta)
      end

    stateless_meta = %{
      "io.modelcontextprotocol/protocolVersion" => Dispatch.protocol_version(),
      "io.modelcontextprotocol/clientCapabilities" => %{}
    }

    adapted = %{
      request
      | params: Map.put(adapted_params, "_meta", Map.merge(meta, stateless_meta))
    }

    # The injected 2026 metadata is strictly an internal adapter detail. A
    # legacy handler must observe only metadata the legacy peer actually sent.
    context = %{context | meta: meta}

    case Dispatch.dispatch(adapted, context, config) do
      {:reply,
       %{
         "result" =>
           %{
             "resultType" => "input_required",
             "inputRequests" => requests
           } = result
       }} ->
        {:input_required, requests, Map.get(result, "requestState")}

      {:reply, %{"result" => result} = response} when is_map(result) ->
        {:reply, %{response | "result" => Map.drop(result, @stateless_result_keys)}}

      {:reply, response} ->
        {:reply, response}
    end
  end

  defp success(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp legacy_callback(id, callback, arguments, context, config) do
    module = config.handler_module
    callback_arguments = arguments ++ [context, config.handler_state]

    if function_exported?(module, callback, length(callback_arguments)) do
      try do
        case apply(module, callback, callback_arguments) do
          :ok -> {:reply, success(id, %{})}
          {:ok} -> {:reply, success(id, %{})}
          {:error, code, message} -> {:reply, error(id, code, message, nil)}
          _invalid -> {:reply, error(id, -32_603, "Invalid handler result", nil)}
        end
      rescue
        _exception -> {:reply, error(id, -32_603, "Handler callback failed", nil)}
      catch
        _kind, _reason -> {:reply, error(id, -32_603, "Handler callback failed", nil)}
      end
    else
      {:reply, error(id, -32_601, "Method not found: #{callback}", nil)}
    end
  end

  defp error(id, code, message, data) do
    body = %{"code" => code, "message" => message}
    body = if is_nil(data), do: body, else: Map.put(body, "data", data)
    %{"jsonrpc" => "2.0", "id" => id, "error" => body}
  end
end

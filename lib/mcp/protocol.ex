defmodule MCP.Protocol do
  @moduledoc """
  JSON-RPC 2.0 encoding/decoding for MCP messages.
  """

  alias MCP.Protocol.Error
  alias MCP.Protocol.Messages.{Notification, Request, Response}

  @protocol_version "2025-11-25"
  @jsonrpc_version "2.0"

  @doc """
  Returns the MCP protocol version this library targets.
  """
  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version

  @doc """
  Returns the JSON-RPC version.
  """
  @spec jsonrpc_version() :: String.t()
  def jsonrpc_version, do: @jsonrpc_version

  @doc """
  Encodes a message struct to a JSON string.
  """
  @spec encode(Request.t() | Response.t() | Notification.t()) ::
          {:ok, String.t()} | {:error, term()}
  def encode(message) do
    {:ok, Jason.encode!(message)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Encodes a message struct to a JSON string, raising on error.
  """
  @spec encode!(Request.t() | Response.t() | Notification.t()) :: String.t()
  def encode!(message) do
    Jason.encode!(message)
  end

  @doc """
  Decodes a JSON string into a classified message struct.
  """
  @spec decode(String.t()) ::
          {:ok, Request.t() | Response.t() | Notification.t()} | {:error, Error.t()}
  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> decode_message(map)
      {:error, _} -> {:error, Error.parse_error()}
    end
  end

  @doc """
  Classifies a decoded JSON map into the appropriate message struct.
  """
  @spec decode_message(map()) ::
          {:ok, Request.t() | Response.t() | Notification.t()} | {:error, Error.t()}
  def decode_message(%{"jsonrpc" => "2.0"} = map) do
    cond do
      # Response: has "id" and ("result" or "error")
      Map.has_key?(map, "id") and (Map.has_key?(map, "result") or Map.has_key?(map, "error")) ->
        checked_response(map)

      # Request: has "id" and "method"
      Map.has_key?(map, "id") and Map.has_key?(map, "method") ->
        {:ok, decode_request(map)}

      # Notification: has "method" but no "id"
      Map.has_key?(map, "method") and not Map.has_key?(map, "id") ->
        {:ok, decode_notification(map)}

      true ->
        {:error, Error.invalid_request()}
    end
  end

  def decode_message(_map) do
    {:error, Error.invalid_request("Missing or invalid jsonrpc version")}
  end

  defp decode_request(map) do
    %Request{
      id: Map.fetch!(map, "id"),
      method: Map.fetch!(map, "method"),
      params: Map.get(map, "params")
    }
  end

  defp decode_response(map) do
    error =
      case Map.get(map, "error") do
        nil -> nil
        error_map -> Error.from_map(error_map)
      end

    %Response{
      id: Map.fetch!(map, "id"),
      result: Map.get(map, "result"),
      error: error
    }
  end

  defp decode_notification(map) do
    %Notification{
      method: Map.fetch!(map, "method"),
      params: Map.get(map, "params")
    }
  end

  # JSON-RPC 2.0 §5: a present `error` member "MUST be an Object as defined in
  # section 5.1", whose `code` "MUST be an integer" and whose `message` is "A
  # String". Anything else is not a response this decoder can build, so it is
  # -32600 rather than a raise in `Error.from_map/1` (MES-190). An `error: null`
  # is read as an absent member, as it was before.
  #
  # §5 also says "Either the result member or error member MUST be included, but
  # both members MUST NOT be included." So a `result` key beside a non-null
  # `error` is refused first, whatever the error's shape, rather than letting
  # the error win and the result vanish (MES-199).
  defp checked_response(%{"result" => _, "error" => error}) when not is_nil(error),
    do:
      {:error,
       Error.invalid_request(
         "a JSON-RPC response must not carry both a result and an error member"
       )}

  defp checked_response(%{"error" => %{"code" => code, "message" => message}} = map)
       when is_integer(code) and is_binary(message),
       do: {:ok, decode_response(map)}

  defp checked_response(%{"error" => error}) when not is_nil(error),
    do:
      {:error,
       Error.invalid_request(
         "a JSON-RPC error member must be an object with an integer code and a string message"
       )}

  defp checked_response(map), do: {:ok, decode_response(map)}
end

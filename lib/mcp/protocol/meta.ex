defmodule MCP.Protocol.Meta do
  @moduledoc """
  Per-request `_meta` handling for the MCP 2026-07-28 stateless core.

  The stateless core removes the `initialize` handshake (SEP-2575): protocol
  version, client info and client capabilities are no longer negotiated once
  per session — they ride in **every request's** `_meta`, under fully-qualified
  `io.modelcontextprotocol/*` keys.

  Keys parsed here (request side):

    * `io.modelcontextprotocol/protocolVersion` — the client's protocol version
      (required; a request without a supported version fails fast with
      `UnsupportedProtocolVersion`, -32022).
    * `io.modelcontextprotocol/clientInfo` — client identity (SHOULD).
    * `io.modelcontextprotocol/clientCapabilities` — client capabilities.
    * `io.modelcontextprotocol/logLevel` — the per-request log level, replacing
      the removed `logging/setLevel` control method (the Logging feature itself
      is retained-deprecated).

  This module reads `_meta` from a decoded request/notification's `params`; it
  never derives any caller **identity** — that comes from the authenticated
  transport pipeline (see the identity-threading design spec), never from the
  message body.
  """

  @protocol_version_key "io.modelcontextprotocol/protocolVersion"
  @client_info_key "io.modelcontextprotocol/clientInfo"
  @client_capabilities_key "io.modelcontextprotocol/clientCapabilities"
  @log_level_key "io.modelcontextprotocol/logLevel"

  defstruct [:protocol_version, :client_info, :client_capabilities, :log_level, raw: %{}]

  @type t :: %__MODULE__{
          protocol_version: String.t() | nil,
          client_info: map() | nil,
          client_capabilities: map() | nil,
          log_level: String.t() | nil,
          raw: map()
        }

  def protocol_version_key, do: @protocol_version_key
  def client_info_key, do: @client_info_key
  def client_capabilities_key, do: @client_capabilities_key
  def log_level_key, do: @log_level_key

  @doc """
  Extracts the per-request `_meta` keys from a request/notification's `params`.

  Accepts the full `params` map (reads its `"_meta"`) or `nil`.
  """
  @spec from_params(map() | nil) :: t()
  def from_params(params) when is_map(params) do
    meta = Map.get(params, "_meta") || %{}
    from_meta(meta)
  end

  def from_params(_), do: %__MODULE__{raw: %{}}

  @doc """
  Builds a `#{inspect(__MODULE__)}` from an already-extracted `_meta` map.
  """
  @spec from_meta(map()) :: t()
  def from_meta(meta) when is_map(meta) do
    %__MODULE__{
      protocol_version: Map.get(meta, @protocol_version_key),
      client_info: Map.get(meta, @client_info_key),
      client_capabilities: Map.get(meta, @client_capabilities_key),
      log_level: Map.get(meta, @log_level_key),
      raw: meta
    }
  end

  @doc """
  Validates the request's protocol version against the version this server
  supports.

  Returns `:ok`, `{:error, :missing}` when no version is present, or
  `{:error, {:unsupported, got}}` when it does not match. Both error cases map
  to `UnsupportedProtocolVersion` (-32022) at the dispatch boundary — the
  stateless core has no legacy path.
  """
  @spec validate_protocol_version(t(), String.t()) ::
          :ok | {:error, :missing} | {:error, {:unsupported, String.t()}}
  def validate_protocol_version(%__MODULE__{protocol_version: nil}, _supported),
    do: {:error, :missing}

  def validate_protocol_version(%__MODULE__{protocol_version: supported}, supported), do: :ok

  def validate_protocol_version(%__MODULE__{protocol_version: got}, _supported),
    do: {:error, {:unsupported, got}}
end

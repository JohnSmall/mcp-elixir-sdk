defmodule MCP.Transport do
  @moduledoc """
  Behaviour for MCP transports.

  A transport handles the I/O layer for MCP communication — framing,
  sending, and receiving JSON-RPC messages over a specific channel
  (stdio, HTTP, etc.).

  Transports run as processes (typically GenServers) owned by a client or
  server. Incoming messages are delivered to the owner process via:

      send(owner, {:mcp_message, decoded_map})

  Transport closure is signaled via:

      send(owner, {:mcp_transport_closed, reason})
  """

  @type opts :: keyword()
  @type message :: map()

  @doc """
  Starts the transport process, linked to the caller.

  Options must include `:owner` — the pid that will receive incoming messages.
  """
  @callback start_link(opts()) :: GenServer.on_start()

  @doc """
  Sends a JSON-RPC message (as a map) through the transport.
  """
  @callback send_message(pid :: pid(), message()) :: :ok | {:error, term()}

  @doc """
  Sends a JSON-RPC message with **per-message** transport options.

  Optional. A transport that does not export it is driven through
  `send_message/2` and simply cannot carry per-message options — it keeps
  working, which is why this is an addition rather than a change.

  The one option defined today is `:headers`, a list of `{name, value}` pairs
  the transport should place on this message only. It exists because
  `Mcp-Param-*` mirroring (SEP-2243) needs the called tool's `inputSchema`,
  which only `MCP.Client` holds — the transport cannot derive those headers on
  its own.

  A transport for which the option is meaningless **may ignore it**: for
  `:headers` on stdio that is the spec's own allowance — "Clients using other
  transports (e.g., stdio) MAY ignore `x-mcp-header` annotations entirely"
  (`server/tools.mdx:367-368`).
  """
  @callback send_message(pid :: pid(), message(), opts()) :: :ok | {:error, term()}

  @doc """
  Closes the transport, releasing all resources.
  """
  @callback close(pid :: pid()) :: :ok

  @optional_callbacks send_message: 3
end

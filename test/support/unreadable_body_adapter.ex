defmodule MCP.Test.UnreadableBodyAdapter do
  @moduledoc """
  A `Plug.Conn.Adapter` whose request body cannot be read: `read_req_body/2`
  answers `{:error, reason}`, as a server adapter does when the client stalls
  (`:timeout`, the default). The adapter contract allows any term as the reason,
  so a unit can pass one shaped like something else the Plug handles (MES-198
  F1). Everything else is `Plug.Adapters.Test.Conn`'s, so the response is
  readable as in any `Plug.Test` unit. Put on a `Plug.Test` conn with
  `with_unreadable_body/2`.
  """

  alias Plug.Adapters.Test.Conn, as: TestConn

  def with_unreadable_body(%Plug.Conn{adapter: {TestConn, state}} = conn, reason \\ :timeout),
    do: %{conn | adapter: {__MODULE__, Map.put(state, :mcp_read_error, reason)}}

  def read_req_body(state, _opts), do: {:error, Map.fetch!(state, :mcp_read_error)}

  defdelegate send_resp(state, status, headers, body), to: TestConn
  defdelegate send_file(state, status, headers, path, offset, length), to: TestConn
  defdelegate send_chunked(state, status, headers), to: TestConn
  defdelegate chunk(state, body), to: TestConn
  defdelegate inform(state, status, headers), to: TestConn
  defdelegate upgrade(state, protocol, opts), to: TestConn
  defdelegate push(state, path, headers), to: TestConn
  defdelegate get_peer_data(state), to: TestConn
  defdelegate get_http_protocol(state), to: TestConn
  defdelegate get_sock_data(state), to: TestConn
  defdelegate get_ssl_data(state), to: TestConn
end

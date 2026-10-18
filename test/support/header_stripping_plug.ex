defmodule MCP.Test.HeaderStrippingPlug do
  @moduledoc """
  A front Plug for `MCP.Transport.StreamableHTTPErrorReplyTest` (MES-189): it
  sits in front of the SDK's own `MCP.Transport.StreamableHTTP.Plug` and
  forwards every request to it.

  The SDK server cannot send `-32020` to the SDK client unaided: it never
  compares `Mcp-Param-*`, and the client always sends correct routing headers.
  With `strip_first_name: true` this Plug deletes `Mcp-Name` from the FIRST
  `tools/call` only, so the SDK server itself issues the genuine HTTP 400 /
  `-32020`, and every later request passes through unaltered.

  Each request is reported to `:test` as
  `{:posted, mcp_method, mcp_protocol_version, altered?}`, read off the
  headers. The body is left unread, because the SDK Plug reads it itself.

  Options: `:test` (pid), `:plug` (the SDK Plug's init options), `:once` (a
  public ETS table, so the strip fires once), `:strip_first_name` (boolean).
  """
  @behaviour Plug

  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @impl Plug
  def init(opts), do: Map.new(opts)

  @impl Plug
  def call(conn, %{test: test, plug: plug_opts, once: once} = opts) do
    method = first_header(conn, "mcp-method")
    version = first_header(conn, "mcp-protocol-version")

    altered? =
      Map.get(opts, :strip_first_name, false) and method == "tools/call" and
        :ets.insert_new(once, {:stripped})

    send(test, {:posted, method, version, altered?})

    conn = if altered?, do: Plug.Conn.delete_req_header(conn, "mcp-name"), else: conn
    MCPPlug.call(conn, plug_opts)
  end

  defp first_header(conn, name), do: conn |> Plug.Conn.get_req_header(name) |> List.first()
end

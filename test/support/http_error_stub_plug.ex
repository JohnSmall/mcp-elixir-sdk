defmodule MCP.Test.HTTPErrorStubPlug do
  @moduledoc """
  A stub Streamable HTTP server for `MCP.Transport.StreamableHTTPErrorReplyTest`
  (MES-189), for the cases where a status, header or body must be forced.

  `:respond` is a 1-arity function. It receives the decoded JSON-RPC message
  the client POSTed and returns `{status, headers, body}`, where `body` is the
  raw binary sent on the wire. Each decoded message is also reported to `:test`
  as `{:stub_posted, message}`.
  """
  @behaviour Plug

  @impl Plug
  def init(opts), do: Map.new(opts)

  @impl Plug
  def call(conn, %{test: test, respond: respond}) do
    {:ok, raw, conn} = Plug.Conn.read_body(conn)
    message = Jason.decode!(raw)
    send(test, {:stub_posted, message})

    {status, headers, body} = respond.(message)

    headers
    |> Enum.reduce(conn, fn {name, value}, acc -> Plug.Conn.put_resp_header(acc, name, value) end)
    |> Plug.Conn.send_resp(status, body)
  end
end

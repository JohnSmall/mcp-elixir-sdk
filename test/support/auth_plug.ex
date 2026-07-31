defmodule MCP.Test.AuthPlug do
  @moduledoc """
  Test-only stand-in for a host's **authenticated** Plug pipeline.

  Reads a credential from the `x-test-role` request header and writes the
  resolved principal into `conn.assigns[:role]` — the shape of a real
  bearer-auth Plug that verifies a credential and stamps the result onto the
  conn. The MCP identity factory then reads `conn.assigns[:role]` (the
  **authenticated** channel established server-side), never a raw request
  header (which would be caller-supplied / unauthenticated — see the factory
  last-mile note in `MCP.Transport.StreamableHTTP.Plug`).

  In the acceptance suite this Plug runs *before* the MCP Plug (via
  `MCP.Test.AuthedMCPPlug`), so by the time the identity factory runs the
  authenticated principal is already on `conn.assigns`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_req_header(conn, "x-test-role") do
      [role | _] -> assign(conn, :role, role)
      [] -> conn
    end
  end
end

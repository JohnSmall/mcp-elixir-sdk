defmodule MCP.Test.AuthedMCPPlug do
  @moduledoc """
  Acceptance-harness composite Plug: `MCP.Test.AuthPlug` (the authenticated
  pipeline) followed by `MCP.Transport.StreamableHTTP.Plug` (the MCP endpoint).

  This is the realistic end-to-end shape the D2 §4.2 boundary assumes: an
  upstream auth Plug converts a verified credential into `conn.assigns`, then
  the MCP Plug's per-request identity factory reads that assign. Bandit is
  handed `{MCP.Test.AuthedMCPPlug, mcp_opts}`; `mcp_opts` are the ordinary
  `MCP.Transport.StreamableHTTP.Plug` options (incl. the `:handler_opts`
  factory that reads `conn.assigns[:role]`).
  """
  @behaviour Plug

  alias MCP.Test.AuthPlug
  alias MCP.Transport.StreamableHTTP.Plug, as: MCPPlug

  @impl Plug
  def init(mcp_opts), do: MCPPlug.init(mcp_opts)

  @impl Plug
  def call(conn, mcp_config) do
    conn
    |> AuthPlug.call(AuthPlug.init([]))
    |> MCPPlug.call(mcp_config)
  end
end

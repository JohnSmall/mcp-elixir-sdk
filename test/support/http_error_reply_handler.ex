defmodule MCP.Test.HTTPErrorReplyHandler do
  @moduledoc """
  Test-support handler for `MCP.Transport.StreamableHTTPErrorReplyTest`
  (MES-189).

  One tool, `echo`, and deliberately **no prompt callbacks**, so the SDK's own
  server answers `prompts/list` with its genuine HTTP 404 / `-32601`.
  """
  @behaviour MCP.Server.Handler

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_list_tools(_cursor, _ctx, state),
    do: {:ok, [%{"name" => "echo", "inputSchema" => %{"type" => "object"}}], nil, state}

  @impl true
  def handle_call_tool("echo", _args, _ctx, state),
    do: {:ok, [%{"type" => "text", "text" => "ok"}], state}
end

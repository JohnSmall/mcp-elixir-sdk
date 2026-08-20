defmodule MCP.Test.ExtrasStruct do
  @moduledoc """
  A struct whose fields are named exactly like `t:MCP.Server.Handler.call_tool_extras/0`.

  It exists to make the struct branch of `warn_unusable_extras/2` discriminating
  (MES-17 F-9). The round-1 test used `%URI{}`, which has neither field — so the
  warning's claim that "structuredContent and isError are IGNORED" happened to
  read true there, and the case that could falsify it was never written. A
  struct IS a map, so dispatch reads these two fields off it and both reach the
  wire; the warning has to say that rather than the opposite.
  """
  defstruct [:structured_content, :is_error]
end

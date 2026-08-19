defmodule MCP.Test.CapabilityProbeHandler do
  @moduledoc """
  A handler that exists purely to drive `MCP.Server.Config.detect_capabilities/2`.

  It implements the three list callbacks *and* the two things that make a
  `listChanged` claim deliverable — `handle_listen/3` (a channel to say it on)
  and `supported_subscriptions/0` (the declaration) — so the capability builder
  can be tested against a handler that has genuinely earned the advertisement,
  separately from any real streaming behaviour.

  Deliberately minimal: the callbacks return fixed values and are never
  dispatched to in the capability tests. `MCP.Test.StatelessHandler` is the
  matching negative case — same list callbacks, no `handle_listen/3`.
  """
  @behaviour MCP.Server.Handler

  alias MCP.Server.ToolContext

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_list_tools(_cursor, %ToolContext{}, state), do: {:ok, [], nil, state}

  @impl true
  def handle_list_resources(_cursor, %ToolContext{}, state), do: {:ok, [], nil, state}

  @impl true
  def handle_list_prompts(_cursor, %ToolContext{}, state), do: {:ok, [], nil, state}

  @impl true
  def handle_listen(filter, %ToolContext{}, state), do: {:ok, filter, state}

  @doc """
  Declares every filter key, including `resourceSubscriptions` — which is never
  implied and must always be declared explicitly.
  """
  @impl true
  def supported_subscriptions do
    ["toolsListChanged", "promptsListChanged", "resourcesListChanged", "resourceSubscriptions"]
  end
end

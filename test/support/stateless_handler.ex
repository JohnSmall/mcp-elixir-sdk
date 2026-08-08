defmodule MCP.Test.StatelessHandler do
  @moduledoc """
  Test handler implementing the 2026-07-28 **context-bearing** callbacks for all
  eight identity-capable families, used to drive `MCP.Server.Dispatch`
  in-process. Every callback reads caller identity from `ctx.identity` — never
  from arguments — and echoes it into its result so the dispatch's MC-1 (context
  reaches every callback) and MC-4 (no model-arg override) guarantees can be
  asserted per family.
  """
  @behaviour MCP.Server.Handler

  alias MCP.Server.ToolContext

  @impl true
  def init(opts), do: {:ok, %{tools: Keyword.get(opts, :tools, [])}}

  @impl true
  def handle_list_tools(_cursor, %ToolContext{} = ctx, state) do
    {:ok, [%{"name" => "whoami", "boundIdentity" => id_str(ctx)}], nil, state}
  end

  @impl true
  def handle_call_tool("whoami", _args, %ToolContext{} = ctx, state) do
    {:ok, [%{"type" => "text", "text" => id_str(ctx)}], state}
  end

  # MRTR (SEP-2322): on a first attempt (`ctx.input` nil) the tool asks for
  # client input and hands back a continuation token; on the retry it reads the
  # fulfilled responses from `ctx.input` and completes.
  def handle_call_tool("needs_input", _args, %ToolContext{input: nil}, state) do
    input_requests = [%{"kind" => "elicitation", "message" => "what is your name?"}]
    {:input_required, input_requests, "rs-token-1", state}
  end

  def handle_call_tool("needs_input", _args, %ToolContext{input: %{responses: responses}}, state) do
    name = responses |> List.wrap() |> List.first() |> then(&Map.get(&1 || %{}, "name", "?"))
    {:ok, [%{"type" => "text", "text" => "hello #{name}"}], state}
  end

  # Reads identity ONLY from ctx; the model-supplied "identity" arg is ignored.
  def handle_call_tool("whoami_with_arg", _args, %ToolContext{} = ctx, state) do
    {:ok, [%{"type" => "text", "text" => id_str(ctx)}], state}
  end

  # A tool that never touches identity — used to prove the SDK response
  # envelope carries no identity of its own (§3.2 identity-never-on-the-wire).
  def handle_call_tool("silent", _args, %ToolContext{}, state) do
    {:ok, [%{"type" => "text", "text" => "ok"}], state}
  end

  # MRTR identity variant: like `needs_input`, but the completion echoes
  # `ctx.identity` (re-resolved from THIS request's pipeline on the retry),
  # never anything carried in the model-supplied requestState/inputResponses.
  def handle_call_tool("needs_input_id", _args, %ToolContext{input: nil}, state) do
    input_requests = [%{"kind" => "elicitation", "message" => "who are you?"}]
    {:input_required, input_requests, "rs-token-id", state}
  end

  def handle_call_tool("needs_input_id", _args, %ToolContext{input: %{responses: _}} = ctx, state) do
    {:ok, [%{"type" => "text", "text" => id_str(ctx)}], state}
  end

  # Ruling 7 regression (MES-14): emit an identity-bearing notification, then
  # RAISE. Proves a prior request's per-request notification collector is
  # unreachable to the next same-process request even when the handler crashes,
  # so no residue leaks into another principal's response.
  def handle_call_tool("emit_then_raise", _args, %ToolContext{} = ctx, _state) do
    ToolContext.log(ctx, "info", %{"identity" => id_str(ctx)})
    raise "boom after emitting a notification"
  end

  def handle_call_tool(_name, _args, %ToolContext{}, state) do
    {:error, -32_602, "unknown tool", state}
  end

  @impl true
  def handle_list_resources(_cursor, %ToolContext{} = ctx, state) do
    {:ok, [%{"uri" => "mem://res", "name" => id_str(ctx)}], nil, state}
  end

  @impl true
  def handle_read_resource(uri, %ToolContext{} = ctx, state) do
    {:ok, [%{"uri" => uri, "text" => id_str(ctx)}], state}
  end

  @impl true
  def handle_list_resource_templates(_cursor, %ToolContext{} = ctx, state) do
    {:ok, [%{"uriTemplate" => "mem://{x}", "name" => id_str(ctx)}], nil, state}
  end

  @impl true
  def handle_list_prompts(_cursor, %ToolContext{} = ctx, state) do
    {:ok, [%{"name" => "who", "description" => id_str(ctx)}], nil, state}
  end

  # Reads identity ONLY from ctx; a model-supplied "identity" arg is ignored (AC3′).
  @impl true
  def handle_get_prompt("who", _args, %ToolContext{} = ctx, state) do
    {:ok,
     %{
       "messages" => [
         %{"role" => "user", "content" => %{"type" => "text", "text" => id_str(ctx)}}
       ]
     }, state}
  end

  @impl true
  def handle_complete(_ref, _argument, %ToolContext{} = ctx, state) do
    {:ok, %{"values" => [id_str(ctx)], "total" => 1}, state}
  end

  defp id_str(%ToolContext{identity: nil}), do: ""
  defp id_str(%ToolContext{identity: id}), do: to_string(id)
end

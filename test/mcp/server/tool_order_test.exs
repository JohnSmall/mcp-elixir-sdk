defmodule MCP.Server.ToolOrderTest do
  @moduledoc """
  Gap-register **E2** — deterministic `tools/list` ordering.

  Normative anchor, quoted from the pinned revision
  (`docs/specification/2026-07-28/server/tools.mdx:71-74` at
  `5f5440bb26a62e2cf3440b92da5a667efa03b267`, md5
  `c302125aae381e9be1feb96305341d4b`):

  > Servers **SHOULD** return tools in a deterministic order (i.e., the same
  > ordering across requests when the underlying set of tools has not changed).

  It is a **stability** rule, not a sortedness rule: alphabetical is *sufficient*
  and is not *necessary*, which is why `:tool_order` has a `:handler` escape
  hatch rather than an unconditional sort.

  ## Arms, and which of them is evidence

  | arm | discriminates? |
  |---|---|
  | SUBJECT — two instances, default config | **yes** — red before the fix |
  | MUTANT — same two instances, `:tool_order = :handler` | **yes** — reproduces the pre-fix divergence in-tree |
  | CONTROL-1 — curated non-alphabetical order preserved | **yes** — the escape hatch is real, not decorative |
  | CONTROL-2 — an already-deterministic handler, default config | **no, and it is labelled so** |
  | BOUND — pagination | asserts the *limit* of the guarantee, not the guarantee |

  CONTROL-2 is green before **and** after the fix. It is here so that nobody can
  quote it as evidence for E2, and it is named a control for that reason.

  **Harness coverage: none.** `@modelcontextprotocol/conformance@0.2.0-alpha.11`
  has no ordering check in either leg — the `tools-list` family is `tools-list`,
  `tools-list-caching-hints`, `tools-list-changed-on-subscription`,
  `tools-list-gate`, and not one of them reads order. So the scored figure is
  byte-identical before and after this change and "added code, number went up" is
  not available here. The evidence for E2 is this file and nothing else.
  """

  use ExUnit.Case, async: true

  alias MCP.Protocol.Capabilities.ServerCapabilities
  alias MCP.Protocol.Messages.Request
  alias MCP.Protocol.Types.Implementation
  alias MCP.Server.Dispatch
  alias MCP.Server.ToolContext
  alias MCP.Test.EtsRegistryHandler

  @version "2026-07-28"

  defp config(handler, handler_opts, extra \\ %{}) do
    {:ok, state} = handler.init(handler_opts)

    Map.merge(
      %{
        handler_module: handler,
        handler_state: state,
        server_info: %Implementation{name: "mcp_elixir_sdk", version: "2.0.0"},
        capabilities: %ServerCapabilities{},
        instructions: nil
      },
      extra
    )
  end

  defp list_tool_names(config, params \\ %{}) do
    params = Map.put(params, "_meta", %{"io.modelcontextprotocol/protocolVersion" => @version})
    req = %Request{id: 1, method: "tools/list", params: params}
    {:reply, resp, _state} = Dispatch.dispatch(req, %ToolContext{request_id: 1}, config)
    Enum.map(resp["result"]["tools"], & &1["name"])
  end

  # --- Fixture precondition (RULING 4): the red arm must be able to be red ---

  test "GUARD — the two population orders really do iterate differently" do
    {fwd, rev} = EtsRegistryHandler.iteration_orders()

    assert Enum.sort(fwd) == Enum.sort(rev),
           "fixture broken: the two instances must hold the IDENTICAL tool set"

    assert fwd != rev, """
    fixture no longer diverges: this ERTS iterates the two differently-populated
    ETS :set tables in the same order, so the E2 SUBJECT arm can no longer go red
    and would be passing vacuously. Rebuild the fixture before trusting E2.
    """
  end

  # --- SUBJECT: the arm that was red before the fix ---

  test "SUBJECT — two instances holding the same tool set answer in the same order" do
    fwd = config(EtsRegistryHandler, order: :forward)
    rev = config(EtsRegistryHandler, order: :reverse)

    assert list_tool_names(fwd) == list_tool_names(rev)
  end

  test "SUBJECT — one instance answers in the same order on every request" do
    cfg = config(EtsRegistryHandler, order: :forward)
    assert Enum.uniq(for _ <- 1..5, do: list_tool_names(cfg)) |> length() == 1
  end

  test "SUBJECT — the default order is by name, and the tool SET is untouched" do
    cfg = config(EtsRegistryHandler, order: :forward)
    names = list_tool_names(cfg)

    assert names == Enum.sort(EtsRegistryHandler.names())
    assert Enum.sort(names) == Enum.sort(EtsRegistryHandler.names())
    assert length(names) == 24
  end

  # --- MUTANT: the mechanism switched off reproduces the defect ---

  test "MUTANT — with :tool_order = :handler the two instances diverge again" do
    fwd = config(EtsRegistryHandler, [order: :forward], %{tool_order: :handler})
    rev = config(EtsRegistryHandler, [order: :reverse], %{tool_order: :handler})

    refute list_tool_names(fwd) == list_tool_names(rev),
           "the sort is not what makes the SUBJECT arm pass — E2's evidence is not sensitive to its own mechanism"
  end

  # --- CONTROL-1: the escape hatch preserves a curated, conformant order ---

  test "CONTROL-1 — :tool_order = :handler keeps a curated non-alphabetical order verbatim" do
    curated = ["tool_9", "tool_1", "tool_24", "tool_3"]
    cfg = config(EtsRegistryHandler, [order: curated], %{tool_order: :handler})

    listed = list_tool_names(cfg)

    assert Enum.sort(listed) == Enum.sort(curated)
    refute listed == Enum.sort(curated), "the curated order happened to be sorted; pick another"
    assert listed == Enum.map(:ets.tab2list(cfg.handler_state.table), &elem(&1, 0))
  end

  # --- CONTROL-2: discriminates nothing, and says so ---

  test "CONTROL-2 (discriminates nothing) — an already-deterministic handler is unaffected" do
    cfg = config(MCP.Test.StatelessHandler, [])
    assert Enum.uniq(for _ <- 1..3, do: list_tool_names(cfg)) |> length() == 1
  end

  # --- BOUND: what the guarantee does NOT cover (A2d) ---

  test "BOUND — sorting is per RESPONSE; a paginated listing is not made deterministic" do
    # Each page is sorted on its way out. That does not make the concatenation of
    # two pages sorted, and it does nothing at all about a handler whose own
    # paging returns different CONTENTS per request. The honest claim is
    # "deterministic within each response, given a deterministic page".
    page_b = config(EtsRegistryHandler, order: ["tool_9", "tool_8", "tool_7"])
    page_a = config(EtsRegistryHandler, order: ["tool_3", "tool_2", "tool_1"])

    listing = list_tool_names(page_b) ++ list_tool_names(page_a)

    assert list_tool_names(page_b) == ["tool_7", "tool_8", "tool_9"]
    assert list_tool_names(page_a) == ["tool_1", "tool_2", "tool_3"]
    refute listing == Enum.sort(listing)
  end
end

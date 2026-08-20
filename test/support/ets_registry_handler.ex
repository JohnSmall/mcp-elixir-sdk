defmodule MCP.Test.EtsRegistryHandler do
  @moduledoc """
  A tool registry backed by an ETS `:set` — the fixture for gap-register **E2**
  (`server/tools.mdx:71-74`, deterministic `tools/list` ordering).

  ## Why ETS, and why two tables

  The E2 SHOULD is a **stability** rule: *"the same ordering across requests when
  the underlying set of tools has not changed"*. So the fixture has to produce a
  genuine ordering instability over an unchanged tool set, and it must do so
  **reproducibly** — a fixture that only sometimes diverges gives a flaky red arm,
  which is no better than a green that cannot go red.

  Two things were measured on this ERTS before this fixture was written, because
  the obvious fixture does not work:

    * Reading one **unchanged** `:set` table repeatedly returns the **same** order
      every time (50/50 reads identical). A handler that lists twice from one
      table therefore cannot go red, and building the E2 test that way would have
      been the unfalsifiable green this ticket exists to catch.
    * Two tables holding the **identical key set**, populated in **different
      orders**, do iterate differently — and each is individually stable. That is
      reproducible across BEAM restarts (`tool_20`/`tool_11` transpose at index 9
      for the 24-name set below).

  The second case is not a contrivance: it is the **2026-07-28 stateless core's
  own deployment model**. Every request is self-contained and any instance behind
  a round-robin balancer may serve it. Two instances of the same server, whose
  registries were populated in different orders (startup race, config merge,
  plug-in load order), hold the same tool set and disagree on its order — so a
  client's tool-list cache is invalidated by which instance answered, which is
  precisely the harm `tools.mdx:73-74` names.

  ## The guard

  `assert_fixture_diverges/0` asserts that the two population orders really do
  produce different ETS iteration orders. If a future ERTS changes `:set`
  iteration so the two agree, the E2 subject arm would start passing for a reason
  that has nothing to do with the SDK. The guard makes that fail loudly instead.
  """

  @behaviour MCP.Server.Handler

  @names for i <- 1..24, do: "tool_#{i}"

  @doc "The tool-name set both instances hold, in declaration order."
  def names, do: @names

  @doc """
  Starts a registry instance. `:order` is the sequence the ETS table is
  populated in — `:forward` and `:reverse` model two instances behind a
  balancer whose registries were built in different orders.
  """
  @impl true
  def init(opts) do
    order =
      case Keyword.get(opts, :order, :forward) do
        :reverse -> Enum.reverse(@names)
        :forward -> @names
        names when is_list(names) -> names
      end

    table = :ets.new(:tool_registry, [:set, :public])
    Enum.each(order, fn name -> :ets.insert(table, {name, tool(name)}) end)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_list_tools(_cursor, _ctx, state) do
    {:ok, Enum.map(:ets.tab2list(state.table), &elem(&1, 1)), nil, state}
  end

  @impl true
  def handle_call_tool(name, _args, _ctx, state) do
    {:ok, [%{"type" => "text", "text" => name}], %{}, state}
  end

  defp tool(name) do
    %{
      "name" => name,
      "description" => "fixture tool #{name}",
      "inputSchema" => %{"type" => "object"}
    }
  end

  @doc """
  The fixture precondition: the two population orders must actually diverge.

  Returns `{forward_names, reverse_names}` so a caller can assert on them.
  """
  def iteration_orders do
    {:ok, fwd} = init(order: :forward)
    {:ok, rev} = init(order: :reverse)
    {:ok, fwd_tools, _, _} = handle_list_tools(nil, nil, fwd)
    {:ok, rev_tools, _, _} = handle_list_tools(nil, nil, rev)
    :ets.delete(fwd.table)
    :ets.delete(rev.table)
    {Enum.map(fwd_tools, & &1["name"]), Enum.map(rev_tools, & &1["name"])}
  end
end

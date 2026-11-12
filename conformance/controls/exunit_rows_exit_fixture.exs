# MES-228 CONTROL FIXTURE — a test process that DIES, not one that fails.
#
# Driven by `conformance/controls/exunit_rows_controls.exs exit`. Outside
# `test_paths`, so gate 5 never runs it (see `exunit_rows_control_fixture.exs`
# for why the fixtures are committed and why nothing here mutates the tree).
#
# ## The failure shape this plants
#
# When a process linked to the test process crashes, the test process dies
# with it. ExUnit then sees a `:DOWN` rather than a reply and records the
# failure with the TUPLE kind `{:EXIT, test_pid}` (`runner.ex:498` at Elixir
# 1.19.5), which its CLI prints as `** (EXIT from #PID<…>)`. Before MES-228 the
# rows formatter called `to_string/1` on that kind, raised, died, and wrote no
# artefact — the Sprint 17 sweep's direction 6 (`MCP.Protocol.Error (decode)`),
# whose mutated `from_map/1` made linked `MCP.Client` processes crash exactly
# so.
#
# Two linked-crash variants, because the exit reason has two shapes and the
# formatter unwraps both:
#
#   * an Elixir exception — the reason is `{%RuntimeError{}, stack}`;
#   * a BEAM `function_clause` — the reason is `{:function_clause, stack}`,
#     the shape the direction-6 transcript carried.
defmodule MES228.ExitFixture do
  use ExUnit.Case, async: false

  @doc false
  def only_ok(:ok), do: :ok

  test "a linked process raises and takes the test process down" do
    spawn_link(fn -> raise "deliberate linked crash — MES-228 control" end)
    Process.sleep(10_000)
  end

  test "a linked process hits a function clause and takes the test process down" do
    spawn_link(fn -> apply(__MODULE__, :only_ok, [:not_ok]) end)
    Process.sleep(10_000)
  end
end

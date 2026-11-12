# MES-228 CONTROL FIXTURE — a `setup_all` process that DIES.
#
# The module-level twin of `exunit_rows_exit_fixture.exs`. A crash linked to the
# `setup_all` process kills it, ExUnit records the module as
# `failed({:EXIT, module_pid}, …)` (`runner.ex:383` at Elixir 1.19.5), and
# every test in the module becomes `{:invalid, module}`. The row's failure
# detail then comes from that module state, through the same rendering that
# raised before MES-228. Its own file because `invalid` is a property of the
# whole module.
defmodule MES228.ExitSetupAllFixture do
  use ExUnit.Case, async: false

  setup_all do
    spawn_link(fn -> raise "deliberate linked crash in setup_all — MES-228 control" end)
    Process.sleep(10_000)
    :ok
  end

  test "never runs, because its setup_all process died" do
    flunk("a test whose setup_all process died must not run")
  end
end

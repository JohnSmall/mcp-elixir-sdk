# MES-83 (B3) CONTROL FIXTURE — the `invalid` state.
#
# `invalid` needs its own module because it is a property of the MODULE: when
# `setup_all` fails, ExUnit marks every test in that module `{:invalid, module}`
# (`runner.ex:330`) and the test never runs. It is neither a pass nor a failure,
# which is why AC2's "errored/invalid" is a fifth state rather than a shade of
# `failed`.
#
# See `exunit_rows_control_fixture.exs` for why these fixtures are committed and
# why nothing here mutates the tree.
defmodule MES83.InvalidFixture do
  use ExUnit.Case, async: false

  setup_all do
    raise "deliberate setup_all failure — MES-83 control"
  end

  test "never runs, and is invalid rather than failed" do
    flunk("an invalid test must not run")
  end
end

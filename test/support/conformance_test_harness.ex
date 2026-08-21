defmodule MCP.Conformance.TestHarness do
  @moduledoc """
  Where the *live* conformance harness lives, and whether it can be driven from
  this host.

  Three tests cross-check our own parsing against the harness's own rendering by
  shelling out to `node`. That cross-check is the point of them — a recorded
  fixture would compare our parser against itself — so the dependency stays, and
  what changes is that it is now **visible**.

  MES-56 round 1: `CODE_REVIEWER` could not reproduce a green gate 5, because
  `node` is on the PM's and `CODE_CREATOR`'s PATH and not on the reviewer's.
  Two of the three tests then guarded themselves with `if File.exists?(yaml)`,
  which is worse than the failure: on a host with the requirement set installed
  and no `node` they exploded, and on a host with neither they **passed having
  checked nothing** — absence read as satisfaction, inside the test suite, on
  the ticket about exactly that.

  So the precondition is stated once, here, and `test_helper.exs` turns it into
  an EXCLUSION with a printed reason: a host that cannot run these reports a
  changed test count and says why, rather than reporting the same green over a
  smaller suite.
  """

  @install_dir "/tmp/conf11/node_modules/@modelcontextprotocol/conformance"
  @revision "2026-07-28"

  @doc "The pinned harness install (`@0.2.0-alpha.11`); `latest` has no #{@revision} scenarios."
  @spec install_dir() :: String.t()
  def install_dir, do: @install_dir

  @doc "The frozen requirement set as shipped inside the harness package."
  @spec requirements_yaml() :: String.t()
  def requirements_yaml, do: Path.join([@install_dir, "requirements", "#{@revision}.yaml"])

  @doc "The harness entry point these tests drive."
  @spec dist() :: String.t()
  def dist, do: Path.join([@install_dir, "dist", "index.js"])

  @doc """
  `nil` when the live harness can be driven here, otherwise the reason it
  cannot — one sentence, printed by `test_helper.exs` beside the exclusion.
  """
  @spec unavailable_reason() :: String.t() | nil
  def unavailable_reason do
    cond do
      System.find_executable("node") == nil ->
        "no `node` on PATH (the harness is a Node program; `mix test` cannot drive it here)"

      not File.exists?(dist()) ->
        "no harness at #{dist()} — install it with " <>
          "`npm i --prefix /tmp/conf11 @modelcontextprotocol/conformance@0.2.0-alpha.11`"

      not File.exists?(requirements_yaml()) ->
        "the harness is installed but carries no #{@revision} requirement set at " <>
          "#{requirements_yaml()} — `latest` has none; the pinned alpha does"

      true ->
        nil
    end
  end

  @doc """
  The harness's own listing of the frozen set, read from the harness rather than
  from a fixture. Raises rather than returning a default: a caller reaching this
  has already been gated by the `:requires_live_harness` tag, so a failure here
  is a broken install and not a host without one.
  """
  @spec listing!() :: String.t()
  def listing! do
    {out, 0} =
      System.cmd("node", [dist(), "list", "--requirements", @revision], stderr_to_stdout: true)

    out
  end

  @doc "The frozen revision these tests pin."
  @spec revision() :: String.t()
  def revision, do: @revision
end

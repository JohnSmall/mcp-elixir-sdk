defmodule MCP.Conformance.CensusMarkdownTest do
  @moduledoc """
  The rendered table, and specifically the column MES-57 changed.

  ## Why this file exists

  `MCP.Conformance.Census.Markdown` had no tests. Its own moduledoc says every
  figure is printed beside the reducer that produced it — "Sprint 4 shipped two
  reducers and the text did not say which was which" — and the per-scenario
  table was doing that very thing: the row's own verdict under the leg's summary
  reducer, and the control's cell under `requirements_exit`, with nothing saying
  they were different.

  On the SERVER leg that is invisible, which is why it survived:
  `requirements_exit` and `server_summary` have identical dispositions over all
  five statuses, so they agree scenario by scenario and MES-56's committed table
  re-renders byte-identically either way. On the CLIENT leg they diverge, because
  `client_summary` **fails a WARNING** that both others ignore. A null control
  that merely warns would have been printed as `pass` and subtracted from the
  honest figure.

  ## Why the fixtures are the COMMITTED censuses, mutated

  A hand-built census is an artefact this tooling could not have produced, and
  MES-56's round-5 guard caught two round-4 controls that were exactly that
  (S5-22). It is also a second copy of a schema that has one authority. So each
  test starts from a real accepted census in `docs/conformance/` and changes the
  one field under test.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.Census.Markdown

  @docs Path.expand("../../docs/conformance", __DIR__)

  defp census(leg) do
    @docs |> Path.join("#{leg}-2026-07-28.json") |> File.read!() |> Jason.decode!()
  end

  # Force one scenario, and its joined control, into the shape where the two
  # reducer families disagree: one WARNING, no FAILURE. `requirements_exit` and
  # `server_summary` ignore it; `client_summary` fails it. Everything here turns
  # on that one row.
  defp warning_only(census, id) do
    passes = %{
      "requirements_exit" => true,
      "server_summary" => true,
      "client_summary" => false,
      "server_summary_or_client_summary" => census["run"]["leg"] != "client"
    }

    scenarios =
      Enum.map(census["scenarios"], fn
        %{"id" => ^id} = s ->
          s
          |> Map.put("passes", passes)
          |> Map.put("control", %{
            "passes" => passes,
            "empty" => false,
            "checks" => s["checks"]
          })

        s ->
          s
      end)

    Map.put(census, "scenarios", scenarios)
  end

  defp row_for(census, id) do
    census
    |> Markdown.render()
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "| `#{id}` |"))
  end

  # The first scored scenario each committed census holds, whatever it is. Found
  # by lookup rather than hardcoded, so a suite change cannot silently make these
  # tests examine a row that is no longer there.
  defp subject(census) do
    census["scenarios"] |> Enum.find(& &1["scored"]) |> Map.fetch!("id")
  end

  describe "the control column is read under the LEG'S OWN summary reducer" do
    test "SERVER: a WARNING-only control renders `pass` — server_summary ignores a WARNING" do
      census = census("server")
      id = subject(census)
      row = census |> warning_only(id) |> row_for(id)

      assert row =~ "| PASS |"
      assert row =~ "| pass |"
    end

    test "CLIENT: the SAME check sheet renders `fail` — client_summary FAILS a WARNING" do
      # The whole point. Same shape, opposite cell. Under the old
      # `requirements_exit` reading BOTH said `pass`, so a null that merely
      # warned would have been subtracted from the honest figure as though it had
      # really passed.
      census = census("client")
      id = subject(census)
      row = census |> warning_only(id) |> row_for(id)

      assert row =~ "| FAIL |"
      assert row =~ "| fail |"
    end

    test "the measurement and the control agree on one identical sheet, on BOTH legs" do
      # Stated as the invariant rather than as two examples: whatever the row's
      # own verdict is computed from, the control's cell is computed from the
      # same thing. That is what was false before MES-57, and it was false in a
      # direction only the client leg could show.
      for leg <- ["server", "client"] do
        census = census(leg)
        id = subject(census)
        row = census |> warning_only(id) |> row_for(id)

        assert row =~ "| PASS |" == (row =~ "| pass |"),
               "on the #{leg} leg the measurement and the control disagree on one identical " <>
                 "check sheet, which can only happen if they are read under different reducers"
      end
    end
  end

  describe "the committed tables are projections of the committed censuses" do
    test "each renders byte-identically from its own census" do
      # The cheap half of the "no hand-written table" rule: if either .md on disk
      # is not what its .json renders to, one of them was edited by hand. This is
      # also the regression guard on MES-56's server artefact, which MES-57 was
      # required to leave byte-identical.
      for leg <- ["server", "client"] do
        rendered = leg |> census() |> Markdown.render()
        on_disk = @docs |> Path.join("#{leg}-2026-07-28.md") |> File.read!()

        assert rendered == on_disk,
               "docs/conformance/#{leg}-2026-07-28.md is not what its census renders to"
      end
    end
  end

  describe "an unjoined control is distinguishable from one that did not run" do
    test "a census with no control joined renders an em dash, not `fail`" do
      # These rendered identically until MES-56 round 1: "the control did not run
      # this scenario" and "no control was joined at all" mean different things
      # and license different subtractions.
      census = census("server")
      id = subject(census)

      stripped =
        census
        |> Map.put("scenarios", Enum.map(census["scenarios"], &Map.put(&1, "control", nil)))
        |> put_in(["totals", "control"], nil)

      row = row_for(stripped, id)

      assert row =~ "| — |"
      refute row =~ "| fail |"
    end
  end
end

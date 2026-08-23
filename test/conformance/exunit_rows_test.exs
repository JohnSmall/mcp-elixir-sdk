defmodule MCP.Conformance.ExUnitRowsTest do
  use ExUnit.Case, async: true

  alias MCP.Conformance.ExUnitRows

  @artefact "docs/conformance/etcc-exunit-rows.json"

  # A synthetic `%ExUnit.Test{}` — the same struct the event manager broadcasts.
  # Building rows from synthetic structs is what lets every state be asserted
  # here; the CONTROL run (conformance/controls/exunit_rows_controls.exs) is
  # what shows the same five states coming out of a real run, because a unit
  # test over a struct I built myself cannot establish that ExUnit produces it.
  defp test_struct(opts) do
    tags =
      Map.merge(
        %{
          file: Path.join(File.cwd!(), "test/mcp/example_test.exs"),
          line: 42,
          test_type: :test,
          describe: nil,
          describe_line: nil,
          registered: %{},
          async: true,
          module: Some.Module,
          test: :"test a",
          test_group: nil
        },
        Keyword.get(opts, :tags, %{})
      )

    %ExUnit.Test{
      name: Keyword.get(opts, :name, :"test a"),
      module: Keyword.get(opts, :module, Some.Module),
      state: Keyword.get(opts, :state, nil),
      tags: tags
    }
  end

  defp row(opts), do: ExUnitRows.row(test_struct(opts), File.cwd!())

  defp failure_state(message) do
    {:failed,
     [
       {:error, %RuntimeError{message: message},
        [{Some.Module, :"test a", 1, [file: ~c"test/mcp/example_test.exs", line: 44]}]}
     ]}
  end

  describe "the row key (AC6)" do
    test "is module and name, joined by /, both verbatim" do
      assert ExUnitRows.key(MCP.Protocol.ErrorTest, :"test round-trips through JSON") ==
               "MCP.Protocol.ErrorTest/test round-trips through JSON"
    end

    test "keeps the type prefix and the describe prefix ExUnit itself built" do
      # ExUnit builds "#{test_type} #{describe} #{name}" at case.ex:701. The key
      # takes that string verbatim so B2a can reconstruct it from source by the
      # same rule; normalising here would make two keys over one fact.
      assert ExUnitRows.key(M, :"doctest MCP.Protocol.encode/1 (2)") ==
               "M/doctest MCP.Protocol.encode/1 (2)"
    end

    test "splits losslessly on the FIRST slash, even when the name carries one" do
      key = ExUnitRows.key(MCP.ProtocolTest, :"doctest MCP.Protocol.encode/1 (2)")

      assert ExUnitRows.split_key(key) ==
               {"MCP.ProtocolTest", "doctest MCP.Protocol.encode/1 (2)"}
    end

    test "a row's key is exactly key/2 of its own module and name" do
      r = row(module: MCP.SomeTest, name: :"test b")
      assert r["key"] == ExUnitRows.key(MCP.SomeTest, :"test b")
      assert r["key"] == r["module"] <> "/" <> r["name"]
    end
  end

  describe "the five states (AC2)" do
    test "passed carries no reason and no failure" do
      assert %{"status" => "passed", "reason" => nil, "failure" => nil} = row(state: nil)
    end

    test "failed carries the failure detail and no reason" do
      r = row(state: failure_state("boom"))

      assert r["status"] == "failed"
      assert r["reason"] == nil

      assert [%{"kind" => "error", "exception" => "RuntimeError", "message" => "boom"} = f] =
               r["failure"]

      assert f["at"] == "test/mcp/example_test.exs:44"
    end

    test "excluded carries ExUnit's own exclusion reason — NOT an absence (S6-9)" do
      r = row(state: {:excluded, "due to test filter"})

      assert r["status"] == "excluded"
      assert r["reason"] == "due to test filter"
      # The whole point: an excluded test is PRESENT, with its reason, so it
      # cannot be confused with a test that was not run or does not exist.
      assert r["key"] != nil
    end

    test "skipped is distinct from excluded and carries its own reason" do
      r = row(state: {:skipped, "due to skip tag"})
      assert r["status"] == "skipped"
      assert r["reason"] == "due to skip tag"
    end

    test "invalid names the module whose setup_all failed, and keeps its failure" do
      module = %ExUnit.TestModule{name: Some.Module, state: failure_state("setup boom")}
      r = row(state: {:invalid, module})

      assert r["status"] == "invalid"
      assert r["reason"] == "setup_all failed in Some.Module"
      assert [%{"message" => "setup boom"}] = r["failure"]
    end

    test "the five statuses are distinct, and are the declared vocabulary" do
      module = %ExUnit.TestModule{name: Some.Module, state: failure_state("x")}

      seen =
        [nil, failure_state("x"), {:excluded, "r"}, {:skipped, "r"}, {:invalid, module}]
        |> Enum.map(&row(state: &1)["status"])

      assert length(Enum.uniq(seen)) == 5
      assert Enum.sort(seen) == Enum.sort(ExUnitRows.statuses())
    end
  end

  describe "row fields" do
    test "file is relative to the checkout, so a worktree and a clone agree" do
      r = row([])
      assert r["file"] == "test/mcp/example_test.exs"
      refute String.starts_with?(r["file"], "/")
    end

    test "a doctest is a row like any other, tagged as one (S6-6)" do
      r = row(tags: %{test_type: :doctest}, name: :"doctest MCP.Protocol.encode/1 (1)")
      assert r["test_type"] == "doctest"
    end

    test "tags drop exactly the declared deny-list and keep everything else" do
      r = row(tags: %{some_tag: true, requires_live_harness: true})

      for denied <- ExUnitRows.denied_tags() do
        refute Map.has_key?(r["tags"], to_string(denied))
      end

      assert r["tags"]["some_tag"] == true
      assert r["tags"]["requires_live_harness"] == true
    end

    test "the tag map is identical between a run and an excluded state" do
      # runner.ex:255-303 merges :test, :module, :async and :test_group into the
      # tags of tests that RUN only. All four are denied, which is what makes
      # the recorded tag map independent of whether the test ran.
      ran = row(state: nil)
      excluded = row(state: {:excluded, "due to test filter"}, tags: %{module: nil, async: nil})
      assert ran["tags"] == excluded["tags"]
    end

    test "non-JSON tag values are rendered rather than dropped" do
      r = row(tags: %{tuple: {:a, 1}, atom: :foo, list: [:a, "b"], nested: %{k: :v}})

      assert r["tags"]["tuple"] == "{:a, 1}"
      assert r["tags"]["atom"] == ":foo"
      assert r["tags"]["list"] == [":a", "b"]
      assert r["tags"]["nested"] == %{"k" => ":v"}
    end
  end

  describe "totals are DERIVED (AC3)" do
    setup do
      rows = [
        row(name: :"test a", state: nil),
        row(name: :"test b", state: {:excluded, "due to test filter"}),
        row(name: :"test c", state: failure_state("x")),
        row(name: :"test d", tags: %{test_type: :doctest})
      ]

      %{rows: rows}
    end

    test "derive_totals is the only producer, and it counts the rows given", %{rows: rows} do
      totals = ExUnitRows.derive_totals(rows)

      assert totals["total"] == 4
      assert totals["by_status"]["passed"] == 2
      assert totals["by_status"]["excluded"] == 1
      assert totals["by_status"]["failed"] == 1
      assert totals["by_test_type"] == %{"test" => 3, "doctest" => 1}
    end

    test "by_status always carries all five keys, so zero is not absence", %{rows: rows} do
      totals = ExUnitRows.derive_totals(rows)
      assert Map.keys(totals["by_status"]) |> Enum.sort() == Enum.sort(ExUnitRows.statuses())
      assert totals["by_status"]["skipped"] == 0
      assert totals["by_status"]["invalid"] == 0
    end

    test "mutating a row moves the total — the totals cannot be stale", %{rows: rows} do
      before = ExUnitRows.derive_totals(rows)
      mutated = List.update_at(rows, 0, &Map.put(&1, "status", "failed"))
      after_ = ExUnitRows.derive_totals(mutated)

      refute before == after_
      assert after_["by_status"]["failed"] == before["by_status"]["failed"] + 1
    end

    test "the artefact's totals equal derive_totals of its own rows", %{rows: rows} do
      artefact = ExUnitRows.artefact(rows, %{})
      assert artefact["totals"] == ExUnitRows.derive_totals(artefact["rows"])
      assert artefact["schema"] == ExUnitRows.schema_version()
    end

    test "encode/1 writes the header first and round-trips", %{rows: rows} do
      encoded = ExUnitRows.encode(ExUnitRows.artefact(rows, %{"tip" => "abc"}))

      assert String.ends_with?(encoded, "\n")
      assert Regex.run(~r/"(schema|run|totals|rows)"/, encoded) |> List.last() == "schema"
      decoded = Jason.decode!(encoded)
      assert decoded["totals"] == ExUnitRows.derive_totals(decoded["rows"])
      assert decoded["run"]["tip"] == "abc"
    end

    test "not_excluded_by_type is the shape ExUnit's headline counts in", %{rows: rows} do
      # cli_formatter.ex:263-265 leaves the counter unchanged for {:excluded, _}.
      assert ExUnitRows.not_excluded_by_type(rows) == %{"test" => 2, "doctest" => 1}
    end
  end

  describe "canonical order and content handles" do
    test "rows are sorted by {module, name} on write" do
      rows = [
        row(module: B.Test, name: :"test a"),
        row(module: A.Test, name: :"test z"),
        row(module: A.Test, name: :"test b")
      ]

      assert ExUnitRows.artefact(rows, %{})["rows"] |> Enum.map(& &1["key"]) ==
               ["A.Test/test b", "A.Test/test z", "B.Test/test a"]
    end

    test "rows_md5 is over the sorted rows, and moves when a row moves" do
      rows = [row(name: :"test a"), row(name: :"test b")]
      artefact = ExUnitRows.artefact(rows, %{})

      assert artefact["run"]["rows_md5"] == ExUnitRows.rows_md5(artefact["rows"])

      mutated = ExUnitRows.artefact([row(name: :"test a"), row(name: :"test c")], %{})
      refute mutated["run"]["rows_md5"] == artefact["run"]["rows_md5"]
    end

    test "key_collisions is empty for distinct keys and names a repeated one" do
      assert ExUnitRows.key_collisions([row(name: :"test a"), row(name: :"test b")]) == []

      assert ExUnitRows.key_collisions([row(name: :"test a"), row(name: :"test a")]) == [
               %{"key" => "Some.Module/test a", "rows" => 2}
             ]
    end
  end

  describe "reconciliation against ExUnit's own summary (AC1)" do
    test "parses the summary out of a full captured run, ignoring the rest" do
      output = """
      Compiling 1 file (.ex)
      ....

      Finished in 0.5 seconds (0.00s async, 0.5s sync)
      13 doctests, 935 tests, 0 failures
      """

      assert {:ok, summary} = ExUnitRows.parse_summary(output)
      assert summary["by_word"] == %{"doctests" => 13, "tests" => 935}
      assert summary["failures"] == 0
      assert summary["excluded"] == 0
    end

    test "parses the invalid, skipped and excluded terms" do
      assert {:ok, s} =
               ExUnitRows.parse_summary("3 tests, 1 failure, 2 invalid, 1 skipped (4 excluded)")

      assert s["failures"] == 1
      assert s["invalid"] == 2
      assert s["skipped"] == 1
      assert s["excluded"] == 4
    end

    test "strips ANSI, because a coloured summary is still a summary" do
      assert {:ok, s} = ExUnitRows.parse_summary("\e[31m2 tests, 1 failure\e[0m")
      assert s["by_word"] == %{"tests" => 2}
      assert s["failures"] == 1
    end

    test "reports :error when there is no summary line at all" do
      assert ExUnitRows.parse_summary("** (Mix) Could not compile") == :error
      assert %{"ok" => false} = ExUnitRows.reconcile("nothing here", %{})
    end

    test "agrees when the rows match the summary — excluded counted separately" do
      rows = [
        row(name: :"test a", state: nil),
        row(name: :"test b", state: {:excluded, "due to test filter"}),
        row(name: :"test c", tags: %{test_type: :doctest})
      ]

      result =
        ExUnitRows.reconcile(
          "1 doctest, 1 test, 0 failures (1 excluded)",
          ExUnitRows.derive_totals(rows)
        )

      assert result["ok"], inspect(result["checks"])
    end

    test "DISAGREES when a row is lost — the mismatch this exists to catch" do
      rows = [row(name: :"test a"), row(name: :"test b")]
      result = ExUnitRows.reconcile("3 tests, 0 failures", ExUnitRows.derive_totals(rows))

      refute result["ok"]

      assert Enum.any?(
               result["checks"],
               &(&1["name"] == "type:test" and &1["exunit"] == 3 and &1["rows"] == 2)
             )
    end

    test "DISAGREES when the excluded rule is mis-modelled" do
      # Counting an excluded row on both sides of the identity is the "more
      # rows" direction, and it is this module's defect, not ExUnit's.
      rows = [row(name: :"test a", state: {:excluded, "due to test filter"})]
      result = ExUnitRows.reconcile("1 test, 0 failures", ExUnitRows.derive_totals(rows))
      refute result["ok"]
    end

    test "an unrecognised summary word surfaces as a DISAGREEing check, not silently" do
      # ExUnit's test types are registerable, so a word this module does not
      # know is possible. Folding it onto "test" would hide a whole category;
      # leaving it alone makes it a visible red.
      rows = [row(name: :"test a")]

      result =
        ExUnitRows.reconcile("1 test, 1 property, 0 failures", ExUnitRows.derive_totals(rows))

      refute result["ok"]
      assert Enum.any?(result["checks"], &(&1["name"] == "type:property" and &1["rows"] == 0))
    end

    test "handles ExUnit's singular at a count of one" do
      rows = [row(name: :"test a")]
      assert ExUnitRows.reconcile("1 test, 0 failures", ExUnitRows.derive_totals(rows))["ok"]
    end
  end

  describe "the module_finished cross-check — the second witness" do
    test "agrees when every run key is in the module's own list" do
      keys = %{"A.Test" => MapSet.new(["A.Test/test a", "A.Test/test b"])}
      assert ExUnitRows.cross_check(keys, keys) == []
    end

    test "names a key the module reported but no test_finished event carried" do
      module = %{"A.Test" => MapSet.new(["A.Test/test a", "A.Test/test b"])}
      events = %{"A.Test" => MapSet.new(["A.Test/test a"])}

      assert ExUnitRows.cross_check(module, events) == [
               %{
                 "module" => "A.Test",
                 "direction" => "missing_from_events",
                 "keys" => ["A.Test/test b"]
               }
             ]
    end

    test "names a key events carried that the module's list did not" do
      module = %{"A.Test" => MapSet.new([])}
      events = %{"A.Test" => MapSet.new(["A.Test/test a"])}

      assert [%{"direction" => "missing_from_module_list", "keys" => ["A.Test/test a"]}] =
               ExUnitRows.cross_check(module, events)
    end
  end

  describe "the committed artefact" do
    # Integrity only. This deliberately does NOT assert the artefact matches the
    # current suite: that is drift detection, it belongs to MES-84, and two
    # owners on one guard is the MES-24 defect.
    setup do
      case File.read(@artefact) do
        {:ok, body} -> %{artefact: Jason.decode!(body)}
        {:error, _} -> flunk("#{@artefact} is missing — it is a committed artefact")
      end
    end

    test "carries the schema this module writes", %{artefact: a} do
      assert a["schema"] == ExUnitRows.schema_version()
    end

    test "its totals are derived from its own rows — a hand-edited total is a red", %{artefact: a} do
      assert a["totals"] == ExUnitRows.derive_totals(a["rows"])
    end

    test "its rows_md5 is the md5 of its own rows", %{artefact: a} do
      assert a["run"]["rows_md5"] == ExUnitRows.rows_md5(a["rows"])
    end

    test "its rows are canonically ordered, so a diff is meaningful", %{artefact: a} do
      assert a["rows"] == ExUnitRows.sort_rows(a["rows"])
    end

    test "every key is unique and every status is in the vocabulary", %{artefact: a} do
      assert ExUnitRows.key_collisions(a["rows"]) == []
      assert a["run"]["key_collisions"] == []

      for row <- a["rows"] do
        assert row["status"] in ExUnitRows.statuses()
        assert row["key"] == row["module"] <> "/" <> row["name"]
      end
    end

    test "no row carries an absolute path — the artefact is checkout-independent", %{artefact: a} do
      for row <- a["rows"], row["file"] do
        refute String.starts_with?(row["file"], "/"), "absolute path in #{row["key"]}"
      end
    end

    test "the run it records was complete and cross-checked", %{artefact: a} do
      assert a["run"]["complete"] == true
      assert a["run"]["module_cross_check"]["disagreements"] == []
      assert a["run"]["modules_started"] == a["run"]["modules_finished"]
    end

    test "it was generated from a clean tree, and says which paths were not", %{artefact: a} do
      # `tree_dirty` is the list, so "clean, and here is the empty list" and
      # "clean, take my word for it" do not print the same. The artefact's own
      # path is excluded from it: it is the file being written.
      assert a["run"]["tree_dirty"] == []
      assert a["run"]["tree_clean"] == true
      assert a["run"]["tip"] =~ ~r/^[0-9a-f]{40}$/
    end
  end
end

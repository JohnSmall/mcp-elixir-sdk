defmodule MCP.Conformance.InputFiguresTest do
  @moduledoc """
  **Guard 31 in gate 5** — the committed tree audits clean, and the decision
  logic unit by unit.

  The first describe block runs `InputFigures.audit/1` over the REAL tree: the
  seven hand-authored conformance inputs, the ledger, the universe registry and
  the baseline commit read from git. That is the wiring the brief asks for — a
  figure edited in an input without its ledger entry, a figure the data under
  it has moved, a dead field-name reference or an unregistered file under
  `docs/conformance/` turns gate 5 red.

  Everything after it drives `audit/1` over small synthetic inputs, because the
  real tree can only exhibit the cases it happens to contain. The end-to-end
  plants against the real files — every occurrence bumped by one, each shape
  planted where no ticket pointed — are
  `conformance/controls/input_figures_controls.exs`.

  It moves the suite's unit population, which dirties condition (b) of the
  end-of-sprint boundary-liveness skip. Declared, not hidden.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.InputFigures, as: F

  # MES-120's delivered pending SET, with the baseline and the scope it was
  # admitted under. It lives in test/ because conformance/figures/ is outside
  # D7's reviewable paths: a ledger-only edit could otherwise move the baseline,
  # widen the scope or swap one pending key for another at a constant count
  # (MES-120 CR probes P1 and P2). The digest makes an edit to the list an edit
  # to this file too. MES-131 shrinks both together; nothing may grow them.
  @delivered_path "test/fixtures/conformance/input_figures_pending_at_delivery.json"
  @delivered_sha256 "5342dff6bdbe306acb1827909f08b79e3e9c5af8cf458f6b67698c7fe6578e0f"
  @external_resource @delivered_path

  # The real-tree audit runs once for the module; the unit tests below ignore it.
  setup_all do
    %{result: F.audit(F.load())}
  end

  describe "the committed tree" do
    test "audits clean", %{result: %{defects: defects}} do
      assert defects == [], Enum.map_join(defects, "\n", &F.format_defect/1)
    end

    test "visits a non-zero population and classifies each occurrence exactly once",
         %{result: %{report: r}} do
      classes = ~w(measured enumerated historical not_a_count pending unparseable refused)
      assert r["visited"] > 0
      assert classes |> Enum.map(&r[&1]) |> Enum.sum() == r["visited"]
      assert r["references_visited"] > 0
      assert r["measured"] > 0 and r["historical"] > 0
    end

    test "the delivered pending record is the committed one" do
      bytes = File.read!(@delivered_path)
      assert :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) == @delivered_sha256
    end

    test "the ledger's baseline and pending scope are the ones MES-120 delivered" do
      delivered = delivered()
      {:ok, ledger} = F.load().ledger
      assert ledger["baseline"] == "7497292"
      assert ledger["baseline"] == delivered["baseline"]
      assert ledger["pending_admissible"] == delivered["pending_admissible"]
      assert length(ledger["pending_admissible"]) == 7
    end

    test "the pending SET only shrinks: every pending key was delivered pending" do
      delivered = delivered_keys()
      {:ok, ledger} = F.load().ledger
      grown = ledger["pending"] |> Enum.map(&key/1) |> Enum.reject(&MapSet.member?(delivered, &1))
      assert grown == [], "pending keys MES-120 did not deliver: #{inspect(grown)}"
    end

    test "a delivered key that left pending is gone from the text or adjudicated" do
      inputs = F.load()
      {:ok, ledger} = inputs.ledger
      {:ok, registry} = inputs.registry

      present =
        for {f, "hand_authored"} <- registry["files"],
            {:ok, doc} = inputs.docs[f],
            o <- F.scan(doc, f),
            into: MapSet.new(),
            do: {o.file, o.path, o.phrase, o.nth}

      pending = MapSet.new(ledger["pending"], &key/1)
      adjudicated = MapSet.new(ledger["entries"], &key/1)

      loose =
        delivered_keys()
        |> MapSet.difference(pending)
        |> Enum.filter(&(MapSet.member?(present, &1) and not MapSet.member?(adjudicated, &1)))

      assert loose == [], "left pending but still asserted and unadjudicated: #{inspect(loose)}"
    end

    test "no file-level figure of a crosswalk input is admissible as pending" do
      {:ok, ledger} = F.load().ledger

      for %{"file" => f, "path_prefixes" => prefixes} <- ledger["pending_admissible"],
          String.contains?(f, ["crosswalk-edges", "oc-axes-c1"]) do
        assert Enum.all?(prefixes, &String.ends_with?(&1, "[")),
               "#{f} admits a file-level prefix to pending: #{inspect(prefixes)}"
      end
    end
  end

  defp delivered, do: @delivered_path |> File.read!() |> Jason.decode!()
  defp delivered_keys, do: MapSet.new(delivered()["pending"], &key/1)
  defp key(e), do: {e["file"], e["path"], e["phrase"], e["nth"]}

  # --- synthetic inputs ----------------------------------------------------------

  @file_a "conformance/data/a.json"

  # Every synthetic document carries one resolvable cross-reference, so the
  # reference half of the reach guard is satisfied and each test sees only the
  # refusal it is about.
  defp inputs(doc, ledger, opts \\ []) do
    doc = Map.merge(%{"zref" => "see `zz_key`", "zz_key" => "v"}, doc)
    registry = Keyword.get(opts, :registry, %{@file_a => "hand_authored"})
    extra = Keyword.get(opts, :extra_docs, %{})
    baseline = Keyword.get(opts, :baseline, doc)

    %{
      registry: {:ok, %{"files" => registry}},
      ledger: {:ok, Map.merge(%{"baseline" => "base", "entries" => [], "pending" => []}, ledger)},
      walk: Keyword.get(opts, :walk, Map.keys(registry)),
      docs: Map.merge(%{@file_a => {:ok, doc}}, extra),
      code_words: Keyword.get(opts, :code_words, MapSet.new()),
      baseline_fun: fn _ -> {:ok, Jason.encode!(baseline)} end
    }
  end

  defp entry(path, phrase, class, arg, nth \\ 1) do
    key = %{
      "measured" => "quantity",
      "enumerated" => "list",
      "historical" => "as_of",
      "not_a_count" => "reason"
    }

    %{
      "file" => @file_a,
      "path" => path,
      "phrase" => phrase,
      "nth" => nth,
      "class" => class,
      key[class] => arg
    }
  end

  defp kinds(inputs), do: inputs |> F.audit() |> Map.fetch!(:defects) |> Enum.map(& &1.kind)

  @count_rows %{
    "quantities" => %{
      "rows" => %{"query" => %{"count" => %{"in" => @file_a, "at" => "rows[]"}}}
    }
  }

  describe "the recogniser" do
    defp phrases(s), do: %{"t" => s} |> F.scan("f") |> Enum.map(& &1.phrase)

    test "digits, words, compound words, hedges, backticked and possessive intervening words" do
      assert phrases("It has 12 edges.") == ["12 edges"]
      assert phrases("It has twenty-nine members.") == ["twenty-nine members"]
      assert phrases("about three checks") == ["about three checks"]

      assert phrases("the seventeen `http-custom-headers` rows") == [
               "seventeen `http-custom-headers` rows"
             ]

      assert phrases("thirteen of C1c-iii-b's rows") == ["thirteen of C1c-iii-b's rows"]
    end

    test "an unhedged `not one` asserts zero, and keeps its phrase" do
      values = fn s -> %{"t" => s} |> F.scan("f") |> Enum.map(&{&1.phrase, &1.value}) end
      assert values.("and not one edge is silent") == [{"one edge", 0}]
      assert values.("NOT ONE declared module") == [{"ONE declared", 0}]
      assert values.("one edge is silent") == [{"one edge", 1}]
      assert values.("knot one edge") == [{"one edge", 1}]
      assert values.("not two rows") == [{"two rows", 2}]
    end

    test "a ticket key, a section number or a path is not a figure" do
      assert phrases("MES-116 members") == []
      assert phrases("A3 §6 claim-level state") == []
      assert phrases("see x/3 rows") == []
    end

    test "parse/1" do
      assert F.parse("1,016") == 1016
      assert F.parse("Ninety-nine") == 99
      assert F.parse("2.7") == :unparseable
      assert F.parse("hundred") == :unparseable
    end

    test "the sentence does not end at i.e. or e.g." do
      [o] = F.scan(%{"t" => "At d5cac00 it was 173, i.e. this file's 49 rows."}, "f")
      assert o.sentence =~ "d5cac00"
    end

    test "occurrences of one phrase in one leaf are numbered" do
      assert %{"t" => "two rows and two rows"} |> F.scan("f") |> Enum.map(& &1.nth) == [1, 2]
    end

    test "list elements are addressed by identity, not index" do
      doc = %{
        "edges" => [
          %{
            "member" => %{"register_key" => "M/t"},
            "claim" => "c",
            "tag" => "x",
            "note" => "3 rows"
          }
        ]
      }

      assert [%{path: "edges[M/t | c | x].note"}] = F.scan(doc, "f")
    end
  end

  describe "the classes" do
    test "measured: equal passes, unequal is a mismatch" do
      doc = %{"t" => "It has 2 rows.", "rows" => [1, 2]}

      ok =
        inputs(
          doc,
          Map.put(@count_rows, "entries", [entry("t", "2 rows", "measured", "rows")])
        )

      assert kinds(ok) == []

      bad =
        inputs(
          %{doc | "rows" => [1]},
          Map.put(@count_rows, "entries", [entry("t", "2 rows", "measured", "rows")])
        )

      assert kinds(bad) == [:mismatch]
    end

    test "measured against a quantity the ledger does not register" do
      i = inputs(%{"t" => "2 rows"}, %{"entries" => [entry("t", "2 rows", "measured", "nope")]})
      assert :unknown_quantity in kinds(i)
    end

    test "a quantity that will not evaluate is refused" do
      q = %{
        "quantities" => %{
          "q" => %{"query" => %{"count" => %{"in" => "missing.json", "at" => "x[]"}}}
        }
      }

      assert :quantity_error in kinds(inputs(%{"t" => "no figure"}, q))
    end

    test "enumerated: relative to the record, or absolute with a leading /" do
      doc = %{"block" => %{"t" => "two entries", "entries" => [1, 2]}, "top" => [1, 2, 3]}

      assert kinds(
               inputs(doc, %{
                 "entries" => [entry("block.t", "two entries", "enumerated", "entries")]
               })
             ) == []

      assert kinds(
               inputs(doc, %{"entries" => [entry("block.t", "two entries", "enumerated", "/top")]})
             ) ==
               [:mismatch]
    end

    test "historical: the anchor must be in the same sentence" do
      doc = %{"t" => "C1c-ii had 5 edges. Then 9 edges."}

      e = [
        entry("t", "5 edges", "historical", "C1c-ii"),
        entry("t", "9 edges", "historical", "C1c-ii")
      ]

      assert kinds(inputs(doc, %{"entries" => e})) == [:unanchored_historical]
    end

    test "historical: an anchor that is not a ticket, slice or sha is refused" do
      e = [entry("t", "5 edges", "historical", "yesterday")]
      assert kinds(inputs(%{"t" => "yesterday 5 edges"}, %{"entries" => e})) == [:bad_entry]
    end

    test "not_a_count must cite a reason the ledger states" do
      doc = %{"t" => "one record per member"}
      e = [entry("t", "one record", "not_a_count", "R1")]
      assert kinds(inputs(doc, %{"entries" => e, "reasons" => %{"R1" => "distributive"}})) == []
      assert :bad_entry in kinds(inputs(doc, %{"entries" => e, "reasons" => %{}}))
    end

    test "not_a_count reason codes are a closed set in the guard, not in the ledger" do
      doc = %{"t" => "one record per member"}
      e = [entry("t", "one record", "not_a_count", "R8")]
      reasons = %{"R1" => "distributive", "R8" => "a reason the ledger invented"}

      defects =
        inputs(doc, %{"entries" => e, "reasons" => reasons}) |> F.audit() |> Map.fetch!(:defects)

      assert Enum.sort(Enum.map(defects, &{&1.kind, &1.path})) == [
               {:reason_outside_closed_set, "reasons.R8"},
               {:reason_outside_closed_set, "t"}
             ]

      assert Enum.all?(defects, &String.starts_with?(F.format_defect(&1), "G31 "))
      assert F.reasons() == ~w(R1 R2 R3 R4 R5 R6 R7)
    end

    test "an unparseable figure is refused unless it is filed as not a count" do
      doc = %{"t" => "2.7 axes a row"}
      assert kinds(inputs(doc, %{})) == [:unparseable]
      e = [entry("t", "2.7 axes", "not_a_count", "R7")]
      assert kinds(inputs(doc, %{"entries" => e, "reasons" => %{"R7" => "a ratio"}})) == []
    end

    test "an unledgered figure, a stale entry and a duplicate" do
      assert kinds(inputs(%{"t" => "4 rows"}, %{})) == [:unledgered]

      stale = [
        entry("t", "4 rows", "historical", "MES-1"),
        entry("t", "5 rows", "historical", "MES-1")
      ]

      assert :stale_entry in kinds(inputs(%{"t" => "MES-1: 4 rows"}, %{"entries" => stale}))

      dup = [
        entry("t", "4 rows", "historical", "MES-1"),
        entry("t", "4 rows", "historical", "MES-1")
      ]

      assert :duplicate_entry in kinds(inputs(%{"t" => "MES-1: 4 rows"}, %{"entries" => dup}))
    end
  end

  describe "pending" do
    @scope %{"pending_admissible" => [%{"file" => @file_a, "path_prefixes" => ["rows["]}]}

    defp pend(path, phrase),
      do: %{"file" => @file_a, "path" => path, "phrase" => phrase, "nth" => 1}

    test "admissible when present at the baseline and inside the scope" do
      doc = %{"rows" => [%{"id" => "r1", "t" => "3 rows"}]}
      assert kinds(inputs(doc, Map.put(@scope, "pending", [pend("rows[r1].t", "3 rows")]))) == []
    end

    test "refused when the figure was not at the baseline" do
      doc = %{"rows" => [%{"id" => "r1", "t" => "3 rows"}]}
      i = inputs(doc, Map.put(@scope, "pending", [pend("rows[r1].t", "3 rows")]), baseline: %{})
      assert kinds(i) == [:pending_not_in_baseline]
    end

    test "refused outside pending_admissible" do
      doc = %{"t" => "3 rows"}

      assert kinds(inputs(doc, Map.put(@scope, "pending", [pend("t", "3 rows")]))) == [
               :pending_outside_scope
             ]
    end

    test "a pending row whose figure has left is stale" do
      i = inputs(%{"rows" => []}, Map.put(@scope, "pending", [pend("rows[r1].t", "3 rows")]))
      assert :stale_pending in kinds(i)
    end

    test "fail-closed when the baseline cannot be read" do
      doc = %{"rows" => [%{"id" => "r1", "t" => "3 rows"}]}

      i = %{
        inputs(doc, Map.put(@scope, "pending", [pend("rows[r1].t", "3 rows")]))
        | baseline_fun: fn _ -> {:error, "gone"} end
      }

      assert kinds(i) == [:pending_unverifiable]
    end
  end

  describe "the universe" do
    test "an unregistered file under a walked root, and a registered file not on disk" do
      i = inputs(%{"t" => "x"}, %{}, walk: [@file_a, "docs/conformance/new.json"])
      assert :unregistered_file in kinds(i)

      i =
        inputs(%{"t" => "x"}, %{},
          registry: %{@file_a => "hand_authored", "gone.json" => "generated"},
          walk: [@file_a]
        )

      assert :absent_file in kinds(i)
    end

    test "a marker the registry disagrees with" do
      doc = %{"authored_by_hand" => true, "t" => "x"}
      i = inputs(doc, %{}, registry: %{@file_a => "generated"})
      assert :marker_disagreement in kinds(i)
    end

    test "a reader that sees nothing cannot pass" do
      i = inputs(%{"t" => "3 rows"}, %{}, registry: %{@file_a => "raw_evidence"})
      assert :reach in kinds(i)
    end
  end

  describe "cross-references (shape 5)" do
    # One anchored figure each, so the FIGURE half of the reach guard is quiet.
    defp with_figure(doc), do: Map.put(doc, "h", "MES-1 had 4 rows.")

    defp figured(ledger),
      do: Map.put(ledger, "entries", [entry("h", "4 rows", "historical", "MES-1")])

    test "resolve in the data, in the sources, or by an exemption — else refused" do
      doc =
        with_figure(%{
          "t" => "see `the_real_key` and `a_code_word` and `an_outside_name`",
          "the_real_key" => "v"
        })

      code = MapSet.new(["a_code_word"])
      assert kinds(inputs(doc, figured(%{}), code_words: code)) == [:unresolved_reference]

      ex = [%{"token" => "an_outside_name", "class" => "external", "reason" => "harness"}]
      assert kinds(inputs(doc, figured(%{"reference_exemptions" => ex}), code_words: code)) == []
    end

    test "an exemption nothing needs is stale, and one with no reason is refused" do
      doc = with_figure(%{"t" => "see `the_real_key`", "the_real_key" => "v"})
      ex = [%{"token" => "unused_name", "class" => "external", "reason" => "x"}]
      assert kinds(inputs(doc, figured(%{"reference_exemptions" => ex}))) == [:stale_exemption]

      ex = [%{"token" => "the_other_one", "class" => "external", "reason" => ""}]
      doc = with_figure(%{"t" => "see `the_real_key` and `the_other_one`", "the_real_key" => "v"})
      assert :bad_entry in kinds(inputs(doc, figured(%{"reference_exemptions" => ex})))
    end
  end
end

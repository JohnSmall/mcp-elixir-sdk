defmodule MCP.Conformance.StringCitationsTest do
  @moduledoc """
  **Guard 33 in gate 5**: the committed tree audits clean, every control
  refuses what it plants, and the ledger's ratchets are the ones MES-192
  delivered.

  The first block audits the REAL tree: the 61 artefacts under
  `conformance/data/` and `docs/conformance/`, every cited source at the tip,
  the anchor commits read from git, and the ledger. A `lib/` or `test/` edit
  that moves or rewrites a cited line, or an artefact edit that adds or drops a
  citation, turns gate 5 red here, naming the command that fixes it.

  The controls come from `MCP.Conformance.StringCitationControls`, the one
  implementation `conformance/controls/string_citations_controls.exs` also
  drives. Each plants one defect into a synthetic universe held in memory and
  requires its refusal KIND, with the `G33` prefix. That script shows each one
  fail with its limb neutralised. Nothing here writes a file.

  Synchronous on purpose: the real-tree audit decodes about 12 MB of JSON, and
  beside the async client tests whose wall-clock deadlines MES-191 records as
  load-sensitive it would add to that load. In the sync phase it contends with
  nothing.
  """

  use ExUnit.Case, async: false

  alias MCP.Conformance.InputFigures
  alias MCP.Conformance.StringCitationControls, as: C
  alias MCP.Conformance.StringCitations, as: S

  # The ratchets, pinned here as well as in the guard: raising one is an edit to
  # this file too (MES-192 ruling 32779 A1; plan 32773 "pins on the ledger").
  @ceilings %{
    {"stale", "MES-193"} => 226,
    {"stale", "MES-194"} => 7,
    {"stale", "MES-195"} => 4,
    {"order", "MES-196"} => 80,
    {"doubled", "client.ex"} => 678,
    {"external", "-"} => 5,
    {"not_a_cite", "fixture"} => 1
  }

  # The only commits an `at` row may name: the MES-161 row anchor (bd99a39),
  # the MES-58 publication (ef7fc48) and the boundaries note's dated cite
  # (5047a0e).
  @at_allowed ~w(
    bd99a3945f2885a943ac736b8b2d33422c97ccc0
    ef7fc4844998edcd6c9b2b9b8d4a0663b4d990bd
    5047a0ebb4180f8ec9c13277a58cd0ef62bbcdeb
  )

  # The context ExUnit hands each test is copied into that test's process, so
  # it carries only small terms: never the occurrences, which hold the decoded
  # records they sit in.
  setup_all do
    inputs = S.load()
    ctx = S.context(inputs)
    {:ok, ledger} = S.decode_ledger(elem(inputs.ledger, 1))

    value_paths =
      ctx.occs
      |> Enum.reject(&String.ends_with?(&1.at_path, "{key}"))
      |> Enum.group_by(& &1.art, & &1.at_path)
      |> Map.new(fn {f, ps} -> {f, Enum.uniq(ps)} end)

    %{inputs: inputs, result: S.audit_context(ctx), ledger: ledger, value_paths: value_paths}
  end

  describe "the committed tree" do
    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "audits clean", %{result: %{defects: defects}} do
      assert defects == [], Enum.map_join(defects, "\n", &S.format_defect/1)
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "visits every artefact, and every occurrence has exactly one row in one state",
         %{result: %{report: r}, inputs: inputs} do
      assert r["files"] == length(inputs.files) and r["files"] > 0
      assert r["occurrences"] > 0
      assert r["rows"] == r["occurrences"]
      assert r["states"] |> Map.values() |> Enum.sum() == r["occurrences"]
      assert r["byte_checked"] > 0
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "the ceilings are the delivered ones, and only shrink" do
      assert S.ceilings() == @ceilings
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "an at row names only an allow-listed commit", %{ledger: l} do
      ats = for %{"state" => "at", "at" => at} <- l.rows, uniq: true, do: at
      assert ats -- @at_allowed == []
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "only an allow-listed doubled basename carries target_by", %{ledger: l} do
      assert for(
               %{"target_by" => _, "cite" => c} <- l.rows,
               uniq: true,
               do: hd(String.split(c, ":"))
             ) ==
               ["client.ex"]
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "the ledger is reviewable and outside the universe it pins" do
      assert String.starts_with?(S.ledger_path(), "test/")
      refute String.starts_with?(S.ledger_path(), ["conformance/data/", "docs/conformance/"])
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "a JSON leaf is addressed exactly as G31 addresses it",
         %{inputs: inputs, value_paths: by_file} do
      for {f, paths} <- by_file, String.ends_with?(f, ".json") do
        {:ok, bin} = inputs.docs[f]

        g31 =
          for {p, _s, _r} <- InputFigures.leaves(Jason.decode!(bin), []),
              into: MapSet.new(),
              do: p

        assert Enum.reject(paths, &MapSet.member?(g31, &1)) == [], f
      end
    end
  end

  describe "the grammar" do
    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "a path or basename, a line or a range; refused shapes are named" do
      assert [t] = S.tokens("see `plug.ex:12-14`.")
      assert {t.cite, t.token, t.a, t.b, t.shape} == {"plug.ex:12-14", "plug.ex", 12, 14, :ok}
      assert [%{token: "lib/mcp/x.ex", a: 3}] = S.tokens("(lib/mcp/x.ex:3)")
      assert [%{cite: "x.ex:1–2", b: 2}] = S.tokens("x.ex:1–2")

      assert S.tokens("x.ex:3:4 y.exs:12th z.ex:0 a.ex:5-4") |> Enum.map(& &1.shape) ==
               [:bad_shape, :bad_shape, :bad_range, :bad_range]

      assert S.tokens("a bare :12 and docs.md:4 and schema.ts:9") == []
    end
  end

  describe "the controls (each plants one defect; MES-192 plan 32777 §6)" do
    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "P: the unplanted universe audits clean" do
      assert C.positive() == []
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C1: a moved window, path form" do
      assert_holds("C1")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C2: a moved window, basename form" do
      assert_holds("C2")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C3: a changed window" do
      assert_holds("C3")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C4: an ambiguous window" do
      assert_holds("C4")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C5: a doubled basename whose target is swapped" do
      assert_holds("C5")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C5a: a doubled basename row that names no evidence" do
      assert_holds("C5a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C5b: order-resolved rows beyond the ceiling" do
      assert_holds("C5b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C5c: a concatenated basename typo" do
      assert_holds("C5c")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C6: a citation added to an artefact" do
      assert_holds("C6")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C7: a citation removed from an artefact" do
      assert_holds("C7")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C8: a ledger row with no citation" do
      assert_holds("C8")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C9: a reader that drops a citation" do
      assert_holds("C9")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C10: a held label on a citation its holder does not read" do
      assert_holds("C10")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C11a: an at row naming no ancestor" do
      assert_holds("C11a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C11b: an at row whose commit lacks the bytes" do
      assert_holds("C11b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C12a: a stale row over its owner's ceiling" do
      assert_holds("C12a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C12b: a stale row with no owning ticket" do
      assert_holds("C12b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C13a: :0 and a reversed range" do
      assert_holds("C13a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C13b: a column and an ordinal" do
      assert_holds("C13b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C14: a ledger not in its canonical encoding" do
      assert_holds("C14")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C15: F1: a leaf that names the other doubled file contradicts an order pin" do
      assert_holds("C15")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C16a: F2: held g32_bytes outside G32's records" do
      assert_holds("C16a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C16b: F2: held g32_anchor_entry outside G32's records" do
      assert_holds("C16b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C16c: F2: held g32_prose_anchor outside G32's records" do
      assert_holds("C16c")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C16d: F2: held attribution_citations in an artefact its holder does not read" do
      assert_holds("C16d")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C16e: F2: held attribution_citations in a section its holder does not audit" do
      assert_holds("C16e")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C16f: F2: held g5_asserts_read on a list no holder test enumerates" do
      assert_holds("C16f")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C16g: F2: held g29 in a section G29 does not permit" do
      assert_holds("C16g")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C16h: F2: held g29 in an artefact G29 does not read" do
      assert_holds("C16h")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C17a: F3: a cite in a root field named module is re-addressed" do
      assert_holds("C17a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C17b: F3: a cite in module beside a key is re-addressed" do
      assert_holds("C17b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C17c: F3: a cite that is a record's identity is refused" do
      assert_holds("C17c")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C18a: R1: held g5_asserts_read is no longer a class" do
      assert_holds("C18a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C18b: R1: held g5_asserts_read under a holder loop filtered to no rows" do
      assert_holds("C18b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C18c: R1: an et_test_at row whose et_test file is not the cited file" do
      assert_holds("C18c")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C19a: R2: two correct cites in separate sentences pass" do
      assert_holds("C19a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C19b: R2: an unrelated other-client path in another sentence passes" do
      assert_holds("C19b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C19c: R2: both doubled files associated with the cite is ambiguous" do
      assert_holds("C19c")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C19d: R2: the :851 form still refuses a wrong pin" do
      assert_holds("C19d")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C20a: S1: a null pin window hash is refused, not skipped" do
      assert_holds("C20a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C20b: S1: a null at window hash is refused, not skipped" do
      assert_holds("C20b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C20c: S1: a window hash that is not lowercase 64-hex is refused" do
      assert_holds("C20c")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C21a: S2: a scalar named live_units is not a snapshot" do
      assert_holds("C21a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C21b: S2: a lookalike nested live_units list is not a snapshot" do
      assert_holds("C21b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C21c: S2: another field of a sweep record is not a snapshot" do
      assert_holds("C21c")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C21d: S2: the sweep's own generated lists stay snapshot" do
      assert_holds("C21d")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C22a: S3: a backup filename is not the other client's path" do
      assert_holds("C22a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C22b: S3: an uppercase-extension cite stands between" do
      assert_holds("C22b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C22c: S3: a digit-extension cite stands between" do
      assert_holds("C22c")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C23: S4: every refusal kind names a fix" do
      assert_holds("C23")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C24a: T1: at null is bad_row at every entry point, never a raise" do
      assert_holds("C24a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C24b: T1: at 1 is bad_row at every entry point, never a raise" do
      assert_holds("C24b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C25a: T2: external beyond its ceiling is refused" do
      assert_holds("C25a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C25b: T2: not_a_cite beyond its ceiling is refused" do
      assert_holds("C25b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C26: T3: the runtime shape kinds are declared and each names a fix" do
      assert_holds("C26")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C27a: U1: every JSON type in every field of every row state is refused, never raised on" do
      assert_holds("C27a")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C27b: U1: a refused row whose cite is an object is described, not raised on" do
      assert_holds("C27b")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "C28: U1: the matrix reads the schema's fields, and they are not empty" do
      assert_holds("C28")
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "every control is run above, once" do
      assert C.controls() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort(
                 ~w(C1 C2 C3 C4 C5 C5a C5b C5c C6 C7 C8 C9 C10 C11a C11b C12a C12b C13a C13b C14) ++
                   ~w(C15 C16a C16b C16c C16d C16e C16f C16g C16h C17a C17b C17c) ++
                   ~w(C18a C18b C18c C19a C19b C19c C19d) ++
                   ~w(C20a C20b C20c C21a C21b C21c C21d C22a C22b C22c C23) ++
                   ~w(C24a C24b C25a C25b C26 C27a C27b C28)
               )
    end
  end

  describe "maintenance (--resolve and --repin, over the planted universe)" do
    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "--resolve moves a moved window: the citation only, and the audit is clean after" do
      i = C.control("C1").inputs.()
      r = S.resolve(i, &base_read/1)
      assert r.moved == [{"lib/a.ex", 3, 3, 4}] and r.refused == []
      {:ok, before} = i.docs["docs/conformance/fixture.json"]

      assert r.docs["docs/conformance/fixture.json"] ==
               String.replace(before, "lib/a.ex:3", "lib/a.ex:4")

      assert S.audit(applied(i, r)).defects == []
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "--resolve refuses a changed and an ambiguous window, and leaves them red" do
      for {id, kind} <- [{"C3", :changed}, {"C4", :moved_ambiguous}] do
        i = C.control(id).inputs.()
        r = S.resolve(i, &base_read/1)
        assert r.docs == %{} and Enum.map(r.refused, & &1.kind) == [kind], id
        assert Enum.map(S.audit(applied(i, r)).defects, & &1.kind) == [:window_drift], id
      end
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "--resolve never rewrites a citation an instrument source writes literally" do
      i = C.control("C1").inputs.()
      r = S.resolve(i, &base_read/1, [{"test/x_test.exs", ~s(assert x == "lib/a.ex:3")}])
      assert r.docs == %{} and Enum.map(r.refused, & &1.kind) == [:literal_in_instrument]
    end

    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "--repin refuses a new basename citation to a doubled basename, and accepts only a named window" do
      ev = C.default_evidence() ++ [{"r5", "request/0 at client.ex:2"}]

      docs = %{
        "docs/conformance/fixture.json" => C.json(ev),
        "docs/conformance/report-2026-07-28.md" => C.md()
      }

      {_, rep} = S.repin(C.inputs(%{docs: docs, ledger: S.encode_ledger(C.decoded())}))
      assert rep.added == 0 and Enum.map(rep.refused, & &1.kind) == [:doubled_basename]

      i = C.control("C3").inputs.()
      {still_red, _} = S.repin(i)

      assert Enum.map(
               S.audit(%{i | ledger: {:ok, S.encode_ledger(still_red)}}).defects,
               & &1.kind
             ) == [:window_drift]

      {l, rep} = S.repin(i, ["lib/a.ex:3-3"])
      assert [{"lib/a.ex:3-3", _, _}] = rep.accepted
      assert S.audit(%{i | ledger: {:ok, S.encode_ledger(l)}}).defects == []
    end
  end

  describe "a malformed ledger as maintenance input (S1)" do
    @tag oc: :none
    @tag oc_reason:
           "G33, a conformance-instrument guard over repository artefacts; no OC check covers it"
    test "--repin and --resolve refuse it, and write nothing" do
      i = C.control("C20a").inputs.()
      assert {:error, [_ | _] = defects} = S.repin(i)
      assert Enum.any?(defects, &(&1.kind == :bad_window))
      assert {:error, [_ | _]} = S.resolve(i, &base_read/1)
    end
  end

  defp assert_holds(id) do
    c = C.control(id)
    defects = C.run(c)

    assert C.holds?(c),
           "#{id} (#{c.what}) expected #{c.kind}, got: " <>
             Enum.map_join(defects, "\n", &S.format_defect/1)
  end

  defp base_read(path) do
    case Map.fetch(C.sources(), path) do
      {:ok, v} -> {:ok, v}
      :error -> {:error, :enoent}
    end
  end

  defp applied(i, r) do
    docs = Map.merge(i.docs, Map.new(r.docs, fn {k, v} -> {k, {:ok, v}} end))
    %{i | docs: docs, ledger: {:ok, S.encode_ledger(r.ledger)}}
  end
end

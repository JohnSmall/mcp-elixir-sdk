defmodule MCP.Conformance.CitationVerbatimTest do
  @moduledoc """
  **Guard 30's decision logic, unit by unit.**

  > **A quoted byte-string in a record's `evidence` must occur verbatim and
  > contiguous inside a window the evidence itself addresses.**

  `MCP.Conformance.CitationVerbatim.audit/3` is a pure function of *(records,
  a window function)*, so every verdict below is reachable directly and
  cheaply — no tree, no harness, no generator run. The end-to-end half — the
  guard shown refusing a real edges file through `mix conformance.crosswalk`,
  at the OS exit status — is
  `conformance/controls/citation_verbatim_controls.exs`.

  ## Why this file exists as well as that one

  The control script drives the real artefacts and can therefore only exhibit
  the cases the real artefacts contain. The absent cases — a record with no
  evidence, a window that could not be built, a limb switched off — are
  reachable here and nowhere else, and two of them (`records_with_evidence`
  under an evidence-less record, and `undeterminable_window`) are precisely the
  fail-closed limbs that must not be left to a mutation of live data to
  demonstrate.

  It moves the suite's unit population, which dirties condition (b) of the
  end-of-sprint boundary-liveness skip. Declared, not hidden.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.CitationVerbatim

  # A window function that hands every record the same fixed windows. The
  # records under test carry the prose; the windows carry the "source".
  defp windows(narrow, broad \\ [], unavailable \\ []) do
    fn _record -> %{narrow: narrow, broad: broad, unavailable: unavailable} end
  end

  defp record(evidence), do: %{"claim" => "a claim", "evidence" => evidence}

  defp kinds(result), do: Enum.map(result["defects"], & &1["kind"])

  describe "the predicate — a quote is placed only by a window the evidence addresses" do
    test "a quote verbatim in a narrow window passes, and is counted as compared" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 — `assert x == 1` holds.")],
          windows([{"et:f.exs:1-1", "assert x == 1"}])
        )

      assert result["defects"] == []
      assert result["quotes_compared"] == 1
      assert result["quotes_counted"] == 1
      assert result["matched_in"] == %{"et:f.exs:1-1" => 1}
    end

    test "a quote in NO window is not verbatim at any cited address" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 — `assert x == 2` holds.")],
          windows([{"et:f.exs:1-1", "assert x == 1"}])
        )

      assert kinds(result) == ["not_verbatim_at_any_cited_address"]
      assert hd(result["defects"])["detail"] == "assert x == 2"
      assert hd(result["defects"])["row"] == "a claim"
      assert result["quotes_compared"] == 0
      assert result["quotes_counted"] == 1
    end

    # The CONTRACT: `audit/3` squashes the needle, and a window arrives already
    # squashed — which is what `line_window/3` does, and what any other window
    # builder (MES-113's) must also do. Pinned through the real builder rather
    # than by restating the rule, because a builder that forgot it would produce
    # false REDS, and a false red on a correct citation is the one failure that
    # would get this guard switched off.
    test "a quote the formatter wrapped differently still places, via line_window/3" do
      source = "line one\nassert x\n         == 1\nline four"

      result =
        CitationVerbatim.audit(
          [record("f.exs:2-3 — `assert x == 1` holds.")],
          windows([{"et:f.exs:2-3", CitationVerbatim.line_window(source, 2, 3)}])
        )

      assert result["defects"] == []
    end

    test "a prose phrase in backticks is not a quote, and is not compared" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 — the `listChanged` flag is set.")],
          windows([{"et:f.exs:1-1", "nothing of the sort"}])
        )

      assert result["defects"] == []
      assert result["quotes_counted"] == 0
    end
  end

  describe "LIMB 1 — WINDOWING catches a right-bytes/wrong-line citation" do
    # The bytes are real and in the file; they are one line outside the span the
    # evidence names. That is C1a's `capabilities_test.exs:97` defect exactly.
    setup do
      %{
        records: [record("f.exs:97 — `assert decoded[\"sampling\"] == %{}` holds.")],
        narrow: [{"et:f.exs:97-97", ""}],
        broad: [{"et-file:f.exs", "line 96 assert decoded[\"sampling\"] == %{} line 98"}]
      }
    end

    test "with the limb ON it is refused", ctx do
      result = CitationVerbatim.audit(ctx.records, windows(ctx.narrow, ctx.broad))
      assert kinds(result) == ["not_verbatim_at_any_cited_address"]
    end

    test "with the limb OFF it passes — which is what makes the limb load-bearing", ctx do
      result =
        CitationVerbatim.audit(ctx.records, windows(ctx.narrow, ctx.broad), limbs: [:contiguity])

      assert result["defects"] == []
    end
  end

  describe "LIMB 2 — CONTIGUITY catches a quote composed from two real lines" do
    # Every token is in the window; the tokens are never adjacent. That is
    # MES-109's composed-quote defect.
    setup do
      %{
        records: [record("f.exs:1-9 — `assert encode(x) == decode(y)` holds.")],
        spliced: [
          {"et:f.exs:1-9", "assert encode(x) == 1 and, nine lines later, 2 == decode(y) here"}
        ]
      }
    end

    test "with the limb ON it is refused", ctx do
      result = CitationVerbatim.audit(ctx.records, windows(ctx.spliced))
      assert kinds(result) == ["not_verbatim_at_any_cited_address"]
    end

    test "with the limb OFF it passes — which is what makes the limb load-bearing", ctx do
      result = CitationVerbatim.audit(ctx.records, windows(ctx.spliced), limbs: [:windowing])
      assert result["defects"] == []
    end
  end

  describe "an elision is refused rather than fragment-matched" do
    test "both spellings are named as an elision, not as a missing quote" do
      for elided <- ["`assert [] = … Keyword.get(:h)`", "`assert [] = ... Keyword.get(:h)`"] do
        result =
          CitationVerbatim.audit([record("f.exs:1 — #{elided}.")], windows([{"w", "anything"}]))

        assert kinds(result) == ["elision_is_not_a_lift"]
      end
    end

    test "it is refused even when the window WOULD contain the elided string" do
      # The point of the ruling: there is no window that rescues an elision, so
      # this cannot be argued down to "the bytes are there really".
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 — `assert a == 1 … b == 2`.")],
          windows([{"w", "assert a == 1 … b == 2"}])
        )

      assert kinds(result) == ["elision_is_not_a_lift"]
    end
  end

  describe "a bare :N continuation is refused as a FORM" do
    test "it is reported even when every quote in the same record places cleanly" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 and :3 — `assert x == 1` holds.")],
          windows([{"et:f.exs:1-1", "assert x == 1"}])
        )

      assert kinds(result) == ["bare_citation_has_no_file"]
      assert hd(result["defects"])["detail"] == ":3"
      # And the clean quote is still counted — the bare citation does not abort
      # the record.
      assert result["quotes_compared"] == 1
    end

    test "a full citation's own :N is not mistaken for a bare one" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:12-14 — `assert x == 1` holds.")],
          windows([{"et:f.exs:12-14", "assert x == 1"}])
        )

      assert result["defects"] == []
    end
  end

  describe "fail-closed — a window that could not be built is not a pass" do
    test "an unplaced quote is UNDETERMINABLE, and named differently from a wrong one" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 — `t===void 0` holds.")],
          windows([{"et:f.exs:1-1", "no"}], [], ["the harness build was not given"])
        )

      assert kinds(result) == ["undeterminable_window"]
      assert hd(result["defects"])["windows_unavailable"] == ["the harness build was not given"]
    end

    test "an available window still places a quote, so the reason does not swallow a pass" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 — `assert x == 1` holds.")],
          windows([{"et:f.exs:1-1", "assert x == 1"}], [], ["the harness build was not given"])
        )

      assert result["defects"] == []
    end
  end

  describe "the counts, which are what the REACH control rests on" do
    test "a record with no evidence is VISITED and contributes nothing" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 — `assert x == 1`."), %{"claim" => "no evidence here"}],
          windows([{"et:f.exs:1-1", "assert x == 1"}])
        )

      assert result["records_visited"] == 2
      assert result["records_with_evidence"] == 1
      assert result["quotes_counted"] == 1
    end

    test "compared + defective == counted, so a dropped quote cannot hide" do
      result =
        CitationVerbatim.audit(
          [record("f.exs:1 — `assert x == 1` and `assert y == 2` and `assert z == 3`.")],
          windows([{"et:f.exs:1-1", "assert x == 1 assert z == 3"}])
        )

      quote_defects = Enum.count(result["defects"], &(&1["kind"] != "bare_citation_has_no_file"))
      assert result["quotes_compared"] + quote_defects == result["quotes_counted"]
      assert result["quotes_counted"] == 3
    end

    test "an empty population is reported as empty rather than as clean" do
      result = CitationVerbatim.audit([], windows([]))
      assert result["quotes_counted"] == 0
      assert result["records_visited"] == 0
      # `defects == []` here too — which is exactly why the control requires
      # `counted > 0` and does not read an empty defect list as a pass.
      assert result["defects"] == []
    end
  end

  describe "the extractors" do
    test "source_quotes/1 takes only spans that look like source" do
      text = "`assert x == 1`, `f(y)`, `a[0]`, `b !== c`, `d === e`, `plain prose`, `Module`"

      assert CitationVerbatim.source_quotes(text) == [
               "assert x == 1",
               "f(y)",
               "a[0]",
               "b !== c",
               "d === e"
             ]
    end

    test "cited_line_spans/1 reads both the single-line and the range form" do
      assert CitationVerbatim.cited_line_spans("a_test.exs:12 and b_test.ex:30-42") == [
               {"a_test.exs", 12, 12},
               {"b_test.ex", 30, 42}
             ]
    end

    test "bare_citations/1 finds the continuation and not the full citation" do
      assert CitationVerbatim.bare_citations("a_test.exs:12 and :30") == [":30"]
    end

    test "line_window/3 is 1-based and inclusive at both ends" do
      assert CitationVerbatim.line_window("a\nb\nc\nd", 2, 3) == "b c"
      assert CitationVerbatim.line_window("a\nb\nc\nd", 2, 2) == "b"
    end

    test "squash/1 collapses runs and trims" do
      assert CitationVerbatim.squash("  a \n\t b  ") == "a b"
    end
  end
end

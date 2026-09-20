defmodule MCP.Conformance.CitationsTest do
  @moduledoc """
  **Guard 29, unit by unit, plus the one assertion that binds it to the tree.**

  > **No citation in `etcc-register.md` may name a unit the register does not
  > carry, and no line-shaped citation may appear anywhere the allow-list does not
  > grandfather THAT OCCURRENCE.**

  `MCP.Conformance.Citations.decide/2` is a pure function of *(prose,
  register keys)*, so every red below is reachable directly and cheaply. The
  end-to-end half — the extractor run over the real committed document, a
  one-character mutation of a real key shown to be refused, and a duplicate
  permitted token shown to be refused — is
  `conformance/controls/etcc_citation_controls.exs`.

  ## Why this is an ExUnit test and §1's control-script note does not forbid it

  `etcc-register.md` §1 argues that a test file added for the **register
  generator** would be a perturbation, because it would join the very population
  the generator enumerates. That argument is about the generator's denominator.
  Guard 29's denominator is *the citations written in one markdown file*, which no
  test file can join. What this file does move is the **suite's** unit count, and
  that is declared rather than hidden: it dirties condition (b) of the
  end-of-sprint boundary-liveness skip, exactly as `origin_sync_test.exs` did on
  MES-95, and the sweep owes a run.

  The pairing matters as much as the reds: `green/0` is the control every red case
  is a single mutation of. A `decide/2` that returned `ok?: false` unconditionally
  would satisfy every red assertion here and fail only that one.

  ## Limb B's erosion case has its own control, because the first cut failed it

  The limb B originally delivered on MES-94 keyed its allow-list on citation
  **text**, and passed a live `:353` written anywhere in the document, because
  `:353` is grandfathered in §6. `the same permitted string in another section is
  REFUSED` and `an extra occurrence in its own section is REFUSED` below are that
  falsification, kept as units.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.Citations

  doctest MCP.Conformance.Citations

  @key "MCP.ClientTest/test lifecycle times out a pending request"
  @known MapSet.new([@key])

  defp green, do: "The unit `#{@key}` is the one ruling C moved."

  # A minimal document in which `:353` stands where the real one grandfathers it.
  defp in_six(body), do: "## §6 PM TIE-BREAK\n\n" <> body

  describe "guard 29 against the committed tree" do
    test "the delivered etcc-register.md passes both limbs" do
      verdict = Citations.decide(Citations.read_document(), Citations.register_keys())

      assert verdict.ok?, Citations.explain(verdict)
    end

    test "and it is not passing vacuously — the extractor reaches the population" do
      # A limb that found nothing would satisfy "every key is known" for free. This
      # is the positive half: the real document really does carry keys, and one we
      # can name by hand is among them.
      keys = Citations.keys(Citations.read_document())

      assert length(keys) > 50
      assert @key in keys
    end

    test "no allow-list entry is stale — every permission is still written in full" do
      # Monotone the other way: the allow-list must not accumulate permissions for
      # citations nobody writes any more, or it stops describing this document.
      # With `ok?` true, this also pins the population exactly: no surplus, no
      # unlisted, no shortfall, so the document writes the permitted multiset and
      # nothing else.
      verdict = Citations.decide(Citations.read_document(), Citations.register_keys())

      assert verdict.stale_permissions == []
    end

    test "the permitted population is still 18 frozen + 20 quoted, as PM-ruled" do
      by_class =
        Citations.permitted_line_citations()
        |> Enum.group_by(fn {_pair, {class, _n}} -> class end, fn {_pair, {_c, n}} -> n end)
        |> Map.new(fn {class, counts} -> {class, Enum.sum(counts)} end)

      assert by_class == %{frozen: 18, quoted: 20}
    end

    test "every permitted occurrence names a section the document actually has" do
      document_sections = Citations.read_document() |> Citations.sections() |> MapSet.new()

      for {{section, text}, _} <- Citations.permitted_line_citations() do
        assert MapSet.member?(document_sections, section),
               "#{text} is pinned to absent #{section}"
      end
    end
  end

  describe "limb A — a cited key must be a key the register carries" do
    test "the control: a known key passes" do
      assert Citations.decide(green(), @known).ok?
    end

    test "an unknown key is refused, and named" do
      verdict = Citations.decide(green(), MapSet.new(["something else"]))

      refute verdict.ok?
      assert verdict.unknown_keys == [@key]
      assert Citations.explain(verdict) =~ @key
    end

    test "ONE character is enough — a renamed unit cannot pass" do
      # The S8-2 shape as it would arrive next time: somebody renames a test and
      # the prose goes on naming the old one.
      renamed = String.replace(green(), "times out", "times-out")

      refute Citations.decide(renamed, @known).ok?
    end

    test "a moved unit CANNOT break it, which is the whole point" do
      # No line appears in a key, so there is nothing a tag insert can shift.
      assert Citations.decide(green(), @known).ok?
      assert Citations.decide(green() <> "\n\n" <> green(), @known).ok?
    end

    test "Module.fun/arity and prose are not mistaken for keys" do
      assert Citations.keys("`MCP.Client.encode/1`, `MCP.Server.Dispatch.dispatch/3`") == []
      assert Citations.keys("`etcc-register.json`, `@tag :etcc`, `%{}`") == []
      assert Citations.keys("MCP.ClientTest/test outside a code span") == []
    end

    test "a doctest row key is a key like any other" do
      key = "MCP.Protocol.ExtensionsTest/doctest MCP.Protocol.Extensions.from_meta/1 (9)"

      assert Citations.keys("`#{key}`") == [key]
    end
  end

  describe "limb B — the ratchet, keyed on the OCCURRENCE" do
    test "the control: a permitted citation in the section that permits it passes" do
      assert Citations.decide(in_six("MES-81 wrote `:353` here."), @known).ok?
    end

    test "the same permitted string in another section is REFUSED — the erosion case" do
      # CODE_REVIEWER's falsification of the text-keyed first cut, as a unit: `:353`
      # is grandfathered in §6 and nowhere else, so a live one in §9 is new.
      verdict = Citations.decide("## §9 Out of scope\n\ncited live at `:353`", @known)

      refute verdict.ok?
      assert [%{text: ":353", section: "§9", reason: :unlisted, line: 3}] = verdict.unpermitted
      assert Citations.explain(verdict) =~ "UNLISTED"
    end

    test "an EXTRA occurrence in its own section is REFUSED, with both counts" do
      # `:353` is permitted three times in §6. A fourth is a citation nobody
      # grandfathered, and the counts are what say so.
      four = in_six(Enum.map_join(1..4, "\n", fn n -> "line #{n} cites `:353`" end))
      verdict = Citations.decide(four, @known)

      refute verdict.ok?
      assert [%{text: ":353", reason: :over_count, seen: 4, permitted: 3}] = verdict.unpermitted
      assert Citations.explain(verdict) =~ "OVER-COUNT, 4 written"
    end

    test "exactly the permitted multiplicity is green — the boundary, not one side of it" do
      three = in_six(Enum.map_join(1..3, "\n", fn n -> "line #{n} cites `:353`" end))

      assert Citations.decide(three, @known).ok?
    end

    test "an unlisted bare continuation is refused, with its line" do
      verdict = Citations.decide("## §6 x\nb\nsee `:9999` for this", @known)

      refute verdict.ok?
      assert [%{text: ":9999", line: 3}] = verdict.unpermitted
      assert Citations.explain(verdict) =~ "etcc-register.md:3"
    end

    test "an unlisted explicit citation is refused" do
      refute Citations.decide(in_six("see `client_test.exs:4242`"), @known).ok?
    end

    test "a citation above the first numbered heading is unlisted — no section, no permission" do
      verdict = Citations.decide("front matter, `:353`\n\n## §6 x", @known)

      refute verdict.ok?
      assert [%{section: "(preamble)", reason: :unlisted}] = verdict.unpermitted
    end

    test "spec anchors are NOT line citations here — out of scope, PM-ruled" do
      assert Citations.line_citations("`schema.ts:450`, `changelog.mdx:14`") == []
      assert Citations.decide("anchored at `schema.ts:450`", @known).ok?
    end

    test "removing a permitted citation stays green — the ratchet is monotone" do
      verdict = Citations.decide("no citations at all", @known)

      assert verdict.ok?
    end

    test "but a permission the prose no longer writes is REPORTED, not silently kept" do
      verdict = Citations.decide("## §6 x\n\nnothing cited", @known)

      assert verdict.ok?

      assert Enum.any?(
               verdict.stale_permissions,
               &match?(%{section: "§6", text: ":353", class: :frozen, permitted: 3, seen: 0}, &1)
             )
    end
  end

  describe "sections — the § anchor limb B pins a permission to" do
    test "a sub-heading without a § belongs to the numbered section above it" do
      # This is why §6's six worked cases, which live under `### The six worked
      # cases`, are pinned to §6 and not to a heading of their own.
      assert Citations.sections("## §6 rule\n### The six worked cases\ntext") ==
               ["§6", "§6", "§6"]
    end

    test "a lettered or dotted section number is its own anchor" do
      assert Citations.sections("## §6a sweep\nx\n### §0.1 form") == ["§6a", "§6a", "§0.1"]
    end

    test "the heading line itself is inside its own section" do
      assert Citations.sections("## §7 escalations") == ["§7"]
    end

    test "and the real document's sections are read, not guessed" do
      found = Citations.read_document() |> Citations.line_citations()

      assert found |> MapSet.new(& &1.section) |> Enum.sort() == ["§2", "§6", "§6a", "§8"]
    end
  end

  describe "code spans" do
    test "a double-backtick span keeps its inner backticks" do
      assert Citations.code_spans("`` a `b` c ``") == [%{text: "a `b` c", line: 1}]
    end

    test "the real key that contains backticks survives extraction" do
      key =
        "MCP.Protocol.Types.ToolTest/test inputSchema keywords beyond `type` are carried " <>
          "verbatim, including `not` and `$anchor`"

      assert Citations.keys("`` #{key} ``") == [key]
    end

    test "lines are 1-based and reported per line" do
      assert Citations.code_spans("x\ny `k`") == [%{text: "k", line: 2}]
    end
  end
end

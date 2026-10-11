defmodule MCP.Conformance.ETCCTagsSourceMarksTest do
  @moduledoc """
  `MCP.Conformance.ETCCTags.source_marks/2` — the reader behind the stray
  direction of `mix conformance.etcc_tags --check` (MES-166).

  Both directions, because either alone passes over the other: a mark inside a
  string or sigil literal is not counted, **and** a real mark still is. The
  end-to-end evidence — the real task over a planted tree, and the mutations that
  turn each direction red — is `conformance/controls/etcc_tags_controls.exs
  source_strays` and `source_strays_mutation`.

  This file is itself a planted literal: every `@tag :etcc` in it is inside a
  string, so `--check` over the whole tree stays at 0 stray only while the reader
  holds.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.ETCCTags

  defp marks(source), do: ETCCTags.source_marks(source, "plant_test.exs")

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "a tag line inside an ~S heredoc is not a mark — the MES-160 fixture shape" do
    source = ~S"""
    defmodule PlantTest do
      use ExUnit.Case

      test "builds a module" do
        src = ~S'''
        @tag :etcc
        test "x", do: :ok
        '''

        assert src
      end
    end
    """

    assert {:ok, []} = marks(source)
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "a tag line inside a plain heredoc string is not a mark" do
    source = ~S'''
    defmodule PlantTest do
      use ExUnit.Case

      test "builds a module" do
        src = """
        @tag :etcc
        test "x", do: :ok
        """

        assert src
      end
    end
    '''

    assert {:ok, []} = marks(source)
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "a doctest directive inside a heredoc is not a mark" do
    source = ~S"""
    defmodule PlantTest do
      use ExUnit.Case

      @fixture ~S'''
      doctest Some.Module, tags: [:etcc]
      '''

      test "reads the fixture", do: assert(@fixture)
    end
    """

    assert {:ok, []} = marks(source)
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "a real tag is a mark, at its own line" do
    source = ~S"""
    defmodule PlantTest do
      use ExUnit.Case

      @tag :etcc
      test "planted", do: :ok
    end
    """

    assert {:ok, [{4, :tag}]} = marks(source)
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "a real doctest directive carrying the tag is a mark, wherever the tag sits in the list" do
    source = ~S"""
    defmodule PlantTest do
      use ExUnit.Case
      doctest Some.Module, tags: [:etcc]
      doctest Other.Module, tags: [:other, :etcc]
      doctest Third.Module, tags: [:etcc, :other]
    end
    """

    assert {:ok, [{3, :directive}, {4, :directive}, {5, :directive}]} = marks(source)
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "layout does not matter — parentheses, a trailing comment, a continuation line" do
    # Every one of these is a real mark the line scan never saw (MES-166 F1).
    source = ~S"""
    defmodule PlantTest do
      use ExUnit.Case
      doctest(Some.Module, tags: [:etcc])

      doctest Other.Module,
        tags: [:etcc]

      @tag(:etcc)
      test "parenthesised", do: :ok

      @tag :etcc # a trailing comment
      test "commented", do: :ok
    end
    """

    assert {:ok, [{3, :directive}, {5, :directive}, {8, :tag}, {11, :tag}]} = marks(source)
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "a literal and a real mark in one source: only the real one counts" do
    source = ~S"""
    defmodule PlantTest do
      use ExUnit.Case

      test "builds a module" do
        src = ~S'''
        @tag :etcc
        test "x", do: :ok
        '''

        assert src
      end

      @tag :etcc
      test "planted", do: :ok
    end
    """

    assert {:ok, [{13, :tag}]} = marks(source)
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "other tags, untagged doctests and the out-of-scope forms are not marks" do
    # @moduletag, @describetag and the keyword form are out of scope by ruling
    # (MES-166 31909): pinned here so a widening is a decision, not a drift.
    source = ~S"""
    defmodule PlantTest do
      use ExUnit.Case
      @moduletag :etcc
      doctest Some.Module
      doctest Some.Module, tags: [:other]

      describe "d" do
        @describetag :etcc
        @tag :other
        @tag etcc: true
        test "planted", do: :ok
      end
    end
    """

    assert {:ok, []} = marks(source)
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "a source that does not parse is an error naming the file, never an empty list" do
    source = ~S"""
    defmodule PlantTest do
      @tag :etcc
      test "planted", do: :ok
    """

    assert {:error, reason} = marks(source)
    assert reason =~ "plant_test.exs:"
  end

  @tag oc: :none
  @tag oc_reason: "instrument unit (etcc_tags source reader); no OC counterpart"
  test "a source that is not UTF-8 is an error naming the file, never a raise" do
    # Code.string_to_quoted/2 RAISES UnicodeConversionError here rather than
    # returning an error (MES-166 F2).
    source = "defmodule PlantTest do\n  @tag :etcc\n  @a \"" <> <<0xFF>> <> "\"\nend\n"

    assert {:error, reason} = marks(source)
    assert reason =~ "plant_test.exs: not valid UTF-8"
  end
end

defmodule MCP.Conformance.ClaudeMdCapTest do
  @moduledoc """
  `MCP.Conformance.ClaudeMdCap`, unit by unit, and the cap applied to this repository.

  The last test is the one that matters on every ticket: it puts the 16 KiB cap and the
  two-way index under gate 5, so a branch that grows the core past the cap, orphans a
  procedure page or leaves a dangling pointer is red at its own merge gate — a PM Task's
  included. The units are the pairing that makes that green mean something: each reason is
  shown firing on bytes built to provoke it. The tree-level controls, with a mutation mode,
  are `conformance/controls/claude_md_cap_controls.exs`.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.ClaudeMdCap

  @pages ["docs/procedure/a.md", "docs/procedure/b.md"]

  defp core(entries, extra \\ "") do
    """
    # Core

    #{extra}
    #{ClaudeMdCap.index_heading()}

    #{Enum.map_join(entries, "\n", &"- `#{&1}` — read it when needed.")}

    ## Critical Rules

    - `docs/procedure/not-the-index.md` is outside the index and does not count.
    """
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "a core within the cap whose index names exactly the pages passes" do
    assert ClaudeMdCap.check(core(@pages), @pages) == :ok
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "the cap is 16,384 bytes: exactly the cap passes, one byte over is refused" do
    base = core(@pages)
    at_cap = base <> String.duplicate("x", ClaudeMdCap.cap() - byte_size(base))

    assert byte_size(at_cap) == 16_384
    assert ClaudeMdCap.check(at_cap, @pages) == :ok

    assert ClaudeMdCap.check(at_cap <> "x", @pages) ==
             {:error, [{:over_cap, 16_385, 16_384}]}
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "an index entry with no page behind it is refused as dangling" do
    named = @pages ++ ["docs/procedure/ghost.md"]

    assert ClaudeMdCap.check(core(named), @pages) ==
             {:error, [{:dangling, ["docs/procedure/ghost.md"]}]}
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "a page the index does not name is refused as an orphan" do
    pages = @pages ++ ["docs/procedure/orphan.md"]

    assert ClaudeMdCap.check(core(@pages), pages) ==
             {:error, [{:orphans, ["docs/procedure/orphan.md"]}]}
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "no index section is refused, and so is more than one" do
    assert ClaudeMdCap.check("# Core\n", []) == {:error, [:no_index]}

    twice = core(@pages, ClaudeMdCap.index_heading() <> "\n")
    assert ClaudeMdCap.check(twice, @pages) == {:error, [{:duplicate_index, 2}]}
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "only backticked docs/procedure paths inside the index section are entries" do
    assert ClaudeMdCap.index(core(@pages)) == {:ok, @pages}
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "an unnamed page in a subdirectory is not a page: non_page_entry, not passed green" do
    entries = @pages ++ [{"docs/procedure/sub", :directory}, "docs/procedure/sub/hidden.md"]

    assert ClaudeMdCap.check(core(@pages), entries) ==
             {:error,
              [{:non_page_entry, ["docs/procedure/sub/", "docs/procedure/sub/hidden.md"]}]}
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "a non-.md file and a symlink are not pages" do
    entries = @pages ++ ["docs/procedure/notes.txt", {"docs/procedure/link.md", :symlink}]

    assert ClaudeMdCap.check(core(@pages), entries) ==
             {:error, [{:non_page_entry, ["docs/procedure/link.md", "docs/procedure/notes.txt"]}]}
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "a nested path named in the index is non_page_entry, present or not, never dangling" do
    named = @pages ++ ["docs/procedure/sub/hidden.md"]

    assert ClaudeMdCap.index(core(named)) == {:ok, @pages}
    assert ClaudeMdCap.nested_named(core(named)) == ["docs/procedure/sub/hidden.md"]

    assert ClaudeMdCap.check(core(named), @pages ++ ["docs/procedure/sub/hidden.md"]) ==
             {:error, [{:non_page_entry, ["docs/procedure/sub/hidden.md"]}]}

    assert ClaudeMdCap.check(core(named), @pages) ==
             {:error, [{:non_page_entry, ["docs/procedure/sub/hidden.md"]}]}
  end

  @tag oc: :none
  @tag oc_reason:
         "repository docs layout (CLAUDE.md cap and index); no OC check covers repository docs"
  test "this repository's CLAUDE.md is within the cap and its index matches docs/procedure/" do
    assert ClaudeMdCap.check_tree(File.cwd!()) == :ok
  end
end

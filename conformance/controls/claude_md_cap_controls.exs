# Controls for the CLAUDE.md size cap and the docs/procedure/ index (MES-177).
#
#     mix run conformance/controls/claude_md_cap_controls.exs
#     mix run conformance/controls/claude_md_cap_controls.exs mutation
#
# WHAT THIS IS EVIDENCE OF. `MCP.Conformance.ClaudeMdCap` refuses a core CLAUDE.md over
# 16,384 bytes, an index entry with no page behind it (dangling), a page the index does not
# name (orphan), and a core with no index or two. Each case below BUILDS the tree it is
# about — a CLAUDE.md and a docs/procedure/ directory under a root generated per run — and
# drives the real module over it with `check_tree/1`.
#
# P1 IS NOT DECORATION. A check that refused everything would "pass" every red case
# vacuously; P1 (this branch's own files) and P2 (a copy padded to exactly the cap) are the
# greens that make R1-R10 mean anything.
#
# EVERY RED IS ADJUDICATED ON ITS REASON CLASS, not on a bare refusal: R1's tree is also
# missing an index, so "refused" alone would pass R1 even with the cap check gone. R7-R10
# (correction round 1, F1: the layout is flat) require non_page_entry and NOTHING else, so
# R9 — a subdirectory page that is also named — cannot pass by being called dangling.
#
# THE MUTATIONS ARE IN MEMORY. `mutation` reads the module's source, neutralises ONE
# predicate by exact string replacement, compiles the result under a throwaway module name,
# and requires the case that predicate answers to go red. The source file is never written.
#
# R1's "current file" is CLAUDE.md as it stood at e74bf3f (2.0.0-dev.81, 57,816 bytes),
# read from git, so it stays the pre-MES-177 file after this branch merges.

defmodule ClaudeMdCapControls do
  alias MCP.Conformance.ClaudeMdCap

  @project File.cwd!()
  @pre_move "e74bf3f"
  @source "conformance/lib/mcp/conformance/claude_md_cap.ex"

  # {id, mutation, the exact source text, its replacement, the case that must go red}
  @mutations [
    {"M1", "cap check removed", "do: byte_size(bytes) > @cap", "do: false", ["R1", "R2"]},
    {"M2", "dangling check removed", "def dangling(named, pages), do: Enum.sort(named -- pages)",
     "def dangling(_named, _pages), do: []", ["R3"]},
    {"M3", "orphan check removed", "def orphans(named, pages), do: Enum.sort(pages -- named)",
     "def orphans(_named, _pages), do: []", ["R4"]},
    {"M4", "index-presence check removed", "defp index_refusal([]), do: :no_index",
     "defp index_refusal([]), do: nil", ["R5"]},
    {"M5", "duplicate-index check removed",
     "defp index_refusal(many), do: {:duplicate_index, length(many)}",
     "defp index_refusal(_many), do: nil", ["R6"]},
    {"M6", "non-page check removed",
     "def non_pages(entries),\n    do: entries |> Enum.reject(&page?/1) |> Enum.map(&label/1) |> Enum.uniq() |> Enum.sort()",
     "def non_pages(_entries), do: []", ["R7", "R8", "R9", "R10"]}
  ]

  def run([]) do
    in_root(fn root ->
      Enum.map(cases(root), fn {id, what, tree, want} ->
        report(id, what, ClaudeMdCap.check_tree(tree), want)
      end)
    end)
  end

  def run(["mutation"]) do
    in_root(fn root ->
      cases = cases(root)
      source = File.read!(Path.join(@project, @source))

      Enum.map(@mutations, fn {mid, what, from, to, reds} ->
        mutant = compile_mutant(source, mid, from, to)

        flipped =
          for {id, _what, tree, want} <- cases, id in reds do
            {id, !satisfied?(mutant.check_tree(tree), want)}
          end

        ok = flipped != [] and Enum.all?(flipped, &elem(&1, 1))

        check(
          "#{mid}/#{Enum.join(reds, ",")}",
          "with the #{what}, #{Enum.join(reds, " and ")} go red — shown able to fail\n" <>
            "        #{inspect(flipped)}",
          ok
        )
      end)
    end)
  end

  def run(_) do
    IO.puts("usage: mix run conformance/controls/claude_md_cap_controls.exs [mutation]")
    System.halt(2)
  end

  # --- the cases ----------------------------------------------------------------

  defp cases(root) do
    core = File.read!(Path.join(@project, "CLAUDE.md"))
    pages = real_pages()
    pre_move = git!(["show", "#{@pre_move}:CLAUDE.md"])
    at_cap = pad(core, ClaudeMdCap.cap())
    [heading] = Regex.run(~r/^#{Regex.escape(ClaudeMdCap.index_heading())}$/m, core)
    no_index = String.replace(core, heading <> "\n", "")

    [
      {"P1", "this branch's CLAUDE.md (#{byte_size(core)} B) and docs/procedure/ pass",
       tree(root, "p1", core, pages), :ok},
      {"P2", "a copy padded to exactly #{byte_size(at_cap)} B passes — the cap is inclusive",
       tree(root, "p2", at_cap, pages), :ok},
      {"R1", "CLAUDE.md at #{@pre_move} (#{byte_size(pre_move)} B) is over the cap",
       tree(root, "r1", pre_move, pages), :over_cap},
      {"R2", "a copy padded to #{byte_size(at_cap) + 1} B is over the cap",
       tree(root, "r2", at_cap <> "x", pages), :over_cap},
      {"R3", "an index entry naming docs/procedure/ghost.md, which does not exist, dangles",
       tree(root, "r3", add_entry(core, "docs/procedure/ghost.md"), pages), :dangling},
      {"R4", "docs/procedure/orphan.md, which the index does not name, is an orphan",
       tree(root, "r4", core, pages ++ [{"docs/procedure/orphan.md", "# Orphan\n"}]), :orphans},
      {"R5", "a core with its index heading removed (and no pages) has no index",
       tree(root, "r5", no_index, []), :no_index},
      {"R6", "a core carrying the index heading twice is refused",
       tree(root, "r6", String.replace(core, heading, heading <> "\n\n" <> heading), pages),
       :duplicate_index},
      {"R7", "an unnamed docs/procedure/sub/hidden.md is not a page: non_page_entry",
       tree(root, "r7", core, pages ++ [{"docs/procedure/sub/hidden.md", "# Hidden\n"}]),
       {:exactly, [:non_page_entry]}},
      {"R8", "an unnamed docs/procedure/notes.txt is not a page: non_page_entry",
       tree(root, "r8", core, pages ++ [{"docs/procedure/notes.txt", "notes\n"}]),
       {:exactly, [:non_page_entry]}},
      {"R9", "docs/procedure/sub/hidden.md, present AND named: non_page_entry, not dangling",
       tree(
         root,
         "r9",
         add_entry(core, "docs/procedure/sub/hidden.md"),
         pages ++ [{"docs/procedure/sub/hidden.md", "# Hidden\n"}]
       ), {:exactly, [:non_page_entry]}},
      {"R10", "a named docs/procedure/sub/ghost.md with nothing behind it: non_page_entry",
       tree(root, "r10", add_entry(core, "docs/procedure/sub/ghost.md"), pages),
       {:exactly, [:non_page_entry]}}
    ]
  end

  defp real_pages do
    @project
    |> Path.join("docs/procedure/*.md")
    |> Path.wildcard()
    |> Enum.map(&{Path.join("docs/procedure", Path.basename(&1)), File.read!(&1)})
  end

  defp add_entry(core, path) do
    [heading] = Regex.run(~r/^#{Regex.escape(ClaudeMdCap.index_heading())}$/m, core)

    String.replace(
      core,
      heading,
      heading <> "\n\n- `#{path}` — a pointer with nothing behind it."
    )
  end

  defp pad(bytes, size), do: bytes <> String.duplicate("x", size - byte_size(bytes))

  defp tree(root, name, claude_md, pages) do
    dir = Path.join(root, name)
    File.mkdir_p!(Path.join(dir, "docs/procedure"))
    File.write!(Path.join(dir, "CLAUDE.md"), claude_md)

    Enum.each(pages, fn {rel, body} ->
      File.mkdir_p!(Path.dirname(Path.join(dir, rel)))
      File.write!(Path.join(dir, rel), body)
    end)

    dir
  end

  # --- adjudication -------------------------------------------------------------

  defp satisfied?(:ok, :ok), do: true

  defp satisfied?({:error, reasons}, {:exactly, classes}),
    do: Enum.sort(Enum.map(reasons, &class/1)) == Enum.sort(classes)

  defp satisfied?({:error, reasons}, class) when class != :ok,
    do: Enum.any?(reasons, &(&1 == class or (is_tuple(&1) and elem(&1, 0) == class)))

  defp satisfied?(_, _), do: false

  defp class(reason) when is_tuple(reason), do: elem(reason, 0)
  defp class(reason), do: reason

  defp report(id, what, got, want) do
    check(
      id,
      "#{what}\n        got: #{inspect(got)}   wanted: #{inspect(want)}",
      satisfied?(got, want)
    )
  end

  defp check(id, what, ok) do
    IO.puts("  #{if ok, do: "PASS", else: "FAIL"}  #{id}  #{what}")
    ok
  end

  # --- plumbing -----------------------------------------------------------------

  defp compile_mutant(source, mid, from, to) do
    unless String.contains?(source, from) do
      raise "CANNOT MUTATE — #{mid}'s target text is not in #{@source}: #{inspect(from)}. " <>
              "The predicate was rewritten; update the mutation, or every case it answers " <>
              "is unfalsified."
    end

    name = "ClaudeMdCapMutant#{mid}#{System.unique_integer([:positive])}"

    mutated =
      source
      |> String.replace(from, to)
      |> String.replace("defmodule MCP.Conformance.ClaudeMdCap do", "defmodule #{name} do")

    [{module, _} | _] = Code.compile_string(mutated)
    module
  end

  defp git!(args) do
    {out, 0} = System.cmd("git", ["-C", @project | args])
    out
  end

  defp in_root(fun) do
    root =
      Path.join(System.tmp_dir!(), "claude_md_cap_controls_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    failed =
      try do
        results = fun.(root)
        failed = Enum.count(results, &(!&1))
        IO.puts("\n  #{length(results)} control(s), #{failed} failed")
        failed
      after
        File.rm_rf!(root)
      end

    # Halt only after the fixture root is gone: System.halt/1 does not run `after`.
    if failed > 0, do: System.halt(1)
  end
end

ClaudeMdCapControls.run(System.argv())

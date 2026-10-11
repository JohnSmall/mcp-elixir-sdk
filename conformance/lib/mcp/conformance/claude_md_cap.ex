defmodule MCP.Conformance.ClaudeMdCap do
  @moduledoc """
  The size cap on the core `CLAUDE.md`, and the index that keeps `docs/procedure/` reachable
  from it (MES-177).

  **Why a cap.** Codex loads project docs only up to `project_doc_max_bytes` — 32 KiB in
  total across every `AGENTS.md` on its path. At 57,816 B the old `CLAUDE.md` was cut off at
  byte 32,768 and the seat's own `AGENTS.md` never loaded (ACM-38 31967). The PO set the core's
  cap at **16 KiB** (2026-10-11), leaving the other half for the seat file.

  **Why the index is checked in both directions.** Moving procedure text out of the core is
  only safe while the core still says where it went. A page in `docs/procedure/` that the
  index does not name is unreachable from the one file every seat loads (an **orphan**); an
  index entry with no page behind it sends a seat to nothing (**dangling**). Either alone is
  silent, so both are refusals.

  **The layout is flat, and enforced.** A page is a regular file directly in
  `docs/procedure/` whose name ends `.md`. Both directions quantify over that one population.
  Every other entry under `docs/procedure/`, found by a recursive walk (a subdirectory, a
  file inside one, a non-`.md` file, a symlink), is refused as `{:non_page_entry, paths}`,
  and so is a backticked `docs/procedure/` path in the index that is not flat. Without
  this, a page in a subdirectory or a `gate-8.txt` would be an orphan the check passes
  green, and the index and the page list would disagree about what a page is (MES-177 F1).

  **Residual: the index is read syntactically.** Any backticked flat path inside the
  section counts as named, including one in a sentence that says *not* to read it. The
  check proves that every page is mentioned there, not that the mention is a pointer.

  `check/2` is a pure function of the bytes and the page list. `check_tree/1` reads them
  off a tree, and is what the gate-5 unit and
  `conformance/controls/claude_md_cap_controls.exs` drive. The predicates are kept one per
  function, each on one line, so the controls' `mutation` mode can neutralise exactly one.
  """

  @cap 16_384
  @index_heading "## Where the procedure lives"
  @procedure_dir "docs/procedure"
  @flat_page ~r{\Adocs/procedure/[^/]+\.md\z}

  @type reason ::
          {:over_cap, non_neg_integer(), pos_integer()}
          | :no_index
          | {:duplicate_index, pos_integer()}
          | {:dangling, [String.t()]}
          | {:orphans, [String.t()]}
          | {:non_page_entry, [String.t()]}

  @typedoc """
  An entry under `docs/procedure/`, repository-relative. A bare path is a regular file;
  otherwise it carries its `File.lstat/1` type (`:directory`, `:symlink`, …), or
  `:index_entry` for a path named in the index.
  """
  @type entry :: String.t() | {String.t(), atom()}

  @doc "The cap on `CLAUDE.md`, in bytes."
  @spec cap() :: pos_integer()
  def cap, do: @cap

  @doc "The heading the index lives under."
  @spec index_heading() :: String.t()
  def index_heading, do: @index_heading

  @doc "Whether `CLAUDE.md`'s bytes exceed the cap."
  @spec over_cap?(binary()) :: boolean()
  def over_cap?(bytes) when is_binary(bytes), do: byte_size(bytes) > @cap

  @doc "Whether an entry is a page: a regular `.md` file directly in `docs/procedure/`."
  @spec page?({String.t(), atom()}) :: boolean()
  def page?({path, type}), do: type == :regular and Regex.match?(@flat_page, path)

  @doc "Entries that are not pages, sorted; a directory is shown with a trailing `/`."
  @spec non_pages([{String.t(), atom()}]) :: [String.t()]
  def non_pages(entries),
    do: entries |> Enum.reject(&page?/1) |> Enum.map(&label/1) |> Enum.uniq() |> Enum.sort()

  defp label({path, :directory}), do: path <> "/"
  defp label({path, _type}), do: path

  @doc "Index entries with no page behind them."
  @spec dangling([String.t()], [String.t()]) :: [String.t()]
  def dangling(named, pages), do: Enum.sort(named -- pages)

  @doc "Pages the index does not name."
  @spec orphans([String.t()], [String.t()]) :: [String.t()]
  def orphans(named, pages), do: Enum.sort(pages -- named)

  @doc """
  The flat `docs/procedure/<name>.md` paths named (in backticks) in the index section: the
  lines after `#{@index_heading}` up to the next heading of level 1 or 2. `{:error, reason}`
  when there is no such section, or more than one. A named path with a `/` after
  `docs/procedure/` is not a page name; `nested_named/1` returns those.
  """
  @spec index(binary()) :: {:ok, [String.t()]} | {:error, reason()}
  def index(claude_md) do
    with {:ok, text} <- index_text(claude_md) do
      {:ok, Enum.filter(backticked(text), &Regex.match?(@flat_page, &1))}
    end
  end

  @doc "Backticked `docs/procedure/` paths in the index section that are not flat page names."
  @spec nested_named(binary()) :: [String.t()]
  def nested_named(claude_md) do
    case index_text(claude_md) do
      {:ok, text} -> Enum.reject(backticked(text), &Regex.match?(@flat_page, &1))
      {:error, _} -> []
    end
  end

  defp index_text(claude_md) do
    sections = index_sections(String.split(claude_md, "\n"))

    case index_refusal(sections) do
      nil -> {:ok, Enum.join(Enum.concat(sections), "\n")}
      reason -> {:error, reason}
    end
  end

  defp backticked(text) do
    ~r/`(#{@procedure_dir}\/[^`\s]+)`/
    |> Regex.scan(text)
    |> Enum.map(&Enum.at(&1, 1))
    |> Enum.uniq()
  end

  defp index_refusal([]), do: :no_index
  defp index_refusal([_one]), do: nil
  defp index_refusal(many), do: {:duplicate_index, length(many)}

  defp index_sections(lines) do
    lines
    |> Enum.chunk_while(
      nil,
      fn line, acc ->
        cond do
          line == @index_heading -> emit(acc, [])
          is_list(acc) and Regex.match?(~r/^\#{1,2} /, line) -> emit(acc, nil)
          is_list(acc) -> {:cont, [line | acc]}
          true -> {:cont, acc}
        end
      end,
      fn acc -> emit(acc, nil) end
    )
    |> Enum.map(&Enum.reverse/1)
  end

  defp emit(nil, next), do: {:cont, next}
  defp emit(acc, next), do: {:cont, acc, next}

  @doc """
  Every refusal for these bytes and these entries under `docs/procedure/`, or `:ok`.
  Entries are repository-relative, e.g. `"docs/procedure/lanes.md"` (see `t:entry/0`).
  """
  @spec check(binary(), [entry()]) :: :ok | {:error, [reason()]}
  def check(claude_md, entries) when is_binary(claude_md) and is_list(entries) do
    entries = Enum.map(entries, &typed/1)

    case size_refusals(claude_md) ++
           non_page_refusals(claude_md, entries) ++ index_refusals(claude_md, entries) do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  defp size_refusals(claude_md) do
    if over_cap?(claude_md), do: [{:over_cap, byte_size(claude_md), @cap}], else: []
  end

  defp non_page_refusals(claude_md, entries) do
    named_nested = for path <- nested_named(claude_md), do: {path, :index_entry}

    case non_pages(entries ++ named_nested) do
      [] -> []
      paths -> [{:non_page_entry, paths}]
    end
  end

  defp index_refusals(claude_md, entries) do
    pages = for entry <- entries, page?(entry), do: elem(entry, 0)

    case index(claude_md) do
      {:ok, named} ->
        Enum.reject(
          [{:dangling, dangling(named, pages)}, {:orphans, orphans(named, pages)}],
          &match?({_, []}, &1)
        )

      {:error, reason} ->
        [reason]
    end
  end

  defp typed({_path, _type} = entry), do: entry
  defp typed(path) when is_binary(path), do: {path, :regular}

  @doc """
  `check/2` over the `CLAUDE.md` of the tree at `root` and EVERY entry under its
  `docs/procedure/`, walked recursively without following symlinks.
  """
  @spec check_tree(Path.t()) :: :ok | {:error, [reason()]}
  def check_tree(root) do
    check(File.read!(Path.join(root, "CLAUDE.md")), walk(root, @procedure_dir))
  end

  defp walk(root, rel) do
    case File.ls(Path.join(root, rel)) do
      {:ok, names} -> Enum.flat_map(Enum.sort(names), &walk_entry(root, Path.join(rel, &1)))
      {:error, _} -> []
    end
  end

  defp walk_entry(root, path) do
    {:ok, %File.Stat{type: type}} = File.lstat(Path.join(root, path))
    if type == :directory, do: [{path, type} | walk(root, path)], else: [{path, type}]
  end
end

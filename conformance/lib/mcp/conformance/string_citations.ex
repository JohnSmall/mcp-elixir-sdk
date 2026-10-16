defmodule MCP.Conformance.StringCitations do
  @moduledoc """
  **Guard 33**: every string-form `file:N` citation written in
  `conformance/data/` and `docs/conformance/` is in a committed ledger, and a
  pinned one still has, at the address it gives, the bytes it was pinned to.

  Established by MES-192 (MES-167 split d), in the D2 form the PO chose on
  MES-167 Q7 (MES-192 32403) and ratified as a plan on MES-192 (32773-32778,
  ruling 32779). It runs in gate 5 (PO ruling, 32571 Q1), through
  `test/conformance/string_citations_test.exs`.

  ## Why a ledger of bytes

  MES-167 measured 7000 such citations, 1465 of them stale by intent, and 92% of
  those under no guard. A citation that has drifted onto another real line reads
  as correct and is not (the S8-2 hazard). A check that the address merely
  resolves would have caught 20% of them. So each citation is pinned to the
  sha256 of the window it cites, whitespace-squashed with
  `MCP.Conformance.Adjudications.squash/1` (G32's own normal form, so a
  `mix format` reflow is not a red). A `lib/` or `test/` edit that moves or
  rewrites a cited line goes red on the ticket that made it.

  ## The occurrence, and its key

  The ledger is `test/fixtures/conformance/string-citations-ledger.json`. It has
  one row per OCCURRENCE, keyed `{art, at_path, cite, nth}`. In a JSON artefact
  `at_path` is the leaf's path with list elements addressed by RECORD IDENTITY,
  `MCP.Conformance.InputFigures.record_ids/1`, so inserting a record moves no
  other key (G31's rule, reused rather than restated). In a Markdown artefact it
  is the nearest ATX heading outside a code fence. `nth` counts the same
  citation text within one leaf. The bare string is never the key: one string
  can be an earlier, different citation (MES-167 E1).

  ## The universe is re-derived on every run

  The files are `git ls-files` under the two roots. Every JSON string, and every
  object key, is read. That set is compared with the ledger both ways:
  `unledgered` (a citation added) and `ledger_orphan` (a citation removed, or a
  row written by hand). A second, raw scan of each file must find the SAME
  sequence of citations as the structured reader (`structured_parity`), so a
  reader that drops a leaf, a key or a file is refused even when the ledger has
  been regenerated to match it. A run that visits nothing is refused (`reach`).

  ## The grammar

  A citation is `(path|basename).ex[s]:N` or `…:N-M` (a hyphen, an en dash, or
  its JSON escape). Before it: not a word character, `.`, `/` or `-`. After it:
  not a digit. Refused as found: `:0` and a reversed range (`bad_range`),
  `x.ex:N:M` and an ordinal `x.ex:12th` (`bad_shape`), a token naming no tracked
  `.ex`/`.exs` (`unresolved`, unless an `external` row), and a basename two
  tracked files share (`doubled_basename`, unless allow-listed and the row names
  its target). A row for a shared basename whose citing leaf writes exactly one
  candidate's full path must pin that file (`target_contradicted`, MES-192
  correction round 1, F1). NOT read, by design: bare `:N` continuations (MES-196), other
  extensions (`.md`, `.json`, `.ts`, `.mdx`), and prose forms such as
  "line N of f".

  ## Each row has a state, and every state but two names who holds it

    * `pin`: the window is hashed at the tip.
    * `at`: hashed at a named ancestor commit (`anchor_invalid`, `at_drift`).
      Classes: `et_test_at` (a cite of the row's `et_test` file in a row whose
      `et_test` carries `at`), `publication` (a dated MES-58 publication),
      `dated_prose` (the leaf names the commit).
    * `held`: another guard holds this occurrence, so it is not byte-checked
      here. Each class is admitted only inside its HOLDER's read domain, keyed
      by artefact and by occurrence and derived from the holder itself, so a
      label alone cannot exempt a citation (`state_unwarranted`; MES-192
      correction round 1, F2):
        - `g32_bytes`, `g32_anchor_entry`: a record in G32's walk
          (`Adjudications.walk_root/0`), the leaf in a map G32's
          `Adjudications.collect/1` takes as a citation;
        - `g32_prose_anchor`: a record in G32's walk, the leaf a field a prose
          anchor on its map names, with that citation;
        - `g29`: an occurrence `Citations.line_citations/1` reads in
          `Citations.document/0`, within the per-section permit;
        - `attribution_citations`: an `.exs` cite that `AttributionCitations`
          reads in a section it audits, in `ETCCAttribution.paths().prose`.
      Each domain comes from calling the holder's own code, never from reading
      a holder's source text: a reader inferred from text can be emptied (a
      filter, a guard, a skip tag) while the text stays (MES-192 correction
      round 2, R1). So the `asserts_read` heads that `adjudications_test.exs`
      checks are not held: each is pinned, at the tip, or at its row's
      `et_test` commit where that test reads the row there.
    * `snapshot`: `sweep_measurement`, the generated `live_units` lists of
      `etcc-boundaries.json`.
    * `stale`: known stale, with an owning ticket and a reason, counted against
      a ceiling that only shrinks (`stale_over_ceiling`).
    * `external`: names no tracked file (stdlib); red if it ever resolves.
    * `not_a_cite`: `fixture`, an address deliberately past the end of its file;
      red if it ever comes into range.

  ## The schema reads first

  The ledger's document shape, then each row and each window, is checked
  before anything else reads a value of it: `context/1` splits the rows the
  schema passes from those it refuses, and every limb, `--repin` and
  `--resolve` read only the first. A refused row reaches only the rows limb,
  which describes it through one total renderer, so a malformed ledger is
  refused at every entry point and never raised on (MES-192 correction rounds
  3-5). Control C27a plants every JSON type into every field of every state,
  the field list read from this module's own schema declaration.

  ## The fixing command is named by every refusal

  `mix conformance.string_citations` audits. `--resolve` re-addresses a moved
  window by the MES-84 E2 / M1 invariant, except a citation that
  `InputFigures.identity_paths/1` reads as an enclosing record's identity
  (`in_record_identity`: rewriting it would re-key that record's G31 paths). `--repin` adds and drops rows, and
  re-pins a window rewritten in place only when that window is named with
  `--accept`. Neither writes under `mix test`.

  ## What it does NOT establish

    * That a pinned citation was RIGHT when pinned. The pins are the authored
      bytes (MES-192 32775: no census-intact pin differs at its own
      introduction), and the M1 class certifies byte movement only (MES-167
      residual ii).
    * That the sentence still describes the bytes. An edit that keeps the bytes
      and changes the meaning is invisible here.
    * Swapping one `stale` or `target_by: order` row for another at a constant
      count passes the ceiling. A ceiling bounds a count, not a set.
    * The forms the grammar does not read, and the `held` and `snapshot`
      occurrences, which are byte-checked elsewhere or not at all.
    * Path evidence beyond the association grammar (`associated_targets/2`):
      punctuation inside a code span ends a sentence there as anywhere else,
      and a sentence that runs across two Markdown lines binds nothing, since
      a Markdown leaf is its line (MES-192 correction round 3).
  """

  alias MCP.Conformance.{
    Adjudications,
    AttributionCitations,
    Citations,
    ETCCAttribution,
    InputFigures
  }

  @guard "G33"
  @roots ["conformance/data", "docs/conformance"]
  @ledger_path "test/fixtures/conformance/string-citations-ledger.json"

  # ONE line-citation shape, EXT its extension. The reader takes `.ex`/`.exs`;
  # the separator of the association grammar takes every extension, so a
  # citation of any file stands between a cite and a path (S3).
  @line_cite ~S"(?<![\w.\/-])((?:[\w.-]+\/)*[\w.-]+\.(?:EXT)):(\d+)(?:(-|–|\\u2013)(\d+))?(?!\d)"
  @cite_src String.replace(@line_cite, "EXT", "exs?")
  @any_cite_src String.replace(@line_cite, "EXT", "[A-Za-z0-9]+")
  @cite ~r/#{@cite_src}/u
  # The walk's starting state (see walk/4).
  @walk_start %{ancestors: [], et_at: nil, identity: MapSet.new()}
  # The kinds the guard builds at runtime (a token's shape, refused as
  # `d(o.shape, ...)`): declared once, read by shape/3 and by runtime_kinds/0,
  # which control C26 holds to a fix each (T3).
  @shape_kinds %{range: :bad_range, shape: :bad_shape}
  @after_bad ~r/\A(?::\d|(?:st|nd|rd|th)(?![A-Za-z]))/

  @states ~w(pin at held snapshot stale external not_a_cite)
  @classes %{
    "at" => ~w(et_test_at publication dated_prose),
    "held" => ~w(g32_prose_anchor g32_anchor_entry g32_bytes g29 attribution_citations),
    "snapshot" => ~w(sweep_measurement),
    "not_a_cite" => ~w(fixture)
  }
  @row_fields ~w(cite nth state class owner at target target_by reason)

  @publications ~w(
    docs/conformance/report-2026-07-28.md
    docs/conformance/confluence/report-2026-07-28.json
  )
  # The one generated list BoundarySweep reads at the root of its table. It
  # has no public reader, and adding one would edit a gate-8 trigger source
  # (boundary_sweep.ex), so it is named here; the per-record lists come from
  # BoundarySweep.measurement_fields/0 and the table from BoundarySweep.paths/0.
  @sweep_root_lists ~w(live_column_excluded_units)

  # A basename two tracked files share is admitted only here, and only for the
  # rows that already carry it (the `doubled` ceiling).
  @doubled_allowed ~w(client.ex)

  # Counts that only shrink. Raising one is a reviewed edit to this file, and
  # the gate-5 test pins the same map.
  @ceilings %{
    {"stale", "MES-193"} => 226,
    {"stale", "MES-194"} => 7,
    {"stale", "MES-195"} => 4,
    {"order", "MES-196"} => 80,
    {"doubled", "client.ex"} => 678,
    {"external", "-"} => 5,
    {"not_a_cite", "fixture"} => 1
  }

  # A window whose every line squashes to one of these cites nothing a reader
  # could check, so it is never re-addressed mechanically (MES-84 M1).
  @trivial ["", "end", "end)", "}", "]", ")"]

  @fix %{
    window_drift:
      "mix conformance.string_citations --resolve (a moved window); otherwise correct the cite and run --repin, or, if the cite still means the rewritten line, --repin --accept <target>:<a>-<b>",
    at_drift: "the at commit must hold the cited bytes: correct the row's at or the cite by hand",
    anchor_invalid: "at must be a full sha of an ancestor of HEAD that holds the file",
    unledgered: "mix conformance.string_citations --repin",
    ledger_orphan: "mix conformance.string_citations --repin",
    unresolved:
      "correct or remove the citation in the artefact; if it must stay as it is, make its row stale with an owning ticket (MES-n)",
    doubled_basename: "write the path form of the cite",
    target_mismatch: "the row's target must be a file the cite resolves to",
    target_contradicted: "pin the row to the file the leaf names (target_by: evidence)",
    target_ambiguous:
      "the leaf binds both files to this cite: write the path form, or reword so one path is bound",
    bad_window:
      "a window is a lowercase 64-hex sha256: restore the ledger from git, then --repin",
    bad_range: "correct the cite in the artefact",
    bad_shape: "correct the cite in the artefact",
    state_unwarranted: "the state's holder does not hold this occurrence: make it pin (--repin)",
    bad_row: "rewrite the row by hand; --repin keeps rows it can read",
    stale_over_ceiling: "a ceiling only shrinks: resolve the rows, do not raise it",
    ledger_not_canonical: "mix conformance.string_citations --repin rewrites the canonical form",
    ledger_unreadable: "restore the ledger from git, then --repin",
    structured_parity:
      "the structured reader and the raw scan disagree: fix the reader, or the artefact",
    unreadable: "the artefact cannot be read or decoded",
    reach: "the audit visited nothing: check the root and the roots",
    changed: "the cited construct changed: correct the cite by hand, then --repin",
    moved_ambiguous: "the bytes recur: choose the address by hand, then --repin",
    base_disagrees: "the ledger was already red at the base: resolve that first",
    not_unique_at_base: "the window recurred at the base: choose the address by hand",
    trivial_window: "cite a line that carries the construct",
    target_gone: "the cited file is gone: correct the cite by hand",
    literal_in_instrument: "edit that instrument source and the cite together, by hand",
    in_record_identity: "the cite is part of a record key: re-key by hand",
    out_of_range: "correct the cite in the artefact",
    unknown_accept: "--accept names a pinned window: <target>:<a>-<b>"
  }

  @doc "The guard's label, as every refusal starts."
  def guard, do: @guard

  @doc "The committed ledger's path, relative to the repository root."
  def ledger_path, do: @ledger_path

  @doc "The ratchet ceilings: `{kind, owner}` to the most rows that may carry it."
  def ceilings, do: @ceilings

  # --- the grammar --------------------------------------------------------------

  @doc """
  Every citation token in `text`, in order, with its byte offset.

  `cite` is the citation as a reader sees it (a JSON escape of the en dash
  decoded); `raw` is the bytes as written. `shape` is `:ok`, `:bad_range` or
  `:bad_shape`. For example, "see `plug.ex:12-14`." holds one token, `plug.ex`
  lines 12 to 14, shape `:ok`; "x.ex:3:4 y.exs:12th z.ex:0" holds three, shaped
  `:bad_shape`, `:bad_shape` and `:bad_range`
  (`test/conformance/string_citations_test.exs` asserts both).
  """
  def tokens(text), do: tokens(text, 0, text)

  # Only a text that contains ".ex" can hold a citation; the regex is not run
  # on the rest. `base` is `text`'s offset in `whole`, which supplies the bytes
  # after a match (the shape check may look past the end of a line).
  defp tokens(text, base, whole) do
    if :binary.match(text, ".ex") == :nomatch,
      do: [],
      else: scan(text, base, whole)
  end

  defp scan(text, base, whole) do
    @cite
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{s, l}, {ts, tl}, {as, al} | rest] ->
      raw = binary_part(text, s, l)
      a = String.to_integer(binary_part(text, as, al))

      {sep, b} =
        case rest do
          [{ss, sl}, {bs, bl}] when ss >= 0 ->
            {binary_part(text, ss, sl), String.to_integer(binary_part(text, bs, bl))}

          _ ->
            {nil, a}
        end

      at = base + s + l
      tail = binary_part(whole, at, min(4, byte_size(whole) - at))

      %{
        raw: raw,
        cite: String.replace(raw, "\\u2013", "–"),
        token: binary_part(text, ts, tl),
        a: a,
        b: b,
        sep: sep,
        offset: base + s,
        shape: shape(a, b, tail)
      }
    end)
  end

  defp shape(a, b, tail) do
    cond do
      a == 0 or b < a -> @shape_kinds.range
      Regex.match?(@after_bad, tail) -> @shape_kinds.shape
      true -> :ok
    end
  end

  # --- occurrences --------------------------------------------------------------

  @doc """
  Every citation occurrence in artefact `file`, whose bytes are `bin`, in
  document order. `{:error, {kind, detail}}` when the file cannot be read as
  its kind, or the raw scan and the structured reader disagree.
  """
  def occurrences(file, bin), do: occurrences(file, bin, &unseamed/2)

  defp unseamed(_file, structured), do: structured

  # `seam` (`fn file, structured -> structured`) is reachable only through
  # `control_audit/2`: a control stands in for a reader that drops citations
  # and shows the raw scan refusing it. `audit/1` and `context/1` cannot take
  # one.
  defp occurrences(file, bin, seam) do
    if String.ends_with?(file, ".json"),
      do: json_occurrences(file, bin, seam),
      else: md_occurrences(file, bin, seam)
  end

  defp json_occurrences(file, bin, seam) do
    with {:ok, plain} <- Jason.decode(bin),
         {:ok, ordered} <- Jason.decode(bin, objects: :ordered_objects) do
      structured = seam.(file, ordered |> walk(plain, [], @walk_start) |> number_within_leaf())
      raw = bin |> mask_escapes() |> line_tokens()

      if Enum.map(structured, & &1.cite) == Enum.map(raw, & &1.cite) do
        {:ok, place(file, bin, structured, raw)}
      else
        {:error, {:structured_parity, parity_detail(structured, raw)}}
      end
    else
      {:error, e} -> {:error, {:unreadable, Exception.message(e)}}
    end
  end

  # Escapes are blanked byte for byte (the en-dash escape is a cite's own
  # separator and is kept), so a raw offset is the file's offset.
  defp mask_escapes(bin),
    do:
      Regex.replace(~r/\\(?:u(?!2013)[0-9a-fA-F]{4}|[^u])/, bin, fn m ->
        String.duplicate(" ", byte_size(m))
      end)

  # The raw scan, a line at a time so the regex only meets lines that can match.
  defp line_tokens(bin) do
    {toks, _} =
      bin
      |> String.split("\n")
      |> Enum.flat_map_reduce(0, fn line, pos ->
        {tokens(line, pos, bin), pos + byte_size(line) + 1}
      end)

    toks
  end

  defp parity_detail(structured, raw) do
    s = Enum.map(structured, & &1.cite)
    r = Enum.map(raw, & &1.cite)
    i = Enum.zip(s, r) |> Enum.find_index(fn {x, y} -> x != y end) || min(length(s), length(r))

    "the structured reader found #{length(s)} citation(s), the raw scan #{length(r)}; " <>
      "first difference at position #{i + 1}: #{inspect(Enum.at(s, i))} vs #{inspect(Enum.at(r, i))}"
  end

  defp place(file, bin, structured, raw) do
    {placed, _} =
      structured
      |> Enum.zip(raw)
      |> Enum.map_reduce({0, 1}, fn {o, r}, {pos, line} ->
        line = line + count_newlines(binary_part(bin, pos, r.offset - pos))
        {%{o | art: file, offset: r.offset, raw: r.raw, line: line}, {r.offset, line}}
      end)

    placed
  end

  defp count_newlines(bin), do: bin |> :binary.matches("\n") |> length()

  # `st.ancestors` holds each enclosing map with the depth of `segs` at which
  # it stands; a leaf's path relative to one is read off `segs` only when the
  # leaf holds a citation. `st.identity` holds the paths of the leaves that
  # `InputFigures.record_ids/1` reads as an enclosing record's identity.
  defp walk(%Jason.OrderedObject{values: kvs}, plain, segs, st) do
    st = %{
      st
      | ancestors: [{plain, length(segs)} | st.ancestors],
        et_at: et_at_of(plain, st.et_at)
    }

    Enum.flat_map(kvs, fn {k, v} ->
      here = segs ++ [{:key, k}]
      leaf(k, here, :key, %{st | ancestors: []}) ++ walk(v, Map.get(plain, k), here, st)
    end)
  end

  defp walk(list, plain, segs, st) when is_list(list) do
    [list, plain, InputFigures.record_ids(plain)]
    |> Enum.zip()
    |> Enum.flat_map(fn {v, pv, id} ->
      here = segs ++ [id]

      identity =
        for p <- InputFigures.identity_paths(pv),
            into: st.identity,
            do: here ++ Enum.map(p, &{:key, &1})

      walk(v, pv, here, %{st | identity: identity})
    end)
  end

  defp walk(s, _plain, segs, st) when is_binary(s), do: leaf(s, segs, :value, st)
  defp walk(_, _, _, _), do: []

  defp et_at_of(%{"et_test" => %{"at" => at, "file" => f}}, _)
       when is_binary(at) and is_binary(f),
       do: {at, f}

  defp et_at_of(_plain, et_at), do: et_at

  defp leaf(s, segs, kind, st) do
    case tokens(s) do
      [] ->
        []

      toks ->
        at_path = if kind == :key, do: render(segs) <> "{key}", else: render(segs)

        for t <- toks do
          Map.merge(t, %{
            art: nil,
            at_path: at_path,
            nth: 0,
            line: 0,
            leaf: s,
            leaf_pos: t.offset,
            segs: segs,
            parent: parent(kind, st.ancestors, segs),
            anchored: anchored?(st.ancestors, segs, t.cite),
            in_identity: kind == :value and MapSet.member?(st.identity, segs),
            et_at: st.et_at
          })
        end
    end
  end

  # The map that holds a value leaf directly, or nil (a list element, a key).
  defp parent(:value, [{map, depth} | _], segs) when length(segs) == depth + 1, do: map
  defp parent(_kind, _ancestors, _segs), do: nil

  # A prose anchor (G32, MES-161) on a map names a field of that map by its
  # dotted path, and the citation that field writes.
  defp anchored?(ancestors, segs, cite) do
    Enum.any?(ancestors, fn
      {%{"prose_anchors" => pa}, depth} when is_list(pa) ->
        rel = Enum.drop(segs, depth)
        Enum.all?(rel, &match?({:key, _}, &1)) and names?(pa, dotted(rel), cite)

      _ ->
        false
    end)
  end

  defp names?(anchors, field, cite),
    do: Enum.any?(anchors, &(is_map(&1) and &1["cite"] == cite and &1["field"] == field))

  defp dotted(rel), do: Enum.map_join(rel, ".", fn {:key, k} -> k end)

  defp render(segs) do
    segs
    |> Enum.map_join("", fn
      {:rec, id} -> "[" <> id <> "]"
      {:key, k} -> "." <> k
    end)
    |> String.trim_leading(".")
  end

  defp number_within_leaf(occs) do
    {numbered, _} =
      Enum.map_reduce(occs, %{}, fn o, seen ->
        k = {o.at_path, o.cite}
        n = Map.get(seen, k, 0) + 1
        {%{o | nth: n}, Map.put(seen, k, n)}
      end)

    numbered
  end

  defp md_occurrences(file, bin, seam) do
    headings = headings(bin)

    lines = bin |> String.split("\n") |> List.to_tuple()

    {starts, _} =
      lines |> Tuple.to_list() |> Enum.map_reduce(0, fn l, at -> {at, at + byte_size(l) + 1} end)

    starts = List.to_tuple(starts)

    occs =
      bin
      |> line_tokens()
      |> place_md(bin)
      |> Enum.map(fn t ->
        line_text = elem(lines, t.line - 1)

        Map.merge(t, %{
          art: file,
          at_path: elem(headings, t.line - 1),
          nth: 0,
          leaf: line_text,
          leaf_pos: t.offset - elem(starts, t.line - 1),
          segs: [],
          parent: nil,
          anchored: false,
          in_identity: false,
          et_at: nil
        })
      end)
      |> number_within_leaf()

    raw = Enum.map(occs, & &1.cite)
    structured = seam.(file, occs)

    if Enum.map(structured, & &1.cite) == raw,
      do: {:ok, structured},
      else: {:error, {:structured_parity, parity_detail(structured, Enum.map(raw, &%{cite: &1}))}}
  end

  defp place_md(toks, bin) do
    {placed, _} =
      Enum.map_reduce(toks, {0, 1}, fn t, {pos, line} ->
        line = line + count_newlines(binary_part(bin, pos, t.offset - pos))
        {Map.put(t, :line, line), {t.offset, line}}
      end)

    placed
  end

  # The heading each line stands under, outside code fences; a repeated heading
  # takes an ordinal so two sections never share an address.
  defp headings(bin) do
    {labels, _} =
      bin
      |> String.split("\n")
      |> Enum.map_reduce({"(preamble)", false, %{}}, &heading_step/2)

    List.to_tuple(labels)
  end

  defp heading_step(line, {current, fenced, seen}) do
    cond do
      Regex.match?(~r/\A {0,3}(```|~~~)/, line) ->
        {current, {current, not fenced, seen}}

      not fenced and Regex.match?(~r/\A {0,3}\#{1,6}\s/, line) ->
        heading = String.trim(line)
        n = Map.get(seen, heading, 0) + 1
        label = if n == 1, do: heading, else: "#{heading} ##{n}"
        {label, {label, fenced, Map.put(seen, heading, n)}}

      true ->
        {current, {current, fenced, seen}}
    end
  end

  # --- loading ------------------------------------------------------------------

  @doc """
  Reads everything the audit needs from `root` (default: the working
  directory). Options: `:root`, `:ledger` (a path relative to root).
  """
  def load(opts \\ []) do
    root = Keyword.get(opts, :root, ".")
    files = git_ls(root, @roots)

    %{
      files: files,
      sources: git_ls(root, ["*.ex", "*.exs"]),
      docs: Map.new(files, &{&1, File.read(Path.join(root, &1))}),
      ledger: File.read(Path.join(root, Keyword.get(opts, :ledger, @ledger_path))),
      read: read_fun(root),
      ancestor?: ancestor_fun(root)
    }
  end

  defp git_ls(root, specs) do
    case System.cmd("git", ["-C", root, "ls-files", "--" | specs]) do
      {out, 0} -> String.split(out, "\n", trim: true)
      _ -> []
    end
  end

  @doc false
  def read_fun(root) do
    fn
      {:tip, path} ->
        File.read(Path.join(root, path))

      {:at, sha, path} ->
        case System.cmd("git", ["-C", root, "show", "#{sha}:#{path}"], stderr_to_stdout: true) do
          {out, 0} -> {:ok, out}
          {out, _} -> {:error, String.trim(out)}
        end
    end
  end

  @doc false
  def ancestor_fun(root) do
    fn sha ->
      Regex.match?(~r/\A[0-9a-f]{40}\z/, sha) and
        match?(
          {_, 0},
          System.cmd("git", ["-C", root, "merge-base", "--is-ancestor", sha, "HEAD"],
            stderr_to_stdout: true
          )
        )
    end
  end

  # --- the ledger ---------------------------------------------------------------

  @doc """
  Decodes ledger bytes into `{windows, rows}`, rows keyed by occurrence. The
  document's shape is checked before anything reads it: exactly the four
  top-level keys, the guard's own label, and each occurrence entry an object
  of `art`, `at_path` (non-empty strings) and `cites` (a list of objects). Anything
  else is `{:error, why}`, never a skipped entry (MES-192 correction round 3).
  """
  def decode_ledger(bin) do
    with {:ok, doc} <- Jason.decode(bin),
         :ok <- ledger_shape(doc) do
      rows =
        for %{"art" => art, "at_path" => p, "cites" => cs} <- doc["occurrences"], c <- cs do
          Map.merge(c, %{"art" => art, "at_path" => p})
        end

      {:ok,
       %{windows: doc["windows"], rows: rows, header: Map.drop(doc, ["occurrences", "windows"])}}
    else
      {:error, %Jason.DecodeError{} = e} -> {:error, Exception.message(e)}
      {:error, why} -> {:error, why}
    end
  end

  defp ledger_shape(%{"windows" => w, "occurrences" => occ} = doc)
       when is_map(w) and is_list(occ) do
    cond do
      Enum.sort(Map.keys(doc)) != ~w(guard occurrences what_this_is windows) ->
        {:error,
         "top-level keys #{shown(Map.keys(doc))}, not guard/what_this_is/windows/occurrences"}

      doc["guard"] != @guard or not is_binary(doc["what_this_is"]) ->
        {:error, "guard must be #{shown(@guard)} and what_this_is a string"}

      bad = Enum.find(occ, &(not occurrence_entry?(&1))) ->
        {:error,
         "an occurrence entry is not {art, at_path (non-empty strings), cites[objects]}: #{shown(bad)}"}

      true ->
        :ok
    end
  end

  defp ledger_shape(_doc), do: {:error, "no windows object and occurrences list"}

  defp occurrence_entry?(%{"art" => a, "at_path" => p, "cites" => cs} = e)
       when is_binary(a) and a != "" and is_binary(p) and p != "" and is_list(cs),
       do: map_size(e) == 3 and Enum.all?(cs, &is_map/1)

  defp occurrence_entry?(_), do: false

  @doc """
  The canonical bytes of a ledger: a fixed header, the windows table sorted one
  per line, then one line per leaf sorted by `{art, at_path}`, its cites sorted
  by `{cite, nth}` with their fields in a fixed order.
  """
  def encode_ledger(%{windows: windows, rows: rows} = l) do
    header = Map.get(l, :header, %{})

    windows_lines =
      windows
      |> Enum.sort()
      |> Enum.map_join(",\n", fn {k, v} -> "    #{Jason.encode!(k)}: #{Jason.encode!(v)}" end)

    leaf_lines =
      rows
      |> Enum.group_by(&{&1["art"], &1["at_path"]})
      |> Enum.sort()
      |> Enum.map_join(",\n", fn {{art, p}, cs} ->
        cites =
          cs
          |> Enum.sort_by(&{&1["cite"], &1["nth"]})
          |> Enum.map_join(",", &encode_row/1)

        ~s(    {"art":#{Jason.encode!(art)},"at_path":#{Jason.encode!(p)},"cites":[#{cites}]})
      end)

    """
    {
      "guard": #{Jason.encode!(Map.get(header, "guard", @guard))},
      "what_this_is": #{Jason.encode!(Map.get(header, "what_this_is", what_this_is()))},
      "windows": {
    #{windows_lines}
      },
      "occurrences": [
    #{leaf_lines}
      ]
    }
    """
  end

  defp encode_row(row) do
    fields =
      for f <- @row_fields,
          Map.has_key?(row, f),
          do: "#{Jason.encode!(f)}:#{Jason.encode!(row[f])}"

    "{" <> Enum.join(fields, ",") <> "}"
  end

  defp what_this_is,
    do:
      "Guard 33's ledger (MES-192): one row per string-form file:N citation in conformance/data and docs/conformance, keyed {art, at_path, cite, nth}. windows maps <target>:<a>-<b>[@<at>] to the sha256 of that window, whitespace-squashed. Written by mix conformance.string_citations --repin / --resolve; a state other than pin is a reviewed hand edit."

  @doc "The windows-table key a pin or at row is checked against."
  def window_key(%{"target" => t, "state" => "at", "at" => at}, a, b), do: "#{t}:#{a}-#{b}@#{at}"
  def window_key(%{"target" => t}, a, b), do: "#{t}:#{a}-#{b}"

  @doc "The sha256 (lowercase hex) of lines `a..b` of `src`, squashed; `:error` past the end."
  def window_sha(src, a, b) do
    lines = String.split(src, "\n")

    if a >= 1 and b <= length(lines),
      do: {:ok, sha(window_text(lines, a, b))},
      else: :error
  end

  defp window_text(lines, a, b),
    do: lines |> Enum.slice((a - 1)..(b - 1)//1) |> Enum.join("\n") |> Adjudications.squash()

  defp sha(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

  @doc "The tracked sources a token resolves to: the exact path, a unique path suffix, or the basename."
  def candidates(token, sources) do
    if String.contains?(token, "/") do
      case Enum.filter(sources, &(&1 == token)) do
        [] -> Enum.filter(sources, &String.ends_with?(&1, "/" <> token))
        exact -> exact
      end
    else
      Enum.filter(sources, &(Path.basename(&1) == token))
    end
  end

  # --- the audit ----------------------------------------------------------------

  @limbs [
    :ledger,
    :universe,
    :parity,
    :shape,
    :rows,
    :resolution,
    :window,
    :anchors,
    :states,
    :ceilings
  ]

  @doc """
  Audits `inputs` (from `load/1`). Returns `%{defects: [...], report: %{...}}`;
  each defect is `%{kind, art, key, detail}` and `format_defect/1` renders it.
  """
  def audit(inputs), do: inputs |> context() |> audit_context()

  @doc false
  # Controls only (C9): the audit with a reader seam. No production caller.
  def control_audit(inputs, seam), do: inputs |> context(seam) |> audit_context()

  @doc "The audit of a context already built by `context/1`, so a caller that needs both reads the tree once."
  def audit_context(ctx) do
    defects = Enum.flat_map(@limbs, &limb(&1, ctx))
    %{defects: defects, report: report(ctx)}
  end

  @doc false
  def context(inputs), do: context(inputs, &unseamed/2)

  defp context(inputs, seam) do
    {ledger, ledger_defects} = read_ledger(inputs.ledger)
    # The schema is the only reader of a row or a window until it has passed
    # it. Everything below takes `rows` and `windows`, never the ledger's own;
    # a refused row reaches only the rows limb, which describes it through
    # shown/1 (MES-192 correction round 5, U1).
    {rows, refused} = schema_split(ledger.rows)
    windows = Map.filter(ledger.windows, fn {k, v} -> window_problem(k, v) == nil end)
    src_cache = source_cache(inputs, rows)
    per_file = Map.new(inputs.files, &{&1, file_occurrences(&1, Map.get(inputs.docs, &1), seam)})

    occs = for {_f, {:ok, os}} <- Enum.sort(per_file), o <- os, do: o
    by_key = Map.new(occs, &{okey(&1), &1})
    rows_by_key = Enum.group_by(rows, &rkey/1)
    matched = for o <- occs, [r] <- [Map.get(rows_by_key, okey(o))], do: {o, r}

    cands =
      occs
      |> Enum.map(& &1.token)
      |> Enum.uniq()
      |> Map.new(&{&1, candidates(&1, inputs.sources)})

    %{
      inputs: inputs,
      ledger: ledger,
      ledger_defects: ledger_defects,
      rows: rows,
      refused: refused,
      windows: windows,
      per_file: per_file,
      occs: occs,
      by_key: by_key,
      rows_by_key: rows_by_key,
      sources: inputs.sources,
      cands: cands,
      matched: matched,
      src_cache: src_cache,
      shas: window_shas(matched, src_cache),
      ancestry: ancestry(rows, inputs)
    }
    |> with_resolutions()
  end

  # The rows the schema passes, and `{row, why}` for each it refuses.
  defp schema_split(rows) do
    checked = Enum.map(rows, &{&1, row_problem(&1)})
    {for({r, nil} <- checked, do: r), for({r, why} <- checked, why != nil, do: {r, why})}
  end

  # Each matched row's resolution defects, computed once and read by the
  # resolution limb, the window limb and --resolve.
  defp with_resolutions(ctx) do
    resolutions = for {o, r} <- ctx.matched, do: {o, r, resolution_defects(o, r, ctx)}

    resolved = Map.new(resolutions, fn {o, _r, ds} -> {okey(o), ds == []} end)
    Map.merge(ctx, %{resolutions: resolutions, resolved: resolved})
  end

  # Whether each at row's commit is an ancestor of HEAD. Only rows the schema
  # passes reach it (a 40-hex at), so the predicate is never handed a null or
  # a number (MES-192 correction rounds 4 and 5, T1 and U1).
  defp ancestry(rows, inputs) do
    for %{"state" => "at", "at" => at} <- rows,
        uniq: true,
        into: %{},
        do: {at, inputs.ancestor?.(at)}
  end

  # Every window a pin or at row reads, hashed once: `{source key, a, b}` to
  # `{:ok, sha} | :error`. Each source is split into lines once.
  defp window_shas(matched, src_cache) do
    lines =
      Map.new(src_cache, fn
        {k, {:ok, src}} -> {k, src |> String.split("\n") |> List.to_tuple()}
        {k, _} -> {k, nil}
      end)

    for {o, %{"state" => st} = r} <- matched,
        st in ["pin", "at"],
        sk = source_key(r),
        uniq: true,
        into: %{},
        do: {{sk, o.a, o.b}, lines_sha(lines[sk], o.a, o.b)}
  end

  defp source_key(%{"state" => "at", "at" => at, "target" => t}), do: {:at, at, t}
  defp source_key(%{"target" => t}), do: {:tip, t}

  defp lines_sha(nil, _a, _b), do: :error

  defp lines_sha(lines, a, b) when a >= 1 and b <= tuple_size(lines) do
    text = (a - 1)..(b - 1)//1 |> Enum.map_join("\n", &elem(lines, &1)) |> Adjudications.squash()
    {:ok, sha(text)}
  end

  defp lines_sha(_lines, _a, _b), do: :error

  @empty_ledger %{windows: %{}, rows: [], bytes: nil}

  defp read_ledger({:ok, bin}) do
    case decode_ledger(bin) do
      {:ok, l} -> {Map.put(l, :bytes, bin), []}
      {:error, why} -> {@empty_ledger, [d(:ledger_unreadable, nil, nil, why)]}
    end
  end

  defp read_ledger({:error, why}),
    do: {@empty_ledger, [d(:ledger_unreadable, nil, nil, "cannot be read: #{shown(why)}")]}

  defp file_occurrences(f, {:ok, bin}, seam), do: occurrences(f, bin, seam)
  defp file_occurrences(_f, {:error, why}, _seam), do: {:error, {:unreadable, inspect(why)}}
  defp file_occurrences(_f, nil, _seam), do: {:error, {:unreadable, "not read"}}

  defp okey(o), do: {o.art, o.at_path, o.cite, o.nth}
  defp rkey(r), do: {r["art"], r["at_path"], r["cite"], r["nth"]}

  defp source_cache(inputs, rows) do
    keys =
      rows
      |> Enum.flat_map(fn
        %{"state" => "at", "at" => at, "target" => t} -> [{:at, at, t}]
        %{"target" => t} -> [{:tip, t}]
        _ -> []
      end)
      |> Enum.uniq()

    Map.new(keys, fn k -> {k, inputs.read.(k)} end)
  end

  # Each limb returns the defects of its own kinds. A limb is a clause of
  # `limb/2`, so a control can neutralise exactly one of them.
  defp limb(:ledger, ctx) do
    # The re-encode reads every value, so it runs only on a ledger whose every
    # row and window the schema passed; any other is refused already.
    passed = ctx.refused == [] and map_size(ctx.windows) == map_size(ctx.ledger.windows)

    canonical =
      case ctx.ledger.bytes do
        bin when is_binary(bin) and ctx.ledger_defects == [] and passed ->
          if encode_ledger(ctx.ledger) == bin,
            do: [],
            else: [
              d(:ledger_not_canonical, nil, nil, "the ledger is not in its canonical encoding")
            ]

        _ ->
          []
      end

    ctx.ledger_defects ++ canonical
  end

  defp limb(:universe, ctx) do
    unledgered =
      for o <- ctx.occs,
          o.shape == :ok,
          not Map.has_key?(ctx.rows_by_key, okey(o)),
          do: d(:unledgered, o, "a citation in the artefact with no ledger row")

    orphans =
      for {k, rs} <- ctx.rows_by_key,
          not Map.has_key?(ctx.by_key, k),
          r <- Enum.take(rs, 1),
          do: d(:ledger_orphan, r, "a ledger row with no citation in its artefact")

    referenced =
      for {o, r} <- ctx.matched, r["state"] in ["pin", "at"], into: MapSet.new() do
        window_key(r, o.a, o.b)
      end

    windows =
      for {k, _} <- ctx.windows,
          not MapSet.member?(referenced, k),
          do: d(:ledger_orphan, nil, k, "a window no pin or at row references")

    reach =
      if ctx.inputs.files == [] or ctx.occs == [],
        do: [
          d(
            :reach,
            nil,
            nil,
            "visited #{length(ctx.inputs.files)} file(s), #{length(ctx.occs)} citation(s)"
          )
        ],
        else: []

    unledgered ++ Enum.sort_by(orphans, & &1.key) ++ windows ++ reach
  end

  defp limb(:parity, ctx) do
    for {f, {:error, {kind, why}}} <- Enum.sort(ctx.per_file), do: d(kind, f, nil, why)
  end

  defp limb(:shape, ctx) do
    for o <- ctx.occs, o.shape != :ok, do: d(o.shape, o, "#{inspect(o.raw)} is not an address")
  end

  defp limb(:rows, ctx) do
    dupes =
      for {_k, [r, _ | _]} <- ctx.rows_by_key,
          do: d(:bad_row, r, "two ledger rows share this occurrence key")

    malformed = for {r, why} <- ctx.refused, do: d(:bad_row, r, why)

    bad_windows =
      for {k, v} <- Enum.sort(ctx.ledger.windows),
          why <- [window_problem(k, v)],
          why != nil,
          do: d(:bad_window, nil, k, why)

    windows =
      for {o, r} <- ctx.matched,
          r["state"] in ["pin", "at"],
          not Map.has_key?(ctx.windows, window_key(r, o.a, o.b)),
          do: d(:bad_row, r, "no window #{window_key(r, o.a, o.b)} in the windows table")

    dupes ++ malformed ++ bad_windows ++ windows
  end

  defp limb(:resolution, ctx) do
    for {_o, _r, defects} <- ctx.resolutions, defect <- defects, do: defect
  end

  defp limb(:window, ctx) do
    for {o, %{"state" => "pin"} = r} <- ctx.matched,
        resolves?(o, r, ctx),
        key = window_key(r, o.a, o.b),
        pinned = ctx.windows[key],
        pinned != nil,
        defect <- window_defect(o, r, pinned, ctx),
        do: defect
  end

  defp limb(:anchors, ctx) do
    for {o, %{"state" => "at"} = r} <- ctx.matched,
        pinned = ctx.windows[window_key(r, o.a, o.b)],
        pinned != nil,
        defect <- at_defect(o, r, pinned, ctx),
        do: defect
  end

  defp limb(:states, ctx) do
    holders = holders(ctx)

    held =
      for {o, r} <- ctx.matched,
          why <- [state_problem(o, r, ctx, holders)],
          why != nil,
          do: d(:state_unwarranted, r, why)

    g29_over =
      for {{section, cite}, n} <- g29_used(ctx, holders.g29),
          n > Map.get(holders.g29.permitted, {section, cite}, 0),
          do:
            d(
              :state_unwarranted,
              Citations.document(),
              "#{section} #{cite}",
              "#{n} held:g29 row(s), G29 permits #{Map.get(holders.g29.permitted, {section, cite}, 0)}"
            )

    held ++ g29_over
  end

  defp limb(:ceilings, ctx) do
    counts =
      ctx.matched
      |> Enum.flat_map(fn {o, r} -> ceiling_kinds(o, r) end)
      |> Enum.frequencies()

    for {key, n} <- Enum.sort(counts),
        n > Map.get(@ceilings, key, 0),
        do:
          d(
            :stale_over_ceiling,
            nil,
            "#{elem(key, 0)} #{elem(key, 1)}",
            "#{n} row(s), ceiling #{Map.get(@ceilings, key, 0)}"
          )
  end

  defp ceiling_kinds(o, r) do
    stale = if r["state"] == "stale", do: [{"stale", r["owner"]}], else: []
    order = if r["target_by"] == "order", do: [{"order", "MES-196"}], else: []

    doubled =
      if not String.contains?(o.token, "/") and o.token in @doubled_allowed,
        do: [{"doubled", o.token}],
        else: []

    unchecked =
      case r["state"] do
        "external" -> [{"external", "-"}]
        "not_a_cite" -> [{"not_a_cite", r["class"]}]
        _ -> []
      end

    stale ++ order ++ doubled ++ unchecked
  end

  # --- row and state rules ------------------------------------------------------

  @doc false
  def row_problem(r), do: row_check(r)

  # Each state's fields: {required, optional}. Every field of a row is checked
  # for type and value before any limb reads it; a field a state does not take
  # is refused, as is a missing, null or ill-typed one (S1).
  @state_fields %{
    "pin" => {~w(target), ~w(target_by)},
    "at" => {~w(class at target), []},
    "held" => {~w(class), []},
    "snapshot" => {~w(class), []},
    "stale" => {~w(owner reason), []},
    "external" => {[], []},
    "not_a_cite" => {~w(class target), []}
  }
  @base_fields ~w(art at_path cite nth state)

  defp row_check(r) do
    cond do
      not (is_binary(r["art"]) and is_binary(r["at_path"]) and is_binary(r["cite"]) and
               r["cite"] != "") ->
        "art, at_path and cite are non-empty strings"

      not (is_integer(r["nth"]) and r["nth"] >= 1) ->
        "nth is a positive integer"

      not Map.has_key?(@state_fields, r["state"]) ->
        "state #{shown(r["state"])} is not one of #{inspect(@states)}"

      true ->
        state_fields_check(r)
    end
  end

  defp state_fields_check(r) do
    {required, optional} = @state_fields[r["state"]]
    present = Map.keys(r) -- @base_fields

    case {required -- present, present -- (required ++ optional)} do
      {[], []} -> Enum.find_value(present, &field_problem(&1, r))
      {[], extra} -> "field(s) #{shown(extra)} do not belong on a #{shown(r["state"])} row"
      {missing, _} -> "a #{shown(r["state"])} row needs #{shown(missing)}"
    end
  end

  defp field_problem("target", r),
    do: if(is_binary(r["target"]) and r["target"] != "", do: nil, else: "target is a path")

  defp field_problem("target_by", r),
    do:
      if(r["target_by"] in ["evidence", "order"], do: nil, else: "target_by is evidence or order")

  defp field_problem("at", r),
    do: if(full_sha?(r["at"]), do: nil, else: "at is a full lowercase 40-hex commit")

  defp field_problem("class", r),
    do:
      if(r["class"] in Map.get(@classes, r["state"], []),
        do: nil,
        else: "class #{shown(r["class"])} is not a #{shown(r["state"])} class"
      )

  defp field_problem("owner", r),
    do:
      if(is_binary(r["owner"]) and r["owner"] =~ ~r/\AMES-\d+\z/,
        do: nil,
        else: "a stale row names its owning ticket (MES-n)"
      )

  defp field_problem("reason", r),
    do: if(is_binary(r["reason"]) and r["reason"] != "", do: nil, else: "a stale row says why")

  defp full_sha?(v), do: is_binary(v) and v =~ ~r/\A[0-9a-f]{40}\z/

  @doc false
  # A window value is the lowercase hex sha256 of a squashed window; its key
  # names `<target>:<a>-<b>`, with `@<40-hex commit>` for an at row.
  def window_problem(k, v) do
    cond do
      not (is_binary(k) and k =~ ~r/\A.+:\d+-\d+(?:@[0-9a-f]{40})?\z/) ->
        "window key #{shown(k)} is not <target>:<a>-<b>[@<commit>]"

      not (is_binary(v) and v =~ ~r/\A[0-9a-f]{64}\z/) ->
        "window #{shown(k)} is #{shown(v)}, not a lowercase 64-hex sha256"

      true ->
        nil
    end
  end

  # The resolution limb's verdict for a row, computed once per context.
  defp resolves?(o, r, ctx) do
    case ctx do
      %{resolved: resolved} ->
        Map.get_lazy(resolved, okey(o), fn -> resolution_defects(o, r, ctx) == [] end)

      _ ->
        resolution_defects(o, r, ctx) == []
    end
  end

  defp resolution_defects(o, %{"state" => "external"} = r, ctx) do
    case token_candidates(o, ctx) do
      [] ->
        []

      cands ->
        [d(:state_unwarranted, r, "external, but #{o.token} resolves to #{inspect(cands)}")]
    end
  end

  defp resolution_defects(o, %{"state" => s} = r, ctx) when s in ["pin", "at", "not_a_cite"],
    do: target_defects(o, r, token_candidates(o, ctx))

  defp resolution_defects(_o, _r, _ctx), do: []

  defp token_candidates(o, ctx),
    do: Map.get_lazy(ctx.cands, o.token, fn -> candidates(o.token, ctx.sources) end)

  defp target_defects(o, r, cands) do
    cond do
      cands == [] ->
        [d(:unresolved, r, "#{o.token} names no tracked .ex/.exs")]

      length(cands) > 1 and not (o.token in @doubled_allowed and Map.has_key?(r, "target_by")) ->
        [d(:doubled_basename, r, "#{o.token} names #{inspect(cands)}")]

      r["target"] not in cands ->
        [d(:target_mismatch, r, "target #{r["target"]} is not among #{inspect(cands)}")]

      true ->
        evidence_defects(o, r, associated_targets(o, cands))
    end
  end

  # MES-192 correction round 2, R2: a full path is evidence for THIS citation
  # only when the association grammar binds it to this occurrence. One bound
  # file must be the pinned one; two bound files are ambiguous and refused.
  defp evidence_defects(_o, r, [named]) do
    if named == r["target"],
      do: [],
      else: [
        d(
          :target_contradicted,
          r,
          "the leaf binds #{named} to this cite, the row pins #{r["target"]}"
        )
      ]
  end

  defp evidence_defects(_o, r, [_, _ | _] = both),
    do: [d(:target_ambiguous, r, "the leaf binds #{Enum.join(both, " and ")} to this cite")]

  defp evidence_defects(_o, _r, _none), do: []

  @doc """
  The candidate files whose full path the citing leaf binds to this occurrence
  of a shared basename, sorted. A path written as its own citation
  (`lib/y/client.ex:2`) is that citation's, never evidence for another. A path
  is bound when, in the leaf:

    * ASSERTION: the cite, then optionally more cites joined by `,` `and` `or`,
      then `is` or `are`, then the path (or a list of paths joined by `,`
      `and` `or`): "`client.ex:379` is `lib/…/client.ex`";
    * TABLE ROW: the leaf is a Markdown table row (`| … |`) and holds no other
      line citation;
    * SENTENCE: the same sentence (bounded by `.` `;` `!` `?` before
      whitespace, a newline, or a table cell `|`), with no other line citation
      between the two. A line citation here is the reader's own shape with any
      extension (`schema.JSON:5`, `x.json5:5`), or a bare `:N`.

  A path is a complete token: `lib/y/client.ex.bak` is not `lib/y/client.ex`.
  Named residuals: punctuation inside a code span counts as a sentence end;
  a sentence spanning two Markdown lines does not bind.

  Any other mention is not evidence and never refuses.
  """
  def associated_targets(o, [_, _ | _] = cands), do: associated(o, cands)
  def associated_targets(_o, _cands), do: []

  # Any line citation, of any file (the reader's own shape, every extension),
  # or a bare `:N`: what may not stand between a cite and a path.
  @separator ~r/#{@any_cite_src}|(?<![\w.:\/-]):\d+/u
  @sentence_end ~r/[.;!?](?=\s|\z)|\n|\|/u

  defp associated(o, cands) do
    text = o.leaf
    at = o.leaf_pos
    stop = at + byte_size(o.cite)
    seps = other_cites(text, at)

    cands
    |> Enum.filter(fn c ->
      text
      |> mentions(c)
      |> Enum.any?(fn m ->
        assertion?(text, stop, m) or table_row?(text, seps) or
          same_sentence?(text, seps, at, stop, m)
      end)
    end)
    |> Enum.sort()
  end

  defp other_cites(text, at) do
    for [{s, l} | _] <- Regex.scan(@separator, text, return: :index), s != at, do: {s, s + l}
  end

  # A COMPLETE path token: not followed by a path character, a dot and more
  # name (`client.ex.bak`), or a line number (then it is its own citation).
  defp mentions(text, path) do
    if String.contains?(text, path), do: path_mentions(text, path), else: []
  end

  defp path_mentions(text, path) do
    ~r/(?<![\w.\/-])#{Regex.escape(path)}(?![\w\/-]|\.\w|:\d)/u
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{s, l}] -> {s, s + l} end)
  end

  defp assertion?(text, stop, {ms, _me}) when ms >= stop do
    between = binary_part(text, stop, ms - stop)

    Regex.match?(
      ~r/\A[`*]*(?:\s*(?:,|\band\b|\bor\b)\s*[`*]*#{@any_cite_src}[`*]*)*\s+(?:is|are)\s+(?:[`*]*[\w.\/-]+\.exs?[`*]*\s*(?:,|\band\b|\bor\b)\s*)*[`*]*\z/u,
      between
    )
  end

  defp assertion?(_text, _stop, _m), do: false

  defp table_row?(text, seps),
    do: String.starts_with?(String.trim_leading(text), "|") and seps == []

  defp same_sentence?(text, seps, at, stop, {ms, me}) do
    {from, to} = if ms >= stop, do: {stop, ms}, else: {me, at}
    span = binary_part(text, from, to - from)

    not Regex.match?(@sentence_end, span) and
      not Enum.any?(seps, fn {s, e} -> s >= from and e <= to end)
  end

  defp window_defect(o, r, pinned, ctx) do
    case ctx.shas[{{:tip, r["target"]}, o.a, o.b}] do
      {:ok, ^pinned} ->
        []

      {:ok, _} ->
        {:ok, src} = ctx.src_cache[{:tip, r["target"]}]

        [
          d(
            :window_drift,
            r,
            "#{r["target"]}:#{o.a}-#{o.b} no longer holds its pinned bytes; " <>
              where_now(src, o, pinned)
          )
        ]

      _ ->
        [d(:window_drift, r, "#{r["target"]} cannot be read, or has no line #{o.b}")]
    end
  end

  @doc false
  def where_now(src, o, pinned) do
    case starts_with_sha(src, o.b - o.a + 1, pinned) do
      [n] -> "the pinned bytes are now at line #{n} (moved)"
      [] -> "the pinned bytes occur nowhere in the file (changed)"
      ns -> "the pinned bytes occur at lines #{inspect(ns, charlists: :as_lists)} (ambiguous)"
    end
  end

  @doc false
  def starts_with_sha(src, len, want) do
    lines = src |> String.split("\n") |> Enum.map(&Adjudications.squash/1) |> List.to_tuple()
    last = tuple_size(lines) - len

    for i <- 0..last//1,
        text =
          0..(len - 1)//1 |> Enum.map_join(" ", &elem(lines, i + &1)) |> String.trim(),
        sha(Adjudications.squash(text)) == want,
        do: i + 1
  end

  defp at_defect(o, r, pinned, ctx) do
    key = {:at, r["at"], r["target"]}

    if Map.get(ctx.ancestry, r["at"], false),
      do: at_window_defect(o, r, pinned, ctx.src_cache[key], ctx.shas[{key, o.a, o.b}]),
      else: [d(:anchor_invalid, r, "#{r["at"]} is not a full sha of an ancestor of HEAD")]
  end

  defp at_window_defect(_o, _r, pinned, {:ok, _src}, {:ok, pinned}), do: []

  defp at_window_defect(o, r, _pinned, {:ok, _src}, _sha) do
    at = String.slice(r["at"], 0, 7)
    [d(:at_drift, r, "#{r["target"]}:#{o.a}-#{o.b} at #{at} does not hold the pinned bytes")]
  end

  defp at_window_defect(_o, r, _pinned, _src, _sha),
    do: [d(:anchor_invalid, r, "#{r["target"]} cannot be read at #{r["at"]}")]

  defp state_problem(o, %{"state" => "at", "class" => c} = r, _ctx, _att) do
    case c do
      "et_test_at" ->
        if o.et_at == {r["at"], r["target"]},
          do: nil,
          else: "et_test_at, but the row's et_test is #{inspect(o.et_at)}"

      "publication" ->
        if o.art in @publications, do: nil, else: "publication, but #{o.art} is not one"

      "dated_prose" ->
        if String.contains?(o.leaf, String.slice(r["at"], 0, 7)),
          do: nil,
          else: "dated_prose, but the leaf does not name #{String.slice(r["at"], 0, 7)}"
    end
  end

  defp state_problem(o, %{"state" => "held", "class" => c}, _ctx, holders) do
    if held_by?(c, o, holders),
      do: nil,
      else: "held:#{c}, but that holder does not read this occurrence"
  end

  defp state_problem(o, %{"state" => "snapshot", "class" => "sweep_measurement"}, _ctx, _att) do
    if sweep_list_element?(o),
      do: nil,
      else: "sweep_measurement, but this is not an element of a list the sweep generates"
  end

  defp state_problem(o, %{"state" => "not_a_cite"} = r, ctx, _att) do
    case ctx.src_cache[{:tip, r["target"]}] do
      {:ok, src} ->
        if window_sha(src, o.a, o.b) == :error,
          do: nil,
          else: "fixture, but #{r["target"]} has line #{o.b}: it is a live citation"

      _ ->
        "fixture, but #{r["target"]} cannot be read, so its range cannot be checked"
    end
  end

  defp state_problem(_o, _r, _ctx, _att), do: nil

  # S2: an element of a list BoundarySweep generates, in its table: a
  # measurement field of a record of `boundaries`, or a root exclusion list.
  # Not a scalar, not a lookalike key elsewhere, not another record field.
  defp sweep_list_element?(o) do
    sweep = MCP.Conformance.BoundarySweep
    record_lists = Enum.reject(sweep.measurement_fields(), &String.contains?(&1, "."))

    o.art == sweep.paths().boundaries and
      case o.segs do
        [{:key, "boundaries"}, {:rec, _}, {:key, f}, {:rec, _}] -> f in record_lists
        [{:key, f}, {:rec, _}] -> f in @sweep_root_lists
        _ -> false
      end
  end

  # --- the holders' read domains -----------------------------------------------
  #
  # A held row is admitted only where its holder's own reader reads that
  # artefact AND that occurrence (MES-192 correction round 1, F2). Each domain
  # is derived by calling the holder's code: G32's walk root and `collect/1`;
  # G29's document and `line_citations/1`; AttributionCitations' document and
  # audited sections.

  defp holders(ctx) do
    %{
      g32: g32_domain(ctx),
      g29: g29_domain(ctx),
      attribution: attribution_domain(ctx)
    }
  end

  defp held_by?("g32_bytes", o, h),
    do: g32_reads?(o, h) and List.last(o.segs) == {:key, "bytes"}

  defp held_by?("g32_anchor_entry", o, h),
    do: g32_reads?(o, h) and {:key, "prose_anchors"} in o.segs

  defp held_by?("g32_prose_anchor", o, h),
    do: MapSet.member?(h.g32.files, o.art) and o.anchored

  defp held_by?("g29", o, h),
    do: o.art == Citations.document() and MapSet.member?(h.g29.reads, {o.line, o.cite})

  defp held_by?("attribution_citations", o, h),
    do: MapSet.member?(h.attribution, {o.art, o.line, Path.basename(o.token), o.a})

  # G32 collects a citation map from a record it walks; the leaf must be in one.
  defp g32_reads?(o, h) do
    case Map.fetch(h.g32.collected, o.art) do
      {:ok, maps} -> o.parent != nil and MapSet.member?(maps, o.parent)
      :error -> false
    end
  end

  defp g32_domain(ctx) do
    {root, glob} = Adjudications.walk_root()

    glob =
      Regex.compile!("\\A" <> (glob |> Regex.escape() |> String.replace("\\*", "[^/]*")) <> "\\z")

    files = for f <- ctx.inputs.files, Path.dirname(f) == root, Path.basename(f) =~ glob, do: f

    held_in =
      for {o, %{"state" => "held", "class" => "g32_" <> _}} <- ctx.matched,
          into: MapSet.new(),
          do: o.art

    collected =
      for f <- files,
          MapSet.member?(held_in, f),
          {:ok, bin} <- [Map.get(ctx.inputs.docs, f)],
          {:ok, doc} <- [Jason.decode(bin)],
          into: %{},
          do: {f, MapSet.new(Adjudications.collect(doc))}

    %{files: MapSet.new(files), collected: collected}
  end

  defp g29_domain(ctx) do
    case Map.get(ctx.inputs.docs, Citations.document()) do
      {:ok, md} ->
        found = Citations.line_citations(md)

        %{
          reads: MapSet.new(found, &{&1.line, &1.text}),
          section: Map.new(found, &{{&1.line, &1.text}, &1.section}),
          permitted: Map.new(Citations.permitted_line_citations(), fn {k, {_c, n}} -> {k, n} end)
        }

      _ ->
        %{reads: MapSet.new(), section: %{}, permitted: %{}}
    end
  end

  defp g29_used(ctx, g29) do
    ctx.matched
    |> Enum.flat_map(fn
      {o, %{"state" => "held", "class" => "g29"}} ->
        case g29.section[{o.line, o.cite}] do
          nil -> []
          section -> [{section, o.cite}]
        end

      _ ->
        []
    end)
    |> Enum.frequencies()
  end

  # The `.exs` addresses AttributionCitations' reader takes from the sections it
  # audits (`populations/0`), in the document it audits.
  defp attribution_domain(ctx) do
    md_path = ETCCAttribution.paths().prose

    case Map.get(ctx.inputs.docs, md_path) do
      {:ok, md} ->
        audited = AttributionCitations.populations() |> Enum.map(& &1.section) |> MapSet.new()

        for t <- AttributionCitations.tokens(md),
            t.kind == :exs,
            MapSet.member?(audited, t.section),
            into: MapSet.new(),
            do: {md_path, t.md_line, Path.basename(t.file), t.line}

      _ ->
        MapSet.new()
    end
  end

  # --- the report ---------------------------------------------------------------

  defp report(ctx) do
    states = ctx.matched |> Enum.map(fn {_, r} -> r["state"] end) |> Enum.frequencies()

    classes =
      ctx.matched
      |> Enum.map(fn {_, r} ->
        "#{r["state"]}:#{r["class"] || r["owner"] || r["target_by"] || "-"}"
      end)
      |> Enum.frequencies()

    %{
      "files" => length(ctx.inputs.files),
      "files_with_citations" => ctx.occs |> Enum.map(& &1.art) |> Enum.uniq() |> length(),
      "occurrences" => length(ctx.occs),
      "rows" => length(ctx.ledger.rows),
      "windows" => map_size(ctx.ledger.windows),
      "states" => states,
      "classes" => classes,
      "byte_checked" => Map.get(states, "pin", 0) + Map.get(states, "at", 0)
    }
  end

  @doc "One line per defect: the guard, the kind, the artefact, the occurrence, and the fixing command."
  def format_defect(%{kind: k, art: art, key: key, detail: det}) do
    where = Enum.join(Enum.reject([art, key], &is_nil/1), " @ ")
    "#{@guard} #{k} — #{where}: #{det} [fix: #{fix(k)}]"
  end

  @doc "The fixing instruction a refusal of `kind` prints (empty if none: a defect)."
  def fix(kind), do: Map.get(@fix, kind, "")

  @doc "Every refusal kind the guard declares (each must have a fix: controls C23, C26)."
  def kinds, do: Enum.uniq(Map.keys(@fix) ++ runtime_kinds())

  @doc "The kinds built at runtime, from the one attribute shape/3 reads."
  def runtime_kinds, do: Map.values(@shape_kinds)

  defp d(kind, %{at_path: p, cite: c, nth: n, art: art}, detail),
    do: %{kind: kind, art: art, key: "#{p} `#{c}`##{n}", detail: detail}

  # A ledger row, possibly one the schema refused: every value through
  # shown/1, a missing one as nil, so describing it cannot raise (U1).
  defp d(kind, r, detail) when is_map(r) and not is_struct(r),
    do: %{
      kind: kind,
      art: shown(r["art"]),
      key: "#{shown(r["at_path"])} `#{shown(r["cite"])}`##{shown(r["nth"])}",
      detail: detail
    }

  defp d(kind, art, key, detail), do: %{kind: kind, art: art, key: key, detail: detail}

  # The one renderer of a ledger value in a refusal: a binary as it is,
  # anything else as inspect/2 shows it. Total, so no refusal raises (U1).
  defp shown(v) when is_binary(v), do: v
  defp shown(v), do: inspect(v, limit: 8, printable_limit: 120)

  # --- maintenance: --repin and --resolve ---------------------------------------

  @doc """
  The ledger re-derived from the tree: rows kept for every occurrence the
  ledger already has; a `pin` row added for each unledgered occurrence that
  resolves to one file and a real window; rows for vanished occurrences
  dropped; and each window named in `accept` (`"<target>:<a>-<b>"`) re-hashed
  at the tip. Never assigns a state other than `pin`.

  Returns `{ledger, %{added, dropped, accepted, refused}}`.
  """
  def repin(inputs, accept \\ []) do
    ctx = context(inputs)

    case schema_defects(ctx) do
      [] -> repin_context(ctx, inputs, accept)
      defects -> {:error, defects}
    end
  end

  # A malformed ledger is refused as input, never repaired by guessing (S1).
  defp schema_defects(ctx),
    do: ctx.ledger_defects ++ Enum.filter(limb(:rows, ctx), &(&1.kind in [:bad_row, :bad_window]))

  defp repin_context(ctx, inputs, accept) do
    tips = tip_sources(inputs, ctx.occs)

    {added, refused} =
      ctx.occs
      |> Enum.reject(&Map.has_key?(ctx.rows_by_key, okey(&1)))
      |> Enum.reduce({[], []}, fn o, {add, ref} ->
        case new_pin(o, ctx.sources, tips) do
          {:ok, row, key, sha} -> {[{row, key, sha} | add], ref}
          {:refuse, kind, why} -> {add, [d(kind, o, why) | ref]}
        end
      end)

    kept = for {k, [r | _]} <- ctx.rows_by_key, Map.has_key?(ctx.by_key, k), do: r
    dropped = length(ctx.ledger.rows) - length(kept)

    windows =
      Map.merge(ctx.windows, Map.new(added, fn {_, k, s} -> {k, s} end), fn _k, old, _new ->
        old
      end)

    {windows, accepted, refused} =
      Enum.reduce(accept, {windows, [], refused}, fn key, {w, acc, ref} ->
        with true <- Map.has_key?(w, key),
             [_, t, a, b] <- Regex.run(~r/\A(.+):(\d+)-(\d+)\z/, key),
             {:ok, src} <- tips[t] || inputs.read.({:tip, t}),
             {:ok, s} <- window_sha(src, String.to_integer(a), String.to_integer(b)) do
          {Map.put(w, key, s), [{key, w[key], s} | acc], ref}
        else
          _ ->
            {w, acc,
             [d(:unknown_accept, nil, key, "no tip window of that key in the ledger") | ref]}
        end
      end)

    rows = kept ++ Enum.map(added, &elem(&1, 0))
    ledger = prune(%{ctx.ledger | windows: windows, rows: rows}, ctx.by_key)

    {ledger,
     %{
       added: length(added),
       dropped: dropped,
       accepted: Enum.reverse(accepted),
       refused: Enum.reverse(refused)
     }}
  end

  defp tip_sources(inputs, occs) do
    occs
    |> Enum.flat_map(&candidates(&1.token, inputs.sources))
    |> Enum.uniq()
    |> Map.new(&{&1, inputs.read.({:tip, &1})})
  end

  defp new_pin(o, sources, tips) do
    with :ok <- o.shape,
         [t] <- candidates(o.token, sources),
         {:ok, src} <- tips[t],
         {:ok, s} <- window_sha(src, o.a, o.b),
         false <- trivial?(src, o.a, o.b) do
      row = %{
        "art" => o.art,
        "at_path" => o.at_path,
        "cite" => o.cite,
        "nth" => o.nth,
        "state" => "pin",
        "target" => t
      }

      {:ok, row, "#{t}:#{o.a}-#{o.b}", s}
    else
      shape when shape in [:bad_range, :bad_shape] ->
        {:refuse, shape, "#{inspect(o.raw)} is not an address"}

      [] ->
        {:refuse, :unresolved, "#{o.token} names no tracked .ex/.exs"}

      [_, _ | _] = c ->
        {:refuse, :doubled_basename, "#{o.token} names #{inspect(c)}: write the path form"}

      :error ->
        {:refuse, :out_of_range, "#{o.token} has no line #{o.b}"}

      true ->
        {:refuse, :trivial_window, "#{o.cite} cites only blank or closing lines"}

      _ ->
        {:refuse, :unresolved, "#{o.token} cannot be read"}
    end
  end

  defp trivial?(src, a, b) do
    lines = String.split(src, "\n")
    lines |> Enum.slice((a - 1)..(b - 1)//1) |> Enum.all?(&(Adjudications.squash(&1) in @trivial))
  end

  defp prune(ledger, by_key) do
    referenced =
      for r <- ledger.rows,
          r["state"] in ["pin", "at"],
          o = by_key[rkey(r)],
          o != nil,
          into: MapSet.new(),
          do: window_key(r, o.a, o.b)

    %{
      ledger
      | windows: Map.filter(ledger.windows, fn {k, _} -> MapSet.member?(referenced, k) end)
    }
  end

  @doc """
  The M1 re-resolver (MES-84 E2 / MES-167 M1). For each pinned window that no
  longer hashes to its pin, it requires: the pinned bytes ARE at that address
  in `base_read`'s tree (the pin and the base agree), they are unique there and
  non-trivial, and they occur exactly once in the target now. Every pin row of
  that window is then rewritten `N[-M]` to `N'[-M']`, keeping the range length,
  by raw byte substitution at its offset, so a derived copy and its source take
  the same substitution. The window's sha is unchanged by construction.

  `instrument` is `[{path, bytes}]` of the test/ and conformance/ sources: a
  citation written there literally is never rewritten.

  Returns `%{docs, ledger, moved, refused}`; `docs` holds only changed files.
  """
  def resolve(inputs, base_read, instrument \\ []) do
    ctx = context(inputs)

    case schema_defects(ctx) do
      [] -> resolve_context(ctx, inputs, base_read, instrument)
      defects -> {:error, defects}
    end
  end

  defp resolve_context(ctx, inputs, base_read, instrument) do
    red = red_pins(ctx)
    {moves, refused} = window_moves(red, base_read, ctx)

    {edits, row_refusals} =
      red
      |> Enum.map(fn {o, r, _} -> {o, r, moves[{r["target"], o.a, o.b}]} end)
      |> Enum.reject(fn {_o, _r, a2} -> a2 == nil end)
      |> Enum.map(&row_edit(&1, instrument))
      |> Enum.split_with(&match?({:edit, _}, &1))

    edits = Enum.map(edits, &elem(&1, 1))
    new_docs = apply_edits(inputs.docs, edits)

    %{
      docs: new_docs,
      ledger: rekey(ctx, inputs, new_docs, edits),
      moved: for({{t, a, b}, a2} <- Enum.sort(moves), do: {t, a, b, a2}),
      edited: length(edits),
      refused: refused ++ Enum.map(row_refusals, &elem(&1, 1))
    }
  end

  defp red_pins(ctx) do
    for {o, %{"state" => "pin"} = r} <- ctx.matched,
        resolves?(o, r, ctx),
        pinned = ctx.windows[window_key(r, o.a, o.b)],
        pinned != nil,
        window_defect(o, r, pinned, ctx) != [],
        do: {o, r, pinned}
  end

  # One M1 decision per window; a refusal names every row of the window.
  defp window_moves(red, base_read, ctx) do
    red
    |> Enum.group_by(fn {o, r, _} -> {r["target"], o.a, o.b} end)
    |> Enum.sort()
    |> Enum.reduce({%{}, []}, fn {{t, a, b} = w, [{_, _, pinned} | _] = rows}, {mv, ref} ->
      case m1(t, a, b, pinned, base_read, ctx) do
        {:ok, a2} -> {Map.put(mv, w, a2), ref}
        {:refuse, kind, why} -> {mv, ref ++ Enum.map(rows, fn {_o, r, _} -> d(kind, r, why) end)}
      end
    end)
  end

  # A citation that `InputFigures.record_ids/1` reads as an enclosing record's
  # identity: rewriting it would re-key every G31 path in that record.
  defp in_identity?(o), do: o.in_identity

  defp row_edit({o, r, a2}, instrument) do
    cond do
      where = literal_in?(o.cite, instrument) ->
        {:refuse, d(:literal_in_instrument, r, "#{o.cite} is written in #{where}")}

      in_identity?(o) ->
        {:refuse, d(:in_record_identity, r, "#{o.cite} is part of a record's identity")}

      true ->
        {:edit, {o, r, a2}}
    end
  end

  defp m1(t, a, b, pinned, base_read, ctx) do
    len = b - a + 1

    with {:tip, {:ok, tip}} <- {:tip, ctx.src_cache[{:tip, t}] || {:error, :absent}},
         {:base, {:ok, base}} <- {:base, base_read.(t)},
         {:agree, {:ok, ^pinned}} <- {:agree, window_sha(base, a, b)},
         {:trivial, false} <- {:trivial, trivial?(base, a, b)},
         {:unique, [^a]} <- {:unique, starts_with_sha(base, len, pinned)} do
      case starts_with_sha(tip, len, pinned) do
        [a2] ->
          {:ok, a2}

        [] ->
          {:refuse, :changed, "#{t}:#{a}-#{b}: the pinned bytes occur nowhere now"}

        ns ->
          {:refuse, :moved_ambiguous,
           "#{t}:#{a}-#{b}: the pinned bytes occur at #{inspect(ns, charlists: :as_lists)}"}
      end
    else
      {:tip, _} ->
        {:refuse, :target_gone, "#{t} cannot be read"}

      {:base, _} ->
        {:refuse, :base_disagrees, "#{t} is absent at the base"}

      {:agree, _} ->
        {:refuse, :base_disagrees, "#{t}:#{a}-#{b} at the base does not hold the pin"}

      {:trivial, _} ->
        {:refuse, :trivial_window, "#{t}:#{a}-#{b} is blank or closing lines"}

      {:unique, _} ->
        {:refuse, :not_unique_at_base, "#{t}:#{a}-#{b} recurs at the base"}
    end
  end

  defp literal_in?(cite, instrument) do
    re = Regex.compile!("(?<![\\w./-])" <> Regex.escape(cite) <> "(?!\\d)", "u")
    Enum.find_value(instrument, fn {path, bin} -> if Regex.match?(re, bin), do: path end)
  end

  defp apply_edits(docs, edits) do
    edits
    |> Enum.group_by(fn {o, _, _} -> o.art end)
    |> Map.new(fn {art, es} ->
      {:ok, bin} = docs[art]

      {art,
       es |> Enum.sort_by(fn {o, _, _} -> o.offset end, :desc) |> Enum.reduce(bin, &substitute/2)}
    end)
  end

  # Byte for byte at the occurrence's offset, after checking the bytes there
  # are the ones read: the rest of the file, escapes and layout included, is
  # untouched.
  defp substitute({o, _r, a2}, bin) do
    len = byte_size(o.raw)
    ^len = byte_size(binary_part(bin, o.offset, len))
    true = binary_part(bin, o.offset, len) == o.raw
    tail = if o.sep, do: o.sep <> Integer.to_string(a2 + o.b - o.a), else: ""
    new_raw = o.token <> ":" <> Integer.to_string(a2) <> tail

    binary_part(bin, 0, o.offset) <>
      new_raw <> binary_part(bin, o.offset + len, byte_size(bin) - o.offset - len)
  end

  # The edited files keep every citation, in order, so the k-th occurrence
  # before is the k-th after: rows travel with their occurrence.
  defp rekey(ctx, inputs, new_docs, edits) do
    moved_windows =
      for {o, r, a2} <- edits, into: %{} do
        {window_key(r, a2, a2 + o.b - o.a), ctx.windows[window_key(r, o.a, o.b)]}
      end

    rows = Enum.flat_map(inputs.files, &rekey_file(&1, ctx, new_docs[&1]))
    windows = Map.merge(ctx.windows, moved_windows)
    prune(%{ctx.ledger | rows: rows, windows: windows}, new_by_key(inputs, new_docs))
  end

  defp rekey_file(f, ctx, new_bin) do
    old = ctx.per_file |> Map.get(f, {:ok, []}) |> ok_list()
    rows = for o <- old, [r] <- [Map.get(ctx.rows_by_key, okey(o))], do: {o, r}
    rekey_rows(f, rows, old, new_bin)
  end

  defp rekey_rows(_f, rows, _old, nil), do: Enum.map(rows, &elem(&1, 1))

  defp rekey_rows(f, rows, old, bin) do
    {:ok, new} = occurrences(f, bin)
    pairs = old |> Enum.zip(new) |> Map.new(fn {o, n} -> {okey(o), n} end)

    for {o, r} <- rows,
        n = pairs[okey(o)],
        do: %{r | "at_path" => n.at_path, "cite" => n.cite, "nth" => n.nth}
  end

  defp ok_list({:ok, l}), do: l
  defp ok_list(_), do: []

  defp new_by_key(inputs, new_docs) do
    for f <- inputs.files,
        {:ok, bin} <- [if(new_docs[f], do: {:ok, new_docs[f]}, else: inputs.docs[f])],
        {:ok, os} <- [occurrences(f, bin)],
        o <- os,
        into: %{},
        do: {okey(o), o}
  end
end

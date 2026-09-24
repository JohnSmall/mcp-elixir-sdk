defmodule MCP.Conformance.AttributionCitations do
  @moduledoc """
  The per-item enumeration predicate for `docs/conformance/etcc-attribution.md`
  (B2b's prose), shared by `conformance/controls/etcc_attribution_controls.exs`
  and by `test/conformance/etcc_attribution_test.exs` so the gate and the control
  drive **one** implementation.

  ## What it is for

  Epic ruling 4: a count is backed by per-item enumeration. So every member of
  every counted population must be cited **at its own address** in the section
  that enumerates it. MES-113 found the check that asserted this was red on
  `main` for a month, and — separately — that it could not have caught most of
  what was wrong with the document even when it was green.

  ## Two structural holes MES-113 measured, and what replaced them

  **The cited set was WHOLE-FILE.** `members ⊆ cited(document)` masks a stale
  citation in one section whenever the same row is cited correctly in another.
  Measured: five of `header_mirror_test.exs`'s nine §3.3 defects were invisible
  for this reason alone, because §2.4 and §5 cite the same rows correctly. So
  the cited set is now scoped to the **enumerating section** — resolved with
  `MCP.Conformance.Citations.sections/1`, which already exists and is already in
  gate 5.

  **The check was ONE-DIRECTIONAL.** `members ⊆ cited` never reports a cited
  address that is not a member, so a citation that drifted **onto another live
  member's address** reads true. Measured: exactly one such citation existed —
  §3.3's `header_mirror_test.exs:410`, authored to name the row now at `:422`
  and landing on the address the row it separately cites as `:399` had moved to.
  So the check is now **set EQUALITY** per section, and the collider becomes
  "cited but not a member".

  Equality needs the non-member citations a section legitimately carries to be
  declared. `non_member_citations/0` is that list, keyed on the **(section,
  address) pair** — the occurrence, never the bare string, for the reason guard
  29's limb B is keyed that way: grandfathering a string licenses every future
  use of it.

  ## The reader, and the one bind it refuses

  A citation is `file.exs:NN`, or a bare `:NN`/`:NN,NN,…` continuation belonging
  to the most recent `.exs` named **in its own paragraph**.

  A `:NN` written immediately after a **non-`.exs`** filename is that file's
  address and binds nothing. The superseded reader recognised only `.exs`
  filenames, so it read `connection.ex:3` as a bare `:3` and credited
  `stdio_test.exs:3` — a citation nobody wrote, in a population the check then
  reported on. That is guard 29's bare-continuation class, and this is the
  narrow form of its refusal: the cross-**file** bind is refused; the comma-run
  continuation is kept, because §3.3 and §2.4 are written in that form and
  refusing it outright would red the document rather than check it.

  ## The residual, stated rather than papered over

  A bare `:NN` whose paragraph names no `.exs` at all cannot be resolved by this
  reader, and there are `unresolvable_bare_citations/0` of them — §2.3's mutation
  table, §3.2's sweep quote, §4.5's gap table and §5.1 all open a paragraph with a
  run of bare addresses. **37 of the 40 were stale when MES-113 measured them**,
  and no limb here could have seen any of them. They are re-resolved in that
  ticket by hand, and the only standing guard over them is the **ratchet**:
  their count is recorded, so the form cannot grow unnoticed. None of the 40 is
  in §2.4 or §3.3, so no enumeration verdict rests on them.
  """

  alias MCP.Conformance.Citations

  @type address :: {String.t(), pos_integer()}

  @citation ~r/(?:([A-Za-z0-9_\/\.]*[A-Za-z0-9_]\.([a-z]+)))?:(\d+(?:\s*,\s*\d+)*)/
  @number ~r/\d+/

  @doc """
  The populations whose per-item enumeration is checked, and the section that
  enumerates each.

  `§2.4` enumerates the `none_determinable` members in six classes; `§3.3`
  enumerates the CG assignments per item. No other section claims to enumerate a
  population, and a population with no enumerating section is not checked here.
  """
  @spec populations() :: [
          %{label: String.t(), section: String.t(), field: String.t(), value: String.t()}
        ]
  def populations do
    [
      %{
        label: "leg: none_determinable",
        section: "§2.4",
        field: "leg",
        value: "none_determinable"
      }
    ] ++
      for cg <- ~w(CG1 CG2 CG4 CG7) do
        %{label: "cg: #{cg}", section: "§3.3", field: "cg", value: cg}
      end
  end

  @doc """
  Citations an enumerating section carries that are **not** members of the
  populations it enumerates, each with the reason it is there.

  Keyed on `{section, address}` — the occurrence. The same address in another
  section is unlisted and goes red, which is the property MES-94's review
  established for guard 29 and the reason that guard is not keyed on the string.
  """
  @spec non_member_citations() :: %{{String.t(), address()} => String.t()}
  def non_member_citations do
    %{
      {"§2.4", {"self_compatibility_test.exs", 101}} =>
        "class (3) cites the client-definite ASSERTION of member :97, not a declaration",
      {"§2.4", {"self_compatibility_test.exs", 110}} =>
        "class (3) cites the server-definite ASSERTION of the same member :97",
      {"§3.3", {"discover_test.exs", 37}} =>
        "CG5's mentioning-not-discharging witness — cited BECAUSE it is not a CG5 member"
    }
  end

  @doc """
  The recorded number of bare `:NN` citations whose paragraph names no `.exs`,
  and which therefore no limb of this predicate can resolve.

  A ratchet, and nothing more: it does not say the 40 are correct, only that a
  41st cannot be added without someone saying so. Measured on MES-113 at
  `2.0.0-dev.52`.
  """
  @spec unresolvable_bare_citations() :: non_neg_integer()
  def unresolvable_bare_citations, do: 40

  @doc """
  Every `:NN` token in `markdown`, in document order.

  `kind` is `:exs` for an address this reader resolves to a test file,
  `:other` for an explicit non-`.exs` file's address, and `:unresolvable` for a
  bare continuation with no `.exs` in paragraph scope.
  """
  @spec tokens(String.t()) :: [map()]
  def tokens(markdown) do
    lines = String.split(markdown, "\n")
    sections = Citations.sections(markdown)

    lines
    |> Enum.zip(paragraph_ids(lines))
    |> Enum.zip(sections)
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, []}, fn {{{line, paragraph}, section}, n}, {state, acc} ->
      {current, found} = line_tokens(line, Map.get(state, paragraph))

      {Map.put(state, paragraph, current),
       acc ++ Enum.map(found, &Map.merge(&1, %{md_line: n, section: section}))}
    end)
    |> elem(1)
  end

  @doc """
  The addresses cited in each section: `%{section => MapSet.t(address())}`.
  """
  @spec cited_by_section(String.t()) :: %{String.t() => MapSet.t(address())}
  def cited_by_section(markdown) do
    markdown
    |> tokens()
    |> Enum.filter(&(&1.kind == :exs))
    |> Enum.group_by(& &1.section, &{&1.file, &1.line})
    |> Map.new(fn {section, addresses} -> {section, MapSet.new(addresses)} end)
  end

  @doc """
  The full audit.

  `register` and `enriched` are the decoded `etcc-register.json` and
  `etcc-attribution.json`. Returns a report with a `:populations` limb (every
  member cited in its own enumerating section), a `:sections` limb (that section
  cites **nothing else**), and the `:unresolvable` ratchet.
  """
  @spec audit(String.t(), map(), map()) :: map()
  def audit(markdown, register, enriched) do
    by_key = Map.new(Map.fetch!(register, "rows"), &{&1["key"], &1})
    cited = cited_by_section(markdown)
    allowed = non_member_citations()

    population_reports =
      for p <- populations() do
        members = member_addresses(enriched, by_key, p)
        in_section = Map.get(cited, p.section, MapSet.new())

        Map.merge(p, %{
          members: members,
          missing: MapSet.difference(members, in_section) |> Enum.sort()
        })
      end

    section_reports =
      for section <- population_reports |> Enum.map(& &1.section) |> Enum.uniq() do
        enumerated =
          population_reports
          |> Enum.filter(&(&1.section == section))
          |> Enum.reduce(MapSet.new(), &MapSet.union(&2, &1.members))

        in_section = Map.get(cited, section, MapSet.new())

        extra =
          in_section
          |> MapSet.difference(enumerated)
          |> Enum.reject(&Map.has_key?(allowed, {section, &1}))
          |> Enum.sort()

        %{section: section, cited: in_section, enumerated: enumerated, extra: extra}
      end

    unresolvable = markdown |> tokens() |> Enum.count(&(&1.kind == :unresolvable))

    %{
      populations: population_reports,
      sections: section_reports,
      unresolvable: unresolvable,
      unresolvable_recorded: unresolvable_bare_citations(),
      ok?:
        Enum.all?(population_reports, &(&1.missing == [])) and
          Enum.all?(section_reports, &(&1.extra == [])) and
          unresolvable == unresolvable_bare_citations()
    }
  end

  @doc """
  The addresses of one population's members, deduplicated.

  Two members can share an address — `extensions_test.exs:35` is two doctests —
  so the count of addresses is not the count of members, and the enumeration is
  over addresses because that is what a citation can name.
  """
  @spec member_addresses(map(), map(), map()) :: MapSet.t(address())
  def member_addresses(enriched, by_key, %{field: field, value: value}) do
    enriched
    |> Map.fetch!("rows")
    |> Enum.filter(&(&1[field] == value))
    |> Enum.map(fn row ->
      register_row = Map.fetch!(by_key, row["key"])
      {Path.basename(register_row["file"]), register_row["line"]}
    end)
    |> MapSet.new()
  end

  # --- the reader -----------------------------------------------------------

  # Paragraphs are blank-line separated; a blank line ends the current one, so a
  # bare continuation never reaches across one.
  defp paragraph_ids(lines) do
    lines
    |> Enum.reduce({[], 0}, fn line, {acc, id} ->
      if String.trim(line) == "", do: {[nil | acc], id + 1}, else: {[id | acc], id}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp line_tokens(line, current) do
    @citation
    |> Regex.scan(line, return: :index)
    |> Enum.reduce({current, []}, fn match, {file, acc} ->
      {extension, name} = matched_file(line, match)
      numbers = run_numbers(line, match)

      case extension do
        "exs" ->
          base = Path.basename(name)
          {base, acc ++ Enum.map(numbers, &token(:exs, base, &1, :explicit))}

        nil when is_nil(file) ->
          {file, acc ++ Enum.map(numbers, &token(:unresolvable, nil, &1, :bare))}

        nil ->
          {file, acc ++ Enum.map(numbers, &token(:exs, file, &1, :bare))}

        _other ->
          # A non-.exs file's own address. It binds nothing, and — this is the
          # refusal — it is NOT read as a continuation of `file`.
          {file, acc ++ Enum.map(numbers, &token(:other, name, &1, :explicit))}
      end
    end)
  end

  defp token(kind, file, {offset, length, value}, form) do
    %{kind: kind, file: file, line: value, offset: offset, length: length, form: form}
  end

  defp matched_file(line, match) do
    case {Enum.at(match, 1), Enum.at(match, 2)} do
      {{-1, 0}, _} -> {nil, nil}
      {{no, nl}, {eo, el}} -> {binary_part(line, eo, el), binary_part(line, no, nl)}
    end
  end

  defp run_numbers(line, match) do
    {offset, length} = Enum.at(match, 3)
    run = binary_part(line, offset, length)

    @number
    |> Regex.scan(run, return: :index)
    |> Enum.map(fn [{o, l}] ->
      {offset + o, l, binary_part(run, o, l) |> String.to_integer()}
    end)
  end
end

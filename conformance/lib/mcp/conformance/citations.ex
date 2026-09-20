defmodule MCP.Conformance.Citations do
  @moduledoc """
  **Guard 29** — every unit `docs/conformance/etcc-register.md` cites in prose is
  cited by its **row key**, and every key it writes is a key the register carries.

  ## What went wrong, and why a line is not an address

  MES-84 inserted `@tag :etcc` lines into the test files that document cites and
  re-addressed 738 citations across ten files. It moved the **explicit**
  `file.exs:NN` citations and left the **bare `:NN` continuations** at MES-81's
  numbering, so the document then carried two numberings at once — sometimes in one
  sentence. Most of the stale addresses landed on a blank line, which is harmless
  because it is obvious. One, `client_test.exs:359`, landed on a **different real
  test**, which is not: it reads as correct and is not. That is `S8-2`, and MES-94
  is the ticket that removed the form rather than chasing the numbers.

  A row key — `inspect(module) <> "/" <> name`, `docs/conformance/etcc-row-key.md`
  §1 — is what `etcc-register.json` is keyed on, and it is exactly the thing that did
  **not** drift while the prose did. So:

    * a unit that **moves** cannot break a citation — the whole point;
    * a unit that is **renamed or deleted** breaks it **loudly**, here.

  ## The boundary with guard 28, drawn on FILES

  Guard 29 quantifies over `docs/conformance/etcc-register.md` and nothing else.
  Guard 28 (MES-102) quantifies over `docs/conformance/etcc-membership.md` §2.5's
  worked-case table and nothing else. Neither can claim a row of the other's, and a
  citation added to either file lands inside exactly one of them.

  ## Two limbs

    * **A — membership.** Every row key written in a code span of the prose must be
      a key of `etcc-register.json` (`rows` ∪ `out_of_scope`, so an out-of-scope
      unit may be cited as one). This is the limb the plan ratified.
    * **B — the ratchet.** A line-shaped citation (`file.exs:NN`, or a bare `:NN`)
      is permitted only where `permitted_line_citations/0` grandfathers **that
      occurrence**: the pair *(§ section, citation text)*, with the number of times
      it may appear in that section and the reason it survives. Converting a
      document and leaving nothing to stop the form coming back would leave the
      conversion to erode; an allow-list of **exceptions** is not the side-car
      manifest the plan rules out, because the population is still read from the
      prose and only the exceptions are named.

  ## Why limb B is keyed on the OCCURRENCE and not on the string

  The first cut of this guard keyed the allow-list on citation **text** alone, and
  CODE_REVIEWER falsified it on MES-94 before it merged: a synthetic **live** `:353`,
  `:29` or `client.ex:868` appended anywhere in the document returned `ok?: true`,
  because each of those strings is grandfathered *somewhere else*. That grandfathers
  the string, not the occurrence, and it smuggles back in exactly the form limb B
  exists to stop — a new bare line citation, indistinguishable in the verdict from
  the historical one it borrows its digits from. So the key is the pair, and the
  count is part of the permission:

    * the same string in a **different** section is **unlisted** — red;
    * an **extra** occurrence in its own section is **over-count** — red, naming how
      many are permitted and how many were found.

  The section is the document's **own** stable self-address — §0.1 rules that this
  file cites a section of itself by its `§` number and never by line — so limb B
  pins an exception to the same address the prose is required to use, and no line
  number enters the allow-list.

  ## What limb A rests on, stated rather than assumed

  It validates prose against `etcc-register.json`, **not against the live suite**.
  That is deliberate — the register is the artefact the prose is about — but it
  means the chain is *prose → register → suite*, and the second hop is **MES-84's**
  drift guard, not this one. A rename that is made and regenerated in one commit is
  caught here; a rename made without regenerating is caught there.

  ## What it does NOT do — the residual, by enumeration

    * It does not check that a citation is *apt* — that the unit named is the unit
      the sentence is about. No guard checks judgement. What it removes is the
      failure where a citation silently comes to name a **different** unit without
      anybody editing it.
    * Limb B's bound is an **upper** bound per *(section, text)*. **Deleting** a
      grandfathered citation stays green — the ratchet is monotone, so a correction
      note that is rewritten into keys never has to ask permission — and an
      allow-list entry the document no longer writes is reported as
      `stale_permissions` and asserted empty against the committed document by
      `test/conformance/etcc_citations_test.exs`, not by `ok?`.
    * Because the bound is per section and not per site, **deleting** a
      grandfathered occurrence and writing a **live** citation with the same text
      into the same section is not caught: the count is unchanged. That takes a
      deliberate edit to a correction note that says in terms it is quoting a wrong
      address, and narrowing it further would mean anchoring an exception to a line
      — the disease this document was re-keyed to cure.
  """

  @register "docs/conformance/etcc-register.json"
  @document "docs/conformance/etcc-register.md"

  # A row key, as written in a code span: `<Module>/<test|doctest> <name>`.
  @key_shape ~r{\A[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*/(?:test|doctest) \S.*\z}s

  # `file.ext:NN` or `file.ext:NN-MM`.
  @explicit ~r{[A-Za-z0-9_./-]+\.(?:exs|ex|md|json|ts|mdx|py|txt):\d+(?:[-–]\d+)?}
  # A bare `:NN` continuation, once explicit citations are masked out.
  @bare ~r{(?<![\w./-]):\d+(?:[-–]\d+)?\b}

  # An ATX heading that opens a numbered section: `## §6a …`, `### §0.1 …`.
  @section_heading ~r/\A[#]+\s+(§\d+[a-z]?(?:\.\d+)*)/u

  # Lines above the first numbered heading. Never a key of the allow-list, so a
  # line-shaped citation written up there is unlisted and red.
  @preamble "(preamble)"

  @typedoc "A code span found in the prose, with the 1-based line it was written on."
  @type span :: %{text: String.t(), line: pos_integer()}

  @typedoc "A line-shaped citation, with its 1-based line and the § section it stands in."
  @type found :: %{text: String.t(), line: pos_integer(), section: String.t()}

  @doc """
  The line-shaped citations `etcc-register.md` is allowed to keep — keyed on the
  **occurrence**, `{section, text}`, and valued `{class, how many times}`.

  Two classes, and both are marked in the document where they stand:

    * `:frozen` — §6's six worked cases and MES-93's superseding note above them.
      MES-93 froze §6 as the provenance record of where the decode-boundary rule
      came from; a provenance record altered is no longer one, and the rule itself
      now lives keyed on `{module, test name}` at `etcc-membership.md` Part A §2.5.
      PM-ruled on MES-94.
    * `:quoted` — a historical address quoted **as the defect under discussion**,
      inside a correction note that exists to say it was wrong. Rewriting those
      would delete the evidence the note is made of.

  The section is part of the key because a permission that travelled with the
  **string** let a new live citation borrow a historical one's digits — see the
  moduledoc. The count is part of the value for the same reason: a second `:353` in
  §6 is a citation nobody grandfathered.

  Spec anchors (`schema.ts:NN`, `changelog.mdx:NN`) are **not** here: they are not
  in this tree, no commit of ours moves them, and they are ruled out of scope
  separately. `line_citations/1` excludes them.
  """
  @spec permitted_line_citations() :: %{{String.t(), String.t()} => {atom(), pos_integer()}}
  def permitted_line_citations do
    %{
      # --- §6: the six frozen worked cases, and MES-93's note stating their drift
      {"§6", ":89"} => {:frozen, 2},
      {"§6", ":124"} => {:frozen, 2},
      {"§6", ":141"} => {:frozen, 2},
      {"§6", ":182"} => {:frozen, 2},
      {"§6", ":347"} => {:frozen, 2},
      {"§6", ":353"} => {:frozen, 3},
      {"§6", ":359"} => {:frozen, 2},
      # verbatim quotations of register FIELD VALUES inside MES-93's note
      {"§6", "test/mcp/client_test.exs:59"} => {:frozen, 1},
      {"§6", "client.ex:868"} => {:frozen, 2},

      # --- §2: MES-87's S8-1 note, quoting the addresses that were already wrong
      {"§2", ":197"} => {:quoted, 1},
      {"§2", ":214"} => {:quoted, 1},
      {"§2", ":425"} => {:quoted, 2},
      {"§2", ":1411"} => {:quoted, 2},
      {"§2", ":1414"} => {:quoted, 2},

      # --- §6a: F15 and F16, quoting the addresses the granularity ruling turned on
      {"§6a", ":7"} => {:quoted, 2},
      {"§6a", ":26"} => {:quoted, 1},
      {"§6a", ":29"} => {:quoted, 4},
      {"§6a", "capabilities_test.exs:31"} => {:quoted, 1},

      # --- §8: the dropped round-2 arrows, quoted as the addresses they were
      {"§8", ":80"} => {:quoted, 2},
      {"§8", ":82"} => {:quoted, 1},
      {"§8", "streamable_http_stateless_test.exs:82"} => {:quoted, 1}
    }
  end

  @doc """
  The `§` section every line of `markdown` stands in, one entry per line.

  An ATX heading that opens with a `§` number sets the section; a sub-heading
  without one belongs to the numbered section above it, which is how §6's
  worked-case sub-heading is part of §6. Lines above the first numbered heading are
  `"(preamble)"`.

      iex> MCP.Conformance.Citations.sections("# title\\n## §6 rule\\n### sub\\n## §7 x")
      ["(preamble)", "§6", "§6", "§7"]
  """
  @spec sections(String.t()) :: [String.t()]
  def sections(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.scan(@preamble, fn line, current ->
      case Regex.run(@section_heading, line) do
        [_, anchor] -> anchor
        nil -> current
      end
    end)
  end

  @doc """
  Every code span in `markdown`, innermost content only, with its line.

  Double-backtick spans are read first, so a key containing a backtick — there is
  one, `MCP.Protocol.Types.ToolTest`'s `inputSchema keywords beyond \\`type\\`` row —
  survives extraction instead of being cut at its first backtick. CommonMark strips
  one leading and one trailing space when **both** are present, and so does this.

      iex> MCP.Conformance.Citations.code_spans("a `b` c")
      [%{text: "b", line: 1}]

      iex> MCP.Conformance.Citations.code_spans("x\\n`` a `b` c ``")
      [%{text: "a `b` c", line: 2}]
  """
  @spec code_spans(String.t()) :: [span()]
  def code_spans(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, n} -> line |> spans_in() |> Enum.map(&%{text: &1, line: n}) end)
  end

  defp spans_in(line) do
    {doubles, rest} = take_spans(line, ~r/``(.+?)``/)
    {singles, _} = take_spans(rest, ~r/`([^`]+)`/)
    Enum.map(doubles ++ singles, &unpad/1)
  end

  defp take_spans(line, re) do
    found = Regex.scan(re, line) |> Enum.map(fn [_, inner] -> inner end)

    {found,
     Regex.replace(re, line, fn whole, _ -> String.duplicate(" ", String.length(whole)) end)}
  end

  defp unpad(<<" ", rest::binary>> = text) do
    if String.ends_with?(text, " ") and String.trim(text) != "",
      do: String.slice(rest, 0, String.length(rest) - 1),
      else: text
  end

  defp unpad(text), do: text

  @doc """
  The row keys written in `markdown`'s prose, deduplicated, in first-seen order.

      iex> MCP.Conformance.Citations.keys("see `MCP.ClientTest/test lifecycle times out a pending request`")
      ["MCP.ClientTest/test lifecycle times out a pending request"]

      iex> MCP.Conformance.Citations.keys("`MCP.Client.encode/1` and `inspect(module)`")
      []
  """
  @spec keys(String.t()) :: [String.t()]
  def keys(markdown) do
    markdown
    |> code_spans()
    |> Enum.filter(&Regex.match?(@key_shape, &1.text))
    |> Enum.map(& &1.text)
    |> Enum.uniq()
  end

  @doc """
  Line-shaped citations in `markdown`, spec anchors excluded, with their line and
  the `§` section they stand in.

      iex> MCP.Conformance.Citations.line_citations("## §6 x\\ncited at `client_test.exs:353`, then `:359`")
      [
        %{text: "client_test.exs:353", line: 2, section: "§6"},
        %{text: ":359", line: 2, section: "§6"}
      ]

      iex> MCP.Conformance.Citations.line_citations("anchor `schema.ts:450`")
      []
  """
  @spec line_citations(String.t()) :: [found()]
  def line_citations(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.zip(sections(markdown))
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{line, section}, n} ->
      explicit = Regex.scan(@explicit, line) |> Enum.map(&hd/1) |> Enum.reject(&spec?/1)
      masked = Regex.replace(@explicit, line, fn w -> String.duplicate(" ", String.length(w)) end)
      bare = Regex.scan(@bare, masked) |> Enum.map(&hd/1)
      Enum.map(explicit ++ bare, &%{text: &1, line: n, section: section})
    end)
  end

  defp spec?(text) do
    String.starts_with?(text, ["schema.ts:", "changelog.mdx:", "docs/specification/"])
  end

  @doc """
  Decide both limbs from already-read inputs. Pure, so every red is reachable in a
  unit test without touching the repository.

  Returns
  `%{ok?: boolean, key_count: n, unknown_keys: [...], unpermitted: [...], stale_permissions: [...]}`.

    * `unknown_keys` is limb A's red;
    * `unpermitted` is limb B's — each entry carries `:reason`, either `:unlisted`
      (no permission for that *(section, text)* at all) or `:over_count` (more
      occurrences than the permission allows), with the `:permitted` and `:seen`
      counts that decided it;
    * `stale_permissions` is **not** a red. It names allow-list entries the document
      no longer writes as often as permitted, so the list can be seen to stop
      describing the document; keeping it out of `ok?` is what makes the ratchet
      monotone under deletion.
  """
  @spec decide(String.t(), MapSet.t(String.t())) :: map()
  def decide(markdown, register_keys) do
    cited = keys(markdown)
    unknown = Enum.reject(cited, &MapSet.member?(register_keys, &1))
    permitted = permitted_line_citations()
    by_occurrence = markdown |> line_citations() |> Enum.group_by(&{&1.section, &1.text})

    unpermitted =
      by_occurrence
      |> Enum.flat_map(fn {pair, found} ->
        surplus(pair, Enum.sort_by(found, & &1.line), permitted)
      end)
      |> Enum.sort_by(&{&1.line, &1.text})

    %{
      ok?: unknown == [] and unpermitted == [],
      key_count: length(cited),
      unknown_keys: unknown,
      unpermitted: unpermitted,
      stale_permissions: stale_permissions(permitted, by_occurrence)
    }
  end

  defp surplus(pair, found, permitted) do
    case Map.fetch(permitted, pair) do
      :error ->
        Enum.map(found, &Map.merge(&1, %{reason: :unlisted, permitted: 0, seen: length(found)}))

      {:ok, {_class, allowed}} ->
        at = Enum.map(found, & &1.line)

        found
        |> Enum.drop(allowed)
        |> Enum.map(
          &Map.merge(&1, %{
            reason: :over_count,
            permitted: allowed,
            seen: length(found),
            lines: at
          })
        )
    end
  end

  defp stale_permissions(permitted, by_occurrence) do
    permitted
    |> Enum.map(fn {{section, text} = pair, {class, allowed}} ->
      %{
        section: section,
        text: text,
        class: class,
        permitted: allowed,
        seen: length(Map.get(by_occurrence, pair, []))
      }
    end)
    |> Enum.filter(&(&1.seen < &1.permitted))
    |> Enum.sort_by(&{&1.section, &1.text})
  end

  @doc """
  Run guard 29 against the committed document and register.

  `root` defaults to the project root. Raises `RuntimeError` naming every offender;
  returns the verdict map on success.
  """
  @spec check!(Path.t()) :: map()
  def check!(root \\ File.cwd!()) do
    verdict = decide(read_document(root), register_keys(root))

    if verdict.ok? do
      verdict
    else
      raise "GUARD 29 FAILS on #{@document}:\n" <> explain(verdict)
    end
  end

  @doc "The document's prose, read from disk."
  @spec read_document(Path.t()) :: String.t()
  def read_document(root \\ File.cwd!()), do: File.read!(Path.join(root, @document))

  @doc """
  Every key `etcc-register.json` carries — `rows` **and** `out_of_scope`.

  Both, because an out-of-scope unit is a thing this document legitimately cites
  (§9 does), and `etcc-row-key.md` §4.1 is explicit that an absent key and an
  excluded one are different facts.
  """
  @spec register_keys(Path.t()) :: MapSet.t(String.t())
  def register_keys(root \\ File.cwd!()) do
    json = root |> Path.join(@register) |> File.read!() |> Jason.decode!()

    (Map.fetch!(json, "rows") ++ Map.fetch!(json, "out_of_scope"))
    |> Enum.map(&Map.fetch!(&1, "key"))
    |> MapSet.new()
  end

  @doc "A human-readable account of a failing verdict."
  @spec explain(map()) :: String.t()
  def explain(verdict) do
    limb_a =
      case verdict.unknown_keys do
        [] ->
          []

        ks ->
          [
            "  LIMB A — #{length(ks)} cited key(s) the register does not carry:"
            | Enum.map(ks, &"    #{&1}")
          ]
      end

    limb_b =
      case verdict.unpermitted do
        [] ->
          []

        cs ->
          [
            "  LIMB B — #{length(cs)} line-shaped citation(s) not permitted where written:"
            | Enum.map(cs, &offence/1)
          ]
      end

    Enum.join(
      limb_a ++
        limb_b ++ ["  See etcc-register.md §0.1 for the citation form this guard enforces."],
      "\n"
    )
  end

  defp offence(%{reason: :unlisted} = c) do
    "    #{@document}:#{c.line}  #{c.text}  in #{c.section} — UNLISTED, no permission for this section"
  end

  defp offence(%{reason: :over_count} = c) do
    # Every site is named, not just the surplus one: which of them is the NEW one
    # is a question the counts cannot answer, and guessing would point at the wrong
    # line as often as not.
    "    #{@document}:#{c.line}  #{c.text}  in #{c.section} — OVER-COUNT, " <>
      "#{c.seen} written (lines #{Enum.join(c.lines, ", ")}), #{c.permitted} permitted"
  end
end

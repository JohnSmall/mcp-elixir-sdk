defmodule MCP.Conformance.CitationVerbatim do
  @moduledoc """
  **Guard 30** — a quoted byte-string in a record's `evidence` must occur
  **verbatim and contiguous** inside a window the evidence itself **addresses**.

  Ruling 7 is "an address AND the bytes at it". The client leg's citation sweeps
  established the first half — every cited address resolves to a real line — and
  nothing established the second. MES-108 ran the byte comparison by hand over
  its own rows and caught two defects a careful read had passed; MES-109 ran it
  and caught two more. Both said in terms that the general guard was MES-112 and
  was not built. This is it.

  ## The two limbs, and each is independently falsifiable

  They are two properties of one predicate rather than one property counted
  twice, and a mutation defeats each with the other left intact.

    * **WINDOWING** — the comparison runs against the **cited span**, never
      against the whole artefact. C1a's `capabilities_test.exs:97` had the right
      bytes one line outside its window. Drop the window — search the whole file
      — and every stale-address defect goes green while staying wrong.
    * **CONTIGUITY** — the window is one whitespace-squashed string and the test
      is substring containment, so a quote spliced from two non-adjacent lines
      is contiguous nowhere. That is MES-109's composed quote,
      `Protocol.encode(Request.new(1, "tools/list", %{"cursor" => "abc"}))`,
      which reads exactly like source and appears in no file. Relax containment
      to token-wise matching and it goes green with the window fully intact.

  `audit/3` takes `limbs:` so a control can run with one limb dropped and show
  the other cannot cover for it. Dropping WINDOWING compares against the
  caller's **broad** windows (the whole file, the whole build); dropping
  CONTIGUITY asks only that every token of the quote occurs *somewhere* in the
  window. Neither relaxation is ever used by the generator — they exist so the
  claim "both limbs are load-bearing" is a measurement rather than an assertion.

  ## An ellipsis inside a source-shaped span is REFUSED, not fragment-matched

  Ratified on MES-112. Admitting `A … B` by matching the non-elided fragments
  **is** the composed-quote hole, re-opened deliberately: it green-lights a
  quote whose halves sit arbitrarily far apart. It would also install a second,
  weaker predicate that no mutation could tell from the strong one — a guard
  with two verdicts and one control attests the easier of them. So an elision is
  a defect in its own right, named as such, and the fix is to re-lift the bytes
  or to stop claiming they are bytes.

  ## A bare `:N` continuation is a FAILURE, not a lookup

  `:262` after a full citation earlier in the same string has no syntactic
  referent — S9's bare-continuation finding — and resolving it against the
  nearest preceding file name is guessing. The guard goes on refusing the
  **form**; the recovery is done once, by an author, into the artefact.

  ## It is artefact-agnostic, and that is deliberate

  It takes **records and windows**, not edges files: `windows_fun` is the only
  thing that knows what an ET line span or an OC byte span is. MES-113 reuses
  the predicate over the attribution surface by supplying its own
  `windows_fun`, without re-deriving any of this. It is **not** wired there
  here.

  ## Fail-closed on a window it cannot build

  A `windows_fun` that cannot construct a window — the harness build absent, so
  an OC byte span cannot be read — returns the reason in `:unavailable`, and a
  quote that no available window places is reported as `:undeterminable_window`
  rather than passing. "I could not tell" is not "it is fine": that is MES-56's
  rule, and reading absence as satisfaction is the failure this whole family of
  guards exists to stop.

  ## What it does NOT establish, by enumeration

    * **Aptness.** That the quote SUPPORTS the verdict it is filed under is a
      judgement, and no refusal reaches it (A3 §7's residual).
    * **Prose accuracy.** Only backtick spans that look like source — carrying
      `=`, `(`, `[`, `!==` or `===` — are treated as lifts. A backticked prose
      phrase is not compared against anything, so an inaccurate paraphrase
      passes. The remedy the ruling gives is to *de-quote* prose, not to widen
      the shape test until English starts failing it.
    * **Layout.** The comparison squashes runs of whitespace, so it accepts a
      quote the formatter has wrapped at a different point than the author did.
      Deliberate — the alternative reddens on `mix format` — and it means the
      check is on the bytes modulo layout, not on the layout.
    * **Fields other than the one the caller passes.** It quantifies over
      whatever string `windows_fun`'s caller hands it as `evidence`. A quoted
      byte-string in some *other* field of the same record is outside this
      guard, and outside it visibly: `records_with_evidence` is reported next to
      `records_visited`, so the gap between them is on the face of the artefact.
  """

  @typedoc "A window to search: a label for reporting, and its squashed bytes."
  @type window :: {String.t(), String.t()}

  @typedoc """
  What `windows_fun` returns for one record.

  EVERY WINDOW ARRIVES SQUASHED. `audit/3` squashes the needle and not the
  haystack, deliberately: the haystack may be an 800KB build, and squashing it
  once in the builder rather than once per record is the difference between
  seconds and minutes. A builder that forgets produces false REDS on correct
  citations, so `line_window/3` and `squash/1` are exported for builders to use
  rather than re-derive.

  `narrow` are the windows the evidence ADDRESSES — the guard's real question.
  `broad` are the same sources unaddressed (the whole file, the whole build),
  used only when a control drops the WINDOWING limb. `unavailable` names every
  window that could not be built, and makes an unplaced quote undeterminable
  rather than wrong.
  """
  @type windows :: %{
          required(:narrow) => [window()],
          required(:broad) => [window()],
          required(:unavailable) => [String.t()]
        }

  @typedoc "One way a record's evidence fails ruling 7."
  @type defect :: %{String.t() => term()}

  # A backtick span, tolerating one nested pair (`` `a `b` c` ``) so the regex
  # reports the span the author wrote rather than a fragment of it — MES-109
  # caught that shape reporting a string nobody had ever written.
  @quote_re ~r/`((?:[^`]|`[^`]*`(?=[^`]*`))+?)`(?!`)/

  # `file.exs:N` or `file.exs:N-M`.
  @cite_re ~r/([a-z0-9_]+\.exs?):(\d+)(?:-(\d+))?/

  # A bare `:N` continuation, once a full citation's own `:N` is excluded by the
  # lookbehinds.
  @bare_cite_re ~r/(?<![\w.])(?<!\.exs)(?<!\.ex):(\d+)\b/

  # What makes a backtick span SOURCE-SHAPED rather than a prose phrase.
  @source_shaped ~r/[=(\[]|!==|===/

  # An elision, in either spelling.
  @ellipsis_re ~r/…|\.\.\./u

  @all_limbs [:windowing, :contiguity]

  @doc """
  The limbs, so a control names them from here rather than restating them.
  """
  @spec limbs() :: [atom()]
  def limbs, do: @all_limbs

  @doc """
  Audit `records` against the windows `windows_fun` builds for each.

  `windows_fun` is called once per record and returns `t:windows/0`. The
  `evidence` key is read off the record; a record carrying none is visited and
  contributes nothing, which is counted and reported rather than skipped
  silently.

  ## Options

    * `:limbs` — which limbs are active, default both. Dropping `:windowing`
      compares against `broad`; dropping `:contiguity` asks only for token
      presence. For controls; the generator never passes this.
    * `:field` — the record key holding the prose, default `"evidence"`.
    * `:label` — a 1-arity function naming a record in a defect, default the
      record's `claim`, else its `tag`.

  Returns a map with `records_visited`, `records_with_evidence`,
  `quotes_compared`, `quotes_counted`, `matched_in` and `defects`.
  `quotes_counted` is an INDEPENDENT count taken by walking the span regex over
  the same records; `quotes_compared == quotes_counted` is what says the sweep
  reached every quote rather than stopping at the first, and neither figure is
  ever a literal.
  """
  @spec audit([map()], (map() -> windows()), keyword()) :: map()
  def audit(records, windows_fun, opts \\ []) when is_function(windows_fun, 1) do
    limbs = Keyword.get(opts, :limbs, @all_limbs)
    field = Keyword.get(opts, :field, "evidence")
    label_fun = Keyword.get(opts, :label, &default_label/1)

    init = %{
      "records_visited" => 0,
      "records_with_evidence" => 0,
      "quotes_compared" => 0,
      "quotes_counted" => 0,
      "matched_in" => %{},
      "defects" => []
    }

    records
    |> Enum.reduce(init, &visit(&1, &2, windows_fun, limbs, field, label_fun))
    |> Map.update!("defects", &Enum.reverse/1)
    |> Map.put("limbs", Enum.map(limbs, &Atom.to_string/1))
  end

  defp visit(record, acc, windows_fun, limbs, field, label_fun) do
    evidence = Map.get(record, field) || ""
    acc = Map.update!(acc, "records_visited", &(&1 + 1))

    if evidence == "" do
      acc
    else
      do_visit(record, evidence, acc, windows_fun, limbs, label_fun)
    end
  end

  defp do_visit(record, evidence, acc, windows_fun, limbs, label_fun) do
    label = label_fun.(record)
    windows = windows_fun.(record)
    quotes = source_quotes(evidence)

    bare =
      for n <- bare_citations(evidence),
          do: defect("bare_citation_has_no_file", label, n, windows)

    {compared, matched, quote_defects} =
      Enum.reduce(quotes, {0, %{}, []}, fn q, {n, hits, bad} ->
        case place(q, windows, limbs) do
          {:matched, where} -> {n + 1, Map.update(hits, where, 1, &(&1 + 1)), bad}
          {:defect, kind} -> {n, hits, [defect(kind, label, q, windows) | bad]}
        end
      end)

    acc
    |> Map.update!("records_with_evidence", &(&1 + 1))
    |> Map.update!("quotes_compared", &(&1 + compared))
    |> Map.update!("quotes_counted", &(&1 + length(quotes)))
    |> Map.update!("matched_in", &Map.merge(&1, matched, fn _k, a, b -> a + b end))
    |> Map.update!("defects", &(Enum.reverse(quote_defects) ++ Enum.reverse(bare) ++ &1))
  end

  # The predicate itself. The ELLIPSIS test comes first because an elided quote
  # is a defect whatever the window holds, and reporting it as "not verbatim"
  # would name the symptom and hide the rule.
  defp place(quote_text, windows, limbs) do
    if Regex.match?(@ellipsis_re, quote_text) do
      {:defect, "elision_is_not_a_lift"}
    else
      search(squash(quote_text), searchable(windows, limbs), windows, limbs)
    end
  end

  defp search(needle, haystacks, windows, limbs) do
    case Enum.find(haystacks, fn {_label, bytes} -> contains?(bytes, needle, limbs) end) do
      {label, _bytes} -> {:matched, label}
      nil -> {:defect, unplaced_kind(windows)}
    end
  end

  # WINDOWING, as a choice of haystack: the addressed spans, or — with the limb
  # dropped — the same sources with their addresses thrown away.
  defp searchable(windows, limbs) do
    if :windowing in limbs, do: windows.narrow, else: windows.broad
  end

  # CONTIGUITY, as a choice of test: one substring, or — with the limb dropped —
  # every token somewhere, in any order and any distance apart.
  defp contains?(bytes, needle, limbs) do
    if :contiguity in limbs do
      String.contains?(bytes, needle)
    else
      needle |> String.split(" ", trim: true) |> Enum.all?(&String.contains?(bytes, &1))
    end
  end

  # Fail-closed: a quote nothing placed is WRONG only if every window that bears
  # on it could actually be read. Otherwise it is undeterminable, and that is a
  # refusal with a different name and a different remedy.
  defp unplaced_kind(%{unavailable: []}), do: "not_verbatim_at_any_cited_address"
  defp unplaced_kind(%{unavailable: _}), do: "undeterminable_window"

  defp defect(kind, label, detail, windows) do
    %{
      "kind" => kind,
      "row" => label,
      "detail" => detail,
      "windows_addressed" => Enum.map(windows.narrow, fn {l, _} -> l end),
      "windows_unavailable" => windows.unavailable
    }
  end

  defp default_label(record),
    do: String.slice(record["claim"] || record["tag"] || "?", 0, 70)

  @doc """
  The backtick spans in `text` that are SOURCE-SHAPED — carrying `=`, `(`, `[`,
  `!==` or `===`.

  A prose phrase in backticks is not a lift and is not compared. That is the
  bound stated in the moduledoc, and it is exactly why the ruling's remedy for
  prose wearing backticks is to remove the backticks.
  """
  @spec source_quotes(String.t()) :: [String.t()]
  def source_quotes(text) do
    for [_, q] <- Regex.scan(@quote_re, text), Regex.match?(@source_shaped, q), do: q
  end

  @doc """
  The bare `:N` continuations in `text`, as they were written.
  """
  @spec bare_citations(String.t()) :: [String.t()]
  def bare_citations(text) do
    for [_, n] <- Regex.scan(@bare_cite_re, text), do: ":" <> n
  end

  @doc """
  The `file.exs:N` / `file.exs:N-M` spans `text` addresses, as
  `{basename, from, to}` with `to >= from`.
  """
  @spec cited_line_spans(String.t()) :: [{String.t(), pos_integer(), pos_integer()}]
  def cited_line_spans(text) do
    for capture <- Regex.scan(@cite_re, text) do
      [_, file, from | rest] = capture
      a = String.to_integer(from)

      b =
        case rest do
          [to] when to != "" -> String.to_integer(to)
          _ -> a
        end

      {file, a, max(a, b)}
    end
  end

  @doc """
  Lines `from`..`to` of `source`, squashed — the ET window for one cited span.
  """
  @spec line_window(String.t(), pos_integer(), pos_integer()) :: String.t()
  def line_window(source, from, to) do
    source
    |> String.split("\n")
    |> Enum.slice((from - 1)..(to - 1)//1)
    |> Enum.join("\n")
    |> squash()
  end

  @doc "Runs of whitespace collapsed to one space, and trimmed."
  @spec squash(String.t()) :: String.t()
  def squash(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()
end

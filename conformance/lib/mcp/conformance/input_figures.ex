defmodule MCP.Conformance.InputFigures do
  @moduledoc """
  **Guard 31** — every population figure a hand-authored conformance input
  asserts in prose is **adjudicated against measurement at the tip**, and every
  backticked field-name cross-reference it makes **resolves**.

  ## Why G21 cannot do this, by construction

  G21 (`population_statement_guard`, MES-104/108) scans the EMITTED crosswalk,
  and a string is the generator's own only if it occurs in no input document.
  So every figure an input states is outside its universe, a word-spelled figure
  is invisible to it, and a stale figure that composes into no artefact at all is
  unreachable forever. Sprint 11 corrected thirty-odd such figures by hand across
  four tickets (S11-2), and each ticket's sweep missed ones the next found.

  ## The population is the file's OWN assertions (ruling on MES-120)

  Not a list of figures somebody knows moved, not a diff, not the emitted
  artefact. `scan/2` reads every prose leaf of every hand-authored file with one
  recogniser — a numeral or number-word, optionally hedged, up to two words
  before a population noun — and **every** occurrence it returns must be
  accounted for. Two reasons, both measured on MES-116/117: a sweep over the
  figures a slice knows it moved cannot reach a count the slice moved without
  knowing; and a figure wrong at its own commit never moved at all.

  ## The ledger — keyed on the OCCURRENCE, never on the value

  `conformance/figures/ledger.json` holds one entry per occurrence
  `{file, path, phrase, nth}` (`nth` counts the same phrase within one leaf).
  An entry is one of:

    * **measured** — names a quantity from the ledger's finite `quantities`
      registry. The guard evaluates the query against the files at the tip and
      requires `figure == measured`. A hedge (`about three`) buys nothing.
    * **enumerated** — names a list in the same file; `figure == length`.
    * **historical** — carries `as_of`, a ticket key, a slice id or a sha, and
      the guard requires that anchor to occur **in the same sentence**. That is
      the whole historical-versus-present rule: an unanchored sentence reads as
      present tense and must be measured.
    * **not_a_count** — the recogniser matched a phrase that asserts no
      population (`one record per (member, claim, check)`, `a check has up to
      five axes`). It carries a `reason`, and it is reported as its own class so
      the number of things waved through this way is visible on every run.

  And a transitional class, **pending** (PM ruling R on MES-120): an
  occurrence that existed at the baseline commit and is owned by MES-131. The
  pending set must EQUAL the scan's unadjudicated remainder, so a new figure is
  refused and a departed one must leave the set; every pending entry must occur
  in the file **as it was at the baseline commit** (read from git), so no file
  added later can carry one; and it must sit inside the ledger's
  `pending_admissible` scope, so the file-level figures of the crosswalk inputs
  — adjudicated here — cannot slide back into it.

  Those two properties rest on ledger data (`baseline`, `pending_admissible`),
  and the ledger is outside D7's reviewable paths, so the guard alone does not
  hold them. Gate 5 does: `test/conformance/input_figures_test.exs` pins the
  baseline to `7497292`, the scope to the seven rows MES-120 delivered, and the
  pending SET to a subset of the delivered keys committed under
  `test/fixtures/conformance/`. That subset test is what makes "may only shrink"
  a property of the set and not merely of its count.

  ## What is refused, and each refusal names the guard, the file and the path

  `unledgered` (a scanned figure with no entry), `stale_entry` (an entry whose
  phrase no longer occurs), `mismatch`, `unanchored_historical`, `unparseable`
  (a figure-shaped match that will not parse), `unknown_quantity`,
  `quantity_error`, `reason_outside_closed_set` (a not_a_count code, in the
  ledger or on an entry, outside the guard's `R1`..`R7`), `pending_*`,
  `duplicate_entry`, `bad_entry`, and for the
  cross-references `unresolved_reference`. The universe refusals are
  `unregistered_file`, `absent_file`, `marker_disagreement` and `unreadable`.

  ## The universe is DERIVED and closed both ways

  The guard walks `conformance/data/**` and `docs/conformance/**/*.json` and
  requires the walk to EQUAL `conformance/figures/universe.json` in both
  directions: an unlisted file is refused and a listed-but-absent file is
  refused. A file that carries `authored_by_hand: true` or `generated_by` must be
  registered consistently with it. So an adjudication record added under
  `docs/conformance/` later lands inside the guard, or turns it red, on arrival.

  ## Reach

  The report counts every occurrence visited and classifies each exactly once;
  `audit/1` refuses a run that visited nothing, or whose classes do not sum to
  what it visited, so a reader that sees nothing cannot pass.

  ## What it does NOT establish

    * That a **measured** quantity is the RIGHT quantity for the sentence. The
      binding of phrase to query is a judgement made once in the ledger; the
      guard holds the number to it thereafter.
    * That a **historical** sentence was true when written. The anchor dates it;
      it does not check it.
    * Figures the recogniser does not see: a count whose noun is not in the
      population-noun list, a count more than two words from its noun, a figure
      in a FIELD NAME (shape 4) or a claim about structure (shape 3). Shapes 3
      and 4 are MES-132's.
  """

  @guard "G31"
  @universe_path "conformance/figures/universe.json"
  @ledger_path "conformance/figures/ledger.json"
  @walk_roots [{"conformance/data", "**"}, {"docs/conformance", "**/*.json"}]
  @classes ~w(hand_authored generated raw_evidence)
  @entry_classes ~w(measured enumerated historical not_a_count)
  # The not_a_count reason codes are a CLOSED set here, in the guard, not in the
  # ledger (PM ruling on MES-120): the ledger states what each means, but a code
  # outside this set is refused, so a new way to wave a figure through is a
  # reviewed change to conformance/lib, not a ledger-only edit.
  @reasons ~w(R1 R2 R3 R4 R5 R6 R7)

  def guard, do: @guard
  def reasons, do: @reasons
  def universe_path, do: @universe_path
  def ledger_path, do: @ledger_path

  # --- the recogniser -------------------------------------------------------

  @number_words ~w(zero one two three four five six seven eight nine ten eleven twelve
                   thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty
                   thirty forty fifty sixty seventy eighty ninety hundred)
  @unit_words ~w(one two three four five six seven eight nine)
  @nouns ~w(members? checks? edges? entries rows? modules? claims? axes conjuncts? clauses?
            scenarios? searches slices? leaves records? near-misses declared)
  @hedges [
    "about",
    "around",
    "roughly",
    "some",
    "nearly",
    "over",
    "under",
    "at least",
    "at most",
    "exactly",
    "all",
    "only"
  ]

  @figure Regex.compile!(
            "(?<![\\w.\\-\\[,§#/:])" <>
              "(?:(" <>
              Enum.join(@hedges, "|") <>
              ")\\s+)?" <>
              "(\\d+(?:,\\d{3})*(?:\\.\\d+)?|(?:" <>
              Enum.join(@number_words, "|") <>
              ")(?:[- ](?:" <>
              Enum.join(@unit_words, "|") <>
              "))?)" <>
              "(?:\\s+(?:`[^`\\s]+`|[A-Za-z0-9_\\-'’]+)){0,2}?\\s+(" <>
              Enum.join(@nouns, "|") <> ")\\b",
            "iu"
          )

  @reference ~r/`([a-z][a-z0-9]*(?:_[a-zA-Z0-9]+)+)`/u
  @anchor ~r/^(MES-\d+|C1[a-c](?:-(?:i|ii|iii|iv)(?:-[ab])?)?|[0-9a-f]{7,40})$/

  @doc "The recogniser. Exposed so a control can show what it does and does not match."
  def figure_regex, do: @figure

  @doc """
  Every figure occurrence in `doc`'s prose leaves, as
  `%{file, path, phrase, nth, hedge, number, noun, value, sentence}`.
  `value` is an integer or `:unparseable`; an unhedged `one` directly after
  `not` reads as 0 (`not one edge` asserts zero edges), with the phrase — and so
  the ledger key — unchanged.
  """
  def scan(doc, file) do
    doc
    |> leaves([])
    |> Enum.flat_map(fn {path, s, record} -> scan_leaf(file, path, s, record) end)
  end

  defp scan_leaf(file, path, s, record) do
    @figure
    |> Regex.scan(s, return: :index)
    |> Enum.map(fn [{start, len} | groups] ->
      [hedge, number, noun] = Enum.map(groups, &group(s, &1))

      %{
        file: file,
        path: path,
        phrase: binary_part(s, start, len),
        hedge: hedge,
        number: number,
        noun: noun,
        value: if(negated?(s, start, hedge, number), do: 0, else: parse(number)),
        sentence: sentence(s, start, len),
        record: record
      }
    end)
    |> number_occurrences(& &1.phrase)
  end

  # `not one edge` asserts ZERO edges. The phrase (the ledger key) stays
  # `one edge`, so the key is unchanged; only the value is read as 0. Unhedged
  # `one` only: `not two rows` does not assert a figure at all.
  defp negated?(s, start, nil, number) do
    String.downcase(number) == "one" and
      binary_part(s, 0, start) =~ ~r/(?<![\w-])not\s+$/iu
  end

  defp negated?(_s, _start, _hedge, _number), do: false

  defp number_occurrences(occs, key_fun) do
    {out, _} =
      Enum.map_reduce(occs, %{}, fn o, seen ->
        n = Map.get(seen, key_fun.(o), 0) + 1
        {Map.put(o, :nth, n), Map.put(seen, key_fun.(o), n)}
      end)

    out
  end

  defp group(_s, {-1, 0}), do: nil
  defp group(s, {st, l}), do: binary_part(s, st, l)

  @doc "Parses a recognised number token: digits (with `,` grouping) or words to ninety-nine."
  def parse(nil), do: :unparseable

  def parse(number) do
    n = String.downcase(number)

    cond do
      n =~ ~r/^\d+(,\d{3})*$/ -> n |> String.replace(",", "") |> String.to_integer()
      n =~ ~r/^\d/ -> :unparseable
      true -> words(n)
    end
  end

  @word_values ~w(zero one two three four five six seven eight nine ten eleven twelve
                  thirteen fourteen fifteen sixteen seventeen eighteen nineteen)
               |> Enum.zip(0..19)
               |> Kernel.++(
                 Enum.zip(
                   ~w(twenty thirty forty fifty sixty seventy eighty ninety),
                   [20, 30, 40, 50, 60, 70, 80, 90]
                 )
               )
               |> Map.new()

  defp words(n) do
    case String.split(n, ~r/[- ]/) do
      [w] ->
        Map.get(@word_values, w, :unparseable)

      [tens, unit] ->
        t = Map.get(@word_values, tens)
        u = Map.get(@word_values, unit)

        if is_integer(t) and t >= 20 and rem(t, 10) == 0 and is_integer(u) and u in 1..9,
          do: t + u,
          else: :unparseable
    end
  end

  @doc """
  The sentence around a byte span: from just after the last `.`/`!`/`?` +
  whitespace before it, to the next such terminator after it.
  """
  def sentence(s, start, len) do
    stop = start + len
    before = binary_part(s, 0, start)
    rest = binary_part(s, stop, byte_size(s) - stop)

    from =
      case boundaries(before) do
        [] -> 0
        idx -> idx |> List.last() |> elem(1)
      end

    to =
      case boundaries(rest <> " ") do
        [] -> byte_size(rest)
        [{st, _} | _] -> min(st + 1, byte_size(rest))
      end

    binary_part(s, from, stop - from) <> binary_part(rest, 0, to)
  end

  # Sentence boundaries as {terminator_offset, next_sentence_start}. A full stop
  # that ends `i.e.`, `e.g.`, `cf.`, `vs.` or `etc.` is not one: splitting there
  # would cut an anchor off from the figure it dates.
  @abbreviations ~w(i.e. e.g. cf. vs. etc.)
  defp boundaries(text) do
    ~r/[.!?]\s+/u
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{st, l}] -> {st, st + l} end)
    |> Enum.reject(fn {st, _} ->
      head = binary_part(text, 0, st + 1)
      Enum.any?(@abbreviations, &String.ends_with?(head, &1))
    end)
  end

  @doc "Every backticked snake_case token in `doc`'s prose leaves, as `%{file, path, token, nth}`."
  def references(doc, file) do
    doc
    |> leaves([])
    |> Enum.flat_map(fn {path, s, _record} ->
      @reference
      |> Regex.scan(s, capture: :all_but_first)
      |> Enum.map(fn [t] -> %{file: file, path: path, token: t} end)
      |> number_occurrences(& &1.token)
    end)
  end

  # --- leaves, addressed by RECORD IDENTITY rather than by index -------------
  #
  # A per-record path keyed on `[12]` would move every later occurrence when one
  # edge is inserted, and the pending set would then read as 800 new figures. So
  # a list element that carries `key`, `id`, or any of member/claim/tag/module/
  # ticket/slice/definition is addressed by those; a collision falls back to an
  # ordinal suffix, and an element with none of them to its index.

  @doc false
  def leaves(doc, prefix), do: leaves(doc, prefix, doc)

  # The third element is the nearest enclosing MAP — the record a leaf belongs
  # to — which is what an `enumerated` entry's relative list path is read from.
  defp leaves(doc, prefix, _record) when is_map(doc) do
    doc
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.flat_map(fn {k, v} -> leaves(v, prefix ++ [k], doc) end)
  end

  defp leaves(list, prefix, record) when is_list(list) do
    list
    |> Enum.zip(record_ids(list))
    |> Enum.flat_map(fn {v, id} -> leaves(v, prefix ++ [id], record) end)
  end

  defp leaves(s, prefix, record) when is_binary(s), do: [{render(prefix), s, record}]
  defp leaves(_, _, _), do: []

  @doc """
  Rebuilds `doc` with `fun.(path, string)` applied to every prose leaf, the path
  rendered exactly as `scan/2` renders it. This is how a control plants a defect
  at an occurrence the scan reported, without re-deriving the addressing.
  """
  def map_leaves(doc, fun), do: map_leaves(doc, [], fun)

  defp map_leaves(doc, prefix, fun) when is_map(doc),
    do: Map.new(doc, fn {k, v} -> {k, map_leaves(v, prefix ++ [k], fun)} end)

  defp map_leaves(list, prefix, fun) when is_list(list) do
    list
    |> Enum.zip(record_ids(list))
    |> Enum.map(fn {v, id} -> map_leaves(v, prefix ++ [id], fun) end)
  end

  defp map_leaves(s, prefix, fun) when is_binary(s), do: fun.(render(prefix), s)
  defp map_leaves(other, _prefix, _fun), do: other

  @identity_fields ~w(member claim tag module ticket slice definition)

  defp record_ids(list) do
    {ids, _} =
      list
      |> Enum.with_index()
      |> Enum.map(fn {v, i} -> identity(v) || "##{i}" end)
      |> Enum.map_reduce(%{}, fn id, seen ->
        n = Map.get(seen, id, 0) + 1
        {{:rec, if(n == 1, do: id, else: "#{id}##{n}")}, Map.put(seen, id, n)}
      end)

    ids
  end

  defp identity(%{"key" => k}) when is_binary(k), do: k
  defp identity(%{"id" => k}) when is_binary(k), do: k

  defp identity(m) when is_map(m) do
    case for(f <- @identity_fields, v = identity_part(m[f]), is_binary(v), do: v) do
      [] -> nil
      parts -> Enum.join(parts, " | ")
    end
  end

  defp identity(_), do: nil

  # An edge's `member` is a map; its `register_key` is the member's identity.
  defp identity_part(%{"register_key" => k}) when is_binary(k), do: k
  defp identity_part(v), do: v

  defp render(prefix) do
    prefix
    |> Enum.map_join("", fn
      {:rec, id} -> "[" <> id <> "]"
      k -> "." <> k
    end)
    |> String.trim_leading(".")
  end

  # --- loading ---------------------------------------------------------------

  @doc """
  Reads everything the audit needs from `root` (default: the working directory).
  Options: `:universe`, `:ledger` (paths relative to root), `:baseline_fun`
  (`file -> {:ok, binary} | {:error, reason}`; default `git show <baseline>:<file>`).
  """
  def load(opts \\ []) do
    root = Keyword.get(opts, :root, ".")
    registry = root |> Path.join(Keyword.get(opts, :universe, @universe_path)) |> read_json()
    ledger = root |> Path.join(Keyword.get(opts, :ledger, @ledger_path)) |> read_json()
    walk = walk(root)

    registered =
      case registry do
        {:ok, %{"files" => files}} when is_map(files) -> files
        _ -> %{}
      end

    docs =
      (walk ++ Map.keys(registered))
      |> Enum.uniq()
      |> Map.new(fn f -> {f, root |> Path.join(f) |> read_json()} end)

    baseline = with {:ok, l} <- ledger, do: l["baseline"]

    baseline_fun =
      Keyword.get(opts, :baseline_fun, fn file -> git_show(root, baseline, file) end)

    %{
      registry: registry,
      ledger: ledger,
      walk: walk,
      docs: docs,
      code_words: code_words(root),
      baseline_fun: baseline_fun
    }
  end

  # The CODE half of the cross-reference universe: every identifier-shaped word
  # in the SDK, its tests and the conformance instruments. G31's OWN control and
  # unit file are excluded by name, because they must be able to spell a dead
  # token in order to plant it — and a token that resolved because the guard's
  # own control mentions it would be the vacuous universe the memory calls
  # "derived from the set".
  @code_globs [
    "lib/**/*.ex",
    "conformance/lib/**/*.ex",
    "conformance/*.{ex,exs}",
    "conformance/controls/*.exs",
    "test/**/*.{ex,exs}"
  ]
  @code_excluded [
    "conformance/controls/input_figures_controls.exs",
    "test/conformance/input_figures_test.exs"
  ]

  @doc false
  def code_words(root) do
    @code_globs
    |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
    |> Enum.reject(fn f -> Enum.any?(@code_excluded, &String.ends_with?(f, &1)) end)
    |> Enum.reduce(MapSet.new(), fn f, acc ->
      ~r/[A-Za-z0-9_]+/
      |> Regex.scan(File.read!(f))
      |> List.flatten()
      |> MapSet.new()
      |> MapSet.union(acc)
    end)
  end

  defp read_json(path) do
    with {:ok, bin} <- File.read(path),
         {:ok, doc} <- Jason.decode(bin) do
      {:ok, doc}
    else
      {:error, %Jason.DecodeError{} = e} -> {:error, "not JSON: " <> Exception.message(e)}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @doc "The derived walk: every file under the roots, relative to `root`, sorted."
  def walk(root) do
    @walk_roots
    |> Enum.flat_map(fn {dir, glob} ->
      root
      |> Path.join(dir)
      |> Path.join(glob)
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&relative(&1, root))
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp relative(path, "."), do: path

  defp relative(path, root) do
    prefix = String.trim_trailing(root, "/") <> "/"
    if String.starts_with?(path, prefix), do: String.replace_prefix(path, prefix, ""), else: path
  end

  defp git_show(_root, nil, _file), do: {:error, "the ledger names no baseline commit"}

  defp git_show(root, rev, file) do
    case System.cmd("git", ["show", "#{rev}:#{file}"], cd: root, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, String.trim(out)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # --- the audit ---------------------------------------------------------------

  @doc """
  Runs the guard over `inputs` (from `load/1`, possibly mutated by a control).
  Returns `%{report: map, defects: [defect]}`; a defect is
  `%{kind, file, path, detail}`. Pure apart from `baseline_fun`.
  """
  def audit(inputs) do
    {universe, universe_defects} = universe(inputs)

    case inputs.ledger do
      {:ok, ledger} when is_map(ledger) ->
        audit_ledger(inputs, ledger, universe, universe_defects)

      other ->
        defect = d(:unreadable, @ledger_path, "", "the ledger cannot be read: #{inspect(other)}")
        %{report: %{"guard" => @guard, "visited" => 0}, defects: universe_defects ++ [defect]}
    end
  end

  defp audit_ledger(inputs, ledger, universe, universe_defects) do
    hand = for {f, "hand_authored"} <- universe, {:ok, doc} <- [inputs.docs[f]], do: {f, doc}
    others = for {f, c} <- universe, c != "hand_authored", {:ok, doc} <- [inputs.docs[f]], do: doc

    occurrences = Enum.flat_map(hand, fn {f, doc} -> scan(doc, f) end)
    entries = List.wrap(ledger["entries"])
    pending = List.wrap(ledger["pending"])
    quantities = ledger["quantities"] || %{}

    {entry_map, dup_defects} = index_entries(entries, pending)
    measured = measure(quantities, inputs.docs)
    docs = Map.new(hand)

    {classified, entry_defects} =
      occurrences
      |> Enum.map(fn o -> classify(o, entry_map[key(o)], measured, docs) end)
      |> Enum.unzip()

    {refs, ref_defects} =
      references_audit(
        hand,
        others,
        Map.get(inputs, :code_words, MapSet.new()),
        ledger["reference_exemptions"]
      )

    counts = Enum.frequencies(classified)
    report = report(universe, length(hand), length(occurrences), counts, refs, quantities)

    defects =
      universe_defects ++
        dup_defects ++
        List.flatten(entry_defects) ++
        ledger_defects(occurrences, entries, pending, ledger, measured) ++
        pending_defects(pending, ledger, baseline_scans(inputs, pending)) ++
        ref_defects ++ reach_defects(report, counts)

    %{report: report, defects: defects}
  end

  defp report(universe, files, visited, counts, refs, quantities) do
    classes = ~w(measured enumerated historical not_a_count pending unparseable refused)

    Map.merge(Map.new(classes, &{&1, Map.get(counts, &1, 0)}), %{
      "guard" => @guard,
      "universe" => universe |> Enum.frequencies_by(&elem(&1, 1)) |> Map.new(),
      "files_scanned" => files,
      "visited" => visited,
      "references_visited" => refs.visited,
      "references_in_data" => refs.data,
      "references_in_code" => refs.code,
      "references_exempt" => refs.exempt,
      "quantities" => map_size(quantities)
    })
  end

  # Defects of the LEDGER rather than of an occurrence: an entry or pending row
  # whose phrase no longer occurs, a measured entry naming no quantity, a
  # not_a_count citing no stated reason, and a quantity that will not evaluate.
  defp ledger_defects(occurrences, entries, pending, ledger, measured) do
    present = MapSet.new(occurrences, &key/1)
    quantities = ledger["quantities"] || %{}
    reasons = ledger["reasons"] || %{}

    stale =
      for {rows, kind} <- [{entries, :stale_entry}, {pending, :stale_pending}],
          e <- rows,
          not MapSet.member?(present, entry_key(e)),
          do:
            d(
              kind,
              e["file"],
              e["path"],
              "#{inspect(e["phrase"])} (nth #{e["nth"]}) no longer occurs"
            )

    unknown =
      for %{"class" => "measured"} = e <- entries,
          not Map.has_key?(quantities, e["quantity"]),
          do:
            d(
              :unknown_quantity,
              e["file"],
              e["path"],
              "no quantity named #{inspect(e["quantity"])}"
            )

    open_codes =
      for {code, _} <- reasons,
          code not in @reasons,
          do:
            d(
              :reason_outside_closed_set,
              @ledger_path,
              "reasons.#{code}",
              "#{inspect(code)} is not one of the guard's closed set #{Enum.join(@reasons, " ")}"
            )

    open_citations =
      for %{"class" => "not_a_count"} = e <- entries,
          e["reason"] not in @reasons,
          do:
            d(
              :reason_outside_closed_set,
              e["file"],
              e["path"],
              "not_a_count cites #{inspect(e["reason"])}, outside the guard's closed set #{Enum.join(@reasons, " ")}"
            )

    unreasoned =
      for %{"class" => "not_a_count"} = e <- entries,
          not stated?(reasons[e["reason"]]),
          do:
            d(
              :bad_entry,
              e["file"],
              e["path"],
              "not_a_count cites reason #{inspect(e["reason"])}, which the ledger does not state"
            )

    broken =
      for {name, {:error, why}} <- measured,
          do: d(:quantity_error, @ledger_path, "quantities.#{name}", why)

    stale ++ unknown ++ open_codes ++ open_citations ++ unreasoned ++ broken
  end

  defp stated?(text), do: is_binary(text) and text != ""

  defp reach_defects(report, counts) do
    sum = counts |> Map.values() |> Enum.sum()

    cond do
      report["visited"] == 0 ->
        [
          d(
            :reach,
            "",
            "",
            "the scan visited ZERO figures — a reader that sees nothing cannot pass"
          )
        ]

      sum != report["visited"] ->
        [d(:reach, "", "", "the classes sum to #{sum}, not to the #{report["visited"]} visited")]

      report["references_visited"] == 0 ->
        [d(:reach, "", "", "the cross-reference scan visited ZERO tokens")]

      true ->
        []
    end
  end

  defp key(o), do: {o.file, o.path, o.phrase, o.nth}
  defp entry_key(e), do: {e["file"], e["path"], e["phrase"], e["nth"]}

  defp index_entries(entries, pending) do
    tagged =
      Enum.map(entries, &{entry_key(&1), &1}) ++
        Enum.map(pending, &{entry_key(&1), Map.put(&1, "class", "pending")})

    dups =
      tagged
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.filter(fn {_k, v} -> length(v) > 1 end)
      |> Enum.map(fn {{f, p, ph, n}, v} ->
        d(:duplicate_entry, f, p, "#{inspect(ph)} (nth #{n}) is adjudicated #{length(v)} times")
      end)

    {Map.new(tagged), dups}
  end

  # One occurrence -> {class_for_the_report, [defect]}
  defp classify(%{value: :unparseable} = o, entry, _m, _docs) do
    case entry do
      %{"class" => "pending"} ->
        {"pending", []}

      %{"class" => "not_a_count", "reason" => r} when is_binary(r) and r != "" ->
        {"not_a_count", []}

      _ ->
        {"unparseable",
         [d(:unparseable, o.file, o.path, "#{inspect(o.phrase)} does not parse as a figure")]}
    end
  end

  defp classify(o, nil, _m, _docs) do
    {"refused",
     [
       d(
         :unledgered,
         o.file,
         o.path,
         "#{inspect(o.phrase)} (nth #{o.nth}) is asserted and adjudicated nowhere — in: #{inspect(o.sentence)}"
       )
     ]}
  end

  defp classify(_o, %{"class" => "pending"}, _m, _docs), do: {"pending", []}

  defp classify(o, %{"class" => "measured", "quantity" => q}, measured, _docs) do
    case measured[q] do
      {:ok, v} when v == o.value ->
        {"measured", []}

      {:ok, v} ->
        {"refused",
         [
           d(
             :mismatch,
             o.file,
             o.path,
             "#{inspect(o.phrase)} says #{o.value}; `#{q}` measures #{v} at this tip — in: #{inspect(o.sentence)}"
           )
         ]}

      _ ->
        {"refused", []}
    end
  end

  defp classify(o, %{"class" => "enumerated", "list" => path}, _m, docs) do
    list =
      case path do
        "/" <> absolute -> get_path(docs[o.file], absolute)
        relative -> get_path(o.record, relative)
      end

    case list do
      l when is_list(l) and length(l) == o.value ->
        {"enumerated", []}

      l when is_list(l) ->
        {"refused",
         [
           d(
             :mismatch,
             o.file,
             o.path,
             "#{inspect(o.phrase)} says #{o.value}; `#{path}` enumerates #{length(l)}"
           )
         ]}

      _ ->
        {"refused",
         [d(:bad_entry, o.file, o.path, "enumerated list `#{path}` is not a list in this file")]}
    end
  end

  defp classify(o, %{"class" => "historical", "as_of" => a}, _m, _docs) when is_binary(a) do
    cond do
      not Regex.match?(@anchor, a) ->
        {"refused",
         [
           d(
             :bad_entry,
             o.file,
             o.path,
             "as_of #{inspect(a)} is not a ticket key, slice id or sha"
           )
         ]}

      not Regex.match?(~r/(?<![\w-])#{Regex.escape(a)}(?![\w-])/u, o.sentence) ->
        {"refused",
         [
           d(
             :unanchored_historical,
             o.file,
             o.path,
             "#{inspect(o.phrase)} is filed historical as of #{a}, and #{a} is not in its sentence: #{inspect(o.sentence)}"
           )
         ]}

      true ->
        {"historical", []}
    end
  end

  defp classify(_o, %{"class" => "not_a_count", "reason" => r}, _m, _docs)
       when is_binary(r) and byte_size(r) > 0,
       do: {"not_a_count", []}

  defp classify(o, entry, _m, _docs) do
    {"refused",
     [
       d(
         :bad_entry,
         o.file,
         o.path,
         "entry is not one of #{inspect(@entry_classes)} with its argument: #{inspect(entry)}"
       )
     ]}
  end

  @doc """
  The occurrence-key sets of each pending file at the baseline commit. A control
  that runs the audit many times computes this once and passes it in as
  `inputs.baseline_scans`; the audit computes it itself otherwise.
  """
  def baseline_scans(inputs, pending \\ nil) do
    case Map.get(inputs, :baseline_scans) do
      nil ->
        pending =
          pending ||
            case inputs.ledger do
              {:ok, l} -> List.wrap(l["pending"])
              _ -> []
            end

        pending
        |> Enum.map(& &1["file"])
        |> Enum.uniq()
        |> Map.new(&{&1, baseline_scan(&1, inputs.baseline_fun)})

      cached ->
        cached
    end
  end

  defp pending_defects(pending, ledger, baselines) do
    scope = ledger["pending_admissible"] || []

    Enum.flat_map(pending, fn e ->
      baseline_defects(e, baselines[e["file"]], ledger["baseline"]) ++ scope_defects(e, scope)
    end)
  end

  # The occurrence keys of `file` AS IT WAS at the baseline commit, read from git
  # rather than from the working tree — which is what stops a figure written
  # after the guard from being parked in pending.
  defp baseline_scan(file, baseline_fun) do
    with {:ok, bin} <- baseline_fun.(file),
         {:ok, doc} <- Jason.decode(bin) do
      {:ok, doc |> scan(file) |> MapSet.new(&key/1)}
    else
      {:error, why} when is_binary(why) -> {:error, why}
      {:error, why} -> {:error, inspect(why)}
    end
  end

  defp baseline_defects(e, {:error, why}, _baseline) do
    [
      d(
        :pending_unverifiable,
        e["file"],
        e["path"],
        "the baseline copy cannot be read, so a pending entry cannot be shown to predate this guard: #{why}"
      )
    ]
  end

  defp baseline_defects(e, {:ok, set}, baseline) do
    if MapSet.member?(set, entry_key(e)) do
      []
    else
      [
        d(
          :pending_not_in_baseline,
          e["file"],
          e["path"],
          "#{inspect(e["phrase"])} did not occur at #{baseline}; a figure first written after the guard may not be pending"
        )
      ]
    end
  end

  defp scope_defects(e, scope) do
    admissible =
      Enum.any?(scope, fn s ->
        s["file"] == e["file"] and
          Enum.any?(s["path_prefixes"] || [], &String.starts_with?(e["path"] || "", &1))
      end)

    if admissible do
      []
    else
      [
        d(
          :pending_outside_scope,
          e["file"],
          e["path"],
          "#{inspect(e["phrase"])} is outside `pending_admissible` — it must be adjudicated, not deferred"
        )
      ]
    end
  end

  # --- the universe ------------------------------------------------------------

  defp universe(inputs) do
    case inputs.registry do
      {:ok, %{"files" => files}} when is_map(files) ->
        walked = MapSet.new(inputs.walk)
        listed = files |> Map.keys() |> MapSet.new()

        unregistered =
          for f <- MapSet.difference(walked, listed) |> Enum.sort(),
              do:
                d(
                  :unregistered_file,
                  f,
                  "",
                  "under a walked root and absent from #{@universe_path} — classify it"
                )

        absent =
          for f <- MapSet.difference(listed, walked) |> Enum.sort(),
              do: d(:absent_file, f, "", "registered in #{@universe_path} and not on disk")

        bad_class =
          for {f, c} <- files,
              c not in @classes,
              do: d(:bad_entry, f, "", "class #{inspect(c)} is not one of #{inspect(@classes)}")

        markers =
          for {f, c} <- files,
              MapSet.member?(walked, f),
              defect <- marker_defects(f, c, inputs.docs[f]),
              do: defect

        present = for {f, c} <- files, MapSet.member?(walked, f), do: {f, c}
        {Enum.sort(present), unregistered ++ absent ++ bad_class ++ markers}

      other ->
        {[],
         [
           d(
             :unreadable,
             @universe_path,
             "",
             "the universe registry cannot be read: #{inspect(other)}"
           )
         ]}
    end
  end

  defp marker_defects(f, class, doc) do
    case {class, doc} do
      {"hand_authored", {:error, why}} ->
        [d(:unreadable, f, "", "registered hand_authored and cannot be scanned: #{why}")]

      {_, {:ok, %{"authored_by_hand" => true}}} when class != "hand_authored" ->
        [
          d(
            :marker_disagreement,
            f,
            "",
            "carries authored_by_hand: true and is registered #{class}"
          )
        ]

      {_, {:ok, %{"generated_by" => _}}} when class != "generated" ->
        [d(:marker_disagreement, f, "", "carries generated_by and is registered #{class}")]

      _ ->
        []
    end
  end

  # --- shape 5: cross-references ------------------------------------------------

  defp references_audit(hand, others, code_words, exemptions) do
    data =
      (Enum.map(hand, &elem(&1, 1)) ++ others)
      |> Enum.reduce(MapSet.new(), &names/2)

    exempt = Map.new(List.wrap(exemptions), &{&1["token"], &1})
    refs = Enum.flat_map(hand, fn {f, doc} -> references(doc, f) end)
    by = Enum.group_by(refs, &resolution(&1.token, data, code_words, exempt))

    unresolved =
      for r <- Map.get(by, :unresolved, []) do
        d(
          :unresolved_reference,
          r.file,
          r.path,
          "`#{r.token}` names no key or identifier value in the universe and no identifier in the repository's sources"
        )
      end

    used = by |> Map.get(:exempt, []) |> MapSet.new(& &1.token)
    exemption_defects = Enum.flat_map(exempt, &exemption_defects(&1, used))

    counts = %{
      visited: length(refs),
      data: length(Map.get(by, :data, [])),
      code: length(Map.get(by, :code, [])),
      exempt: length(Map.get(by, :exempt, []))
    }

    {counts, unresolved ++ exemption_defects}
  end

  defp resolution(token, data, code_words, exempt) do
    cond do
      MapSet.member?(data, token) -> :data
      MapSet.member?(code_words, token) -> :code
      Map.has_key?(exempt, token) -> :exempt
      true -> :unresolved
    end
  end

  @exemption_classes ~w(external retired not_a_field_name)

  defp exemption_defects({t, e}, used) do
    cond do
      e["class"] not in @exemption_classes or not stated?(e["reason"]) ->
        [
          d(
            :bad_entry,
            @ledger_path,
            "reference_exemptions",
            "`#{t}` needs a class (#{Enum.join(@exemption_classes, ", ")}) and a reason"
          )
        ]

      not MapSet.member?(used, t) ->
        [
          d(
            :stale_exemption,
            @ledger_path,
            "reference_exemptions",
            "`#{t}` is exempted and no longer needs to be — it resolves, or no longer occurs"
          )
        ]

      true ->
        []
    end
  end

  defp names(m, acc) when is_map(m),
    do: Enum.reduce(m, acc, fn {k, v}, a -> names(v, MapSet.put(a, k)) end)

  defp names(l, acc) when is_list(l), do: Enum.reduce(l, acc, &names/2)

  defp names(s, acc) when is_binary(s),
    do: if(String.contains?(s, " "), do: acc, else: MapSet.put(acc, s))

  defp names(_, acc), do: acc

  # --- the measured-quantity registry -------------------------------------------
  #
  # A quantity is a small query over the files at the tip — never a stored
  # number. `count` counts records at a path (`[]` flattens a list; a nested
  # flatten merges the parent record's fields under each child's own), filtered by
  # `where` and optionally reduced to `distinct` values of one field; `value`
  # reads an integer (or a list's length) at a path; `sum` adds quantities.

  @doc false
  def measure(quantities, docs) do
    Map.new(quantities, fn {name, spec} ->
      {name,
       try do
         eval(spec["query"] || spec, docs)
       rescue
         e -> {:error, Exception.message(e)}
       end}
    end)
  end

  defp eval(%{"count" => c}, docs) do
    files = List.wrap(c["in"])

    records =
      Enum.flat_map(files, fn f ->
        case docs[f] do
          {:ok, doc} -> records(doc, String.split(c["at"] || "", ".", trim: true), %{})
          _ -> throw({:missing, f})
        end
      end)
      |> Enum.filter(&all?(&1, prepare(c["where"] || [], docs), docs))

    values = fn field -> Enum.map(records, &transform(get_path(&1, field), c["transform"])) end

    cond do
      c["distinct"] ->
        {:ok, c["distinct"] |> values.() |> Enum.uniq() |> length()}

      c["max_group"] ->
        {:ok,
         c["max_group"]
         |> values.()
         |> Enum.frequencies()
         |> Map.values()
         |> Enum.max(fn -> 0 end)}

      c["pick"] ->
        pick(records, c["pick"])

      true ->
        {:ok, length(records)}
    end
  catch
    {:missing, f} -> {:error, "#{f} is not a readable file"}
  end

  defp eval(%{"value" => %{"in" => f, "path" => p}}, docs) do
    value_at(docs, f, p)
  end

  defp eval(%{"sum" => qs}, docs) do
    Enum.reduce_while(qs, {:ok, 0}, fn q, {:ok, acc} ->
      case eval(q, docs) do
        {:ok, n} -> {:cont, {:ok, acc + n}}
        e -> {:halt, e}
      end
    end)
  end

  defp eval(%{"difference" => [a, b]}, docs) do
    with {:ok, x} <- eval(a, docs), {:ok, y} <- eval(b, docs), do: {:ok, x - y}
  end

  defp eval(other, _docs), do: {:error, "not a query: #{inspect(other)}"}

  defp value_at(docs, f, p) do
    case docs[f] do
      {:ok, doc} -> figure(get_path(doc, p), "#{f} #{p}")
      _ -> {:error, "#{f} is not a readable file"}
    end
  end

  # `pick` reads a figure off the ONE record the `where` selects; zero or two
  # matches is an error rather than a guess.
  defp pick([rec], path), do: figure(get_path(rec, path), path)
  defp pick(recs, path), do: {:error, "pick #{path}: #{length(recs)} records matched, not 1"}

  defp figure(n, _where) when is_integer(n), do: {:ok, n}
  defp figure(l, _where) when is_list(l), do: {:ok, length(l)}
  defp figure(m, _where) when is_map(m), do: {:ok, map_size(m)}
  defp figure(other, where), do: {:error, "#{where} is #{inspect(other)}, not a figure"}

  # `module` reads an ET-CC key's module: everything before the first `/`.
  defp transform(v, "module") when is_binary(v), do: v |> String.split("/", parts: 2) |> hd()
  defp transform(v, _), do: v

  defp records(doc, [], _parent), do: List.wrap(doc)

  defp records(doc, [seg | rest], parent) do
    {name, flatten?} =
      if String.ends_with?(seg, "[]"),
        do: {String.trim_trailing(seg, "[]"), true},
        else: {seg, false}

    here = if name == "", do: doc, else: doc[name]

    cond do
      flatten? and is_list(here) -> Enum.flat_map(here, &flattened(&1, rest, parent))
      is_map(here) -> records(here, rest, parent)
      true -> throw({:missing, "path #{seg}"})
    end
  end

  # A flattened child carries its parent record's fields under its own, so a
  # nested row (a manifest check inside its scenario) can be filtered by either.
  defp flattened(item, rest, parent) when is_map(item) do
    item = Map.merge(parent, item)
    if rest == [], do: [item], else: records(item, rest, item)
  end

  defp flattened(item, [], _parent), do: [item]
  defp flattened(item, rest, _parent), do: records(item, rest, %{})

  defp all?(rec, conds, docs), do: Enum.all?(conds, &holds?(rec, &1, docs))

  defp holds?(rec, %{"not" => c}, docs), do: not holds?(rec, c, docs)
  defp holds?(rec, %{"any_of" => cs}, docs), do: Enum.any?(cs, &holds?(rec, &1, docs))

  defp holds?(rec, %{"text_matches" => re}, _docs),
    do: Regex.match?(Regex.compile!(re, "u"), Jason.encode!(rec))

  @operators ~w(eq ne in in_set is_null starts_with matches empty every some)

  defp holds?(rec, %{"field" => f} = c, docs) do
    v = rec |> get_path(f) |> transform(c["transform"])

    case Enum.find(@operators, &Map.has_key?(c, &1)) do
      nil -> raise "condition #{inspect(c)} names no operator"
      op -> test(op, v, c[op], docs)
    end
  end

  defp test("eq", v, arg, _docs), do: v == arg
  defp test("ne", v, arg, _docs), do: v != arg
  defp test("in", v, arg, _docs), do: v in arg
  defp test("in_set", v, %MapSet{} = set, _docs), do: MapSet.member?(set, v)
  defp test("in_set", v, arg, docs), do: v in value_set(arg, docs)
  defp test("is_null", v, arg, _docs), do: is_nil(v) == arg
  defp test("starts_with", v, arg, _docs), do: is_binary(v) and String.starts_with?(v, arg)

  defp test("matches", v, arg, _docs),
    do: is_binary(v) and Regex.match?(Regex.compile!(arg, "u"), v)

  defp test("empty", v, arg, _docs), do: v in [nil, [], %{}, ""] == arg

  defp test("every", v, arg, docs),
    do: is_list(v) and v != [] and Enum.all?(v, &all?(&1, arg, docs))

  defp test("some", v, arg, docs), do: is_list(v) and Enum.any?(v, &all?(&1, arg, docs))

  # An `in_set` join's inner query is evaluated ONCE per quantity, not once per
  # record it filters — the difference between 0.5 s and a minute per audit.
  defp prepare(conds, docs) when is_list(conds), do: Enum.map(conds, &prepare(&1, docs))

  defp prepare(%{"in_set" => %{"count" => _} = q} = c, docs),
    do: %{c | "in_set" => value_set(q, docs)}

  defp prepare(%{"not" => c} = n, docs), do: %{n | "not" => prepare(c, docs)}
  defp prepare(%{"any_of" => cs} = a, docs), do: %{a | "any_of" => prepare(cs, docs)}
  defp prepare(c, _docs), do: c

  # The distinct values a `count` query's `distinct` field takes — the SET an
  # `in_set` condition tests membership of, so a cross-file join is a query too.
  defp value_set(%{"count" => c} = spec, docs) do
    field = c["distinct"] || raise "in_set needs a `distinct` query: #{inspect(spec)}"

    List.wrap(c["in"])
    |> Enum.flat_map(fn f ->
      {:ok, doc} = docs[f]
      records(doc, String.split(c["at"] || "", ".", trim: true), %{})
    end)
    |> Enum.filter(&all?(&1, prepare(c["where"] || [], docs), docs))
    |> MapSet.new(&transform(get_path(&1, field), c["transform"]))
  end

  @doc false
  def get_path({:ok, doc}, path), do: get_path(doc, path)

  def get_path(doc, path) when is_binary(path) do
    path
    |> String.split(".", trim: true)
    |> Enum.reduce_while(doc, fn seg, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, seg) -> {:cont, acc[seg]}
        is_list(acc) and seg =~ ~r/^\d+$/ -> {:cont, Enum.at(acc, String.to_integer(seg))}
        true -> {:halt, nil}
      end
    end)
  end

  def get_path(_, _), do: nil

  defp d(kind, file, path, detail), do: %{kind: kind, file: file, path: path, detail: detail}

  @doc "One line per defect, each naming the guard, the kind, the file and the field."
  def format_defect(%{kind: k, file: f, path: p, detail: det}),
    do: "#{@guard} #{k} — #{f}#{if p != "", do: " @ " <> p, else: ""}: #{det}"
end

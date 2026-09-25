defmodule MCP.Conformance.Adjudications do
  @moduledoc """
  **Guard 32**: every edge a bucket view projects is **adjudicated exactly
  once**, by a hand-authored adjudication record whose rows **equal** the view
  in both directions. Each row's disposition comes from a closed set, and each
  repository citation it makes still has the bytes it quotes at the address it
  gives.

  Established by MES-126 (D4a) for the D group. MES-127, 128, 129 and 130 reuse
  it. A new disposition is a reviewed change to this file: MES-127 (D4b) added
  `extend_test` and `accept_bound`, and the `bound_missing` refusal with them
  (PM ratification, MES-127 comment 29430, Q1 and Q2). MES-128 (D2b) added
  `extend_to_match` and `build_test`, and the `build_level_missing` refusal with
  them (PM ratification, MES-128 comment 29444, Q1). MES-129 (D2a-i) added
  `blocked_on_sdk_gap`, and the `sdk_gap_missing` refusal with it (PM
  ratification, MES-129 comment 29460, Q1).

  ## The dispositions

    * `fix_sdk`, `fix_conformance_adapter`, `keep_design_publish_bound`,
      `po_decision_required`, `suite_defect_upstream`: MES-126.
    * `extend_test`: the unit already drives the seam at which the omitted axis
      can be observed. The remedy is an added assertion on that axis in the same
      unit, not a new test. It is recorded by D and performed by remediation
      (ruling 3). Where the SDK currently fails the axis, the assertion lands in
      the same change as the named root cause's fix, so `main` never carries a
      red test.
    * `accept_bound`: the unit's seam cannot observe the omitted axis, so the
      edge's coverage is bounded to the axes the unit asserts. The row states
      that bound in `bound`, as one consumer-readable sentence: a non-empty
      string on a single line, or the row is refused (`bound_missing`). The
      guard holds the shape. Whether the sentence is honest is the reviewer's
      check.
    * `extend_to_match`: for a check with NO edge (bucket 2). An existing ET-CC
      unit already drives the seam and sends the check's stimulus, but asserts
      nothing the check requires. The remedy is an added assertion, or added
      loop cases, in that unit, which would give the crosswalk an edge. The row
      cites the unit in `extend_target`. It differs from `extend_test`, which
      presumes an existing edge with an omitted axis.
    * `build_test`: for a check with no edge that no existing unit drives at any
      level. The remedy is a new ET-CC unit.
    * `blocked_on_sdk_gap`: the check's behaviour is not implemented by the SDK,
      or it passes only through a path an SDK gap creates. So no ET-CC unit can
      honestly be built or extended until a named SDK change lands. The row's
      `build_level` and `remedy` name the unit to build once the gap is fixed,
      and that unit lands in the same change as the fix, so `main` never
      carries a red test (the `extend_test` precedent). The row also carries
      `sdk_gap`: the owning ticket (`owner`), one line naming the record that
      ticket carries (`owner_record`), and a repository citation of the gap in
      this tree (`record`). Otherwise the row is refused (`sdk_gap_missing`).
      Shape only: whether the owning ticket really carries the record is the
      reviewer's check.

  An `extend_to_match`, `build_test` or `blocked_on_sdk_gap` row carries `build_level` (one of
  `pure_unit`, `mock_transport`, `plug`, `live_http`) and a one-line `remedy`,
  and an `extend_to_match` row also carries an `extend_target` map. Otherwise
  the row is refused (`build_level_missing`). Like `bound_missing`, this checks
  SHAPE only: whether the level is the cheapest one that works, and whether the
  remedy would really give the check an edge, is the reviewer's check. The
  `extend_target` citation's bytes are held by `citation_drift` like any other.

  ## The record, and the unit it adjudicates

  A record is `docs/conformance/adjudications/*.json`, **one file per
  ticket**, and it carries `schema: "adjudication-record/1"` and
  `authored_by_hand: true`. It holds **sections**. A section is bound to ONE
  view by the view's repository path, and a view may have several sections bound
  to it, even from different tickets. That is what lets bucket 2a be split
  between MES-129 and MES-130, and lets D4a adjudicate the escalated view in the
  same record as bucket 4a (PM ratification, MES-126 comment 29406 (i)).

  A section's `closure` is `closed` or `open`. Per view, the guard takes the
  union of the rows of every section bound to it:

    * **phantom**: a row whose key the view does not project. Refused always.
    * **missing**: a view key that no row adjudicates. Refused when ANY section
      bound to the view is `closed`. When every bound section is `open`, a
      missing key is allowed, which is the state of a split view before its
      closing ticket lands. An `open` section must name an `owner`.
    * **duplicate**: one key adjudicated twice, including across records.

  ## The key: the edge triple, derived by ONE function from both sides

  `key/1` is `[member, claim, tag]`. `member` is the member's `register_key`
  (a view row carries the member as a map, and a record row carries the string),
  and a component the row does not carry is `nil`. The same function is applied
  to the view's rows and to the record's rows, so the two sides cannot key
  differently. No shorter key works on the views the D group adjudicates,
  measured at `b1cd59e`. The member alone collides in `bucket-4b` (two members
  carry two rows each, differing by tag). `[member, tag]` still collides in
  `bucket-5a` and `bucket-5b`, where one member carries several rows on one
  check that differ only by claim. The mutation mode of
  `conformance/controls/adjudications_controls.exs` recompiles this guard with
  each shorter key and shows those real views refused. A view whose rows do not
  key uniquely under the triple is refused (`view_key_collision`) rather than
  adjudicated approximately. `bucket-0` is such a view at `b1cd59e`: its rows
  carry `token`, not `tag`, so they key alike.

  (MES-126's plan said the two T-CG1c rows of the escalated view share a
  `register_key`. They do not: each is its own test. The control plant that
  assumed they did found this out.)

  ## Echo: a regenerated view under an unchanged key is caught

  Each row copies its view row's `shape`, `verdicts`, `bucket`,
  `escalation_reason` and `escalation_cause` (whichever the view row carries)
  into `echo`. The guard requires `echo` to EQUAL that projection. So a view
  re-projected with a different verdict under the same edge refuses
  (`echo_drift`), rather than leaving an adjudication standing over a fact
  that has changed.

  **Echo is vacuous on bucket-2 views.** A bucket-2 (and bucket-1) view row
  carries only `leg` and `tag`, none of the echoed fields, so its echo is `{}`
  and `echo_drift` cannot fire there (CR K4 on MES-126). `leg` and `tag` are
  both inside the key, so there is nothing a view row could change under an
  unchanged key. What such a record can still hold is its PREMISE: D2b's rows
  cite each check's status at the accepted run as a repository citation, and
  gate 5 requires it to be SUCCESS. The hardening is MES-135's.

  ## Citations: an address AND the bytes at it (ruling 7)

  Anywhere in a row, a map carrying `file`, `lines` (`[from, to]`, 1-based,
  inclusive) and `bytes` is a **repository citation**. The guard reads that
  line window at the tip and requires it to EQUAL `bytes` once whitespace runs
  are squashed. The test is equality, not containment, so a quote cannot hide a
  stale window or a spliced one. A map carrying `harness_sha256`, `byte_span`
  and `bytes` is a **harness citation**. The harness build is not in this
  repository, so gate 5 cannot read it. Those citations are counted in the
  report and verified by the control's `harness` mode against the pinned build.
  That split is a stated residual, not a pass.

  ## What is refused

  `unreadable`, `bad_record`, `bad_section`, `unknown_view`,
  `view_key_collision`, `open_without_owner`, `bad_row`,
  `disposition_outside_set`, `bound_missing`, `build_level_missing`, `sdk_gap_missing`,
  `phantom`, `missing`,
  `duplicate`, `echo_drift`, `citation_drift`, and `reach`. Every refusal names the guard, the kind, the
  record file and the edge key.

  ## Reach, and what the guard reports over an empty directory

  The report states `records_visited`, `rows_visited`, `views_bound` and the
  citations verified. Over an EMPTY adjudications directory the guard reports
  `records_visited: 0, rows_visited: 0` and refuses nothing: no view is bound,
  so no view is owed an adjudication. That is the state before the first record,
  and it is why the walk root is pinned by gate 5
  (`test/conformance/adjudications_test.exs`): a narrowed walk that sees no
  record would otherwise pass silently. Once any record is visited, a run that
  visited zero rows is refused (`reach`).

  ## What it does NOT establish

    * That a disposition is RIGHT. The guard holds the record's shape against
      the view. The judgement is the author's, and the reviewer's to check.
    * That a view is owed a record. A view no section binds is not examined.
      Which views a ticket must close is the ticket's acceptance, not this
      guard's.
    * Harness bytes in gate 5 (see above).
  """

  @guard "G32"
  @walk_root "docs/conformance/adjudications"
  @walk_glob "*.json"
  @schema "adjudication-record/1"
  @view_schemas ~w(bucket-view/1 escalated-view/1)
  @closures ~w(closed open)

  # The dispositions are a CLOSED set here, in the guard, not in the data
  # (G31's @reasons precedent, PM ratification on MES-126 (ii)). Adding one is a
  # reviewed change to conformance/lib, proposed at the adding ticket's plan hop.
  @dispositions ~w(fix_sdk fix_conformance_adapter keep_design_publish_bound
                   po_decision_required suite_defect_upstream extend_test accept_bound
                   extend_to_match build_test blocked_on_sdk_gap)

  # The build levels an extend_to_match, build_test or blocked_on_sdk_gap row may
  # name (MES-128, 29444; MES-129, 29460).
  @build_levels ~w(pure_unit mock_transport plug live_http)
  @build_dispositions ~w(extend_to_match build_test blocked_on_sdk_gap)
  @ticket_key ~r/\A[A-Z][A-Z0-9]+-[0-9]+\z/

  @row_fields ~w(member claim tag echo et_test check root_cause if_conformance_fixed
                 disposition rationale)
  @escalated_fields ~w(whose_defect cause_slug)
  @whose ~w(ours suite)
  @slug_verdicts ~w(confirmed corrected)
  @echo_fields ~w(shape verdicts bucket escalation_reason escalation_cause)

  def guard, do: @guard
  def walk_root, do: {@walk_root, @walk_glob}
  def dispositions, do: @dispositions
  def build_levels, do: @build_levels
  def schema, do: @schema

  # --- the key -------------------------------------------------------------

  @doc """
  The edge triple `[member, claim, tag]`, the same function for a view row and a
  record row. `member` is a `register_key` string whether the row carries the
  member as a map (a view) or as a string (a record).
  """
  def key(row) when is_map(row), do: [member_key(row["member"]), row["claim"], row["tag"]]

  defp member_key(%{"register_key" => k}), do: k
  defp member_key(k) when is_binary(k), do: k
  defp member_key(_), do: nil

  @doc "The fields of a view row a record row must echo verbatim."
  def echo(view_row) when is_map(view_row), do: Map.take(view_row, @echo_fields)

  # --- loading --------------------------------------------------------------

  @doc """
  Reads the records under the walk root, every view a section binds, and a
  `source_fun` for repository citations. Options: `:root` (default `.`).
  """
  def load(opts \\ []) do
    root = Keyword.get(opts, :root, ".")
    walk = walk(root)
    records = Map.new(walk, &{&1, read_json(Path.join(root, &1))})

    views =
      records
      |> Enum.flat_map(fn
        {_, {:ok, %{"sections" => s}}} when is_list(s) -> Enum.map(s, &(is_map(&1) && &1["view"]))
        _ -> []
      end)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Map.new(&{&1, read_json(Path.join(root, &1))})

    %{walk: walk, records: records, views: views, source_fun: &read_source(root, &1)}
  end

  @doc "The derived walk: every `*.json` directly under the walk root, relative to `root`, sorted."
  def walk(root) do
    root
    |> Path.join(@walk_root)
    |> Path.join(@walk_glob)
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.join(@walk_root, Path.basename(&1)))
    |> Enum.sort()
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

  # A citation may only name a relative path inside the repository.
  defp read_source(root, file) do
    if Path.type(file) == :relative and ".." not in Path.split(file),
      do: File.read(Path.join(root, file)),
      else: {:error, :outside_repository}
  end

  # --- the audit --------------------------------------------------------------

  @doc """
  Runs the guard over `inputs` (from `load/1`, possibly mutated by a control).
  Returns `%{report: map, defects: [defect]}`. A defect is
  `%{kind, file, key, detail}`.
  """
  def audit(inputs) do
    {sections, record_defects} = sections(inputs.records)
    {view_keys, view_defects} = view_index(sections, inputs.views)

    rows = for s <- sections, r <- s.rows, do: {s, r}

    row_defects = Enum.flat_map(rows, fn {s, r} -> row_defects(s, r, view_keys) end)
    {citations, citation_defects} = citations(rows, inputs.source_fun)

    set_defects =
      sections
      |> Enum.group_by(& &1.view)
      |> Enum.flat_map(fn {view, ss} -> set_defects(view, ss, view_keys[view]) end)

    report = %{
      "guard" => @guard,
      "records_visited" => map_size(inputs.records),
      "sections" => length(sections),
      "rows_visited" => length(rows),
      "views_bound" => sections |> Enum.map(& &1.view) |> Enum.uniq() |> length(),
      "citations_verified" => citations.repo,
      "harness_citations_not_verified_in_gate_5" => citations.harness,
      "dispositions" => rows |> Enum.map(fn {_, r} -> r["disposition"] end) |> Enum.frequencies()
    }

    defects =
      record_defects ++
        view_defects ++ row_defects ++ set_defects ++ citation_defects ++ reach(report)

    %{report: report, defects: defects}
  end

  defp reach(%{"records_visited" => n, "rows_visited" => 0}) when n > 0,
    do: [
      d(
        :reach,
        "",
        nil,
        "#{n} record(s) visited and ZERO rows: a reader that sees nothing cannot pass"
      )
    ]

  defp reach(_), do: []

  defp sections(records) do
    records
    |> Enum.sort()
    |> Enum.map(fn {file, doc} -> record_sections(file, doc) end)
    |> Enum.reduce({[], []}, fn {ss, ds}, {acc, defects} -> {acc ++ ss, defects ++ ds} end)
  end

  defp record_sections(file, {:ok, %{"schema" => @schema, "authored_by_hand" => true} = doc})
       when is_list(:erlang.map_get("sections", doc)) do
    {ok, bad} = Enum.split_with(doc["sections"], &section?/1)

    bad_defects =
      Enum.map(bad, fn s ->
        d(
          :bad_section,
          file,
          nil,
          "a section needs a string `view`, a `closure` in #{inspect(@closures)} and a `rows` list: #{inspect(s, limit: 5)}"
        )
      end)

    owner_defects =
      for %{"closure" => "open"} = s <- ok, not stated?(s["owner"]) do
        d(
          :open_without_owner,
          file,
          nil,
          "the open section on #{s["view"]} names no `owner`, so nothing closes it"
        )
      end

    parsed =
      Enum.map(ok, &%{file: file, view: &1["view"], closure: &1["closure"], rows: &1["rows"]})

    {parsed, bad_defects ++ owner_defects}
  end

  defp record_sections(file, {:ok, _}) do
    {[],
     [
       d(
         :bad_record,
         file,
         nil,
         "needs schema #{inspect(@schema)}, `authored_by_hand: true` and a `sections` list"
       )
     ]}
  end

  defp record_sections(file, {:error, why}), do: {[], [d(:unreadable, file, nil, why)]}

  defp section?(%{"view" => v, "closure" => c, "rows" => r})
       when is_binary(v) and c in @closures and is_list(r),
       do: true

  defp section?(_), do: false

  # view path -> %{key => view_row}, or :unusable when the view cannot be keyed.
  defp view_index(sections, views) do
    sections
    |> Enum.map(& &1.view)
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn view, {idx, defects} ->
      file = sections |> Enum.find(&(&1.view == view)) |> Map.fetch!(:file)
      {index, ds} = index_view(view, views[view], file)
      {Map.put(idx, view, index), defects ++ ds}
    end)
  end

  defp index_view(view, {:ok, %{"schema" => s, "rows" => rows}}, file)
       when s in @view_schemas and is_list(rows) do
    case rows |> Enum.frequencies_by(&key/1) |> Enum.filter(fn {_, n} -> n > 1 end) do
      [] ->
        {Map.new(rows, &{key(&1), &1}), []}

      collisions ->
        {:unusable,
         Enum.map(collisions, fn {k, n} ->
           d(
             :view_key_collision,
             file,
             k,
             "#{view} projects #{n} rows under this key; the edge triple cannot adjudicate it"
           )
         end)}
    end
  end

  defp index_view(view, other, file) do
    {:unusable,
     [
       d(
         :unknown_view,
         file,
         nil,
         "#{view} is not a readable bucket or escalated view: #{inspect(other, limit: 3)}"
       )
     ]}
  end

  defp row_defects(section, row, view_keys) when is_map(row) do
    k = key(row)
    view_row = view_row(view_keys[section.view], k)
    escalated? = is_map(view_row) and Map.has_key?(view_row, "escalation_reason")

    field_defects(section.file, k, row, escalated?) ++
      disposition_defects(section.file, k, row) ++
      bound_defects(section.file, k, row) ++
      build_defects(section.file, k, row) ++
      sdk_gap_defects(section.file, k, row) ++
      echo_defects(section.file, k, row, view_row) ++
      if(escalated?, do: escalation_defects(section.file, k, row, view_row), else: [])
  end

  defp row_defects(section, row, _),
    do: [d(:bad_row, section.file, nil, "a row must be an object: #{inspect(row, limit: 3)}")]

  defp view_row(index, k) when is_map(index), do: index[k]
  defp view_row(_unusable, _k), do: nil

  defp field_defects(file, k, row, escalated?) do
    required = if escalated?, do: @row_fields ++ @escalated_fields, else: @row_fields

    case Enum.reject(required, &Map.has_key?(row, &1)) do
      [] -> []
      fs -> [d(:bad_row, file, k, "missing #{Enum.join(fs, ", ")}")]
    end
  end

  defp disposition_defects(file, k, row) do
    if row["disposition"] in @dispositions do
      []
    else
      [
        d(
          :disposition_outside_set,
          file,
          k,
          "#{inspect(row["disposition"])} is not one of the guard's closed set #{Enum.join(@dispositions, " ")}"
        )
      ]
    end
  end

  # An accept_bound row must say what it accepts, in one line a consumer can read.
  defp bound_defects(file, k, %{"disposition" => "accept_bound"} = row) do
    b = row["bound"]

    if is_binary(b) and String.trim(b) != "" and not String.contains?(b, ["\n", "\r"]) do
      []
    else
      [
        d(
          :bound_missing,
          file,
          k,
          "an accept_bound row must state its bound as one non-empty line in `bound`, not #{inspect(b, limit: 3)}"
        )
      ]
    end
  end

  defp bound_defects(_file, _k, _row), do: []

  # A bucket-2 row says at what level the missing test would be built, and how,
  # in one line; an extend_to_match row also names the unit it would extend.
  defp build_defects(file, k, %{"disposition" => disp} = row) when disp in @build_dispositions do
    wrong =
      [
        {row["build_level"] in @build_levels,
         "`build_level` in #{inspect(@build_levels)}, not #{inspect(row["build_level"], limit: 3)}"},
        {one_line?(row["remedy"]),
         "a one-line, non-empty `remedy`, not #{inspect(row["remedy"], limit: 3)}"},
        {disp != "extend_to_match" or is_map(row["extend_target"]),
         "an `extend_target` map naming the unit it extends"}
      ]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    case wrong do
      [] -> []
      ws -> [d(:build_level_missing, file, k, "a #{disp} row needs " <> Enum.join(ws, "; "))]
    end
  end

  defp build_defects(_file, _k, _row), do: []

  # A blocked row names the gap that blocks it: the owning ticket, the record
  # that ticket carries, and a citation of the gap in this tree (whose bytes
  # citation_drift holds like any other).
  defp sdk_gap_defects(file, k, %{"disposition" => "blocked_on_sdk_gap"} = row) do
    gap = row["sdk_gap"]

    ok? =
      is_map(gap) and is_binary(gap["owner"]) and gap["owner"] =~ @ticket_key and
        one_line?(gap["owner_record"]) and repo_citation?(gap["record"])

    if ok? do
      []
    else
      [
        d(
          :sdk_gap_missing,
          file,
          k,
          "a blocked_on_sdk_gap row needs `sdk_gap` with a ticket-key `owner`, a one-line `owner_record` and a repository citation `record`, not #{inspect(gap, limit: 3)}"
        )
      ]
    end
  end

  defp sdk_gap_defects(_file, _k, _row), do: []

  defp repo_citation?(%{"file" => f, "lines" => [_, _], "bytes" => b})
       when is_binary(f) and is_binary(b),
       do: true

  defp repo_citation?(_), do: false

  defp one_line?(t),
    do: is_binary(t) and String.trim(t) != "" and not String.contains?(t, ["\n", "\r"])

  defp echo_defects(file, k, row, view_row) do
    if is_map(view_row) and row["echo"] != echo(view_row) do
      [
        d(
          :echo_drift,
          file,
          k,
          "echo #{inspect(row["echo"])} is not the view's #{inspect(echo(view_row))}"
        )
      ]
    else
      []
    end
  end

  defp escalation_defects(file, k, row, view_row) do
    whose =
      if row["whose_defect"] in @whose,
        do: [],
        else: [d(:bad_row, file, k, "whose_defect must be one of #{inspect(@whose)}")]

    slug =
      case row["cause_slug"] do
        %{"view" => v, "verdict" => verdict} when verdict in @slug_verdicts ->
          cond do
            v != view_row["escalation_cause"] ->
              [
                d(
                  :echo_drift,
                  file,
                  k,
                  "cause_slug.view #{inspect(v)} is not the view's #{inspect(view_row["escalation_cause"])}"
                )
              ]

            verdict == "corrected" and not stated?(row["cause_slug"]["to"]) ->
              [d(:bad_row, file, k, "a corrected cause_slug must name what it is corrected `to`")]

            true ->
              []
          end

        _ ->
          [
            d(
              :bad_row,
              file,
              k,
              "cause_slug must be {view, verdict in #{inspect(@slug_verdicts)}}"
            )
          ]
      end

    whose ++ slug
  end

  defp set_defects(view, sections, keys) when is_map(keys) do
    file = hd(sections).file
    adjudicated = for s <- sections, r <- s.rows, is_map(r), do: {s.file, key(r)}
    counts = Enum.frequencies_by(adjudicated, &elem(&1, 1))
    closed? = Enum.any?(sections, &(&1.closure == "closed"))

    phantom =
      for {f, k} <- adjudicated,
          not Map.has_key?(keys, k),
          do:
            d(
              :phantom,
              f,
              k,
              "adjudicated in a section bound to #{view}, which projects no such edge"
            )

    duplicate =
      for {k, n} <- counts,
          n > 1,
          do:
            d(:duplicate, file, k, "adjudicated #{n} times across the sections bound to #{view}")

    missing =
      if closed?,
        do:
          for(
            k <- Map.keys(keys),
            not Map.has_key?(counts, k),
            do:
              d(
                :missing,
                file,
                k,
                "#{view} projects this edge and a closed section bound to it does not adjudicate it"
              )
          ),
        else: []

    phantom ++ duplicate ++ Enum.sort_by(missing, & &1.key)
  end

  defp set_defects(_view, _sections, _unusable), do: []

  # --- citations ---------------------------------------------------------------

  defp citations(rows, source_fun) do
    found = for {s, r} <- rows, is_map(r), c <- collect(r), do: {s.file, key(r), c}
    forms = Enum.frequencies_by(found, fn {_, _, c} -> citation_form(c) end)

    defects =
      Enum.flat_map(found, fn {f, k, c} ->
        case verify(c, source_fun) do
          :ok ->
            []

          {:error, why} ->
            [d(:citation_drift, f, k, "#{c["file"]}:#{inspect(c["lines"])} #{why}")]
        end
      end)

    {%{repo: Map.get(forms, :repo, 0), harness: Map.get(forms, :harness, 0)}, defects}
  end

  defp citation_form(%{"file" => _, "lines" => _}), do: :repo
  defp citation_form(%{"harness_sha256" => _, "byte_span" => _}), do: :harness
  defp citation_form(_), do: :malformed

  @doc false
  def collect(%{"bytes" => b} = m) when is_binary(b), do: [m]
  def collect(m) when is_map(m), do: m |> Map.values() |> Enum.flat_map(&collect/1)
  def collect(l) when is_list(l), do: Enum.flat_map(l, &collect/1)
  def collect(_), do: []

  @doc """
  `:ok` when the cited line window of `file`, whitespace-squashed, EQUALS the
  squashed `bytes`. A `bytes` map that is neither a repository nor a harness
  citation is an error, so a malformed citation cannot slip past as uncounted.
  """
  def verify(%{"file" => f, "lines" => [from, to], "bytes" => b}, source_fun)
      when is_binary(f) and is_integer(from) and is_integer(to) and from >= 1 and to >= from do
    case source_fun.(f) do
      {:ok, src} -> compare(String.split(src, "\n"), from, to, b)
      {:error, why} -> {:error, "cannot be read: #{inspect(why)}"}
    end
  end

  def verify(%{"harness_sha256" => _, "byte_span" => [_, _]}, _source_fun), do: :ok

  def verify(other, _source_fun),
    do: {:error, "is not a citation of either form: #{inspect(Map.drop(other, ["bytes"]))}"}

  defp compare(lines, _from, to, _b) when to > length(lines),
    do: {:error, "is past the end of the file (#{length(lines)} lines)"}

  defp compare(lines, from, to, b) do
    window = lines |> Enum.slice((from - 1)..(to - 1)) |> Enum.join("\n") |> squash()

    if window == squash(b),
      do: :ok,
      else: {:error, "holds #{inspect(window)}, not the cited #{inspect(squash(b))}"}
  end

  @doc "Whitespace runs collapsed to one space, trimmed."
  def squash(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp stated?(t), do: is_binary(t) and t != ""

  defp d(kind, file, key, detail), do: %{kind: kind, file: file, key: key, detail: detail}

  @doc "One line per defect, naming the guard, the kind, the record file and the edge key."
  def format_defect(%{kind: k, file: f, key: key, detail: det}),
    do: "#{@guard} #{k} — #{f}#{if key, do: " @ " <> inspect(key), else: ""}: #{det}"
end

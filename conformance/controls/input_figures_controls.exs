# Controls for G31 — the input-figures guard (MES-120).
#
#     mix run conformance/controls/input_figures_controls.exs positive
#     mix run conformance/controls/input_figures_controls.exs shapes
#     mix run conformance/controls/input_figures_controls.exs universe
#     mix run conformance/controls/input_figures_controls.exs pending
#     mix run conformance/controls/input_figures_controls.exs reach
#     mix run conformance/controls/input_figures_controls.exs sweep
#     mix run conformance/controls/input_figures_controls.exs mutation
#     mix run conformance/controls/input_figures_controls.exs all
#
# WHAT G31 CLAIMS. Every population figure a hand-authored conformance input
# asserts in prose is adjudicated against measurement at the tip, and every
# backticked snake_case cross-reference resolves. `positive` shows the committed
# tree green; the rest show it red for each thing it claims to refuse, and each
# red is required to NAME the guard, the refusal kind, the file and the field —
# a refusal for an unrelated reason fails the control rather than passing it.
#
# WHY IN MEMORY. Every plant mutates a decoded document inside this VM and hands
# it to `InputFigures.audit/1`; nothing in the clone is written. Seats share one
# checkout and a killed VM runs no `after` block (S8-14).
#
# WHERE THE PLANTS GO. `shapes` plants into fields NO ticket pointed at
# (`why_one_file_per_leg`, `polarity_rule`, a per-record `evidence`), not into
# the named slots. `sweep` then plants at EVERY position the scan reports — each
# of the 1800-odd occurrences bumped by one, in its own spelling — and requires
# every one refused at that file and that field: planted N, caught N, uncaught 0,
# where N counts only documents the plant actually changed. `mutation` shows the
# sweep's adjudicator is able to report an uncaught plant: under a guard that
# ignores occurrence identity, it must.

defmodule InputFiguresControls do
  alias MCP.Conformance.InputFigures, as: F

  @client "conformance/data/crosswalk-edges-client.json"
  @server "conformance/data/crosswalk-edges-server.json"
  @residual "conformance/data/crosswalk-edges.json"
  @axes "conformance/data/oc-axes-c1.json"
  @key_change ~w(unledgered stale_entry stale_pending mismatch)a

  def run(["positive"]), do: positive(inputs())
  def run(["shapes"]), do: shapes(inputs())
  def run(["universe"]), do: universe(inputs())
  def run(["pending"]), do: pending(inputs())
  def run(["reach"]), do: reach(inputs())
  def run(["sweep"]), do: sweep(inputs(), & &1, :assert)
  def run(["mutation"]), do: mutation(inputs())

  def run(["all"]) do
    i = inputs()
    positive(i)
    shapes(i)
    universe(i)
    pending(i)
    reach(i)
    sweep(i, & &1, :assert)
    mutation(i)
  end

  def run(_) do
    IO.puts("usage: positive | shapes | universe | pending | reach | sweep | mutation | all")
    System.halt(2)
  end

  # --- positive ----------------------------------------------------------------
  #
  # Without it a guard red on EVERYTHING would pass every control below.

  defp positive(i) do
    header("POSITIVE — the committed tree passes G31")
    %{report: r, defects: defects} = F.audit(i)

    classes = ~w(measured enumerated historical not_a_count pending unparseable refused)
    sum = classes |> Enum.map(&r[&1]) |> Enum.sum()

    IO.puts("  visited #{r["visited"]} = " <> Enum.map_join(classes, " + ", &"#{r[&1]} #{&1}"))

    IO.puts(
      "  references #{r["references_visited"]}: #{r["references_in_data"]} data, #{r["references_in_code"]} code, #{r["references_exempt"]} exempt"
    )

    check("zero defects", defects == [], Enum.map(defects, &F.format_defect/1))
    check("visited is non-zero", r["visited"] > 0)
    check("the classes sum to visited", sum == r["visited"])
    check("nothing refused", r["refused"] == 0)
  end

  # --- shapes ------------------------------------------------------------------

  defp shapes(i) do
    header("SHAPES — each shape in scope planted where no ticket pointed, and refused by name")

    # Shape 1: a bare numeral nobody derives, in a field no ticket touched.
    expect(
      "S1 digit — a new `12 edges` in the client's why_one_file_per_leg",
      plant_append(i, @client, "why_one_file_per_leg", " The file holds 12 edges."),
      :unledgered,
      @client,
      "why_one_file_per_leg"
    )

    # Shape 1 by DATA: the figure's text is untouched and the set under it moves,
    # so only measurement — not occurrence identity — can see it.
    # RE-AIMED AT MES-110. Rule A (A3 §2) left the client file with ZERO
    # all-silent edges, so there is none to drop; the measured figure is now
    # `ZERO all-silent edges`, and the planted defect is the opposite move —
    # one edge silenced on every axis — which must make that zero mismatch.
    expect(
      "S1 measured — silence every axis of one client edge; `ZERO all-silent edges` must now mismatch",
      plant_all_silent_edge(i),
      :mismatch,
      @client,
      "the_all_silent_case"
    )

    # Shape 2: a word-spelled, hedged count, in a field no ticket touched.
    expect(
      "S2 word, hedged — `about nine members` in oc-axes-c1's polarity_rule",
      plant_append(i, @axes, "polarity_rule", " It holds about nine members."),
      :unledgered,
      @axes,
      "polarity_rule"
    )

    # Shape 2 at the named slot: SRV01's corrected `eighteen` put back to `seventeen`.
    expect(
      "S2 word — SRV01's near miss back to `seventeen`",
      plant_replace(
        i,
        @server,
        "absence_searches[SRV01].near_miss",
        "eighteen `http-custom",
        "seventeen `http-custom"
      ),
      :unledgered,
      @server,
      "absence_searches[SRV01].near_miss"
    )

    # The historical rule: an anchor is required IN THE SENTENCE.
    expect(
      "H — a historical sentence with its anchor removed",
      plant_replace(
        i,
        @axes,
        "scope.what_C1c_iii_contributes_and_the_shape_it_has",
        "(C1c-iii) The TWENTY-TWO",
        "The TWENTY-TWO"
      ),
      :unanchored_historical,
      @axes,
      "scope.what_C1c_iii_contributes_and_the_shape_it_has"
    )

    # Shape 5: the brief's own example — a renamed field, cited by its OLD name.
    expect(
      "S5 file-level — `the_bucket_2_entry_this_ticket_closed` in the residual file's absence_searches_note",
      plant_append(
        i,
        @residual,
        "absence_searches_note",
        " See `the_bucket_2_entry_this_ticket_closed`."
      ),
      :unresolved_reference,
      @residual,
      "absence_searches_note"
    )

    evidence = first_leaf(i, @client, &String.ends_with?(&1, ".evidence"))

    expect(
      "S5 per-record — a dead field name in #{String.slice(evidence, 0, 50)}…",
      plant_append(i, @client, evidence, " Cf. `why_the_selector_is_still_a_union_of_slices`."),
      :unresolved_reference,
      @client,
      evidence
    )
  end

  # --- universe ----------------------------------------------------------------

  defp universe(i) do
    header("UNIVERSE — derived, closed both ways, and consistent with the markers")

    new = "docs/conformance/adjudication-record-sprint-12.json"

    expect(
      "U1 a new file under docs/conformance/ that the registry does not list",
      %{i | walk: Enum.sort([new | i.walk]), docs: Map.put(i.docs, new, {:ok, %{"note" => "x"}})},
      :unregistered_file,
      new,
      ""
    )

    {:ok, reg} = i.registry
    ghost = "conformance/data/ghost.json"

    expect(
      "U2 a registered file that is not on disk",
      %{i | registry: {:ok, put_in(reg, ["files", ghost], "hand_authored")}},
      :absent_file,
      ghost,
      ""
    )

    expect(
      "U3 a hand-authored input registered as generated",
      %{i | registry: {:ok, put_in(reg, ["files", @client], "generated")}},
      :marker_disagreement,
      @client,
      ""
    )
  end

  # --- pending -----------------------------------------------------------------

  defp pending(i) do
    header("PENDING — only pre-existing, only in scope (the set pin is in gate 5)")
    {:ok, ledger} = i.ledger

    # P1: a new per-record figure parked in pending (in scope, but not at baseline).
    evidence = first_leaf(i, @client, &String.ends_with?(&1, ".evidence"))
    planted = plant_append(i, @client, evidence, " It rests on 23 members.")
    row = %{"file" => @client, "path" => evidence, "phrase" => "23 members", "nth" => 1}
    p1 = %{planted | ledger: {:ok, %{ledger | "pending" => [row | ledger["pending"]]}}}

    expect(
      "P1 a figure first written after the baseline, parked in pending",
      p1,
      :pending_not_in_baseline,
      @client,
      evidence
    )

    # P2: a file-level entry moved into pending (at baseline, but out of scope).
    [e | _] =
      Enum.filter(
        ledger["entries"],
        &(&1["file"] == @client and &1["path"] == "the_all_silent_case")
      )

    moved = Map.take(e, ~w(file path phrase nth))

    p2 = %{
      i
      | ledger:
          {:ok,
           %{
             ledger
             | "entries" => ledger["entries"] -- [e],
               "pending" => [moved | ledger["pending"]]
           }}
    }

    expect(
      "P2 a file-level figure deferred to pending",
      p2,
      :pending_outside_scope,
      @client,
      "the_all_silent_case"
    )

    # P3: a pending figure whose text has left must leave the set.
    [p | _] = ledger["pending"]

    gone =
      plant_leaf(i, p["file"], p["path"], fn s ->
        String.replace(s, p["phrase"], "[figure removed]")
      end)

    expect(
      "P3 a pending row whose figure no longer occurs",
      gone,
      :stale_pending,
      p["file"],
      p["path"]
    )

    # P4: fail-closed when the baseline cannot be read.
    p4 =
      i
      |> Map.delete(:baseline_scans)
      |> Map.put(:baseline_fun, fn _ -> {:error, "no such commit"} end)

    expect("P4 the baseline copy is unreadable", p4, :pending_unverifiable, p["file"], p["path"])
  end

  # --- reach -------------------------------------------------------------------

  defp reach(i) do
    header("REACH — a reader that sees nothing cannot pass")
    {:ok, reg} = i.registry
    blind = Map.new(reg["files"], fn {f, _} -> {f, "raw_evidence"} end)
    markers_ok = %{i | docs: Map.new(i.docs, fn {f, _} -> {f, {:ok, %{}}} end)}

    expect(
      "R1 every file classified away from hand_authored",
      %{markers_ok | registry: {:ok, %{reg | "files" => blind}}},
      :reach,
      "",
      ""
    )
  end

  # --- sweep -------------------------------------------------------------------

  defp sweep(i, filter, mode) do
    header("SWEEP — every occurrence bumped by one in its own spelling, and refused at its field")
    occ = occurrences(i)

    results =
      occ
      |> Task.async_stream(&bump_and_audit(i, &1, filter),
        max_concurrency: System.schedulers_online(),
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn {:ok, r} -> r end)

    planted = Enum.filter(results, & &1.changed)
    caught = Enum.filter(planted, & &1.caught)
    uncaught = planted -- caught

    IO.puts(
      "  occurrences #{length(occ)}   planted #{length(planted)} (documents actually changed)"
    )

    IO.puts("  caught #{length(caught)}   uncaught #{length(uncaught)}")

    for u <- Enum.take(uncaught, 10),
        do: IO.puts("    UNCAUGHT  #{u.file} @ #{u.path}: #{inspect(u.phrase)}")

    by_class = caught |> Enum.frequencies_by(& &1.class) |> Enum.sort()
    IO.puts("  caught by the occurrence's class: #{inspect(by_class)}")

    counts = {length(planted), length(caught), length(uncaught)}

    # The mutation mode reuses this sweep under a weakened guard and asserts
    # the OPPOSITE, so the assertion is the caller's choice, not a closure test.
    if mode == :assert do
      {p, c, u} = counts
      check("planted == caught, uncaught 0", p > 0 and p == c and u == 0)
    end

    counts
  end

  # --- mutation ----------------------------------------------------------------
  #
  # A sweep whose adjudicator cannot report an uncaught plant proves nothing.
  # Drop the refusals that come from OCCURRENCE IDENTITY (the kinds a changed
  # phrase produces) — a guard that looked only at measured values — and the
  # same sweep must report uncaught plants.

  defp mutation(i) do
    header(
      "MUTATION — the sweep under a guard blind to occurrence identity must report uncaught plants"
    )

    weakened = fn defects ->
      Enum.reject(defects, &(&1.kind in [:unledgered, :stale_entry, :stale_pending]))
    end

    sample = i |> occurrences() |> Enum.take_every(25)
    sampled = %{i | sample: sample}
    {p, _c, u} = sweep(sampled, weakened, :report)
    check("the weakened guard leaves plants uncaught (#{u} of #{p})", p > 0 and u > 0)
  end

  # --- helpers -----------------------------------------------------------------

  defp inputs do
    i = F.load()
    i |> Map.put(:baseline_scans, F.baseline_scans(i)) |> Map.put(:sample, nil)
  end

  defp occurrences(%{sample: s}) when is_list(s), do: s

  defp occurrences(i) do
    {:ok, reg} = i.registry

    for {f, "hand_authored"} <- reg["files"],
        {:ok, doc} <- [i.docs[f]],
        o <- F.scan(doc, f),
        do: o
  end

  defp bump_and_audit(i, o, filter) do
    {:ok, doc} = i.docs[o.file]
    mutated = F.map_leaves(doc, fn path, s -> if path == o.path, do: bump(s, o), else: s end)

    defects =
      %{i | docs: Map.put(i.docs, o.file, {:ok, mutated})}
      |> F.audit()
      |> Map.fetch!(:defects)
      |> filter.()

    caught =
      Enum.any?(defects, &(&1.kind in @key_change and &1.file == o.file and &1.path == o.path))

    {:ok, ledger} = i.ledger

    %{
      file: o.file,
      path: o.path,
      phrase: o.phrase,
      changed: mutated != doc,
      caught: caught,
      class: class_of(ledger, o)
    }
  end

  defp class_of(ledger, o) do
    k = {o.file, o.path, o.phrase, o.nth}

    cond do
      Enum.any?(ledger["pending"], &({&1["file"], &1["path"], &1["phrase"], &1["nth"]} == k)) ->
        "pending"

      e = Enum.find(ledger["entries"], &({&1["file"], &1["path"], &1["phrase"], &1["nth"]} == k)) ->
        e["class"]

      true ->
        "?"
    end
  end

  # Replace the NUMBER of the o.nth occurrence of o.phrase in `s` with value+1,
  # spelled the way it was spelled.
  defp bump(s, o) do
    matches = Regex.scan(F.figure_regex(), s, return: :index)

    {[_whole, _hedge, {ns, nl} | _], _} =
      matches
      |> Enum.filter(fn [{st, l} | _] -> binary_part(s, st, l) == o.phrase end)
      |> Enum.with_index(1)
      |> Enum.find(fn {_m, n} -> n == o.nth end)

    number = binary_part(s, ns, nl)
    binary_part(s, 0, ns) <> respell(number) <> binary_part(s, ns + nl, byte_size(s) - ns - nl)
  end

  @words ~w(zero one two three four five six seven eight nine ten eleven twelve thirteen
            fourteen fifteen sixteen seventeen eighteen nineteen)
  @tens ~w(twenty thirty forty fifty sixty seventy eighty ninety)

  defp respell(number) do
    case F.parse(number) do
      n when is_integer(n) ->
        if number =~ ~r/^\d/, do: Integer.to_string(n + 1), else: recase(word(n + 1), number)

      :unparseable ->
        number <> "1"
    end
  end

  defp word(n) when n < 20, do: Enum.at(@words, n)
  defp word(n) when rem(n, 10) == 0, do: Enum.at(@tens, div(n, 10) - 2)

  defp word(n) when n < 100,
    do: Enum.at(@tens, div(n, 10) - 2) <> "-" <> Enum.at(@words, rem(n, 10))

  defp word(_), do: "hundred"

  defp recase(w, like) do
    cond do
      like == String.upcase(like) -> String.upcase(w)
      String.first(like) == String.upcase(String.first(like)) -> String.capitalize(w)
      true -> w
    end
  end

  defp plant_append(i, file, path, text), do: plant_leaf(i, file, path, &(&1 <> text))

  defp plant_replace(i, file, path, from, to) do
    plant_leaf(i, file, path, fn s ->
      unless String.contains?(s, from),
        do: raise("control setup: #{inspect(from)} not in #{file} @ #{path}")

      String.replace(s, from, to, global: false)
    end)
  end

  defp plant_leaf(i, file, path, fun) do
    {:ok, doc} = i.docs[file]
    mutated = F.map_leaves(doc, fn p, s -> if p == path, do: fun.(s), else: s end)
    if mutated == doc, do: raise("control setup: nothing changed at #{file} @ #{path}")
    %{i | docs: Map.put(i.docs, file, {:ok, mutated})}
  end

  defp plant_all_silent_edge(i) do
    {:ok, doc} = i.docs[@client]
    [first | rest] = doc["edges"]
    silenced = %{first | "axes" => Enum.map(first["axes"], &%{&1 | "verdict" => "silent"})}
    %{i | docs: Map.put(i.docs, @client, {:ok, %{doc | "edges" => [silenced | rest]}})}
  end

  defp first_leaf(i, file, pred) do
    {:ok, doc} = i.docs[file]
    doc |> F.leaves([]) |> Enum.map(&elem(&1, 0)) |> Enum.find(pred)
  end

  # A refusal is evidence only for the class it was planted to cause: the
  # defect must be of `kind`, at `file`, at a path containing `path`, and its
  # printed line must name the guard.
  defp expect(label, inputs, kind, file, path) do
    defects = F.audit(inputs).defects

    hit =
      Enum.find(defects, fn d ->
        d.kind == kind and d.file == file and String.contains?(d.path, path)
      end)

    case hit do
      nil ->
        IO.puts("  FAIL  #{label}")
        IO.puts("        wanted #{kind} at #{file} @ #{path}; got #{length(defects)} defect(s):")

        for d <- Enum.take(defects, 5),
            do: IO.puts("          " <> String.slice(F.format_defect(d), 0, 200))

        System.halt(1)

      d ->
        line = F.format_defect(d)
        check_named(label, line)
        IO.puts("        " <> String.slice(line, 0, 220))
    end
  end

  defp check_named(label, line) do
    if String.starts_with?(line, "G31 "),
      do: IO.puts("  ok    #{label}"),
      else:
        (
          IO.puts("  FAIL  #{label} — the refusal does not name G31: #{line}")
          System.halt(1)
        )
  end

  defp check(label, ok?, detail \\ []) do
    if ok? do
      IO.puts("  ok    #{label}")
    else
      IO.puts("  FAIL  #{label}")
      for l <- Enum.take(detail, 10), do: IO.puts("        #{l}")
      System.halt(1)
    end
  end

  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

InputFiguresControls.run(System.argv())

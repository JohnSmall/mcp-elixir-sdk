# Controls for the ET-CC attribution register (MES-82 / B2b).
#
#     mix run conformance/controls/etcc_attribution_controls.exs guards
#     mix run conformance/controls/etcc_attribution_controls.exs strip-boundary
#     mix run conformance/controls/etcc_attribution_controls.exs sweep
#     mix run conformance/controls/etcc_attribution_controls.exs reproduce
#     mix run conformance/controls/etcc_attribution_controls.exs proxy
#     mix run conformance/controls/etcc_attribution_controls.exs figures
#
# WHY A SCRIPT AND NOT AN ExUnit TEST — the same reason B2a gives: a test file
# under `test/mcp/` would add members to the population this register attributes,
# and one under `test/conformance/` would move MES-83's 992-row artefact. An
# instrument that changes its own denominator by existing is a perturbation.
# (`test/conformance/etcc_attribution_test.exs` is the deliberate exception: AC5
# asks for a cross-file test IN gate 5, and its cost to the denominator is stated
# there rather than hidden.)
#
# `guards` is what makes the rest mean anything: it mutates a copy of the authored
# source once per fail-closed condition and shows the builder REFUSING. A guard
# that has never been seen to fire is a promise, not a guard.
#
# `strip-boundary` is the control the PM asked for by name. A promise that I did
# not use the register's `boundary` field as a leg proxy is unfalsifiable, so this
# does not offer one: it deletes `boundary` from every register row, re-runs the
# WHOLE build, and asserts the output is byte-identical.

defmodule ETCCAttributionControls do
  alias MCP.Conformance.ETCCAttribution

  @paths ETCCAttribution.paths()

  def run(["guards"]), do: guards()
  def run(["strip-boundary"]), do: strip_boundary()
  def run(["sweep"]), do: sweep()
  def run(["reproduce"]), do: reproduce()
  def run(["proxy"]), do: proxy()
  def run(["figures"]), do: figures()

  def run(_) do
    IO.puts("usage: guards | strip-boundary | sweep | reproduce | proxy | figures")
    System.halt(2)
  end

  # --- guards: every fail-closed condition, shown FIRING ---------------------

  defp guards do
    header("GUARDS — each fail-closed condition, mutated and shown to refuse")

    authored = read(@paths.authored)
    first = hd(authored)
    with_cg = Enum.find(authored, &(not is_nil(&1["cg"])))
    with_tok = Enum.find(authored, &(&1["tokens"] != []))
    with_contra = Enum.find(authored, &(not is_nil(&1["contradicts_oc"])))

    refuses("1  field disjointness — an authored row also carrying `label`", fn ->
      build_with(replace(authored, first, Map.put(first, "label", "ET-CC")))
    end)

    refuses("2  field disjointness — an authored row also carrying `line`", fn ->
      build_with(replace(authored, first, Map.put(first, "line", 1)))
    end)

    refuses("3  unknown authored field", fn ->
      build_with(replace(authored, first, Map.put(first, "verdict", "green")))
    end)

    refuses("4  key-set: a member with NO attribution", fn ->
      build_with(List.delete(authored, first))
    end)

    refuses("5  key-set: an attribution naming a NON-member", fn ->
      build_with(authored ++ [Map.put(first, "key", "MCP.NoSuchTest/test nope")])
    end)

    refuses("6  key VERBATIM — one character changed in an authored key", fn ->
      build_with(replace(authored, first, Map.put(first, "key", mutate_one_char(first["key"]))))
    end)

    refuses("7  key VERBATIM — the test-type prefix stripped (a normalisation)", fn ->
      stripped = String.replace(first["key"], "/test ", "/", global: false)
      build_with(replace(authored, first, Map.put(first, "key", stripped)))
    end)

    refuses("8  leg outside the vocabulary", fn ->
      build_with(replace(authored, first, Map.put(first, "leg", "both")))
    end)

    refuses("9  leg with no reason", fn ->
      build_with(replace(authored, first, Map.put(first, "leg_reason", "")))
    end)

    refuses("10 cg_basis absent — silence encoding a decision", fn ->
      build_with(replace(authored, first, Map.delete(first, "cg_basis")))
    end)

    refuses("11 cg outside CG1..CG7", fn ->
      build_with(replace(authored, with_cg, Map.put(with_cg, "cg", "CG9")))
    end)

    refuses("12 contradicts_oc as a bare flag, naming nothing", fn ->
      build_with(replace(authored, with_contra, Map.put(with_contra, "contradicts_oc", true)))
    end)

    refuses("13 contradicts_oc naming something that is not an OC token", fn ->
      broken = %{"check" => "the initialize one", "note" => "n"}
      build_with(replace(authored, with_contra, Map.put(with_contra, "contradicts_oc", broken)))
    end)

    refuses("14 a token that is neither an oc: nor an oc:none/ address", fn ->
      build_with(replace(authored, with_tok, Map.put(with_tok, "tokens", ["CG7"])))
    end)

    refuses("15 an oc:none/ token whose native id carries a `/` (match-relation §6)", fn ->
      bad = ["oc:none/no-oc-scenario/CG2/inbound-parse"]
      build_with(replace(authored, with_tok, Map.put(with_tok, "tokens", bad)))
    end)

    refuses("16 a token part outside the measured [A-Za-z0-9_-] charset", fn ->
      bad = ["oc:none/no-oc-scenario/CG2 inbound parse"]
      build_with(replace(authored, with_tok, Map.put(with_tok, "tokens", bad)))
    end)

    IO.puts("\n  16 of 16 fail-closed conditions were seen to refuse.")
  end

  # --- the strip-boundary control -------------------------------------------

  defp strip_boundary do
    header("STRIP-BOUNDARY — the whole build re-run against a register with no `boundary`")

    IO.puts("""
      The register's `boundary` field decides gate 2. It is NOT a leg attribution.
      This deletes it from every register row and re-runs the build. A build that
      had used it cannot survive this; a build that had not, cannot fail it.
    """)

    register = read(@paths.register)
    rows = Map.fetch!(register, "rows")

    carried = Enum.count(rows, &Map.has_key?(&1, "boundary"))
    IO.puts("  register rows carrying `boundary`: #{carried} of #{length(rows)}")

    if carried == 0 do
      IO.puts("  BROKEN CONTROL: nothing to strip, so passing would mean nothing.")
      System.halt(1)
    end

    stripped = Map.put(register, "rows", Enum.map(rows, &Map.delete(&1, "boundary")))
    path = write_tmp("register-no-boundary", stripped)

    baseline = canonical(ETCCAttribution.build())
    without = canonical(ETCCAttribution.build(register: path))
    File.rm(path)

    IO.puts("  md5 with    boundary: #{md5(baseline)}")
    IO.puts("  md5 without boundary: #{md5(without)}")

    if baseline == without do
      IO.puts("\n  ok — byte-identical. The build never read `boundary`.")
    else
      IO.puts("\n  DIFFER — the build reads `boundary`. That is the shortcut the brief forbids.")
      System.halt(1)
    end
  end

  # --- the sweep, demoted to a control --------------------------------------

  # MEASURED BEFORE IT WAS PROPOSED, and disqualified as the method by that
  # measurement: over the 12 register rows cg-reconciliation.md §3 names as CG1's
  # and CG7's end-to-end discharge, a SEP-number sweep over `spec_anchor` returns
  # 7 — a 42% under-count, every loss in the "none" direction. So the sweep can
  # only ACCUSE the enumeration; it can never confirm it. It runs here, and every
  # hit the enumeration called "none" is printed for a mandatory re-read.
  defp sweep do
    header("SWEEP — the term-driven instrument, run as a control on the enumeration")

    register = read(@paths.register)
    enriched = read(@paths.enriched)

    by_key = Map.new(Map.fetch!(register, "rows"), &{&1["key"], &1})
    attributed = Map.new(Map.fetch!(enriched, "rows"), &{&1["key"], &1})

    # POSITIVE CONTROL FIRST, gate-6a shape: a term known to hit that returns 0
    # means the instrument is broken, not that the answer is none.
    positive = hits(by_key, attributed, "2243")

    IO.puts("  positive control — /2243/ over spec_anchor: #{length(positive)} hit(s)")

    if positive == [] do
      IO.puts("  BROKEN INSTRUMENT: SEP-2243 is known to be present. Not a result.")
      System.halt(1)
    end

    IO.puts("""

      THE MEASUREMENT THAT DISQUALIFIED THIS AS THE METHOD. cg-reconciliation.md §3
      names 12 rows as CG1's and CG7's end-to-end discharge. The sweep below finds
      7 of them: :199, :222, :239, :342 and :359 anchor to streamable-http.mdx line
      ranges without naming the SEP. 42% under-count, every loss toward "none".
    """)

    cg1_cg7 =
      for {key, row} <- by_key,
          row["file"] == "test/mcp/transport/routing_headers_test.exs",
          row["line"] in [89, 108, 122, 133, 161, 180, 199, 222, 239, 307, 342, 359],
          row["label"] == "ET-CC",
          do: {row["line"], String.contains?(row["spec_anchor"] || "", "2243"), key}

    found = Enum.count(cg1_cg7, fn {_l, hit, _k} -> hit end)
    IO.puts("  of the 12 discharge rows, the SEP sweep finds: #{found}")

    for {line, hit, _} <- Enum.sort(cg1_cg7) do
      IO.puts("    #{if hit, do: "hit ", else: "MISS"} routing_headers_test.exs:#{line}")
    end

    IO.puts("\n  Sweep hits the ENUMERATION recorded as cg: none — each re-read by hand:")

    accused =
      for {_key, %{"cg" => nil}} = pair <- positive, do: pair

    if accused == [] do
      IO.puts("    (none)")
    else
      for {key, row} <- Enum.sort(accused) do
        r = Map.fetch!(by_key, key)
        IO.puts("    #{r["file"]}:#{r["line"]}")
        IO.puts("      basis: #{String.slice(row["cg_basis"], 0, 96)}…")
      end
    end

    # The FALSE-POSITIVE control, on the pairing A4 examined and REJECTED.
    # `ClientCustomHeaderNoMirrorNumber` asserts an UNANNOTATED number is not
    # mirrored; our constraint is that an ANNOTATED one is rejected outright.
    # If any member here claims it as a counterpart, this method is broken.
    claimed =
      enriched
      |> Map.fetch!("rows")
      |> Enum.flat_map(& &1["tokens"])
      |> Enum.filter(&String.contains?(&1, "ClientCustomHeaderNoMirrorNumber"))

    IO.puts("\n  false-positive control — members claiming ClientCustomHeaderNoMirrorNumber: #{length(claimed)}")

    if claimed == [] do
      IO.puts("    ok — A4 examined and rejected that pairing, and this method agrees.")
    else
      IO.puts("    BROKEN METHOD: it accepts a pairing A4 rejected on the predicate.")
      System.halt(1)
    end
  end

  defp hits(by_key, attributed, term) do
    for {key, row} <- by_key,
        row["label"] == "ET-CC",
        String.contains?(row["spec_anchor"] || "", term),
        do: {key, Map.fetch!(attributed, key)}
  end

  # --- the S7-24 column, as a control instead of a hand pass ----------------

  # S7-24: prose figures are not rebuilt when the artefact is. Round 1 ran this
  # as a hand column and three figures did not survive it. It is a control now,
  # for the reason S7-24 exists: a check run by hand once is run once.
  #
  # AND ITS OWN BOUND, WHICH IS S7-29. This re-derives each figure FROM THE
  # ARTEFACT, so it reaches every figure with an artefact counterpart and NO
  # figure asserted about another SECTION of the prose — which is exactly where
  # round 1's two surviving stale figures were. The complement is an
  # internal-consistency read, and no artefact can stand in for it.
  defp figures do
    header("FIGURES — every artefact-derived figure re-derived and looked for in the prose")

    enriched = read(@paths.enriched)
    totals = Map.fetch!(enriched, "totals")
    rows = Map.fetch!(enriched, "rows")
    prose = File.read!("docs/conformance/etcc-attribution.md")

    by_leg = Map.fetch!(totals, "by_leg")
    by_cg = Map.fetch!(totals, "by_cg")

    state_1 = Enum.count(all_tokens(rows), &(not String.starts_with?(&1, "oc:none/")))
    carriers_1 = Enum.count(rows, fn r -> Enum.any?(r["tokens"], &(not String.starts_with?(&1, "oc:none/"))) end)

    checks = [
      {"members", Map.fetch!(totals, "members")},
      {"leg server", Map.fetch!(by_leg, "server")},
      {"leg client", Map.fetch!(by_leg, "client")},
      {"leg none_determinable", Map.fetch!(by_leg, "none_determinable")},
      {"with_cg", Map.fetch!(totals, "with_cg")},
      {"cg none", Map.fetch!(by_cg, "none")},
      {"CG1", Map.fetch!(by_cg, "CG1")},
      {"CG2", Map.fetch!(by_cg, "CG2")},
      {"CG4", Map.fetch!(by_cg, "CG4")},
      {"CG7", Map.fetch!(by_cg, "CG7")},
      {"state-3 tokens", Map.fetch!(totals, "state_3_tokens")},
      {"state-1 tokens", state_1},
      {"state-1 carriers", carriers_1},
      {"contradicts_oc", Map.fetch!(totals, "contradicts_oc")}
    ]

    missing =
      for {label, n} <- checks, reduce: [] do
        acc ->
          found? = prose =~ ~r/(?<![0-9])#{n}(?![0-9])/
          IO.puts("  #{String.pad_trailing(label, 22)} #{String.pad_leading(to_string(n), 4)}  #{if found?, do: "present in prose", else: "ABSENT FROM PROSE"}")
          if found?, do: acc, else: [label | acc]
      end

    IO.puts("""

      NOTE ON WHAT "present" MEANS — a bare numeral search is a WEAK check: it
      cannot tell the right figure in the right sentence from the same digits
      somewhere else. It fails only in the safe direction (an ABSENT figure is a
      real finding), and it is the enumeration check below that carries weight.
    """)

    enumeration_check(rows, prose)

    if missing != [] do
      IO.puts("\n  FIGURES MISSING FROM THE PROSE: #{inspect(Enum.reverse(missing))}")
      System.halt(1)
    end
  end

  # Every member of every population must be CITED at its own address in the
  # prose (epic ruling 4: a count is backed by per-item enumeration). "In the
  # population and not cited" must be empty for each.
  defp enumeration_check(rows, prose) do
    register = read(@paths.register)
    by_key = Map.new(Map.fetch!(register, "rows"), &{&1["key"], &1})
    cited = cited_addresses(prose)

    populations =
      [{"leg: none_determinable", fn r -> r["leg"] == "none_determinable" end}] ++
        for cg <- ~w(CG1 CG2 CG4 CG7) do
          {"cg: #{cg}", fn r -> r["cg"] == cg end}
        end

    IO.puts("  PER-ITEM ENUMERATION — every member of each population cited at its own address\n")

    bad =
      for {label, pred} <- populations, reduce: [] do
        acc ->
          members =
            rows
            |> Enum.filter(pred)
            |> Enum.map(fn r ->
              row = Map.fetch!(by_key, r["key"])
              {Path.basename(row["file"]), row["line"]}
            end)
            |> Enum.uniq()

          absent = Enum.reject(members, &MapSet.member?(cited, &1))

          IO.puts(
            "    #{String.pad_trailing(label, 24)} #{length(members)} distinct address(es), " <>
              "not cited: #{if absent == [], do: "none", else: inspect(absent)}"
          )

          if absent == [], do: acc, else: [{label, absent} | acc]
      end

    if bad != [] do
      IO.puts("\n  ENUMERATION INCOMPLETE — a counted member is not cited: #{inspect(bad)}")
      System.halt(1)
    end
  end

  # Reads the prose the way a reader does: inside one paragraph, a bare
  # `:NNN,NNN,…` run belongs to the most recent `*.exs` named in that paragraph,
  # and a run after a filename belongs to that file. The prose spells every file
  # basename out for this reason — a two-letter shorthand would make a bare
  # `:NNN` ambiguous, and an ambiguity here credits a citation that was never
  # written, which is the one direction this check must not fail in.
  defp cited_addresses(prose) do
    prose
    |> String.split(~r/\n\s*\n/)
    |> Enum.flat_map(&paragraph_addresses/1)
    |> MapSet.new()
  end

  defp paragraph_addresses(par) do
    ~r/(?:([A-Za-z0-9_]+\.exs))?:(\d+(?:\s*,\s*\d+)*)/
    |> Regex.scan(par)
    |> Enum.reduce({nil, []}, fn
      [_, "", lines], {current, acc} -> {current, emit(current, lines, acc)}
      [_, file, lines], {_current, acc} -> {file, emit(file, lines, acc)}
      [_, file], {_current, acc} -> {file, acc}
      _, state -> state
    end)
    |> elem(1)
  end

  defp emit(nil, _lines, acc), do: acc

  defp emit(file, lines, acc) do
    lines
    |> String.split(",")
    |> Enum.map(&String.to_integer(String.trim(&1)))
    |> Enum.reduce(acc, &[{file, &1} | &2])
  end

  defp all_tokens(rows), do: Enum.flat_map(rows, & &1["tokens"])

  # --- the boundary proxy, IMPLEMENTED rather than asserted ------------------

  # ADDED IN CORRECTION ROUND 1 (review comment 26098, part (b)). The
  # `etcc-attribution.md` §1(b) agreement figure was the one claim in the file
  # with no control behind it, and a reviewer showed it is RULE-SENSITIVE: the
  # strict reading of the proxy ("every `boundary` entry must be leg-specific
  # AND agree") and the loose one ("any leg-specific entry decides") give
  # different numbers, and only the strict one has a one-directional
  # disagreement table. An unimplemented rule cannot settle which was meant.
  #
  # So both readings run here and both are printed. Note what this does and does
  # not do: it makes §1(b) REPRODUCIBLE, and it does not make the correlation
  # evidence about the authoring — see §1(b)'s own bound, which says why no
  # correlation could be.
  defp proxy do
    header("BOUNDARY PROXY — both readings implemented, so §1(b) is reproducible")

    register = read(@paths.register)
    enriched = read(@paths.enriched)

    by_key = Map.new(Map.fetch!(register, "rows"), &{&1["key"], &1})

    rows =
      for row <- Map.fetch!(enriched, "rows") do
        boundary = Map.fetch!(by_key, row["key"])["boundary"] || []
        {boundary, row["leg"]}
      end

    for {name, reading} <- [{"STRICT — every entry leg-specific AND agreeing", :strict},
                            {"LOOSE  — any leg-specific entry decides", :loose}] do
      table =
        Enum.frequencies_by(rows, fn {boundary, leg} -> {proxy_leg(boundary, reading), leg} end)

      agree = table |> Enum.filter(fn {{p, l}, _} -> p == l end) |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      total = length(rows)

      pct = Float.round(agree * 100 / total, 1)
      IO.puts("\n  #{name}\n  agreement: #{agree} of #{total} = #{pct}%")

      for {{p, l}, n} <- Enum.sort(table) do
        IO.puts("    proxy=#{pad(p)} file=#{pad(l)} #{n} #{if p == l, do: "agrees", else: "DISAGREES"}")
      end

      crossing =
        table
        |> Enum.filter(fn {{p, l}, _} -> p != l and p != "none_determinable" end)
        |> Enum.map(&elem(&1, 1))
        |> Enum.sum()

      IO.puts("    disagreements NOT of the form (proxy abstains, file decides): #{crossing}")
    end

    IO.puts("""

      §1(b) states the STRICT table and the claim that every disagreement is the
      proxy abstaining. The LOOSE reading is printed beside it because it does NOT
      have that property, which is exactly why the reading has to be named.
    """)
  end

  defp proxy_leg(boundary, reading) do
    legs = Enum.map(boundary, &entry_leg/1)
    named = Enum.reject(legs, &is_nil/1)

    decided? =
      case reading do
        :strict -> boundary != [] and Enum.all?(legs, &(not is_nil(&1)))
        :loose -> named != []
      end

    if decided? and Enum.uniq(named) |> length() == 1,
      do: hd(named),
      else: "none_determinable"
  end

  defp entry_leg("MCP.Client" <> _), do: "client"
  defp entry_leg("MCP.Server." <> _), do: "server"
  defp entry_leg("MCP.Transport.StreamableHTTP.Plug" <> _), do: "server"
  defp entry_leg(_), do: nil

  defp pad(s), do: String.pad_trailing(s, 19)

  # --- reproduce -------------------------------------------------------------

  defp reproduce do
    header("REPRODUCE — the committed artefact, rebuilt and diffed")

    committed = File.read!(@paths.enriched)
    rebuilt = Jason.encode!(ETCCAttribution.build(), pretty: true) <> "\n"

    IO.puts("  committed md5: #{md5(committed)}")
    IO.puts("  rebuilt   md5: #{md5(rebuilt)}")

    if committed == rebuilt do
      IO.puts("\n  ok — byte-identical.")
    else
      IO.puts("\n  DIFFER — the committed artefact is not what the authored source builds.")
      System.halt(1)
    end
  end

  # --- helpers ---------------------------------------------------------------

  defp build_with(authored) do
    path = write_tmp("attribution", authored)

    try do
      ETCCAttribution.build(authored: path)
    after
      File.rm(path)
    end
  end

  defp refuses(label, fun) do
    fun.()
    IO.puts("  DID NOT REFUSE  #{label}")
    System.halt(1)
  rescue
    e -> IO.puts("  refused  #{label}\n           #{first_line(Exception.message(e))}")
  end

  defp replace(list, old, new), do: Enum.map(list, &if(&1 == old, do: new, else: &1))

  defp mutate_one_char(key) do
    <<head::binary-size(byte_size(key) - 1), last::binary-size(1)>> = key
    head <> if last == "x", do: "y", else: "x"
  end

  defp canonical(map), do: Jason.encode!(map, pretty: true)

  defp read(path), do: path |> File.read!() |> Jason.decode!()

  defp write_tmp(stem, doc) do
    path = Path.join(System.tmp_dir!(), "#{stem}-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(doc))
    path
  end

  defp md5(bin), do: :crypto.hash(:md5, bin) |> Base.encode16(case: :lower)

  defp first_line(msg), do: msg |> String.split("\n") |> hd()

  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

ETCCAttributionControls.run(System.argv())

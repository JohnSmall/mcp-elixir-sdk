# Controls for the ET-CC register (MES-81 / B2a).
#
#     mix run conformance/controls/etcc_register_controls.exs guards
#     mix run conformance/controls/etcc_register_controls.exs totality
#     mix run conformance/controls/etcc_register_controls.exs keysets
#     mix run conformance/controls/etcc_register_controls.exs reproduce
#     mix run conformance/controls/etcc_register_controls.exs spec <dir>
#     mix run conformance/controls/etcc_register_controls.exs delimit
#     mix run conformance/controls/etcc_register_controls.exs f4
#     mix run conformance/controls/etcc_register_controls.exs identity
#     mix run conformance/controls/etcc_register_controls.exs oracle
#     mix run conformance/controls/etcc_register_controls.exs all
#
# `all` (MES-229) runs guards, totality, keysets, reproduce, delimit, f4, identity and oracle
# (MES-230), each in its own `mix run`, and exits 1 if any of them fails. `spec` is NOT in it: it needs a
# materialised spec tree at 5f5440bb passed as <dir>, which no tree carries.
#
# WHY A SCRIPT AND NOT AN ExUnit TEST. Any test file added here lands in the very
# suite the register enumerates: under `test/mcp/` it would add members to the
# population it validates, and under `test/conformance/` it would still move the
# artefact's 992 and so the out-of-scope enumeration. An instrument that changes
# its own denominator by existing is a perturbation, not a test. Same idiom as
# `conformance/controls/exunit_rows_controls.exs` (MES-83).
#
# `guards` is the one that makes the rest mean anything: it MUTATES a copy of the
# authored decisions file once per fail-closed condition and shows the generator
# REFUSING. A guard that has never been seen to fire is a promise, not a guard.

defmodule ETCCRegisterControls do
  alias MCP.Conformance.{ETCCRegister, OcGateDeclarations}

  @paths ETCCRegister.paths()
  @in_scope "test/mcp/"

  def run(["guards"]), do: guards()
  def run(["totality"]), do: totality()
  def run(["keysets"]), do: keysets()
  def run(["reproduce"]), do: reproduce()
  def run(["spec", dir]), do: spec(dir)
  def run(["delimit"]), do: delimit()
  def run(["f4"]), do: f4()
  def run(["identity"]), do: identity()
  def run(["oracle"]), do: oracle()
  def run(["all"]), do: all()

  def run(_) do
    IO.puts(
      "usage: guards | totality | keysets | reproduce | spec <dir> | delimit | f4 | identity | oracle | all\n" <>
        "       (all = every mode but spec, which needs a materialised spec tree as <dir>)"
    )

    System.halt(2)
  end

  # --- all: every mode but spec, each in its own VM, one verdict per mode ---

  # Each mode is its own `mix run`, because the modes signal failure by halting the VM;
  # running them in-process would end `all` at the first red instead of reporting
  # every mode.
  @all_modes ~w(guards totality keysets reproduce delimit f4 identity oracle)

  defp all do
    header("ALL — #{Enum.join(@all_modes, ", ")} (spec excluded: it needs a spec tree)")
    mix = System.find_executable("mix") || raise "mix is not on PATH"

    results =
      for mode <- @all_modes do
        {_, status} =
          System.cmd(mix, ["run", __ENV__.file, mode],
            into: IO.stream(:stdio, :line),
            stderr_to_stdout: true
          )

        {mode, status}
      end

    IO.puts("\n== ALL — verdicts ==\n")

    for {mode, status} <- results,
        do: IO.puts("  #{if status == 0, do: "ok  ", else: "FAIL"}  #{mode}  (exit #{status})")

    failed = Enum.count(results, fn {_, st} -> st != 0 end)
    IO.puts("\n  #{length(results) - failed}/#{length(results)} modes green.")
    if failed > 0, do: System.halt(1)
  end

  # --- guards: every fail-closed condition, shown FIRING ---

  defp guards do
    header("GUARDS — each fail-closed condition, mutated and shown to refuse")

    doc = read(@paths.decisions)
    decisions = doc["decisions"]
    et_cc = Enum.find(decisions, &(&1["label"] == "ET-CC"))
    et_adj = Enum.find(decisions, &(&1["label"] == "ET-ADJ"))
    et_ctrl = Enum.find(decisions, &(&1["label"] == "ET-CTRL"))
    et_out = Enum.find(decisions, &(&1["label"] == "ET-OUT"))
    adjudicated = Enum.find(decisions, &(&1["adjudication"] != nil))

    # Guard 22's subject: a member §6.1 populated. Found by predicate rather than by key,
    # so it does not go stale if the enumeration in Part C §C.4 ever changes.
    inherited = Enum.find(decisions, &(&1["inherited_from"] != nil))

    # Guard 21's subject: a member that names BOTH directions of a split module, so the
    # mutation that drops its `(decode)` leaves a row whose test body still calls the
    # decode producer. Found by predicate rather than by key, so it does not go stale.
    decode_caller =
      Enum.find(decisions, fn d ->
        d["label"] == "ET-CC" and is_list(d["boundary"]) and
          Enum.any?(d["boundary"], &String.ends_with?(&1, " (decode)")) and
          Enum.any?(d["boundary"], &String.ends_with?(&1, " (encode)"))
      end)

    cases = [
      {"an in-scope unit with no decision", fn ds -> tl(ds) end},
      {"a decision naming a key the artefact does not have",
       fn ds -> [put_in(hd(ds), ["key"], "MCP.NoSuchTest/test nope") | ds] end},
      {"excluding_gate 4 (amendment 2 — UNREPRESENTABLE, not merely promised)",
       fn ds -> replace(ds, et_out, %{"excluding_gate" => 4}) end},
      {"an ET-CC row with no spec_anchor (AC3)",
       fn ds -> replace(ds, et_cc, %{"spec_anchor" => nil}) end},
      {"an ET-CC row carrying an excluding gate",
       fn ds -> replace(ds, et_cc, %{"excluding_gate" => 2}) end},
      {"a non-member with no excluding gate",
       fn ds -> replace(ds, et_out, %{"excluding_gate" => nil}) end},
      {"an ET-ADJ row with no consumed_at",
       fn ds -> replace(ds, et_adj, %{"consumed_at" => nil}) end},
      {"an ET-CTRL row controlling a unit that does not exist",
       fn ds -> replace(ds, et_ctrl, %{"controls" => "MCP.NoSuchTest/test nope"}) end},
      {"falsifiable on a non-member (§4/§8: a per-MEMBER field)",
       fn ds -> replace(ds, et_out, %{"falsifiable" => "yes"}) end},
      {"an ET-CC row with no falsifiable",
       fn ds -> replace(ds, et_cc, %{"falsifiable" => nil}) end},
      {"OUT-OF-SCOPE used as a fifth label (§1: it is not one of the four)",
       fn ds -> replace(ds, et_out, %{"label" => "OUT-OF-SCOPE"}) end},
      {"escalated: true with no question (§9 requires the question ON THE ROW)",
       fn ds -> replace(ds, et_out, %{"escalated" => true, "question" => nil}) end},
      {"a row with no evidence (epic ruling 7)",
       fn ds -> replace(ds, et_cc, %{"evidence" => ""}) end},
      {"an adjudicated row that is no longer escalated (26037 item 2)",
       fn ds -> replace(ds, adjudicated, %{"escalated" => false}) end},
      {"an adjudication whose raised_by is neither sweep nor PM (26046/26047)",
       fn ds ->
         replace(ds, adjudicated, %{
           "adjudication" => Map.put(adjudicated["adjudication"], "raised_by", "nobody")
         })
       end},
      {"an ET-CC row with no boundary (ruling A is decided PER BOUNDARY)",
       fn ds -> replace(ds, et_cc, %{"boundary" => nil}) end},
      {"an ET-CC row naming a boundary the boundaries file does not record",
       fn ds -> replace(ds, et_cc, %{"boundary" => ["MCP.NoSuch.Boundary"]}) end},
      {"a boundary on a row that is NOT ET-CC",
       fn ds -> replace(ds, et_out, %{"boundary" => ["MCP.Client"]}) end},
      {"an ET-CC row EVERY boundary of which is recorded DEAD (26048 item 5 — ruling A)",
       fn ds ->
         replace(ds, et_cc, %{"boundary" => ["MCP.Protocol.Messages.Resources (encode)"]})
       end},
      # The REASON is checked (MES-176): from MES-161 to MES-176 this case printed REFUSED
      # because guard 21 could not delimit a drifted row, never because of attribution.
      {"an ET-CC row calling a split module's DECODE producer without naming its (decode) direction (guard 21 — F9)",
       fn ds ->
         replace(ds, decode_caller, %{
           "boundary" =>
             Enum.reject(decode_caller["boundary"], &String.ends_with?(&1, " (decode)"))
         })
       end, ~r/without naming its \(decode\) direction \(guard 21\)\.$/},
      # Guard 22 (MES-87, §6.1). Five limbs, each mutated on its own, because a guard
      # that only ever fires on one of its conditions has three untested ones.
      {"inherited_from on a row that is NOT a member (guard 22 — §6.1/§8)",
       fn ds -> replace(ds, et_out, %{"inherited_from" => "test/mcp/client_test.exs:59"}) end},
      {"inherited_from whose file:line does not RESOLVE at this tip (guard 22)",
       fn ds ->
         replace(ds, inherited, %{"inherited_from" => "test/mcp/client_test.exs:999999"})
       end},
      {"inherited_from naming the ASSERTION rather than the helper declaration (guard 22)",
       fn ds -> replace(ds, inherited, %{"inherited_from" => "test/mcp/client_test.exs:62"}) end},
      {"inherited_from naming a real helper that contains NO assertion (guard 22)",
       fn ds -> replace(ds, inherited, %{"inherited_from" => "test/mcp/client_test.exs:83"}) end},
      {"inherited_from that is not a file:line at all (guard 22)",
       fn ds -> replace(ds, inherited, %{"inherited_from" => "do_connect/2"}) end}
    ]

    results =
      for c <- cases do
        {name, mutate, reason} =
          case c do
            {name, mutate} -> {name, mutate, nil}
            {name, mutate, reason} -> {name, mutate, reason}
          end

        path = write_tmp(%{doc | "decisions" => mutate.(decisions)})

        outcome =
          try do
            ETCCRegister.build(decisions: path)
            :ACCEPTED
          rescue
            e in RuntimeError -> {:REFUSED, first_line(Exception.message(e))}
          after
            File.rm(path)
          end

        case outcome do
          {:REFUSED, why} ->
            if reason == nil or Regex.match?(reason, why) do
              IO.puts("  REFUSED  #{name}\n           -> #{why}")
              :ok
            else
              IO.puts("  REFUSED  #{name}   <-- FOR THE WRONG REASON\n           -> #{why}")
              :error
            end

          :ACCEPTED ->
            IO.puts("  ACCEPTED #{name}   <-- THE GUARD DID NOT FIRE")
            :error
        end
      end

    # Guard 20 mutates the BOUNDARIES file rather than the decisions file: it is a
    # condition on the measurement, not on a label.
    boundaries = read(@paths.boundaries)
    dead = Enum.find(boundaries["boundaries"], &(&1["verdict"] == "dead"))

    g20 =
      [
        {"a boundary recorded DEAD with NO l2 record (guard 20 — F6)",
         fn b -> Map.put(b, "l2", nil) end},
        {"a boundary recorded DEAD whose l2 record says it was never run",
         fn b -> Map.put(b, "l2", Map.put(b["l2"], "ran", false)) end},
        {"a boundary recorded DEAD whose l2 record says LIVE",
         fn b -> Map.put(b, "l2", Map.put(b["l2"], "verdict", "live")) end}
      ]
      |> Enum.map(fn {name, mutate} ->
        rows =
          Enum.map(boundaries["boundaries"], fn b ->
            if b["id"] == dead["id"], do: mutate.(b), else: b
          end)

        path = write_tmp_named("etcc-boundaries-mutant", %{boundaries | "boundaries" => rows})

        outcome =
          try do
            ETCCRegister.build(boundaries: path)
            :ACCEPTED
          rescue
            e in RuntimeError -> {:REFUSED, first_line(Exception.message(e))}
          after
            File.rm(path)
          end

        case outcome do
          {:REFUSED, why} ->
            IO.puts("  REFUSED  #{name}\n           -> #{why}")
            :ok

          :ACCEPTED ->
            IO.puts("  ACCEPTED #{name}   <-- THE GUARD DID NOT FIRE")
            :error
        end
      end)

    results = results ++ g20

    IO.puts("\n  #{Enum.count(results, &(&1 == :ok))}/#{length(results)} guards fired.")

    # The negative control on the controls: the UNMUTATED file must still build.
    ETCCRegister.build()
    IO.puts("  CONTROL: the unmutated decisions file builds cleanly, so the guards above")
    IO.puts("           are discriminating rather than refusing everything.")

    if Enum.any?(results, &(&1 == :error)), do: System.halt(1)
  end

  # --- totality: §7, demonstrated from the COMMITTED register, not asserted ---

  defp totality do
    header("TOTALITY — recomputed from the committed register's own rows")
    r = read(@paths.register)
    counts = Enum.frequencies_by(r["rows"], & &1["label"])
    labels = ~w(ET-CC ET-CTRL ET-ADJ ET-OUT)
    sum = labels |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()

    for l <- labels, do: IO.puts("  #{String.pad_trailing(l, 8)} #{Map.get(counts, l, 0)}")
    IO.puts("  #{String.duplicate("-", 14)}")
    IO.puts("  sum      #{sum}")
    IO.puts("  in_scope #{r["totals"]["in_scope"]}   (the enumerated population)")
    IO.puts("  rows     #{length(r["rows"])}")

    IO.puts(
      "\n  every row has exactly one label: #{Enum.all?(r["rows"], &(&1["label"] in labels))}"
    )

    IO.puts(
      "  no key appears twice: #{length(Enum.uniq_by(r["rows"], & &1["key"])) == length(r["rows"])}"
    )

    IO.puts(
      "  sum == in_scope == rows: #{sum == r["totals"]["in_scope"] and sum == length(r["rows"])}"
    )

    IO.puts(
      "\n  OUT-OF-SCOPE is held apart (§1) and is NOT in the sum: #{r["totals"]["out_of_scope"]} units"
    )
  end

  # --- keysets: both ways, against the artefact ---

  defp keysets do
    header("KEY SETS — register vs artefact, BOTH ways")
    a = read(@paths.artefact)
    r = read(@paths.register)

    artefact_all = MapSet.new(a["rows"], & &1["key"])

    artefact_in =
      a["rows"]
      |> Enum.filter(&String.starts_with?(&1["file"], "test/mcp/"))
      |> MapSet.new(& &1["key"])

    reg = MapSet.new(r["rows"], & &1["key"])
    oos = MapSet.new(r["out_of_scope"], & &1["key"])

    show("register rows == artefact rows under test/mcp/", reg, artefact_in)
    show("register + out_of_scope == the whole artefact", MapSet.union(reg, oos), artefact_all)
    show("register and out_of_scope are disjoint", MapSet.intersection(reg, oos), MapSet.new())
  end

  # --- reproduce: rebuild in place and diff ---

  # Red from MES-161 (bb68d9f) to MES-229: the register was hand-edited (196 `line` fields,
  # and `provenance.decisions_md5` left at a superseded decisions file) while build() went
  # on joining the artefact's captured line. MES-229 made `line` the located one (PM
  # `35131`) and rebuilt the register, so it is green again. It goes red whenever a commit
  # moves a `test/mcp/` test without rebuilding, and that is the drift it exists to show.

  defp reproduce do
    header("REPRODUCE — rebuild the register and diff against the committed copy")
    before = File.read!(@paths.register)
    tmp = Path.join(System.tmp_dir!(), "etcc-register-reproduce.json")

    ETCCRegister.write(
      register: tmp,
      spec_md5s: read(@paths.register)["provenance"]["spec_files"]
    )

    now = File.read!(tmp)
    File.rm(tmp)

    IO.puts("  committed md5 #{md5(before)}")
    IO.puts("  rebuilt   md5 #{md5(now)}")
    IO.puts("  identical: #{before == now}")
    unless before == now, do: System.halt(1)
  end

  # --- spec: re-md5 a materialised pinned tree ---

  defp spec(dir) do
    header("SPEC FILES — re-md5 a materialised tree at 5f5440bb and diff")
    recorded = read(@paths.register)["provenance"]["spec_files"]

    for {path, expected} <- Enum.sort(recorded) do
      full = Path.join(dir, path)

      actual =
        if File.exists?(full), do: md5(File.read!(full)), else: "ABSENT"

      verdict = if actual == expected, do: "ok    ", else: "DIFFER"
      IO.puts("  #{verdict} #{expected}  #{path}")
      unless actual == expected, do: IO.puts("         got #{actual}")
    end
  end

  # --- oracle: delimit and f4's oracle covers the register's rows, all of them (MES-230) ---

  # PM `35180` Q4. `oracle_lines/2` raises when a row's name matches other than exactly
  # one declaration, and that raise is what makes delimit and f4 trust it. MES-230
  # restricts it to `register_tests/1`. Two cases, on the committed artefact:
  #
  #   * O-out: the out-of-scope `Gate8TriggerTest` row ("E1 (observed, residual 6)…") is
  #     in the artefact and is AMBIGUOUS to the unrestricted oracle (the control on the
  #     control: without it the case below shows nothing). Over `register_tests/1` the
  #     oracle does not raise, and the row is not in its population.
  #   * O-in: a planted in-scope ambiguity, an exact copy of an in-scope test's whole
  #     block written under it in a copy of its source, still raises, naming that row.
  #     The restriction drops out-of-scope rows, never an in-scope one.
  @o_out_key "MCP.Conformance.Gate8TriggerTest/test the verdict on each fixture " <>
               "E1 (observed, residual 6): an unresolvable ref reads as silent"

  defp oracle do
    header("ORACLE — delimit and f4's oracle covers exactly the register's rows")

    artefact = read(@paths.artefact)
    all_tests = Enum.filter(artefact["rows"], &(&1["test_type"] == "test"))
    tests = register_tests(artefact)
    sources = all_tests |> Enum.map(& &1["file"]) |> Enum.uniq() |> Map.new(&{&1, File.read!(&1)})

    results = [oracle_out(artefact, all_tests, tests, sources), oracle_in(tests, sources)]
    IO.puts("\n  #{Enum.count(results, &(&1 == :ok))}/#{length(results)} as expected.")
    if Enum.any?(results, &(&1 == :error)), do: System.halt(1)
  end

  defp oracle_out(artefact, all_tests, tests, sources) do
    IO.puts("  O-out — the out-of-scope Gate8TriggerTest row cannot stop the oracle")
    row = Enum.find(artefact["rows"], &(&1["key"] == @o_out_key))
    unrestricted = oracle_attempt([row], sources)
    restricted = oracle_attempt(tests, sources)
    in_population = Enum.any?(tests, &(&1["key"] == @o_out_key))

    cond do
      row == nil ->
        IO.puts("    FAIL  the row is not in the artefact, so this case shows nothing")
        :error

      not match?({:raised, "oracle: " <> _}, unrestricted) ->
        IO.puts(
          "    FAIL  control: unrestricted, the row did not raise -> #{inspect(unrestricted)}"
        )

        :error

      in_population or not match?({:ok, _}, restricted) ->
        IO.puts(
          "    FAIL  restricted: #{inspect(restricted, limit: 3)}; in population: #{in_population}"
        )

        :error

      true ->
        {:raised, why} = unrestricted
        {:ok, lines} = restricted

        IO.puts(
          "    ok  control: unrestricted it raises -> #{why}\n" <>
            "    ok  restricted: #{map_size(lines)} of #{length(all_tests)} test rows located, " <>
            "none raised, the row is not among them"
        )

        :ok
    end
  end

  defp oracle_in(tests, sources) do
    IO.puts("\n  O-in — a planted in-scope ambiguity still raises, naming its row")
    {:ok, base} = oracle_attempt(tests, sources)

    r =
      Enum.find(tests, fn r ->
        lines = String.split(sources[r["file"]], "\n")
        Enum.at(lines, base[r["key"]] - 1) =~ ~r/^\s+test "[^"#]*" do$/
      end)

    lines = String.split(sources[r["file"]], "\n")
    first = base[r["key"]]
    last = closing_end(lines, first)
    block = Enum.slice(lines, (first - 1)..(last - 1))
    planted = Enum.join(Enum.take(lines, last) ++ block ++ Enum.drop(lines, last), "\n")
    want = "oracle: #{r["key"]} matches 2 declarations in #{r["file"]}"

    case oracle_attempt(tests, Map.put(sources, r["file"], planted)) do
      {:raised, ^want} ->
        IO.puts("    ok  #{r["file"]}:#{first}-#{last} copied below itself -> #{want}")
        :ok

      other ->
        IO.puts("    FAIL  expected `#{want}`, got #{inspect(other, limit: 3)}")
        :error
    end
  end

  defp oracle_attempt(rows, sources) do
    {:ok, oracle_lines(rows, sources)}
  rescue
    e in RuntimeError -> {:raised, Exception.message(e)}
  end

  # --- f4: a row whose line lands on ANOTHER test (MES-194 F4, MES-229) ---

  # F4 on MES-194 was the silent case: a guard that delimits a unit at its captured line
  # scans whatever test that line now lands on, and reports nothing. MES-176 made guard 21
  # locate by name, and MES-229 made the register's `line` the located one. This mode is
  # the pair the PM accepted at `35131` (b), planted on the COMMITTED artefact (its real
  # drift left in place):
  #
  #   * F4-pos: member R's captured line is pointed at a neighbour test in its file that
  #     calls no producer, and R's decisions are intact. The build ACCEPTS, and the line it
  #     emits for R is R's own declaration, not the planted one.
  #   * F4-neg: the same plant, with R's (decode) boundary dropped. The build REFUSES for
  #     guard 21, naming R's OWN line. Code that trusted the planted line would scan the
  #     neighbour, find no producer call, and accept.
  #
  # A line that lands on another test is NOT refused for that alone: 262 of 994 captured
  # lines did at dea3afe, legitimately, and MES-230's re-capture took that to 0 of the 798
  # in-scope test rows. What is refused is a defect in the NAMED test's own body.
  defp f4 do
    header("F4 — a row whose captured line lands on another test")

    artefact = read(@paths.artefact)
    doc = read(@paths.decisions)
    labels = Map.new(doc["decisions"], &{&1["key"], &1["label"]})
    tests = register_tests(artefact)
    sources = tests |> Enum.map(& &1["file"]) |> Enum.uniq() |> Map.new(&{&1, File.read!(&1)})
    oracle = oracle_lines(tests, sources)
    members = tests |> Enum.filter(&(labels[&1["key"]] == "ET-CC")) |> Enum.sort_by(& &1["key"])

    with {r, ds} <- pick_decode_member(artefact, doc, members),
         t when t != nil <- quiet_neighbour(r, artefact, sources, oracle) do
      own = oracle[r["key"]]
      planted = oracle[t["key"]]
      art = mutate_rows(artefact, r["key"], %{"line" => planted})

      IO.puts(
        "  R = #{r["file"]}:#{own} (#{r["name"]})\n" <>
          "  planted line :#{planted} = #{t["name"]}, a test that calls no producer\n"
      )

      results = [f4_pos(art, r, own, planted), f4_neg(art, ds, r, own)]
      IO.puts("\n  #{Enum.count(results, &(&1 == :ok))}/#{length(results)} as expected.")
      if Enum.any?(results, &(&1 == :error)), do: System.halt(1)
    else
      _ ->
        IO.puts("  FAIL  no member found to plant")
        System.halt(1)
    end
  end

  defp f4_pos(art, r, own, planted) do
    IO.puts("  F4-pos — decisions intact: the build must ACCEPT and emit R's own line")
    path = write_tmp_named("etcc-f4-artefact", art)

    emitted =
      try do
        ETCCRegister.build(artefact: path)
        |> Map.fetch!("rows")
        |> Enum.find(&(&1["key"] == r["key"]))
        |> Map.fetch!("line")
      rescue
        e in RuntimeError -> {:refused, first_line(Exception.message(e))}
      after
        File.rm(path)
      end

    case emitted do
      ^own ->
        IO.puts("    ok  ACCEPTED; R emitted at :#{own}, not the planted :#{planted}")
        :ok

      {:refused, why} ->
        IO.puts("    FAIL  REFUSED -> #{why}")
        :error

      other ->
        IO.puts(
          "    FAIL  ACCEPTED but R emitted at :#{other} (own :#{own}, planted :#{planted})"
        )

        :error
    end
  end

  defp f4_neg(art, ds, r, own) do
    IO.puts(
      "\n  F4-neg — R's (decode) dropped: the build must REFUSE for guard 21 at R's own line"
    )

    body = Regex.escape("#{r["file"]}:#{own} calls")

    expect_refusal(
      %{artefact: art, decisions: ds},
      Regex.compile!("\\(guard 21\\)\\.\\n.*" <> body, "s"),
      full: true
    )
  end

  # --- identity: the emitted line needs an ESTABLISHED identity (MES-229 round 1) ---

  # CR finding 1 at `35147`: emitting a located line for every test row reached the rows
  # guard 21 never reads, the NON-members, and it accepted a match that cannot establish
  # identity. A test or `describe` named by an attribute matches as a bare wildcard, so
  # four different registered names all "located" at one unrelated test. That match is
  # a wildcard, not a location.
  #
  # Planted on a NON-member row R, in a file with no ET-CC row (so guard 21 never reads
  # it and the refusal can only come from line emission), in a scratch copy of the
  # sources (`source_root:`). Every other row of R's file is re-declared literally, so it
  # locates, and only R's declaration varies:
  #
  #   * I-pos: R declared literally too. The build ACCEPTS. This is the control on the
  #     control: the rewritten file is itself locatable, so the cases below discriminate.
  #   * I-none: R not declared. Refused: no `test` declaration has that name.
  #   * I-ambiguous: R declared twice. Refused: 2 `test` declarations match.
  #   * I-test-attr: R's TEST named by `@attr`, inside R's own describe. Refused: it
  #     cannot establish identity.
  #   * I-describe-attr: R's DESCRIBE named by `@attr`. Refused for the same reason.
  #
  # Each refusal must name R's key. A refusal for another row, or for another reason,
  # counts as a failure.
  defp identity do
    header("IDENTITY — a line is emitted only for a test whose identity is established")

    artefact = read(@paths.artefact)
    labels = Map.new(read(@paths.decisions)["decisions"], &{&1["key"], &1["label"]})
    in_scope = Enum.filter(artefact["rows"], &String.starts_with?(&1["file"], "test/mcp/"))

    picked =
      in_scope
      |> Enum.group_by(& &1["file"])
      |> Enum.sort()
      |> Enum.find_value(fn {file, rows} ->
        r =
          Enum.all?(rows, &(&1["test_type"] == "test" and labels[&1["key"]] != "ET-CC")) &&
            rows |> Enum.sort_by(& &1["key"]) |> Enum.find(&solo_describe?(&1, rows))

        if r, do: {file, rows, r}
      end)

    case picked do
      nil ->
        IO.puts("  FAIL  no non-member file with a single-test describe to plant on")
        System.halt(1)

      {file, rows, r} ->
        IO.puts(
          "  R = #{r["key"]}\n      (#{labels[r["key"]]}, in #{file}: #{length(rows)} test rows, none ET-CC)\n"
        )

        others = Enum.reject(rows, &(&1["key"] == r["key"]))
        mine = Regex.escape("cannot locate #{r["key"]} in #{file} to emit its line: ")

        unnamed =
          mine <> "the only declaration its name matches, at :\\d+, cannot establish identity"

        cases = [
          {"I-pos — R declared literally: ACCEPT", [decl(r)], nil},
          {"I-none — R not declared", [], mine <> "no `test` declaration has that name"},
          {"I-ambiguous — R declared twice", [decl(r), decl(r)],
           mine <> "2 `test` declarations match"},
          {"I-test-attr — R's test named by @attr", [attr_test(r)],
           unnamed <> " — its test name @mes229_name"},
          {"I-describe-attr — R's describe named by @attr", [attr_describe(r)],
           unnamed <> " — its describe name @mes229_describe"}
        ]

        results =
          Enum.map(cases, fn {name, r_decls, pattern} ->
            IO.puts("  #{name}")
            identity_case(in_scope, file, Enum.map(others, &decl/1) ++ r_decls, pattern)
          end)

        IO.puts("\n  #{Enum.count(results, &(&1 == :ok))}/#{length(results)} as expected.")
        if Enum.any?(results, &(&1 == :error)), do: System.halt(1)
    end
  end

  defp identity_case(in_scope, file, decls, pattern) do
    root = Path.join(System.tmp_dir!(), "etcc-identity-#{System.unique_integer([:positive])}")

    try do
      for f <- in_scope |> Enum.map(& &1["file"]) |> Enum.uniq() do
        dst = Path.join(root, f)
        File.mkdir_p!(Path.dirname(dst))
        File.cp!(f, dst)
      end

      File.write!(
        Path.join(root, file),
        "defmodule MES229IdentityScratch do\n  use ExUnit.Case\n\n" <>
          Enum.join(decls, "\n") <> "end\n"
      )

      case {attempt(%{source_root: root}), pattern} do
        {:accepted, nil} ->
          IO.puts("    ok  ACCEPTED")
          :ok

        {:accepted, _} ->
          IO.puts("    FAIL  ACCEPTED — the emitted line was not refused")
          :error

        {{:refused, why}, nil} ->
          IO.puts("    FAIL  REFUSED -> #{why}")
          :error

        {{:refused, why}, pattern} ->
          if Regex.match?(Regex.compile!(pattern, "u"), why) do
            IO.puts("    ok  REFUSED -> #{why}")
            :ok
          else
            IO.puts("    FAIL  REFUSED FOR THE WRONG REASON -> #{why}")
            :error
          end
      end
    after
      File.rm_rf!(root)
    end
  end

  defp solo_describe?(r, rows),
    do: r["describe"] != nil and Enum.count(rows, &(&1["describe"] == r["describe"])) == 1

  # The test's own name: the runtime name less "test " and the describe prefix.
  defp tail(%{"name" => "test " <> rest, "describe" => nil}), do: rest

  defp tail(%{"name" => "test " <> rest, "describe" => d}),
    do: String.replace_prefix(rest, d <> " ", "")

  defp decl(%{"describe" => nil} = r),
    do: "  test #{inspect(tail(r))} do\n    assert true\n  end\n"

  defp decl(%{"describe" => d} = r),
    do:
      "  describe #{inspect(d)} do\n    test #{inspect(tail(r))} do\n      assert true\n" <>
        "    end\n  end\n"

  defp attr_test(%{"describe" => d}),
    do:
      "  @mes229_name \"unrelated replacement\"\n  describe #{inspect(d)} do\n" <>
        "    test @mes229_name do\n      assert true\n    end\n  end\n"

  defp attr_describe(r),
    do:
      "  @mes229_describe \"unrelated\"\n  describe @mes229_describe do\n" <>
        "    test #{inspect(tail(r))} do\n      assert true\n    end\n  end\n"

  # --- delimit: guard 21 finds a unit by its NAME, never by its captured line (MES-176) ---

  # The artefact's `line` is ExUnit's capture at 584e115. Tests have moved since (225 of
  # 994 rows by MES-176's count; MES-161's tag inserts moved `initialize is removed` from
  # :82 to :106), and a guard that trusts the captured line either dies on a line that is
  # no longer a `test` (the loud case) or scans ANOTHER test's body and reports nothing
  # (the silent case, F4 on MES-194). Guard 21 now locates each unit by its runtime name.
  #
  # The ORACLE for where a test is, here, is gate 7's reader (`OcGateDeclarations`), not
  # the `UnitLocator` under test: a control that shares its code with what it checks can
  # only agree with it.
  #
  #   * POSITIVE — every artefact test row: the locator's line is the oracle's, its end is
  #     the `end` that closes it, and the unmutated build is accepted. The rows whose test
  #     has a multi-line attribute above it (the ticket's original suspicion) are counted
  #     and named, `initialize is removed` among them.
  #   * N1 — a row whose name no test in its file has. Refused: cannot locate.
  #   * N2 — the silent case, planted: a member whose own body calls a split module's
  #     decode producer loses its `(decode)` boundary, and its captured line is pointed at
  #     a test that calls no producer at all. Trusting the line ACCEPTS that (the false
  #     green); locating by name refuses it, naming the member's own line.
  #   * N3 — two tests with the same runtime name, in a scratch copy of the sources
  #     (`source_root:`). Refused: the locator refuses rather than guess.
  #   * L-a1, L-a2, L-b, L-c (MES-176 correction round 1, CR F1 at 32621) — N2's member,
  #     its (decode) dropped, rewritten in a scratch copy so its decode call sits where a
  #     line-sliced body never looks: a `do:` one-liner (a1), `do … end` on one line (a2),
  #     the declaration line of a multi-line test (b), and the closing-`end` line (c).
  #     Each must be refused for ATTRIBUTION (guard 21), naming the member's line — a body
  #     that loses those bytes scans nothing there and accepts.
  #   * T-after, T-rescue, T-catch, T-else (correction round 2, CR F2 at 32660) — the same
  #     member with its decode call in a clause ExUnit runs through `try(contents)` (any
  #     block other than exactly `[do: _]`). Refused for ATTRIBUTION, as above.
  #   * S-key, S-pending, S-nonliteral — shapes guard 21 cannot scan: a block key `try`
  #     does not take, a bodiless (pending) `test/1`, and a last argument that is not a
  #     literal keyword block. Each must be REFUSED by guard 21 for that named reason —
  #     never located-and-skipped, never "not found".
  #   * F-attr, F-interp, F-describe (correction round 3, CR F3 at 32697) — names with no
  #     literal identity: `test @attr` naming a DIFFERENT runtime name, `test "#{expr}"`,
  #     and `describe @attr`. Each is the only candidate for the captured row, and each
  #     must be REFUSED by guard 21 as a name it cannot establish — a wildcard that is
  #     the only match is not proof of identity.
  #
  # N1-N3 run on a RE-LINED artefact (every line the oracle's), so each one isolates its
  # own condition: with the committed lines, code that trusts the line refuses all three
  # for the unrelated drift, and a refusal for the wrong reason is counted as a failure.
  defp delimit do
    header("DELIMIT — guard 21 locates each unit by name; the captured line is not trusted")

    artefact = read(@paths.artefact)
    doc = read(@paths.decisions)
    labels = Map.new(doc["decisions"], &{&1["key"], &1["label"]})
    tests = register_tests(artefact)
    sources = tests |> Enum.map(& &1["file"]) |> Enum.uniq() |> Map.new(&{&1, File.read!(&1)})
    oracle = oracle_lines(tests, sources)
    moved = Enum.count(tests, &(&1["line"] != oracle[&1["key"]]))

    IO.puts(
      "  #{length(tests)} test rows; #{moved} captured lines are not where the test is now\n"
    )

    relined = %{artefact | "rows" => Enum.map(artefact["rows"], &reline(&1, oracle))}
    members = tests |> Enum.filter(&(labels[&1["key"]] == "ET-CC")) |> Enum.sort_by(& &1["key"])

    picked = pick_decode_member(relined, doc, members)

    results =
      [
        delimit_positive(tests, sources, oracle, members),
        delimit_n1(relined, hd(members)),
        delimit_n2(relined, picked, sources, oracle),
        delimit_n3(relined, hd(members), sources, oracle)
      ] ++
        delimit_layouts(relined, picked, sources, oracle) ++
        delimit_names(relined, picked, sources, oracle)

    IO.puts("\n  #{Enum.count(results, &(&1 == :ok))}/#{length(results)} as expected.")
    if Enum.any?(results, &(&1 == :error)), do: System.halt(1)
  end

  defp delimit_positive(tests, sources, oracle, members) do
    IO.puts("  POSITIVE — the locator agrees with the oracle on every row, and the build accepts")

    agree =
      try do
        index =
          Map.new(sources, fn {f, src} -> {f, MCP.Conformance.UnitLocator.index(src, f)} end)

        Enum.reject(tests, fn r ->
          lines = String.split(sources[r["file"]], "\n")

          case MCP.Conformance.UnitLocator.locate(index[r["file"]], r["name"]) do
            {:ok, l, e} -> l == oracle[r["key"]] and e == closing_end(lines, l)
            _ -> false
          end
        end)
      rescue
        e -> {:raised, Exception.format_banner(:error, e)}
      end

    multi = Enum.filter(members, &multi_line_attr_above?(sources[&1["file"]], oracle[&1["key"]]))

    named =
      Enum.find(
        multi,
        &String.ends_with?(
          &1["name"],
          "initialize is removed → UnsupportedProtocolVersion (-32022)"
        )
      )

    IO.puts(
      "    ET-CC rows with a multi-line attribute above their test: #{length(multi)}, " <>
        "captured line still right for #{Enum.count(multi, &(&1["line"] == oracle[&1["key"]]))}"
    )

    if named,
      do:
        IO.puts(
          "    e.g. #{named["file"]}: captured :#{named["line"]}, the test is at :#{oracle[named["key"]]}"
        )

    built =
      try do
        ETCCRegister.build()
        :accepted
      rescue
        e in RuntimeError -> {:refused, first_line(Exception.message(e))}
      end

    case {agree, built} do
      {[], :accepted} when multi != [] and named != nil ->
        IO.puts(
          "    ok  #{length(tests)}/#{length(tests)} located at the oracle's line and end; build ACCEPTED"
        )

        :ok

      _ ->
        IO.puts(
          "    FAIL  locator disagreements: #{inspect(agree, limit: 5)}; build: #{inspect(built)}"
        )

        :error
    end
  end

  defp delimit_n1(relined, row) do
    renamed = row["name"] <> " — NO SUCH TEST (MES-176 N1)"
    IO.puts("\n  N1 — #{row["file"]}: a row renamed to a name no test there has")
    art = mutate_rows(relined, row["key"], %{"name" => renamed})

    expect_refusal(
      %{artefact: art},
      ~r/guard 21 cannot locate .* no `test` declaration has that name/
    )
  end

  # R: the first member naming both directions of a split module that guard 21 refuses
  # once its (decode) is dropped, the lines right. N2 and the layout cases plant on it.
  defp pick_decode_member(relined, doc, members) do
    by_key = Map.new(doc["decisions"], &{&1["key"], &1})

    members
    |> Enum.filter(fn r ->
      b = by_key[r["key"]]["boundary"] || []

      Enum.any?(b, &String.ends_with?(&1, " (decode)")) and
        Enum.any?(b, &String.ends_with?(&1, " (encode)"))
    end)
    |> Enum.find_value(fn r ->
      ds = drop_decode(doc, r["key"])

      case attempt(%{artefact: relined, decisions: ds}) do
        {:refused, why} -> if why =~ "(guard 21).", do: {r, ds}
        :accepted -> nil
      end
    end)
  end

  defp delimit_n2(relined, picked, sources, oracle) do
    with {r, ds} <- picked,
         t when t != nil <- quiet_neighbour(r, relined, sources, oracle) do
      IO.puts(
        "\n  N2 — #{r["file"]}:#{oracle[r["key"]]} loses its (decode); its line points at :#{oracle[t["key"]]}, " <>
          "a test that calls no producer"
      )

      art = mutate_rows(relined, r["key"], %{"line" => oracle[t["key"]]})
      body = Regex.escape("#{r["file"]}:#{oracle[r["key"]]} calls")

      expect_refusal(
        %{artefact: art, decisions: ds},
        Regex.compile!("\\(guard 21\\)\\.\\n.*" <> body, "s"),
        full: true
      )
    else
      _ ->
        IO.puts("\n  N2 — FAIL: no member found to plant")
        :error
    end
  end

  # R's test rewritten in four layouts, each keeping R's own runtime name and R's own
  # decode call (read from its body), in a scratch copy of the sources.
  defp delimit_layouts(_relined, nil, _sources, _oracle) do
    IO.puts("\n  L — FAIL: no member found to plant")
    [:error]
  end

  defp delimit_layouts(relined, {r, ds}, sources, oracle) do
    lines = String.split(sources[r["file"]], "\n")
    first = oracle[r["key"]]
    last = closing_end(lines, first)
    decl = Enum.at(lines, first - 1)
    head = String.replace_suffix(decl, " do", "")
    pad = String.duplicate(" ", String.length(decl) - String.length(String.trim_leading(decl)))

    [call | _] =
      for l <- Enum.slice(lines, first..(last - 2)//1),
          [c] <- Regex.scan(~r/\b[A-Z][\w.]*\.(?:from_map|decode_[a-z_]+|parse_[a-z_]+)\(/, l),
          do: c <> "%{})"

    attribution =
      Regex.compile!(
        "\\(guard 21\\)\\.\\n.*" <> Regex.escape("#{r["file"]}:#{first} calls"),
        "s"
      )

    cannot_scan = fn why ->
      Regex.compile!("guard 21 cannot scan .*#{Regex.escape("#{r["file"]}:#{first}")}: .*" <> why)
    end

    clause = fn key, lines ->
      [decl, pad <> "  assert true", pad <> key] ++
        Enum.map(lines, &(pad <> "  " <> &1)) ++ [pad <> "end"]
    end

    layouts = [
      {"L-a1", "a `do:` one-liner", [head <> ", do: assert(#{call})"], attribution},
      {"L-a2", "`do … end` on one line", [head <> " do assert(#{call}) end"], attribution},
      {"L-b", "the call on the declaration line",
       [head <> " do assert(#{call})", pad <> "  assert true", pad <> "end"], attribution},
      {"L-c", "the call on the closing-`end` line",
       [decl, pad <> "  assert true", pad <> "  assert(#{call}) end"], attribution},
      {"T-after", "the call in an `after` clause", clause.("after", ["#{call}"]), attribution},
      {"T-rescue", "the call in a `rescue` clause", clause.("rescue", ["_ -> #{call}"]),
       attribution},
      {"T-catch", "the call in a `catch` clause", clause.("catch", ["_ -> #{call}"]),
       attribution},
      {"T-else", "the call in an `else` clause", clause.("else", ["_ -> #{call}"]), attribution},
      {"S-key", "a block key `try` does not take",
       [head <> ", do: assert(true), bogus: assert(#{call})"], cannot_scan.("\\[:bogus\\]")},
      {"S-pending", "a bodiless (pending) test", [head], cannot_scan.("bodiless")},
      {"S-nonliteral", "a last argument that is not a literal keyword block",
       [head <> ", body_of(#{call})"], cannot_scan.("not a literal keyword block")}
    ]

    for {id, what, block, expected} <- layouts do
      src =
        Enum.join(Enum.take(lines, first - 1) ++ block ++ Enum.drop(lines, last), "\n")

      IO.puts("\n  #{id} — #{r["file"]}:#{first} rewritten as #{what}, calling #{call}")
      IO.puts("    | " <> Enum.join(block, "\n    | "))

      with_scratch(sources, %{r["file"] => src}, fn root ->
        expect_refusal(%{artefact: relined, decisions: ds, source_root: root}, expected,
          full: true
        )
      end)
    end
  end

  # R's test, or its describe, renamed by an expression with no literal identity.
  defp delimit_names(_relined, nil, _sources, _oracle), do: [:error]

  defp delimit_names(relined, {r, ds}, sources, oracle) do
    lines = String.split(sources[r["file"]], "\n")
    first = oracle[r["key"]]
    decl = Enum.at(lines, first - 1)
    pad = String.duplicate(" ", String.length(decl) - String.length(String.trim_leading(decl)))

    # The nearest `describe "…" do` above R, at a shallower indent.
    d_at =
      Enum.find((first - 1)..1//-1, fn i ->
        Regex.match?(~r/^\s*describe\s+".*"\s+do\s*$/, Enum.at(lines, i - 1))
      end)

    d_line = Enum.at(lines, d_at - 1)
    [_, d_pad, d_name] = Regex.run(~r/^(\s*)describe\s+"(.*)"\s+do\s*$/, d_line)
    [_, t_name] = Regex.run(~r/test\s+"(.*)"/, decl)

    cases = [
      {"F-attr", "`test @attr` naming a DIFFERENT runtime name, its body `assert true`",
       Enum.take(lines, first - 1) ++
         [
           pad <> "@mes176_name \"a different runtime name\"",
           String.replace(decl, ~s("#{t_name}"), "@mes176_name"),
           pad <> "  assert true",
           pad <> "end"
         ] ++ Enum.drop(lines, closing_end(lines, first)), "its test name"},
      {"F-interp", "a pure-interpolation name, `test \"\#{…}\"`",
       List.replace_at(
         lines,
         first - 1,
         String.replace(decl, ~s("#{t_name}"), ~s("\#{#{inspect(t_name)}}"))
       ), "its test name"},
      {"F-describe", "`describe @attr` around it",
       List.replace_at(lines, d_at - 1, [
         d_pad <> "@mes176_describe " <> inspect(d_name),
         d_pad <> "describe @mes176_describe do"
       ]), "its describe name"}
    ]

    for {id, what, new_lines, why} <- cases do
      src = new_lines |> List.flatten() |> Enum.join("\n")
      IO.puts("\n  #{id} — #{r["file"]}: R (#{r["name"]}) under #{what}")

      with_scratch(sources, %{r["file"] => src}, fn root ->
        expect_refusal(
          %{artefact: relined, decisions: ds, source_root: root},
          Regex.compile!(
            "guard 21 cannot scan .*" <> Regex.escape(r["file"]) <> ":\\d+: " <> why
          ),
          full: true
        )
      end)
    end
  end

  # A scratch copy of `sources` with `overrides` applied, removed afterwards.
  defp with_scratch(sources, overrides, fun) do
    root = Path.join(System.tmp_dir!(), "etcc-delimit-#{System.unique_integer([:positive])}")

    try do
      for {f, src} <- Map.merge(sources, overrides) do
        File.mkdir_p!(Path.join(root, Path.dirname(f)))
        File.write!(Path.join(root, f), src)
      end

      fun.(root)
    after
      File.rm_rf!(root)
    end
  end

  defp delimit_n3(relined, row, sources, oracle) do
    root = Path.join(System.tmp_dir!(), "etcc-delimit-n3-#{System.unique_integer([:positive])}")

    try do
      for {f, src} <- sources do
        File.mkdir_p!(Path.join(root, Path.dirname(f)))
        File.write!(Path.join(root, f), src)
      end

      lines = String.split(sources[row["file"]], "\n")
      first = oracle[row["key"]]
      last = closing_end(lines, first)
      {head, tail} = Enum.split(lines, last)
      copy = Enum.slice(lines, (first - 1)..(last - 1))
      File.write!(Path.join(root, row["file"]), Enum.join(head ++ [""] ++ copy ++ tail, "\n"))

      IO.puts("\n  N3 — a scratch copy of #{row["file"]} declares :#{first}'s test twice")

      expect_refusal(
        %{artefact: relined, source_root: root},
        ~r/guard 21 cannot locate .* 2 `test` declarations match/
      )
    after
      File.rm_rf!(root)
    end
  end

  # A test in R's file, other than R, whose body calls no decode-side producer at all —
  # by a pattern WIDER than guard 21's (any `.from_map(`/`.decode_`/`.parse_` call).
  defp quiet_neighbour(r, relined, sources, oracle) do
    lines = String.split(sources[r["file"]], "\n")

    relined["rows"]
    |> Enum.filter(
      &(&1["file"] == r["file"] and &1["test_type"] == "test" and &1["key"] != r["key"])
    )
    |> Enum.sort_by(& &1["key"])
    |> Enum.find(fn t ->
      l = oracle[t["key"]]
      body = Enum.slice(lines, l..(closing_end(lines, l) - 2)//1)
      not Enum.any?(body, &Regex.match?(~r/\.(from_map|decode_[a-z_]+|parse_[a-z_]+)\(/, &1))
    end)
  end

  defp drop_decode(doc, key) do
    ds =
      Enum.map(doc["decisions"], fn d ->
        if d["key"] == key,
          do:
            Map.update!(
              d,
              "boundary",
              &Enum.reject(&1, fn b -> String.ends_with?(b, " (decode)") end)
            ),
          else: d
      end)

    %{doc | "decisions" => ds}
  end

  defp mutate_rows(art, key, changes),
    do: %{
      art
      | "rows" =>
          Enum.map(art["rows"], &if(&1["key"] == key, do: Map.merge(&1, changes), else: &1))
    }

  # Only the rows the register emits are re-lined: the oracle covers exactly those
  # (`register_tests/1`), and an out-of-scope row's line is never emitted (MES-230).
  defp reline(%{"test_type" => "test", "key" => k, "file" => @in_scope <> _} = r, oracle),
    do: %{r | "line" => Map.fetch!(oracle, k)}

  defp reline(r, _oracle), do: r

  defp expect_refusal(inputs, pattern, opts \\ []) do
    case attempt(inputs, opts) do
      {:refused, why} ->
        shown = first_line(why)

        if Regex.match?(pattern, why) do
          IO.puts("    ok  REFUSED -> #{shown}")
          :ok
        else
          IO.puts("    FAIL  REFUSED FOR THE WRONG REASON -> #{shown}")
          :error
        end

      :accepted ->
        IO.puts("    FAIL  ACCEPTED — guard 21 did not fire")
        :error
    end
  end

  # Writes each mutated input to a temp file and builds. Returns :accepted or
  # {:refused, message} — the whole message with `full: true`, else its first line.
  defp attempt(inputs, opts \\ []) do
    paths =
      for {k, v} <- inputs, k in [:artefact, :decisions], into: %{} do
        {k, write_tmp_named("etcc-delimit-#{k}", v)}
      end

    build_opts =
      Enum.to_list(paths) ++ Enum.reject(inputs, fn {k, _} -> k in [:artefact, :decisions] end)

    try do
      ETCCRegister.build(build_opts)
      :accepted
    rescue
      e in RuntimeError ->
        msg = Exception.message(e)
        {:refused, if(Keyword.get(opts, :full), do: msg, else: first_line(msg))}
    after
      Enum.each(paths, fn {_, p} -> File.rm(p) end)
    end
  end

  # The rows the register emits a line for: `test` rows under `test/mcp/`. The oracle
  # runs over these and nothing else (MES-230, PM `35180` Q4). Before MES-230 it ran
  # over every artefact row, and the re-captured artefact's out-of-scope
  # `Gate8TriggerTest` row, which a `for`-generated template in its own describe also
  # matches, stopped delimit and f4 for a row the register never locates. `oracle`
  # below shows the restriction drops that row and no in-scope ambiguity.
  defp register_tests(artefact),
    do:
      Enum.filter(
        artefact["rows"],
        &(&1["test_type"] == "test" and String.starts_with?(&1["file"], @in_scope))
      )

  # key -> the line gate 7's reader puts that test's declaration at. Exactly one
  # declaration must match, or the oracle itself is not usable and the mode stops.
  defp oracle_lines(rows, sources) do
    decls =
      Map.new(sources, fn {f, src} ->
        {:ok, ds} = OcGateDeclarations.parse(src, f)
        {f, Enum.map(ds, &{oracle_pattern(&1), &1.line})}
      end)

    Map.new(rows, fn r ->
      case for({re, l} <- decls[r["file"]], Regex.match?(re, r["name"]), do: l) do
        [l] -> {r["key"], l}
        ls -> raise "oracle: #{r["key"]} matches #{length(ls)} declarations in #{r["file"]}"
      end
    end)
  end

  defp oracle_pattern(%{describe: d, name: n}) do
    Regex.compile!(
      "\\A" <> "test " <> if(d, do: rendered(d) <> " ", else: "") <> rendered(n) <> "\\z",
      "u"
    )
  end

  # `OcGateDeclarations` renders a literal name as itself and an interpolated one as
  # its source, `"…#{x}…"`; the latter becomes a pattern with `.+?` per interpolation.
  defp rendered(s) do
    with "\"" <> _ <- s,
         {:ok, {:<<>>, _, parts}} <- Code.string_to_quoted(s) do
      Enum.map_join(parts, &if(is_binary(&1), do: Regex.escape(&1), else: ".+?"))
    else
      _ -> Regex.escape(s)
    end
  end

  # The `end` at the declaration's own indentation — the delimiter guard 21 used before
  # MES-176, valid here because the line it starts from is the oracle's.
  defp closing_end(lines, line) do
    first = Enum.at(lines, line - 1)

    closing =
      String.duplicate(" ", String.length(first) - String.length(String.trim_leading(first))) <>
        "end"

    line + 1 + Enum.find_index(Enum.drop(lines, line), &(&1 == closing))
  end

  # Some module attribute in the run of statements directly above the declaration spans
  # more than one line: the run holds a line that is not where an attribute starts.
  defp multi_line_attr_above?(src, line) do
    run =
      src
      |> String.split("\n")
      |> Enum.take(line - 1)
      |> Enum.reverse()
      |> Enum.take_while(&(String.trim(&1) != "" and not Regex.match?(~r/^\s*(end|.* do)$/, &1)))
      |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))

    run != [] and String.starts_with?(String.trim_leading(List.last(run)), "@") and
      Enum.any?(run, &(not String.starts_with?(String.trim_leading(&1), "@")))
  end

  # --- helpers ---

  defp read(path), do: path |> File.read!() |> Jason.decode!()

  defp replace(decisions, target, changes) do
    Enum.map(decisions, fn d ->
      if d["key"] == target["key"], do: Map.merge(d, changes), else: d
    end)
  end

  defp write_tmp(doc), do: write_tmp_named("etcc-decisions-mutant", doc)

  defp write_tmp_named(stem, doc) do
    path = Path.join(System.tmp_dir!(), "#{stem}-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(doc))
    path
  end

  defp show(label, a, b) do
    IO.puts("  #{if MapSet.equal?(a, b), do: "ok    ", else: "DIFFER"} #{label}")

    unless MapSet.equal?(a, b) do
      IO.puts("         only in first:  #{MapSet.difference(a, b) |> Enum.take(3) |> inspect()}")
      IO.puts("         only in second: #{MapSet.difference(b, a) |> Enum.take(3) |> inspect()}")
      System.halt(1)
    end
  end

  defp md5(bin), do: :crypto.hash(:md5, bin) |> Base.encode16(case: :lower)

  defp first_line(msg), do: msg |> String.split("\n") |> hd()

  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

ETCCRegisterControls.run(System.argv())

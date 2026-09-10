# Controls for the ET-CC register (MES-81 / B2a).
#
#     mix run conformance/controls/etcc_register_controls.exs guards
#     mix run conformance/controls/etcc_register_controls.exs totality
#     mix run conformance/controls/etcc_register_controls.exs keysets
#     mix run conformance/controls/etcc_register_controls.exs reproduce
#     mix run conformance/controls/etcc_register_controls.exs spec <dir>
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
  alias MCP.Conformance.ETCCRegister

  @paths ETCCRegister.paths()

  def run(["guards"]), do: guards()
  def run(["totality"]), do: totality()
  def run(["keysets"]), do: keysets()
  def run(["reproduce"]), do: reproduce()
  def run(["spec", dir]), do: spec(dir)

  def run(_) do
    IO.puts("usage: guards | totality | keysets | reproduce | spec <dir>")
    System.halt(2)
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
      {"an ET-CC row calling a split module's DECODE producer without naming its (decode) direction (guard 21 — F9)",
       fn ds ->
         replace(ds, decode_caller, %{
           "boundary" =>
             Enum.reject(decode_caller["boundary"], &String.ends_with?(&1, " (decode)"))
         })
       end},
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
      for {name, mutate} <- cases do
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
            IO.puts("  REFUSED  #{name}\n           -> #{why}")
            :ok

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

# A3 escalation rulings — MES-110. Rules A, B and C of match-relation.md, each
# shown FIRING on a planted input and NOT firing on its near miss, through the
# real generator (A6 / A7c), and each guard shown ABLE to fail.
#
#     mix run conformance/controls/a3_escalation_rulings_controls.exs rules
#     mix run conformance/controls/a3_escalation_rulings_controls.exs mutation
#     mix run conformance/controls/a3_escalation_rulings_controls.exs all
#
# THE RULES, as match-relation.md states them:
#
#   A (§2)  an all-silent claim is NO MATCH at any arity; the generator REFUSES
#           an all-silent edge record and names the rule.
#   B (§6)  an `oc:none` token on an EDGE-BEARING member is a claim-level
#           unmatched record: state 3 lexically, a registered search, and one
#           native id per claim across the bucket-1 and claim-level ids TOGETHER;
#           on an edge-less member it is refused.
#   C (§3)  every escalation is owned, and an inconsistent_verdict_pair carries a
#           cause from a closed set; a cause on an edge that buckets is refused.
#
# And the consequence rule A has for G20: an inherited B2b token whose edge rule
# A refused is accounted for ONLY by that member's own `no-axis-contact` record
# naming it as `near_miss_tag`.
#
# THE DISCIPLINES
#
#   * The refusal must NAME the rule. "It raised" is not "rule A caught it": a
#     mutation can trip an unrelated guard first (G23 runs before rule B's own
#     checks, for instance), and a bare rescue reads both as success.
#   * Every firing case has a NEAR MISS that builds — the closest input the rule
#     must not fire on. Without it a rule refusing everything passes.
#   * The unmutated build runs FIRST, as the negative control, and again LAST.
#   * `mutation` recompiles `MCP.Conformance.Crosswalk` IN MEMORY with one
#     guard neutralised at a time and requires the case that guard is named for
#     to go red — so each case is shown to be about its guard and not about
#     something upstream of it. Nothing is written to disk (S8-14): the
#     original module is recompiled in an `after`.

defmodule A3EscalationRulingsControls do
  @harness "/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js"
  @client "conformance/data/crosswalk-edges-client.json"
  @server "conformance/data/crosswalk-edges-server.json"
  @residual "conformance/data/crosswalk-edges.json"
  @crosswalk_src "conformance/lib/mcp/conformance/crosswalk.ex"

  def run(argv) do
    # The generator reports every successful build; a control running it a
    # dozen times needs only the verdicts.
    Mix.shell(Mix.Shell.Quiet)
    dispatch(argv)
  end

  defp dispatch(["rules"]), do: rules()
  defp dispatch(["mutation"]), do: mutation()

  defp dispatch(["all"]) do
    rules()
    mutation()
    IO.puts("\n== BOTH MODES GREEN ==\n")
  end

  defp dispatch(_) do
    IO.puts("usage: rules | mutation | all")
    System.halt(2)
  end

  # === the cases, as data, so `rules` and `mutation` drive the SAME inputs ===

  # {id, rule, what, which file is mutated, mutation fun, fragment the refusal
  # must carry — or :builds for a near miss}
  defp cases do
    client = read(@client)
    server = read(@server)

    multi = Enum.find(client["edges"], &(length(&1["axes"]) > 1))
    name_pair = Enum.find(client["edges"], &(&1["escalation_cause"] != nil))

    four_a =
      Enum.find(client["edges"] ++ server["edges"], fn e ->
        Enum.any?(e["axes"], &(&1["verdict"] == "contradicts")) and e["escalation_cause"] == nil
      end)

    four_a_file = if four_a in client["edges"], do: :client, else: :server
    # A claim-level row that SUPERSEDES no inherited token. The rule-A rows
    # (NAC03's elicitation claim) do, so moving or un-tagging one trips G20
    # before rule B is ever reached — measured, and the reason B1 names its rule.
    claim_row = Enum.find(client["claims_without_an_edge"], &(&1["search_id"] == "CLV01"))

    b1_same_slug =
      Enum.find(
        client["declared_unmatched"],
        &(String.starts_with?(&1["tag"], "oc:none/no-oc-scenario/") and
            &1["claim_the_slot_names"] not in [nil, claim_row["claim"]])
      )

    edgeless = hd(client["declared_unmatched"])
    superseding = Enum.find(client["declared_unmatched"], &(&1["search_id"] == "NAC01"))

    [
      {"A1", "A",
       "an all-silent edge (every axis of a #{length(multi["axes"])}-axis check silent) is refused",
       :client, fn d -> swap_edge(d, multi, silence(multi)) end, ":no_axis_contact_is_no_match"},
      {"A1n", "A",
       "NEAR MISS: the same edge with ONE axis agreeing and the rest silent builds (partial)",
       :client, fn d -> swap_edge(d, multi, one_agrees(multi)) end, :builds},
      {"B1", "B", "a claim-level record moved onto an EDGE-LESS member is refused", :client,
       fn d -> swap_claim(d, claim_row, %{claim_row | "member" => edgeless["member"]}) end,
       ":claim_level_record_on_a_member_with_no_edge"},
      # A token that is ABSENT, or that resolves, is refused one guard earlier —
      # G23b requires the entry's kind to equal the row's reason slug, and
      # neither has one (measured: `:entry_kind_is_not_the_rows_reason_slug`).
      # So rule B's state-3 limb is reachable only by a token whose slug is
      # right and whose native id is not: outside the charset `decode/1` holds.
      {"B2", "B",
       "a claim-level token with the right slug and a malformed native id is refused as not state 3",
       :client,
       fn d ->
         swap_claim(d, claim_row, %{claim_row | "tag" => "oc:none/no-oc-scenario/has a space"})
       end, ":claim_level_tag_is_not_state_3"},
      {"B3", "B",
       "a claim-level native id that a bucket-1 row uses for a DIFFERENT claim is refused (the union index)",
       :client, fn d -> swap_claim(d, claim_row, %{claim_row | "tag" => b1_same_slug["tag"]}) end,
       "declared_claim_index/1 refused the bucket-1 and claim-level ids"},
      {"Bn", "B",
       "NEAR MISS: the committed claim-level record, on its edge-bearing member, builds", :client,
       & &1, :builds},
      {"C1", "C", "an inconsistent_verdict_pair edge with its cause REMOVED is refused", :client,
       fn d -> swap_edge(d, name_pair, Map.delete(name_pair, "escalation_cause")) end,
       ":escalation_has_no_cause"},
      {"C2", "C", "a cause OUTSIDE the closed set is refused", :client,
       fn d -> swap_edge(d, name_pair, %{name_pair | "escalation_cause" => "vibes"}) end,
       ":escalation_cause_outside_the_closed_set"},
      {"C3", "C",
       "a cause on a contradicting edge under a RED check (4a, which buckets) is refused",
       four_a_file,
       fn d -> swap_edge(d, four_a, Map.put(four_a, "escalation_cause", "provenance")) end,
       ":escalation_cause_on_an_edge_that_buckets"},
      {"Cn", "C", "NEAR MISS: that same 4a edge with NO cause builds — a red pair needs none",
       four_a_file, & &1, :builds},
      {"G20", "A→G20",
       "a no-axis-contact row that stops naming its near_miss_tag leaves the inherited B2b token unaccounted for",
       :client,
       fn d ->
         swap_du(d, superseding, Map.delete(superseding, "near_miss_tag"))
       end, "G20 —"}
    ]
  end

  # === rules — every case through the real generator ========================

  defp rules do
    header("RULES — A, B and C (match-relation.md, MES-110) through the real generator")
    require_harness!()

    verdict(
      "NEGATIVE CONTROL FIRST: the unmutated build succeeds",
      build(:client, & &1) == :built
    )

    halt_unless(build(:client, & &1) == :built)

    for {id, rule, what, file, fun, expect} <- cases() do
      outcome = build(file, fun)
      ok = judged(outcome, expect)
      IO.puts("  #{if ok, do: "ok  ", else: "FAIL"}  #{id} [rule #{rule}] #{what}")
      IO.puts("        #{describe(outcome)}")
      halt_unless(ok)
    end

    verdict(
      "and the unmutated build still succeeds AFTER the mutations",
      build(:client, & &1) == :built
    )
  end

  # === mutation — each guard neutralised, its named case must go red ========
  #
  # Each entry: the case ids it must turn red, the source edit that removes the
  # guard, and a label. The edit is asserted to APPLY (a replacement that finds
  # nothing is a no-op mutation, which would count as caught and prove nothing).
  defp mutations do
    [
      {"rule A's refusal (axis_contact/1 returns :ok for an all-silent edge)", ["A1"],
       "if axes != [] and Enum.all?(axes, &(&1.verdict == :silent)) do", "if false do"},
      {"rule B's edge-bearing limb (claim_level_problems/3 skips the with_edges check)", ["B1"],
       "if MapSet.member?(with_edges, key),", "if true,"},
      {"rule B's state-3 limb (claim_level_problems/3 accepts any token)", ["B2"],
       "{:declared_unmatched, _} -> []", "_ -> []"},
      {"rule B's union (claim_index_rows/2 drops the claim-level rows)", ["B3"],
       "Enum.map(claim_level, &{&1[\"tag\"], &1[\"claim\"]})", "[]"},
      {"rule C's cause requirement (a missing cause is accepted)", ["C1"],
       "is_nil(cause) ->\n        {:error, {:escalation_has_no_cause, reason, @escalation_causes}}",
       "is_nil(cause) ->\n        {:ok, owned(reason, %{})}"},
      {"rule C's closed set (any cause is accepted)", ["C2"],
       "cause not in @escalation_causes ->", "false ->"},
      {"rule C's stray-cause refusal (a cause on a bucketing edge is accepted)", ["C3"],
       "{:error, {:escalation_cause_on_an_edge_that_buckets, bucket, cause}}", "{:ok, %{}}"},
      {"G20's supersession (superseded_tokens/1 names nothing, so the COMMITTED build must go red)",
       ["NEG"], "match?(\"oc:none/no-axis-contact/\" <> _, r[\"tag\"]),", "false,"}
    ]
  end

  defp mutation do
    header("MUTATION — each guard removed in memory; the case it is named for must go RED")
    require_harness!()

    source = File.read!(@crosswalk_src)
    by_id = Map.new(cases(), fn {id, _, _, file, fun, expect} -> {id, {file, fun, expect}} end)

    try do
      for {label, ids, from, to} <- mutations() do
        halt_unless_applies(source, from, label)
        recompile!(String.replace(source, from, to))

        red =
          Enum.map(ids, fn
            "NEG" ->
              {"the unmutated inputs", build(:client, & &1) != :built}

            id ->
              {file, fun, expect} = Map.fetch!(by_id, id)
              {id, not judged(build(file, fun), expect)}
          end)

        recompile!(source)
        ok = Enum.all?(red, &elem(&1, 1))

        IO.puts(
          "  #{if ok, do: "ok  ", else: "FAIL"}  #{label}\n        red: " <>
            Enum.map_join(red, ", ", fn {id, r} -> "#{id}=#{r}" end)
        )

        halt_unless(ok)
      end

      # And with every guard restored, every case is green again — so the red
      # above was the mutation's and not a state the run left behind.
      restored = Enum.all?(cases(), fn {_, _, _, f, fun, e} -> judged(build(f, fun), e) end)
      verdict("every case green again with the original module restored", restored)
      halt_unless(restored)
    after
      recompile!(source)
    end
  end

  # === plumbing =============================================================

  defp judged(:built, :builds), do: true
  defp judged({:refused, msg}, expect) when is_binary(expect), do: String.contains?(msg, expect)
  defp judged(_, _), do: false

  defp describe(:built), do: "built"
  defp describe({:refused, msg}), do: "refused: " <> String.slice(first_lines(msg), 0, 220)

  defp first_lines(msg), do: msg |> String.split("\n") |> Enum.take(3) |> Enum.join(" / ")

  # The mutated file takes its slot; the other two are the committed ones.
  defp build(which, fun) do
    {slot, src} = if which == :client, do: {0, @client}, else: {1, @server}
    mutated = write_tmp(fun.(read(src)))
    edges = List.replace_at([@client, @server, @residual], slot, mutated)
    out = tmp()

    try do
      Mix.Task.rerun("conformance.crosswalk", Enum.flat_map(edges, &["--edges", &1]) ++ args(out))
      :built
    rescue
      e in Mix.Error -> {:refused, Exception.message(e)}
    after
      File.rm(mutated)
      File.rm(out)
    end
  end

  defp args(out) do
    [
      "--manifest",
      "docs/conformance/in-scope-2026-07-28.json",
      "--denominator",
      "docs/conformance/bucket-0-2026-07-28.json",
      "--register",
      "docs/conformance/etcc-register.json",
      "--attribution",
      "docs/conformance/etcc-attribution.json",
      "--a3-axes",
      "docs/conformance/oc-axes-2026-07-28.json",
      "--c1-axes",
      "conformance/data/oc-axes-c1.json",
      "--emitting-sites",
      "docs/conformance/oc-emitting-sites-2026-07-28.json",
      "--harness",
      @harness,
      "-o",
      out
    ]
  end

  defp silence(edge),
    do: %{edge | "axes" => Enum.map(edge["axes"], &%{&1 | "verdict" => "silent"})}

  defp one_agrees(edge) do
    [h | t] = edge["axes"]

    %{
      edge
      | "axes" => [%{h | "verdict" => "agrees"} | Enum.map(t, &%{&1 | "verdict" => "silent"})]
    }
  end

  defp swap_edge(doc, old, new), do: swap(doc, "edges", old, new)
  defp swap_claim(doc, old, new), do: swap(doc, "claims_without_an_edge", old, new)
  defp swap_du(doc, old, new), do: swap(doc, "declared_unmatched", old, new)

  # Exactly ONE record is replaced, or the case is not the case it is named.
  defp swap(doc, coll, old, new) do
    n = Enum.count(doc[coll], &(&1 == old))

    if n != 1 do
      IO.puts("  CONTROL DEFECT: #{coll} holds #{n} copies of the record a case targets")
      System.halt(1)
    end

    update_in(doc, [coll], fn rs -> Enum.map(rs, &if(&1 == old, do: new, else: &1)) end)
  end

  defp halt_unless_applies(source, from, label) do
    if not String.contains?(source, from) do
      IO.puts("  NO-OP MUTATION: #{label} — the guard's text is not in #{@crosswalk_src}")
      System.halt(1)
    end
  end

  defp recompile!(source) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source, @crosswalk_src)
  after
    Code.put_compiler_option(:ignore_module_conflict, false)
  end

  defp require_harness! do
    if not File.exists?(@harness) do
      IO.puts("CONTROL DID NOT FIRE (not a result): the harness build is absent at #{@harness}")
      System.halt(1)
    end
  end

  defp tmp, do: Path.join(System.tmp_dir!(), "mes110-#{System.unique_integer([:positive])}.json")

  defp write_tmp(doc) do
    path = tmp()
    File.write!(path, Jason.encode!(doc))
    path
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp header(t), do: IO.puts("\n== #{t} ==\n")
  defp verdict(label, true), do: IO.puts("  ok    #{label}")
  defp verdict(label, false), do: IO.puts("  FAIL  #{label}")
  defp halt_unless(true), do: :ok
  defp halt_unless(false), do: System.halt(1)
end

A3EscalationRulingsControls.run(System.argv())

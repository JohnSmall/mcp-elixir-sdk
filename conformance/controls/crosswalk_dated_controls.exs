# Controls for G30's DATED limb (MES-234) and for the artefacts its regeneration moved.
#
#     mix run conformance/controls/crosswalk_dated_controls.exs all
#
# Every mutant runs the REAL tool (the crosswalk generator, `buckets --check`, the noop control,
# G33) over a mutated input, and passes only if that tool exits non-zero AND names the expected
# refusal. A mutant that is refused for some other reason is a FAIL: it tripped a different guard.
# Each mutation restores the original bytes in an `after` block, and the run ends by checking that
# every touched path is byte-identical to how it started.
#
# WHY A SCRIPT AND NOT AN ExUnit TEST: these rewrite authored inputs and committed artefacts and
# re-run whole builds. The decision logic is unit-tested in
# test/conformance/crosswalk_dated_evidence_test.exs, so gate 5 covers it.
#
# M3 writes ONE unreachable commit object (git commit-tree, no ref), because "not an ancestor of
# HEAD" cannot be shown without a commit that is not one. It is garbage for `git gc`.

defmodule CrosswalkDatedControls do
  alias MCP.Conformance.Crosswalk

  @harness "/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js"
  @server "conformance/data/crosswalk-edges-server.json"
  @all_edges [
    "conformance/data/crosswalk-edges-client.json",
    @server,
    "conformance/data/crosswalk-edges.json"
  ]
  @crosswalk "docs/conformance/crosswalk-2026-07-28.json"
  @view_4a "docs/conformance/buckets/bucket-4a-2026-07-28.json"
  @ledger "test/fixtures/conformance/string-citations-ledger.json"
  @at "bd99a3945f2885a943ac736b8b2d33422c97ccc0"
  @absent_at_bd99a39 "listener_port_race_test.exs"

  def run(["all"]) do
    unless File.exists?(@harness), do: halt("HARNESS ABSENT at #{@harness}")
    pins_path = Crosswalk.dated_pins_path()
    watched = [@server, pins_path, @crosswalk, @view_4a, @ledger]
    before = Map.new(watched, &{&1, File.read!(&1)})

    results = positive() ++ mutants()

    after_ok = Enum.all?(watched, &(File.read!(&1) == before[&1]))
    verdict("every touched path is byte-identical to how it started", after_ok)

    failed = Enum.count(results ++ [after_ok], &(!&1))
    IO.puts("\n  #{length(results) + 1 - failed}/#{length(results) + 1} green.")
    if failed > 0, do: System.halt(1)
  end

  def run(_), do: halt("usage: mix run conformance/controls/crosswalk_dated_controls.exs all")

  # --- positive controls ----------------------------------------------------

  defp positive do
    header("POSITIVE — the unmutated tree")
    out = tmp()
    {text, status} = generate(out, @all_edges)
    a = if status == 0, do: out |> File.read!() |> Jason.decode!(), else: %{}
    File.rm(out)
    g30 = a["citation_verbatim_guard"] || %{}
    dated = g30["dated_limb"] || %{}

    [
      verdict("the generator exits 0 (#{first_refusal(text)})", status == 0),
      verdict(
        "G30 has no defects and the dated limb read #{inspect(dated["records_dated"])} records " <>
          "at #{inspect(dated["commits"])}, placed #{inspect(get_in(g30, ["quotes_placed_by_window_kind", "et@bd99a39"]))}",
        g30["defects"] == [] and dated["records_dated"] == 8 and dated["commits"] == [@at]
      ),
      exits_zero("buckets --check", ["conformance.buckets", "--check"]),
      exits_zero("G33", ["conformance.string_citations"]),
      exits_zero("crosswalk_controls noop", [
        "run",
        "conformance/controls/crosswalk_controls.exs",
        "noop"
      ])
    ]
  end

  # --- mutants --------------------------------------------------------------

  defp mutants do
    header("MUTANTS — each must be refused, BY NAME")
    orphan = orphan_commit()
    tip = git!(["rev-parse", "HEAD"])

    [
      gen(
        "M0  a planted non-verbatim quote in an UNDATED edge",
        ["not_verbatim_at_any_cited_address", "== 7"],
        [{@server, &plant_undated/1}]
      ),
      gen(
        "M1  a planted non-verbatim quote at a DATED address",
        ["not_verbatim_at_any_cited_address", "et@bd99a39", "-32_023"],
        [{@server, &plant_dated/1}]
      ),
      gen(
        "M2a a commit that is not a full sha (0000000)",
        ["dated_commit_unresolved"],
        recommit("0000000")
      ),
      gen(
        "M2b a full sha naming no commit",
        ["dated_commit_unresolved"],
        recommit(String.duplicate("1", 40))
      ),
      gen(
        "M3  a commit that is not an ancestor of HEAD (orphan #{String.slice(orphan, 0, 7)})",
        ["dated_commit_not_ancestor"],
        recommit(orphan)
      ),
      gen(
        "M4  evidence_at dropped from all eight (main's state, pins kept)",
        ["dated_pin_unused"],
        [{@server, &edit_dated(&1, fn e -> pop(e, "evidence_at") end)}]
      ),
      gen(
        "M5  dated at the TIP instead (pins and leaves agree): the quotes are not there",
        ["G30 — 14 quoted", "not_verbatim_at_any_cited_address"],
        recommit(tip, rename_leaf: true)
      ),
      gen("M6  a leaf that no longer names the commit", ["dated_leaf_unnamed"], [
        {@server,
         &edit_first_dated(&1, fn e ->
           update(e, "evidence", fn ev -> String.replace_prefix(ev, "At bd99a39, ", "") end)
         end)}
      ]),
      gen("N1  a ninth evidence_at record", ["dated_over_ceiling", "dated_not_pinned"], [
        {@server, &ninth/1}
      ]),
      gen("N2  a dated record with no owner (pin agrees)", ["dated_without_owner"], [
        {@server,
         &edit_first_dated(&1, fn e -> update(e, "evidence_at", fn at -> pop(at, "owner") end) end)},
        {Crosswalk.dated_pins_path(), &edit_first_pin(&1, fn p -> pop(p, "owner") end)}
      ]),
      gen("N3  a dated record that is not in the pinned set", ["dated_not_pinned"], [
        {Crosswalk.dated_pins_path(), &update(&1, "records", fn rs -> tl(rs) end)}
      ]),
      gen(
        "N4  the pinned set's ceiling raised above the compiled one",
        ["dated_ceiling_raised"],
        [{Crosswalk.dated_pins_path(), &put(&1, "ceiling", 9)}]
      ),
      gen("N5  a cited file that does not exist at the commit", ["dated_file_absent"], [
        {@server,
         &edit_first_dated(&1, fn e ->
           update(
             e,
             "evidence",
             fn ev ->
               String.replace(ev, "dispatch_test.exs", @absent_at_bd99a39, global: false)
             end
           )
         end)}
      ]),
      gen("N6  a pin no dated record uses", ["dated_pin_unused"], [
        {@server, &edit_first_dated(&1, fn e -> pop(e, "evidence_at") end)}
      ]),
      tool(
        "M7  a hand-edited committed crosswalk leaf: noop goes red",
        ["run", "conformance/controls/crosswalk_controls.exs", "noop"],
        ["DIFFERS    crosswalk"],
        [{@crosswalk, &edit_bytes(&1, "At bd99a39, ", "At bd99a39,  ")}]
      ),
      tool(
        "M8  bucket-4a restored from main: buckets --check goes red",
        ["conformance.buckets", "--check"],
        ["differ from a fresh projection (1)"],
        [{@view_4a, fn _ -> git!(["show", "main:" <> @view_4a], trim: false) end}]
      ),
      gen_with(
        "M9  main's moduledoc example (client and edges only)",
        ["G24"],
        Enum.reject(@all_edges, &(&1 == @server)),
        []
      ),
      tool(
        "M10 a G33 dated row moved to another commit",
        ["conformance.string_citations"],
        ["G33"],
        [
          {@ledger,
           &edit_bytes(
             &1,
             ~s("at":"#{@at}","target":"test/mcp/server/dispatch_test.exs"),
             ~s("at":"#{tip}","target":"test/mcp/server/dispatch_test.exs")
           )}
        ]
      )
    ]
  end

  # --- mutations ------------------------------------------------------------

  defp plant_undated(doc) do
    edges = doc["edges"]

    i =
      Enum.find_index(
        edges,
        &(not has?(&1, "evidence_at") and
            String.contains?(&1["evidence"] || "", ~s(assert r["ttlMs"] == 0)))
      )

    put(
      doc,
      "edges",
      List.update_at(
        edges,
        i,
        &update(&1, "evidence", fn ev ->
          String.replace(ev, ~s(r["ttlMs"] == 0), ~s(r["ttlMs"] == 7), global: false)
        end)
      )
    )
  end

  defp plant_dated(doc),
    do:
      edit_first_dated(doc, fn e ->
        update(e, "evidence", fn ev -> String.replace(ev, "-32_022", "-32_023", global: false) end)
      end)

  defp ninth(doc) do
    edges = doc["edges"]
    i = Enum.find_index(edges, &(not has?(&1, "evidence_at") and is_binary(&1["evidence"])))

    put(
      doc,
      "edges",
      List.update_at(edges, i, fn e ->
        e
        |> update("evidence", &("At bd99a39, " <> &1))
        |> put("evidence_at", ordered([{"commit", @at}, {"owner", "MES-193"}]))
      end)
    )
  end

  # Records AND pins move together, so the only refusal left is the one under test.
  defp recommit(sha, opts \\ []) do
    short = String.slice(sha, 0, 7)

    leaf = fn e ->
      if opts[:rename_leaf],
        do:
          update(e, "evidence", fn ev ->
            String.replace_prefix(ev, "At bd99a39, ", "At #{short}, ")
          end),
        else: e
    end

    [
      {@server,
       &edit_dated(&1, fn e ->
         e |> update("evidence_at", fn at -> put(at, "commit", sha) end) |> leaf.()
       end)},
      {Crosswalk.dated_pins_path(),
       &update(&1, "records", fn rs -> Enum.map(rs, fn p -> put(p, "commit", sha) end) end)}
    ]
  end

  defp edit_dated(doc, fun),
    do:
      update(doc, "edges", fn es ->
        Enum.map(es, &if(has?(&1, "evidence_at"), do: fun.(&1), else: &1))
      end)

  defp edit_first_dated(doc, fun) do
    i = Enum.find_index(doc["edges"], &has?(&1, "evidence_at"))
    update(doc, "edges", &List.update_at(&1, i, fun))
  end

  defp edit_first_pin(doc, fun), do: update(doc, "records", &List.update_at(&1, 0, fun))

  defp edit_bytes(bin, from, to) do
    unless String.contains?(bin, from),
      do: halt("BROKEN CONTROL: #{inspect(from)} is not in the file")

    String.replace(bin, from, to, global: false)
  end

  # --- runners --------------------------------------------------------------

  defp gen(label, expected, mutations), do: gen_with(label, expected, @all_edges, mutations)

  defp gen_with(label, expected, edges, mutations) do
    with_mutations(mutations, fn ->
      out = tmp()
      {text, status} = generate(out, edges)
      File.rm(out)
      refused(label, expected, text, status)
    end)
  end

  defp tool(label, args, expected, mutations) do
    with_mutations(mutations, fn ->
      {text, status} = System.cmd("mix", args, stderr_to_stdout: true)
      refused(label, expected, text, status)
    end)
  end

  defp refused(label, expected, text, status) do
    missing = Enum.reject(expected, &String.contains?(text, &1))
    ok = status != 0 and missing == []

    verdict(
      "#{label}\n        exit #{status}; named #{inspect(expected -- missing)}" <>
        if(missing == [],
          do: "",
          else: "; NOT named #{inspect(missing)}; got: #{first_refusal(text)}"
        ),
      ok
    )
  end

  defp with_mutations(mutations, fun) do
    originals = Map.new(mutations, fn {path, _} -> {path, File.read!(path)} end)

    try do
      for {path, mutate} <- mutations do
        bytes = File.read!(path)

        new =
          if json?(path) and path not in [@crosswalk, @view_4a, @ledger],
            do: bytes |> decode() |> mutate.() |> Jason.encode!(pretty: true),
            else: mutate.(bytes)

        File.write!(path, new)
      end

      fun.()
    after
      Enum.each(originals, fn {path, bytes} -> File.write!(path, bytes) end)
    end
  end

  defp generate(out, edges) do
    System.cmd(
      "mix",
      ["conformance.crosswalk"] ++
        Enum.flat_map(edges, &["--edges", &1]) ++
        ~w(--manifest docs/conformance/in-scope-2026-07-28.json
           --denominator docs/conformance/bucket-0-2026-07-28.json
           --register docs/conformance/etcc-register.json
           --attribution docs/conformance/etcc-attribution.json
           --a3-axes docs/conformance/oc-axes-2026-07-28.json
           --c1-axes conformance/data/oc-axes-c1.json
           --emitting-sites docs/conformance/oc-emitting-sites-2026-07-28.json) ++
        ["--harness", @harness, "-o", out],
      stderr_to_stdout: true
    )
  end

  defp exits_zero(label, args) do
    {text, status} = System.cmd("mix", args, stderr_to_stdout: true)
    verdict("#{label} exits 0 (#{first_refusal(text)})", status == 0)
  end

  defp orphan_commit,
    do: git!(["commit-tree", "HEAD^{tree}", "-m", "MES-234 M3 orphan (unreachable)"])

  defp git!(args, opts \\ [trim: true]) do
    {out, 0} = System.cmd("git", args)
    if opts[:trim], do: String.trim(out), else: out
  end

  # --- ordered JSON ---------------------------------------------------------

  defp decode(bin), do: Jason.decode!(bin, objects: :ordered_objects)
  defp ordered(kvs), do: %Jason.OrderedObject{values: kvs}
  defp has?(%Jason.OrderedObject{values: vs}, k), do: List.keymember?(vs, k, 0)

  defp put(%Jason.OrderedObject{values: vs} = o, k, v),
    do: %{
      o
      | values:
          if(List.keymember?(vs, k, 0),
            do: List.keyreplace(vs, k, 0, {k, v}),
            else: vs ++ [{k, v}]
          )
    }

  defp update(o, k, fun), do: put(o, k, fun.(o[k]))
  defp pop(%Jason.OrderedObject{values: vs} = o, k), do: %{o | values: List.keydelete(vs, k, 0)}
  defp json?(path), do: String.ends_with?(path, ".json")

  # --- output ---------------------------------------------------------------

  defp first_refusal(text) do
    case Regex.run(~r/\*\* \([^)]+\) [^\n]*/, text) do
      [line] -> String.slice(line, 0, 140)
      nil -> "no refusal line"
    end
  end

  defp verdict(label, true), do: IO.puts("  ok    #{label}") && true
  defp verdict(label, false), do: IO.puts("  FAIL  #{label}") && false
  defp header(t), do: IO.puts("\n== #{t} ==\n")

  defp tmp,
    do: Path.join(System.tmp_dir!(), "mes234-dated-#{System.unique_integer([:positive])}.json")

  defp halt(msg) do
    IO.puts(msg)
    System.halt(2)
  end
end

CrosswalkDatedControls.run(System.argv())

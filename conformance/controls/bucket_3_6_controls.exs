# Controls for the D3+D6 record (MES-144; plan 30054 C3, ratified 30055 Q3):
# buckets 3 and 6, checked, and zero.
#
#     mix run conformance/controls/bucket_3_6_controls.exs live
#     mix run conformance/controls/bucket_3_6_controls.exs plants
#     mix run conformance/controls/bucket_3_6_controls.exs all
#
# WHAT IT HOLDS. Both buckets need an edge whose ET-CC member is RED. The
# crosswalk's `et` verdict is a hand-entered input (each edge's `et_verdict`),
# so the views' zero is a fact about that input, not about the suite. `live`
# measures the criterion itself: it runs `mix test.etcc --rows` at this tip,
# joins each member's status to the crosswalk's cells, and requires
#
#   * selection: the run carried EXACTLY the register's ET-CC members;
#   * statuses: each member's status equals the record's
#     (mechanism.criterion_run.statuses);
#   * red_members: the members that did not pass EQUAL the record's (none);
#   * red_cells: the cells whose member did not pass EQUAL the record's
#     (mechanism.joined_to_the_crosswalk.red_cells, none);
#   * stored_vs_run: every cell's stored `et` verdict agrees with the run
#     (green iff its member passed). This is route (b) of the record's
#     fill_conditions.on_main: a wrong stored verdict is caught here.
#
# Fail-closed: a member the run did not carry is not a pass, and a run that
# leaves no capture is refused, not read as zero.
#
# Gate 5 cannot hold this: the run IS a run of the suite. The consistency of
# the record's statuses, red members and red cells with each other and with
# the crosswalk is held in gate 5 (adjudications_test.exs, "the D3+D6 record
# (MES-144)"); what lives here is the part that needs the suite run.
#
# `plants` takes the live capture and the crosswalk and mutates them IN
# MEMORY. P0: none (the positive limb, run first). P1: an ET-CC member ON an
# edge reported failed. P2: a member on NO edge reported failed, which is a
# red member and no red cell, so the two sets are different claims. P3: an
# edgeless member absent from the capture. P4: one cell's stored verdict
# flipped to red while its member passed. Each plant must be refused by
# exactly the kinds it names, and every refusal must name this control.
#
# Measured at MES-144: `all` runs in 22 seconds wall-clock, nearly all of it
# the `mix test.etcc` run. Nothing in the clone is written; the capture goes to
# the system tmp dir and is removed.

defmodule Bucket36Controls do
  @record "docs/conformance/adjudications/adjudication-D3-D6-2026-07-28.json"
  @crosswalk "docs/conformance/crosswalk-2026-07-28.json"
  @register "docs/conformance/etcc-register.json"
  @name "BUCKET-3/6 CONTROL"

  def run(["live"]), do: live(capture!()) && IO.puts("\nPASS live")

  def run(["plants"]), do: plants(capture!()) && IO.puts("\nPASS plants")

  def run(["all"]) do
    {micros, :ok} =
      :timer.tc(fn ->
        cap = capture!()
        live(cap)
        plants(cap)
        :ok
      end)

    IO.puts("\nPASS all (#{div(micros, 1_000_000)} s)")
  end

  def run(_) do
    IO.puts("usage: mix run #{__ENV__.file |> Path.relative_to_cwd()} live|plants|all")
    System.halt(2)
  end

  # --- the run ------------------------------------------------------------------

  # {member => status} from a fresh `mix test.etcc --rows` capture at this tip.
  def capture! do
    path =
      Path.join(System.tmp_dir!(), "mes144-etcc-#{System.unique_integer([:positive])}.json")

    {out, status} = System.cmd("mix", ["test.etcc", "--rows", path], stderr_to_stdout: true)

    unless File.regular?(path) do
      IO.puts(out)
      check("the run left a capture at #{path} (exit #{status})", false)
    end

    doc = path |> File.read!() |> Jason.decode!()
    File.rm!(path)
    IO.puts("  run   mix test.etcc exited #{status}; #{doc["totals"]["by_status"] |> inspect()}")
    for r <- doc["rows"], r["status"] != "excluded", into: %{}, do: {r["key"], r["status"]}
  end

  # --- the adjudication ---------------------------------------------------------

  # [{kind, detail}]; [] when the record's zero holds against this run.
  def refusals(statuses, cells, record, etcc) do
    run = record["mechanism"]["criterion_run"]
    recorded = Map.new(run["statuses"], &{&1["member"], &1["status"]})
    status = fn m -> Map.get(statuses, m, "absent") end

    selected = statuses |> Map.keys() |> MapSet.new()
    red_members = for m <- etcc, status.(m) != "passed", do: m
    red_cells = for c <- cells, status.(member(c)) != "passed", do: key(c)

    disagree =
      for c <- cells,
          c["verdicts"]["et"] == "green" != (status.(member(c)) == "passed"),
          do: {key(c), c["verdicts"]["et"], status.(member(c))}

    moved = for m <- etcc, status.(m) != recorded[m], do: {m, recorded[m], status.(m)}

    [
      {:selection, selected != MapSet.new(etcc),
       fn ->
         "the run carried #{MapSet.size(selected)} members; not EXACTLY the register's #{length(etcc)} ET-CC members: missing #{inspect(MapSet.difference(MapSet.new(etcc), selected) |> Enum.take(3))}, stray #{inspect(MapSet.difference(selected, MapSet.new(etcc)) |> Enum.take(3))}"
       end},
      {:statuses, moved != [],
       fn ->
         "#{length(moved)} member(s) not at the record's status: #{inspect(Enum.take(moved, 3))}"
       end},
      {:red_members, red_members != run["red_members"],
       fn ->
         "red members #{inspect(Enum.take(red_members, 3))} (#{length(red_members)}); the record says #{inspect(run["red_members"])}"
       end},
      {:red_cells, red_cells != record["mechanism"]["joined_to_the_crosswalk"]["red_cells"],
       fn ->
         "red cells #{inspect(Enum.take(red_cells, 3))} (#{length(red_cells)}); the record says #{inspect(record["mechanism"]["joined_to_the_crosswalk"]["red_cells"])}: a bucket-3 or bucket-6 cell the views do not project"
       end},
      {:stored_vs_run, disagree != [],
       fn ->
         "#{length(disagree)} cell(s) whose stored et verdict disagrees with the run: #{inspect(Enum.take(disagree, 3))}"
       end}
    ]
    |> Enum.filter(fn {_, fired?, _} -> fired? end)
    |> Enum.map(fn {kind, _, detail} -> {kind, "#{@name} refused — #{kind}: #{detail.()}"} end)
  end

  defp member(c), do: c["member"]["register_key"]
  defp key(c), do: [member(c), c["claim"], c["tag"]]

  defp inputs do
    record = @record |> File.read!() |> Jason.decode!()
    cells = (@crosswalk |> File.read!() |> Jason.decode!())["cells"]

    etcc =
      for r <- (@register |> File.read!() |> Jason.decode!())["rows"],
          r["label"] == "ET-CC",
          do: r["key"]

    {record, cells, etcc}
  end

  # --- live ---------------------------------------------------------------------

  def live(statuses) do
    header("live — the record's zero against a run at this tip")
    {record, cells, etcc} = inputs()
    rs = refusals(statuses, cells, record, etcc)

    check(
      "the run's #{map_size(statuses)} members hold the record: no refusal",
      rs == [],
      Enum.map(rs, &elem(&1, 1))
    )

    red = for c <- cells, Map.get(statuses, member(c)) != "passed", do: key(c)

    check(
      "red cells over all #{length(cells)} cells: #{length(red)}, as both views' count",
      red == []
    )

    true
  end

  # --- plants -------------------------------------------------------------------

  def plants(statuses) do
    header("plants — each refused by exactly the kinds it names")
    {record, cells, etcc} = inputs()
    on_edge = cells |> Enum.map(&member/1) |> MapSet.new()
    edged = cells |> hd() |> member()
    edgeless = Enum.find(etcc, &(not MapSet.member?(on_edge, &1)))
    [c | rest] = cells
    passed_cell = Enum.find(cells, &(Map.get(statuses, member(&1)) == "passed"))

    flip = fn cs ->
      Enum.map(cs, fn x ->
        if x == passed_cell, do: put_in(x, ["verdicts", "et"], "red"), else: x
      end)
    end

    for {label, st, cs, kinds} <- [
          {"P0 (positive) the live run, unplanted", statuses, cells, []},
          {"P1 an ET-CC member ON an edge reported failed", %{statuses | edged => "failed"},
           cells, [:statuses, :red_members, :red_cells, :stored_vs_run]},
          {"P2 a member on NO edge reported failed: a red member, and no red cell",
           %{statuses | edgeless => "failed"}, cells, [:statuses, :red_members]},
          {"P3 an edgeless member absent from the run: not a pass",
           Map.delete(statuses, edgeless), cells, [:selection, :statuses, :red_members]},
          {"P4 a cell's stored et verdict flipped to red while its member passed", statuses,
           flip.([c | rest]), [:stored_vs_run]}
        ] do
      rs = refusals(st, cs, record, etcc)

      check(
        label <> ": #{inspect(kinds)}",
        Enum.map(rs, &elem(&1, 0)) == kinds,
        Enum.map(rs, &elem(&1, 1))
      )

      for {kind, line} <- rs do
        check(
          "  … names the control and the kind: #{String.slice(line, 0, 110)}",
          String.starts_with?(line, "#{@name} refused — #{kind}: ")
        )
      end
    end

    # P2's point, stated: the red-member set moved and the red-cell set did not.
    red_cells =
      for x <- cells,
          Map.get(%{statuses | edgeless => "failed"}, member(x)) != "passed",
          do: key(x)

    check("P2 leaves red cells empty while red members is not", red_cells == [])
    true
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

Bucket36Controls.run(System.argv())

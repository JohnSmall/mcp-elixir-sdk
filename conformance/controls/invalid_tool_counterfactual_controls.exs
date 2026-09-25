# MES-111 — the §2.1 counterfactual behind etcc-register.md §12, made re-runnable.
#
#     MIX_ENV=test mix run conformance/controls/invalid_tool_counterfactual_controls.exs
#
# MIX_ENV=test because the units under test use `MCP.Test.MockTransport`, which
# lives in `test/support` and is compiled in the test env only.
#
# WHAT IT ATTESTS. §12 rules that the six `MCP.Protocol.HeaderMirrorTest` units
# in "annotation validity — the ten classes the alpha.11 fixture exercises" stay
# ET-ADJ, and one leg of that ruling is membership §2.1 answered YES: *could an
# SDK get the ClientRejectsInvalidTool behaviour arbitrarily wrong and still pass
# them?* This file measures that answer rather than leaving it as prose. It
# makes the client IGNORE `HeaderMirror.validate_tool/1`'s verdict, so a tool
# the validator rejects is kept anyway, and runs the units against that client.
#
# THE FOUR LIMBS, in this order, all in one VM:
#
#   P1  unmutated          the six subjects AND the W6 witnesses all pass. The
#                          positive control: without it a red in M1 could be a
#                          red that was already there.
#   M1  verdict ignored    the six subjects all STILL pass (the §2.1 YES), AND at
#                          least one W6 witness FAILS. The second conjunct is the
#                          potency limb: "six stayed green" is only evidence if
#                          the mutation demonstrably changed client behaviour,
#                          and a W6 ET-CC unit going red is that demonstration.
#   N1  no-op mutation     the ORIGINAL source recompiled through the very same
#                          path. M1's adjudicator must REFUSE it, naming the
#                          potency guard — otherwise the potency limb is a claim
#                          that was never seen to fire.
#   R1  restored           the compiled .beam reloaded; its md5 must equal the
#                          one recorded before P1, and everything passes again.
#
# THE POPULATIONS ARE THE REGISTER'S, NOT THIS FILE'S. The six subjects are the
# `etcc-register.json` rows in that describe, required to be exactly six, all
# ET-ADJ at gate 2; the witnesses are the register's ET-CC rows in describe
# "W6 — SEP-2243 tool exclusion". Both sets are then cross-checked against the
# rows the run actually produced, in both directions, so a unit that was added,
# renamed or dropped goes red here rather than shrinking the control silently.
#
# NOTHING IS WRITTEN INTO THE REPO. The mutation is an in-VM `Code.compile_string`
# of the modified source; `lib/mcp/client.ex` is read, never written, and its
# sha256 is asserted unchanged at the end. A seat death mid-run leaves at most a
# mutated module in a VM that no longer exists (S8-14). The per-run row
# artefacts go to System.tmp_dir!/0 and are removed.
#
# Exit 0 only if every limb holds; 1 otherwise, naming the limb.

defmodule InvalidToolCounterfactualControls do
  alias MCP.Conformance.ExUnitRows

  @register "docs/conformance/etcc-register.json"
  @client_src "lib/mcp/client.ex"
  @test_files [
    "test/mcp/protocol/header_mirror_test.exs",
    "test/mcp/client_tool_schemas_test.exs"
  ]

  @subject_module "MCP.Protocol.HeaderMirrorTest"
  @subject_describe "annotation validity — the ten classes the alpha.11 fixture exercises"
  @witness_module "MCP.ClientToolSchemasTest"
  @witness_describe "W6 — SEP-2243 tool exclusion"

  # The site `consumed_at` names in all six register rows. Matched as source
  # text, and required to occur EXACTLY once: zero means client.ex moved and
  # the control must be re-pointed, two means the replacement is ambiguous.
  @site "case HeaderMirror.validate_tool(tool) do"
  @mutant "case HeaderMirror.validate_tool(tool) |> then(fn {:error, _} -> {:ok, []}; ok -> ok end) do"

  def run(_argv) do
    t0 = System.monotonic_time(:millisecond)
    src_sha = sha(File.read!(@client_src))
    beam_md5 = MCP.Client.module_info(:md5)

    {subjects, witnesses, witness_describe_rows} = populations()
    modules = load_tests()

    header("P1 — unmutated: every subject and every witness passes")
    p1 = run_suite(modules, "p1")
    cross_check!(p1, subjects, witnesses, witness_describe_rows)
    limb("P1", all_passed?(p1, subjects) and all_passed?(p1, witnesses), p1, subjects, witnesses)

    header("M1 — the client IGNORES validate_tool/1's verdict (in-VM recompile)")
    source = File.read!(@client_src)
    sites = length(String.split(source, @site)) - 1

    unless sites == 1 do
      halt(
        "M1: the mutation site occurs #{sites} times in #{@client_src}, not once — re-point @site"
      )
    end

    recompile(String.replace(source, @site, @mutant))
    mutated_md5 = MCP.Client.module_info(:md5)
    IO.puts("  MCP.Client md5 #{hex(beam_md5)} -> #{hex(mutated_md5)}")
    halt_unless(mutated_md5 != beam_md5, "M1: the recompiled module is byte-identical")

    m1 = run_suite(modules, "m1")
    m1_ok = adjudicate_mutant(m1, subjects, witnesses)
    limb("M1", m1_ok == :ok, m1, subjects, witnesses)

    header("N1 — a NO-OP mutation: M1's adjudicator must refuse it on potency")
    recompile(source)
    n1 = run_suite(modules, "n1")
    n1_verdict = adjudicate_mutant(n1, subjects, witnesses)
    IO.puts("  adjudicator: #{inspect(n1_verdict)}")

    limb(
      "N1",
      n1_verdict == {:refused, :not_potent},
      n1,
      subjects,
      witnesses
    )

    header("R1 — restored: the compiled .beam reloaded, everything passes again")
    :code.purge(MCP.Client)
    {:module, MCP.Client} = :code.load_file(MCP.Client)
    halt_unless(MCP.Client.module_info(:md5) == beam_md5, "R1: reloaded md5 differs from P1's")
    IO.puts("  MCP.Client md5 #{hex(MCP.Client.module_info(:md5))} (== P1)")
    r1 = run_suite(modules, "r1")
    limb("R1", all_passed?(r1, subjects) and all_passed?(r1, witnesses), r1, subjects, witnesses)

    header("DISK — nothing written into lib/")
    halt_unless(sha(File.read!(@client_src)) == src_sha, "DISK: #{@client_src} changed on disk")
    IO.puts("  #{@client_src} sha256 #{src_sha} (unchanged)")

    elapsed = System.monotonic_time(:millisecond) - t0
    IO.puts("\nALL LIMBS HOLD — P1 M1 N1 R1. #{elapsed} ms.")
  end

  # --- populations ----------------------------------------------------------

  defp populations do
    rows = read_json(@register)["rows"]

    subjects =
      for r <- rows, r["module"] == @subject_module, r["describe"] == @subject_describe, do: r

    # Every register row in the W6 describe, whatever its label: the describe
    # also holds ET-OUT rows, and the run-to-register limb must admit those.
    witness_describe_rows =
      for r <- rows, r["module"] == @witness_module, r["describe"] == @witness_describe, do: r

    witnesses = for r <- witness_describe_rows, r["label"] == "ET-CC", do: r

    halt_unless(length(subjects) == 6, "POPULATION: #{length(subjects)} subject rows, not 6")

    Enum.each(subjects, fn r ->
      halt_unless(
        r["label"] == "ET-ADJ" and r["excluding_gate"] == 2,
        "POPULATION: #{r["name"]} is #{r["label"]}/gate #{inspect(r["excluding_gate"])}, not ET-ADJ/2"
      )
    end)

    halt_unless(witnesses != [], "POPULATION: no ET-CC witness in #{@witness_describe}")

    IO.puts("register: #{length(subjects)} ET-ADJ subjects, #{length(witnesses)} ET-CC witnesses")
    {keys(subjects), keys(witnesses), keys(witness_describe_rows)}
  end

  # The register's own `key` field, the same row key the B3 instrument emits.
  defp keys(rows), do: MapSet.new(rows, & &1["key"])

  # --- running the suite in this VM -----------------------------------------

  defp load_tests do
    Code.compiler_options(ignore_module_conflict: true)
    ExUnit.start(autorun: false, formatters: [ExUnitRows], seed: 0)

    for file <- @test_files,
        {mod, _} <- Code.require_file(file),
        function_exported?(mod, :__ex_unit__, 0),
        do: mod
  end

  # One ExUnit run of the two modules, captured row-per-test by the B3
  # instrument. The first run takes the modules require_file registered; later
  # runs name them, which is ExUnit.run/1's documented re-run form.
  defp run_suite(modules, stem) do
    path =
      Path.join(System.tmp_dir!(), "mes111-#{stem}-#{System.unique_integer([:positive])}.json")

    System.put_env(ExUnitRows.env_path_var(), path)

    try do
      ExUnit.run(if(stem == "p1", do: [], else: modules))
      rows = read_json(path)["rows"]
      halt_unless(rows != [], "#{stem}: the run produced no rows")
      Map.new(rows, &{&1["key"], &1})
    after
      System.delete_env(ExUnitRows.env_path_var())
      File.rm(path)
    end
  end

  defp recompile(source) do
    {_, diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(source, @client_src) end)
    errors = for %{severity: :error} = d <- diagnostics, do: d.message
    halt_unless(errors == [], "recompile failed: #{inspect(errors)}")
  end

  # --- adjudication ---------------------------------------------------------

  # Both sets must be exactly what the run produced in those describes: a
  # register row the run did not produce, or a runtime unit in the describe the
  # register does not hold, is a population that moved under the control. The
  # witnesses are an ET-CC subset of their describe, so their run-to-register
  # limb is asked of the describe's register rows of ANY label.
  defp cross_check!(results, subjects, witnesses, witness_describe_rows) do
    ran = fn module, describe ->
      for {k, r} <- results,
          r["module"] == module,
          r["describe"] == describe,
          into: MapSet.new(),
          do: k
    end

    ran_subjects = ran.(@subject_module, @subject_describe)

    halt_unless(
      ran_subjects == subjects,
      "POPULATION: register vs run differ in the subject describe — " <>
        "register-only #{inspect(MapSet.difference(subjects, ran_subjects) |> MapSet.to_list())}, " <>
        "run-only #{inspect(MapSet.difference(ran_subjects, subjects) |> MapSet.to_list())}"
    )

    ran_witness_describe = ran.(@witness_module, @witness_describe)
    missing = MapSet.difference(witnesses, ran_witness_describe)

    halt_unless(
      MapSet.size(missing) == 0,
      "POPULATION: witnesses not run: #{inspect(MapSet.to_list(missing))}"
    )

    unregistered = MapSet.difference(ran_witness_describe, witness_describe_rows)

    halt_unless(
      MapSet.size(unregistered) == 0,
      "POPULATION: run units in the witness describe the register does not hold: " <>
        inspect(MapSet.to_list(unregistered))
    )
  end

  # M1's verdict. Order matters: potency is asked FIRST, because a mutation that
  # changed nothing leaves the subjects green for a reason unrelated to §2.1.
  defp adjudicate_mutant(results, subjects, witnesses) do
    cond do
      not Enum.any?(witnesses, &(status(results, &1) == "failed")) -> {:refused, :not_potent}
      not all_passed?(results, subjects) -> {:refused, :subject_went_red}
      true -> :ok
    end
  end

  defp all_passed?(results, keys), do: Enum.all?(keys, &(status(results, &1) == "passed"))
  defp status(results, key), do: get_in(results, [key, "status"]) || "absent"

  defp limb(name, ok?, results, subjects, witnesses) do
    print_set("subjects (ET-ADJ)", results, subjects)
    print_set("witnesses (W6 ET-CC)", results, witnesses)
    IO.puts("  #{name}: #{if ok?, do: "HOLDS", else: "FAILS"}")
    halt_unless(ok?, "#{name} does not hold")
  end

  defp print_set(title, results, keys) do
    IO.puts("  #{title}:")

    for k <- Enum.sort(keys) do
      name = k |> String.split("/", parts: 2) |> List.last()
      IO.puts("    #{String.pad_trailing(status(results, k), 7)} #{name}")
    end
  end

  # --- plumbing -------------------------------------------------------------

  defp halt_unless(true, _msg), do: :ok

  defp halt_unless(false, msg) do
    IO.puts("\nCONTROL FAILS — #{msg}")
    System.halt(1)
  end

  defp halt(msg), do: halt_unless(false, msg)

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()
  defp sha(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
  defp hex(md5), do: Base.encode16(md5, case: :lower)
  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

InvalidToolCounterfactualControls.run(System.argv())

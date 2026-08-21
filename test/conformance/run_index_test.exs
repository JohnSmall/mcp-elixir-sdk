defmodule MCP.Conformance.RunIndexTest do
  @moduledoc """
  The client leg's scenario key, and the property the whole design turns on.

  Every claim here is checkable with `mix test` alone, over a committed fixture.
  That constraint is not stylistic: `node` is not on the CODE_REVIEWER seat's
  PATH (S5-16), so a claim demonstrated by re-running the harness is a claim
  only its author can verify — which is to say a claim nobody verifies.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.{Console, RequirementSet, RunIndex}

  @fixture Path.expand("../fixtures/conformance/client-alpha11", __DIR__)

  setup_all do
    console = File.read!(Path.join(@fixture, "console.txt"))
    expected = File.read!(Path.join(@fixture, "expected.txt"))
    yaml = File.read!(Path.join(@fixture, "requirements.yaml"))

    dirs =
      Path.join(@fixture, "scenario-dirs.txt")
      |> File.read!()
      |> String.split("\n", trim: true)

    {:ok, set} = RequirementSet.parse(yaml, expected)

    %{console: console, dirs: dirs, set: set}
  end

  # A run directory built from a LIST, so the caller chooses the creation order
  # and the test can permute it. `checks.json` is empty rather than absent:
  # RunIndex keys on the directory NAME, and what a check sheet says is
  # irrelevant to which scenario it is attributed to.
  defp build_run!(dirs, opts \\ []) do
    root = Path.join(System.tmp_dir!(), "mes57-runindex-#{System.unique_integer([:positive])}")
    without_checks = Keyword.get(opts, :without_checks, [])
    File.mkdir_p!(root)

    for rel <- dirs do
      File.mkdir_p!(Path.join(root, rel))

      unless rel in without_checks or not stamped?(rel) do
        File.write!(Path.join([root, rel, "checks.json"]), "[]")
      end
    end

    on_exit_rm(root)
    root
  end

  defp stamped?(rel), do: Regex.match?(RunIndex.stamp_pattern(), rel)

  defp on_exit_rm(root), do: ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)

  defp index(root, console, set) do
    RunIndex.index("client",
      console_body: console,
      run_dir: root,
      out_dir: root,
      requirement_set: set
    )
  end

  # A deterministic permutation, seeded from the element itself. `Enum.shuffle/1`
  # would make a failure unreproducible, and this file's whole subject is
  # ordering.
  defp permute(list), do: Enum.sort_by(list, &:erlang.phash2({&1, 0xC0FFEE}))

  describe "the key identifies every scenario in a real alpha.11 client run" do
    test "39 directories, 39 scenarios, no faults", %{console: c, dirs: d, set: s} do
      result = index(build_run!(d), c, s)

      assert result.faults == []
      assert length(result.mappings) == 39
      assert Enum.all?(result.mappings, &(&1.dir != nil))
    end

    test "the ids are the frozen set's, exactly — no leftovers either way", %{
      console: c,
      dirs: d,
      set: s
    } do
      result = index(build_run!(d), c, s)
      expected = RequirementSet.expected_to_run(s, "client")

      assert RunIndex.ran(result) == Enum.sort(expected.scored ++ expected.not_scored)
    end

    test "the timestamp suffix is the harness's, checked against real directory names", %{
      dirs: d
    } do
      # Taken from `Ho()` in dist/index.js:
      #   new Date().toISOString().replace(/[:.]/g, "-")
      # and settled against the tree a real run produced, which is the check the
      # PM asked for: a wrong pattern fails SAFE (every directory would refuse as
      # ARTEFACT_DIR_UNKNOWN) but would send a reader hunting the wrong thing.
      {stamped, unstamped} = Enum.split_with(d, &stamped?/1)

      assert length(stamped) == 39

      # Enumerated, not counted (A2d): there is exactly one unstamped directory
      # and it is the container `path.join` creates for slashed scenario ids.
      assert unstamped == ["auth"]
    end
  end

  describe "ORDER-INDEPENDENCE — the property positional pairing fails" do
    test "shuffling and reversing the DIRECTORY list changes nothing", %{
      console: c,
      dirs: d,
      set: s
    } do
      # Each run lives under its own tmp root, so the comparison is made on the
      # part that carries meaning: which scenario maps to which directory,
      # relative to the run.
      as_map = fn dirs ->
        root = build_run!(dirs)
        result = index(root, c, s)

        {Map.new(result.mappings, &{&1.scenario, &1.dir && Path.relative_to(&1.dir, root)}),
         result.faults}
      end

      sorted = as_map.(d)

      assert as_map.(permute(d)) == sorted
      assert as_map.(Enum.reverse(d)) == sorted
    end

    test "shuffling and reversing the CONSOLE's lines changes nothing", %{
      console: c,
      dirs: d,
      set: s
    } do
      root = build_run!(d)
      lines = String.split(c, "\n")

      sorted = index(root, c, s)
      shuffled = index(root, Enum.join(permute(lines), "\n"), s)
      reversed = index(root, lines |> Enum.reverse() |> Enum.join("\n"), s)

      # This is the one that must be shown, and shown on a REAL console rather
      # than a fixture built to pass it: it is exactly the property a positional
      # pairing does not have.
      assert shuffled.mappings == sorted.mappings
      assert reversed.mappings == sorted.mappings
    end

    test "a POSITIONAL pairing over the same artefacts DISAGREES, and by how much", %{
      console: c,
      dirs: d,
      set: s
    } do
      root = build_run!(d)
      key = index(root, c, s) |> Map.fetch!(:mappings) |> Map.new(&{&1.scenario, &1.dir})

      positional = positional_pairing(c, root)

      # Both derivations see the same 39 scenarios, and both express the same
      # directories under this test's root — so any disagreement is about
      # ATTRIBUTION and nothing else. Asserted rather than assumed: if the two
      # sides disagreed on the SET of directories, "mis-attributed 35 of 39"
      # would be measuring a path bug instead of the ordering hazard.
      assert map_size(positional) == map_size(key)
      assert Enum.sort(Map.keys(positional)) == Enum.sort(Map.keys(key))
      assert positional |> Map.values() |> Enum.sort() == key |> Map.values() |> Enum.sort()

      wrong = for {id, dir} <- positional, Map.fetch!(key, id) != dir, do: id

      # MES-56 measured positional pairing mis-attributing 4 of 5 on a
      # five-scenario suite. Quantified here on the real 39-scenario run, so the
      # guard's value is a number rather than an assertion. The exact count is
      # not pinned — it is a property of one run's completion order — but that it
      # is a LARGE majority is the finding, and zero would mean this test had
      # stopped testing anything.
      assert length(wrong) > 30,
             "positional pairing mis-attributed only #{length(wrong)} of #{map_size(key)}; " <>
               "if it now agrees, this test is no longer evidence for the key"
    end
  end

  # The pairing MES-57 was dispatched to rule OUT, implemented here and nowhere
  # else: take `Starting scenario:` lines in order, take `Results saved to`
  # lines in order, zip. It is plausible, it is what the server leg's bracketing
  # would license, and on this leg it is wrong.
  defp positional_pairing(console, root) do
    lines = String.split(console, "\n")

    starts =
      for line <- lines, [_, id] <- [Regex.run(~r/^Starting scenario: (.+)$/, line)], do: id

    saves =
      for line <- lines, [_, dir] <- [Regex.run(~r/^Results saved to (\S.*)$/, line)], do: dir

    original_root = common_prefix(saves)

    starts
    |> Enum.zip(saves)
    |> Map.new(fn {id, dir} -> {id, Path.join(root, Path.relative_to(dir, original_root))} end)
  end

  # The fixture's `Results saved to` lines carry the ORIGINAL run's absolute
  # paths, and the run root is their longest common path prefix. Derived rather
  # than hardcoded, and derived CORRECTLY rather than from the first line: taking
  # `dirname` of whichever save happened to come first would yield
  # `<root>/auth` whenever an auth scenario finished first, and the resulting
  # pairing would disagree with the key for a second, spurious reason. A control
  # that fires for the wrong reason is not a control (S5-22).
  defp common_prefix([]), do: "/"

  defp common_prefix([first | rest]) do
    rest
    |> Enum.reduce(Path.split(first), fn path, acc ->
      path
      |> Path.split()
      |> Enum.zip(acc)
      |> Enum.take_while(fn {a, b} -> a == b end)
      |> Enum.map(&elem(&1, 0))
    end)
    |> Path.join()
  end

  describe "REFUSALS — each shown failing on a tree mutated from the real run" do
    test "ARTEFACT_DIR_UNKNOWN: a directory the frozen set does not name", %{
      console: c,
      dirs: d,
      set: s
    } do
      # A scenario renamed upstream is the realistic cause, so the mutation is a
      # rename rather than an invention.
      renamed =
        Enum.map(d, fn rel ->
          String.replace(rel, "tools_call-2026", "tools-call-2026")
        end)

      result = index(build_run!(renamed), c, s)

      assert Enum.any?(result.faults, &(&1 =~ "ARTEFACT_DIR_UNKNOWN"))
      assert Enum.any?(result.faults, &(&1 =~ "tools-call"))
      refute Enum.any?(result.mappings, &(&1.scenario == "tools_call"))
    end

    test "ARTEFACT_DIR_UNKNOWN: an unstamped directory that is not a container", %{
      console: c,
      dirs: d,
      set: s
    } do
      result = index(build_run!(d ++ ["leftovers"]), c, s)

      assert Enum.any?(result.faults, &(&1 =~ "ARTEFACT_DIR_UNKNOWN" and &1 =~ "leftovers"))
    end

    test "the container `auth/` is NOT refused — the accept half", %{
      console: c,
      dirs: d,
      set: s
    } do
      # Without this the previous test would pass for the wrong reason: a rule
      # that refuses every unstamped directory refuses the whole run.
      assert "auth" in d
      assert index(build_run!(d), c, s).faults == []
    end

    test "ARTEFACT_DIR_AMBIGUOUS: two directories claiming one scenario", %{
      console: c,
      dirs: d,
      set: s
    } do
      # The shape a re-used output directory produces, which is the MES-24
      # stale-artefact defect wearing a different hat.
      twin = "tools_call-2026-08-21T07-11-11-111Z"
      result = index(build_run!(d ++ [twin]), c, s)

      assert Enum.any?(
               result.faults,
               &(&1 =~ "ARTEFACT_DIR_AMBIGUOUS" and &1 =~ "claimed by 2 artefact directories")
             )
    end

    test "ARTEFACT_DIR_AMBIGUOUS: one directory matching a doubled frozen-set entry", %{
      console: c,
      dirs: d
    } do
      # The half that reads as vacuous under exact equality and is not: the
      # expected list is `scored ++ not_scored`, so a set naming one id in both
      # makes a single directory match twice. Checked because MES-56 spent two
      # rounds learning that the multiplicity half of a pair is the one that
      # gets skipped.
      doubled = %{
        scored: %{"client" => ["tools_call", "tools_call"], "server" => []},
        not_scored: []
      }

      result = index(build_run!(d), c, doubled)

      assert Enum.any?(
               result.faults,
               &(&1 =~ "ARTEFACT_DIR_AMBIGUOUS" and &1 =~ "names 2 times")
             )
    end

    test "ARTEFACT_CHECKS_ABSENT: a matched directory with no check sheet", %{
      console: c,
      dirs: d,
      set: s
    } do
      victim = Enum.find(d, &String.starts_with?(&1, "tools_call-"))
      result = index(build_run!(d, without_checks: [victim]), c, s)

      assert Enum.any?(
               result.faults,
               &(&1 =~ "ARTEFACT_CHECKS_ABSENT" and &1 =~ "tools_call")
             )
    end

    test "a SKIPPED scenario's empty directory is NOT refused — it is explained", %{
      dirs: d,
      set: s
    } do
      # `Ko()` in dist/index.js mkdirs the output directory BEFORE the
      # applicability check and returns early on a skip, so this state is one
      # the harness really produces. Reading it as absence would drop the
      # scenario from the census without dropping it from the denominator.
      victim = Enum.find(d, &String.starts_with?(&1, "tools_call-"))

      console =
        "SKIPPED: scenario 'tools_call' is not applicable at spec version 2026-07-28 " <>
          "(introduced in 2027-01-01). Use --force to run it anyway.\n" <>
          File.read!(Path.join(@fixture, "console.txt"))

      result = index(build_run!(d, without_checks: [victim]), console, s)

      refute Enum.any?(result.faults, &(&1 =~ "ARTEFACT_CHECKS_ABSENT"))
    end

    test "no frozen set is a refusal, not an empty map that reads as clean", %{
      console: c,
      dirs: d
    } do
      result =
        RunIndex.index("client",
          console_body: c,
          run_dir: build_run!(d),
          out_dir: "/tmp",
          requirement_set: nil
        )

      assert result.mappings == []
      assert Enum.any?(result.faults, &(&1 =~ "could not be read"))
    end

    test "a leg this tooling cannot index refuses rather than defaulting" do
      result = RunIndex.index("sever", console_body: "")

      assert result.mappings == []
      assert Enum.any?(result.faults, &(&1 =~ "not a leg this tooling can index"))
    end
  end

  describe "the SCORED-ABSENT direction is discharged by expected_diff/2, not duplicated here" do
    test "a missing scored directory leaves the scenario out of `ran`", %{
      console: c,
      dirs: d,
      set: s
    } do
      # One defect, one fault. `Manifest.check_scored_present/3` turns this
      # absence into SCORED_SCENARIO_ABSENT; raising a second fault here would
      # give it two names and two places to be fixed.
      without = Enum.reject(d, &String.starts_with?(&1, "tools_call-"))
      result = index(build_run!(without), c, s)

      refute "tools_call" in RunIndex.ran(result)
      refute Enum.any?(result.faults, &(&1 =~ "tools_call"))
    end
  end

  describe "the SERVER leg delegates to Console unchanged" do
    # The regression guard for every future leg added to this module, and the
    # control on MES-57's blast radius into MES-51's merged adjudicator. Stated
    # as an equivalence over ALL consoles the suite holds rather than as one
    # golden file: a golden file pins one run, this pins the mechanism.
    test "index/2 returns exactly Console.parse/1's mappings and faults" do
      for {label, body} <- server_consoles() do
        parsed = Console.parse(body)
        indexed = RunIndex.index("server", console_body: body)

        assert indexed.mappings == parsed.mappings, "mappings differ for #{label}"
        assert indexed.faults == parsed.faults, "faults differ for #{label}"
      end
    end

    test "a client console routed through the SERVER leg still REFUSES", %{console: c} do
      # `Console.parallel_leg_faults/1` is not relaxed, deleted or bypassed. It
      # is the thing standing between this project and a mis-attributed client
      # table, and nothing routes a client console into it any more — but if
      # something ever did, it must still refuse.
      result = RunIndex.index("server", console_body: c)

      assert result.mappings == []
      assert Enum.any?(result.faults, &(&1 =~ "Promise.all"))
    end
  end

  defp server_consoles do
    healthy = """
    === Running scenario: tools-list ===
    Results saved to /tmp/run/server-tools-list-2026-08-21T00-00-00-000Z
    === Running scenario: resources-list ===
    Results saved to /tmp/run/server-resources-list-2026-08-21T00-00-00-000Z

    === SUITE SUMMARY ===

    ✓ tools-list: 1 passed, 0 failed
    ✓ resources-list: 1 passed, 0 failed

    Total: 2 passed, 0 failed
    """

    [
      {"healthy", healthy},
      {"empty", ""},
      {"a scenario that threw",
       """
       === Running scenario: tools-list ===
       Failed to run scenario tools-list: boom
       """},
      {"an unterminated scenario",
       """
       === Running scenario: tools-list ===
       === Running scenario: resources-list ===
       Results saved to /tmp/run/server-resources-list-2026-08-21T00-00-00-000Z
       """},
      {"a duplicated mark", healthy <> "✗ tools-list: 0 passed, 1 failed\n"},
      {"an orphaned mark", healthy <> "✓ ghost: 1 passed, 0 failed\n"}
    ]
  end

  describe "Console.blocks/1 and Console.parse/1 agree on every block fault" do
    test "the block faults are identical on a server console" do
      # `blocks/1` exists so the client leg keeps the block guards that
      # `parse/1`'s client-console refusal would otherwise take with it. If the
      # two ever diverge, one leg is being guarded and the other is not.
      for {label, body} <- server_consoles() do
        parsed = Console.parse(body)
        blocks = Console.blocks(body)

        assert blocks.marks == parsed.marks, "marks differ for #{label}"
        assert blocks.not_scored == parsed.not_scored, "not_scored differ for #{label}"
        assert blocks.totals == parsed.totals, "totals differ for #{label}"

        # `parse/1` adds only the mapping faults and the parallel-leg sentence;
        # every block fault it reports must be one `blocks/1` reports too.
        assert blocks.faults -- parsed.faults == [], "block faults differ for #{label}"
      end
    end

    test "the client console's block guards are LIVE, not bounded away", %{console: c} do
      # Before MES-57 every mark on a client console was orphaned by
      # construction — there were no `=== Running scenario:` headers — so the
      # membership arms were suppressed with the justification that "the console
      # is refused either way". `RunIndex` makes client runs adjudicable, so
      # that justification lapsed. A lapsed justification guarding a live leg is
      # worse than no guard, because it reads as considered.
      assert Console.blocks(c).faults == []

      ghosted = c <> "\n✓ ghost-scenario: 1 passed, 0 failed\n"
      faults = Console.blocks(ghosted).faults

      assert Enum.any?(faults, &(&1 =~ "ghost-scenario" and &1 =~ "never announced"))
    end
  end

  describe "the drive-policy probe cannot drift from the adapter it is compared against" do
    test "the probe drives exactly the scenario, and the calls, the measurement adapter does" do
      # The probe COPIES the measurement adapter's `request-metadata` clause
      # rather than importing it, so that the measurement instrument does not
      # acquire a second mode. The cost of that choice is that the copy can
      # drift, and a drifted copy would make the discount-1 comparison measure
      # two different clients instead of one policy.
      adapter = File.read!(Path.expand("../../conformance/client_adapter.exs", __DIR__))

      probe =
        File.read!(Path.expand("../../conformance/controls/strict_connect_adapter.exs", __DIR__))

      # The probe's scope now comes from the registry, so THAT is what must be
      # pinned: one declaration, read by the probe and by the derivation.
      assert probe =~ ~s|@driven MCP.Conformance.Adapters.scope(:client, "strict_connect")|
      assert MCP.Conformance.Adapters.scope(:client, "strict_connect") == ["request-metadata"]

      for call <- ["Client.connect(client)", "Client.list_tools(client)"] do
        assert adapter =~ call
        assert probe =~ call
      end

      call_tool =
        ~S|drive("tools/call any_tool", fn -> Client.call_tool(client, "any_tool", %{}) end)|

      assert adapter =~ call_tool
      assert probe =~ call_tool
    end
  end
end

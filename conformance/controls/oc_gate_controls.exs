# Controls for gate 7, `mix conformance.oc_gate` (MES-160).
#
#     mix run conformance/controls/oc_gate_controls.exs            # the cases
#     mix run conformance/controls/oc_gate_controls.exs mutation   # the mutations
#     mix run conformance/controls/oc_gate_controls.exs all        # both
#
# WHAT THIS IS EVIDENCE OF. Each case builds a branch in a THROWAWAY CLONE of this
# repository, plants the thing the gate exists to refuse, drives THE REAL TASK
# against it (live legs included), and requires the named guard to be the one that
# refuses — by its class in the output, not by the exit status alone. P1 is the
# positive control: a check that is red on everything would "pass" every red case
# vacuously.
#
# EVERY CASE ALSO HOLDS THE EXIT STATUS TO THE VERDICT: 1 exactly when the final
# line is `OC-GATE REFUSE`, else 0. The D7 lane guard's status is not in
# correspondence with its verdict (S9-22); this instrument's is, and this is where
# that is shown.
#
# THE MUTATIONS show the cases can fail. Each commits one change to the gate's own
# source on its plant branch — in the clone, never here — recompiles, and requires
# its named case to go RED. A mutation whose site is not found halts the run: a
# mutation that silently did not apply is the no-op that counts as "caught".
#
# IT CANNOT TOUCH THIS CLONE. Everything lives under a root generated per run; the
# clone's top level is re-read before every gate run and must be that root's repo.
#
# TWO CASES HAVE A SECOND LAYER, measured by hand on 2026-09-27, and go red on the
# named guard's absent message, not on the verdict: under M5 the run is still
# refused by the census's COMMIT_MISMATCH; under M3 the runner completes with no
# harness and the census refuses the run as MANIFEST_INCOMPLETE (null
# harness.dist_sha256).
#
# COST, measured on the CC seat 2026-09-27 after correction round 2: `all` 36
# controls in 122 s wall (live legs included). After MES-236 (2026-11-16, 62
# oc-tagged tests on main, so most cases re-measure two legs): `all` 43 controls
# in 254 s wall; 48 after its correction round 1, in 296 s. Run it detached if the engine may exit (setsid nohup ... > file).

defmodule OcGateControls do
  alias MCP.Conformance.{Census, HarnessHost, MatchKey, OcGate}

  @project File.cwd!()

  # A client check that is SUCCESS on this SDK (http-custom-headers, 18/18).
  @green "oc:client/http-custom-headers/sep-2243-client-supports-custom-headers/ClientSupportsCustomHeaders"
  # SKIPPED by design — structurally unable to be SUCCESS, so stable as a plant (Q1).
  @skipped "oc:client/http-standard-headers/sep-2243-client-includes-standard-headers/ClientMcpMethodHeader_initialize"
  # The three-row fieldIssue tie, without its discriminator.
  @bare "oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/HttpServerMetaInvalid400"
  @ghost "oc:client/http-custom-headers/no-such-check/NoSuchCheck"

  def run([]), do: in_root(&cases/1)
  def run(["mutation"]), do: in_root(&mutations/1)
  def run(["all"]), do: in_root(&(cases(&1) ++ mutations(&1)))

  def run(_) do
    IO.puts("usage: mix run conformance/controls/oc_gate_controls.exs [mutation|all]")
    System.halt(2)
  end

  # --- the cases -------------------------------------------------------------

  defp cases(fx) do
    # R7 runs first: its live server run is where R3b's FAILURE row is found.
    {r7, r7_out} = r7(fx)

    [
      p1(fx),
      na(fx),
      r1(fx),
      r2(fx),
      r3(fx),
      r3b(fx, r7_out),
      r4(fx),
      r5(fx),
      r6a(fx),
      r6b(fx),
      r7,
      r8a(fx),
      r8b(fx),
      r9(fx),
      r10(fx),
      pa(fx),
      pe(fx),
      pb(fx),
      pc(fx),
      pj(fx),
      r6c(fx),
      n1(fx),
      n3a(fx),
      n3b(fx),
      po(fx),
      lk(fx),
      nl(fx),
      lks(fx),
      lkv(fx),
      re(fx),
      lkm(fx)
    ]
  end

  defp p1(fx) do
    plant(fx, "P1", tagged_test(~s(@tag oc: "#{@green}")))

    verify("P1 positive: a new test tagged to a SUCCESS check passes", gate(fx, "P1"),
      exit: 0,
      final: "OC-GATE PASS",
      has: ["PASS  ", "#{@green} -> SUCCESS", "measured client leg"]
    )
  end

  defp na(fx) do
    plant(fx, "NA", [{"docs/oc_gate_control.md", "no test/ or lib/ change\n"}])

    verify("NA: a branch touching neither test/ nor lib/ is not applicable", gate(fx, "NA"),
      exit: 0,
      final: "OC-GATE N/A"
    )
  end

  defp r1(fx, extra \\ []) do
    plant(fx, "R1", tagged_test(""), extra)

    verify("R1 untagged new test [guard: classify/untagged]", gate(fx, "R1"),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["[new]  untagged: no @tag oc:"]
    )
  end

  # An EXISTING untagged test, one token added to its body: changed, not new.
  defp r2(fx) do
    {file, line} = existing_untagged_test(fx)
    lines = fx |> Path.join(file) |> File.read!() |> String.split("\n")
    edited = List.insert_at(lines, line, "    _ = :oc_gate_control_r2")
    plant(fx, "R2", [{file, Enum.join(edited, "\n")}])

    verify("R2 changed body, untagged [guard: new/changed diff + untagged]", gate(fx, "R2"),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: [file, "[changed: body]  untagged:"]
    )
  end

  defp r3(fx, extra \\ []) do
    plant(fx, "R3", tagged_test(~s(@tag oc: "#{@skipped}")), extra)

    verify("R3 tagged to a SKIPPED check [guard: judge/not_success]", gate(fx, "R3"),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["#{@skipped} -> SKIPPED (not_success:"]
    )
  end

  # A check that is FAILURE in THIS tree's live run, found in R7's run rather than
  # hardcoded — so the case survives the fix that turns today's red rows green.
  defp r3b(fx, r7_out) do
    case red_token(r7_out) do
      nil ->
        {"R3b tagged to a live FAILURE check", :fail,
         "no FAILURE row found in R7's server run — cannot plant; " <>
           "if the server leg is now all green, re-point this case at a client FAILURE"}

      token ->
        plant(fx, "R3b", tagged_test(~s(@tag oc: "#{token}")))

        verify(
          "R3b tagged to a live FAILURE check (#{token}) [guard: judge/not_success]",
          gate(fx, "R3b"),
          exit: 1,
          final: "OC-GATE REFUSE (1)",
          has: ["#{token} -> FAILURE (not_success:"]
        )
    end
  end

  defp r4(fx) do
    plant(fx, "R4", tagged_test(~s(@tag oc: "#{@ghost}")))

    verify("R4 tag naming a nonexistent check [guard: judge/unresolved]", gate(fx, "R4"),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["#{@ghost} -> - (unresolved:"]
    )
  end

  defp r5(fx) do
    plant(fx, "R5", tagged_test("@tag oc: :none"))

    verify("R5 oc: :none with no reason [guard: classify/none_without_reason]", gate(fx, "R5"),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["none_without_reason:"]
    )
  end

  defp r6a(fx, extra \\ []) do
    empty = Path.join(Path.dirname(fx), "no-harness")
    File.mkdir_p!(empty)
    plant(fx, "R6a", tagged_test(~s(@tag oc: "#{@green}")), extra)

    verify(
      "R6a harness absent [guard: HarnessHost/harness_unavailable]",
      gate(fx, "R6a", ["--harness-dir", empty]),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["harness_unavailable: no harness at #{empty}"]
    )
  end

  defp r6b(fx) do
    path =
      System.get_env("PATH")
      |> String.split(":")
      |> Enum.reject(&File.exists?(Path.join(&1, "node")))
      |> Enum.join(":")

    plant(fx, "R6b", tagged_test(~s(@tag oc: "#{@green}")))

    verify(
      "R6b no node on PATH [guard: HarnessHost/harness_unavailable]",
      gate(fx, "R6b", [], [{"PATH", path}]),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["harness_unavailable: no `node` on PATH"]
    )
  end

  defp r7(fx, extra \\ []) do
    plant(fx, "R7", tagged_test(~s(@tag oc: "#{@bare}")), extra)
    {out, status} = gate(fx, "R7")

    result =
      verify("R7 the fieldIssue tie without # [guard: judge/ambiguous]", {out, status},
        exit: 1,
        final: "OC-GATE REFUSE (1)",
        has: [
          "(ambiguous:",
          "matches 3 rows; add one of #missing-meta, #missing-protocol-version, " <>
            "#missing-client-capabilities"
        ]
      )

    {result, out}
  end

  # HEAD is one commit AHEAD of the branch: the live legs would measure a tree
  # other than the tip. Ahead, not main: the task recompiles on start, so a HEAD on
  # main would run main's gate source and a mutation carried by the branch never.
  defp r8a(fx, extra \\ []) do
    plant(fx, "R8", tagged_test(~s(@tag oc: "#{@green}")), extra)
    git!(fx, ["checkout", "-q", "-B", "R8-ahead", "R8"])
    write_all(fx, [{"docs/oc_gate_control_ahead.md", "ahead\n"}])
    commit!(fx, "control: HEAD ahead of R8")

    verify(
      "R8a HEAD is not the branch tip [guard: tree_refusal/wrong_tree]",
      gate(fx, "R8"),
      exit: 1,
      final: "OC-GATE REFUSE (1): wrong_tree",
      has: ["wrong_tree: HEAD is"]
    )
  end

  defp r8b(fx) do
    git!(fx, ["checkout", "-q", "R8"])
    stray = Path.join(fx, "stray.txt")
    File.write!(stray, "dirty\n")

    try do
      verify("R8b the working tree is dirty [guard: tree_refusal/wrong_tree]", gate(fx, "R8"),
        exit: 1,
        final: "OC-GATE REFUSE (1): wrong_tree",
        has: ["the working tree is not clean"]
      )
    after
      File.rm!(stray)
    end
  end

  defp r9(fx) do
    verify("R9 an unresolvable key [guard: population/unresolvable]", gate(fx, "MES-404404"),
      exit: 1,
      final: "OC-GATE REFUSE (1): unresolvable",
      has: ["unresolvable_ref"]
    )
  end

  defp r10(fx) do
    plant(fx, "R10", tagged_test(~s(@tag oc: :none, oc_reason: "r"), ~s(@moduletag oc: :none)))

    verify("R10 @moduletag oc: [guard: classify/suite_level_tag]", gate(fx, "R10"),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["suite_level_tag:"]
    )
  end

  # --- correction round 1 (MES-160 CR 30211/30214, PM 30226) ------------------

  # PA, on the REAL repo pattern: one row appended to manifest_test.exs's @pairs
  # adds one ExUnit test and moves no test call's bytes.
  defp pa(fx, extra \\ []) do
    file = "test/conformance/manifest_test.exs"
    source = File.read!(Path.join(fx, file))
    row = ~s(    {:CWD_NOT_PROJECT_ROOT, ["invocation", "cwd_is_project_root"], false, true},\n)
    added = ~s(    {:CWD_NOT_PROJECT_ROOT, ["invocation", "cwd_is_project_root"], :no, true},\n)
    if length(String.split(source, row)) != 2, do: halt("PA: the @pairs row moved — re-point it")
    plant(fx, "PA", [{file, String.replace(source, row, row <> added)}], extra)

    verify(
      "PA a row added to manifest_test.exs @pairs [guard: file context + untagged]",
      gate(fx, "PA"),
      exit: 1,
      final: "OC-GATE REFUSE (",
      has: [file, "[changed: file]  untagged:"]
    )
  end

  @legacy "test/oc_gate_legacy_test.exs"
  @legacy_src ~S'''
  defmodule OcGateLegacyTest do
    use ExUnit.Case
    @value 1

    defp helper, do: :one

    for m <- [:a] do
      test "gen #{m}" do
        assert m
      end
    end

    test "reads" do
      assert @value == 1 and helper() == :one
    end
  end
  '''

  # A legacy untagged file committed on `<name>-base`; the branch edits one thing
  # OUTSIDE every test call. The gate diffs against that base.
  defp legacy(fx, name, from, to, what) do
    edited = String.replace(@legacy_src, from, to)
    if edited == @legacy_src, do: halt("#{name}: the edit did not apply")
    plant(fx, "#{name}-base", [{@legacy, @legacy_src}])
    git!(fx, ["checkout", "-q", "-B", name, "#{name}-base"])
    write_all(fx, [{@legacy, edited}])
    commit!(fx, "control plant #{name}")

    verify(
      "#{name} #{what} [guard: file context + untagged]",
      gate(fx, name, ["--base", "#{name}-base"]),
      exit: 1,
      final: "OC-GATE REFUSE (2)",
      has: [
        inspect(~S("gen #{m}")) <> "  [changed: file]  untagged:",
        ~s("reads"  [changed: file]  untagged:)
      ]
    )
  end

  defp pe(fx), do: legacy(fx, "PE", "[:a]", "[:a, :b]", "a for gains a generator element")
  defp pb(fx), do: legacy(fx, "PB", "@value 1\n", "@value 2\n", "only a module attribute changed")

  defp pc(fx),
    do: legacy(fx, "PC", "do: :one", "do: :two", "only a same-file defp helper changed")

  # PJ: an existing GREEN-tagged test is re-declared onto a SKIPPED check, body
  # untouched. The tag is part of the test's fingerprint, so it is re-verified.
  defp pj(fx, extra \\ []) do
    # A mutation rides the BASE: on the branch it would change conformance/ and
    # the N2 re-measure would refuse the retag by another route.
    plant(fx, "PJ-base", tagged_test(~s(@tag oc: "#{@green}")), extra)
    git!(fx, ["checkout", "-q", "-B", "PJ", "PJ-base"])
    write_all(fx, tagged_test(~s(@tag oc: "#{@skipped}")))
    commit!(fx, "control plant PJ")

    verify(
      "PJ a green test re-tagged onto a SKIPPED check [guard: tag fingerprint + not_success]",
      gate(fx, "PJ", ["--base", "PJ-base"]),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["[changed: tags]", "#{@skipped} -> SKIPPED (not_success:"]
    )
  end

  # R6c: a harness install whose dist is NOT the pinned build — a copy of the real
  # one with one comment line appended — is refused, naming the pinned sha.
  defp r6c(fx, extra \\ []) do
    copy = Path.join(Path.dirname(fx), "foreign-harness")

    unless File.dir?(copy) do
      File.cp_r!(HarnessHost.default_harness_dir(), copy)
      File.write!(HarnessHost.dist(copy), "\n// not the pinned build\n", [:append])
    end

    plant(fx, "R6c", tagged_test(~s(@tag oc: "#{@green}")), extra)

    verify(
      "R6c a non-pinned harness dist [guard: Census.build expect_harness_dist_sha256]",
      gate(fx, "R6c", ["--harness-dir", copy]),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["run_not_accepted:", "is not the expected #{HarnessHost.pinned_dist_sha256()}"]
    )
  end

  # N1: the runner raises (its out dir cannot be made) — refused with the final
  # line intact, not a crash.
  defp n1(fx) do
    not_a_dir = Path.join(Path.dirname(fx), "out-root-is-a-file")
    File.write!(not_a_dir, "")
    plant(fx, "N1", tagged_test(~s(@tag oc: "#{@green}")))

    verify(
      "N1 the runner raises [guard: run_runner/run_not_accepted]",
      gate(fx, "N1", ["--out-root", not_a_dir]),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: ["run_not_accepted: the client leg did not run:"]
    )
  end

  # N3 (Q5, live): a branch that changes ONLY lib/ re-measures an existing
  # oc-tagged test. (a) a green one passes, (b) a SKIPPED one is refused — (b) is
  # the discriminating limb: an empty re-measure population would pass it.
  defp n3(fx, name, token, expect, extra \\ []) do
    # A mutation rides the base, so the branch's diff is lib/ and nothing else.
    plant(fx, "#{name}-base", tagged_test(~s(@tag oc: "#{token}")), extra)
    git!(fx, ["checkout", "-q", "-B", name, "#{name}-base"])
    lib = "lib/mcp/protocol.ex"
    write_all(fx, [{lib, File.read!(Path.join(fx, lib)) <> "\n# oc-gate control #{name}\n"}])
    commit!(fx, "control plant #{name}: lib/ only")
    gate_out = gate(fx, name, ["--base", "#{name}-base"])

    case expect do
      :pass ->
        verify("#{name} lib/-only branch re-measures a green oc-tagged test (Q5)", gate_out,
          exit: 0,
          final: "OC-GATE PASS (",
          has: ["0 new/changed", ~s("planted"  [unchanged]  #{token} -> SUCCESS)]
        )

      :refuse ->
        verify(
          "#{name} lib/-only branch re-measures a SKIPPED oc-tagged test (Q5) [guard: tagged_elsewhere + not_success]",
          gate_out,
          exit: 1,
          final: "OC-GATE REFUSE (1)",
          has: [~s("planted"  [unchanged]  #{token} -> SKIPPED (not_success:)]
        )
    end
  end

  defp n3a(fx), do: n3(fx, "N3a", @green, :pass)
  defp n3b(fx, extra \\ []), do: n3(fx, "N3b", @skipped, :refuse, extra)

  # --- correction round 2 (MES-160 CR 30255, PM 30256) ------------------------

  @po "test/oc_gate_position_test.exs"
  @po_src ~S'''
  defmodule OcGatePositionTest do
    use ExUnit.Case
    @x 1
    test "alpha", do: assert(@x > 0)
    @x 2
    test "beta", do: assert(@x > 0)
  end
  '''

  # PO: a test MOVED across a module-attribute redefinition, no statement's bytes
  # changed. The file context is equal; alpha now reads @x = 2. Only the slot sees it.
  defp po(fx, extra \\ []) do
    alpha = "  test \"alpha\", do: assert(@x > 0)\n"

    moved =
      @po_src |> String.replace(alpha, "") |> String.replace("  @x 2\n", "  @x 2\n" <> alpha)

    if moved == @po_src, do: halt("PO: the move did not apply")
    # A mutation rides the BASE, so the branch's diff is test/ and nothing else.
    plant(fx, "PO-base", [{@po, @po_src}], extra)
    git!(fx, ["checkout", "-q", "-B", "PO", "PO-base"])
    write_all(fx, [{@po, moved}])
    commit!(fx, "control plant PO")

    verify(
      "PO a test moved across an attribute redefinition [guard: position slot + untagged]",
      gate(fx, "PO", ["--base", "PO-base"]),
      exit: 1,
      final: "OC-GATE REFUSE (1)",
      has: [~s("alpha"  [changed: position]  untagged:)]
    )
  end

  # --- MES-236: gate 7 on a mix.lock-only change (PO ruling 2026-11-12) -------
  #
  # Every lock branch's diff against its base is `mix.lock` and nothing else: a
  # plant or a mutation rides the BASE. The lock edit swaps two entries, which
  # changes the file's bytes and no dependency.

  @plant_stale {"conformance/lib/mcp/conformance/classification.ex",
                ~s(    "http-custom-header-server-validation" => "SEP-2243 custom-header validation"\n),
                ~s(    "http-custom-header-server-validation" => "SEP-2243 custom-header validation",\n) <>
                  ~s(    "http-custom-headers" => "oc-gate control plant: a stale classification"\n)}

  # LK: a mix.lock-only branch is applicable, re-measures, and runs both legs.
  defp lk(fx, extra \\ []) do
    lock_branch(fx, "LK", [], extra)

    verify(
      "LK a mix.lock-only branch is not N/A: every leg runs whole [guard: lock_changed]",
      gate(fx, "LK", ["--base", "LK-base"]),
      exit: 0,
      final: "OC-GATE PASS (",
      has: [
        "mix.lock changed: true",
        "measured client leg",
        "measured server leg",
        "2 whole run(s)"
      ]
    )
  end

  # NL: a file NAMED mix.lock below the root is not the project's lock.
  defp nl(fx) do
    plant(fx, "NL", [{"docs/oc_gate_control/mix.lock", "%{}\n"}])

    verify("NL a nested mix.lock is not the project lock: still N/A", gate(fx, "NL"),
      exit: 0,
      final: "OC-GATE N/A"
    )
  end

  # LKS, the MES-227 shape: the dependency set now makes a classified scenario
  # pass. Planted as a stale classification of the passing http-custom-headers on
  # the base, with a test tagged to a check in it; the branch touches mix.lock
  # only. The planted test must be re-measured and refused on its own line.
  defp lks(fx, extra \\ []) do
    lock_branch(fx, "LKS", tagged_test(~s(@tag oc: "#{@green}")) ++ [stale_plant(fx)], extra)

    verify(
      "LKS a mix.lock-only branch re-measures an oc-tagged test (MES-227 shape) [guard: remeasure on lock_changed]",
      gate(fx, "LKS", ["--base", "LKS-base"]),
      exit: 1,
      final: "OC-GATE REFUSE (",
      has: [
        ~s("planted"  [unchanged]  #{@green} -> - (run_not_accepted:),
        "CLASSIFICATION_STALE"
      ]
    )
  end

  # LKV, the vacuity control: as LKS, but NO test carries a check token, so no
  # declaration names a leg. A lock change still runs every leg whole and refuses
  # the run the census does not accept.
  defp lkv(fx, extra \\ []) do
    lock_branch(fx, "LKV", [stale_plant(fx) | untokened_tests(fx)], extra)

    verify(
      "LKV a mix.lock-only branch with no oc-tagged test still measures [guard: forced legs + whole-run refusal]",
      gate(fx, "LKV", ["--base", "LKV-base"]),
      exit: 1,
      final: "OC-GATE REFUSE (1) of 0 declaration(s)",
      has: [
        "0 new/changed declaration(s), 0 unchanged oc-tagged",
        "REFUSE  run_not_accepted (client leg, mix.lock changed):",
        "CLASSIFICATION_STALE"
      ]
    )
  end

  # RE (CR-RE, correction round 1): the root lock RENAMED away. With rename
  # detection the diff lists only `deps.lock`, and the gate printed N/A. The base
  # points Mix at `deps.lock`, so the renamed tip still compiles with the same
  # dependency entries; the branch's only change is the rename.
  defp re(fx, extra \\ []) do
    from = "      elixirc_paths: elixirc_paths(Mix.env()),\n"
    mix = main_blob(fx, "mix.exs")
    if length(String.split(mix, from)) != 2, do: halt("RE: the mix.exs anchor is not found once")

    plant(
      fx,
      "RE-base",
      [{"mix.exs", String.replace(mix, from, from <> ~s(      lockfile: "deps.lock",\n))}],
      extra
    )

    git!(fx, ["checkout", "-q", "-B", "RE", "RE-base"])
    git!(fx, ["mv", "mix.lock", "deps.lock"])
    commit!(fx, "control plant RE: rename the root mix.lock")
    status = git!(fx, ["diff", "--name-status", "RE-base...RE"])

    unless status =~ ~r/^R100\s+mix\.lock\s+deps\.lock$/,
      do: halt("RE: the diff is #{inspect(status)}, not a pure rename")

    verify(
      "RE the root mix.lock renamed away is a lock change [guard: --no-renames]",
      gate(fx, "RE", ["--base", "RE-base"]),
      exit: 0,
      final: "OC-GATE PASS (",
      has: [
        "mix.lock changed: true",
        "measured client leg",
        "measured server leg",
        "2 whole run(s)"
      ]
    )
  end

  # LKM (correction round 1, the CR's tripwire): a forced leg whose measurement
  # goes MISSING is refused by the forced-leg rule itself. The base carries
  # CR-M15 (the client entry deleted after measuring) and no check token, so no
  # declaration can refuse in its place, and no census refusal is planted.
  @cr_m15 {"measurements = measure(legs, pop.tip, opts)",
           ~s[measurements = measure(legs, pop.tip, opts) |> Map.delete("client")]}
  @lkm_task "conformance/lib/mix/tasks/conformance.oc_gate.ex"

  defp lkm(fx, extra \\ []) do
    {from, to} = @cr_m15
    # A mutation of the task rides on top of the planted CR-M15, not instead of it.
    task_src =
      case List.keyfind(extra, @lkm_task, 0) do
        {_, src} -> src
        nil -> main_blob(fx, @lkm_task)
      end

    if length(String.split(task_src, from)) != 2,
      do: halt("LKM: the CR-M15 site is not found once")

    extra = List.keydelete(extra, @lkm_task, 0)

    lock_branch(
      fx,
      "LKM",
      [{@lkm_task, String.replace(task_src, from, to)} | untokened_tests(fx)],
      extra
    )

    verify(
      "LKM a forced leg with no measurement is refused [guard: run_refusals accepts only an accepted run]",
      gate(fx, "LKM", ["--base", "LKM-base"]),
      exit: 1,
      final: "OC-GATE REFUSE (1) of 0 declaration(s)",
      has: [
        ~s(legs measured: ["server"]),
        "REFUSE  measurement_missing (client leg, mix.lock changed): the leg was forced and not measured"
      ]
    )
  end

  # `name-base` = main + mutation + base plant; `name` = base + the lock swap.
  defp lock_branch(fx, name, base_files, extra) do
    # LK plants nothing on its base: unmutated, the base is main itself.
    plant(fx, "#{name}-base", base_files, extra)
    git!(fx, ["checkout", "-q", "-B", name, "#{name}-base"])
    [head, a, b | rest] = fx |> Path.join("mix.lock") |> File.read!() |> String.split("\n")
    if a == b, do: halt("#{name}: the two mix.lock entries are equal; the swap is a no-op")
    write_all(fx, [{"mix.lock", Enum.join([head, b, a | rest], "\n")}])
    commit!(fx, "control plant #{name}: mix.lock only")
    diff = git!(fx, ["diff", "--name-only", "#{name}-base...#{name}"])
    if diff != "mix.lock", do: halt("#{name}: the branch diff is #{inspect(diff)}, not mix.lock")
  end

  defp stale_plant(fx) do
    {file, from, to} = @plant_stale
    src = main_blob(fx, file)

    if length(String.split(src, from)) != 2,
      do: halt("stale plant: site not found once in #{file}")

    {file, String.replace(src, from, to)}
  end

  # Every test file's check tokens rewritten to `:none`; the files that carry none
  # are left alone. Halts if there was nothing to rewrite.
  defp untokened_tests(fx) do
    files =
      fx
      |> git!(["ls-tree", "-r", "--name-only", "main", "--", "test/"])
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.ends_with?(&1, "_test.exs"))
      |> Enum.map(fn file ->
        src = main_blob(fx, file)
        {file, src, Regex.replace(~r/@tag oc:\s*(\[[^\]]*\]|"oc:[^"]*")/s, src, "@tag oc: :none")}
      end)
      |> Enum.reject(fn {_, src, out} -> out == src end)
      |> Enum.map(fn {file, _, out} -> {file, out} end)

    if files == [], do: halt("LKV: no test carries a check token to rewrite")
    files
  end

  # A file as `main` has it, read from git objects, so a case never inherits the
  # previous case's checkout. Not trimmed: the bytes are written back.
  defp main_blob(fx, file) do
    case System.cmd("git", ["-C", fx, "show", "main:#{file}"], stderr_to_stdout: true) do
      {out, 0} -> out
      {out, code} -> halt("git show main:#{file} exited #{code}: #{out}")
    end
  end

  # --- the mutations ---------------------------------------------------------

  @decls "conformance/lib/mcp/conformance/oc_gate_declarations.ex"
  @judge "conformance/lib/mcp/conformance/oc_gate.ex"
  @task "conformance/lib/mix/tasks/conformance.oc_gate.ex"

  defp mutations(fx) do
    [
      mutate(
        "M1 any status counts as SUCCESS",
        "R3",
        fn e -> r3(fx, e) end,
        {@judge, ~s(if status == "SUCCESS",), ~s(if status != nil,)}
      ),
      mutate(
        "M2 an untagged test reads as a declared none",
        "R1",
        fn e -> r1(fx, e) end,
        {@decls, "do: {:refuse, :untagged, ", "do: {:none, "}
      ),
      mutate(
        "M3 the harness precondition is skipped",
        "R6a",
        fn e -> r6a(fx, e) end,
        {@judge, "case HarnessHost.unavailable_reason(harness_dir) do", "case nil do"}
      ),
      mutate(
        "M4 a bare token on a tie reads as a typo",
        "R7",
        fn e -> r7(fx, e) |> elem(0) end,
        {@judge, ~s(siblings != [] and (decoded.discriminator == "" or),
         ~s(false and (decoded.discriminator == "" or)}
      ),
      mutate(
        "M5 the HEAD-is-tip check is off",
        "R8a",
        fn e -> r8a(fx, e) end,
        {@task, "head != {:ok, tip} ->", "false ->"}
      ),
      mutate(
        "M6 a refusal exits 0",
        "R1",
        fn e -> r1(fx, e) end,
        {@task, ~s[\#{whole}, \#{ms} ms")\n      exit({:shutdown, 1})],
         ~s[\#{whole}, \#{ms} ms")\n      :ok]}
      ),
      mutate(
        "M7 the file context is ignored",
        "PA",
        fn e -> pa(fx, e) end,
        {@decls, "file_moved? = base_ctx != tip_ctx", "file_moved? = false"}
      ),
      mutate(
        "M8 a test's tags are not part of its fingerprint",
        "PJ",
        fn e -> pj(fx, e) end,
        {@decls, "b.tag_fingerprint != d.tag_fingerprint ->", "false ->"}
      ),
      mutate(
        "M9 the run is not pinned to the harness build",
        "R6c",
        fn e -> r6c(fx, e) end,
        {@judge, "expect_harness_dist_sha256: HarnessHost.pinned_dist_sha256()",
         "expect_harness_dist_sha256: nil"}
      ),
      mutate(
        "M10 a lib/ change re-measures nothing",
        "N3b",
        fn e -> n3b(fx, e) end,
        {@decls, "remeasure = lib_changed or conformance_changed", "remeasure = false"}
      ),
      mutate(
        "M11 a test's position slot is not compared",
        "PO",
        fn e -> po(fx, e) end,
        {@decls, "b.position != d.position ->", "false ->"}
      ),
      mutate(
        "M12 mix.lock is dropped from the applicability match",
        "LK",
        fn e -> lk(fx, e) end,
        {@task, " or pop.lock_changed) ->", ") ->"}
      ),
      mutate(
        "M13 a mix.lock change re-measures nothing",
        "LKS",
        fn e -> lks(fx, e) end,
        {@decls, "remeasure = lib_changed or conformance_changed or lock_changed",
         "remeasure = lib_changed or conformance_changed"}
      ),
      mutate(
        "M14 a mix.lock change forces no leg",
        "LKV",
        fn e -> lkv(fx, e) end,
        {@task, "defp forced_legs(%{lock_changed: true}), do: @all_legs",
         "defp forced_legs(%{lock_changed: true}), do: []"}
      ),
      mutate(
        "M15 a forced client measurement is lost after measuring (CR-M15)",
        "LKV",
        fn e -> lkv(fx, e) end,
        {@task, elem(@cr_m15, 0), elem(@cr_m15, 1)}
      ),
      mutate(
        "M16 a missing forced measurement reads as accepted",
        "LKM",
        fn e -> lkm(fx, e) end,
        {@task, "case Map.fetch(measurements, leg) do",
         ~s|case Map.fetch(Map.put_new(measurements, leg, {:ok, %{rows: []}}), leg) do|}
      ),
      mutate(
        "M17 rename detection restored in the name list",
        "RE",
        fn e -> re(fx, e) end,
        {@decls, ~s(["diff", "--no-renames", "--name-only",), ~s(["diff", "--name-only",)}
      )
    ]
  end

  # Runs `case_fun` on a branch carrying the mutation and requires the case RED.
  defp mutate(label, case_name, case_fun, {file, from, to}) do
    source = File.read!(Path.join(@project, file))
    n = source |> String.split(from) |> length() |> Kernel.-(1)

    if n != 1 do
      halt("#{label}: mutation site found #{n} times in #{file}, need exactly 1 — re-point it")
    end

    {_, result, detail} = case_fun.([{file, String.replace(source, from, to)}])
    # The first line of a red case's detail is its fault list: WHY it went red.
    why = detail |> to_string() |> String.split("\n") |> hd()

    if result == :fail,
      do: {"#{label} -> #{case_name} RED as required (#{why})", :pass, detail},
      else: {"#{label} -> #{case_name} stayed GREEN: the case cannot fail", :fail, detail}
  end

  # --- fixtures --------------------------------------------------------------

  defp in_root(fun) do
    root = Path.join(System.tmp_dir!(), "oc_gate_controls_#{System.unique_integer([:positive])}")
    fx = Path.join(root, "repo")

    # The exit status is decided INSIDE and acted on OUTSIDE: System.halt/1 inside
    # the try would skip the `after`, leaking the root on exactly the red runs.
    status =
      try do
        head = git!(@project, ["rev-parse", "HEAD"])
        git!(root |> tap(&File.mkdir_p!/1), ["clone", "-q", "--no-checkout", @project, fx])
        git!(fx, ["checkout", "-q", "-B", "main", head])
        for d <- ["deps", "_build"], do: File.cp_r!(Path.join(@project, d), Path.join(fx, d))
        IO.puts("fixture: #{fx} at #{String.slice(head, 0, 7)}")
        summarise(fun.(fx))
      catch
        {:control_halt, msg} ->
          IO.puts("CONTROL HALTED: " <> msg)
          1
      after
        File.rm_rf!(root)
      end

    if status != 0, do: System.halt(status)
  end

  # A branch off `main`: an optional mutation commit, then the plant commit.
  defp plant(fx, branch, files, mutation \\ []) do
    git!(fx, ["checkout", "-q", "-B", branch, "main"])

    if mutation != [] do
      write_all(fx, mutation)
      commit!(fx, "control mutation")
    end

    # A lock case's base may carry a mutation and nothing else (M12 on LK).
    if files != [] do
      write_all(fx, files)
      commit!(fx, "control plant #{branch}")
    end
  end

  defp write_all(fx, files) do
    for {path, body} <- files do
      File.mkdir_p!(Path.dirname(Path.join(fx, path)))
      File.write!(Path.join(fx, path), body)
    end
  end

  defp tagged_test(tag, moduletag \\ "") do
    [
      {"test/oc_gate_plant_test.exs",
       """
       defmodule OcGatePlantTest do
         use ExUnit.Case
         #{moduletag}
         #{tag}
         test "planted" do
           assert true
         end
       end
       """}
    ]
  end

  # The first `test "…" do` line with no @tag oc: in the four lines above it.
  defp existing_untagged_test(fx) do
    fx
    |> git!(["ls-files", "test/"])
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.ends_with?(&1, "_test.exs"))
    |> Enum.sort()
    |> Enum.find_value(fn file ->
      lines = fx |> Path.join(file) |> File.read!() |> String.split("\n")

      Enum.find_value(Enum.with_index(lines), fn {l, i} ->
        above = lines |> Enum.slice(max(i - 4, 0), min(i, 4)) |> Enum.join("\n")

        if Regex.match?(~r/^  test "[^"#]+" do$/, l) and not String.contains?(above, "oc:"),
          do: {file, i + 1}
      end)
    end) || halt("R2: no existing untagged test found to change")
  end

  defp red_token(out) do
    with [_, dir] <- Regex.run(~r/measured server leg in \d+ ms: \d+ checks, (\S+)/, out),
         {:ok, census} <- Census.build(dir) do
      "server"
      |> OcGate.rows(dir, census)
      |> Map.fetch!(:rows)
      |> Enum.find(&(&1["status"] == "FAILURE"))
      |> case do
        nil -> nil
        row -> MatchKey.encode!(row["key"])
      end
    else
      _ -> nil
    end
  end

  # --- driving the task ------------------------------------------------------

  defp gate(fx, key, args \\ [], env \\ []) do
    refuse_foreign!(fx)
    # Compiled up front so a compile failure halts loudly here rather than
    # reading as a refusal; the task recompiles stale sources on start anyway.
    compile!(fx)
    runs = Path.join(Path.dirname(fx), "runs")
    args = if "--out-root" in args, do: args, else: ["--out-root", runs | args]

    System.cmd("mix", ["conformance.oc_gate", key | args],
      cd: fx,
      env: [{"MIX_ENV", "dev"} | env],
      stderr_to_stdout: true
    )
  end

  defp compile!(fx) do
    {out, code} = System.cmd("mix", ["compile"], cd: fx, stderr_to_stdout: true)
    if code != 0, do: halt("mix compile in the fixture exited #{code}:\n#{out}")
  end

  defp refuse_foreign!(fx) do
    top = git!(fx, ["rev-parse", "--show-toplevel"])

    unless Path.expand(top) == Path.expand(fx) and
             Path.basename(Path.dirname(fx)) =~ "oc_gate_controls_",
           do: halt("REFUSING TO RUN: #{fx} is not this run's fixture clone (toplevel #{top})")
  end

  # --- adjudication ----------------------------------------------------------

  defp verify(label, {out, status}, expect) do
    final =
      out |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "OC-GATE")) |> List.last()

    corresponds =
      status == if(final && String.starts_with?(final, "OC-GATE REFUSE"), do: 1, else: 0)

    faults =
      [
        status != expect[:exit] && "exit #{status}, expected #{expect[:exit]}",
        not corresponds && "exit #{status} does not correspond to #{inspect(final)}",
        not (final && String.starts_with?(final, expect[:final])) &&
          "final line #{inspect(final)}, expected #{inspect(expect[:final])}"
      ] ++
        for s <- Keyword.get(expect, :has, []),
            not String.contains?(out, s),
            do: "missing #{inspect(s)}"

    case Enum.filter(faults, & &1) do
      [] -> {label, :pass, final}
      fs -> {label, :fail, Enum.join(fs, "; ") <> "\n" <> indent(out)}
    end
  end

  defp summarise(results) do
    for {label, result, detail} <- results do
      IO.puts("#{if result == :pass, do: "PASS", else: "FAIL"}  #{label}")
      if result != :pass, do: IO.puts(detail)
    end

    failed = Enum.count(results, &(elem(&1, 1) != :pass))
    IO.puts("\n#{length(results) - failed}/#{length(results)} controls hold")
    if failed > 0, do: 1, else: 0
  end

  defp indent(out), do: out |> String.split("\n") |> Enum.map_join("\n", &("      | " <> &1))

  defp commit!(fx, msg) do
    git!(fx, ["add", "-A"])

    git!(fx, [
      "-c",
      "user.name=control",
      "-c",
      "user.email=c@c",
      "commit",
      "-q",
      "--no-verify",
      "-m",
      msg
    ])
  end

  defp git!(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      {out, code} -> halt("git #{Enum.join(args, " ")} in #{dir} exited #{code}: #{out}")
    end
  end

  # Thrown, not halted: `in_root/1` catches it after cleaning up.
  defp halt(msg), do: throw({:control_halt, msg})
end

OcGateControls.run(System.argv())

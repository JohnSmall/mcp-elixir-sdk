# Controls for the D7 PM-alone lane guard (MES-100).
#
#     mix run conformance/controls/pm_alone_lane_guard_controls.exs
#     mix run conformance/controls/pm_alone_lane_guard_controls.exs mutation
#     mix run conformance/controls/pm_alone_lane_guard_controls.exs guard-mutation
#
# WHAT THIS IS EVIDENCE OF. D7 ships a fail-closed merge guard: a PM Task whose branch
# touched a reviewable path is refused. The brief requires it shown RED on a branch that
# touched one and GREEN on a docs-only branch — fail-then-pass, per A7. Neither state can
# be found lying around, so each is BUILT: a throwaway git repository with its own `main`
# and its own branch, in the state the case is about.
#
# IT DRIVES THE REAL TEXT, NOT A RETYPED COPY. `extract_guard/0` pulls the fenced block
# out of CLAUDE.md itself and substitutes the fixture's branch for `{TICKET_KEY}`. A drift
# between CLAUDE.md and this control is therefore impossible by construction. What it
# CANNOT anchor is CLAUDE.md against D7 on Confluence 250052681 — a committed second copy
# would be one transcription checked against itself, not an independent anchor. That check
# was done by hand on MES-100 (guard string md5 b154f3c95c9d71da41f7516dc9ca0f38, 238
# bytes, page v15) and is stated as a residual rather than faked.
#
# EVERY CASE ADJUDICATES ON THE REFUSE MESSAGE, NEVER ON THE EXIT STATUS. Measured on
# MES-100 (S9-22): as the last command of a script the guard exits 1 on a CLEAN docs-only
# branch — grep's own status surviving as the `&&` list's status — which is the same status
# as the refusal. Exit status does not distinguish the two verdicts, so it is printed as an
# observation and decided on by nothing. E1/E2 below are that measurement, run.
#
# P1 IS NOT DECORATION. A guard that refused everything would "pass" all five reds
# vacuously, so the docs-only positive control is what makes R1-R5 mean anything. N1-N4 are
# the other side: a guard that over-refuses pushes real PM Tasks into the reviewed lane and
# the lane dies of noise.
#
# IT CANNOT TOUCH THE REAL REPOSITORY. Every fixture lives under a root generated per run,
# and `refuse_foreign_fixture!/3` re-reads the work tree out of git before each run and
# refuses unless it resolves inside THAT root. G1-G4 hold that guard to the property, and
# `guard-mutation` puts weakened predicates back in charge and requires the same paths to be
# ADMITTED — so the G cases are shown able to fail. The only thing read out of this clone is
# CLAUDE.md (and, in MG3 alone, a read-only `git rev-parse`); nothing is written here.
#
# THE MUTATIONS ARE IN MEMORY. `mutation` mutates the EXTRACTED snippet, never the file —
# a seat death mid-run must not leave this shared clone holding a mutated CLAUDE.md (S8-14).

defmodule PmAloneLaneGuardControls do
  @project File.cwd!()
  @branch "MES-FIXTURE"
  # The containment guard's refusals open with this. `guard/3` rescues RuntimeError, and
  # git's own failures are RuntimeErrors too, so without this marker a fixture that merely
  # blew up would be scored as a refusal.
  @refusal "REFUSING TO RUN"

  @reds [
    {"R1", "lib/", "lib/mcp/transport.ex"},
    {"R2", "test/", "test/mcp/transport_test.exs"},
    {"R3", "conformance/lib/", "conformance/lib/run_provenance.ex"},
    {"R4", "conformance/controls/", "conformance/controls/some_controls.exs"},
    {"R5", "docs/conformance/", "docs/conformance/etcc-membership.md"}
  ]

  @near_misses [
    {"N1", "mylib/a.ex", "a directory ENDING in lib/ — the ^ anchor is what refuses it"},
    {"N2", "docs/conformance-testing.md", "a real file: docs/conformance MINUS the slash"},
    {"N3", "other/lib/a.ex", "lib/ nested under another directory"},
    {"N4", "test_helper.exs", "a root file starting with test — the slash is what saves it"}
  ]

  def run([]) do
    in_fixture_root(fn root ->
      g = extract_guard()

      [p1(root, g)] ++
        reds(root, g) ++
        near_misses(root, g) ++ [t1(root, g), x1(root, g)] ++ e1(root, g) ++ guards(root, g)
    end)
  end

  def run(["mutation"]), do: in_fixture_root(&mutation(&1, extract_guard()))
  def run(["guard-mutation"]), do: in_fixture_root(&guard_mutation(&1, extract_guard()))

  def run(_) do
    IO.puts(
      "usage: mix run conformance/controls/pm_alone_lane_guard_controls.exs " <>
        "[mutation|guard-mutation]"
    )

    System.halt(2)
  end

  defp in_fixture_root(fun) do
    root =
      Path.join(
        System.tmp_dir!(),
        "pm_alone_lane_guard_controls_#{System.unique_integer([:positive])}"
      )

    try do
      summarise(fun.(root))
    after
      File.rm_rf!(root)
    end
  end

  # --- the guard, taken out of CLAUDE.md ---------------------------------------
  #
  # Three things are asserted about the extraction itself, because each of them failing
  # silently would make every case below vacuous: exactly one fenced block carries the
  # refusal, it carries exactly one `{TICKET_KEY}` to substitute, and it echoes exactly
  # one message. The message is READ OUT of the snippet rather than restated here — a
  # restatement is the second copy this control exists to avoid.

  defp extract_guard do
    source = File.read!(Path.join(@project, "CLAUDE.md"))

    snippet =
      ~r/```bash\n(.*?)\n```/s
      |> Regex.scan(source)
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.filter(&String.contains?(&1, "REFUSE PM-alone"))
      |> one!("bash block in CLAUDE.md carrying \"REFUSE PM-alone\"")

    _ =
      ~r/\{TICKET_KEY\}/
      |> Regex.scan(snippet)
      |> one!("{TICKET_KEY} placeholder in the extracted guard")

    message =
      ~r/echo "([^"]*)"/
      |> Regex.scan(snippet)
      |> Enum.map(&Enum.at(&1, 1))
      |> one!("echoed message in the extracted guard")

    IO.puts("""
      guard extracted from CLAUDE.md (#{byte_size(snippet)} bytes):
    #{indent(snippet)}
      refusal message adjudicated on: #{message}
    """)

    %{snippet: snippet, message: message}
  end

  defp one!([one], _what), do: one

  defp one!(many, what) do
    raise "CANNOT EXTRACT — found #{length(many)} of: #{what}. Expected exactly one. " <>
            "The guard has been renamed, removed or duplicated in CLAUDE.md; every control " <>
            "below would otherwise run against the wrong text or no text at all."
  end

  # --- driving it --------------------------------------------------------------

  defp run_guard(root, work, script, key) do
    refuse_foreign_fixture!(root, work)

    System.cmd("bash", ["-c", String.replace(script, "{TICKET_KEY}", key)],
      cd: work,
      stderr_to_stdout: true
    )
  end

  defp verdict(out, message), do: if(String.contains?(out, message), do: :refuse, else: :allow)

  defp expect(id, what, {out, status}, message, want) do
    got = verdict(out, message)
    unless got == want, do: IO.puts(indent(out))

    check(
      id,
      "#{what}\n        verdict: #{got} (wanted #{want})" <>
        "   exit #{status} — recorded, not adjudicated on (S9-22)",
      got == want
    )
  end

  # --- P1: the positive control ------------------------------------------------

  defp p1(root, g) do
    work = fixture(root, "p1", ["CLAUDE.md", "docs/sprint_9_issues.md", "README.md"])

    expect(
      "P1",
      "a docs-only branch is NOT refused — the positive control",
      run_guard(root, work, g.snippet, @branch),
      g.message,
      :allow
    )
  end

  # --- R1-R5: one per reviewable prefix ----------------------------------------
  #
  # Five, not one: the pattern is an alternation, and a single case leaves four
  # alternatives unexercised — any of which could be dropped without a control noticing.

  defp reds(root, g) do
    Enum.map(@reds, fn {id, prefix, file} ->
      work = fixture(root, String.downcase(id), ["CLAUDE.md", file])

      expect(
        id,
        "reviewable path #{file} (#{prefix}) is REFUSED",
        run_guard(root, work, g.snippet, @branch),
        g.message,
        :refuse
      )
    end)
  end

  # --- N1-N4: the near misses --------------------------------------------------

  defp near_misses(root, g) do
    Enum.map(@near_misses, fn {id, file, why} ->
      work = fixture(root, String.downcase(id), ["CLAUDE.md", file])

      expect(
        id,
        "#{file} is NOT refused — #{why}",
        run_guard(root, work, g.snippet, @branch),
        g.message,
        :allow
      )
    end)
  end

  # --- T1: the three dots are load-bearing (F3) --------------------------------
  #
  # The fixture is the failure the gate-6 applicability rule already documents, in the
  # lane guard's clothes: the branch touched CLAUDE.md only, then MAIN moved and touched
  # lib/. Two-dot compares the two tips and reports main's own edit as the branch's, so it
  # refuses a legitimate PM Task. Three-dot diffs from the merge-base and does not. The
  # canonical snippet is right; T1 exists so nobody later "tidies" it.

  defp t1(root, g) do
    work = fixture(root, "t1", ["CLAUDE.md"])
    commit(work, "lib/moved_on_main.ex", "main's own edit, made after the branch was cut")

    canonical = run_guard(root, work, g.snippet, @branch)
    two_dot = run_guard(root, work, String.replace(g.snippet, "main...", "main.."), @branch)

    IO.puts("      T1  three-dot: #{git!(work, ["diff", "--name-only", "main...#{@branch}"])}")
    IO.puts("      T1  two-dot:   #{git!(work, ["diff", "--name-only", "main..#{@branch}"])}")

    canonical? = verdict(elem(canonical, 0), g.message) == :allow
    two_dot? = verdict(elem(two_dot, 0), g.message) == :refuse

    check(
      "T1",
      "main moved and touched lib/ after the branch was cut:\n" <>
        "        three-dot (canonical) allows the docs-only branch: #{canonical?}\n" <>
        "        two-dot refuses it for main's own edit: #{two_dot?}",
      canonical? and two_dot?
    )
  end

  # --- X1: the F2 hole, recorded as observed (S9-23) ---------------------------
  #
  # NOT a case the guard passes. The branch here really does touch lib/, so the honest
  # verdict is REFUSE — but with an unresolvable key git prints `fatal:` to stderr, puts
  # nothing on stdout, grep matches nothing, the && is not taken and the guard falls
  # through GREEN. A check that cannot determine its input answers "fine". D7 §3 heads
  # this "Guarded fail-closed"; on this input it is not. Remedy owned by MES-106; the
  # string above is D7's and is shipped verbatim, so this control documents the hole
  # rather than asserting a fix.

  defp x1(root, g) do
    work = fixture(root, "x1", ["lib/a.ex"])
    {out, status} = run_guard(root, work, g.snippet, "MES-NOSUCH")

    fell_through? = verdict(out, g.message) == :allow
    fatal? = String.contains?(out, "fatal:")

    check(
      "X1",
      "an unresolvable ref on a branch that DOES touch lib/ (S9-23, remedy MES-106):\n" <>
        "        git could not resolve it: #{fatal?}\n" <>
        "        the guard fell through green anyway: #{fell_through?}   exit #{status}",
      fell_through? and fatal?
    )
  end

  # --- E1/E2: the exit status measured (S9-22) ---------------------------------

  defp e1(root, g) do
    clean = fixture(root, "e1clean", ["CLAUDE.md"])
    dirty = fixture(root, "e1dirty", ["lib/a.ex"])

    {clean_out, clean_status} = run_guard(root, clean, g.snippet, @branch)
    {_, dirty_status} = run_guard(root, dirty, g.snippet, @branch)

    {_, followed_status} =
      run_guard(root, clean, g.snippet <> "\necho 'the guard fell through'", @branch)

    [
      check(
        "E1",
        "exit status does NOT distinguish the verdicts (S9-22, remedy MES-106):\n" <>
          "        clean docs-only branch, guard as last line: exit #{clean_status}, " <>
          "output #{inspect(clean_out)}\n" <>
          "        reviewable branch, refused:                 exit #{dirty_status}",
        clean_status == 1 and dirty_status == 1
      ),
      check(
        "E2",
        "the 1 is grep's status surviving the && list, not a verdict:\n" <>
          "        same clean branch with ONE command after the guard: exit #{followed_status}",
        followed_status == 0
      )
    ]
  end

  # --- G1-G4: the containment guard held to its property ------------------------

  defp guards(root, _g) do
    work = fixture(root, "g", ["CLAUDE.md"])

    [
      accepts("G1", work, guard(root, work)),
      refuses("G2", same_tmp_sibling(), guard(root, same_tmp_sibling())),
      refuses("G3", prefix_escape(), guard(root, prefix_escape())),
      refuses("G4", @project, guard(root, @project))
    ]
  end

  defp accepts(id, path, outcome) do
    IO.puts("      #{id}  #{path}\n        -> #{describe(outcome)}")

    check(
      id,
      "the run's own in-root fixture is ACCEPTED — the guard's positive control",
      outcome == :ok
    )
  end

  defp refuses(id, path, outcome) do
    case outcome do
      {:refused, message} ->
        IO.puts("      -- #{id}: the refusal this case requires, as raised --")
        IO.puts(indent(message))

      other ->
        IO.puts("      -- #{id}: NOT REFUSED — #{describe(other)} --")
    end

    check(
      id,
      "outside this run's root, REFUSED:\n        #{path}",
      match?({:refused, _}, outcome)
    )
  end

  # --- mutation: the cases shown able to fail ----------------------------------
  #
  #     mix run conformance/controls/pm_alone_lane_guard_controls.exs mutation
  #
  # P1, R1-R5 and N1-N4 all end in `check/3` returning true, which is equally consistent
  # with cases that cannot fail. So each mutation below breaks ONE property of the
  # extracted snippet IN MEMORY and requires the cases that rest on that property to flip.
  # Note which case answers which mutation: N1/N3 rest on the ^ anchor, N2/N4 rest on the
  # TRAILING SLASH, and R2 rests on its alternative being present at all. Dropping the
  # anchor does not move N2 or N4 — the near-misses are not interchangeable, and a
  # mutation mode that asserted they were would be evidence of nothing.

  defp mutation(root, g) do
    IO.puts("  -- the flipped verdicts below are this mode's expected output, not a defect --")

    unanchored = String.replace(g.snippet, "'^(", "'(")

    unslashed =
      g.snippet
      |> String.replace("test/|", "test|")
      |> String.replace("conformance/)", "conformance)")

    dropped = String.replace(g.snippet, "test/|", "")

    [
      mutated(root, g, "M1", unanchored, "the ^ anchor dropped", [
        {"N1", "mylib/a.ex", :refuse},
        {"N3", "other/lib/a.ex", :refuse}
      ]),
      mutated(root, g, "M2", unslashed, "the trailing slashes dropped", [
        {"N2", "docs/conformance-testing.md", :refuse},
        {"N4", "test_helper.exs", :refuse}
      ]),
      mutated(root, g, "M3", dropped, "the test/ alternative dropped", [
        {"R2", "test/mcp/transport_test.exs", :allow}
      ])
    ]
    |> List.flatten()
  end

  defp mutated(root, g, id, script, what, cases) do
    if script == g.snippet do
      [check(id, "#{what} — THE MUTATION DID NOT APPLY, so the cases below prove nothing", false)]
    else
      Enum.map(cases, fn {case_id, file, want} ->
        work =
          fixture(root, "#{String.downcase(id)}_#{String.downcase(case_id)}", ["CLAUDE.md", file])

        expect(
          "#{id}/#{case_id}",
          "with #{what}, #{file} flips to #{want} — #{case_id} can fail",
          run_guard(root, work, script, @branch),
          g.message,
          want
        )
      end)
    end
  end

  # --- guard-mutation: G1-G4 shown able to fail --------------------------------
  #
  #     mix run conformance/controls/pm_alone_lane_guard_controls.exs guard-mutation
  #
  # The same three paths G2-G4 refuse are put to WEAKENED predicates and must now be
  # ADMITTED. MG1/MG2 use the raw /tmp string prefix that MES-95's review corrected — it
  # admits a /tmp sibling and admits /tmp_prefix_escape, because both strings start with
  # "/tmp". MG3 removes containment altogether, because no string-prefix predicate is weak
  # enough to admit this clone: G4's protection rests on containment EXISTING, not on the
  # separator fix, and a mutation that could not admit it would leave G4 unfalsified.

  defp guard_mutation(root, _g) do
    IO.puts("  -- the ADMITTED lines below are this mode's expected output, not a defect --")

    [
      admitted("MG1", same_tmp_sibling(), guard(root, same_tmp_sibling(), &tmp_prefix?/2)),
      admitted("MG2", prefix_escape(), guard(root, prefix_escape(), &tmp_prefix?/2)),
      admitted("MG3", @project, guard(root, @project, fn _, _ -> true end))
    ]
  end

  defp admitted(id, path, outcome) do
    IO.puts("      #{id}  #{path}\n        -> #{describe(outcome)}")

    check(
      id,
      "the weakened predicate ADMITS what the delivered guard refuses — the G case can fail",
      not match?({:refused, _}, outcome)
    )
  end

  defp describe(:ok), do: "ADMITTED by the guard"
  defp describe({:refused, _}), do: "refused by the guard"

  defp describe({:raised, message}) do
    "ADMITTED by the guard; the run then died on git's own error, which is not a refusal: " <>
      (message |> String.split("\n") |> hd())
  end

  # --- the containment guard ----------------------------------------------------
  #
  # Fail-closed, and re-read from git rather than remembered: the directory this run is
  # about to shell into must resolve — as git resolves it, not as the string looks — inside
  # THIS run's generated root. The path limb is decided BEFORE any git command runs in it:
  # a directory the guard has not cleared is not one to shell into. The predicate is the
  # boundary-safe form MES-95's review arrived at; `guard-mutation` runs the superseded one.

  defp guard(root, work, contains \\ &contained?/2) do
    refuse_foreign_fixture!(root, work, contains)
    :ok
  rescue
    e in RuntimeError ->
      message = Exception.message(e)
      if String.starts_with?(message, @refusal), do: {:refused, message}, else: {:raised, message}
  end

  defp refuse_foreign_fixture!(root, work, contains \\ &contained?/2) do
    unless contains.(work, root), do: refuse!(root, work, nil, "path")
    top = git!(work, ["rev-parse", "--show-toplevel"])
    unless contains.(top, root), do: refuse!(root, work, top, "resolved work tree")
  end

  # Canonical containment, boundary-safe: the candidate must BE the root or lie under it
  # ACROSS A PATH SEPARATOR. `Path.expand/1` canonicalises both sides so the comparison is
  # not between raw strings; the separator is what stops `/tmp_prefix_escape` being read as
  # a child of `/tmp`.
  defp contained?(candidate, root) do
    root = Path.expand(root)
    candidate = Path.expand(candidate)

    candidate == root or String.starts_with?(candidate, with_separator(root))
  end

  defp with_separator(path), do: if(String.ends_with?(path, "/"), do: path, else: path <> "/")

  # The predicate EXACTLY as MES-95 delivered it, kept so the correction's red half is RUN
  # and not merely described. It decides nothing in the G cases.
  defp tmp_prefix?(candidate, _root),
    do: String.starts_with?(Path.expand(candidate), Path.expand(System.tmp_dir!()))

  defp refuse!(root, work, resolved, limb) do
    raise """
    #{@refusal} — the fixture is not a fixture: its #{limb} is outside this run's root.
      root:     #{root}
      repo:     #{work}
      resolved: #{resolved || "(not read — the path was refused before any git ran in it)"}
    These controls run `git diff main...<branch>` inside whatever they are handed. Handed
    this clone, the evidence would be about MES-100's own branch instead of a fixture.
    """
  end

  defp tmp, do: Path.expand(System.tmp_dir!())
  defp same_tmp_sibling, do: Path.join(tmp(), "outside_same_tmp")
  defp prefix_escape, do: Path.join(tmp() <> "_prefix_escape", "repo")

  # --- the fixture --------------------------------------------------------------

  defp fixture(root, name, files) do
    work = Path.join(root, name)
    File.mkdir_p!(work)

    git!(work, ["init", "--quiet", "-b", "main"])
    git!(work, ["config", "user.name", "PM-alone lane controls"])
    git!(work, ["config", "user.email", "controls@example.invalid"])

    commit(work, "base.md", "fixture #{name}, before the branch was cut")

    git!(work, ["checkout", "--quiet", "-b", @branch])
    Enum.each(files, &commit(work, &1, "#{name}: the branch's change to #{&1}"))
    git!(work, ["checkout", "--quiet", "main"])

    work
  end

  defp commit(repo, file, text) do
    path = Path.join(repo, file)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text <> "\n")
    git!(repo, ["add", file])
    git!(repo, ["commit", "--quiet", "-m", text])
  end

  defp git!(repo, args) do
    case System.cmd("git", args, cd: repo, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      {out, n} -> raise "git #{Enum.join(args, " ")} exited #{n} in #{repo}: #{out}"
    end
  end

  # --- adjudication -------------------------------------------------------------

  defp indent(text), do: text |> String.split("\n") |> Enum.map_join("\n", &("        " <> &1))

  defp check(id, what, true) do
    IO.puts("  PASS  #{id}  #{what}")
    true
  end

  defp check(id, what, false) do
    IO.puts("  FAIL  #{id}  #{what}")
    false
  end

  defp summarise(results) do
    failed = Enum.count(results, &(&1 == false))

    IO.puts("\n  #{length(results)} control(s), #{failed} failed\n")
    if failed > 0, do: System.halt(1)
  end
end

PmAloneLaneGuardControls.run(System.argv())

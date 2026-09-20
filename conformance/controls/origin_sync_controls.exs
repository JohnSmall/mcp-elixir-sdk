# Controls for `mix origin.sync` (MES-95).
#
#     mix run conformance/controls/origin_sync_controls.exs
#
# WHAT THIS IS EVIDENCE OF. The brief requires the instrument shown RED with origin
# behind and GREEN in sync — fail-then-pass, per A7. The repository was measured in
# sync on 2026-09-19 and again on 2026-09-20, so the red cases cannot be found; they
# have to be BUILT. Each case below constructs a throwaway git fixture in a state the
# rule forbids, drives THE REAL TASK against it, and requires the named conjunct to be
# the one that fails.
#
# P1 IS NOT DECORATION. A check that is red on everything would "pass" every red case
# here vacuously, so the positive control — the same fixture, in sync, exit 0, five
# greens — is what makes the five reds mean anything (S8-3).
#
# IT DRIVES THE TASK, NOT A COPY OF ITS LOGIC. `mix origin.sync --repo/--remote/--version`
# exists for exactly this: a control that re-implemented the decision would be evidence
# about the control.
#
# IT CANNOT TOUCH THE REAL REPOSITORY. Every fixture lives under a root generated per
# run, and `refuse_foreign_fixture!/2` re-reads the repo path and the remote URL out of
# the fixture itself before each run and refuses unless BOTH resolve inside THAT root.
# Nothing here fetches, pushes to, or writes a ref in this clone.
#
# AND THE GUARD IS ITSELF UNDER CONTROL (G0-G3). The first version of that guard tested a
# raw string prefix against System.tmp_dir!/0, so it admitted any /tmp sibling outside the
# run's root and admitted /tmp_prefix_escape as well — weaker than the property the eight
# cases above it rest on. The G cases below drive the corrected guard directly and require
# it to REFUSE both, with the real in-root fixture accepted.

defmodule OriginSyncControls do
  @version "0.0.1-fixture.1"
  # The guard's own refusals open with this. `guard/3` rescues RuntimeError, and git's
  # failures are RuntimeErrors too, so without this marker a fixture that merely blew up
  # would be scored as a refusal — which is how the guard-mutation mode's MG3 would pass
  # while the guard had admitted the path.
  @refusal "REFUSING TO RUN"
  @project File.cwd!()

  def run(["mutation"]), do: in_fixture_root(&[mutation(&1)])
  def run(["guard-mutation"]), do: in_fixture_root(&guard_mutation/1)

  def run([]) do
    in_fixture_root(&([p1(&1), r1(&1), r2(&1), r3(&1), r4(&1)] ++ r5(&1) ++ guards(&1)))
  end

  def run(_) do
    IO.puts(
      "usage: mix run conformance/controls/origin_sync_controls.exs [mutation|guard-mutation]"
    )

    System.halt(2)
  end

  defp in_fixture_root(fun) do
    root =
      Path.join(System.tmp_dir!(), "origin_sync_controls_#{System.unique_integer([:positive])}")

    try do
      summarise(fun.(root))
    after
      File.rm_rf!(root)
    end
  end

  # --- the mutation: the ADJUDICATOR shown firing ------------------------------
  #
  # P1 through R5a all end in `verify/3` returning true. That is consistent with an
  # adjudicator that returns true unconditionally, and no positive control can
  # separate the two — it IS the same call. So here the in-sync fixture is checked
  # against a DELIBERATELY WRONG expectation (C2 red, exit 1, on a repository that is
  # in sync). `verify/3` must come back FALSE and must name both faults. A run where
  # this case "passes" is a run whose other seven results mean nothing.

  defp mutation(root) do
    work = fixture(root, "mutation", push_tag: true)
    {out, status} = origin_sync(root, work)

    IO.puts("  -- the FAIL line below is this case's expected output, not a defect --")

    fired? =
      not verify("MUT", "an in-sync fixture asserted to be C2-red and exit 1",
        expect_exit: 1,
        expect: %{c2: :red},
        out: out,
        status: status,
        quiet: true
      )

    check("MUT", "the adjudicator refuses an expectation the run does not support", fired?)
  end

  # --- P1: the positive control ------------------------------------------------

  defp p1(root) do
    work = fixture(root, "p1", push_tag: true)

    {out, status} = origin_sync(root, work)

    verify("P1", "fixture in sync — the positive control",
      expect_exit: 0,
      expect: %{c1: :green, c2: :green, c3: :green, c4: :green, c5: :green},
      out: out,
      status: status
    )
  end

  # --- R1: main not pushed -----------------------------------------------------

  defp r1(root) do
    work = fixture(root, "r1", push_tag: true)
    commit(work, "local-only.txt", "a merge that was never published")

    {out, status} = origin_sync(root, work)

    verify("R1", "a commit on main that was never pushed",
      expect_exit: 1,
      expect: %{c1: :green, c2: :red, c3: :green, c4: :green, c5: :green},
      out: out,
      status: status
    )
  end

  # --- R2: the S7-47 lapse — main pushed, tag not ------------------------------

  defp r2(root) do
    work = fixture(root, "r2", push_tag: false)

    {out, status} = origin_sync(root, work)

    verify("R2", "main pushed, tag NOT pushed — what a bare `git push origin main` leaves",
      expect_exit: 1,
      expect: %{c1: :green, c2: :green, c3: :green, c4: :red, c5: :green},
      out: out,
      status: status
    )
  end

  # --- R3: same tag name, different objects ------------------------------------

  defp r3(root) do
    work = fixture(root, "r3", push_tag: true)
    # Re-make the tag locally. Same name, same commit, a NEW tag object — which is
    # what an amended merge followed by `git tag -f` produces, and what a name-only
    # check on origin cannot see.
    git!(work, ["tag", "-f", "-a", @version, "-m", "re-made"])

    {out, status} = origin_sync(root, work)

    verify("R3", "the tag exists on both sides under one name, as two different objects",
      expect_exit: 1,
      expect: %{c1: :green, c2: :green, c3: :green, c4: :red, c5: :green},
      out: out,
      status: status
    )
  end

  # --- R4: the fail-closed limb ------------------------------------------------

  defp r4(root) do
    work = fixture(root, "r4", push_tag: true)
    git!(work, ["remote", "set-url", "origin", Path.join(root, "r4-no-such-repo.git")])

    {out, status} = origin_sync(root, work)

    verify("R4", "origin unreachable — RED, never green, and C2/C4 undetermined not passed",
      expect_exit: 1,
      expect: %{c1: :red, c2: :undetermined, c3: :green, c4: :undetermined, c5: :green},
      out: out,
      status: status
    )
  end

  # --- R5: the cache control, and the case that earns the deviation ------------

  defp r5(root) do
    work = fixture(root, "r5", push_tag: true)

    # A SECOND clone moves the remote. `work` never fetches, so its
    # refs/remotes/origin/main still holds the sha it pushed.
    other = Path.join(root, "r5-other")
    git!(root, ["clone", "--quiet", bare(root, "r5"), other])
    identity(other)
    commit(other, "elsewhere.txt", "someone else published this")
    git!(other, ["push", "--quiet", "origin", "HEAD:main"])

    cached = git!(work, ["rev-parse", "origin/main"])
    local = git!(work, ["rev-parse", "main"])
    live = work |> git!(["ls-remote", "origin", "refs/heads/main"]) |> String.split("\t") |> hd()

    {out, status} = origin_sync(root, work)

    IO.puts("""
      the brief's literal form, on THIS fixture:
        git rev-parse origin/main  -> #{short(cached)}
        git rev-parse main         -> #{short(local)}
        equal? #{cached == local}  => the rev-parse check exits 0, GREEN
      the live remote, on the same fixture:
        ls-remote refs/heads/main  -> #{short(live)}
        equal to local main? #{live == local}\
    """)

    ok? =
      verify("R5", "a STALE refs/remotes/origin/main matching local main while origin has moved",
        expect_exit: 1,
        expect: %{c1: :green, c2: :red, c3: :green, c4: :green, c5: :green},
        out: out,
        status: status
      )

    also? =
      check(
        "R5a",
        "the rev-parse form is GREEN on the very fixture origin.sync calls RED",
        cached == local and live != local
      )

    [ok?, also?]
  end

  # --- G: the containment guard, shown accepting the fixture and refusing escapes ----
  #
  # Added by the MES-95 correction round, on CR's blocking finding. `refuse_foreign_fixture!/2`
  # is the safety property the eight cases above rest on, and it was the one thing here not
  # itself under control: as delivered it was weaker than the claim written over it, and the
  # runs were clean only because the fixtures happen to build under the root.
  #
  # RED-THEN-GREEN, COMMITTED RATHER THAN CLAIMED. `superseded_guard_accepts?/1` is the
  # delivered predicate kept verbatim. Every escape case asserts BOTH that the superseded
  # predicate ACCEPTED the path — which is what makes it a genuine escape and not merely a
  # bad path — and that the corrected guard REFUSES it. If the old predicate ever stops
  # accepting one of these, the case fails and says so rather than passing vacuously.
  #
  # THE ESCAPE PATHS ARE DELIBERATELY NOT CREATED ON DISK. The guard must decide on the path
  # alone, before it touches anything; and creating them would leave litter outside the root
  # these controls clean up. G3 exercises the repo limb, whose refusal must therefore fire
  # before `git remote get-url` is ever run in a directory that does not exist.

  defp guards(root) do
    work = fixture(root, "g", push_tag: true)

    [
      g0(root, work),
      escape(
        root,
        work,
        "G1",
        "a sibling in the same tmp dir, outside this run's root",
        same_tmp_sibling()
      ),
      escape(
        root,
        work,
        "G2",
        "a prefix escape — #{prefix_escape_dir()} is not a child of #{tmp()}",
        prefix_escape()
      ),
      g3(root)
    ]
  end

  # G0: the positive control. Without it, a guard that refused everything would "pass"
  # G1-G3 vacuously — and would also stop the other eight cases from running at all.
  defp g0(root, work) do
    url = git!(work, ["remote", "get-url", "origin"])
    outcome = guard(root, work)

    if match?({:refused, _}, outcome), do: IO.puts(indent(elem(outcome, 1)))

    check(
      "G0",
      "the real in-root fixture is ACCEPTED — the guard is not simply refusing everything" <>
        "\n        repo   #{work}\n        origin #{url}",
      outcome == :ok and superseded_guard_accepts?(work) and superseded_guard_accepts?(url)
    )
  end

  # G1/G2: the origin-URL limb, on the two shapes CR's probe found the old guard admitting.
  defp escape(root, work, id, what, url) do
    git!(work, ["remote", "set-url", "origin", url])
    outcome = guard(root, work)
    git!(work, ["remote", "set-url", "origin", bare(root, "g")])

    adjudicate(id, what, url, outcome)
  end

  # G3: the OTHER limb. The guard has two conjuncts and each needs its own escape, or one
  # of them is asserted rather than measured.
  defp g3(root) do
    adjudicate(
      "G3",
      "the repo limb — a work tree in the same tmp dir, outside this run's root",
      repo_escape(),
      guard(root, repo_escape())
    )
  end

  defp adjudicate(id, what, path, outcome) do
    was_accepted? = superseded_guard_accepts?(path)

    case outcome do
      {:refused, message} ->
        IO.puts("      -- #{id}: the refusal this case requires, as raised --")
        IO.puts(indent(message))

      other ->
        IO.puts("      -- #{id}: NOT REFUSED — #{describe(other)} --")
    end

    check(
      id,
      "#{what}\n        #{path}\n        superseded guard accepted it: #{was_accepted?}" <>
        "   corrected guard refuses it: #{match?({:refused, _}, outcome)}",
      match?({:refused, _}, outcome) and was_accepted?
    )
  end

  # --- the guard mutation: the G cases shown FALSIFIABLE ------------------------
  #
  #     mix run conformance/controls/origin_sync_controls.exs guard-mutation
  #
  # G1-G3 all end in `check/3` returning true, which is equally consistent with G cases
  # that cannot fail. So here the SUPERSEDED predicate is put back in charge of the real
  # guard and the same three escapes are re-run: each must now be ADMITTED. That is the
  # correction's red half executed rather than asserted — the old guard let these through,
  # the corrected one does not, and it is the fix that makes G1-G3 pass.
  #
  # MG3 is why `guard/3` distinguishes a refusal from any other raise: its work tree does
  # not exist, so under the superseded predicate the guard admits the path and `git remote
  # get-url` then fails on its own. Scoring that as a refusal would have shown MG3 passing
  # over a guard that had admitted the path.

  defp guard_mutation(root) do
    work = fixture(root, "gm", push_tag: true)

    IO.puts("  -- the ADMITTED lines below are this mode's expected output, not a defect --")

    [
      admits_url(root, work, "MG1", same_tmp_sibling()),
      admits_url(root, work, "MG2", prefix_escape()),
      admitted("MG3", repo_escape(), guard(root, repo_escape(), &superseded_contains?/2))
    ]
  end

  defp admits_url(root, work, id, url) do
    git!(work, ["remote", "set-url", "origin", url])
    outcome = guard(root, work, &superseded_contains?/2)
    git!(work, ["remote", "set-url", "origin", bare(root, "gm")])

    admitted(id, url, outcome)
  end

  defp admitted(id, path, outcome) do
    IO.puts("      #{id}  #{path}\n        -> #{describe(outcome)}")

    check(
      id,
      "the superseded predicate ADMITS what the corrected guard refuses — the G case can fail",
      not match?({:refused, _}, outcome)
    )
  end

  defp describe(:ok), do: "ADMITTED by the guard"
  defp describe({:refused, _}), do: "refused by the guard"

  defp describe({:raised, message}) do
    "ADMITTED by the guard; the run then died on git's own error, which is not a refusal: " <>
      (message |> String.split("\n") |> hd())
  end

  defp guard(root, work, contains \\ &contained?/2) do
    refuse_foreign_fixture!(root, work, contains)
    :ok
  rescue
    e in RuntimeError ->
      message = Exception.message(e)
      if String.starts_with?(message, @refusal), do: {:refused, message}, else: {:raised, message}
  end

  # The containment predicate EXACTLY as MES-95 delivered it, kept so the correction's red
  # half is RUN and not merely described. In the G cases it decides nothing — it only shows
  # what the old guard said about the same path. `guard-mutation` puts it back in charge.
  defp superseded_contains?(candidate, _root) do
    String.starts_with?(Path.expand(candidate), Path.expand(System.tmp_dir!()))
  end

  defp superseded_guard_accepts?(path), do: superseded_contains?(path, :root_is_ignored)

  defp tmp, do: Path.expand(System.tmp_dir!())
  defp same_tmp_sibling, do: Path.join(tmp(), "outside_same_tmp.git")
  defp prefix_escape_dir, do: tmp() <> "_prefix_escape"
  defp prefix_escape, do: Path.join(prefix_escape_dir(), "repo.git")
  defp repo_escape, do: Path.join(tmp(), "outside_same_tmp_repo")

  defp indent(text), do: text |> String.split("\n") |> Enum.map_join("\n", &("        " <> &1))

  # --- the fixture -------------------------------------------------------------

  defp fixture(root, name, opts) do
    work = Path.join(root, name)
    File.mkdir_p!(work)

    git!(root, ["init", "--quiet", "--bare", "-b", "main", bare(root, name)])
    git!(work, ["init", "--quiet", "-b", "main"])
    identity(work)
    git!(work, ["remote", "add", "origin", bare(root, name)])

    commit(work, "README.md", "fixture #{name}")
    git!(work, ["tag", "-a", @version, "-m", "fixture tag #{@version}"])
    # A commit AFTER the tag, so the fixture has the real repository's shape: the
    # tag peels to main~1, not to the tip. C5 asserts ancestor-or-equal for this
    # reason, and a tip check would be red on every case here.
    commit(work, "post-tag.md", "the post-merge record, committed after the tag")

    git!(work, ["push", "--quiet", "-u", "origin", "main"])
    if opts[:push_tag], do: git!(work, ["push", "--quiet", "origin", @version])

    work
  end

  defp bare(root, name), do: Path.join(root, "#{name}-origin.git")

  defp identity(repo) do
    git!(repo, ["config", "user.name", "Origin Sync Controls"])
    git!(repo, ["config", "user.email", "controls@example.invalid"])
  end

  defp commit(repo, file, text) do
    File.write!(Path.join(repo, file), text <> "\n")
    git!(repo, ["add", file])
    git!(repo, ["commit", "--quiet", "-m", text])
  end

  defp git!(repo, args) do
    case System.cmd("git", args, cd: repo, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      {out, n} -> raise "git #{Enum.join(args, " ")} exited #{n} in #{repo}: #{out}"
    end
  end

  # --- driving the real task ---------------------------------------------------

  defp origin_sync(root, work) do
    refuse_foreign_fixture!(root, work)

    System.cmd(
      "mix",
      ["origin.sync", "--repo", work, "--remote", "origin", "--version", @version],
      cd: @project,
      stderr_to_stdout: true
    )
  end

  # Fail-closed, and re-read from the fixture rather than remembered: both the repo this
  # run is about to shell into and the remote URL it is about to query must resolve inside
  # THIS run's generated root. R4 rewrites a remote URL, so "we built it, therefore it is
  # safe" is exactly the assumption that must not be made.
  #
  # The repo limb is decided BEFORE any git command runs in `work`: a directory the guard
  # has not cleared is not one to shell into, and `git remote get-url` in it would fail
  # with git's error rather than this refusal.
  #
  # CORRECTED in the MES-95 review round. As delivered this tested
  # `String.starts_with?(Path.expand(path), Path.expand(System.tmp_dir!()))` — a raw string
  # prefix against /tmp, not containment in the generated root. It therefore accepted a
  # /tmp sibling outside the root, and accepted /tmp_prefix_escape/... because that string
  # does start with "/tmp". Harmless in the runs only because the fixtures happen to be
  # built under the root — which is the assumption the guard exists to not make. G0-G3
  # hold the corrected form to the property.
  defp refuse_foreign_fixture!(root, work, contains \\ &contained?/2) do
    unless contains.(work, root), do: refuse!(root, work, nil, "repo path")
    url = git!(work, ["remote", "get-url", "origin"])
    unless contains.(url, root), do: refuse!(root, work, url, "origin URL")
  end

  # Canonical containment, boundary-safe: the candidate must BE the root or lie under it
  # ACROSS A PATH SEPARATOR. Path.expand/1 canonicalises both sides (`.`, `..`, repeated
  # and trailing separators) so the comparison is not between raw strings; the separator
  # is what stops `/tmp_prefix_escape` being read as a child of `/tmp`.
  defp contained?(candidate, root) do
    root = Path.expand(root)
    candidate = Path.expand(candidate)

    candidate == root or String.starts_with?(candidate, with_separator(root))
  end

  defp with_separator(path), do: if(String.ends_with?(path, "/"), do: path, else: path <> "/")

  defp refuse!(root, work, url, limb) do
    raise """
    #{@refusal} — the fixture is not a fixture: its #{limb} is outside this run's root.
      root:   #{root}
      repo:   #{work}
      origin: #{url || "(not read — the repo path was refused before any git ran in it)"}
    These controls drive a live ls-remote. Run them against a real remote and the
    evidence would be about that remote, and the next case would push to it.
    """
  end

  # --- adjudication ------------------------------------------------------------

  defp verify(id, what, opts) do
    seen = conjuncts(opts[:out])
    expect = opts[:expect]
    status = opts[:status]

    faults =
      Enum.flat_map(expect, fn {c, want} ->
        case Map.fetch(seen, c) do
          {:ok, ^want} -> []
          {:ok, got} -> ["#{String.upcase(to_string(c))} came back #{got}, wanted #{want}"]
          :error -> ["#{String.upcase(to_string(c))} was not reported at all"]
        end
      end) ++
        if status == opts[:expect_exit],
          do: [],
          else: ["exit #{status}, wanted #{opts[:expect_exit]}"]

    if faults == [] do
      check(id, what, true)
    else
      unless opts[:quiet], do: IO.puts(opts[:out])
      check(id, "#{what}\n      #{Enum.join(faults, "\n      ")}", false)
    end
  end

  defp conjuncts(out) do
    ~r/^\s*(GREEN|RED|UNDET)\s+(C\d)\b/m
    |> Regex.scan(out)
    |> Map.new(fn [_, mark, c] -> {conjunct_id(c), status(mark)} end)
  end

  defp conjunct_id("C1"), do: :c1
  defp conjunct_id("C2"), do: :c2
  defp conjunct_id("C3"), do: :c3
  defp conjunct_id("C4"), do: :c4
  defp conjunct_id("C5"), do: :c5

  defp status("GREEN"), do: :green
  defp status("RED"), do: :red
  defp status("UNDET"), do: :undetermined

  defp check(id, what, true) do
    IO.puts("  PASS  #{id}  #{what}")
    true
  end

  defp check(id, what, false) do
    IO.puts("  FAIL  #{id}  #{what}")
    false
  end

  defp short(sha), do: String.slice(sha, 0, 12)

  defp summarise(results) do
    failed = Enum.count(results, &(&1 == false))

    IO.puts("\n  #{length(results)} control(s), #{failed} failed\n")
    if failed > 0, do: System.halt(1)
  end
end

OriginSyncControls.run(System.argv())

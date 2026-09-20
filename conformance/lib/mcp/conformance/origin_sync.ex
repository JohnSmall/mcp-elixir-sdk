defmodule MCP.Conformance.OriginSync do
  @moduledoc """
  The instrument behind `mix origin.sync`: is this repository's published state
  the state we actually hold?

  ## What it is for (MES-95, S7-47)

  `main` on GitHub is the product surface — what people read, clone and file
  issues against — and the standing rule (overrides page, D8) is that the PM
  pushes `main` **and the merge's tag** as the final step of every merge gate.
  That rule had no instrument once before, lapsed silently for 30 commits and
  2.5 sprints, and was then rationalised as intentional. The blunt test of a
  rule is: *if every trace of it were removed, what goes red?* This module is
  the answer.

  ## Why not the obvious check

  The brief specified `git rev-parse origin/main` = `git rev-parse main`, plus
  "the merge's tag resolves on origin". Built literally, **both halves exit
  green over a divergent origin**, and both were measured doing so:

    * `origin/main` is `refs/remotes/origin/main` — an ordinary *local file*
      that changes only on fetch or push. Nothing re-reads the remote, so the
      verdict is a function of a local snapshot rather than of the remote it
      claims to describe. That is gate 6's limitation 1, in a second place.
    * `git ls-remote origin refs/tags/2.0.0-dev.999` — a tag that does not
      exist — exits **0** with empty output. So "the tag resolves on origin"
      cannot be established by an exit code at all. A null result and an unrun
      check are the same artefact (A7c).

  So every reading here comes from a **live `git ls-remote`**, and every
  decision is made on the **returned shas** — never on an exit code, never on a
  tracking ref.

  ## Fail-closed

  A conjunct that cannot be determined is `:undetermined`, and
  `t:verdict/0`'s `ok?` is true only when every conjunct is `:green`. An
  unreachable origin, an unreadable ref, a missing `git` — each is RED with its
  reason named, never green. "I could not tell" means *not verified*, the same
  ruling `mix conformance.sweep --host` already runs under.

  ## The five conjuncts

    * **C1** — `origin` is reachable and readable.
    * **C2** — the live `refs/heads/main` equals local `main`.
    * **C3** — the tag named by the project version exists locally and is
      **annotated**. D4 fixes the tag string as exactly the version with no
      leading `v`, so the expected name is *derived* rather than taken on trust.
    * **C4** — that tag exists on `origin` and its tag-object sha matches the
      local one. This is the conjunct a bare `git push origin main` fails: the
      S7-47 lapse exactly.
    * **C5** — the tag peels to a commit that is an **ancestor-or-equal** of
      local `main`. Not "on the tip": measured 2026-09-20, `2.0.0-dev.33` peels
      to `main~1` on a correct repo, because the PM's post-merge sweep record is
      committed after the tagged merge. A tip check would be red on a healthy
      tree.

  ## What it does not cover

  It checks the **current** version's tag only. That *every* `dev.N` in
  `mix.exs` history has a tag on the right commit is MES-90's, and is not built
  here.
  """

  @typedoc "A single conjunct's outcome. `:undetermined` is not a pass — see Fail-closed."
  @type status :: :green | :red | :undetermined

  @typedoc "One conjunct: its id, what it asserts, how it came out, and the evidence."
  @type conjunct :: %{
          id: :c1 | :c2 | :c3 | :c4 | :c5,
          claim: String.t(),
          status: status(),
          lines: [String.t()]
        }

  @type verdict :: %{ok?: boolean(), conjuncts: [conjunct()]}

  @typedoc """
  Everything read from git, as read. Kept separate from `decide/1` so the
  decision is a pure function of the readings and can be unit-tested without a
  network or a repository.
  """
  @type observation :: %{
          repo: String.t(),
          remote: String.t(),
          version: String.t(),
          tag: String.t(),
          local_main: {:ok, String.t()} | {:error, String.t()},
          live: {:ok, %{String.t() => String.t()}} | {:error, String.t()},
          local_tag:
            {:ok, %{object: String.t(), annotated?: boolean(), peels_to: String.t()}}
            | {:error, String.t()},
          ancestry: :ancestor_or_equal | :not_ancestor | {:error, String.t()},
          distance: String.t()
        }

  # ---------------------------------------------------------------------------
  # Observation — all the I/O, and nothing else
  # ---------------------------------------------------------------------------

  @doc """
  Read the live remote and the local repository.

  Required options: `:repo` (working directory), `:remote` (remote name) and
  `:version` (the project version, from which the expected tag name is derived).
  All three are parameters rather than constants so that `mix origin.sync` can be
  driven against a throwaway fixture by the controls — the same code path, only
  the inputs differ, and the task announces when they were supplied by hand.
  """
  @spec observe(keyword()) :: observation()
  def observe(opts) do
    repo = Keyword.fetch!(opts, :repo)
    remote = Keyword.fetch!(opts, :remote)
    version = Keyword.fetch!(opts, :version)
    tag = tag_for(version)

    local_main = read_local_main(repo)
    local_tag = read_local_tag(repo, tag)
    live = read_live(repo, remote, tag)

    %{
      repo: repo,
      remote: remote,
      version: version,
      tag: tag,
      local_main: local_main,
      live: live,
      local_tag: local_tag,
      ancestry: ancestry(repo, local_tag, local_main),
      distance: distance(repo, live, local_main)
    }
  end

  @doc """
  The tag name a version is expected to carry.

  D4 fixes it as exactly the version string — no leading `v`. Derived, so a
  renamed tag is a finding rather than a silent pass.

      iex> MCP.Conformance.OriginSync.tag_for("2.0.0-dev.33")
      "2.0.0-dev.33"
  """
  @spec tag_for(String.t()) :: String.t()
  def tag_for(version), do: version

  defp read_local_main(repo) do
    case git(repo, ["rev-parse", "--verify", "refs/heads/main"]) do
      {:ok, out} -> {:ok, String.trim(out)}
      {:error, why} -> {:error, why}
    end
  end

  defp read_local_tag(repo, tag) do
    ref = "refs/tags/" <> tag

    with {:ok, object} <- git(repo, ["rev-parse", "--verify", ref]),
         {:ok, type} <- git(repo, ["cat-file", "-t", String.trim(object)]),
         {:ok, peeled} <- git(repo, ["rev-parse", "--verify", ref <> "^{commit}"]) do
      {:ok,
       %{
         object: String.trim(object),
         annotated?: String.trim(type) == "tag",
         peels_to: String.trim(peeled)
       }}
    end
  end

  # ONE ls-remote, both refs, exact patterns — no globs, which would also match
  # a longer tag name. The result is a map of ref => sha built from the OUTPUT;
  # a ref the remote does not have is simply absent, which is the whole point:
  # on a missing ref this command exits 0 and prints nothing.
  defp read_live(repo, remote, tag) do
    case git(repo, ["ls-remote", remote, "refs/heads/main", "refs/tags/" <> tag]) do
      {:ok, out} -> {:ok, parse_ls_remote(out)}
      {:error, why} -> {:error, why}
    end
  end

  @doc """
  Parse `git ls-remote` output into `ref => sha`.

      iex> MCP.Conformance.OriginSync.parse_ls_remote("abc123\\trefs/heads/main\\n")
      %{"refs/heads/main" => "abc123"}

      iex> MCP.Conformance.OriginSync.parse_ls_remote("")
      %{}
  """
  @spec parse_ls_remote(String.t()) :: %{String.t() => String.t()}
  def parse_ls_remote(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 2) do
        [sha, ref] -> [{String.trim(ref), String.trim(sha)}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp ancestry(repo, {:ok, %{peels_to: peeled}}, {:ok, main}) do
    case git_status(repo, ["merge-base", "--is-ancestor", peeled, main]) do
      {_out, 0} -> :ancestor_or_equal
      {_out, 1} -> :not_ancestor
      {out, n} -> {:error, "git merge-base exited #{n}: #{String.trim(out)}"}
    end
  end

  defp ancestry(_repo, _local_tag, _local_main), do: {:error, "not attempted"}

  # How far apart, in commits, for the report. Only meaningful when both objects
  # are present locally — a remote that is AHEAD names a commit this clone has
  # never seen, and asking `rev-list` about it errors. That is a reporting
  # limitation, not a verdict: C2 has already decided on the shas.
  defp distance(repo, {:ok, live}, {:ok, main}) do
    case Map.fetch(live, "refs/heads/main") do
      {:ok, ^main} ->
        "0 (identical)"

      {:ok, remote_sha} ->
        count(repo, remote_sha, main)

      :error ->
        "not computable — origin has no refs/heads/main"
    end
  end

  defp distance(_repo, _live, _local_main), do: "not computable"

  defp count(repo, remote_sha, main) do
    case git(repo, ["rev-list", "--left-right", "--count", "#{remote_sha}...#{main}"]) do
      {:ok, out} -> render_count(out, remote_sha)
      {:error, _why} -> "not computable — #{short(remote_sha)} is not an object in this clone"
    end
  end

  defp render_count(out, remote_sha) do
    case String.split(String.trim(out)) do
      [behind, ahead] -> "local main is #{ahead} ahead, #{behind} behind origin"
      _ -> "unreadable rev-list output for #{short(remote_sha)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Decision — a pure function of the observation
  # ---------------------------------------------------------------------------

  @doc """
  Adjudicate an observation. Green only when all five conjuncts are green;
  `:undetermined` never counts as a pass.
  """
  @spec decide(observation()) :: verdict()
  def decide(obs) do
    conjuncts = [c1(obs), c2(obs), c3(obs), c4(obs), c5(obs)]

    %{ok?: Enum.all?(conjuncts, &(&1.status == :green)), conjuncts: conjuncts}
  end

  defp c1(%{live: {:ok, refs}, remote: remote}) do
    green(:c1, claim(:c1), ["#{remote} answered; #{map_size(refs)} of the 2 refs asked for exist"])
  end

  defp c1(%{live: {:error, why}, remote: remote}) do
    red(:c1, claim(:c1), [
      "#{remote} could not be read: #{why}",
      "RED and not skipped: an origin we cannot reach is an origin we cannot attest."
    ])
  end

  defp c2(%{live: {:error, _}}), do: undetermined(:c2, claim(:c2), ["origin unreadable (C1)"])

  defp c2(%{local_main: {:error, why}}),
    do: undetermined(:c2, claim(:c2), ["local main unreadable: #{why}"])

  defp c2(%{live: {:ok, refs}, local_main: {:ok, main}, distance: distance, remote: remote}) do
    case Map.fetch(refs, "refs/heads/main") do
      {:ok, ^main} ->
        green(:c2, claim(:c2), ["both at #{short(main)}"])

      {:ok, other} ->
        red(:c2, claim(:c2), [
          "live #{remote} refs/heads/main = #{short(other)}",
          "local main                      = #{short(main)}",
          "distance: #{distance}",
          "The push did not happen, or did not carry this commit."
        ])

      :error ->
        red(:c2, claim(:c2), [
          "#{remote} has no refs/heads/main at all.",
          "ls-remote exits 0 on a ref that is not there, so this is read off the",
          "OUTPUT, never off the status."
        ])
    end
  end

  defp c3(%{local_tag: {:error, why}, tag: tag}) do
    red(:c3, claim(:c3), [
      "no usable local tag #{tag}: #{why}",
      "The name is derived from the project version (D4), not taken on trust."
    ])
  end

  defp c3(%{local_tag: {:ok, %{annotated?: false, object: object}}, tag: tag}) do
    red(:c3, claim(:c3), [
      "#{tag} exists locally at #{short(object)} but is LIGHTWEIGHT, not annotated.",
      "D6 tags the merge with an annotated tag; a lightweight one carries no",
      "tagger, no date and no message, so the merge record is not in the object."
    ])
  end

  defp c3(%{local_tag: {:ok, %{object: object, peels_to: peeled}}, tag: tag}) do
    green(:c3, claim(:c3), ["#{tag} = annotated tag #{short(object)} -> commit #{short(peeled)}"])
  end

  defp c4(%{live: {:error, _}}), do: undetermined(:c4, claim(:c4), ["origin unreadable (C1)"])

  defp c4(%{local_tag: {:error, _}, tag: tag}),
    do: undetermined(:c4, claim(:c4), ["no local tag #{tag} to compare against (C3)"])

  defp c4(%{live: {:ok, refs}, local_tag: {:ok, %{object: object}}, tag: tag, remote: remote}) do
    case Map.fetch(refs, "refs/tags/" <> tag) do
      {:ok, ^object} ->
        green(:c4, claim(:c4), ["#{tag} on #{remote} = #{short(object)}, the same object"])

      {:ok, other} ->
        red(:c4, claim(:c4), [
          "#{tag} on #{remote} = #{short(other)}",
          "#{tag} locally     = #{short(object)}",
          "Same name, different objects — the tag was moved or re-made on one side."
        ])

      :error ->
        red(:c4, claim(:c4), [
          "#{remote} has no refs/tags/#{tag}.",
          "This is what a bare `git push origin main` leaves behind: the commits",
          "arrive and the tag does not. The S7-47 lapse exactly."
        ])
    end
  end

  defp c5(%{ancestry: :ancestor_or_equal, tag: tag}),
    do: green(:c5, claim(:c5), ["#{tag} peels to a commit main contains"])

  defp c5(%{ancestry: :not_ancestor, tag: tag} = obs) do
    red(:c5, claim(:c5), [
      "#{tag} peels to #{peel_text(obs)}, which is NOT an ancestor of local main.",
      "The tag is on a commit this branch does not contain — a tag made on the",
      "wrong branch, or a main that was rewritten under it."
    ])
  end

  defp c5(%{ancestry: {:error, why}}),
    do: undetermined(:c5, claim(:c5), ["ancestry not established: #{why}"])

  defp peel_text(%{local_tag: {:ok, %{peels_to: peeled}}}), do: short(peeled)
  defp peel_text(_obs), do: "an unreadable commit"

  defp claim(:c1), do: "origin is reachable and readable"
  defp claim(:c2), do: "live refs/heads/main on origin == local main"
  defp claim(:c3), do: "the version's tag exists locally and is annotated"
  defp claim(:c4), do: "that tag is on origin, as the same object"
  defp claim(:c5), do: "the tag peels to an ancestor-or-equal of local main"

  defp green(id, claim, lines), do: %{id: id, claim: claim, status: :green, lines: lines}
  defp red(id, claim, lines), do: %{id: id, claim: claim, status: :red, lines: lines}

  defp undetermined(id, claim, lines) do
    %{
      id: id,
      claim: claim,
      status: :undetermined,
      lines: lines ++ ["UNDETERMINED is not a pass — see the fail-closed rule."]
    }
  end

  @doc "First 12 characters of a sha, for reports. Never used for comparison."
  @spec short(String.t()) :: String.t()
  def short(sha), do: String.slice(sha, 0, 12)

  # ---------------------------------------------------------------------------
  # git
  # ---------------------------------------------------------------------------

  defp git(repo, args) do
    case git_status(repo, args) do
      {out, 0} -> {:ok, out}
      {out, n} -> {:error, "`git #{Enum.join(args, " ")}` exited #{n}: #{String.trim(out)}"}
    end
  end

  # No prompting, and a bounded connect: an instrument that hangs waiting for a
  # password is an instrument that never returns a verdict. GIT_SSH_COMMAND is
  # set only when the caller has not set one, so a custom ssh setup still wins.
  defp git_status(repo, args) do
    System.cmd("git", args, cd: repo, stderr_to_stdout: true, env: git_env())
  rescue
    e in ErlangError -> {"git could not be executed: #{inspect(e)}", 127}
  end

  defp git_env do
    ssh =
      case System.get_env("GIT_SSH_COMMAND") do
        nil -> [{"GIT_SSH_COMMAND", "ssh -o BatchMode=yes -o ConnectTimeout=10"}]
        _set -> []
      end

    [{"GIT_TERMINAL_PROMPT", "0"}] ++ ssh
  end
end

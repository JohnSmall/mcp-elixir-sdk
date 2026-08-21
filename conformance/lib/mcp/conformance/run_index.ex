defmodule MCP.Conformance.RunIndex do
  @moduledoc """
  **What ran, and where are its results?** — asked once, answered per leg.

  ## The problem this module exists to solve

  Four call sites ask that question, and before MES-57 three of them got the
  answer from `MCP.Conformance.Console`:

    * `Manifest.judge/3` → `check_console_versus_disk/2`, the adjudication gate;
    * `Manifest.expected_diff/2`, the absentee register;
    * `Census.scenarios/4`, every per-scenario figure;
    * `Census.corroborate_not_scored/3`, the frozen-set cross-check.

  `Console.parse/1` **refuses** a client console, on purpose and correctly (see
  its `parallel_leg_faults/1`). So on the client leg all four answered "nothing
  ran", and they answered it in incompatible ways: the gate refused
  `ARTEFACTS_INCONSISTENT`, `expected_diff/2` reported all 32 scored scenarios
  absent, and `corroborate_not_scored/3` silently degraded to a check that could
  no longer fire. **No client run could be adjudicated at all**, which is why no
  client figure existed to be reported.

  Fixing only the census would have left the gate and the report answering that
  one question differently — precisely the disagreement `expected_diff/2` was
  written to prevent. So there is **one derivation**, here, and the four call
  sites consume it.

  ## Server leg: delegation, not reimplementation

  `index/2` for `:server` returns `Console.parse/1`'s mappings and faults
  unchanged. The existing parser stays the server leg's authority, its
  parallel-leg refusal stays exactly where it is, and its behaviour is held
  byte-identical by a regression test that re-adjudicates and re-renders MES-56's
  committed runs. That test is the control on this module's blast radius, and it
  is the regression guard for every future leg added here.

  ## Client leg: the key is the artefact DIRECTORY NAME, checked against the
  ## frozen set, refusing on any ambiguity

  Measured at alpha.11 (MES-56, `--suite sep-835`): client scenarios run inside
  one `Promise.all`, so every `Starting scenario:` line precedes every
  `Results saved to` line and the saves arrive in **completion** order.
  Adjacency carries no information; positional pairing was measured and
  mis-attributed 4 of 5.

  The harness does author one deliberate per-scenario identifier, and exactly
  one. `checks.json` carries no scenario id — its `id` field is the *check's* —
  and no sibling metadata file is written. What the harness does write is the
  output directory, built by `Ho()` in `dist/index.js`:

      Ho(outDir, scenario, prefix = "") =
        join(outDir, `${prefix ? prefix + "-" + scenario : scenario}-${stamp}`)
        where stamp = new Date().toISOString().replace(/[:.]/g, "-")

  So a directory name is `<scenario-id>-<stamp>`, the scenario id may contain
  slashes (`auth/metadata-var1`) and `path.join` nests them, and the client leg
  passes **no prefix** (`Ho(r,t)`, two-arg) where the server leg passes
  `"server"`. Both facts were confirmed against the real tree this ticket ran,
  not only against the source: of 39 directories, 39 matched
  `#{inspect(Regex.source(~r/-\\d{4}-\\d{2}-\\d{2}T\\d{2}-\\d{2}-\\d{2}-\\d{3}Z$/))}`
  and none carried a prefix.

  Matching is **exact against the frozen set** after removing that suffix. No
  prefix stripping, no fuzzy match, no longest-prefix rule: a directory the set
  does not name is refused, never repaired. "Strip anything that looks like a
  prefix" is how one scenario silently acquires two rows.

  ## The four refusals, and what each one is guarding

  | code | condition |
  | --- | --- |
  | `ARTEFACT_DIR_UNKNOWN` | a directory matching no expected id — a renamed scenario upstream, a stray directory, an unexpected prefix |
  | `ARTEFACT_DIR_AMBIGUOUS` | a directory matching **more than one** expected id, **or** two directories matching the same id. Both halves are checked, not just the one that can happen today |
  | `ARTEFACT_CHECKS_ABSENT` | a matched directory with no `checks.json` that no id-keyed `SKIPPED:` line explains |
  | *(absentee)* | an expected **scored** id with neither a directory nor a `Failed to run scenario` line. Not raised here: `Manifest.expected_diff/2` already turns it into `SCORED_SCENARIO_ABSENT`, and one defect must produce one fault |

  The multiplicity check reads as vacuous under exact equality and is not: the
  expected list is built from the frozen set's `scored ++ not_scored`, and a set
  naming one id in both — or twice in one — makes a single directory match two
  entries. That is a corrupt denominator, and it is exactly the class the
  `n/32` headline is quoted over.

  ## Order-independence, which is the property the whole design turns on

  The map is derived from **directory names and the frozen set only**. The
  console is still read, but exclusively for facts keyed BY SCENARIO ID — a
  scenario that threw (`Console.thrown_by_id/1`) and a scenario the harness
  skipped (`Console.skipped_by_id/1`). No line's position is ever consulted, and
  the output is sorted by scenario id, so **no completion ordering can change
  any output**.

  That is proved by measurement rather than argued, in `RunIndexTest`, three
  ways: the directory list is shuffled and reversed and the map must be
  byte-identical; the console's lines are shuffled and reversed and the map must
  be byte-identical; and a positional pairing is implemented in the test, run
  against the same real artefacts, and asserted to **disagree** — quantifying
  the mis-attribution this key prevents.
  """

  alias MCP.Conformance.{Console, RequirementSet}

  # `new Date().toISOString().replace(/[:.]/g, "-")` — 2026-08-21T06-50-59-377Z.
  # Anchored at both ends of the final path segment, so a directory whose name
  # merely CONTAINS something stamp-shaped is not a candidate.
  @stamp ~r/-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z$/

  @typedoc "One scenario, its artefact directory (absolute) or `nil`, and why it has none."
  @type mapping :: %{scenario: String.t(), dir: String.t() | nil, threw: String.t() | nil}

  @typedoc """
  The shape both legs return: exactly the fields the four call sites consume
  from `Console.parse/1`, so a consumer cannot tell which leg produced it.
  """
  @type t :: %{leg: String.t(), mappings: [mapping()], faults: [String.t()]}

  @doc """
  Index one run.

  `leg` is the manifest's own `leg` string. Options:

    * `:console_body` — `console.txt` as read (both legs)
    * `:run_dir` — the directory being adjudicated, walked on the client leg
    * `:out_dir` — the manifest's `invocation.out_dir`, so `:dir` is expressed
      the same way `Console` expresses it and an archived run reads like a fresh
      one
    * `:requirement_set` — the parsed frozen set, the client leg's key

  Never raises and never returns an error tuple: a problem is a **fault
  sentence**, because the adjudicator turns faults into a refusal and the census
  into an exit status, and neither wants an exception.
  """
  @spec index(String.t(), keyword()) :: t()
  def index("server", opts) do
    parsed = Console.parse(Keyword.get(opts, :console_body) || "")
    %{leg: "server", mappings: parsed.mappings, faults: parsed.faults}
  end

  def index("client", opts) do
    body = Keyword.get(opts, :console_body) || ""
    blocks = Console.blocks(body)

    case Keyword.get(opts, :requirement_set) do
      nil ->
        %{
          leg: "client",
          mappings: [],
          faults:
            blocks.faults ++
              [
                "the client leg's scenario -> artefact key is the frozen requirement set, " <>
                  "and it could not be read for this run, so no directory can be identified " <>
                  "and no per-scenario figure can be attributed"
              ]
        }

      set ->
        client_index(body, blocks, set, opts)
    end
  end

  # A leg the frozen set does not define reaches here only if `Manifest` and
  # `Census` both let it through; they refuse it first (LEG_NOT_IN_REQUIREMENT_SET).
  # Refusing again rather than defaulting is the `Map.get/3` lesson: a default
  # cannot distinguish "this leg has no scenarios" from "this leg does not exist".
  def index(leg, _opts) do
    %{
      leg: to_string(leg),
      mappings: [],
      faults: [
        "#{inspect(leg)} is not a leg this tooling can index; the scenario -> artefact map " <>
          "is derived per leg and there is no generic derivation to fall back to"
      ]
    }
  end

  @doc "Scenario ids the run executed, sorted."
  @spec ran(t()) :: [String.t()]
  def ran(%{mappings: mappings, leg: "server"}), do: Enum.map(mappings, & &1.scenario)
  def ran(%{mappings: mappings}), do: mappings |> Enum.map(& &1.scenario) |> Enum.sort()

  @doc """
  Artefact directories the index named, relative to `run_dir` and sorted — the
  same shape `MCP.Conformance.Provenance.scenario_dirs/1` returns from disk, so
  the two can be compared directly.
  """
  @spec dirs_relative(t(), String.t()) :: [String.t()]
  def dirs_relative(%{mappings: mappings}, run_dir) do
    mappings
    |> Enum.reject(&is_nil(&1.dir))
    |> Enum.map(&Path.relative_to(Path.expand(&1.dir), Path.expand(run_dir)))
    |> Enum.sort()
  end

  @doc "Scenarios that ran, threw, and left no artefact directory behind."
  @spec thrown(t()) :: [mapping()]
  def thrown(%{mappings: mappings}), do: Enum.filter(mappings, &is_nil(&1.dir))

  @doc "The timestamp suffix `Ho()` appends, exposed so a test can assert against it."
  @spec stamp_pattern() :: Regex.t()
  def stamp_pattern, do: @stamp

  @doc """
  Every directory under `run_dir`, relative and sorted — including ones with no
  `checks.json`.

  `Provenance.scenario_dirs/1` keys on `checks.json` and so is blind to a
  skipped client scenario's empty directory (`Console.skipped_by_id/1`). This
  walk is not, which is what lets that state be NAMED rather than read as
  absence.
  """
  @spec all_dirs(String.t()) :: [String.t()]
  def all_dirs(run_dir) do
    run_dir
    |> walk()
    |> Enum.map(&Path.relative_to(&1, run_dir))
    |> Enum.sort()
  end

  defp walk(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        children =
          entries
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.filter(&File.dir?/1)

        children ++ Enum.flat_map(children, &walk/1)

      {:error, _} ->
        []
    end
  end

  # --- the client leg's key --------------------------------------------------

  defp client_index(body, blocks, set, opts) do
    run_dir = opts |> Keyword.fetch!(:run_dir) |> Path.expand()
    out_dir = opts |> Keyword.get(:out_dir, run_dir) |> Path.expand()

    expected = RequirementSet.expected_to_run(set, "client")
    expected_ids = expected.scored ++ expected.not_scored

    dirs = all_dirs(run_dir)
    {candidates, others} = Enum.split_with(dirs, &Regex.match?(@stamp, &1))

    thrown = Console.thrown_by_id(body)
    skipped = Console.skipped_by_id(body)

    matched = Enum.map(candidates, &{&1, strip_stamp(&1), matches(&1, expected_ids)})

    faults =
      blocks.faults ++
        stray_dir_faults(others, candidates) ++
        unknown_faults(matched) ++
        ambiguous_faults(matched) ++
        checks_absent_faults(matched, run_dir, skipped)

    mappings =
      matched
      |> Enum.flat_map(fn
        {rel, _stripped, [id]} -> [%{scenario: id, dir: Path.join(out_dir, rel), threw: nil}]
        _ -> []
      end)
      |> Kernel.++(thrown_mappings(thrown, expected_ids, matched))
      |> Enum.sort_by(& &1.scenario)

    %{leg: "client", mappings: mappings, faults: faults}
  end

  defp strip_stamp(rel), do: Regex.replace(@stamp, rel, "")

  # Exact equality, filtered rather than found, so the "matches more than one"
  # half of the ambiguity property is CHECKED rather than argued away.
  defp matches(rel, expected_ids) do
    stripped = strip_stamp(rel)
    Enum.filter(expected_ids, &(&1 == stripped))
  end

  # A directory that is not a candidate is admissible only as a pure container
  # of candidates — `auth/` on this leg, created by `path.join` nesting a
  # slashed scenario id. Anything else is a directory in the run whose contents
  # nothing accounts for, and skipping it silently is how an artefact tree grows
  # a row nobody reads.
  defp stray_dir_faults(others, candidates) do
    for rel <- others, not Enum.any?(candidates, &ancestor?(rel, &1)) do
      "ARTEFACT_DIR_UNKNOWN: #{inspect(rel)} is a directory in the run that carries no " <>
        "#{inspect(Regex.source(@stamp))} timestamp suffix and is not an ancestor of any " <>
        "directory that does, so nothing in the run accounts for it"
    end
  end

  defp ancestor?(rel, candidate), do: String.starts_with?(candidate, rel <> "/")

  defp unknown_faults(matched) do
    for {rel, stripped, []} <- matched do
      "ARTEFACT_DIR_UNKNOWN: #{inspect(rel)} reduces to scenario id #{inspect(stripped)}, " <>
        "which the frozen requirement set does not name for this leg. It is refused rather " <>
        "than skipped: a directory the set cannot name is either a scenario renamed upstream " <>
        "or a directory from another run, and both would be quoted as if measured"
    end
  end

  defp ambiguous_faults(matched) do
    multi =
      for {rel, stripped, ids} <- matched, length(ids) > 1 do
        "ARTEFACT_DIR_AMBIGUOUS: #{inspect(rel)} reduces to #{inspect(stripped)}, which the " <>
          "frozen set names #{length(ids)} times, so the directory cannot be attributed to " <>
          "one scenario"
      end

    collisions =
      matched
      |> Enum.flat_map(fn {rel, _stripped, ids} -> Enum.map(ids, &{&1, rel}) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.filter(fn {_id, rels} -> length(rels) > 1 end)
      |> Enum.sort()
      |> Enum.map(fn {id, rels} ->
        "ARTEFACT_DIR_AMBIGUOUS: scenario #{inspect(id)} is claimed by #{length(rels)} " <>
          "artefact directories in one run (#{inspect(Enum.sort(rels))}), so no single check " <>
          "sheet can be attributed to it"
      end)

    Enum.sort(multi) ++ collisions
  end

  # The state harness source predicted and this ticket then measured: `Ko()`
  # mkdirs the output directory BEFORE the applicability check and returns early
  # on a skip, leaving a directory with no `checks.json`. That has exactly one
  # innocent cause, it is stated on an id-keyed console line, and anything else
  # wearing the same shape is a truncated or half-written run.
  defp checks_absent_faults(matched, run_dir, skipped) do
    for {rel, _stripped, [id]} <- matched,
        not File.regular?(Path.join([run_dir, rel, "checks.json"])),
        not Map.has_key?(skipped, id) do
      "ARTEFACT_CHECKS_ABSENT: #{inspect(rel)} holds no checks.json and the console carries " <>
        "no `SKIPPED: scenario '#{id}'` line to explain it. A directory with no check sheet " <>
        "is invisible to the artefact walk, so reading it as absence would drop the scenario " <>
        "from the census without dropping it from the denominator"
    end
  end

  # A scenario the harness could not run leaves no directory. Attributed by id
  # off the console line, never by position, and only for ids the frozen set
  # names — a throw line for something else is a fact about another run.
  defp thrown_mappings(thrown, expected_ids, matched) do
    already = for {_rel, _stripped, [id]} <- matched, into: MapSet.new(), do: id

    for {id, message} <- thrown,
        id in expected_ids,
        not MapSet.member?(already, id),
        do: %{scenario: id, dir: nil, threw: message}
  end
end

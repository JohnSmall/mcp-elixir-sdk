defmodule MCP.Conformance.Console do
  @moduledoc """
  Parse the run-level console output the harness prints and MES-51 captures as
  `console.txt`.

  ## Why the console is load-bearing rather than a transcript

  Two things exist **only** here, in a file the harness does not consider an
  artefact at all — the first of them **on the server leg**, since the client
  leg's key to it is the artefact tree rather than this file, as that bullet
  explains:

    * the **scenario → artefact-directory map**. `checks.json` carries no
      scenario id — measured, not assumed: its keys are `id`, `name`,
      `description`, `status`, `timestamp`, `specReferences`, `details`,
      `errorMessage`, and the `id` there is the *check's*, not the scenario's.
      Directory names concatenate leg, scenario id and timestamp with dashes
      inside both halves (`server-tools-call-simple-text-2026-…`), so splitting
      one back into its parts is guesswork.

      **On the SERVER leg** the console states the pairing outright — a
      `=== Running scenario: X ===` header followed by that scenario's
      `Results saved to DIR` — so the console is the only non-guessing key to
      it, and that is what makes this file load-bearing.

      **On the CLIENT leg the console is NOT the key to the mapping** and this
      file never reads one from it (the next section measures why, and
      `parallel_leg_faults/1` refuses it). The client key is the artefact
      **directory name**, in `MCP.Conformance.RunIndex`: it strips the
      timestamp suffix and matches the remainder **exactly** against the frozen
      requirement set, refusing on anything it does not name. Matching exactly
      is deliberately not *splitting* — where scenario ids contain slashes
      (`auth/metadata-default`) and the harness nests them, splitting a name
      would mis-attribute results silently.

    * the **scored / not-scored split**, in the "Not scored for REV" block.
      Nothing in the artefact tree records which scenarios counted.

  ## MEASURED: the MAPPING is server-leg only, and the client leg's key was a
  ## design question rather than a missing branch (S5-12)

  The scenario -> directory pairing above exists **only on the server leg**.
  Measured on the client leg at alpha.11, `--suite sep-835`, five scenarios:

      Running sep-835 suite (5 scenarios) in parallel...
      Starting scenario: auth/scope-from-www-authenticate
      Starting scenario: auth/scope-retry-limit
      ... all five started ...
      Results saved to /tmp/…/auth/scope-from-scopes-supported-2026-…Z
      Results saved to /tmp/…/auth/scope-from-www-authenticate-2026-…Z
      ... in COMPLETION order ...

  Three differences, and the third is fatal to this approach:

    1. there is no `=== Running scenario: X ===` header at all — the client
       path prints `Starting scenario: X`;
    2. the summary mark grows an optional `, K warnings` suffix;
    3. **the client leg runs its scenarios in `Promise.all`**, so every start
       line is printed before any `Results saved to`, and the saves arrive in
       completion order. There is no textual adjacency linking a scenario to
       its directory, and pairing them positionally would have mis-attributed
       four of five here — silently, with every scenario still accounted for.

  So a leg-agnostic MAPPING is not what this is. Rather than guess, `parse/1`
  **refuses a client-leg console outright**: it reports a fault naming this
  finding, and every caller turns a fault into a refusal. Declining to measure
  is the correct behaviour for an instrument that cannot attribute what it
  reads, and that refusal is unchanged.

  The scope of that refusal, however, is narrower than this section used to
  say. MES-57 chose the client leg's key — the artefact **directory name**,
  matched exactly against the frozen requirement set and refused on any
  ambiguity, in `MCP.Conformance.RunIndex` — and it read the rest of the
  console through `blocks/1`, whose guards are live on both legs. So:

    * the scenario → directory **mapping** is server-leg only, here, and
      `parallel_leg_faults/1` still refuses to produce one for a client
      console;
    * **membership** — `marks` and `not_scored` against `announced/1` — is
      guarded on **both** legs, because the SET of announced scenarios is a
      position-free fact even where their ORDER is not.

  Leaving the wider claim standing after MES-57's own change falsified it is
  S5-24, and it happened twice in this file.

  ## The marks are the harness's own reducer, and that is the point

  `✓ scenario: N passed, M failed` is the harness applying its own rule —
  `✗` iff the scenario has at least one `FAILURE` check. `MCP.Conformance.Census`
  recomputes that rule from `checks.json` and compares the two. A reducer I
  wrote agreeing with a reducer the harness wrote, over the same run, is a
  falsifiable claim; a reducer that only agrees with itself is not.
  """

  # The labels the harness's `Total:` printers can emit, read off
  # @modelcontextprotocol/conformance 0.2.0-alpha.11 rather than inferred from
  # the runs we happen to hold: `dist/index.js` has three `Total:` emit sites,
  # two server-shape (`N passed, M failed`) and one client-shape
  # (`N passed, M failed, K warnings[, J skipped]`). The union is closed, so a
  # label outside it is a console this parser cannot attribute — and refusing is
  # the fail-closed direction if a later harness adds a column, which is the one
  # this pin (alpha.11) is allowed to notice.
  @total_labels ~w(passed failed warnings skipped)

  # The subset of those labels the SUMMARY block also carries, and therefore the
  # subset `total_sum_faults/3` can check. `skipped` is absent by measurement,
  # not oversight — see that function.
  @summed_labels [{"passed", :passed}, {"failed", :failed}, {"warnings", :warnings}]

  @typedoc """
  One `=== Running scenario: X ===` and how it ended.

  `dir` is the artefact directory, or `nil` when the scenario **threw**. That
  second case is real and was measured on the null-control run: when a scenario
  raises, the harness catches it, synthesises a `FAILURE` check into its own
  summary, and writes **no artefact directory at all**. A census built from the
  artefact tree alone would silently omit it — and omit it in the flattering
  direction, since a thrown scenario is always a failing one. `threw` carries
  the harness's message so the omission is recorded rather than inferred.
  """
  @type mapping :: %{scenario: String.t(), dir: String.t() | nil, threw: String.t() | nil}

  @typedoc """
  One `✓ scenario: N passed, M failed` line from the SUMMARY block.

  `warnings` is the `, K warnings` suffix the client leg's printer appends when
  a scenario carries `WARNING` checks, and `0` when the suffix is absent — which
  is always, on the server leg, whose printer has no such suffix. It is read
  rather than skipped over because the client leg's `Total:` line states a
  `warnings` column, and `total_sum_faults/3` has nothing to check that column
  against unless the marks carry the number the harness summed.
  """
  @type mark :: %{
          scenario: String.t(),
          pass: boolean(),
          passed: integer(),
          failed: integer(),
          warnings: integer()
        }

  @typedoc "One not-scored line from the `Not scored for REV` block."
  @type not_scored :: %{scenario: String.t(), pass: boolean(), reason: String.t()}

  @typedoc "Everything `parse/1` reads out of one run's console."
  @type t :: %{
          mappings: [mapping()],
          marks: [mark()],
          not_scored: [not_scored()],
          totals: %{String.t() => integer()},
          announced: MapSet.t(),
          faults: [String.t()]
        }

  @doc """
  Parse `body`.

  Returns a map of `:mappings`, `:marks`, `:not_scored`, `:totals` and
  `:faults`. `:faults` is a list of sentences describing anything structurally
  wrong that a caller must not paper over. It is returned rather than raised
  because the adjudicator turns it into a refusal and the census into an exit
  status, and neither wants an exception.

  A console is well-formed only if **every scenario it names appears exactly
  once in each block that names scenarios**, so all of these fault:

    * a `=== Running scenario:` with no `Results saved to` and no
      `Failed to run scenario` after it;
    * the same scenario mapped to two artefact directories;
    * the same scenario carrying two SUMMARY marks, contradictory or not;
    * a SUMMARY mark for a scenario that never ran;
    * the same scenario listed twice in the not-scored block;
    * a not-scored line for a scenario that never ran;
    * a not-scored line whose ✓/✗ contradicts that scenario's SUMMARY mark;
    * more than one `Total:` line, or one `Total:` line repeating a label;
    * a `Total:` line carrying a part that is not `N label`, or a label the
      harness does not print;
    * a `Total:` line that disagrees with the SUMMARY marks it is the sum of.

  ## Block × guarantee, because the sentence above is a claim nothing checked

  That sentence is **universal**, and correction rounds 2 and 3 each found one
  more block it was false of — first the SUMMARY marks, then the not-scored
  block's membership. Neither was a guard someone forgot: both were a stated
  property with nothing comparing it against the code. Patching the named
  sibling only ever yields the next sibling, so the claim is discharged here as
  a table over a **closed** set — the four content blocks `parse/1` itself
  returns. That set is the parser's own return map, not a judgement about which
  blocks are worth looking at, which is what gives the table a last row.

  Two guarantees are stated of each block, because those two are what a
  consumer keying on a scenario id depends on:

    * **multiplicity** — may the same key appear twice?
    * **membership** — must every key it names be one the console announced?

  Every cell is *enforced by* a named function, *vacuous* for a stated reason,
  or *bounded* for a stated reason. **A cell that is none of those three is a
  defect**, and this table is where it becomes visible rather than a review
  finding a round later.

  | block | multiplicity | membership |
  | --- | --- | --- |
  | `mappings` | enforced by `duplicate_faults/1` — one scenario mapped to two artefact directories | **vacuous.** A mapping exists only because `scenario_header/1` matched, and `announced/1` reads the same headers off the same lines, so a mapping cannot name a scenario the console did not announce. The mappings *are* the ground truth every other row is checked against |
  | `marks` | enforced by `mark_faults/3`, duplicates arm — whether or not the two agree, since "refuse only on conflict" would make the guard depend on the comparison it exists to protect | enforced by `mark_faults/3`, orphans arm, against `announced/1`, **on both legs**. `announced/1` reads the server's `=== Running scenario: X ===` and the client's `Starting scenario: X`, so the arm has a real set to check against either way, and `attributable?` (`parallel_leg == [] or announced != ∅`) arms it by asking whether the console announced *anything to attribute to* rather than which leg printed it. It was **bounded on the client leg until MES-57**, on the argument that such a console was refused whole anyway; `RunIndex` made client runs adjudicable and that argument lapsed (S5-24). What still refuses is narrower and is not this cell: `parse/1` declines the client leg's scenario → directory *mapping* and position pairing via `parallel_leg_faults/1`. The two coexist because membership is a position-free fact — which scenarios the console named — and pairing is not |
  | `not_scored` | enforced by `duplicate_not_scored_faults/1` | enforced by `orphan_not_scored_faults/3` against `announced/1`, live on both legs under the same `attributable?` as `marks` and for the same reason. The **cross-authority** half — does the frozen set agree this scenario is not scored, and for the same reason — is deliberately not here: it needs `MCP.Conformance.RequirementSet`, and a parser that imports its own referee is no longer a parser. It lives in `MCP.Conformance.Census.corroborate_not_scored/3`, as `NOT_SCORED_DISAGREES_WITH_FROZEN_SET` |
  | `totals` | enforced by `totals_faults/1`, in both senses: more than one `Total:` line, and one line repeating a label | enforced by `totals_faults/1` against `@total_labels`. Round 4 called this cell **vacuous** because the block keys on status *labels* rather than scenario ids, and that was the wrong conclusion from a true premise: a label is still a key, and `total_parts/1` accepted any lowercase word, so `Total: 3 widgets` parsed faultlessly into a key nothing reads — while a part matching neither shape was dropped in silence. The admissible set is the union of the harness's three `Total:` printers, so it is the harness's set and not this parser's |

  Completing the table opened one guarantee the table does not itself state.
  `marks` and `not_scored` both carry a ✓/✗ for the *same* scenario — the
  harness builds the not-scored block by re-listing scenarios it has already
  marked — and nothing compared the two. A console marking a scenario ✗ in the
  SUMMARY block and ✓ in the not-scored block satisfies every cell above and is
  still two verdicts for one scenario: the duplicate-mark defect spread across
  two blocks instead of packed into one. `not_scored_verdict_faults/2` faults
  it.

  An **absent** `Total:` line remains the one site deliberately left unguarded,
  and it is a third property — presence — rather than a cell of this table.
  Multiplicity is two contradictory values with one silently chosen; absence is
  no value, and `%{}` is visibly empty to whoever reads it.

  Only the first two bullets of that fault list — the two **mapping-block**
  ones, a header with no ending and one scenario mapped to two directories —
  were checked before MES-56 correction round 2, which made this parser's
  guarantee true of the mapping block and false of every other block in the
  same file — the failure those rounds are about. (Named rather than counted:
  an ordinal into a list that a later edit can reorder is a claim resting on
  its neighbours, which is the shape of the defect this round is about.)

  ## Pair × guarantee, because a per-block table says nothing about the joins

  The table above enumerates what is true of each block **on its own**, and
  round 4 read that as closure. It is not: a console can satisfy all eight cells
  and still be one the harness could not have printed, because the blocks are
  reducers over one run and therefore constrain each other. Measured, not
  argued — a console whose SUMMARY marks summed to 1 passed / 0 failed while its
  `Total:` line said 0 passed / 1 failed satisfied every cell above, parsed with
  `faults: []`, and the census ACCEPTED it.

  So the joins get their own register, over the same closed set: four blocks,
  six unordered pairs, no pair omitted. As above, each is *guarded by* a named
  function or *vacuous* for a stated reason.

  | pair | guarantee |
  | --- | --- |
  | `mappings × marks` | **guarded.** Mark → mapping by `mark_faults/3`'s orphans arm against `announced/1`; mapping → mark by `MCP.Conformance.Census.corroborate_reducer/3`, which refuses a scenario that ran with no mark (`HARNESS_MARK_MISSING`) — the direction this parser cannot take, since a missing mark is only detectable against the artefact tree |
  | `mappings × not_scored` | **guarded.** Not-scored → mapping by `orphan_not_scored_faults/3` against `announced/1`. The other direction is not a defect — most scenarios that ran are scored and rightly have no line here — so the question "should this scenario have one?" is the cross-authority one, and `Census.corroborate_not_scored/3` answers it against the frozen set (`NOT_SCORED_DISAGREES_WITH_FROZEN_SET`) |
  | `mappings × totals` | **vacuous.** `totals` is keyed on labels and carries no scenario id, so the only candidate is "the total sums the marks of scenarios that ran" — which is `mappings × marks` conjoined with `marks × totals` and has no content of its own once both hold |
  | `marks × not_scored` | **guarded** by `not_scored_verdict_faults/2`: both blocks carry a ✓/✗ for the same scenario, and a console stating both is two verdicts for one scenario. The membership half — a not-scored line for a scenario with no mark — is `mappings × marks` again, since such a scenario is announced and its missing mark is what `corroborate_reducer/3` refuses |
  | `marks × totals` | **guarded** by `total_sum_faults/3`. This was the open pair, and it is the one with an aggregate property no per-block cell can state: the harness computes the `Total:` line **by summing the marks it has just printed**, so the two cannot disagree in a console it produced |
  | `not_scored × totals` | **vacuous.** The `Total:` line does not partition by the scored split — read off the harness, it is printed before the not-scored split has been computed at all, and it sums every mark including the not-scored ones. The not-scored counts live in that block's own header line, which is not `totals` |

  ## Does a THIRD register exist? No, and here is why the recursion stops

  Two registers are now closed over sets the code defines, and the obvious next
  question is triples, then quadruples. The answer is that **no property of
  arity ≥ 3 over these blocks can be violated while all of its pairs hold**, so
  registers 1 and 2 are jointly complete.

  The argument is a census of what the blocks actually carry. Every field in
  `parse/1`'s return map is one of:

    * a **scenario id** — `mappings`, `marks`, `not_scored`, all read off the
      same `scenario_header/1` lines;
    * a **per-scenario verdict** — `marks` and `not_scored`;
    * a **per-scenario check count** — `marks` alone;
    * an **aggregate of those counts** — `totals` alone;
    * an **artefact directory or throw message** — `mappings` alone;
    * a **harness reason** — `not_scored` alone.

  A consistency property has content only where a value is derivable from more
  than one block, so the last three lines can only be checked against an outside
  authority and are not properties of this return map at all. That leaves
  exactly two sources of content, and both are 2-ary by construction:

    * **membership** is stated against `announced/1`, a set derived from
      `mappings` alone. A three-way membership claim is therefore the
      conjunction of two `(block, mappings)` pairs — transitivity, not a new
      property;
    * **agreement** needs two carriers of one value, and no value here has
      three. The verdict has two carriers; the check counts have one carrier and
      one aggregate over that same one.

  For a genuine triple there would have to be a **hyperedge**: a value derivable
  jointly from three blocks and from no two of them. That means either a field
  shared by three blocks — there is none wider than the scenario id, which is
  transitive — or an aggregate over two blocks at once, and `totals` sums the
  marks and nothing else. The same census answers every higher arity, because it
  is an enumeration over the return map rather than a search. **The recursion
  stops at 2.**

  ### What that argument does NOT cover, stated by enumeration

  It is a claim about the **fields of the return map**, so it says nothing about
  lines of the console no block reads. One class of such line carries a
  checkable number, and the class is enumerable because the harness has exactly
  three printers that state a count:

    1. `Running <label> (N scenarios) …` — N is the number of
       `=== Running scenario:` headers that follow;
    2. `Total: …` — the only one inside the return map, guarded above;
    3. `Not scored for REV: N scenario(s) run, K failing` — N is the number of
       lines in the not-scored block and K the number of them marked ✗.

  (1) and (3) are **bounded rather than guarded, and the bound names what makes
  it safe**: a console that loses a header loses a mapping, and
  `MCP.Conformance.Manifest` compares `dirs_relative/2` against the recorded and
  on-disk artefact trees — measured, a console with one header, save and mark
  removed and its `Total:` line corrected refuses as `ARTEFACTS_INCONSISTENT`
  naming the orphaned directory. A not-scored block that gains, loses, repeats
  or flips an entry is refused by the four guards the pair table already names.
  Guarding (1) and (3) here would add a second fault for defects that are
  already refused, which is the cost this file spends on diagnosis and never on
  verdicts.
  """
  @spec parse(String.t()) :: t()
  def parse(body) do
    lines = String.split(body, "\n")

    {mappings, open_faults} = mappings(lines)
    blocks = block_analysis(lines)

    Map.merge(blocks_public(blocks), %{
      mappings: mappings,
      faults:
        open_faults ++
          duplicate_faults(mappings) ++
          blocks.faults ++
          blocks.parallel_leg
    })
  end

  @typedoc "Everything `blocks/1` reads: the console blocks that are NOT the mapping."
  @type blocks :: %{
          marks: [mark()],
          not_scored: [not_scored()],
          totals: %{String.t() => integer()},
          announced: MapSet.t(),
          faults: [String.t()]
        }

  @doc """
  The console's per-scenario blocks — SUMMARY marks, the not-scored block and
  the `Total:` line — **without** the scenario -> artefact-directory mapping.

  ## Why this is a separate entry point rather than a flag on `parse/1`

  `parse/1` is the SERVER leg's authority and refuses a client console whole,
  via `parallel_leg_faults/1`. That guard is not an obstacle to be relaxed: it
  is what stands between this project and a mis-attributed client table, and
  MES-57 was dispatched with an explicit instruction not to weaken it.

  But the mapping is the *only* block the client leg cannot express. Its marks,
  its not-scored block and its `Total:` line are printed by the same code paths
  and parse identically — measured on the alpha.11 client console this ticket
  ran. Routing the client leg away from `parse/1` and stopping there would have
  left **every** block guard dark on that leg: a duplicated flattering mark
  would then reach `Census.corroborate_reducer/3`, which keys marks by scenario
  and so keeps whichever came last. That is B2 exactly, re-opened on a new leg.

  So the blocks and their guards are shared, and only the mapping is
  leg-dispatched — by `MCP.Conformance.RunIndex`, which is the one derivation
  both the gate and the census consume.

  `parse/1` returns everything this does, plus `:mappings`, plus the
  `parallel_leg_faults/1` sentence. The block faults are byte-identical between
  the two, and a test holds them so.
  """
  @spec blocks(String.t()) :: blocks()
  def blocks(body) do
    body
    |> String.split("\n")
    |> block_analysis()
    |> then(&Map.put(blocks_public(&1), :faults, &1.faults))
  end

  defp blocks_public(blocks) do
    %{
      marks: blocks.marks,
      not_scored: blocks.not_scored,
      totals: blocks.totals,
      announced: blocks.announced
    }
  end

  defp block_analysis(lines) do
    marks = marks(lines)
    not_scored = not_scored(lines)
    parallel_leg = parallel_leg_faults(lines)
    announced = announced(lines)
    totals = totals(lines)

    # A console is attributable when it announced anything at all to attribute
    # to. Before MES-57 this read `parallel_leg == []`, whose stated
    # justification was that a client console "is refused either way, so the
    # bound costs a diagnosis and never a verdict". `RunIndex` makes client runs
    # adjudicable, so that justification lapsed — and a lapsed justification
    # guarding a live leg is worse than no guard, because it reads as
    # considered. `announced/1` now recognises the client leg's
    # `Starting scenario:` header too, so the membership arms have a real set to
    # check against on both legs.
    #
    # Server behaviour is unchanged and provably so: a server console has no
    # `Starting scenario:` lines, so `parallel_leg == []` and the first disjunct
    # decides exactly as before.
    attributable? = parallel_leg == [] or not Enum.empty?(announced)

    marks_block = mark_faults(marks, announced, attributable?)
    totals_block = totals_faults(lines)

    %{
      marks: marks,
      not_scored: not_scored,
      totals: totals,
      announced: announced,
      parallel_leg: parallel_leg,
      faults:
        marks_block ++
          duplicate_not_scored_faults(not_scored) ++
          orphan_not_scored_faults(not_scored, announced, attributable?) ++
          not_scored_verdict_faults(not_scored, marks) ++
          totals_block ++
          total_sum_faults(totals, marks, marks_block ++ totals_block)
    }
  end

  # The guard, not a branch. A console that announces scenarios the client
  # leg's way carries no usable scenario -> directory map, so this refuses to
  # produce one instead of producing a plausible wrong one.
  defp parallel_leg_faults(lines) do
    if Enum.any?(lines, &Regex.match?(~r/^Starting scenario: /, &1)) do
      [
        "this console was produced by the client leg, whose scenarios run in Promise.all: " <>
          "every `Starting scenario:` line precedes every `Results saved to` line, and the " <>
          "saves arrive in completion order, so no scenario -> directory pairing can be read " <>
          "from it. Measured at alpha.11 on --suite sep-835 (S5-12). This parser's MAPPING is " <>
          "server-leg only and refuses rather than guessing; the client leg's artefact key is " <>
          "`MCP.Conformance.RunIndex`'s, and this console's other blocks are read by " <>
          "`MCP.Conformance.Console.blocks/1`, which is guarded on both legs"
      ]
    else
      []
    end
  end

  @doc """
  Scenarios the harness reported it could not run, keyed BY SCENARIO ID.

  Position-free by construction: the id is on the line itself. This is what
  makes the fact usable on the client leg, where line order carries no
  information — see `blocks/1`.

  A scenario that threw leaves **no artefact directory**, so without this a
  crash is indistinguishable from a scenario that never ran at all, and the
  flattering reading of that is "nothing failed".
  """
  @spec thrown_by_id(String.t()) :: %{String.t() => String.t()}
  def thrown_by_id(body) do
    for line <- String.split(body, "\n"),
        [_, id, message] <- [Regex.run(~r/^Failed to run scenario (\S+): (.*)$/, line)],
        into: %{},
        do: {id, String.trim(message)}
  end

  @doc """
  Scenarios the harness SKIPPED as inapplicable, keyed BY SCENARIO ID.

  Read off `Wo()` in dist/index.js at alpha.11:

      SKIPPED: scenario 'ID' is not applicable at spec version VER (WHY). Use --force ...

  On the client leg this is load-bearing rather than informational. `Ko()`
  creates the scenario's output directory **before** the applicability check and
  returns early on a skip, so a skipped client scenario leaves a directory with
  no `checks.json` in it. `MCP.Conformance.Provenance.scenario_dirs/1` keys on
  `checks.json` and therefore cannot see such a directory at all: the artefact
  tree and the enumerated tree disagree, and the disagreement has an innocent
  cause exactly here and nowhere else. Measured from harness source, and the
  reason `RunIndex` gives that state a NAME instead of reading it as absence.
  """
  @spec skipped_by_id(String.t()) :: %{String.t() => String.t()}
  def skipped_by_id(body) do
    for line <- String.split(body, "\n"),
        [_, id, why] <- [Regex.run(~r/^SKIPPED: scenario '([^']+)' (.*)$/, line)],
        into: %{},
        do: {id, String.trim(why)}
  end

  @doc "Scenario ids in the order the run executed them."
  @spec ran(t()) :: [String.t()]
  def ran(%{mappings: mappings}), do: Enum.map(mappings, & &1.scenario)

  @doc """
  Artefact directories the console named, relative to `run_dir` and sorted — the
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

  @doc """
  Scenarios that ran, threw, and left no artefact directory behind.

  Enumerated rather than counted, and surfaced as its own function because the
  whole hazard is that these are invisible in the artefact tree.
  """
  @spec thrown(t()) :: [mapping()]
  def thrown(%{mappings: mappings}), do: Enum.filter(mappings, &is_nil(&1.dir))

  # A scenario header opens a mapping, and exactly two things may close it:
  #
  #   * `Results saved to DIR` — it ran and wrote artefacts;
  #   * `Failed to run scenario X: MESSAGE` — it THREW, and the harness wrote no
  #     artefact directory for it while still counting it as failing.
  #
  # Anything else — a header closed by the next header, or by end of file — is a
  # scenario whose outcome cannot be attributed at all, and that is a fault.
  # Keeping the third case a fault is what stops the second from turning the
  # check into "anything goes": a truncated console still refuses.
  defp mappings(lines) do
    {mappings, open, faults} = Enum.reduce(lines, {[], nil, []}, &mapping_line/2)

    {mappings, if(is_nil(open), do: faults, else: faults ++ [unterminated(open)])}
  end

  defp mapping_line(line, {_acc, open, _faults} = state) do
    cond do
      id = scenario_header(line) -> open_mapping(id, state)
      is_nil(open) -> state
      true -> close_mapping(line, state)
    end
  end

  defp scenario_header(line) do
    case Regex.run(~r/^=== Running scenario: (.+) ===$/, line) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp open_mapping(id, {acc, nil, faults}), do: {acc, id, faults}
  defp open_mapping(id, {acc, open, faults}), do: {acc, id, faults ++ [unterminated(open)]}

  # The open scenario ends here, or the line is noise between the header and
  # whichever of the two endings comes. A `Failed to run scenario` naming some
  # OTHER scenario is noise, not an ending: it must not close this one.
  defp close_mapping(line, {acc, open, faults} = state) do
    saved = Regex.run(~r/^Results saved to (\S.*)$/, line)
    threw = Regex.run(~r/^Failed to run scenario (\S+): (.*)$/, line)

    cond do
      is_list(saved) ->
        {acc ++ [ran(open, String.trim(Enum.at(saved, 1)))], nil, faults}

      is_list(threw) and Enum.at(threw, 1) == open ->
        {acc ++ [threw(open, String.trim(Enum.at(threw, 2)))], nil, faults}

      true ->
        state
    end
  end

  defp ran(scenario, dir), do: %{scenario: scenario, dir: dir, threw: nil}
  defp threw(scenario, message), do: %{scenario: scenario, dir: nil, threw: message}

  defp unterminated(scenario) do
    "scenario #{inspect(scenario)} was announced and then neither saved results nor reported " <>
      "a failure to run, so its outcome cannot be attributed"
  end

  defp duplicate_faults(mappings) do
    mappings
    |> Enum.frequencies_by(& &1.scenario)
    |> Enum.filter(fn {_, n} -> n > 1 end)
    |> Enum.map(fn {scenario, n} ->
      "scenario #{inspect(scenario)} was mapped to #{n} artefact directories in one run"
    end)
  end

  # B2, and the class it belongs to. `duplicate_faults/1` above has always faulted
  # a scenario mapped to two artefact directories; the SUMMARY block — the other
  # half of the same "one line per scenario" concept, and the half every
  # cross-check is keyed on — had no such guard. A consumer that keys marks by
  # scenario (`Map.new(marks, &{&1.scenario, &1})`) collapses a duplicate
  # last-wins, so a console carrying both `✗ x: 0 passed, 1 failed` and
  # `✓ x: 1 passed, 0 failed` silently kept whichever came last. Measured on a
  # one-scenario run that the census ACCEPTED with the ✓ and discarded the ✗:
  # the collapse resolves in whichever direction the file happens to be ordered,
  # and a malformed console can therefore be flattering.
  #
  # Both directions of the mark <-> mapping join are faulted here, because only
  # one of them was checked anywhere:
  #
  #   * a scenario with more than one mark — the census cannot say which mark it
  #     agreed with, so it may not claim to have agreed with the harness at all;
  #   * a mark naming a scenario that never ran — the mirror case.
  #     `corroborate_reducer/3` refuses a scenario with no mark
  #     (HARNESS_MARK_MISSING) and says nothing about a mark with no scenario,
  #     so an invented mark passed every gate.
  #
  # Duplicates fault whether or not they agree. An identical repeat is still a
  # console this parser cannot attribute a count to, and "refuse unless they
  # conflict" would make the guard depend on the very comparison it exists to
  # protect. The message says which it was, because the two mean different
  # things to whoever reads the fault.
  # `attributable?` asks whether the console announced anything to attribute a
  # mark TO, and it is true on both legs: `announced/1` reads the server's
  # `=== Running scenario: X ===` and the client's `Starting scenario: X`, so
  # the orphans arm is live on a client console. Until MES-57 it was bounded
  # away there, on the argument that `parallel_leg_faults/1` refused such a
  # console whole so the bound cost a diagnosis and never a verdict; `RunIndex`
  # made client runs adjudicable and that argument lapsed (S5-24).
  #
  # Live membership does NOT reinstate any positional reading, and the two facts
  # are about different things: this arm reads the SET of announced ids, while
  # `parse/1` still refuses the client leg's mapping and position pairing. A set
  # is position-free; a pairing is not.
  #
  # The arm is false only for a degenerate console — client-leg start lines
  # present and not one of them carrying an id, so there is no announced set to
  # check against. There, `parallel_leg_faults/1`'s sentence is the one true
  # thing to say and per-scenario orphans would bury it. Duplicate marks are
  # faulted regardless, because a duplicate is a duplicate whoever printed it.
  defp mark_faults(marks, announced, attributable?) do
    duplicates =
      marks
      |> Enum.group_by(& &1.scenario)
      |> Enum.filter(fn {_, ms} -> length(ms) > 1 end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {scenario, ms} ->
        verdicts = ms |> Enum.map(& &1.pass) |> Enum.uniq()

        "scenario #{inspect(scenario)} carries #{length(ms)} SUMMARY marks in one run" <>
          if(length(verdicts) > 1,
            do:
              ", and they CONTRADICT each other (#{Enum.map_join(ms, " then ", &render_mark/1)}); " <>
                "keying marks by scenario would keep only the last",
            else: ", so no single harness verdict can be read from it"
          )
      end)

    orphans =
      if attributable? do
        for m <- marks, not MapSet.member?(announced, m.scenario), uniq: true do
          "the SUMMARY block marks scenario #{inspect(m.scenario)}, which the console never " <>
            "announced as running, so there is nothing to attribute the mark to"
        end
      else
        []
      end

    duplicates ++ Enum.sort(orphans)
  end

  # Every scenario the console ANNOUNCED, which is not the same set as the
  # scenarios it completed. Keying the orphan check on completed mappings made
  # an unterminated scenario fault twice — once truthfully as unterminated, once
  # with a sentence saying the console never announced it, which it had. One
  # defect must produce one fault, and a fault that misdescribes its own cause
  # is worse than none.
  defp announced(lines) do
    for line <- lines, id = scenario_announcement(line), into: MapSet.new(), do: id
  end

  # The two shapes the harness announces a scenario in, read off dist/index.js
  # at alpha.11 rather than inferred: the server leg's sequential runner prints
  # `=== Running scenario: X ===`, and the client leg's parallel runner prints
  # `Starting scenario: X` (`Ko()`, via `console.error`).
  #
  # Both are MEMBERSHIP facts — "this console announced X" — and neither is an
  # ORDER fact. That distinction is the whole of MES-57's design ruling: the
  # client leg's saves arrive in completion order, so a scenario's POSITION
  # carries no information, while the SET of scenarios it announced still does.
  # Reading the set is not the positional pairing that was measured and
  # mis-attributed 4 of 5.
  defp scenario_announcement(line), do: scenario_header(line) || starting_scenario(line)

  defp starting_scenario(line) do
    case Regex.run(~r/^Starting scenario: (.+)$/, line) do
      [_, id] -> String.trim(id)
      _ -> nil
    end
  end

  defp render_mark(m),
    do: "#{if m.pass, do: "✓", else: "✗"} #{m.passed} passed, #{m.failed} failed"

  # The not-scored block's own copy of the same property. Nothing in this
  # project reads `not_scored` yet — MES-57 and MES-58 will — and a duplicate
  # here fails exactly the way the marks did, silently and in whichever
  # direction the file is ordered. Guarded now rather than after it is
  # load-bearing, since that is the difference this round was called to fix.
  defp duplicate_not_scored_faults(not_scored) do
    not_scored
    |> Enum.frequencies_by(& &1.scenario)
    |> Enum.filter(fn {_, n} -> n > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {scenario, n} ->
      "scenario #{inspect(scenario)} appears #{n} times in the not-scored block, so its " <>
        "harness reason cannot be read from it"
    end)
  end

  # C1, and B3's intra-console half. `duplicate_not_scored_faults/1` above has
  # guarded this block's MULTIPLICITY since round 2; nothing guarded its
  # MEMBERSHIP, so the file implemented one half of a paired concept for the
  # third time. This is the sibling of `mark_faults/3`'s orphans arm.
  #
  # Measured, not argued: a console with `✓ ghost-scenario (extension)` appended
  # to its not-scored block parsed with `faults: []`, the ghost reached
  # `parsed.not_scored`, and the census ACCEPTED the run. A scenario that never
  # ran carried a harness verdict and a harness reason into an IR that MES-57
  # and MES-58 are documented consumers of.
  #
  # Armed by the same `attributable?` as `mark_faults/3` and live on both legs
  # for the same reason: `announced/1` reads the client leg's
  # `Starting scenario:` header too, so this block's membership is checked on a
  # client console. The client-leg bound this arm used to carry lapsed with
  # MES-57's `RunIndex` (S5-24). The false clause below is the degenerate case
  # named there, not a leg test.
  defp orphan_not_scored_faults(_not_scored, _announced, false), do: []

  defp orphan_not_scored_faults(not_scored, announced, true) do
    orphans =
      for e <- not_scored, not MapSet.member?(announced, e.scenario), uniq: true do
        "the not-scored block lists scenario #{inspect(e.scenario)}, which the console never " <>
          "announced as running, so there is nothing to attribute its harness reason to"
      end

    Enum.sort(orphans)
  end

  # Opened by completing the block × guarantee table rather than reported by a
  # review: `marks` and `not_scored` each carry a ✓/✗ for the SAME scenario,
  # because the harness builds the not-scored block by re-listing scenarios it
  # has already marked — and no cell of that table compares the two. A console
  # marking a scenario ✗ in the SUMMARY block and ✓ in the not-scored block
  # satisfies multiplicity and membership in both blocks and still states two
  # verdicts for one scenario, which is the duplicate-mark defect spread across
  # two blocks instead of packed into one.
  #
  # Scenarios carrying more than one mark are skipped here deliberately.
  # `mark_faults/3` already faults them, and comparing against whichever of the
  # pair a keying happened to keep would emit a second fault derived from the
  # collapse the first fault exists to report.
  #
  # Not scoped to a leg: two verdicts are two verdicts whoever printed them, and
  # on a healthy console of either leg the blocks agree — measured across all
  # four delivered runs — so this cannot restate the client-leg finding.
  defp not_scored_verdict_faults(not_scored, marks) do
    marked =
      marks
      |> Enum.group_by(& &1.scenario)
      |> Enum.filter(fn {_, ms} -> length(ms) == 1 end)
      |> Map.new(fn {scenario, [m]} -> {scenario, m.pass} end)

    not_scored
    |> Enum.filter(&contradicts_mark?(&1, marked))
    |> Enum.map(fn e ->
      "scenario #{inspect(e.scenario)} is marked #{tick(Map.fetch!(marked, e.scenario))} in " <>
        "the SUMMARY block and #{tick(e.pass)} in the not-scored block, so the console " <>
        "states two verdicts for it"
    end)
    |> Enum.uniq()
  end

  defp contradicts_mark?(entry, marked) do
    case Map.fetch(marked, entry.scenario) do
      {:ok, pass} -> pass != entry.pass
      :error -> false
    end
  end

  defp tick(true), do: "✓"
  defp tick(false), do: "✗"

  # `totals/1` takes the FIRST `Total:` line and folds its parts into a map,
  # where a repeated label would collapse last-wins. Neither the second line nor
  # the losing label is reported by the fold itself, so both are faulted here.
  # Same reasoning as the block above: unread today, load-bearing for MES-58.
  #
  # MES-56 correction round 5, C2. The other two arms are this block's
  # MEMBERSHIP guarantee, which round 4 called vacuous on the ground that the
  # block keys on status labels rather than scenario ids. The review measured
  # that the keys are still a domain someone can leave: `total_parts/1` matches
  # `^(\d+) ([a-z]+)$`, so `Total: 3 widgets` parsed faultlessly and put a key in
  # the map that no reader knows about, and a part matching NEITHER shape was
  # dropped by the `is_list/1` filter without a word. Both are the same defect
  # the round is about — a line that contributes nothing and says nothing — so
  # the cell is enforced here rather than excused.
  defp totals_faults(lines) do
    totals = Enum.filter(lines, &String.starts_with?(&1, "Total: "))
    first = Enum.take(totals, 1)

    repeated_lines =
      if length(totals) > 1,
        do: [
          "the console carries #{length(totals)} `Total:` lines (#{inspect(totals)}); only " <>
            "the first is read, so the run has no single total"
        ],
        else: []

    unparsed =
      first
      |> Enum.flat_map(&unparsed_parts/1)
      |> Enum.map(fn part ->
        "the `Total:` line carries the part #{inspect(part)}, which is not `N label`; a part " <>
          "that does not parse is dropped without a word, so the line would state less than " <>
          "it appears to"
      end)

    unknown =
      first
      |> Enum.flat_map(&labels/1)
      |> Enum.reject(&(&1 in @total_labels))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn label ->
        "the `Total:` line states #{inspect(label)}, which is not a label the harness prints " <>
          "(#{Enum.map_join(@total_labels, ", ", & &1)}); a key nothing reads contributes " <>
          "nothing and says nothing"
      end)

    repeated_labels =
      first
      |> Enum.flat_map(&labels/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_, n} -> n > 1 end)
      |> Enum.sort()
      |> Enum.map(fn {label, n} ->
        "the `Total:` line states #{inspect(label)} #{n} times, and only the last is kept"
      end)

    repeated_lines ++ unparsed ++ unknown ++ repeated_labels
  end

  # C1, and the join the block table cannot state because it is not a property
  # of any one block. The `Total:` line and the SUMMARY marks are two reducers
  # the harness runs over ONE result list, and it computes the first BY summing
  # the second — read off the harness rather than inferred:
  #
  #     for (let r of e) { ... t += passed; n += failed;
  #                        log(`${tick} ${r.scenario}: ${passed} passed, ${failed} failed`) }
  #     log(`\nTotal: ${t} passed, ${n} failed`)
  #                       -- @modelcontextprotocol/conformance 0.2.0-alpha.11,
  #                          dist/index.js, both server printers; the client
  #                          printer is the same fold with a warnings column
  #
  # So a console in which they disagree is not a console the harness produced,
  # and nothing may be attributed to it. Measured before it was guarded: a
  # console whose marks sum to 1 passed / 0 failed and whose `Total:` line says
  # 0 passed / 1 failed parsed with `faults: []` and the census ACCEPTED it.
  #
  # Suppressed when the marks block or the `Total:` line is ALREADY faulted,
  # which is the file's rule that one defect produces one fault. A sum taken
  # over a block that repeats or invents a mark is not the harness's sum, and a
  # total read off a malformed line is not the harness's total; re-reporting
  # either as a disagreement would describe the symptom of a defect whose cause
  # is already named. The console is refused either way, so the suppression
  # costs a diagnosis and never a verdict.
  #
  # `skipped` is the one label with no arm here, and it is a bound rather than a
  # gap: the client leg prints a skipped scenario as `- X: skipped`, which
  # carries no ✓/✗ and is not a SUMMARY mark, so there is no mark-side number to
  # sum. Reading that line would mean deciding whether a skipped scenario counts
  # as announced — a question this parser still does not answer, and one that is
  # separate from the client leg's artefact key, which MES-57 settled in
  # `MCP.Conformance.RunIndex`.
  defp total_sum_faults(_totals, _marks, [_ | _]), do: []

  defp total_sum_faults(totals, marks, []) do
    @summed_labels
    |> Enum.filter(fn {label, _} -> Map.has_key?(totals, label) end)
    |> Enum.flat_map(fn {label, field} ->
      summed = marks |> Enum.map(&Map.fetch!(&1, field)) |> Enum.sum()
      stated = Map.fetch!(totals, label)

      if summed == stated do
        []
      else
        [
          "the SUMMARY block's #{length(marks)} marks sum to #{summed} #{label}, and the " <>
            "`Total:` line states #{stated}; the harness prints that line by summing the " <>
            "marks it has just printed, so a console it produced cannot disagree with itself " <>
            "here"
        ]
      end
    end)
  end

  defp labels(line), do: line |> total_parts() |> Enum.map(&elem(&1, 0))

  defp unparsed_parts(line) do
    for part <- raw_total_parts(line), is_nil(Regex.run(~r/^(\d+) ([a-z]+)$/, part)), do: part
  end

  # The warnings suffix is CAPTURED rather than skipped. `Regex.run/2` drops a
  # trailing group that did not participate, so a server-leg line arrives as
  # four captures and a client-leg line with warnings as five; both shapes are
  # matched here rather than defaulted after the fact.
  defp marks(lines) do
    lines
    |> Enum.map(
      &Regex.run(~r/^([✓✗]) (\S+): (\d+) passed, (\d+) failed(?:, (\d+) warnings)?$/u, &1)
    )
    |> Enum.filter(&is_list/1)
    |> Enum.map(fn
      [_, tick, scenario, passed, failed] ->
        mark(tick, scenario, passed, failed, "")

      [_, tick, scenario, passed, failed, warnings] ->
        mark(tick, scenario, passed, failed, warnings)
    end)
  end

  defp mark(tick, scenario, passed, failed, warnings) do
    %{
      scenario: scenario,
      pass: tick == "✓",
      passed: String.to_integer(passed),
      failed: String.to_integer(failed),
      warnings: count(warnings)
    }
  end

  defp count(""), do: 0
  defp count(digits), do: String.to_integer(digits)

  # The not-scored block repeats scenarios that already have a SUMMARY mark, and
  # adds the harness's reason. Parsed separately so the reason can be compared
  # with the frozen set's rather than trusted from either alone.
  defp not_scored(lines) do
    lines
    |> Enum.map(&Regex.run(~r/^  ([✓✗]) (\S+) \(([a-z-]+)\)$/u, &1))
    |> Enum.filter(&is_list/1)
    |> Enum.map(fn [_, tick, scenario, reason] ->
      %{scenario: scenario, pass: tick == "✓", reason: reason}
    end)
  end

  # `Total:` is `N passed, M failed` on the server leg and grows `, K warnings`
  # and `, J skipped` on the client leg. Parsed as named parts rather than by
  # position, so the client leg's extra fields are read instead of shifting the
  # server leg's.
  defp totals(lines) do
    lines
    |> Enum.find("", &String.starts_with?(&1, "Total: "))
    |> total_parts()
    |> Map.new()
  end

  # One parse, three readers: `totals/1` wants the numbers, `totals_faults/1`
  # wants the labels, and `unparsed_parts/1` wants the parts that matched
  # neither. Reading the line three times with three copies of the same regex
  # would let the fault checks and the value they guard drift apart.
  defp total_parts(line) do
    line
    |> raw_total_parts()
    |> Enum.map(&Regex.run(~r/^(\d+) ([a-z]+)$/, &1))
    |> Enum.filter(&is_list/1)
    |> Enum.map(fn [_, n, label] -> {label, String.to_integer(n)} end)
  end

  defp raw_total_parts(line) do
    line
    |> String.replace_prefix("Total: ", "")
    |> String.split(", ", trim: true)
  end
end

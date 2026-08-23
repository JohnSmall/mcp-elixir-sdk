# Sprint 7 — procedure defects

Procedure defects found while working Sprint 7 (epic MES-65): things wrong with
**how we work** — the gate set, the briefs, the tooling contract.

Ticket substance does not go here. Findings about the MCP SDK itself, about
conformance results, or about a specific ticket's deliverable belong in comments
on that ticket. This file is for defects a *future* sprint would otherwise hit
again.

Each entry states the **mechanism**, because the mechanism is the transferable
part. "The description tool wouldn't take my content" is not reusable; "the
description writer validates against the `jira_comment` profile, which has no
`heading` node" is.

---

## S7-1 — The sweep that establishes a defect outlives the script that produced it: the number survives and the thing that produced it does not

**Found:** MES-75, 2026-08-23, by CODE_CREATOR, while planning the fix for a
defect CODE_REVIEWER had established at MES-66's merge gate.
**Status:** CLOSED — the remedy landed in MES-75 itself, in the same commit as
the defect it was found under. Recorded anyway, because the mechanism is
general and the next occurrence will not be in a ticket that happens to be
about mutation sweeps.

### The defect

CODE_REVIEWER's merge gate on MES-66 (comment 25594) established MES-75's entire
premise by measurement rather than by reading: it mutated the committed
manifest four ways and read `mix test`'s verdict off each.

```
EMPTY           -> 24 tests, 6 failures
DROP_EXCLUSION  -> 24 tests, 1 failure
FABRICATE_ROW   -> 24 tests, 0 failures   <-- passes
FLIP_STATUS     -> 24 tests, 0 failures   <-- passes
restored        -> 24 tests, 0 failures
```

That table is the whole evidentiary basis for a ticket. **The script that
produced it was never committed and no longer exists** —
`grep -rl 'FLIP_STATUS\|FABRICATE_ROW' /tmp` returned nothing **when taken,
2026-08-23 at the start of this ticket**. Re-run after the ticket it returns many
paths — this ticket's own committed script and its working copies. The dated
qualifier is not pedantry: a stated check in a committed register must survive
being re-run literally, and without the date this one now reads as refuted by
the very work that fixed it. Raised by CODE_REVIEWER at the MES-75 merge gate. What survived is
five numbers in a Jira comment, in a project whose standing rule is that every
claim carries an address *and* the bytes at it.

So the mutations had to be reconstructed from the comment's prose. The
reconstruction reproduced all five counts exactly, which is the lucky outcome
and not the point:

```
mutation                tests  failures
EMPTY                      24         6
DROP_EXCLUSION             24         1
FABRICATE_ROW              24         0
FLIP_STATUS                24         0
RESTORED                   24         0
```

**Had it not reproduced, a bad reconstruction and a changed tree would have
been indistinguishable.** The ticket's premise would then have been
unfalsifiable in *either* direction: agreement could not confirm it, because a
different mutation can produce the same count, and disagreement could not
refute it, because the original mutation was unavailable to compare against.
The evidence was one coin-flip away from being unusable, and nothing in the
procedure noticed.

### The mechanism, which is the transferable part

**A measurement's output is committed and its instrument is not.**

The three steps are individually reasonable and jointly lossy:

1. A seat needs to establish something about the tree, so it writes a throwaway
   script under `/tmp`.
2. It reports the *result* — a table, a count, a verdict — in a Jira comment,
   because that is where findings go.
3. The comment is permanent. `/tmp` is not.

Nothing in the procedure connects steps 1 and 3, because the script never
presents itself as a deliverable: it is scaffolding, and scaffolding comes down.
But the number's *meaning* is entirely a function of the scaffolding — "0
failures" means nothing without the definition of the mutation that produced it.

The distinguishing test for whether this applies is not "was code written" but:
**would a future reader need to re-run this to act on it?** A one-off `wc -l` is
not this. A control, a sweep, a probe, or anything whose result becomes a
ticket's premise is.

### Same shape as S6-4, one level up

S6-4 recorded an artefact regenerated from the wrong input, internally
consistent, passing every semantic check — settled only by *reproduction against
the committed bytes*. Its lesson was that provenance is proved by regeneration,
not by inspection.

This is that lesson applied to a **measurement** rather than to an artefact.
There, the artefact was committed and the input was not. Here, the result is
committed and the instrument is not. In both cases what is missing is exactly
the thing that would let a second person get the same answer.

Note the direction of the irony: **MES-75 exists because an assertion nobody had
watched fail was shipped, and it was very nearly fixed by a sweep nobody could
re-run.**

### The remedy, as applied

`conformance/controls/manifest_mutation_sweep.exs` is committed, alongside the
five controls already in that directory.

The PM's ruling on it is the load-bearing half and is worth restating:
**commit the mutation DEFINITIONS, not just a runner.** The definitions are the
part that was lost. A runner that read its mutations from an uncommitted file
would reproduce this very finding inside its own fix.

The script also gains something the original could not have: because it is
committed, it can be run at any later tree. Its first use was to reproduce
CODE_REVIEWER's five rows on the *unchanged* tree before any assertion was
added — which is what made the before/after comparison a like-for-like one
rather than two tables measured with different instruments.

### What is NOT wrong, and should be said

CODE_REVIEWER's decision to mutate the manifest rather than trust the reported
sweep is the reason this defect was found at all. The finding here is about
where the script *lived*, not about the work. Reviewing by measurement is the
behaviour this project wants more of, and a rule that made it more expensive
would be a bad trade.

Nor is "commit every throwaway script" the lesson. Most `/tmp` scripts should
stay in `/tmp`. The trigger is narrower and is stated above: the script produced
a result that became a ticket's premise.

### Transferable form

**If a measurement's result is going to be cited, its instrument is part of the
result.** Commit the definitions with the number, or expect the next reader to
reconstruct them from prose and to have no way of telling a bad reconstruction
from a changed tree. A table in a comment is a claim; a table plus the script
that emits it is a measurement.

---

## S7-2 — An interrupted mutation sweep leaves the tree falsified, and nothing marks it

**Found:** MES-75 (Sprint 7), 2026-08-23, by the PM, from a lost CODE_REVIEWER turn.
**Status:** open as a class. The reference remedy already exists in-tree — see below.

**Sibling of [S7-1](#s7-1), and they fail in opposite directions.** S7-1 *loses*
information: the script goes, the number stays, and the next reader at least knows
they are stuck. **S7-2 leaves false information behind** — a falsified artefact with
no marker saying so, which the next reader measures against and gets a confident
wrong answer from. That is the worse failure, and it is why this is a separate
entry rather than a restatement.

### What happened, measured

```
15:50:50Z  CODE_REVIEWER ASSIGNED + PICKUP   ticket=MES-75
15:51:55Z  erl_crash.dump written in /tmp/cr75 (5.7 MB)
             "Runtime terminating during boot ({badarg,[{io,put_chars,
              [standard_error, ..."
16:17:13Z  CODE_REVIEWER ENGINE_EXIT rc=0
           comments posted: ZERO.  elapsed: 26 minutes
```

The turn ended mid-sweep. `/tmp/cr75` was left with an **uncommitted
`FABRICATE_ROW` mutation still applied** to `docs/conformance/in-scope-2026-07-28.json`
— `id` → `fabricated-check-id`, `description` → "a check that was never run", the
six-field `key` left stale. Diff preserved at `/tmp/cr75-leftover-mutation.diff`;
restored by the PM to md5 `f121edf6f18666cc27c44c4dfa8e7ac5`, verified against the
committed blob rather than against an asserted number.

### Why a restart is exactly when this bites

Nobody re-checks a starting state that looks like the one they left. The seat would
have resumed in a worktree it recognised, run the suite against a manifest with a
fabricated row in it, and reported a verdict — and neither seat nor PM would have had
any signal. The tree carries no marker distinguishing "mid-sweep" from "clean".

**Bound, stated so the entry is not read as wider than it is.** Worktree isolation
held: `main` and the branch were never touched. The exposure is confined to whoever
next uses that worktree, which on a restart is the same seat.

### Transferable form

**A sweep's scaffolding and the sweep's lifetime are not the same length, and the
tree is not a scratch buffer.** Anything that mutates a committed artefact in place
must be able to restore it *without* reaching the end of its own happy path.

### The remedy already exists and is committed

`conformance/controls/manifest_mutation_sweep.exs`, delivered by this same ticket, is
the reference implementation: it holds the original bytes in memory, restores after
**every single run** rather than at the end of the batch, re-checks the md5 at exit,
and exits non-zero if the restore did not take. CODE_REVIEWER built the same guard
into its own independent runner and verified all five of its worktrees clean before
removing them. The pattern is established; what is missing is anything that *requires*
it.

**Wording of the mechanism, the bound and the S7-1 contrast owed to CODE_REVIEWER's
MES-75 merge-gate review.**

---

## S7-3 — An acceptance criterion borrows the check that is right for the artefact's usual case, and the ticket is about the exception

**Found:** MES-77, 2026-08-23, by CODE_CREATOR at the plan hop, while trying to
satisfy AC1 literally. **Second occurrence in two consecutive tickets**, which is
what promotes it from an incident to a mechanism — the PM named the count and asked
for the decision to be made with it in view (MES-77 comment 25982).

### The two occurrences

| ticket | the AC | why it could not be satisfied as written |
| --- | --- | --- |
| **MES-75** | AC5 — regenerate the census and diff byte-identically | the census's *change* was the deliverable, so byte-identity with the committed file was false **by construction** |
| **MES-77** | AC1 — `encode/1`/`decode/1` round-trip the new form | the new form is the `oc:none` token, and `encode/1` structurally cannot build it: it gates on `check_leg/1` against `@legs = ~w(server client)`, so leg `none` returns `{:error, {:unknown_leg, "none"}}`. The builder is `none/2` (`match_key.ex:165-172` **at `main` = `32dd7c2`, the tip the AC was read against**; MES-77 moved it to `:191`) |

### The mechanism

Both ACs name a check that is **correct for the artefact's ordinary case**, and in
both the ticket is about the case that is not ordinary. "Regenerate and diff" is the
standing way to prove a generated artefact's provenance — except when the
regeneration target *is* the change. "`encode/1` round-trips it" is the standing way
to prove a token scheme reversible — except for the one token `encode/1` is
constructed to refuse.

That is why neither is caught in the writing. The AC names a **real** procedure and a
**real** function, so it reads as concrete and already-verified. The error is not in
the identifier; it is in the identifier's **scope**, and scope is invisible at the
altitude a brief is written at.

### What made both detectable in advance — and it is the same property that caused them

Both ACs named a **specific identifier**. That is precisely what let them be read
against the code at plan time and falsified before a line was written. An AC phrased
as *"prove the new form round-trips"* would have been unfalsifiable at the plan hop
and would have surfaced at the gate instead, as a correction round.

**So the remedy is not "write vaguer ACs".** Precision is what made the catch
possible; the defect and its detection come from the same property. The remedy is on
the reading side.

### Transferable form

**Before executing, run every AC that names a function or a procedure literally
against the code — not charitably.** A charitable reading substitutes the AC the
author meant, which is exactly the substitution that hides the defect. Where the
literal reading fails, propose the substitute *and say it is a substitute*, at the
plan hop where it costs one comment rather than at the gate where it costs a round.

Both times the substitute was accepted unchanged. Neither cost more than a paragraph.

**Generalises past ACs:** this is the same shape as
[stated-check-must-be-run-literally] — a stated check returning the opposite when
actually run. Here the check does not return the opposite; it cannot be run at all.

---

## S7-4 — A textual mutation that fails to apply is indistinguishable from a mutation that was not caught

**Found:** MES-77, 2026-08-23, by CODE_CREATOR, live, in this ticket's own mutation
sweep over `MCP.Conformance.MatchKey`.

### What happened

Six mutations were run against the new tests to show they discriminate. The fourth
substituted a source line by exact-string anchor; the anchor was mistyped, so the
patch script raised and **applied nothing**. The runner then executed the suite
against the *unmutated* file and printed:

```
MUT offender not sorted (last, not first) -> 49 tests, 0 failures
```

which is the exact output a **genuinely uncaught mutation** produces. Read down a
column of results, it is a finding: "this mutation is not detected". It is not one.
Re-run against the real line, the mutation was caught — 1 failure.

### The mechanism

A mutation sweep reports the *suite's* verdict. It does not report whether the
**mutation was applied**, and those are two different questions that share one output
line. The failure is silent in the direction that matters: a mutation that never
lands reads as a **gap in coverage**, which is the alarming direction, so it will be
believed and acted on.

This is the **gate-6a sentinel shape** arriving in mutation testing: a green (or here,
a zero-failure) that means "the instrument did not fire" rather than "the answer is
none". The project has recorded that shape against greps and against `hex.audit`;
this is the same thing one layer over.

**It is specific to TEXTUAL-anchor mutation.**
`conformance/controls/manifest_mutation_sweep.exs` (S7-2's reference implementation)
mutates **decoded JSON structurally** — `Map.put` on a parsed row — so it has no
anchor to miss, and this entry is not a defect in it. The hazard belongs to any
runner that patches source by exact string, which is the natural way to mutate code
rather than data.

### Transferable form

**A mutation runner must assert the mutation LANDED, and report an anchor miss as a
distinct outcome from a zero-failure run.** The cheap form is an anchor-count
assertion (`count == 1`, so a missing *or* duplicated anchor both fail) plus a
distinct label in the output — `ANCHOR MISS (no mutation applied; NOT a result)`
rather than a test summary. That is what the corrected runner in this ticket printed.

**The general rule:** whenever an instrument can fail in a way that produces a
well-formed answer, the "did the instrument fire" question needs its own reported
result, next to the answer and not folded into it.

---

## S7-5 — A re-point can remove the last witness for a property that no individual test ever claimed to be testing

**Found:** MES-77, 2026-08-23, by CODE_REVIEWER, with a mutation of its own (CR-M8)
after the PM asked for one in the over-strict direction. Surviving mutation, so the
gap was demonstrated and not inferred.

### What happened

Ruling (3) on MES-77 deliberately preserved `MatchKey.none/2`'s open contract: it
accepts a heading-only origin id such as a bare `CG4`. The same ruling re-pointed
`match_key_test.exs:152,194` away from that form onto the new `none/3` builder,
because the heading-only form is forbidden *in the new scheme*.

CR-M8 then made `none/2` **reject** a heading-only id — inverting the preserved
contract — and gate 5 returned **49 tests, 0 failures**, with the mutation confirmed
applied. The property was unwitnessed.

The mechanism, established rather than guessed: after the re-point, the only surviving
`none/2` call anywhere in `test/` was `match_key_test.exs:545`, which passes
`T-CG1a` — and that **contains a hyphen**. The natural way to implement the forbidden
strictness is "must contain a separator", and the sole remaining witness happened to
satisfy it. The two re-pointed tests had been the last hyphen-free callers.

### The mechanism

Neither re-pointed test *claimed* to test the hyphen-free contract. Both were named
and written for their decode and `guard_state/2` properties, and — checked line by
line, before and after — they still assert exactly those. **The re-point was correct
and lost nothing either test was for.** What left was a property those tests happened
to witness as a side effect of their fixture data.

That is what makes this different from S7-3's family and from an ordinary regression:
there is no wrong assertion to find and no reviewer reading either test would notice,
because the property's name appears in neither. A test's fixture values are load-bearing
for properties beyond the one in its name, and **changing a fixture is not visibly a
coverage change**.

Two bounds, so this is not read as larger than it is. The property was never
*uncovered* — the AC4 control catches CR-M8 (rc=1, `MatchError` at
`native_id_collision.exs:78`, which builds `none(reason, "CG7")`). So the coverage had
moved **out of the gate and into a control run by hand**, which is pinned by whoever
remembers to run it. And the behaviour itself was correct throughout; only its witness
was gone.

### Transferable form

**When a ruling preserves a behaviour deliberately, pin it with a test whose NAME says
so — otherwise the witness is a fixture value, and the next edit that changes the
fixture removes it silently.** The remedy shipped in this ticket is one such test, and
it was verified by re-running CR-M8 against it: 50 tests, 1 failure, the new test and
only the new test.

**The general rule:** a deliberate exception is exactly the thing no test is named
after, because tests get named after the rule. Whoever writes the exception owes it a
witness — and the seat that ruled the exception is the one who owes it, not the one who
later trips over its absence.

## S7-6 — A ratification distributed across a comment thread cannot be relocated faithfully without per-element provenance, and a single comment id per element cannot carry it

**Found:** MES-80, 2026-08-23, by CODE_CREATOR at the plan hop, while working out how to
discharge an AC that asked for exactly one comment id per transcribed element.
**Status:** CLOSED — the two-id scheme was ratified (MES-80 comment `25998`) and is what
`docs/conformance/etcc-membership.md` uses. Recorded because the next
definition-shaped deliverable will hit the same thing.

### The defect

MES-67 (A2) ratified the ET-CC membership criterion. Its acceptance criteria required the
criterion to be **ratified**; nothing required it to be **written down anywhere durable**.
A1, A3 and A4 all produced files because their deliverables were file-shaped. A2's was
definition-shaped, and the brief did not notice the difference — the PM's own diagnosis, in
MES-80's body.

So the criterion lived only in the thread, and the thread is not a document. Measured:
**14 of MES-67's 21 comments carry ratified criterion text** — `25596`, `25597`, `25598`,
`25600`, `25601`, `25603`, `25604`, `25605`, `25610`, `25612`, `25613`, `25614`, `25615`,
`25616` — written by **three different seats** across a plan hop, a ratification, a
close-out, a review and a correction round.

### The mechanism — why one id per element is not merely thin, but wrong

**The unit of ratification is not the comment. It is the element, and an element has two
events that need not be in the same comment or by the same seat.**

| element | authored at | ratified at |
| --- | --- | --- |
| gate 2's decision procedure | `25610` — **CODE_REVIEWER**, as a review *recommendation* | `25612` — PM, *"I am ruling it in"* |
| the `ET-ADJ` positive test | `25603` — CODE_CREATOR, as a flagged **deviation** from the PM's condition | `25612` — PM, withdrawing their own condition as "the weaker formulation" |
| gate 4 records, never excludes | `25596` — PM, as an amendment **in the dispatch** | `25601` — PM, after CC argued for it |

A single-id citation on the first row must either **attribute a ratified rule to a review
recommendation** or **lose where it came from**. There is no third option. The scheme the
AC specified could not have carried that element correctly.

Two consequences follow immediately, and neither is available from one id:

1. **An element with an authored-at and no ratified-at is a PROPOSAL.** Without the
   distinction, transcribing the *ratification* and transcribing the *conversation* are the
   same operation, and nothing afterwards can tell them apart.
2. **Superseded values are indistinguishable from current ones.** Two of MES-67's nine
   worked examples were corrected after first statement — example 4 from `47 / 0` to
   `31 ET-CC / 16 ET-OUT` (`25604` → `25613`) and example 5 from `9/2/2` to `6/5/2`
   (`25605` → `25614`). A transcription that takes a first statement puts a figure the PM
   has since ruled **wrong** into the file the next three tickets read.

### Why "regenerate and diff" was not available, which is the reason it needed a scheme at all

Every other artefact in `docs/conformance/` has a generator, so its provenance is proved by
regenerating it and diffing. A transcription has no generator. **The check has to be
carried by the document itself** — every element naming the ids it came from, so a reader
can walk each row back — and anything in the document with no id behind it is an addition
rather than an edit.

### Transferable form

**When a deliverable is definition-shaped rather than file-shaped, the brief must name the
file, and the relocation must carry per-element `authored-at | ratified-at` provenance.**
One id per element is not a lighter version of this; it is a scheme that cannot express a
rule authored by one seat and ruled in by another, which is the normal case in a mediated
`PM→CC→PM→CR→PM` flow.

**Generalises:** the general form is that **a brief whose output is a ruling rather than a
file must name the file, or the ruling lives only in Jira comments** — the class MES-80's
own body names, alongside MES-78. It also has S6-5's shape one level up: N consumers
reconstructing one rule from a conversation, each reconstructing a slightly different rule,
with nothing to detect the divergence.

---

## S7-7 — A literal reading is the right discipline for a named IDENTIFIER and the wrong one for a named CARDINALITY. Amends S7-3's remedy.

**Found:** MES-80, 2026-08-23, by the PM, in the PM's own brief, one ticket after S7-3 was
written — and corrected before dispatch (MES-80 comment `25994`).
**Status:** OPEN as an amendment to [S7-3](#s7-3). S7-3's finding stands; its **remedy** is
under-specified and this entry narrows it. Appended rather than edited in place, because
the register is append-only.

### The instance

MES-80's brief, in draft, said *"the **nine** comments on MES-67 are the record"* — twice,
once inside the sentence **"anything not in them is not ratified."** MES-67 carries **21**.
The PM counted them rather than trusting their own text, and corrected the brief before
dispatch.

### Why it is not simply a third data point for S7-3

S7-3's remedy is: *"run every AC that names a function or a procedure literally, not
charitably, because the charitable reading substitutes the AC the author meant and that
substitution is what hides the defect."*

**Here the literal reading was the harmful one and the charitable reading was safe** — the
reverse. Read literally, "the nine comments are the record, anything not in them is not
ratified" instructs a seat to pick nine comments and treat twelve ratified ones as
non-existent. Read charitably — "all of them" — it is correct.

### The mechanism — the two cases are one rule stated at the wrong altitude

The difference is **what kind of thing the AC names.**

| the AC names | wrong value fails… | so the right discipline is |
| --- | --- | --- |
| an **identifier** — a function, a file, a procedure (`encode/1`; "regenerate and diff") | **closed**. The identifier does not exist, or the procedure cannot be run. It fails loudly, at the plan hop, for free. | **read it literally.** The literal reading is what surfaces the failure; the charitable reading substitutes a working identifier and buries it. |
| a **cardinality** — a count of a population (`nine` comments; `537` tests; `37` tests in a file) | **open**. A wrong count still names a real, non-empty set. It selects a subset and returns success, and *from inside, a subset and the whole read identically*. | **neither. Re-derive it from the source.** Reading it literally selects the wrong subset; reading it charitably discards the figure the author may have meant precisely. |

So S7-3's remedy is right about identifiers and does not reach cardinalities. A count in an
AC is not a claim to be read at all — it is a **measurement to be re-run**, and the register
already carries three instances of a count going wrong in exactly this way: S6-6's `537`
declarations presented as `566` tests, MES-67's `37` tests in a file that holds `47` units,
and now `nine` comments in a thread of `21`.

### Transferable form

**Read a named identifier literally; re-measure a named cardinality.** A figure in an AC is
never evidence — it is a hypothesis about the tree, and the tree is one command away.

The corollary is the part that costs nothing and is skipped anyway: **when an AC's figure
turns out to be right, say that you re-derived it.** "579, re-measured at the delivered tip
and it agrees" and "579" are the same number and different claims, and only the first one
tells the next reader whether anybody checked.

**Generalises:** [S7-1](#s7-1) is this rule applied across time rather than across
documents — a figure that was true at the tip it was measured at, cited at a tip that has
moved. Same object, same remedy: re-run it.

## S7-8 — A tool's own summary is a lossy projection of its own event stream, so it is neither a safe denominator nor an independent witness

**Found:** MES-83, 2026-08-23, by CODE_CREATOR, while working out what AC1's
"reconciles with `mix test`'s own reported count" could actually establish. The PM had
asked at dispatch which direction a mismatch would point, which is the question that
surfaced it.
**Status:** CLOSED in this ticket — the artefact counts from the stream and carries a
second witness. Recorded because the mechanism is not about ExUnit.

### What happened

ExUnit's headline — `13 doctests, 979 tests, 0 failures (3 excluded)` — looks like a
census of the run. It is not. `update_test_counter/2` (`cli_formatter.ex:263-265`)
returns the counter **unchanged** for `{:excluded, _reason}`, so the per-type totals
omit excluded tests entirely while including skipped and invalid ones. The excluded
count is printed, but in a separate term, in parentheses, only when non-zero.

Two consequences, and this ticket would have hit both:

1. **As a denominator it is lossy in exactly the category that mattered.** Hazard 2 of
   this ticket exists to keep "excluded" distinguishable from "not run" and from "no
   longer exists" (S6-9). An artefact that took its denominator from the headline would
   have dropped precisely that category — reproducing S6-9 *inside the fix for S6-9*.
   Measured: on a host without `node`, the same tree reports `976 tests ... (3 excluded)`
   against `979 tests` with it. The headline moves by 3; the population does not move at
   all.

2. **As a cross-check it is not independent.** Both the headline and the row count are
   computed from the *same* broadcast — `event_manager.ex:87-93` casts every event to
   every formatter. So a test that never reached the event manager (a module that failed
   to load, `--only-test-ids`, a `--max-failures` cut-off) is invisible to **both** sides
   and cancels. The reconciliation checks the projection from events to rows. It cannot
   check that the suite was discovered, and a green from it does not mean it did.

### The mechanism

A summary is produced by the same process, from the same stream, as the thing it
summarises. It therefore fails in the two ways every projection fails: it **discards
categories silently** (nothing in the output says "excluded tests are not in this
number"), and it **shares every upstream defect** with the stream it projects. Neither
failure is visible from the summary alone — a lossy projection and a faithful one print
the same shape.

This is S6-11 one level up (`sprint_6_issues.md`). S6-11 is about *our* artefacts aggregating at the point
of capture; this is about *someone else's* aggregate being borrowed as if it were a
measurement.

### Transferable form

**Count from the stream, never from the tool's summary — and when you reconcile against
that summary, say what the reconciliation cannot see.**

The remedy that worked here, and it is general: **find a second witness inside the same
run whose code path differs.** ExUnit's `module_finished` carries the module's own test
list, assembled at `runner.ex:275` by a different path from the counters, so it catches a
dropped `test_finished` that the headline cannot. Its **membership had to be established
rather than described** — it holds run and invalid tests only, because excluded and
skipped are emitted earlier at `runner.ex:243-249` and are never joined back in. The
control run establishes that by arithmetic (7 keys in the lists, 7 run/invalid rows, 2
excluded/skipped rows absent from them) rather than by reading the source and believing
it.

**The corollary is the cheap half:** a reconciliation that states its own blind spot is
worth more than one that does not, and costs a sentence. "These two numbers agree" and
"these two numbers agree, and here is the class of defect that would leave them agreeing"
are the same green and different claims.

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

---

## S7-9 — A public accessor can go stale without any test going red, because nothing calls it. Establishing that is a grep, not a judgement.

**Found on MES-81 (B2a), 2026-08-23, while sweeping `test/mcp/protocol_test.exs`.**
Raised because the PM asked for a specific distinction: whether it was **established**
that this is a defect, or only that it **looks** like one.

### The instance

`test/mcp/protocol_test.exs:10` is `assert Protocol.protocol_version() == "2025-11-25"`,
in a tree whose stateless core is pinned to `2026-07-28`.

### ESTABLISHED, and what was established

* `MCP.Protocol.protocol_version/0` returns `@protocol_version "2025-11-25"`
  (`lib/mcp/protocol.ex:9,16`) and is documented as *"Returns the MCP protocol version
  this library targets"* (`:12-16`).
* `grep -rn "protocol_version()" lib/` returns **three** hits and **all three are a
  different function**: `protocol.ex:15` is its own `@spec`, while `config.ex:141` and
  `plug.ex:244` call `Dispatch.protocol_version()`, which is
  `@stateless_protocol_version "2026-07-28"` (`dispatch.ex:84,102`).
* `MCP.Protocol.protocol_version/0` has **exactly one caller in the entire
  repository — the test line above.**

So: **nothing depends on the old constant, and the stale value cannot reach the wire.**
What is stale is a **public, documented accessor returning a version the library does not
target** — a consumer calling it gets `2025-11-25`. That is a public-API defect, not a
wire defect, and the distinction is the whole finding.

### Mechanism

A constant reaches the wire through call sites. Delete the call sites and it stops being
load-bearing **without stopping being public** — and the one test still pinning it keeps
the suite green, so nothing anywhere goes red. The test is not wrong; it faithfully
asserts what the function does.

### Transferable form

**"Is this stale?" and "does anything depend on it?" are two greps, and only the second
tells you what kind of defect you have.** A stale constant with call sites is a wire
defect; a stale constant with none is an API-surface defect and belongs in a different
ticket with a different urgency. Reporting the first without running the second overstates
it; reporting neither and calling it "looks stale" is the AC7 error of recording an
unestablished suspicion as a finding.

---

## S7-10 — A public encode/decode surface can be complete, tested, and on no path the SDK itself uses

**Found on MES-81, 2026-08-23. It is the largest single escalation in B2a's register
(45 of 75 rows) and the reason that escalation is a DISCLOSURE rather than a question.**

### The instance

Measured at `94f4d2a` with `grep -rn "..." lib/ conformance/`, each returning only the
definition site:

| surface | callers in `lib/` |
| --- | ---: |
| `MCP.Protocol.encode/1`, `encode!/1` | **0** |
| `MCP.Protocol.Messages.Response` (struct, `success/2`, `error/2`, its `defimpl`) | **0** |
| `MCP.Protocol.Messages.Tools` (`ListParams`, `ListResult`, `CallParams`, `CallResult`) | **0** |
| `MCP.Protocol.Error`'s derived `Jason.Encoder` | **0** — the only route to it was `Response` |
| `MCP.Server.StateHandle` (`mint/2`, `fetch/2`, `delete/2`) | **0** |

The SDK's own wire messages are built by hand elsewhere: `dispatch.ex:723-729`
(`error_response/2`, which conditionally **drops** `data`), `plug.ex` `send_json_error`,
and `client.ex:868` `Jason.decode!(Jason.encode!(struct))`. `Protocol.decode_message/1` —
the one MCP.Protocol function that IS on a live path — is used at `client.ex:362`,
`connection.ex:103` and `plug.ex:324`.

### Why it matters to a membership sweep, and why it was not absorbed

These modules are public API: a consumer calling `MCP.Protocol.encode!/1` puts exactly
those bytes on the wire, so §2's *"the gate is on what is asserted, not on where the test
sits"* admits them. But §2.1's counterfactual — *would an SDK that got this wire behaviour
arbitrarily wrong still pass this test?* — answers **yes** if "this wire behaviour" means
the message **this SDK actually emits**, because a broken `dispatch.ex` leaves all 45
green.

The sweep decided gate 2 **passes** and disclosed the fact on every affected row rather
than silently choosing. One answer moves 45 rows.

### The narrower observation inside it

`MCP.Protocol.Messages.Response` declares **both** `@derive Jason.Encoder`
(`response.ex:10`) and an explicit `defimpl Jason.Encoder, for: __MODULE__` (`:30-43`).
Which wins was **not established** — nothing depends on it, because nothing constructs a
`Response` — and it is recorded as a question, not a finding.

### Transferable form

**"Is this tested?" and "is this on a path the product uses?" are independent, and a
green suite answers only the first.** Before treating a test as evidence about a
product's wire behaviour, grep for the callers of the function it exercises. Where the
answer is zero, say so **in the artefact** rather than in a close-out: the fact is about
the tree, so it survives the ticket, and the next reader should not have to re-derive it.

---

## S7-11 — Gate 1 scopes on LOCATION, so an instrument test sitting in the product's test tree is in scope and must be excluded on its merits

**Found on MES-81, 2026-08-23. The mirror image of the sweep's HAZARD 4.**

### The instance

HAZARD 4 warns that `test/conformance/` is the Sprint-5 instrument and is out by rule —
413 units at this tip, excluded at gate 1 and enumerated separately so "excluded by rule"
cannot be confused with "never looked at".

The reverse case is `test/mcp/conformance_request_state_test.exs`: **12 units that test
the conformance server FIXTURE's tamper-evident `requestState` token**
(`conformance/request_state.ex`). Its own moduledoc says so — *"The fixture's helper is a
fixture, not the product answer — the SDK offers no mint/verify for `requestState`"* — and
the file sits under `test/mcp/` by a ratified decision (MES-24 RULING 4).

Gate 1 asks *"is the unit under `test/mcp/`?"*. It is. So all 12 are **in the 579** and had
to be excluded at gate 2 or 3 on their own merits:

* eleven at **gate 2** — the asserted artefacts are fixture-invented atoms (`:bad_tag`,
  `:malformed`), and `ET-ADJ` is unreachable because §5 requires a call site that is a
  `file:line` in **`lib/`**, and `grep -rn "RequestState" lib/` returns nothing;
* one at **gate 3** — `:48` asserts the token is url-safe and unpadded, and
  `schema.ts:591-592` says *"The client must treat this as an **opaque blob**; it must not
  interpret it in any way."* **A requirement that a value is opaque is precisely a
  requirement that its format is ungoverned.**

### Transferable form

**A scoping gate that keys on location classifies files, not intentions.** When a
deliberate exception puts an instrument test inside the product's tree, the scoping gate
will not catch it and the substantive gates must — so a sweep that reasons "this file
tests the instrument, therefore out of scope" has skipped the gates that actually apply,
and will record the wrong excluding gate even when it reaches the right label.

And the smaller, sharper half: **"the spec says this value is opaque" is a gate-3
FAILURE, not a gate-3 gap.** It is the one case where the spec's own words establish that
no anchor can exist, which is stronger evidence than not finding one.

---

## S7-12 — A ratified worked example can carry a sub-figure that no longer reproduces, without its ruling being wrong

**Found on MES-81, 2026-08-23, by running §11's twenty-two pre-decided units as ordinary
units and comparing only afterwards.**

### What reproduced, and what did not

All **eight** ratified labels reproduced exactly, including both split figures —
`JsonSchema202012Test` 31/16 over 47 units with 15 excluded at gate 2 and 1 at gate 3, and
the 13 doctests 6/5/2. The control worked.

Two **sub-figures inside the reasoning** did not:

1. `§11` example 2 states *"11 of those constants **are** consumed on a wire path"*. At
   `94f4d2a` it is **9 of 12**: `grep -rn "Methods.<name>()" lib/` returns zero for
   `initialize`, `ping` and `logging_set_level`.
2. `§11` example 4 states *"two bind the response to `_result` and discard it"*. It is
   **four** — `json_schema_2020_12_test.exs:307`, `:340`, `:439`, `:451`.

Neither changes a label: §6's any-assertion rule needs **one** consumed constant, and the
15/1 gate split is stated independently of how the fifteen were spelled.

### Mechanism, and why it is worth a numbered entry

A worked example carries two kinds of number: the **verdict** (a label, a split) and the
**working** (a count inside the argument for it). Ratification is about the verdict; the
working is checked as far as it needs to be to carry the verdict and no further. So a
working figure can drift, or be miscounted at ratification, while the verdict stays right
— and nothing downstream will notice, because downstream consumes the verdict.

`§B.4(ii)` already records one figure in this thread that does not reproduce (the "nine
comments" count, which is 14), and `§B.4(iii)` records that example 4's own `31` has a
narrower ratification than the rest of its correction round. **This is the third and
fourth instance**, which is what makes it a pattern rather than a slip.

### Transferable form

**When you use a ratified example as a control, compare the VERDICT and re-derive the
WORKING.** They have different warrants. Reporting a working figure that has drifted is
cheap and keeps the example usable; silently re-aligning to it — or worse, propagating it
— turns a control into a copy.

---

## S7-13 — Two ratified rules can decide the same fact differently when one is a worked example and the other is a later tie-break

**Found on MES-81, 2026-08-23. It is why one fact carries two labels in B2a's register,
and the disagreement is stated on both sides rather than smoothed over.**

### The instance

`etcc-membership.md` §11.1 rules **both** `Extensions.from_meta/1` doctests `ET-CC`,
describing the `from_meta(nil) -> %{}` one as *"the weaker: `falsifiable: undetermined`"*
— treating an **absence marker** as a gate-**4** weakness, which never excludes.

The PM's decode-boundary tie-break of 2026-08-23 (MES-81 comment `26026`) rules the
opposite for structurally identical values: a value with *"no wire counterpart at all —
there is nothing for them to be verbatim to"* fails gate **2**. `%{}` returned for an
input of `nil` has no wire counterpart.

Six rows turn on the answer: the doctest itself, `extensions_test.exs:391` and `:411`,
`meta_test.exs:28`, and `capabilities_test.exs:26` and `:75`.

### What the sweep did, and why

It carried **§11.1's ratified label** for the unit §11.1 names — Part A binds the
consuming ticket, and a worked example naming an exact unit outranks a §9 tie-break — and
the **tie-break's answer** for the five units §11.1 does not name. So the register is
internally inconsistent on one fact **on purpose**, with both rows saying so and three of
them escalated.

The alternative — picking one rule and applying it to all six — would have produced a
consistent register and hidden the conflict, and nobody downstream could have found it.

### Mechanism

A worked example is ratified as a **decision about a unit**; a tie-break is ratified as a
**rule about a class**. Where the unit is in the class and the two disagree, there is no
ordering between them that is not itself a decision. The criterion's own precedence
machinery (§6) orders *labels*, not *authorities*.

### Transferable form

**When a ratified example and a ratified rule disagree, record both answers and escalate;
do not derive a third.** The inconsistency is a fact about the criterion, and making the
artefact consistent destroys the only evidence of it. State it on **every** affected row,
not once in prose — a reader querying the artefact must be able to find all of them
without reading the document.

---

## S7-14 — Three ambiguities in a ratified criterion, each surfaced by a ticket applying it and each needing an amendment rather than a tie-break

**Found on MES-81, 2026-08-23, in the PM's five adjudications (`26033`-`26037`). All
three are candidates for a Part A amendment ticket with MES-67-style ratification; none
was fixed in place, because correcting ratified text is editing a ratified document.**

### The three

| # | ratified text | the ambiguity | how it was resolved for now |
| --- | --- | --- | --- |
| 1 | **§2**, *"the output of the public encode/decode boundary **that produces one**"* | Does the qualifier restrict the clause, or merely describe it? On the restrictive reading a boundary with no `lib/` caller does not *produce* a wire artefact and gate 2 fails; on the plain reading `MCP.Protocol.encode/1` is literally the public encode boundary and gate 2 passes. **45 rows turn on it.** | PM ruling A (`26034`) took the restrictive reading, resolving inside Part A's own decision procedure (§2.1's counterfactual) rather than overriding it. Governs B2a, B2b and B4 until amended. |
| 2 | **§6**, the any-assertion rule | It makes membership follow assertions executed in a shared `setup`/helper, so **every test sharing an asserting helper becomes a member**. That is what §6 says; it is not obviously what §6 intended. | PM ruling C (`26035`) applied §6 as written and accepted the consequence, noting it is a reason to amend §6, not to decide against it. Moved 3 rows here, and would move more in any file with a richer helper. |
| 3 | **§11.1** as a worked example vs a later §9 tie-break | A worked example carries a *reason*, not only a result. Letting the reason govern one row and a later rule govern its structural twins produces one fact under two labels. | PM ruling E (`26036`) generalised §11.1's ratio and **reconciled** the two rather than withdrawing either. See S7-13 for the conflict and S7-15 for how it arose. |

**Added in round 3 (CODE_REVIEWER at `26046`, adopted by the PM at `26047`), because
"4 of 5 rulings overturned the sweep" will be read later as a verdict on the sweep and
it is not one: every one of the four was overturned on a RULE the sweeper had flagged,
not on a FACT the sweeper got wrong.** The reviewer re-ran every underlying measurement
and the facts held; the single figure that moved (F2) moved in the sweeper's favour. A
high overturn rate on flagged rules is what a working escalation discipline looks like
from the outside, and reading it as an error rate would create exactly the pressure not
to flag.

### Mechanism

All three are the same shape: **the ticket that first applies a criterion at scale is the
first thing that can find its ambiguities**, because an ambiguity is invisible until two
readings decide a real row differently. A criterion reviewed in the abstract cannot
produce that pressure; 579 rows can.

### Transferable form

**An ambiguity in ratified text is not a tie-break's to fix.** A tie-break decides a case;
an amendment changes a rule. Resolving an ambiguity *by* tie-break leaves the ratified
text still ambiguous and adds a second authority beside it — which is how the S7-13
conflict was manufactured in the first place. Record the ambiguity, take the narrow
ruling for the ticket in hand, and put the amendment on the board as its own ticket.

---

## S7-15 — A tie-break written to fill a gap in a document can contradict that document, because its author is looking at the gap and not at the text around it

**Found on MES-81, 2026-08-23. Named by the PM as their own error, in `26036`.**

### The instance

The PM's decode-boundary tie-break (`26026`) was authored specifically to fill R1, the
residual §9 declares and leaves without a worked case. It ruled that a value with *"no
wire counterpart at all"* fails gate 2. **§11.1 — a worked example ratified in the very
document the tie-break was filling a gap in — had already ruled the opposite** for
`Extensions.from_meta(nil) -> %{}`, treating the absence marker as a gate-4 weakness
(`falsifiable: undetermined`) rather than a gate-2 failure.

Neither the author nor the sweeper noticed at the plan hop. It surfaced only when the
sweep put both rules on structurally identical rows and had to label them (S7-13).

### Mechanism

Filling a declared gap focuses attention on the **gap's own statement** — here §9's R1
paragraph — and the reviewer's question becomes *"does this decide R1?"*. The worked
examples that constrain the same class live in a **different section** (§11.1, four
screens away) and are not what anyone re-reads when authoring a tie-break. The document's
own structure makes the check unlikely to be performed.

### Transferable form

**Check a tie-break against the WORKED EXAMPLES of the section it lands in, not only
against the rule it replaces.** A rule and an example are different kinds of authority: a
rule is checked for consistency with other rules, and nobody thinks to check it against a
table of decided cases. The examples are where the contradiction will be, precisely
because they are decisions and not statements.

**Corollary, and it is the reason this cost one round rather than a sprint:** the sweeper
who found it **shipped the inconsistency** with both answers on the rows rather than
picking a side. A consistent register would have been indistinguishable from a correct
one.

---

## S7-16 — A call-site grep on a FULLY-QUALIFIED module name is answered by the alias, and the answer it gives is always the reassuring one

**Found on MES-81, 2026-08-23, in round 2. It corrects a claim in this file's own S7-10
and in the round-1 register, and the same grep had been independently reproduced at the
PM seat (`26033`) — so it survived two checks.**

### The instance

The claim, from three places: *"`MCP.Protocol.Messages.Response` is used **nowhere** in
`lib/`"*, on the strength of `grep -rn "Messages.Response" lib/` returning only
`response.ex` itself.

The grep is correct and the claim is false. Three files alias the module —
`protocol.ex:7`, `client.ex:98`, `connection.ex:35`, each
`alias MCP.Protocol.Messages.{… Response}` — after which every use is spelled
`%Response{}` or `Response.t()`. Measured at `94f4d2a`, `grep -rn '\bResponse\b' lib/`
returns the struct **constructed** at `protocol.ex:98` (`decode_response/1`) and
**pattern-matched** at `connection.ex:112` and at `client.ex:363, 415, 435, 449, 463, 538,
563, 582, 597, 640, 656, 665`.

**The conclusion those greps were supporting survives, for a narrower reason that had to
be established separately:** every one of those uses is INBOUND, and no `lib/` path ever
re-encodes a `%Response{}`. `Response.success/2` and `Response.error/2` have zero `lib/`
call sites (`grep -rnE 'Response\.(success|error|new)\(' lib/`), and the direct evidence
is a mutation: breaking the struct's `defimpl Jason.Encoder` arbitrarily reddened exactly
2 of 979 units, both in `ProtocolTest`.

### Mechanism

Elixir's `alias` makes the fully-qualified name **absent from every call site by
construction** — that is what `alias` is for. So a grep for the qualified name searches
the one place the codebase has agreed not to write it, and returns the definition site
alone. Crucially the failure is **directional**: it can only ever *under*-count callers,
so it always produces the answer "this is dead", which is the answer a dead-path argument
wants. Nothing about the output looks wrong.

### Transferable form

**A "nothing calls this" claim needs the last segment, the alias forms, and a mutation —
not the fully-qualified name.** Concretely: grep `\bLastSegment\b` (not `A.B.LastSegment`),
grep the `alias` lines that could rebind it, and then **break the thing and run the
suite**. A mutation cannot be fooled by spelling: if nothing outside the module's own
tests reddens, nothing outside calls it. The grep is the hypothesis; the mutation is the
measurement.

---

## S7-17 — A ruling stated over a family has an ANTECEDENT, and per-row establishment is what discovers the rows that do not satisfy it

**Found on MES-81, 2026-08-23. It is why PM ruling A moved 40 rows and not the 45 the
ruling itself expected.**

### The instance

Ruling A (`26034`): *"An assertion on the output of a public encode/decode boundary that
**NO `lib/` call site routes to a transport** fails gate 2."* Expected outcome, stated in
the ruling: **all 45 → `ET-OUT`**. The ruling also said: *"Establish that per row; do not
apply it as a family sweep."*

Established per row by mutation, the antecedent turned out **not** to hold for 5 of the
45. All five assert the output of `MCP.Protocol.encode/1` — which does have zero `lib/`
call sites — but the bytes they assert are produced by the **struct's own
`Jason.Encoder`**, and those encoders are live:

| mutated | reddened |
| --- | --- |
| `%Request{}`'s `defimpl` (`request.ex:25`) | **37 units across 8 modules** — 18 `ClientTest`, 8 `IntegrationTest`, 3 `ProtocolTest`, 3 `RoutingHeadersTest`, 2 `ClientToolSchemasTest`, 1 each `ClientDefectsTest` / `ClientConformanceTest` / `SelfCompatibilityTest` — live path `client.ex:839` → `:868`. **(F8: this line read "3 units in `ProtocolTest` and 21 in `ClientTest`" until round 4. It is 18, not 21, and six further modules redden; measured twice by CODE_REVIEWER at `26045` and reproduced independently. Corrected in `etcc-register.md` in round 3, in **§7 family A**, on the table row beginning `| \`%Request{}\`'s hand-written \`defimpl\``. **At the delivered round-5 tip that row is `:996`.** The bare line number has now been wrong three times — `:739` at round 3, `:915` at round 4, `:929` after this branch's own next commit inserted 14 lines above it — which is why the section and the row's opening text are given here as well: a line address is only valid at the tip it was taken at (S7-23), and those two are content handles that survive a tip that moves. Per `26059` item 6 and `26071` item 3.)** |
| `%Notification{}`'s `defimpl` (`notification.ex:24`, `:29`) | the unit **and 14 / 13 live-path units** — live paths `connection.ex:203`, `notification_collector.ex:49` |
| `%Response{}`'s `defimpl` (`response.ex:32-38`) | **2 units, both `ProtocolTest`; 0 live** — antecedent holds, row moves |

Three struct encoders reached through one dead entry point, two of them live and one dead.
§2.1's counterfactual returns NO for the five and YES for the other 40.

### Mechanism

A ruling is written from the **exemplar** that prompted it — here `Messages.Tools`, where
the entry point and the encoder are the same dead module. The rule is then stated in terms
that fit the exemplar (*"a public encode/decode boundary"*) and applied to a family
assembled by the escalation, which was assembled by **question**, not by antecedent. The
question *"is this boundary dead?"* was one question; the answer is per row.

### Transferable form

**REWRITTEN in round 3, PM-authorised at `26049`. Clauses (ii) and (iii) are
CODE_REVIEWER's, authored at `26046`; the reason they exist is that (i) alone — which
the PM wrote into the round-2 contract almost as boilerplate — was not enough to find
F1 (S7-18). As first written this entry was half a rule, and the missing half arrived
one round later, which is the best evidence for the rewrite that could be asked for.**

Where a ruling names a condition, the condition is the deliverable, not the expected
count. Three clauses, and the third is the one that makes the first two run:

1. **Establish the antecedent PER ROW INSIDE the family — it will not hold for all of
   them.** This is what caught the five survivors above. Report the rows that fail it
   even when that disagrees with the number the ruling predicted, and especially then:
   a family-sweep that reproduces the predicted number is indistinguishable from one
   that was never checked.
2. **Then ask which rows OUTSIDE the family the antecedent also reaches.** A ruling
   stated over a family **silently inherits that family's boundary** — and that
   boundary was drawn before the ruling existed, usually by something with nothing to
   do with the antecedent (here: what the sweeper happened to escalate). The scope of a
   ruling is its antecedent, not the set of rows it was put over.
3. **Name the test.** For ruling A it is *"mutate the encoder, re-run the suite, count
   what reddens outside the module's own tests"* — about 20 seconds per module. **A
   ruling whose antecedent has no named procedure gets applied by reading, and reading
   is what draws the boundary at the family.** Naming the procedure is also what makes
   clause 2 affordable: 29 boundaries at 20 seconds is one sitting, and nobody omits a
   step that cheap for reasons of cost.

The corollary for the entity issuing the ruling is unchanged: **state the expected
outcome as a sketch and say the number wins**, which is what `26037` did and what
`26048` did again when the sweep returned 30 against an expectation of 33.

---

## S7-18 — A correction contract scoped to the ESCALATED rows cannot surface a ruling's reach, because "escalated" is a property of what the sweeper found hard and the antecedent is a property of the code

**Found on MES-81, 2026-08-24, by CODE_REVIEWER (F1, comment `26044`). Named by the PM
as their own defect at `26047`. It is the instance S7-17 clause (ii) was written from,
and it is recorded separately because the rule and the case that produced it are
different things to look up.**

### The instance

Round 2's PM correction contract (`26037`) said two things that are individually right
and jointly blind:

* **item 1** — re-decide the 78 escalated rows under rulings A–E, establishing each
  ruling's antecedent per row;
* and, in the same contract, ***"Do not re-sweep the 504 unescalated rows."***

The sweeper executed both exactly. Ruling A's antecedent — *"no `lib/` call site routes
this encode/decode boundary to a transport"* — was then tested on the 45 rows the ruling
was put over, and on no others. **Thirty rows outside that set satisfy it identically.
Not one of them was escalated**, so nothing the contract asked for could have reached
them, and the register shipped `ET-CC` overstated by 30 (307 where 277 is right).

The rows are not exotic. They are `Types.Tool` (9), `Messages.Resources` (5),
`Messages.Sampling` (4), `Types.Resource` (4) and four of the five `Types.Content`
subtypes (8) — the same condition that moved `Messages.Tools`'s 36, one family over.

### Mechanism

**`escalated` and the antecedent are different partitions of the same population, and
nothing keeps them aligned.** `escalated` records what the *sweeper* could not settle
from the criterion; the antecedent is a fact about *the code*. A family assembled from
the first is a sample of the second, drawn by a process — "which rows did the sweeper
find hard?" — that has nothing to do with the condition being tested.

The instruction not to re-sweep is what makes this invisible rather than merely likely,
and it was **right for cost**: re-deciding 504 rows by hand is not affordable and would
have been the wrong use of a round. It was **wrong for reach**, and both halves belong
in the finding. The cost objection dissolves once the antecedent has a **named
procedure** (S7-17 clause iii): the total sweep that replaced it partitioned all 307
members into 31 groups over 29 boundaries and mutated each one — 29 runs, one sitting.

**And the fix is not "apply it to the reviewer's 33" either.** That was the PM's own
first instinct, rejected at `26047`: it moves the boundary from *"rows the sweeper
escalated"* to *"rows the reviewer happened to look at"* — the same defect one
iteration later. The reviewer checked five modules because the antecedent pointed at
them and said so; **five is not a population**.

### Transferable form

**When a ruling is issued mid-ticket, scope the re-decision by the ruling's ANTECEDENT
and the population by the ARTEFACT — never by the escalation list.** Concretely: before
writing *"do not re-sweep X"* into a correction contract, ask whether any ruling in that
contract has an antecedent that is a property of the code rather than of the sweep. If
one does, the contract must name a **total** procedure for it, partitioned over the
whole population, or it has silently capped the ruling's reach at whatever the sweeper
happened to flag.

**The tell that this has happened is a ruling that "moved exactly the rows it was put
over".** That reads as confirmation and is the shape of a boundary nobody tested.

---

## S7-19 — A mutation is only as strong as it is WIDE, and a narrow one returns the dead verdict for a live boundary

**Found on MES-81, 2026-08-24, running the total boundary sweep S7-18 called for. It is
the one row of that sweep that disagrees with the review's expectation, and it qualifies
S7-16's own remedy.**

### The instance

S7-16's transferable form ends *"break the thing and run the suite … A mutation cannot
be fooled by spelling."* True, and not sufficient. Both a narrow and a wide mutation of
`MCP.Protocol.Types.Content` were run over the same 979 units at the same seed:

| mutation | reddened | outside own + dead | verdict |
| --- | --- | ---: | --- |
| `TextContent.text`, `ImageContent.mimeType` (CODE_REVIEWER, `26044`) | 3 `ContentTest` + collateral | **0** | DEAD — all 11 rows move |
| per subtype: the `type:` discriminator VALUE, the payload key, and every key each `defimpl` emits | 13/11/2/2/2/2 across six boundaries | **1** for `TextContent`, 0 for the rest | `TextContent` **LIVE** — 3 rows stay, 8 move |

The single live unit is `json_schema_2020_12_test.exs:468`, which drives a real
`Dispatch` with a handler returning a `%TextContent{}`. Confirmed by construction rather
than left as an inference: that handler's return produces the wire bytes
`{"id":1,"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"hello"}],"resultType":"complete"}}`.
`TextContent`'s encoder is on the live emit path; the other four subtypes' are not.

### Mechanism

**A mutation tests the boundary only through the parts of it the mutation actually
touched, and "dead" is the verdict you get from touching nothing that anything
consumes.** The narrow mutation changed a payload key (`"text"`); the live consumer keys
on the **discriminator value** (`type: "text"`), which the narrow mutation left intact.
So the failure is directional in exactly the way S7-16 warns about for greps: **a
too-narrow mutation can only under-report reachability, so it always returns the
reassuring "this is dead"**. The measurement had the same bias as the grep it replaced.

Two corollaries, both of which the sweep now runs as procedure:

* **Potency is a precondition of a DEAD verdict.** If a mutation does not redden the
  boundary's own rows, it has not tested them. Widen until it does. (Two boundaries
  needed widening this round: `Messages.Sampling` left row `:69` green until the
  `CreateMessageResult` encoder was mutated too.)
* **A composite boundary must be split before it is mutated.** `Types.Content` looked
  like one boundary and is six; mutated whole, one live subtype is invisible behind five
  dead ones, and the verdict for the composite is the verdict for its *weakest* part.

### The other half — where the redness proxy is blind ALTOGETHER

`reddens nothing outside its own tests` is a **proxy** for the antecedent, and it has a
second failure mode the width fix does not touch: it detects reachability only *through
other tests*. Three boundaries reddened nothing outside their own tests and are
nonetheless live:

| boundary | why the proxy was silent |
| --- | --- |
| `MCP.Transport.Stdio` | the boundary **is** the transport. Its own test is the wire test — it reads bytes off a real subprocess pipe — so there is no "other test" for the proxy to find |
| `MCP.Server.NotificationCollector` | the one live test that could have caught it **refutes** a notification's presence, so renaming the key leaves the refute passing |
| `MCP.Server.Connection` | reddened **zero** units: nothing in the tree asserts a Connection-emitted notification's `method` at all |

### Transferable form

**A DEAD verdict needs three things a LIVE one does not: a wide mutation, a potency
check, and a direct look at the code.** Concretely — (i) mutate the discriminator and
the payload and every key the encoder emits, not one field; (ii) require the mutation to
redden the rows whose fate it decides, and widen it until it does; (iii) where nothing
reddens outside the boundary's own tests, **do not conclude dead** — name the `lib/` call
site and show the bytes, because silence means either *"nothing routes this to a
transport"* or *"something does and no test asserts it"*, and only reading the code tells
them apart. **LIVE is cheap and conclusive from any mutation; DEAD is the expensive
verdict and has to be earned.**

---

## S7-20 — A remedy added to fix a scope defect acquires the SAME scope defect within one round, because the seat adding it is looking at the cases that motivated it

**Found on MES-81 round 4, 2026-08-24, by CODE_REVIEWER (`26055`) and ruled BLOCKING by
the PM (`26058`). The PM records it as theirs twice over: they ratified the limb and
wrote out its justification at length without ever asking where its own antecedent
held — the exact question they had put in CODE_CREATOR's contract one round earlier.**

### The instance

**S7-17 is the defect: a ruling stated over a family has an ANTECEDENT, and applying it
to the family rather than to the antecedent misses rows.** Round 3's remedy for a
neighbouring problem was **L2**, a second limb added because L1's redness proxy is blind
in one direction — its silence means either *"nothing routes this to a transport"* or
*"something does and no test asserts it"*, and only reading the code tells them apart.

L2's trigger was written as *"where L1 is silent"*. The column that decides silence is
`reddened_outside_own_and_dead`, and it was **0 for twelve boundaries**. L2 ran on
**three** — the three the sweeper suspected.

| | |
| --- | --- |
| boundaries with `reddened_outside_own_and_dead == 0` | **12** |
| carrying an L2 record | **3** (+ `TextContent`, live by L1) |
| recorded DEAD with **no** L2 record | **9 of 9** |
| of those nine, wrong | **6** — every one came back LIVE with bytes through a real `Dispatch.dispatch/3` |

**The limb added to fix "applied to the family, not the antecedent" was itself applied
to the family and not the antecedent, one round later, by the seat that had just
written the rule down.** The six wrong verdicts moved 21 rows out of `ET-CC` that had
no business leaving; re-decided per row under the granularity ruling, 9 of the 21 came
back.

### Mechanism

A limb is introduced **in front of the cases that motivated it**. Those cases are vivid,
the antecedent is abstract, and the two are never separated at the moment of writing —
so the limb is run on the vivid set and the abstract set is never enumerated. Nothing
in the artefact distinguishes *"the trigger fired and the answer was DEAD"* from
*"the trigger never fired"*, because both print the same word.

**A rule about a rule's reach does not exempt itself.** That is the whole of it, and it
is why this entry is worth more than the count it moved.

### Transferable form

**Give every new limb a MECHANICAL TRIGGER and a GUARD at the moment it is introduced,
not after.**

* **Mechanical trigger.** State the trigger as a predicate over a column that already
  exists — *"L2 runs on every boundary whose live count is zero"* — never as a
  disposition like *"where L1 is silent"*, which reads as an invitation to judge.
  Then run it by iterating the column, not by recalling which rows looked odd.
* **Guard.** Make the un-run case **unrepresentable** in the artefact. Here that is one
  line: *no boundary may be recorded DEAD without an L2 record.* It costs nothing, it
  fires the moment the trigger is skipped, and it is the difference between a limb that
  was applied and a limb that was intended. Exercise it in more than the null form — an
  L2 record that says `ran: false`, or one whose verdict contradicts the boundary's,
  must fail too, or the guard only catches the tidiest way of getting it wrong.
* **The cost of not doing it is a whole round**, and the round is expensive because
  every downstream figure has to be re-derived. The guard would have cost four lines.

---

## S7-21 — A module nothing uses acquires no rows, so it never becomes a boundary, so its tests are never excluded — and its redness then reads as evidence FOR ITS NEIGHBOURS

**Found on MES-81 round 4, 2026-08-24, at CODE_CREATOR's seat while running the
call-site enumeration L2 requires. It is S7-20's defect one level down, and it is what
makes the exclusion set — not just the trigger — a thing that has to be derived rather
than listed.**

### The instance

The boundary sweep's live column is *"units reddened outside this boundary's own tests
**and outside the own-tests of boundaries recorded dead**"*. The second clause exists
because a dead module's tests still go red when a neighbour it calls is mutated, and
counting that as live-path evidence is exactly the mistake.

But **a boundary only enters the table if some `ET-CC` row names it as the producer of
its bytes.** A module `lib/` never uses produces no member's bytes, so it acquires no
row, so it never becomes a boundary — **so its own-tests are never in the exclusion
set.** The dead-neighbour correction has a hole shaped exactly like the modules it most
needs to cover.

`MCP.Protocol.Messages.Initialize` is such a module. The 2026-07-28 core has no
`initialize` handshake (SEP-2575/2567), and `grep -rnE '\bInitialize\b' lib/` returns
one line, doc prose at `server/handler.ex:81`. Its five test units are all `ET-OUT`, so
it never appeared in the round-3 boundary table at all. And:

    MCP.Protocol.Capabilities.ClientCapabilities (decode)
      L1 live units: 2   ->  BOTH in test/mcp/protocol/messages/initialize_test.exs
      lib/ call sites of ClientCapabilities.from_map/1: exactly ONE, initialize.ex:28
      the server never decodes client capabilities into this struct: meta.ex:105
        keeps io.modelcontextprotocol/clientCapabilities as a RAW MAP

So the boundary read **live** on the redness of a module `lib/` never runs. Under the
direction split it is **dead**, and three rows leave `ET-CC`.

### Mechanism

The exclusion set was built by asking *"which boundaries are dead?"* — a question about
the table. The right question is *"which units in a live count come from a module `lib/`
never uses?"* — a question about the **tree**. The table cannot answer it, because
membership in the table is downstream of having members.

It is the same shape as S7-20 and as S7-17 before it: a correction scoped to the set
that was already visible, rather than to the set its own antecedent picks out.

### Transferable form

**Derive the exclusion set from the live counts, not from the table.** Enumerate every
test file contributing at least one unit to any live count, and for each one ask whether
its subject module is reachable in `lib/` at all. On MES-81 that was 21 files and
`initialize_test.exs` was the single miss — a **checked negative over the whole set**,
which is the only form in which "we looked" and "there was nothing" are distinguishable.

Two smaller rules fall out of it:

* **Exclude at UNIT level, not file level, where a file is shared.** `tool_test.exs`
  holds the own-tests of a dead decode direction and a live encode one; excluding the
  file would silence the live half. The round-4 boundaries file records both sets
  explicitly — 4 files, 27 units — rather than describing the policy.
* **Record a dead module as a boundary even when it carries no members.** It costs one
  measurement and it puts the module inside the guard's reach; leaving it out is what
  made this invisible. `Messages.Initialize`, `Messages.Tools` and `Messages.Response`
  are all recorded that way now.

---

## S7-22 — ATTRIBUTION is a separate step from establishment, and it was the last one still done by eye: four rounds closed how a verdict is REACHED and none closed which rows it is APPLIED TO

**Found on MES-81 round 4 by CODE_REVIEWER (`26066`, F9), ruled by the PM at `26070`,
and closed at round 5. It is the fourth place one shape has lived in this ticket, and
the map of the four is the finding — not any one of them.**

### The instance

Two `ET-CC` rows, line-for-line identical in construction, were attributed to different
boundary sets in the same round under the same ruling:

```
capabilities_test.exs:42   -> ['ServerCapabilities (encode)']            <- encode ONLY
  caps = ServerCapabilities.from_map(map)
  decoded = Jason.decode!(Jason.encode!(caps))
  assert decoded["tools"]["listChanged"] == true

resource_test.exs:44       -> ['Resource (decode)', 'Resource (encode)']  <- BOTH
  resource = Resource.from_map(@resource_map)
  decoded = Jason.decode!(Jason.encode!(resource))
  assert decoded["uri"] == "file:///project/readme.md"
```

Not two judgements — one judgement recorded two ways. Four rows under-named:
`capabilities_test.exs:42`, `:83`, `tool_test.exs:73`, `:84`.

### Mechanism — the four places, and why the fourth outlived the other three

The register's central shape is *a rule whose antecedent nobody re-asked*. It lived in
four places, and each of the first three was closed by the same remedy — **a mechanical
antecedent plus a guard**:

| # | place | what it decides | closed by |
| --- | --- | --- | --- |
| 1 | the rule's **reach** | which boundaries a ruling is put to | F1 → whole-population sweep |
| 2 | the limb's **trigger** | when L2 runs | F6 → guard 20 (`dead` ⇒ an `l2` record) |
| 3 | the trigger's **input** | which units feed a live count | S7-21 → unit-level exclusion |
| 4 | **attribution** | which rows a verdict is applied to | F9 → guard 21 |

The first three are all about how a **boundary's** verdict is established, and they are
upstream-facing: each was found by asking *"where else does this antecedent hold?"*
**Attribution runs the other way** — it is about which rows the finished verdict lands
on — and no guard reached it. The existing guards check that a named boundary exists,
that a non-member names none, and that not every named one is dead. **Nothing checked
that the set named is the right set.** That is why F9 survived four rounds and three
seats while sitting in plain sight in the delivered artefact.

### Transferable form

**A guard that validates the ANSWER does not validate the QUESTION it was asked of.**
When a verdict is established per subject and then applied per row, the application is a
separate step and needs its own antecedent and its own guard — otherwise every check in
the pipeline can pass over a row the verdict never should have reached.

The concrete form here, and the one worth reusing: **make the criterion a
discrimination test, not a reading of the source.** The rejected alternative was *"a
fixture-builder call is not asserting a value from that producer"*, which turns on how a
line reads and is not runnable by a second reader. The ruled one — *"would a wrong
producer fail this assertion?"* — is answerable by mutation, and all four rows were
established that way rather than by inspection. One of them (`tool_test.exs:84`, which
asserts only ABSENCES) returns a two-sided answer worth keeping: a producer that
**wrongly populates** an absent optional fails it, a producer that merely **drops** a
read does not. The rule is load-bearing for exactly the fault class the row exists to
catch — which is the answer, and it is not the same as "yes".

**And state the guard's reach.** Guard 21 reads the member's own test body, so the six
`ET-CC` **doctest** rows are outside it: a doctest's body is the `@doc` in `lib/`, not
the test file at that line. A guard that scans the wrong bytes and finds nothing reports
a false green, so the residual is named rather than left to be discovered.

---

## S7-23 — A line address is only valid at the tip it was taken at, and the commit that invalidates it is usually your own next one

**Found on MES-81 by CODE_REVIEWER (`26067`, F11) — the third iteration of the same
note's own address (739 → 915 → 929), and the sharpest, because the second was caught by
CODE_CREATOR and the third was created by CODE_CREATOR's next commit on the same
branch.**

### The instance

`docs/sprint_7_issues.md:949` cited `etcc-register.md:915` for the *"37 units across 8
modules"* measurement:

```
at fe9ad8b  :915 IS the 37-across-8-modules line   <- the fix was CORRECT when made
   0860ebb  inserts 14 lines EARLIER in that file  <- the next commit, same branch
at 0860ebb  :915 is a BLANK LINE; the target is now :929
```

Nothing was rebased, nothing was merged, no other seat touched the file. A commit that
inserts **above** a cited line silently invalidates every citation below it.

### Mechanism

A line number is a coordinate in a mutable frame. Every other form of address this
project uses is content-addressed — an md5, a key, a commit hash — and stays valid
because the thing it names cannot move underneath it. A `file:line` is the one address
whose referent moves without any edit to the referent.

It is S5-31's shape (*two spellings of one fact drift apart*) moved from documents to
line numbers, and the drift is silent in both directions: neither the citing note nor
the cited section knows the other exists.

### Transferable form

**Re-resolve every `file:line` citation at the DELIVERED tip, not at the tip you fixed
it at** — and treat your own subsequent commits to the cited file as invalidating
events, because within a branch they are the likeliest one.

**This one is machine-checkable, and cheaply.** The note already names the section as
well as the line (*"in §7 family A, at `:915`"*), and that redundancy is what makes it a
checkable pair rather than a bare number: resolve the section heading in the cited file,
assert the cited line falls inside it, or better, assert the cited line matches a
recorded fragment of its own text. The general rule: **a line citation should always
carry a second, content-addressed handle** — a section, a heading, a quoted fragment —
so that a checker (and a human) can tell a stale address from a moved one.

---

## S7-24 — Prose figures are not rebuilt when the artefact is, so a delivered document accumulates the previous round's numbers in exactly the places a generator cannot reach

**Found on MES-81 round 5 at CODE_CREATOR's seat while executing the correction contract
for F10 — the same shape the contract was correcting, two sections along, and not looked
for by anyone until the third instance.**

### The instances

Three integers and one address, in three delivered documents, all of them the previous
round's value:

| where | said | should say | went stale at |
| --- | --- | --- | --- |
| `etcc-boundaries.json`, two `l2.call_site_enumeration` records | 6 and 7 live units | **5 and 6** | round 4's unit-level exclusion (F10, CR `26067`) |
| `etcc-register.md` §3 | `75 / 33 is the split` | **`75 / 37`** | round 4, while the table 20 lines above it WAS re-derived to 112 (F12) |
| `etcc-register.md` §3, "the five that left" | `capabilities_test.exs:60, :83, :161` | **`:60, :75, :161`** | never correct — two overlapping sets conflated (F13, CR `26068` found it in the close-out and it is in the document too) |

F13 is the one with teeth: `:83` is **still an `ET-CC` member**, so a reader following
the citation finds a member where the sentence promises a row that left.

### Mechanism

`etcc-register.json` is generated and cannot carry a stale figure — every number in it
is recomputed from the decisions file on every build, and 23 guards refuse a build that
does not hold together. **The prose is the complement of exactly that set**: every
figure a human typed *about* the artefact, in a file no generator writes.

So the defect concentrates where the checking does not reach, and it survives review for
a specific reason: a stale figure is locally plausible. `75 / 33` reads fine; only
comparing it to a table in the same section falsifies it. That is also why it is found
by **re-deriving the whole column** rather than by reading — the same lesson §10's
`schema.ts` count taught (220 → 194) and S7-12 before it.

### Transferable form

**Every figure in prose that also exists in a generated artefact should be re-derived
from the artefact at the delivered tip, as a column, not spot-checked.** Where the
figure is stated in a sentence rather than a table, say what it is a count *of* — a
figure with its predicate written down can be re-derived by a second reader; one without
can only be believed.

The stronger version, which is MES-85's and MES-88's to take: **the prose figures a
document states about an artefact are a checkable set.** `75 / 37`, `34 distinct
boundary ids`, `194 anchors`, `27 status assertions` — each is one query against the
committed JSON. A checker that extracts them is the only thing that makes "this document
was re-derived" distinguishable from "this document was re-read".

---

## S7-25 — Two artefacts counting "the same" units against different questions produce figures that look like a disagreement and are not one; reading one side's count as the other's member list is the actual defect

**Found on MES-82 (B2b)** while joining B2a's member register to A4's CG-side
reconciliation. Raised as the general form of D1 and D2 in
`docs/conformance/etcc-attribution.md` §4.1.

### What happened

`cg-reconciliation.md` §3 records CG2's discharge as **4 ET-CC units**
(`client_conformance_test.exs:184,209,217,232`) and CG7's bucket-1 constraints as
**9 ET-CC units** (`header_mirror_test.exs:113,120,133,156,168,194,205,222,231`).

In B2a's delivered register, **2 of that 4** and **2 of that 9** carry the label
`ET-CC`. `:209` and `:217` are `ET-OUT` on gate 2; seven of the nine are `ET-ADJ`.

### It is NOT a defect in A4, and saying so is half the entry

A4 built and guard-checked all seven CGs validly, and it ran **before** A2's gates
had been applied per unit — so it could not have used B2a's answer, and its own
answer is true of its own question.

The two artefacts are counting different things:

* **A4's discharge layer** counts units that **CLOSE THE GAP** — does this test
  establish the required behaviour?
* **B2a's ET-CC criterion** counts units that **ASSERT A WIRE ARTEFACT** (gate 2)
  — does this test's assertion address bytes a peer could observe?

A test can do the first without the second: `:217` asserts only that nothing is
logged, and `:113`/`:120` assert that a validator returns an error tuple. Real
discharge, no wire artefact.

### The actual defect, and where it would have landed

**Reading one artefact's count as the other's member list.** B2b's Job 2 would
have done exactly that had it taken A4's discharge rows as its member set instead
of joining from the member side: it would have attributed four members where two
exist, and inherited two labels that are not `ET-CC`.

The same shape produced **three** instances in one ticket — D1, D2, and AC4's
carrier-less tokens (`etcc-attribution.md` §5.2), which is not a separate residual
but this defect arriving a third time.

### Transferable form

**A count is a function of the question that produced it, so two artefacts'
counts of "the same" units are not comparable until both questions are stated.**
Before joining on another artefact's enumeration, ask what its rows are rows *of*.
Where the questions differ, join from your own side and report the difference —
never reconcile it by preferring a side, and never treat the other side's count as
a member list.

**The tell is that both figures survive scrutiny.** Neither "4" nor "2" is wrong,
so a reviewer checking either one in isolation finds it correct. Only the
predicate — *units that close the gap* versus *units that assert a wire artefact*
— separates them, and neither artefact had to state it to be right on its own
terms.

---

## S7-26 — A module-level attribute cannot answer a function-level question, and read as one it fails silently toward "shared"

**Found on MES-82 (B2b)** attributing a leg to each of B2a's 281 members.

### What happened

B2a's register carries a `boundary` per `ET-CC` row — the `lib/` encode/decode
boundary-direction the asserted bytes come from. The brief warned it is not a leg
attribution. Measured against the delivered attribution, a boundary-driven rule
(`MCP.Client` → client, `MCP.Server.*`/plug → server, anything else →
`none_determinable`) agrees on **163 of 281 — 58%**.

**All 118 disagreements have one shape**: the proxy answers `none_determinable`
where a per-**function** measurement resolves a definite leg. There is no
`client`→`server` or `server`→`client` cell in the table.

The reason is that a shared `MCP.Protocol.*` module is not shared function by
function:

| function | only `lib/` call site | leg |
| --- | --- | --- |
| `HeaderMirror.encode_value/1`, `headers_for/2` | `client.ex`, `streamable_http/client.ex` | client |
| `HeaderMirror.decode_value/1` | `plug.ex:906` | **server** |
| `SSE.encode_message/2` | `plug.ex` | server |
| `SSE.feed/2` (→ `decode_event/1`) | `streamable_http/client.ex:569` | **client** |
| `Discover.Result.to_map/1` / `from_map/1` | `dispatch.ex:150` / `client.ex:539` | server / **client** |
| `Extensions.from_meta/1` | **none on either leg** | neither |

`test/mcp/transport/sse_test.exs` is the clearest consequence: **19 members in one
file**, splitting 8 server / 10 client / 1 round-trip. A module-level read puts all
19 in the residue.

### Why it fails silently, and toward the reassuring answer

`none_determinable` is the *safe-looking* answer — it claims less. So a
module-level read never produces an obviously wrong client-versus-server flip; it
produces an over-large residue that reads as appropriate caution. **42% of the
member set would have been described as "no determinable leg" when the leg is
determinable and measurable.**

### Transferable form

**Before using an artefact's field to answer a question it was not built for,
state the granularity of each.** A field recorded per module answers per module; a
question about which implementation runs the code is answered per function, and
the gap between them is invisible in the field's own values.

And the check that catches it is cheap: **compute the agreement rate between the
proxy and the real reading, and look at the shape of the disagreements, not the
percentage.** A one-directional disagreement table is a granularity mismatch; a
scattered one is two unrelated instruments. Here the direction was uniform across
all 118, which is what identified the cause.

---

## S7-27 — A discriminator stated as a WORDING test does not separate the rows it is applied to, because a test name describes the scenario and not the implementation under test

**Found on MES-82 (B2b).** Shipped in round 1 as a wording test; **broken by a
reviewer in one mutation** (`26096` F1) and replaced by the PM's mechanical rule
(`26100`). Recorded in the form the rule ended in, with the failure that produced
it kept, because the failure is the transferable part.

### What was shipped, and how it broke

The leg rule was *"the implementation whose observable behaviour the assertion
constrains"*, and its hard case is a test that uses one leg's code as the **oracle**
for the other leg's behaviour:

    assert HeaderMirror.decode_value(headers["mcp-name"]) == hostile

`decode_value/1`'s only `lib/` call site is `plug.ex:906` — our **server** — so a
server-side mutation reddens `routing_headers_test.exs:239`, which is a claim about
our **client**. Round 1 separated the oracle case from the genuine round-trip case
on **whether the test's wording made the decode "the claim"**:

| | test name |
| --- | --- |
| `routing_headers_test.exs:199` | *"a non-ASCII tool name is encoded, **and decodes back to the body value**"* |
| `header_mirror_test.exs:360` | *"**every encoded value decodes back to exactly the body value**"* |

**The wording is the same.** Applied as stated, the rule put the client-leg member
on the round-trip member's side — so the discriminator did not discriminate, and
the answer it produced was right for reasons the rule did not state.

### The rule that replaced it, and it is per ASSERTION not per test

> A member has a **definite leg** iff it carries **at least one assertion that a
> mutation of that leg's code falsifies and no mutation of the other leg's code
> falsifies**. It is **`none_determinable`** iff no leg is definite.
>
> **Second limb.** A decode/parse applied to **our own encoder's output** is a
> **round-trip** — its assertion is falsified from either side, so it makes neither
> leg definite. A decode/parse applied to a **literal** is an **independent
> single-leg claim**. Whose output the decode consumes is checkable by reading the
> call, which is what keeps it mechanical.

The oracle case then resolves without any appeal to wording:
`routing_headers_test.exs:199` also carries
`assert String.starts_with?(header, "=?base64?")`, which no server mutation can
reach — one client-definite assertion, so `client`. `header_mirror_test.exs:360`
carries **only** the round-trip, so `none_determinable`. **The unit of the rule is
the assertion; a test is a bundle of them, and attributing the bundle was the
error underneath the wording.**

### Two things the mechanical rule does NOT settle, both found by applying it

**(a) A member can be definite for BOTH legs, and the rule has no word for it.**
`self_compatibility_test.exs:96` carries a client-definite assertion at `:100` and
a server-definite one at `:109`; `header_mirror_test.exs:425` encodes one literal
and decodes another. Resolved as `none_determinable` — a member whose claims span
both legs can match an OC check on either, which is what that value means for the
consumer — but it is a third outcome wearing the second one's name. **This is the
one row the new rule re-attributed**: 146/107/28 became 145/107/29.

**(b) The rule's negative half is not mutation-checkable, and cannot be made so.**
*"Some assertion this leg's mutation falsifies"* is positive and runnable. *"No
mutation of the other leg's code falsifies it"* quantifies over mutations nobody
has run — **a mutation proves LIVE, never DEAD** (S7-19). So the negative half is
discharged by a **reachability argument over `lib/` call sites**, and every claim
of a definite leg rests on an argument at exactly one point. Where a mutation
*can* settle it, it is because a mutation of the *other* leg reddened the **same
assertion**, proving that assertion is not single-leg — which runs in the
permitted direction.

### Transferable form

**A discriminator has to be tested against the rows it will be applied to, not
against the example that motivated it.** The round-1 rule was stated in front of
one pair and separated that pair; the first reviewer to fetch a second pair broke
it in one command. Before shipping a rule, apply it to the *hardest* rows on both
sides and print what it returns — and if a mechanical restatement and the words
disagree, that is not a licence to use the words, it is evidence the rule is not
yet stated.

**And name the unit.** "Which mutation reddens this test" and "what does this test
claim" diverge whenever a test bundles claims, which is most tests. A rule whose
unit is the test cannot express a member that claims one thing about each side.

**Direction still matters for the audit.** The oracle defect inflates the residue —
it moves members *into* `none_determinable` — so it fails toward the cautious
answer and will not announce itself. The both-legs case does the same. The
countermeasure is a bounded candidate sweep **with a positive control**: every
member whose unit names a leg-specific function or entry point from both legs,
adjudicated one at a time. B2b's first version of that sweep read the unit body
alone and found **1 of the 7** members it was known to have to find, because the
driving happened in a helper. **A candidate sweep that finds one of seven is what a
missing positive control looks like.**


## S7-28 — An address arrived at by counting from a citation instead of resolving it is wrong in the one way re-reading the citation cannot catch

**Found on MES-82 (B2b)**, against this ticket's own ratified plan.

### What happened

The plan (MES-82 comment `26087`) reported as an AC3 disagreement:

> **D5** — one fact, two addresses, and one of them is wrong at this tip.
> Declaration line is 35 (the register's key); the `cache_scope` assertion is at
> **48**, not 47.

Run literally at the delivered tip, that is false.
`test/mcp/protocol/messages/discover_test.exs:47` **is**
`assert result.cache_scope == "public"`, exactly as `match-relation.md` §6 cites
it. Line 48 is `assert result.server_info.name`.

So D5 is not a disagreement at all: A4 §3 cites the `test` declaration line (35,
the register's key under `etcc-row-key.md` §1) and §6 cites the assertion line
(47). Both addresses are correct for one test and differ only by the
decl-versus-assert convention.

### Why the error had the shape it did

The plan's figure was reached by *counting* — taking the cited line and reasoning
about what must be near it — rather than by resolving the address against the
tree. That is a variant of the move the PM's one standing instruction for this
ticket forbade (`26090`: read the test body, not a secondary copy), and it fails
in a way re-reading cannot catch: **re-reading the citation reproduces the
citation.** Only opening the file at that line falsifies it.

It also inverted a real relationship. The plan reported the *live* document as
wrong and the archive as right; the truth was the reverse of the error and neither
document was wrong at all.

### Transferable form

**Never state a line address you have not resolved at the tip you are delivering
from — including one you are asserting is WRONG.** S7-23 says a citation dies to a
later commit; this is its complement: *a citation you never opened was never alive
to begin with*, and a claim that someone else's address is stale needs the same
evidence as the address itself.

**The specific trap is a near-miss.** An address off by one or two lands inside
the same test and looks plausible against every summary of it. The only check that
discriminates is printing the line — which costs one command, and which this entry
exists because nobody ran until delivery.

---

## S7-29 — A remedy is an instrument, and an instrument has a reach nobody states when they build it: the S7-24 column re-derives from the ARTEFACT, so it cannot reach a figure asserted about another SECTION

**Found on MES-82 (B2b), correction round 1.** Not an instance of S7-24 — **a
bound on S7-24's own remedy**. Raised by the reviewer (`26097`), adopted by the PM
(`26101`), and the recurrence is itself the finding.

### What happened

S7-24 says prose figures accumulate the previous round's numbers "in exactly the
places a generator cannot reach". B2b's remedy was a **column**: after the last
change, re-derive **every** prose figure from the committed artefact. It ran, and
three figures did not survive it — they were fixed in `6ae97d5` and reported as
the column's result.

The reviewer then found **two more**, both of which the column had passed over:

* `etcc-attribution.md:537` (§7 bullet 3): *"The **five** unmatched checks in §3.4"*,
  where §3.4 enumerates **four** and closes `11 matched + 4 unmatched = 15`. The
  same commit that changed "five" → "four" in §3.4 left §7(3).
* `etcc-attribution.md:354` (§4.1): *"§5's **three** carrier-less tokens"*, where
  §5.2 is headed *"**Two** tokens have no carrier"*. The 4/3 → 5/2 overturn was
  applied in §5 and not in §4.1.

**The column could not have caught either, by construction.** It re-derives each
figure *from the artefact*, so it reaches every figure with an artefact
counterpart — and both survivors are figures asserted about **another section of
the same prose**, which has none. There is no `unmatched_checks` field to compare
"five" against; the referent is §3.4's own sentence.

### The instrument that does reach them

An **internal-consistency check**: every figure stated *about another section*,
re-read against that section. Mechanically: find each line that names a `§` other
than its own and carries a figure, then resolve the figure against the named
section. On this file that is ~50 lines and one pass, and it earned its keep
immediately: §4's D2 row said *"CG7's member set is **35**"* after §4.5 had moved
it to 31. **That one was made stale by correction round 1's own edit rather than
surviving round 1** — which is the point, not a caveat: the same edit that fixed
the count elsewhere created the mismatch here, and the artefact column would have
passed it too, because D2's figure is a claim about a count stated *elsewhere in
the same file*.

The two checks are complementary and neither subsumes the other:

| check | reaches | blind to |
| --- | --- | --- |
| artefact column (S7-24's remedy) | every figure with a counterpart in the built artefact | figures whose referent is other prose |
| internal-consistency read (this entry) | figures asserted about another section | figures asserted about the artefact but never restated in prose |

### Transferable form

**When you add a remedy, state its reach in the same breath — because the reach is
what the next reviewer will find.** A remedy is built while looking at the cases
that motivated it, so it inherits their shape; the cases it cannot see are exactly
the ones nobody had in hand. Write the bound down at the moment the remedy is
added, when the shape of what it consults is still in view.

**And this is a recurring shape, not a one-off.** S7-19 bounds S7-16's remedy (a
narrow mutation carries the same directional bias as the grep it replaced); F6 on
B2a bounds L2's; this bounds S7-24's. **Three instances in two tickets of the same
second-order defect.** So the practice generalises: after adding an instrument,
ask *what class of case is invisible to this*, and record the answer beside the
instrument rather than waiting for a reviewer to supply it.

---

## S7-30 — A per-item field carrying one shared string reads as per-item evidence and is a single claim, and it hides the items the claim does not fit

**Found on MES-82 (B2b), correction round 1**, from review finding F2 (`26096`).

### What happened

The enriched register carries a `cg_basis` per member — the reason that member
corresponds to the CG it is assigned. **13 of CG7's 35 members carried this
verbatim, character for character:**

> *"The client-side inputSchema/annotation cache and the SEP-2243 tool-exclusion
> rule; this machinery exists solely to drive CG7's `Mcp-Param-*` mirroring, so its
> claims are CG7's."*

Two defects, and they compound:

**(1) The basis is PURPOSIVE.** It argues from what the machinery is *for*, not
from what the member asserts. The brief establishes correspondence against the
check's `description` — never a title, and by the same reasoning never a purpose.
It is the false-positive shape with a different label on it.

**(2) One string thirteen times cannot be audited per row.** The field's *shape*
promises a per-item reason; its *content* is one reason. So a reviewer checking row
`n` learns nothing about row `n+1`, and the 13 rows are only as good as the single
weakest of them.

Checked per row against the members' own assertions, **8 assert `Mcp-Param-*`
mirroring directly**, one asserts the SEP-2243 exclusion, and **4 assert neither**
— three are the client's `-32020` recovery policy and one is malformed-`tools/list`
robustness. Checked against A4's CG7 **gap** statement (*mirror designated
parameters / encode unsafe values / exclude invalidly-annotated tools*), none of
the three limbs reaches those four. **They left, and CG7 went 35 → 31.**

### The discriminator was in the file the whole time

`client_tool_schemas_test.exs:399` and `:415` sit in the **same `describe`** and
make the same kind of claim, yet `:415` asserts
`headers_for_call(client, transport, "t") == [{"mcp-param-region", "us-west1"}]`
and `:399` asserts nothing about a header. A per-row basis surfaces that in one
line; a shared basis buries it. **The evidence that separated the rows was
available to whoever wrote the shared string** — what was missing was the
obligation to write it down once per row.

### Transferable form

**A field whose name is singular but whose scope is a group is a count wearing an
enumeration's clothes** (epic ruling 4). Before writing the same justification into
n rows, ask whether it is *true of each* or merely *true of the set* — and if the
honest answer is the set, put it in the set's own record and give each row the
sentence that is about that row.

**The cheap detector: group the field by value and look at the group sizes.** A
per-item reason field with a group of 13 identical values is either a genuine
regularity worth naming as one rule, or 13 rows nobody looked at individually.
Both are worth knowing, and the query costs one line.

---

## S7-31 — A selection mechanism whose granularity option silently REWRITES the identifier it selects on, so narrowing the selection re-keys the rows

**Found on MES-84 (B4), at planning**, while establishing how the 6 doctest
members could be tagged. Ruled by the PM at `26115` / `26117` (E1).

### The mechanism

`ExUnit.DocTest` numbers generated examples with a **module-wide counter over the
selected set**. `doctest Mod` and `doctest Mod, only: [f: 1]` therefore produce
*different names for the same example*:

```
doctest Mod                       doctest Mod, only: [b?: 1]
  ...a/1 (1)  ...a/1 (2)
  ...b?/1 (3) ...b?/1 (4)   -->     ...b?/1 (1)  ...b?/1 (2)
  ...c/1 (5)
```

`only:` is documented as a way to *narrow* a selection. It is also, undocumented
and unannounced, a way to **renumber** it. Nothing warns, nothing fails, and both
runs are green.

That would be a curiosity except that the number is inside the row key
(`docs/conformance/etcc-row-key.md` §1), and the row key is the **authored join
key** of `conformance/data/etcc-decisions.json`. Narrowing one directive from 9
examples to 2 would have re-keyed 9 entries of a *merged* deliverable and forced
a rebuild of the register, the attribution and the rows artefact — to buy a source
marker on 2 tests.

### Why it was worth a ruling rather than a workaround

The PM's HAZARD 1 verdict was "resolvable, split it", reached before anyone had
measured what `only:` does to the index. The corrected verdict is **resolvable in
principle, and we decline the resolution because it costs more than the gap**. The
distinction matters: an unmeasured "resolvable" invites the next person to do it.

### Transferable form

**Before using a mechanism's narrowing option, ask what the option does to the
IDENTIFIERS of the things it keeps.** A filter that only removes rows is safe; a
filter that renumbers what it keeps is a rename, and a rename of a join key is a
migration. The cheap detector is one run of each form side by side with the names
printed — which is `conformance/controls/etcc_tags_controls.exs doctest_options`,
committed for exactly that reason.

---

## S7-32 — A source marker cannot be added without moving every address below it, and the blast radius is not confined to the artefact that predicted it

**Found on MES-84 (B4), at planning and then re-measured at the delivered tip.**
Ruled by the PM at `26116` (E2, option (ii): re-sync at the end of the ticket).

### The mechanism

Adding `@tag :etcc` above a test inserts a line. Every `file:line` address below
it in that file is now off by one, cumulatively. 265 insertions over 30 files.

**Row keys are unaffected** — a key carries module and name and never a line —
which is what makes the repair mechanical rather than a re-decision. Only the
human-readable addresses move.

### The part that was under-measured, and it is the transferable half

Planning measured the authored citations in **one** file's one field:
`conformance/data/etcc-decisions.json` `evidence`, 1108 citations of which 393
pointed into a file about to be tagged. That number was reproduced by the PM and
ruled on. At the delivered tip, scanning **every tracked file** found **1319
citations into a tagged file, across 17 files** — the boundaries file, five
`docs/conformance/*.md` documents, three sprint issue registers and two test
files, none of which the estimate had looked at.

The estimate was not wrong about what it measured. It was scoped to the artefact
the ticket was *thinking* about, and an address shift does not respect that scope.

### The second grammar problem

A naive `\.exs?:(\d+)` scan also **under-counts**, because citations are written
in more than one grammar:

```
header_mirror_test.exs:113,120,133,156,168,194,205,222,231     a LIST
discover_test.exs:31-32                                        a RANGE
```

A rewriter matching only the first number produces a **half-corrected citation**,
which is worse than an uncorrected one: it looks repaired. The grammar has to be
`:\d+((,|-|/:)\d+)*` and every number in it remapped.

### The invariant that makes the repair safe

> **the bytes at the new line equal the bytes that were at the old line before
> tagging.**

Checked mechanically for every citation, not for the subset expected to move.
Result at the delivered tip: **738 moved, 138 unmoved, 2 escalated** over the
files rewritten. The 2 are the same address twice — the one line whose *content*
this ticket deliberately rewrote — so no rewrite could satisfy the invariant and
none was attempted.

### Transferable form

**A mechanical repair needs a mechanical acceptance test, and the test must run
over the whole population rather than the part you expect to move.** A citation
predicted not to move is a prediction until the check runs. And the scan that
finds the population must be written against the *grammars in use*, established by
looking, not against the one grammar you had in mind.

---

## S7-33 — Declining a resolution leaves a residual, and a residual that no control watches is the shape the ticket existed to prevent

**Found on MES-84 (B4).** The PM's condition on the E1 ruling (`26115`).

### The residual, stated as a cost

`test/mcp/protocol/extensions_test.exs` carries a `doctest` directive generating
9 examples, 2 of which are ET-CC members. Since the directive is left unsplit
(S7-31), those 2 members carry **no marker in the source at all**. A reader of
that file sees nothing on them. They are selected by an exact test-name filter
derived from the register.

**2 of 281 members, and the cost is legibility rather than coverage.**

### Why it is not a special case

The two keys are in `expected_keys/1` exactly like every other member, so
`mix test.etcc` refuses if the name filter ever stops selecting them, in the same
comparison and with the same message. There is no branch that treats them
differently and therefore no branch that could stop watching them.

The name filter is exact only because **no two tests in this tree share a name** —
a property of the tree, not a guarantee of the mechanism. So it is asserted as its
own check (`name_collisions/1`), and a future collision goes red rather than
silently widening the selection.

### Transferable form

**When a ruling declines a resolution, the residual has to be named AND guarded.**
Named, because a declined resolution and an unnoticed gap read identically a
sprint later. Guarded, because the argument for declining is always "the cheaper
mechanism covers it" — and that argument is only true while something checks that
the cheaper mechanism still does.

---

## S7-34 — An unknown option to `doctest` is ignored in silence, so a misspelling is a mark that was never applied over a suite that stays green

**Found on MES-84 (B4), AC4, measured at CODE_CREATOR's seat** rather than taken
from the brief that predicted it.

### The mechanism

`ExUnit.DocTest`'s documented option vocabulary is `:only`, `:except`, `:import`,
`:tags`, `:inspect_opts`. An option outside it produces **no error, no warning,
exit 0, and no tag**:

```
doctest Subject, only: [c: 1], tagz: [:etcc]     # tagz, not tags
  MES84.DoctestTypoFixture/doctest ...c/1 (1)    etcc=nil
```

Compare the correctly spelled form, which does place the tag on **every** example
of the selected `{function, arity}`:

```
doctest Subject, only: [b?: 1], tags: [:etcc]
  MES84.DoctestOnlyFixture/doctest ...b?/1 (1)   etcc=true
  MES84.DoctestOnlyFixture/doctest ...b?/1 (2)   etcc=true
```

### Why this is a procedure defect and not a trivium

The whole tagging mechanism rests on the mark actually reaching the test. A
misspelling here is indistinguishable, from the suite's output, from a correctly
applied mark on a test that happens to pass. It cannot be caught where it is made;
it has to be caught somewhere that compares **what was intended** against **what
ExUnit actually reports**, which is what `mix conformance.etcc_tags --check` and
the runtime guard do.

### Transferable form

**A configuration surface that ignores what it does not recognise converts every
typo into a silent no-op**, and a no-op in a marking mechanism is invisible by
construction. The detector is a committed negative fixture — one deliberately
misspelled option whose *absence of effect* is asserted — because a mechanism
nobody has watched fail is a mechanism nobody has watched.

---

## S7-35 — A selection mechanism's green means "everything selected passed", never "everything intended was selected", and no exit status can tell them apart

**Found on MES-84 (B4).** The brief's HAZARD 4 stated the risk one notch too
strongly; the correction is the useful part.

### What the brief said, and what is actually true

HAZARD 4 said a zero-selection run "would exit 0 having run zero tests, and read
as success". Measured: it does not.

```
$ mix test --only no_such_tag --seed 0
All tests have been excluded.
0 tests, 0 failures (41 excluded)
The --only option was given to "mix test" but no test was executed
rc=1
```

**ExUnit already refuses a totally vacuous `--only` run and names the cause.** The
zero case was never ours to discover.

### The case that IS ours, and it is the likelier one

**Partial selection exits 0.** 1 of 281 tagged and passing prints a green summary;
so does 280 of 281, and so does 281 of 281. No exit status can separate them,
because all three are truthfully "everything selected passed". Demonstrated: with
one `@tag :etcc` line removed, `mix test` ran 280 tests and passed all 280 — the
run is green and the claim set is short by one.

So the check cannot be on the status. It has to be on the **captured key set**,
compared to the register in both directions.

### What makes that comparison possible at all

MES-83's rule that **an excluded test still gets a row, carrying its exclusion
reason**. Without it, "selected" would not be readable off the artefact and
"absent from the artefact" would collapse three different things into one silence.
A detectable vacuity is a property somebody had to build.

### Transferable form

**Whenever a tool reports on a subset it chose, the report must state the subset,
not just the verdict over it.** The question "did everything pass?" is answerable
by a status; the question "was everything asked?" is not, and it is the one that
goes wrong quietly.

---

## S7-36 — Runtime units and source declarations are two different populations, and the distinction has to be restated at every use rather than established once

**Found on MES-84 (B4), at planning**, in the PM's own dispatch. Accepted and
reproduced by the PM at `26115` (E3).

### What happened

Sprint 7 spent most of B1–B3 separating **runtime tests** from **source
declarations** — S6-6 is that distinction, and the row key exists because of it.
One paragraph after stating the rule that depends on it, MES-84's dispatch said:

> "573 of the 579 declarations produce exactly one unit each"

Both figures are wrong in the same way. **579 is the count of runtime units.** The
declarations are **539**, of which 533 produce exactly one unit and 6 produce 46
between them; 533 + 46 = 579. 573 is not a count of anything.

The ruling the sentence supports was unaffected — a `@tag` on an individual test
reaches exactly one runtime unit, and that is true of 533 declarations.

### The mechanism

The two populations are near enough in size (539 vs 579) that a wrong one reads as
plausible, and the arithmetic that would catch it (`single + units-in-multi =
total`) is only obvious once you already have both figures. A conflation of two
close numbers survives review in a way that an order-of-magnitude error does not.

### Transferable form

**A distinction established at the start of a sprint does not stay established.**
It has to be re-stated at each use, in the sentence that uses it — "539
declarations producing 579 runtime units", never "the 579". And any figure about
either population should be published with the bridging arithmetic beside it, so
that the reader can tell which population is being counted without knowing which
one the author meant.

---

## S7-37 — Four merged artefacts now disagree with the tree by a known, enumerable amount, and that is a decision rather than a drift

**Found on MES-76 (F1–F4), 2026-08-24, by CODE_CREATOR at planning; ruled by the
PM at `26128` (Q3).** Recorded here as the condition of that ruling.

### The arithmetic, stated so a later reader can act on it

`docs/conformance/etcc-exunit-rows.json` records **1007** runtime units, captured
at a named tip. Gate 5 at `18df3a6` reported `13 doctests, 994 tests` = **1007**,
so the census matched the tree exactly up to the moment this ticket landed.
MES-76 adds **27** tests and the delivered tip reports `13 doctests, 1021 tests`
= **1034**. The difference is **+27**, and it is precisely the tests this ticket
added, enumerated:

| deliverable | tests | file |
| --- | --- | --- |
| D4 — token injectivity | 5 | `test/conformance/match_key_test.exs` |
| D5 — `bucket/1` exhaustiveness | 7 | same |
| D2+D3 — polarity and preconditions | 8 | same |
| D1 — reverse lookup | 7 | same |
| **total** | **27** | |

All 27 are untagged, so the ET-CC selection is untouched: `mix test.etcc` reports
**selected 281, expected 281, missing 0, stray 0** before and after.

### Why no re-capture, and what that costs

The census is a **records-then** document, not a **describes-now** one: it carries
`run.tip`, `rows_md5`, `tree_clean` and `complete`, and claims to be the tree *at
a named tip* rather than the tree now. Re-capturing would move the register's
inputs on a ticket that adds no ET-CC member and changes no membership — the
in-scope 579 and ET-CC 281 cannot move whatever the out-of-scope count does.

What it costs is that four merged artefacts now disagree with the live tree by
27. **That is the whole reason this entry exists.** "Four artefacts disagree with
the tree by N, and here are the N" is a fact a later reader can act on; a silent
drift is not.

### The mechanism

A committed census is an instrument that **changes its own denominator by
existing** — any ticket that adds a test moves the population the census
measured. So the question "should the census be re-captured?" has no per-ticket
answer: answering it inside a ticket either blocks unrelated work or absorbs the
decision silently. It belongs at a **cadence boundary**, scoped and scheduled
like any other work — the same rule the end-of-sprint procedure already applies
to dependency advisories.

### Transferable form

**When an artefact is a snapshot at a named tip, a ticket that invalidates the
snapshot should publish the delta, not repair the snapshot.** Repairing it inside
the ticket makes the artefact's provenance depend on whatever work happened to
notice, which is exactly the property a content-hashed snapshot exists to avoid.
Publish the arithmetic; let the cadence decide the re-capture.

---

## S7-38 — A test asserting a uniform reason over a population is a stronger claim than the fix supports, and it fails toward the author's framing

**Found on MES-76 (D4), 2026-08-24, by CODE_CREATOR — by running the test, not by
reading it.**

### What happened

D4 makes the `oc:` token injective: `oc:…/Name#` decoded to a map byte-identical
to the one `oc:…/Name` produces, so two token strings named one value while
`render/1` could emit only one of them. The fix refuses the explicitly-empty
discriminator.

The obvious test is "for every one of the 175 manifest rows, appending `#` is
refused as `:empty_discriminator`". It went **red on the first run**. Appending
`#` to a row that *already carries* a discriminator produces a **three**-segment
split, refused as `:multiple_discriminators` — and refused that way **before the
fix as well**.

So the honest figure is that D4 moves **172 of 175** rows from accepted to
refused, not 175. The three that did not move were never the defect.

### The mechanism

Two ways to write that test both pass, and both mislead:

* assert one reason for all 175 — **false**, and it fails loudly, which is the
  good case;
* assert "refused, somehow" — **true, and it hides the partition**. It would have
  passed, and the close-out would have reported 175.

The second is the dangerous one because the weaker assertion is the *easier* one
to write and it reads as more robust. A test that accepts any refusal cannot
distinguish "the fix caught this row" from "something else already did", so it
silently credits the fix with rows it never touched.

### Transferable form

**When a fix is claimed over a population, assert the reason per item and compare
the frequencies as a partition summing to the population** — here
`%{empty_discriminator: 172, multiple_discriminators: 3}`, sum 175. A single
reason asserted over a whole population is a claim about uniformity that the fix
usually does not make; "refused, somehow" is a claim so weak it cannot be wrong.
The partition is the only form that both passes and reports the truth.

---

## S7-39 — A mutation that the existing suite already catches is not evidence for a new test, and the temptation is to report the first mutation that goes red

**Found on MES-76 (D5), 2026-08-24, by CODE_CREATOR.**

### What happened

D5 adds an exhaustiveness assertion over `bucket/1`'s 2×2×3 domain, guarding
MES-68's own lesson: an implicit case in a total-looking table. To show it works,
the natural mutation is to **reintroduce the original defect** — delete the
`{:red, :green, :full}` clause so that cell falls through to `:undecidable`.

It went red: 3 failures. Reported alone, that reads as proof the new tests work.
It is not. **One of the three was a pre-existing test** — MES-68 added a test for
exactly that cell when it fixed it. The mutation is caught with or without the
new work, so it discriminates nothing.

The mutation that *does* discriminate is vocabulary drift: extend `@edge_shapes`
to a fourth shape and leave the bucket table behind. That gives **5 red, all five
among the new tests, zero pre-existing tests red** — because the hand-written
examples are written against today's three shapes and cannot see a fourth.

### The mechanism

A mutation is chosen to demonstrate a *specific* test, but it is scored against
the *whole suite*. When the defect being re-injected is one a previous ticket
already fixed **and tested**, the old test fires too, and a red count alone
cannot separate the two contributions. The failure mode is not a wrong
measurement — it is a correct measurement of the wrong thing, reported as
evidence for a claim it does not support.

### Transferable form

**Score a mutation by *which* tests reddened, never by how many** — and state
whether any of them pre-date the work. A mutation whose casualties are all
pre-existing tests is evidence about the *old* suite. The discriminating mutation
for a generalising test is one that breaks the *generalisation* (extend the
domain, drift the vocabulary), not one that re-breaks the specific case the
generalisation was derived from.

---

## S7-40 — Gate 1's blindness to `conformance/controls/` is worth re-measuring per ticket, because reading `.formatter.exs` answers a different question than running the gate

**Found on MES-76, 2026-08-24, by CODE_CREATOR.** Confirms S7-11 by mutation
rather than inheriting it.

### What happened

The brief said to format any new `conformance/controls/` file explicitly because
gate 1 does not see it (S7-11). Rather than repeat that, it was tested: a
deliberately misformatted line (`x   =  1`) was appended to the new control and
`mix format --check-formatted` was run.

**Gate 1 exited 0.** The claim holds, and the explicit format was necessary.

### The mechanism

Reading `.formatter.exs` shows `inputs:` scoped to `conformance/lib/**` and
invites the inference that `conformance/controls/` is unreached. That inference is
*usually* right, but it is an inference about a config file, not a measurement of
the gate: a `.formatter.exs` can be overridden, a subproject formatter can widen
the set, and a path can be reached by more than one pattern. The distinction
matters because the two failure directions differ in cost — believing the gate is
blind when it sees costs a redundant `mix format`; believing it sees when it is
blind ships an unformatted file that no gate will ever flag.

### Transferable form

**A claim of the form "gate X does not reach path P" is falsifiable in one
command: break P deliberately and run gate X.** Prefer that to reading the gate's
configuration, and re-run it per ticket rather than citing an earlier ticket's
finding — the config is exactly the kind of file another ticket can widen without
anyone re-testing the claims that rested on it.

---

## S7-41 — An identifier pattern that cannot spell the language's own naming convention under-counts silently, and a count that can only be short reads as ABSENCE

**Found at the PM seat, 2026-08-24, while preparing MES-84's dispatch — one step from
reporting that MES-81's just-merged register had lost four rows.**

Censusing the runtime doctests in `docs/conformance/etcc-register.json`:

```python
re.compile(r'^doctest (\S+)\.(\w+/\d+) \((\d+)\)$')
```

returned **9**, where `etcc-exunit-rows.json` and `mix test` both say **13**.

### The mechanism

`\w+` is `[A-Za-z0-9_]`. It does not match `?` or `!`, so
`Extensions.reserved_prefix?/1` and `Extensions.valid_identifier?/1` — four rows between
them — could never match. Elixir *conventionally* ends predicates in `?` and raising
variants in `!`, so in an Elixir tree this is not an edge case, it is a naming convention
the pattern is structurally blind to. The correct class is `[A-Za-z_][A-Za-z0-9_?!]*`.

### Why it belongs with the sprint's other directional failures

A name pattern can only ever **under**-count. So it can only ever return "fewer than you
expected", which reads as *absence* — and absence was the alarming answer here, exactly as
it was the reassuring one when S7-16's grep asked whether code was dead. Same defect,
opposite-signed conclusion. **A check that can only fail in one direction tells you about
the check, not about the subject.**

### Transferable form

For "how many X are in this artefact": (1) do not key on a name pattern when the artefact
carries a **field** for it — the register has `test_type` (`test` / `doctest`), which is
mechanical and cannot mis-lex; and (2) settle totality by **set comparison against the
source population**, not by a pattern count. `{register keys} == {artefact keys}` returned
992 = 992, zero either way, and that — not the corrected regex — is what actually proved
the register intact.

---

## S7-42 — "Records then" and "describes now" are two kinds of document, and the same stale address demands opposite remedies in each

**Ruled at the PM seat on MES-84 (comment `26121`) and applied again on MES-76 (`26128`)
within four hours — the second application is what makes it a rule rather than an answer.**

MES-84's tagging moved line addresses that other files cite. CODE_CREATOR asked whether the
32 citations in `sprint_4_issues.md`, `sprint_6_issues.md` and `sprint_7_issues.md` should be
re-addressed along with the live conformance artefacts. MES-76 then asked the structurally
identical question about `etcc-exunit-rows.json`, whose 1007-row census the ticket's new
tests would leave 27 short of the tree.

### The mechanism

A **live artefact** asserts something about the tree as it is now. A stale address in one is
simply wrong, and repairing it restores the claim.

A **historical record** asserts that on a date, at a tip, someone measured something at an
address. Rewriting that address to today's line does not repair the record — it *falsifies*
it. The finding did not happen at today's line, and a reader who follows the new address and
reads today's bytes concludes something that was never measured.

`etcc-exunit-rows.json` sits in the second class despite looking like the first, and it says
so itself: `run.tip`, `rows_md5`, `tree_clean`, `complete`. It does not claim to be the tree;
it claims to be the tree **at a named tip**. Confirmed by measurement rather than by reading:
no control asserts totality over the live tree — `etcc_register_controls.exs`'s `totality`
recomputes from the committed register's own rows and never looks at the working tree.

### Transferable form

Before repairing a stale address, ask which class the document is in. **The discriminator is
whether it claims to describe now or to record then** — and a document that carries its own
tip and hash has already answered. Where the answer is "records then", the remedy is a
sentence saying the addresses are as-of, never a rewrite.

---

## S7-43 — An invariant is a proxy for the question it was built for, and it answers a DIFFERENT event with the wrong sign

**Found on MES-84, escalation 1 — the invariant fired, and the correct response was to look
rather than to act.**

MES-84's re-address held every rewrite to: *the bytes at the new line equal the bytes that
were at the old line before tagging*. Two citations to `header_mirror_test.exs:31` failed it.
CODE_CREATOR escalated instead of rewriting. The line number had not moved; the **content**
had, because the ticket deliberately edited that line from `doctest MCP.Protocol.HeaderMirror`
to `doctest MCP.Protocol.HeaderMirror, tags: [:etcc]`.

Adjudicated by opening both citations rather than reasoning about them: neither quotes line
31's bytes, and both name the *declaration* and what it generates — "(×4 doctests)". The
declaration is still at `:31` and still generates the same four. Nothing to repair.

### The mechanism

Byte-equality is a proxy for **"does this citation still point at the thing it named?"** It
answers correctly for the event it was designed against — an insertion above pushing the line
out from under a citation — and incorrectly for a different event: a deliberate edit *to* the
cited line. Two events, one signal, opposite right answers.

### Transferable form

Keep the invariant; it failed **safe**, which is the direction worth having. What it needs is
the accompanying rule: **a red from a proxy means "look", not "act"**. A remedy wired directly
to a proxy's red would have silently rewritten two correct citations here.

---

## S7-44 — A deliverable held in a seat's context, or in an uncommitted worktree, is lost when the engine dies — and the tidy-up reflex destroys what survived

**Four `rc=1` engine deaths on 2026-08-24, against zero in the entire prior dispatch log.**

Two shapes. Two deaths were mid-work (15 and 42 minutes in). Two were at **startup** — ~3¼
minutes in, having produced nothing at all: no commit, no comment, no worktree — and both
followed a Jira thread that had grown long.

### What it cost, and what saved it

The 42-minute death left **865 uncommitted insertions across 5 files** in an orphaned
worktree. The first recovery of the day had removed a previous orphan without looking,
because that one happened to be clean. **The same reflex would have destroyed the round.**
`git status --porcelain` before removal is what made the difference.

### The recovery sequence, validated four times

Confirm `rc != 0` with no comment posted and the ticket still assigned → **inspect the
worktree and preserve any uncommitted work before removing it** → unassign → wait ~10s for
the loop to clear `/tmp/seat-MES-<SEAT>.last` → re-assign. Re-assigning before the marker
clears is a no-op: `seat_loop.sh` edge-triggers on the ticket key.

For the startup shape, a re-dispatch opening **"DO NOT RE-READ THE COMMENT THREAD"**, naming
only the one or two comments that matter and compressing every ruling inline, recovered both
occurrences. *Correlational, not proven* — recorded as a working hypothesis.

### Transferable form

Ask the executing seat to **commit after each scope item and post close-out parts as they
land**. A commit made and a part posted both survive an engine death; a deliverable held in
context does not. Six partial reports beat one complete one that never arrives — and on
MES-84 and MES-76 both, this is exactly what happened.

---

## S7-45 — Having the fact recorded is not the same as applying it, and the failure mode looks identical to not knowing

**Found at the PM seat on MES-84, 2026-08-24.**

The dispatch for MES-84 ruled HAZARD 1 "resolvable — split `extensions_test.exs:35` with
`only:`". CODE_CREATOR's plan then measured that `only:` **renumbers the doctest example
index**, that the index is inside the row key, and that the key is the authored join key of
an already-merged deliverable. The ruling was withdrawn and the split declined.

The renumbering was already written down. It had been measured on an earlier ticket and
recorded, in those words, in the PM seat's own notes — *"`only:`/`except:` RENUMBER the (n)
that is part of the test name"*. It was not consulted before the ruling was written.

### The mechanism

A prior finding protects nothing unless something forces a lookup at the moment of decision.
A ruling written from a fresh reading of the code will re-derive whatever the code shows and
**silently omit whatever only the notes know** — and the output is indistinguishable from the
output of never having found it. Nothing in the ruling looked uncertain.

### Transferable form

**Before ruling on a mechanism, search the register for that mechanism by name** — the cost is
one grep, the failure mode is a correction round. And where a finding constrains a *decision*
rather than a line of code, say so in the entry, so a later reader knows it is meant to be
consulted rather than merely recorded.

---

## S7-46 — Prose can contradict EXECUTABLE CODE that derives the same number from the same file, and the code being right is what makes the prose invisible

**Found on MES-82 as F14, and distinct from S7-24.**

S7-24 is prose-vs-artefact: a delivered document keeps the previous round's numbers because
no generator reaches prose. S7-46 is narrower and worse. Here the document contains **a
control that derives the figure from the artefact**, and prose elsewhere in the same document
states a different figure for the same population. The control is green, because the control
does not read the prose.

### The mechanism

Adding executable verification to a document raises confidence across the *whole* document,
including the parts it does not reach. A reader who has seen the control pass has no
prompting to check a sentence — the presence of a green instrument is read as coverage of the
file rather than coverage of the instrument's own inputs. The figure and its check live in one
file and never meet.

### Transferable form

**A control's reach is its inputs, not its file.** When a document carries both derived and
asserted figures, the derived ones need no check and the asserted ones need every check — so
enumerate the asserted figures explicitly and re-resolve each at the delivered tip. "The
controls are green" is a statement about the controls.

---

# End-of-sprint dependency sweep — Sprint 7

**Run at the PM seat, 2026-08-24, at the sprint's final tip `c807733` /
`2.0.0-dev.30`, tree clean.** Recorded whether clean or not, because "checked, and
zero" and "never asked" read identically when only the answer is printed.

**The per-ticket gate-6 applicability rule does not apply here.** That rule is about
tickets; this is a cadence sweep and it runs every sprint boundary regardless of what
changed. Sprint 7 changed no dependency — no ticket touched `mix.exs` or `mix.lock` —
and the sweep ran anyway, which is precisely its purpose: to catch advisories published
against dependencies nobody touched.

```
hex version        Hex v2.5.1        meets the >= 2.5.1 gate-6 floor (checked, not assumed)

GATE 6a  baseline-lock sentinel at d697093
         advisory ids present   22 of 22        PASS
         validates local advisory data for bandit, hpax, mint, plug, req

GATE 6b  mix hex.audit on this project at c807733
         "No retired or security advisory packages found"      rc=0

RESULT   CLEAN.  Zero advisories, zero retired packages.
         No Jira ticket raised, because there was nothing to raise.
```

**What this result does and does not mean.** 6a passing is what makes 6b's green worth
reading: a bare `mix hex.audit` exits 0 over an outstanding advisory when the local
registry cache is incomplete, and 6a is the control that rules that out. But 6a narrows
limitation 1 to the five advisory-bearing packages — **21 of the 26 locked packages
remain unvalidated**, including `finch` and `thousand_island`, which are runtime deps on
this SDK's transport path. And neither half detects **staleness**: a complete-but-old
registry passes both while missing every advisory published since the snapshot. The
compensating control for both residuals is the live whole-tree OSV cross-check, owned by
MES-19 at release.

**PA-9 remains open and is unchanged by this sweep.** The live question is whether the
OSV cross-check should also run at the sprint boundary — where network dependence costs
nothing, since no work is in flight and no merge is blocked. Still the PO's call.

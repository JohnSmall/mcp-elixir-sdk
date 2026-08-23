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

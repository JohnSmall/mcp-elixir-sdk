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
`grep -rl 'FLIP_STATUS\|FABRICATE_ROW' /tmp` returns nothing. What survived is
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

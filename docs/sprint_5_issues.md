# Sprint 5 — procedure defects

Procedure defects found while working Sprint 5 (epic MES-55): things wrong with
**how we work** — the gate set, the briefs, the tooling contract.

Ticket substance does not go here. Findings about the MCP SDK itself, about
conformance results, or about a specific ticket's deliverable belong in comments
on that ticket. This file is for defects a *future* sprint would otherwise hit
again.

Each entry states the **mechanism**, because the mechanism is the transferable
part. "Gate 3 missed a file" is not reusable; "credo's bundled default carries a
hardcoded `files.included` and never reads `elixirc_paths`" is.

---

## S5-1 — Gate 3 (`mix credo`) was blind to `conformance/`, and `elixirc_paths` could not fix it

**Found:** MES-51, 2026-08-20.
**Status:** fixed for `conformance/lib/` by a root `.credo.exs` (MES-51, ratified as E1).
**Still open:** the rest of `conformance/` — see the residual below.

### The defect

MES-46 established that gates 1 (`mix format --check-formatted`) and 2
(`mix compile --warnings-as-errors`) are blind to the `conformance/` directory,
and the MES-51 brief repeated that pair. **Gate 3 is blind too, and the brief did
not say so.** Anything placed in `conformance/` was unchecked by three of the six
DoD gates, not two.

Worse, the obvious fix does not work. Gates 1, 2 and 4 are all reachable from
project configuration that already exists:

| Gate | How it reaches `conformance/lib/` |
|------|-----------------------------------|
| 1 `mix format --check-formatted` | add the glob to `.formatter.exs` `inputs` |
| 2 `mix compile --warnings-as-errors` | add the path to `elixirc_paths/1` in `mix.exs` |
| 3 `mix credo` | **neither of the above works — needs a `.credo.exs`** |
| 4 `mix dialyzer` | follows from gate 2 (the modules become app beams) |

### The mechanism

With no `.credo.exs` present, credo loads its **bundled default config**, whose
`files.included` is a hardcoded list:

```
["lib/**/*.{ex,exs}", "src/", "test/**/*.{ex,exs}", "web/",
 "apps/*/lib/", "apps/*/src/", "apps/*/test/", "apps/*/web/"]
```

Credo **never reads `elixirc_paths`**. The two are unrelated mechanisms. So
extending `elixirc_paths` — which is what brings gates 2 and 4 onto a new
directory — does not drag credo along with it, and a "the gates now cover it"
claim would ship with credo silently absent.

### Measured, both directions

On `main @ ae0e922`, before the fix:

```
$ mix credo --debug | grep Checking
Checking 121 source files (this might take a while) ...
```

`lib/` + `test/` contain exactly 121 `.ex`/`.exs` files; the 4 files under
`conformance/` are not among them.

The control that matters is the same defect judged twice. A module with no
`@moduledoc` was placed in `conformance/lib/`:

```
with    .credo.exs   ->  exit 4, "Modules should have a @moduledoc tag", 128 files checked
without .credo.exs   ->  exit 0, "found no issues",                      121 files checked
```

The identical defect is invisible in one configuration and caught in the other.
That is the mechanism demonstrated rather than asserted.

### The fix, and its one trap

A root `.credo.exs` that **restates credo's default `files.included` verbatim
and appends one entry**. `checks:` is deliberately **omitted**: naming checks
there would freeze the enabled-check set at whatever credo's default happened to
be on the day the file was written, so the project would stop tracking credo's
defaults without anyone noticing.

Verify by the **list, not the count** — 121 can equal 121 while membership has
swapped:

```
$ comm -23 files_before.txt files_after.txt   # removed from credo's set
(empty)
$ comm -13 files_before.txt files_after.txt   # added
conformance/lib/mcp/conformance/beacon.ex
conformance/lib/mcp/conformance/manifest.ex
conformance/lib/mcp/conformance/provenance.ex
conformance/lib/mcp/conformance/runner.ex
conformance/lib/mix/tasks/conformance.adjudicate.ex
conformance/lib/mix/tasks/conformance.run.ex
$ diff checks_before.txt checks_after.txt      # 57 enabled checks, unchanged
(empty)
```

### Residual — what is still unchecked

The fix is scoped to `conformance/lib/`, **not** all of `conformance/`. These
four files remain outside gates 1, 2, 3 and 4:

- `conformance/server_adapter.exs`
- `conformance/client_adapter.exs`
- `conformance/server_handler.ex`
- `conformance/request_state.ex`

That is deliberate. MES-46 measured that adding `conformance/` wholesale to
`elixirc_paths` makes gate 2 **exit 1** on those pre-existing adapters. Pulling
them in would be a different ticket's remediation smuggled into MES-51, and
would put MES-51's gates at the mercy of code it did not write.

**They are the measurement instrument for MES-56 and MES-57.** Bringing them
under the gates is worth its own ticket.

---

## S5-2 — `mix credo --debug` leaves an untracked file at the repo root

**Found:** MES-51, 2026-08-20. **Status:** fixed (`/credo-debug-log.html` in `.gitignore`).

`mix credo --debug` writes `credo-debug-log.html` to the repository root. Before
MES-51 this was untidy. After MES-51 it is a **false-red**: a dirty worktree is
now a refusal condition for a conformance run, so running a diagnostic command
would cause the adjudicator to refuse an otherwise good run.

The general shape is worth keeping in mind: **once "clean worktree" becomes a
gate, every command that drops a stray file becomes a gate failure.** A false-red
is not the lesser failure — a gate that fails spuriously teaches people to bypass
it, and a bypassed gate gives exactly the assurance of no gate while still
looking like one.

---

## S5-3 — `plt_add_apps` did not carry `:mix`, so gate 4 could not see Mix tasks

**Found:** MES-51, 2026-08-20. **Status:** fixed (`plt_add_apps: [:ex_unit, :mix]`).

The moment gate 4 (`mix dialyzer`) reached a directory containing Mix tasks, it
reported 9 errors that were nothing to do with the code:

```
Function Mix.shell/0 does not exist.
Function Mix.raise/1 does not exist.
Function Mix.env/0 does not exist.
conformance/lib/mix/tasks/conformance.run.ex:1:callback_info_missing
```

`:mix` was not in the PLT because, until MES-51, no module under `elixirc_paths`
had ever called into `Mix.*` at runtime. Any future ticket that adds a Mix task
to a gate-covered path hits this on its first `mix dialyzer` and can lose time
reading it as a defect in its own code. It is a PLT contents problem, not a type
problem.

---

## S5-4 — The A12 role table still assigns PM-only transitions to CODE_CREATOR

**Found:** MES-51 dispatch (raised by the PM, recorded here for the PO).
**Status:** open — PO's to correct.

The A12 table assigns the *To Do → In Planning* transition to CODE_CREATOR. That
row predates the seat cutover (MES-27, 2026-08-16). `jira_transition` is PM-only
and **server-enforced from the bearer**, so a CODE_CREATOR call is refused before
anything is requested: the row describes an action no CC seat can perform.

The transferable point: **a role table that predates a permissions change becomes
a set of instructions that cannot be followed**, and a seat trying to follow it
burns a turn discovering that. Any procedure table naming an actor and an action
needs re-reading whenever enforcement moves.

---

## S5-5 — Conformance artefacts nest suite scenarios, so a top-level count understates by 4x

**Found:** MES-51, 2026-08-20. **Status:** fixed in MES-51's tooling; **relevant to MES-56/57's denominator.**

The harness's `-o` tree is **not flat**. Most scenarios get a top-level directory,
but a *suite* scenario gets one directory holding all of its members:

```
$ ls /tmp/run | wc -l                                  # top-level entries
39   -> reported as 9 before this was noticed
$ find /tmp/run -name checks.json | wc -l              # actual scenario dirs
39
$ find /tmp/run/auth -name checks.json | wc -l         # inside ONE entry
31
```

A top-level `ls` of a client run returns 9 entries, of which `auth/` alone
contains 31 checks-bearing directories. Counting the top level reports 9 where
the truth is 39 — **understating by a factor of four.**

The transferable point: **any script that enumerates conformance artefacts must
walk recursively and key on the presence of `checks.json`**, which is the
harness's own unit of a scored scenario. MES-49's scratch adjudicator used a
single-level `os.listdir`, so it silently omitted every `auth/*` scenario.

This is a denominator question, and the denominator is the headline of both
MES-56 and MES-57.

---

## S5-6 — The harness exits non-zero on scenario failures, so its exit code cannot be a gate

**Found:** MES-51, 2026-08-20. **Status:** recorded; the field is provenance-only by design.

`conformance server|client` exits **1** whenever any scenario fails. For this SDK
that is the *normal* state of a run, so a provenance check of the form "refuse a
run whose harness exit code is non-zero" would refuse every real run.

MES-51 records `result.harness_exit_code` and explicitly does **not** judge it.
The general shape is worth stating because it nearly went the other way: **a
signal that is non-zero in the healthy case cannot be used as a failure gate**,
and wiring it up anyway produces a control that refuses everything — which fails
exactly as badly as one that never fires, while looking much more diligent.

---

## S5-7 — A check reading a decoded-JSON operand passes when the operand is absent

**Found:** MES-51 review round 1, 2026-08-20. **Status:** fixed in the adjudicator
(`MANIFEST_INCOMPLETE`); the *mechanism* is general and unfixed everywhere else.

The mechanism, which is the transferable part: **in Elixir, a missing key in a
decoded JSON map arrives as `nil`, and `nil` reads as SATISFIED by every operator
a check is likely to use.**

```elixir
nil == 0        # false -> `if count == 0, do: refuse` never fires
nil > 0         # true  -> term order puts every atom above every number
if nil, do: ...  # falsy -> the branch that refuses is skipped
nil or false     # ** (BadBooleanError) -- a crash, not a refusal
```

Only the last of those four is loud. The other three make a check that **passes
because it could not see**, which is indistinguishable, from the output alone,
from a check that ran and found nothing.

Measured on the MES-51 adjudicator before the fix: of the 54 fields its manifest
carries, **47 could be deleted outright and `judge/3` still returned `:ok`** —
one raised instead. Three of those were reported as separate findings; they were
one defect with three visible faces, and fixing the three would have left the
other forty-four.

**What to do instead.** Do not harden the comparisons one at a time — that is the
fix-the-instance-not-the-class trap, and there is no point at which you know you
are done. Establish *completeness of the record* as a precondition, once, before
any comparison runs, and drive it off an enumeration the tests already pin to
what the writer actually writes. Then state the guarantee as a property
("no comparison can be reached with an absent operand"), because a property is
checkable by enumeration over every field and a list of patched instances is not.

**How to test it.** Enumerate. One test that removes *every* field in turn and
requires a refusal each time; one that nulls every judged field and requires a
refusal; and — the half that is easy to forget — one that nulls every
*unjudged* field and requires ACCEPTANCE. Without that third test, "refuse
everything" satisfies the suite, and a control that refuses everything is as
useless as one that never fires.

**Where else this applies.** Anywhere a gate reads structured input it did not
construct in the same process: `checks.json`, harness JSON output, cached
advisory data, a manifest, a config file. The DoD gate-6 false-green on absent
advisory data (see `CLAUDE.md`, "Known limitation 1") is the same shape at a
different layer — a lookup returning `nil` for a missing key, and `nil` read as
"no advisory".

---

## S5-8 — Narrowing a check to cure a false-red can manufacture a false-green

**Found:** MES-51 review round 1, 2026-08-20. **Status:** fixed
(`DIRTY_EXCLUSION_COVERS_ROOT`, plus the collector refusing to apply a covering
exclusion).

The sequence, which recurs whenever a control is tuned:

1. A control fires on a good run (`WORKTREE_DIRTY` refused every run whose
   artefacts landed inside the repository — the run dirtied the tree it was
   measuring). A real false-red, correctly reported.
2. The fix **narrows the control's input**: exclude the run directory from the
   dirty computation.
3. The narrowing has no upper bound. Exclude a path that *equals or contains*
   the repository root and the control is not narrowed but **switched off** —
   measured: `collect_git(root, [root])` returned `dirty: false` on a worktree
   with a modified tracked file.

**A false-red and a false-green are not symmetric, and the asymmetry is the whole
point.** A false-red is loud, blocks, and gets investigated within the hour. A
false-green is silent, and its output gets published. Trading one for the other
is a regression even though the defect count is unchanged.

**The rule.** When a fix narrows a check's scope, the narrowing needs its own
stated bound, and the bound needs its own control. Ask directly: *what is the
largest exclusion this accepts, and what does the check still guarantee at that
size?* If the answer is "nothing", the bound is missing. Both directions must
then be demonstrated — the newly-refused case AND the originally-false-red case
still accepted — because a fix that closes the new hole by reopening the old one
is not a fix.

---

## S5-9 — Gate 6 went green then red on an unchanged tree, and the mechanism is NOT the one CLAUDE.md documents

**Found:** MES-51 correction round 2, 2026-08-20. **Status:** recorded; the
mechanism is unfixed and, as stated below, **unfixable by any local or live
check**. Raised for the PO — it is a third gate-6 limitation, and `CLAUDE.md`
lists two.

### The two measurements

Same branch, same tree, same `mix.lock`, no repository change between them:

```
20:49:39Z   tip 2186343 committed
            ...gates run on it, gate 6b -> EXIT 0
            "No retired or security advisory packages found"
21:01:27Z   that green reported (comment 24956)

21:35:19Z   gate 6b re-run, same lock -> EXIT 1
            bandit 1.12.1: EEF-CVE-2026-74836 (HIGH), EEF-CVE-2026-75484 (MEDIUM)
```

All timestamps UTC, container clock, with the offset written out (R2). The Jira
comment carrying the green is stamped `22:01:27+0100`, which is the same instant
— the two clocks in this project are one hour apart and mixing them has already
manufactured a phantom stall once.

### The correction — this is not a stale cache, and saying so would be the error

The obvious reading, and the one first reported on the ticket, is that this is
`CLAUDE.md`'s **Known limitation 2** observed rather than theorised: a
complete-but-old registry passing while an advisory published since the snapshot
goes unreported. **The timestamps rule that out.** Both advisories were published
upstream *after* the green ran:

```
$ curl -s https://api.osv.dev/v1/vulns/EEF-CVE-2026-74836 | python3 -c 'import sys,json;print(json.load(sys.stdin)["published"])'
2026-08-20T21:11:18.999Z
$ curl -s https://api.osv.dev/v1/vulns/EEF-CVE-2026-75484 | python3 -c 'import sys,json;print(json.load(sys.stdin)["published"])'
2026-08-20T21:11:27.523Z
```

The green run is bounded to `(20:49:39Z, 21:01:27Z)` — after the commit it
audited, before the comment reporting it. Publication is at `21:11:18.999Z`.
Even taking the very latest instant the green could have run, it preceded the
first advisory's publication by **591 seconds**, and publication falls strictly
inside the green→red interval.

So the local cache was not carrying old data. **There was no advisory to carry.**
The gate was *correct* at 21:01 and *correct* at 21:35, and the answer changed
because the world did. Reporting it as a staleness instance would be claiming a
mechanism wider than the measurement supports — this sprint's own central finding,
committed by the person who found it.

The one bound worth stating: hex's advisory rows and the OSV record come from the
same EEF CNA feed (the ids are literally `EEF-CVE-*`, sourced from
`cna.erlef.org/osv/`), so OSV's `published` is being used as the upstream
availability time. hex.pm cannot plausibly have carried the row *before* the CNA
published it, which is the only direction that would reopen the staleness reading.

### The mechanism

**Gate 6's verdict is a function of `(lock, wall-clock)`, not of the commit.**
Every other DoD gate is a pure function of the tree: gates 1–5 give the same
answer on the same commit forever. Gate 6 reads a continuously-updated external
feed, so its verdict carries an implicit *as-of* timestamp that nothing in our
process records and nothing in our process re-checks.

The DoD is written as though greenness were a property of the commit — "six gates
green" — and for gate 6 it is a property of a moment that has already passed by
the time anybody reads the sentence.

### Why the existing compensating controls do not cover it

This is the part that matters, and it is the reason this entry is not a
restatement of a known limitation:

| Control | Covers absent/corrupt data | Covers stale data | Covers **this** |
|---|---|---|---|
| Gate 6a baseline-lock sentinel | 5 of 26 packages | no | **no** |
| Gate 6b `mix hex.audit` | no (limitation 1) | no (limitation 2) | **no** |
| MES-19's live whole-tree OSV cross-check | yes | yes | **no** |

The live OSV cross-check is freshness-independent and cannot be stale-green — and
it would still have returned **green at 21:01**, because at 21:01 OSV had no
record either. **A control cannot report a fact that is not yet true.** No amount
of freshness, fail-closed behaviour, or live querying reaches this; the gap is not
in where the data is read from but in *when the reading is taken*.

### The rule

Separate the two failure modes, because they have different fixes and only one of
them has a fix at all:

- **Freshness** — the data existed and I did not have it. Fixed by refetching, or
  by querying live. This is limitations 1 and 2, and MES-19 covers them.
- **Recency** — the data did not exist yet. Not fixable by any check, however
  live, run at the same instant.

For recency the only available control is **re-running the check at the moment of
the decision it gates**, and treating the earlier verdict as expired rather than
banked. Concretely: a green gate 6 at ticket time is not evidence at merge time,
and a green at merge time is not evidence at publish time. `CLAUDE.md` already
says a release must not treat a green `mix hex.audit` as publish-blocking evidence
on its own; **the same reasoning applies one level down, to the per-ticket gate,
and is not currently written anywhere.**

The transferable shape, beyond this gate: **any verdict derived from an external
feed should be recorded with the timestamp it was taken at, and consumed with an
explicit expiry.** A verdict quoted without its as-of time is being read as a
property of the artefact when it is a property of an instant — which is exactly
the provenance failure the rest of this ticket exists to make detectable, arrived
at from the opposite direction.

### What was done about it here

MES-51 bumped `bandit` 1.12.1 → 1.12.5 under A11.1, which clears both ids and
turns 6b green again. That fixes the instance. **It does not touch the mechanism**,
and the next advisory published against a locked package between one seat's gate
run and the next will reproduce it exactly.

`CLAUDE.md`'s gate-6 text is deliberately **not** edited. Whether the DoD should
carry an as-of stamp or an expiry for gate 6 is a procedure change and therefore
the PO's decision, not a correction round's.

---

## S5-10 — A command's exit status read off a pipeline is `tail`'s, so a sweep harness reports green it cannot not report

**Found:** MES-51 correction round 3, 2026-08-20 — **and found before, on MES-19,
in Sprint 4.** **Status:** both instances corrected in place; the *mechanism* is
recorded here because correcting instances has now failed twice.

This entry exists because the finding **recurred**. It was hit, diagnosed and
written down in Sprint 4, in the same document that argues a green is only as
good as the instrument that produced it, and it was then hit again in Sprint 5 by
a different seat on a different ticket. A defect that survives being found once
is no longer an incident; it is a property of how we write these harnesses, and
it needs an entry with an owner rather than a paragraph inside a gate table.
(I14 — a finding with no owner lapses; A8.)

### The mechanism

In POSIX shells, `$?` after a **pipeline** is the exit status of its **last
stage**. Write the idiomatic capture-and-trim —

```bash
out=$(some_command | tail -1); rc=$?
```

— and `rc` is `tail`'s status. `tail` succeeds whenever it can read its input,
which is always. **`rc` is structurally incapable of being non-zero**, whatever
`some_command` did, however loudly it failed, and whether or not it ran at all.

Measured, all three arms in one script:

```text
$ fail() { echo "some output"; return 7; }

  out=$(fail | tail -1); rc=$?      ->  PIPED    rc=0   out=[some output]
  out=$(fail); rc=$?                ->  DIRECT   rc=7   out=[some output]
  set -o pipefail
  out=$(fail | tail -1); rc=$?      ->  PIPEFAIL rc=7   out=[some output]
```

The first line is the defect: **the output is right and the status is wrong**,
which is what makes it survive review. A reader checking the transcript sees the
correct text of a failure sitting next to `rc=0` and reads the pair as consistent,
because the text is the part they actually look at.

### Instance 1 — MES-19, Sprint 4

`docs/sprint_4_issues.md:5616-5623`. The gate-5 seed sweep was first written
`out=$(mix test --seed $s 2>&1 | tail -2 | tr '\n' ' '); rc=$?`, so `$?` was
`tr`'s. Twenty seeds reported `rc=0` and, as that entry states, **every one of
those twenty numbers was meaningless: that harness could not have reported a
failure** — including the loudest failure available, a suite that will not
compile, which is how the instance is remembered. It was caught one round after
the PM had named the trap by hand (MES-19 comment 24577 item 2).

The sharpest detail is not that it happened but that **the correct shape was
already written down in the same file**, `docs/sprint_4_issues.md:5124-5127`:

```text
  out=$(cmd 2>&1); rc=$?      <- rc of cmd            USED
  cmd 2>&1 | tail -1; rc=$?   <- rc of TAIL, always 0  NOT USED
```

Prose stating the right answer, in the same document, a few hundred lines above
the place it was got wrong. **Documenting a remedy is not the same as making it
unavailable to get wrong**, and this is the evidence for that.

### Instance 2 — MES-51, this ticket

Both of this ticket's `mix test` loops — the 20-seed sweep and the order-dependent
positive control — were first written `out=$(mix test --seed $s | tail -2); code=$?`.
Same construct, same inert column.

**It was caught only because the expected answer was known in advance.** The
control probe is two tests deliberately built so that one order fails; the loop
reported it **7 PASS / 0 FAIL**. Re-measured with the status taken off `mix test`
directly, the same probe is **4 FAIL / 3 PASS**. Nothing about the transcript
looked wrong — 7/0 is a perfectly ordinary-looking result — and it was disbelieved
only because the probe had been constructed to fail. **A control whose output
nobody has independently validated is not evidence** (A7c): had this construct
sat under the sweep alone, where 20/20 green is the expected answer, it would have
been believed.

That the seat that hit it had read neither the MES-19 entry nor comment 24577 is
the point, not an excuse. The construct is what a competent person writes when
they want the last two lines of output and the status, and it will be written
again.

### Instance 3 — the same family, already inside a DoD gate

`CLAUDE.md`'s gate 6a carries the note *"Capture output BEFORE matching
(pipefail-safe — no `grep -q` in a pipe)"* (`CLAUDE.md:164`). Same family,
opposite sign, and it is worth measuring rather than asserting because
`set -o pipefail` is the obvious fix and **it introduces its own false verdict**:

```text
$ set -o pipefail
$ if seq 1 200000 | grep -q '^7$'; then echo "matched, rc=$?"; else echo "NOT matched, rc=$?"; fi
NOT matched, rc=141
```

The value **is** present. `grep -q` exits at the first match, the producer is
killed by `SIGPIPE`, and `pipefail` promotes 141 to the pipeline's status — so a
successful match is reported as a failure. `pipefail` converts this class of
false-green into a **false-red**, which is the safer direction but is still a
wrong answer, and under `set -e` it aborts the run.

Three disguises — an inert sweep column, an inert control column, and a gate
match that must not be piped. The project has now paid for one mechanism three
times.

### The remedy, as a property rather than a patch

**Take the status off the command being measured. Never off a pipeline that wraps
it.** Trim, format and match *afterwards*, from a variable or a file:

```bash
out=$(mix test --seed "$s" 2>&1); rc=$?     # status here, from the real process
echo "$out" | tail -2                        # shaping is a separate statement
```

State it as a property because a property is checkable by reading every capture
site, and "we fixed the two loops in this ticket" is not. `pipefail` is a useful
belt but not the fix: it makes the wrong-status case louder, it does not remove
the coupling between "what I measured" and "what I formatted with", and — per
instance 3 — it creates a fresh way to be wrong.

**The general form, of which this is one case:** a status, count or verdict must
be read from the process that produced the thing being judged. Every layer
between the two — a pipe, a wrapper script, a formatter, a `tee`, a subshell — is
a place the value can be replaced by that layer's own, silently and with the
correct-looking text still attached.

### Consequence for this ticket's own evidence — read this before trusting a column

MES-51's gate-5 seed sweep was produced by the broken harness, so **its exit-status
column is withdrawn and is not quoted anywhere in this ticket.** The sweep evidence
of record is the **enumerated per-seed result line** — 20 seeds, 20 reporting
`13 doctests, 626 tests, 0 failures`, 0 not reporting it (A2d) — which is text
ExUnit printed and does not pass through the capture that was broken. Same verdict;
different, and independently produced, evidence for it.

This is said plainly so that a later reader does not re-derive confidence in a
column that was deliberately withdrawn. **A retracted measurement that is merely
"not mentioned again" gets picked back up**, because absence of a caveat reads as
absence of a problem.

---

## S5-11 — Keeping `OptionParser`'s invalid list does not reject unknown switches; only `strict:` does

**Class.** Absence read as satisfaction, third surface. S5-7 was absence in the
*manifest* (an absent JSON key comparing as satisfied). B2 was absence in the
*artefacts* (a missing scenario directory counting as a passing one). This is
absence in **the operator's own input**: a misspelled pin is silently *no* pin,
so the check that was asked for is never run — while the tool returns its only
success signal.

### The defect

`mix conformance.adjudicate` and `mix conformance.run` both parsed argv with
`OptionParser.parse(argv, switches: ...)` and discarded the third element.
Measured against a good manifest whose commit equalled `HEAD`, all of these
exited **0 ACCEPTED**:

```
--bogus                                    rc=0 ACCEPTED
--allow-dirty            (retired a round ago) rc=0 ACCEPTED
--expect-commit          (no value)        rc=0 ACCEPTED
--expect-comit 000…      (misspelled)      rc=0 ACCEPTED
--expect-requirement-md5 bad (misspelled)  rc=0 ACCEPTED
--diagnose=maybe                           rc=0 ACCEPTED
RUN_DIR /another/dir     (extra positional) rc=0 ACCEPTED
```

The sharp one is the misspelling: `--expect-comit 000…` accepts, while the
correctly spelled `--expect-commit 000…` refuses `COMMIT_MISMATCH`. **One
transposed letter turns a refusal into a green**, on the tool MES-56, MES-57 and
MES-58 gate on.

### The trap — the obvious fix catches 2 of the 6

The natural remedy is "stop discarding the invalid list". **It is not
sufficient, and reading the docs will not tell you so.** Under `switches:`, an
*unknown* switch is not reported invalid — it is discarded silently, together
with the value behind it:

```elixir
OptionParser.parse(["/d", "--expect-comit", "0000"], switches: [expect_commit: :string])
#=> {[], ["/d"], []}          # empty invalid list; the misspelling is simply gone

OptionParser.parse(["/d", "--expect-comit", "0000"], strict:   [expect_commit: :string])
#=> {[], ["/d"], [{"--expect-comit", nil}]}
```

Only a **known** switch given a bad or missing value reaches `invalid`. Of the
six invocations above, `switches:` reports **2**; `strict:` reports **6**.
Enumerated, `switches:` catches `--expect-commit` (no value) and
`--diagnose=maybe`, and misses `--bogus`, `--allow-dirty`, `--expect-comit` and
`--expect-requirement-md5`. A fix built on the invalid list alone would have
left the four misspelling-shaped cases — including the one that reaches a
report — exactly as they were, while looking like a fix.

### The remedy, as a property

**No invalid operator input may produce exit 0.** Not "unknown switches are
warned about", not "the invalid list is checked" — the property is about the
*status*, because a consumer reading only the status cannot see anything that
was printed. It needs three mechanisms together, each covering a hole the others
leave:

1. `strict:` — so an unrecognised switch is an error rather than noise;
2. the invalid list — so a known switch with a missing or ill-typed value fails;
3. a bound on positional arguments — so a stray path is not silently ignored.

Stated **once for the whole tool** (`MCP.Conformance.Argv`), not per call site:
three surfaces found by three different means is enough to assume a fourth.

### A retired flag needs its own message

`--allow-dirty` was removed one round earlier *precisely* so it could not yield
exit 0. Passing it still did, by a different route — unrecognised, discarded,
run accepted on its merits. **Removing a flag does not retire it if an unknown
flag is ignored**; an operator on a stale runbook gets exactly the outcome the
removal was meant to prevent, and gets it silently. Retired switches are named
explicitly and say they were removed on purpose.

### The test that passed for the wrong reason

The regression test guarding the removal asserted exit 1 on a **dirty** manifest,
reasoning "OptionParser drops the unknown switch; the run is refused on its
merits". Both halves were true and the conclusion was still wrong: the run was
refused because it was *dirty*, not because the flag was rejected. On a **clean**
manifest — the case it never tried — the same invocation exited 0 ACCEPTED. **A
test whose subject and whose cause of passing differ is a green that means
nothing.** When a test's outcome would be the same with the feature removed,
it is testing something else.

### Choosing the exit status rather than falling into it

A usage error exits **64** (`EX_USAGE`, sysexits.h), not 1 and not 2. Reaching
for `Mix.raise` would have given 1 by accident, and 1 already means *this run is
inadmissible* — a verdict reached by adjudicating the run. A usage error
adjudicates nothing. Sharing the code would make a caller that reports
"provenance refused" misreport a typo as a provenance failure, and the two want
opposite responses: fix the command line, versus re-run the measurement. **The
bound:** a caller testing only `rc != 0` cannot tell the four statuses apart,
and that is intended — the safety property is that a usage error is never
mistaken for success, not that every consumer distinguishes it.

---

## S5-12 — The client leg prints no scenario→artefact map, because it runs in parallel

**Found:** MES-56, 2026-08-21, by a deliberate smoke run rather than by MES-57
hitting it under time pressure. **Status:** the server-leg parser refuses a
client console outright; choosing the client leg's key is MES-57's design call.

`checks.json` carries **no scenario id** — its `id` is the *check's*. So a census
needs some other key from a scenario to the directory holding its results. On the
**server** leg the console provides one, adjacently and unambiguously:

```
=== Running scenario: tools-list ===
Results saved to /tmp/run/server-tools-list-2026-…Z
```

On the **client** leg that key does not exist. Measured at
`@modelcontextprotocol/conformance@0.2.0-alpha.11`, `client --suite sep-835`:

```
Running sep-835 suite (5 scenarios) in parallel...
Starting scenario: auth/scope-from-www-authenticate
Starting scenario: auth/scope-retry-limit
… all five started …
Results saved to /tmp/…/auth/scope-from-scopes-supported-2026-…Z
Results saved to /tmp/…/auth/scope-from-www-authenticate-2026-…Z
… in COMPLETION order …
```

**The mechanism:** the client path is a single `Promise.all` over every scenario
(`dist/index.js`), so all start lines precede all save lines and the saves come
back in completion order. There is no textual adjacency to pair them by. The
`--requirements` invocation takes the same branch, so this is not an artefact of
using `--suite` for the smoke run. Two smaller differences travel with it: the
header is `Starting scenario:`, not `=== Running scenario: … ===`, and the
summary mark grows an optional `, K warnings` suffix.

**Why this is worth an entry rather than a fix.** Pairing them positionally
*looks* correct — every scenario is accounted for and every directory is used —
and would have mis-attributed **four of five** here, silently. That is the worst
available failure: a complete-looking table that is wrong. The client leg needs a
different key entirely (its directories are `<scenario-id>-<timestamp>` under a
real `auth/` directory, which is parseable *because* the expected id list is
known and ambiguity can be made to refuse), and picking one is a design decision,
not an adjustment. So `MCP.Conformance.Console` **refuses** a client console and
says why. An instrument that cannot attribute what it reads should decline, not
guess.

---

## S5-13 — A scenario that throws is summarised, scored, and leaves no artefact

**Found:** MES-56, 2026-08-21, on the null-implementation control run.
**Status:** handled explicitly in the console parser and the census; the entry
exists because the shape generalises.

Running the suite against a server that answers `-32601` to everything made
`tasks-capability-negotiation` **raise** inside the harness. The harness caught
it, and:

* printed `Failed to run scenario <id>: <message>` and a stack trace;
* synthesised a single `FAILURE` check for it and counted it in the SUMMARY
  (`✗ tasks-capability-negotiation: 0 passed, 1 failed`) and in the not-scored
  block;
* wrote **no artefact directory at all** — 49 directories for 50 scenarios.

**The mechanism, and why it is dangerous:** a census built from the artefact tree
alone is short by exactly the scenarios that crashed, and a crashed scenario is
always a *failing* one — so the omission biases in the **flattering** direction,
which is the direction nobody audits. Worse, the natural repair is worse than the
disease: treating "no `checks.json`" as "no checks, therefore nothing failed"
turns every crash into a pass.

This is S5-5's shape a second time — the artefact tree is not a faithful index of
what ran — and it is the reason the console↔disk consistency check exists. That
check **caught this unprompted**, on its first contact with a run nobody had
designed it against, which is the only kind of evidence that a control is not
unfalsifiable.

Handled by distinguishing three endings for an announced scenario, from the
console's own evidence: `Results saved to` (ran, artefacts present),
`Failed to run scenario <same id>` (ran, threw, no artefacts — recorded, with the
message, and **failing** under every reducer), and neither (unattributable —
still a refusal, so accepting the second case did not switch the check off).

---

## S5-14 — The adjudicator cannot accept a run of any tree that predates it

**Found:** MES-56, 2026-08-21, at plan time, trying to satisfy an AC that asked
for an adjudicated comparison against a Sprint 4 figure. **Status:** structural,
correct, and **not to be fixed**; ruled by the PM as the fingerprint route.

`mix conformance.adjudicate` accepts only a run whose worktree was clean at the
measured commit. A tree that predates the adjudicator does not contain it, so:

* transplanting the tooling into that tree makes the worktree dirty →
  `WORKTREE_DIRTY`;
* pointing `--cwd` at an old worktree → `CWD_NOT_PROJECT_ROOT`.

There is no third route, and **that falls straight out of the requirement rather
than being a bug in it.** The consequence is general and every future
re-measurement of a shipped release will hit it: *no historical figure can ever
be retro-adjudicated.*

**What to do instead** — and the reason this is an entry rather than a defect.
Reconstructing "old tree + new tooling" on a throwaway branch would produce an
*accepted* manifest attesting a tree nobody ever shipped: not weak provenance but
**false** provenance, manufactured by the tool built to prevent it. Compare
**fingerprints** instead: quote the historical side explicitly as a claim under
review rather than as an accepted figure, and compare against everything the old
run recorded — every reducer, the null control, the check-level census, the named
failing scenarios, the failure decomposition — not just the headline. Zero delta
then means *the fingerprints match*, and any drift lands on a named scenario and
check id instead of on a total.

---

## S5-15 — A seat can exit mid-ticket still holding the baton, and neither Jira nor the dispatch log detects it alone

**Found:** MES-56, 2026-08-21, by the PM, when this seat's engine died 49 minutes
into execution. **Status:** unmitigated. Recovered by hand; the recovery is
recorded here because the *recovery move is not the obvious one*.

The EMFA overrides already name seat death as a gap in the abstract. This is an
instance, with timestamps, and it sharpens the abstract statement in two places.

**What happened.** All times UTC, from `/tmp/emfa-seat-dispatch.log`; Jira
renders `+0100`, and mixing the two inflates every interval by an hour.

| UTC | event |
|---|---|
| `00:13:58` | `ASSIGNED` + `PICKUP` MES-56 — 6s after the PM's ratification handoff |
| `01:03:15` | `ENGINE_EXIT ticket=MES-56 rc=0` — no close-out posted, assignee unchanged |
| `01:16:23` | PM posts a resume handoff to `CODE_CREATOR`, who is **already** the assignee |
| — | **no dispatch for 8m35s** |
| `01:24:58` | PM unassigns, then hands off — an assignee *change* |
| `01:25:04` | `ASSIGNED` + `PICKUP` — 6s later |

**Mechanism 1 — the exit is invisible from either source on its own, so
detection requires a join.** From Jira the ticket is In Progress and assigned to
a seat: indistinguishable from one still working, and there is no upper bound on
a legitimate turn against which a stall could be timed out. The dispatch log does
record the exit — but it logs `ENGINE_EXIT rc=0` for a *healthy* end-of-turn
too. This very ticket shows both: the planning turn exited `rc=0` at `00:09:25`,
19 seconds after its handoff landed, and that was correct. **`rc=0` is emitted
whether or not the baton was passed**, so the log alone cannot classify an exit
either. The signal is the conjunction — *an `ENGINE_EXIT` whose ticket is still
assigned to the seat that exited* — and nothing computes it.

**Mechanism 2 — the obvious recovery is a silent no-op, and this is the more
useful half.** The harness dispatches on an assignee **change**, not on a new
comment and not on an `updated` timestamp. So re-sending the handoff to a dead
seat — exactly what a PM who has correctly diagnosed the death would do, and
what `jira_handoff` is *for* — sets the assignee to the value it already holds,
changes nothing, and fires nothing. The 8m35s row above is that no-op. A PM can
diagnose the stall correctly, re-hand the baton correctly, and still wait
forever, with every reason to believe the seat is alive. **Recovery requires
manufacturing an assignee change: unassign, then hand off.**

**What bounded the loss**, since the interesting question is why 49 minutes of
work survived. Two things, and only the first is the usual advice:

* Commits were small and frequent — three on the branch — so what was lost was
  not a session but a single untracked directory.
* That directory was `docs/conformance/`, which is a **projection** of saved run
  artefacts plus committed code, not an original. Regenerating it and diffing
  reproduced all three files byte-identically. The generate-don't-transcribe rule
  adopted for the census against MES-24's drift defect turned out to also make
  the artefact *reconstructible after a crash* — a second, unplanned payoff for
  the same discipline.

The general form: **work is recoverable to the extent it is either committed or
derivable.** An untracked file that is neither is the only thing a mid-ticket
death can actually destroy.

---

## S5-16 — A DoD gate the reviewer cannot run: `node` is on two seats' PATH and not on the third's

**Found:** MES-56 round 1, 2026-08-21, by `CODE_REVIEWER`, when it tried to
reproduce a green gate 5 and could not. **Status:** the dependency is now
declared and excluded-with-a-reason (`:requires_live_harness`); the PATH
difference between seats is unfixed and is not this ticket's to fix.

Three conformance tests shell out to `node` to cross-check our parsing of the
harness's frozen requirement set against the harness's own listing of it. They
pass for `PM` and for `CODE_CREATOR`, whose shells have node v24.13.0 via nvm,
and they raise for `CODE_REVIEWER`, whose shell does not. Same clone, same
commit, same `mix test` — a green gate for two seats and `rc 2` for the third.

**The mechanism is not the missing binary.** It is that the seats share a
repository and *not* an environment, while the review model rests on the
reviewer being able to re-derive what the author claims. After the seat-family
change, authorship separation is the independence property we have left; an
environment difference that silently removes the reviewer's ability to re-run a
gate erodes it exactly as effectively as a shared identity would, and it does so
without anyone deciding to.

**The half that was ours, and is worse.** Two of the three tests already guarded
themselves with `if File.exists?(requirements_yaml)`. On a host with the
requirement set installed and no `node`, that guard passes and the body then
explodes — which is how it was found. On a host with neither, the guard fails,
the body never runs, and the test **reports green having checked nothing**. A
conditional skip written inside a test body is indistinguishable from a pass in
every report the suite produces. That is absence read as satisfaction, inside
the test suite, on the ticket about exactly that.

**The remedy is a tag, not a fixture.** The precondition is declared once
(`MCP.Conformance.TestHarness.unavailable_reason/0`) and `test_helper.exs` turns
it into an exclusion that prints the reason and visibly shortens the suite:
`170 tests, 0 failures (3 excluded)` instead of `173 tests, 0 failures`. Both
directions were measured. Recording the harness output as a fixture was
considered and rejected: the value of those tests is that two *independent*
derivations agree, and a snapshot would compare the parser against itself.

**Transferable form:** *a test that decides for itself whether it can run must
report that decision in the suite's own counters.* A skip that is invisible in
the count is a pass. And when a gate's runnability depends on the host,
**a green from one seat is not evidence for another** until the dependency is
declared.

---

## S5-17 — Fixing the instance does not answer the class: four defects of one shape in one sprint

**Found:** MES-56 round 1, 2026-08-21, by the PM, on being handed the fourth.
**Status:** answered for the census by an enumerated precondition register
(`MCP.Conformance.Census.precondition_register/0`), with tests that fail when a
refusal exists without one.

Four separate defects this sprint were the same defect: **a value computed as
though its precondition held, with nothing said when it did not.**

| # | site | what it computed anyway |
|---|---|---|
| S5-7 | a check reading a decoded-JSON operand | passed when the operand was absent |
| MES-51 | the acceptance block | printed a console hash for a file that did not exist |
| S5-16 | a test guarding itself with `File.exists?` | reported green having checked nothing |
| B1 | the null-control join | printed "ours alone" over scenarios the control never ran |

Each was found separately, fixed separately, and none of the fixes protected the
next site. The reason is that they are not related by *code* — different modules,
different authors, different rounds — but by *shape*, and a shape is not
something a diff review can be relied on to see.

**What the register does that a fix cannot.** It lists every site in the module
whose value rests on a precondition, together with what happens when that
precondition fails, and it lists the sites that are **already correct** — because
"correct" and "never examined" are indistinguishable from outside, which is the
whole complaint. Four dispositions are allowed: `:refuses`, `:refused_upstream`
(named the condition that makes the local default unreachable), `:reported`
(stated why no printed figure can depend on it), and `:degrades` — of which
exactly one site is permitted, is named, and is asserted by a test, so a second
cannot join it quietly.

Writing it found a fifth instance the review had not: an unrecognised check
status had no disposition in any reducer, so it was silently non-failing and
counted as a **pass** under all three at once — and the harness cross-check could
not catch it, because the harness keys on `FAILURE` too and calls it non-failing
as well. Now `CHECK_STATUS_UNKNOWN`.

**Transferable form:** when a defect recurs, the deliverable is *the enumeration
of its class*, not the fix. Ask of every value: what must be true for this to
mean anything, and what does this code do when that is false? Write the answer
down for the sites where it is "nothing" as well as the sites where it is
"refuses" — an unenumerated correct site is a site nobody has checked.

---

## S5-18 — A seed sweep that tails its own output cannot name the failure it found

**Found:** MES-56 round 1, 2026-08-21, on the gate-5 sweep for the correction.
**Status:** the sweep harness now writes one full log per seed; the red it found
is recorded here because it could not be identified afterwards.

The first 20-seed sweep of the round came back **19 green, 1 red** (seed
`1000003`). The harness printed `tail -25` of the failing run's output, which on
this suite is Bandit's shutdown logging — the ExUnit failure block had already
scrolled past. Nothing else was kept, so the failing test's *identity was
destroyed by the harness that detected it*.

Everything after that is weaker than it should have been: seed `1000003` was
re-run 22 times and passed every time, a fresh logged 20-seed sweep was 20/20
green, and 20 further logged runs at other seeds were green — **61 runs, one
red, unidentified and unreproduced**. That is enough to say the suite is not
reliably red, and not enough to say what happened once.

**Mechanism, and it is the S5-10 family.** S5-10 is about a status read off a
pipeline being `tail`'s rather than the command's; this is its sibling — the
status was read correctly, and the *evidence* was piped away. A sweep exists to
turn a rare failure into a caught one, and catching it is worth nothing if the
artefact that names it is discarded in the same breath.

**Rule:** a sweep writes each run's complete output to its own file and reports
paths, never excerpts. Cheap — 20 files, a few hundred KB — and it is the whole
difference between "a flake exists somewhere" and a bug report.

**Left open, deliberately:** an unidentified intermittent failure in this
suite. It is not attributed to this round's changes (they add pure, `async`
conformance tests with no ports or timers) and it is not attributed to anything
else either, because attributing it would require the log this file exists to
say we did not keep.

---

## S5-19 — A precondition register is complete only relative to the question used to build it

**Found:** MES-56 round 2, 2026-08-21, by the CODE_REVIEWER, on a register that
S5-17 had just declared the class answer.
**Status:** the register stands and was extended; what changed is that it is no
longer treated as self-certifying. A second, mechanical question is now part of
writing one.

S5-17 answered a recurring defect by enumerating its class into
`MCP.Conformance.Census.precondition_register/0` — fifteen sites, each with what
it does when its precondition fails, including the sites that were already
right. The register was **complete against the question that built it**, which
was an intent question: *what preconditions does this code have?* Every site the
author could think of was in it.

The reviewer found a sixteenth by asking a different question, and a mechanical
one:

> Trace every `Map.new`, every default (`||`, `Map.get/3`, `Enum.find/3`), and
> every list-to-set conversion. At each, ask: **is this value valid only if some
> input is unique, or complete?**

That question does not need the author's model of the code, and it is the reason
it found what the intent walk missed. `Map.new(parsed.marks, &{&1.scenario, &1})`
keys the harness's own per-scenario verdicts by scenario id. Two marks for one
scenario collapse **last-wins**, silently. A one-scenario run whose console
carried both `✗ tools-list: 0 passed, 1 failed` and `✓ tools-list: 1 passed, 0
failed` was ACCEPTED, keeping the ✓ — *the flattering one* — while the
cross-check reported agreement with a harness verdict it had just discarded.
The register said "every scenario has a mark". It did not say "exactly one, and
no conflicting duplicate", because nobody had asked whether it needed to.

**The sub-shape worth carrying: PAIRED CONCEPTS, one half guarded.**
`Console.parse/1` had always faulted a scenario mapped to two artefact
directories (`duplicate_faults/1`). The SUMMARY block — the other half of the
same "one line per scenario" property, in the same file, feeding the same
cross-check — had nothing. The concept existed, was implemented once, and was
never applied to its sibling. That is fix-the-instance-not-the-class in
miniature, occurring *inside* the register written to prevent it. So: **wherever
a guard exists for one member of a pair, go and look at the other member.**

Running the mechanical question over the whole converter found **five more**
accepting cases, each measured on a run the tooling accepted before the guard
and refuses after:

| site | the input it assumed | what it did instead of refusing |
|---|---|---|
| `Console.marks/1` | one SUMMARY mark per scenario | kept the last; the ✗ vanished (B2) |
| `Console.marks/1` | no mark without a scenario | ignored a mark for a scenario that never ran |
| `Console.not_scored/1` | one not-scored line per scenario | kept both; the reason became order-dependent |
| `Console.totals/1` | one `Total:` line, one label each | read the first line, kept the last label |
| `RequirementSet` scored/not-scored lists | each id listed once | `expected_counts.scored = 2` over a one-scenario set, with `absentees.scored = []` |
| `Census` leg → frozen set | the leg is one the set defines | `Map.get(…, leg, [])` gave an empty denominator; 0 of 0 rendered as a complete census |
| `Classification` table | the three sources do not overlap | `Map.merge/2` silently kept the harness entry over ours |

Two are worth naming beyond the table. The `RequirementSet` one is the **AC2
denominator vouching for a total it had inflated itself** — and its own
yaml-versus-listing cross-check could not catch it, because that check compares
`MapSet`s, and a `MapSet` discards multiplicity along with the order it was
written to ignore. The `Classification` one is B2's exact sentence in another
file: a duplicate collapses last-wins, and the winner is the entry that says
failing the scenario "costs nothing against the conformance denominator", so the
owned `:real_gap` is the half that disappears.

**Negatives, enumerated, because a negative is the evidence the pass was made.**
The same trace cleared: `Map.new(@reducers, …)`, `Map.new(@statuses, …)`,
`Map.new(Map.keys(@reducers), …)`, `Map.new(@statuses ++ ["total"], …)` and
`Map.new(Classification.classes(), …)` — every key a literal of this codebase's,
unique by construction and asserted by an existing test; the four sites keying on
scenario id (`by_id` twice, a `Map.keys` difference, one `Enum.find`), which
`duplicate_faults/1` has always refused upstream; `Beacon.read/2`'s
`Enum.uniq`, which collapses multiplicity but keeps the count in a separate
field and feeds an existential test; `counts/1`'s `|| "ABSENT"` and
`Map.merge/3` adder, both closed by `CHECK_STATUS_UNKNOWN`; and
`Manifest.refusal_codes/0`'s `Enum.find_index`, over a literal list.

One site was examined and **deliberately left unguarded**: an *absent* `Total:`
line does not fault. Multiplicity and absence are not the same hazard —
multiplicity means two contradictory values with one chosen silently, absence
means no value, and `%{}` is visibly empty to whoever reads it. Guarding it
would be a bound with nothing behind it.

**Transferable form.** A register is an artefact of the question that produced
it, and its completeness claim is only ever relative to that question. Build one
with at least two questions, and let one of them be mechanical enough that it
does not consult your model of the code: *grep the collapse points, then ask
what each one assumes*. Where the answers differ, the second question is the one
that found something.

---

## S5-20 — A stated property with nothing checking the code against it yields one sibling defect per review round

**Found:** MES-56 round 3, 2026-08-21, by the CODE_REVIEWER; the *class* named by
the PM in the round-4 correction contract.
**Status:** closed by construction — the property is now a table over a set the
code itself defines, and completing that table is the terminating condition.

### The defect

`MCP.Conformance.Console`'s `parse/1` moduledoc has asserted a **universal**
property since it was written:

> A console is well-formed only if every scenario it names appears exactly once
> in each block that names scenarios.

Its bullet list also claimed the membership half for one block ("a SUMMARY mark
for a scenario that never ran"). The code satisfied that claim for **three** of
the four blocks `parse/1` returns, and rounds 2 and 3 each found one more block
it was false of:

| round | block | half that was missing |
|---|---|---|
| 2 (B2) | `marks` | multiplicity, then membership |
| 3 (B3) | `not_scored` | membership |

Neither was a guard someone forgot. Both were **a stated property with nothing
comparing it against the code** — and the thing absent was the doc-to-code
check itself, so its absence read as satisfaction. That is this sprint's
recurring defect one level up (S5-17, S5-19).

### Why patching does not terminate

Round 2 fixed the block the reviewer named and swept for more, using the
reviewer's question. Round 3 asked the *same* question and found the next
sibling. A review round that fixes the named instance and sweeps by the same
question can always yield exactly one more instance, because the sweep's
boundary is the sweeper's model of the code rather than anything the code
declares. Rounds 1, 2 and 3 produced 1, 6 and 1 findings, with no round able to
say it was the last.

### The close, and why it terminates

The enumeration is taken over a set **the code defines rather than the author
chooses**: the four content blocks `parse/1` itself returns
(`mappings`, `marks`, `not_scored`, `totals`). For each, both guarantees are
stated in the moduledoc as a table, and every cell must be one of

* *enforced by* a named function,
* *vacuous* for a stated reason (`mappings` **are** the ground truth membership
  is checked against),
* *bounded* for a stated reason (at the time: the client leg has no scenario
  headers, so every mark and every not-scored line is an orphan by construction
  and `parallel_leg_faults/1` refuses that console whole).

A cell that is none of the three is a defect, and the table makes it visible in
the source rather than a review round later. When the table is complete there is
no next sibling for the question to find, because the question's domain is the
return map.

> **Superseded in part, MES-57 round 2 — see S5-24.** The *bounded* example
> above is no longer true of the delivered source. `RunIndex` made client runs
> adjudicable, `announced/1` was taught the client leg's `Starting scenario:`
> header, and both membership cells are now *enforced* on both legs. The
> example is left in place because the point it illustrates — that "bounded for
> a stated reason" is an admissible cell — survives; what it demonstrates in
> passing is that such a reason is a claim about the world and can lapse
> without anyone touching the cell.

> **Superseded in part, MES-56 round 5 — see S5-21.** This entry originally
> gave `totals` as a second *vacuous* example, on the ground that it keys on
> status labels and never on scenario ids. The premise is true and the
> conclusion was not: a label is still a key, and `total_parts/1` accepted any
> lowercase word. That cell is now *enforced*. More importantly, "the question's
> domain is the return map" fixes the domain and leaves the **arity** free, and
> the register one arity up was not closed at all.

Completing it also opened one guarantee **the table does not itself state**:
`marks` and `not_scored` both carry a ✓/✗ for the *same* scenario, and nothing
compared them, so a console could mark a scenario ✗ in one block and ✓ in the
other while satisfying every cell. That is the duplicate-mark defect spread
across two blocks. Guarded in the same round rather than discovered in the next
one — which is what "closed by construction" is supposed to buy.

### The layering, which is a separate ruling

B3 named two different membership questions and they belong in different
modules:

| question | authority | where |
|---|---|---|
| does this not-scored line name a scenario that **ran**? | intra-console | `Console.orphan_not_scored_faults/3` |
| does the **frozen set** agree this scenario is not scored, and for the same reason? | console vs. requirement set | `Census.corroborate_not_scored/3` (`NOT_SCORED_DISAGREES_WITH_FROZEN_SET`) |

`RequirementSet` is deliberately **not** imported into the parser: a parser that
imports its own referee can no longer be used to check the referee. Both halves
are needed — the intra-console guard catches a not-scored line for a scenario
that never ran, and only the cross-authority one catches a not-scored line for a
scenario that ran and that the frozen set **scores**, which is the flattering
direction (a scenario leaving the scored denominator by an edit to a text file
the census reads and never cross-examines).

### Transferable form

A universal claim in a doc comment is a **specification with no test**. Where
one exists, discharge it as a table over a set the code declares — a return map,
a struct's fields, a behaviour's callbacks — not over a list of places worth
looking at. Then the register is closed by construction, and the convergence
signal is *"the table is complete"* rather than *"this round found nothing"*,
which is a claim no round can make.

---

## S5-21 — A register closed over items is not closed over their joins, and the arity has to be argued rather than climbed one round at a time

**Found:** MES-56 round 4, 2026-08-21, by the CODE_REVIEWER.
**Status:** closed by construction — both registers are now enumerations over
sets the code defines, and the moduledoc states why there is no third.

### The defect

S5-20 closed a universal doc claim by turning it into a table over a **closed**
set: the four blocks `MCP.Conformance.Console.parse/1` returns, two guarantees
each, eight cells, every cell *enforced-by* / *vacuous-because* /
*bounded-because*. The round-4 close-out then claimed closure "in your sense…
the question has no undiscovered instance to find, because its domain is the
return value".

That claim was true of what it enumerated and **false of the register one arity
up**. The eight cells say what is true of each block *on its own*. The blocks
are reducers over one run, so they also constrain *each other*, and a console
can satisfy all eight cells and still be one the harness could not have printed.
Measured: a console whose SUMMARY marks sum to 1 passed / 0 failed while its
`Total:` line states 0 passed / 1 failed satisfies every cell, parses with
`faults: []`, and the census **ACCEPTS** it.

### Why it is the same mechanism as S5-20, one level up

S5-20's lesson was "do not enumerate over a set you chose; enumerate over a set
the code declares". Round 4 did that — and then picked the **arity** by hand.
Unary properties were enumerated exhaustively; binary ones were not enumerated
at all, so the first join anyone looked at was unguarded. Choosing the arity is
choosing the domain again, in the one dimension the closed set does not fix.

Climbing one arity per review round does not terminate either, for exactly the
reason S5-20 gives: each round's boundary is that round's model of the code.

### The close, and why it terminates

Two things, and the second is the one that ends it:

1. **Enumerate the next register too** — four blocks, six unordered pairs, no
   pair omitted, each *guarded-by* or *vacuous-because*. Four of the six were
   already guarded; one (`marks × totals`) was the measured defect above and is
   now `total_sum_faults/3`; two are vacuous for stated reasons.
2. **Argue the arity, in the source.** Take a census of what the blocks carry —
   scenario id, verdict, check counts, an aggregate of those counts, directory,
   reason. A consistency property has content only where a value is derivable
   from more than one block. Membership is always stated against one
   distinguished set, so a three-way membership claim is the conjunction of two
   pairs (transitivity, not a new property); agreement needs two carriers of one
   value and no value has three. A genuine triple needs a **hyperedge** — a
   value derivable jointly from three blocks and from no two of them — and the
   census shows there is none. The same census answers every higher arity,
   because it is an enumeration rather than a search.

The terminating condition is therefore not "round 5 found nothing" but "the
arity argument is stated and its premise is a census over the return map".

### Transferable form

When you discharge a universal claim as a register over a closed set, **state
the register's arity and defend it in the same breath**. A per-item register is
evidence about items; it is silent about joins, and joins are where reducers
over one source disagree. Either show that the n-ary case decomposes into the
(n−1)-ary one — usually by finding the shared value and showing it has at most
two carriers — or enumerate the next register too. A closure claim that does not
name its arity is a closure claim about a domain the reader has to guess.

---

## S5-22 — A hand-built accept-half control can be an artefact the source could never emit, and then it proves less than it appears to

**Found:** MES-56 round 5, 2026-08-21, by the CODE_CREATOR — by the guard added
in the same round refusing the round's own controls.
**Status:** fixed; three probe directories and one test fixture rebuilt, and the
fixture now computes the fields the harness computes.

### The defect

Adding `total_sum_faults/3` (S5-21) immediately refused two things that were
supposed to be **accept halves**:

* `/tmp/mes56r4-ns-clean`, the round-4 accept-half control for the not-scored
  cross-authority guard, and the two refusal probes derived from it. Its
  SUMMARY marks sum to 1 passed / 1 failed; its `Total:` line said
  1 passed / 0 failed. The harness cannot print that — it computes the second by
  summing the first;
* the census test's console fixture, which generated its SUMMARY block from the
  run's scenarios and then stated `Total: 3 passed, 2 failed` as a **constant**.
  Correct for the default run, wrong for every test that passes a subset.

Both were accepted for as long as nothing compared the two blocks. The moment
something did, they were revealed as consoles no run could have produced.

### Why it matters more than a broken fixture

The two derived probes — "the console omits a not-scored scenario that ran" and
"the two authorities give different reasons" — were published in round 4 as
evidence that `NOT_SCORED_DISAGREES_WITH_FROZEN_SET` fires. After the new guard
they refused **earlier**, on the incoherent total, and so no longer reached the
guard they existed to exercise. A refusal control that refuses for the wrong
reason still looks green in a table of refusals.

The same applies in the flattering direction: an **accept**-half control built
by hand is an assertion that the instrument accepts something. If the something
is unreachable from the source, the assertion is about nothing.

### The close

Every fixture field the harness *computes* is now computed in the fixture too —
the `Total:` line from the marks it prints, the opening scenario count from the
scenarios it announces, the not-scored header's failing count from the entries
it lists. A control that spoils one field corrects the fields the harness would
have recomputed, so the forgery is internally coherent and the guard under test
is the one that has to catch it. That is a strictly stronger control: it must
now catch a console nothing else can tell is wrong.

### Transferable form

A control is only as good as the fidelity of the artefact it is built from. For
every field of a synthetic fixture, ask whether the *producer* derives it from
another field; if so, derive it in the fixture too, and have a spoiling probe
correct the derived fields it disturbs. Otherwise the first guard that checks
the derivation will silently re-point your whole control set at itself — and the
table of refusals will not change colour when it does.

---

## S5-23 — The client leg's ~39 adapters append to ONE `beacon.jsonl` concurrently, and an interleaved write would corrupt the PROVENANCE while every figure still looked right

**Found:** MES-57, 2026-08-21, by the CODE_CREATOR at plan time; recorded at the
PM's instruction as a genuine new finding.
**Status:** checked and reported on every MES-57 run; 0 foreign and 0
unparseable lines on all five. Not fixed, because there is nothing yet to fix —
see "what would have to change".

### The defect

`MCP.Conformance.Beacon` was designed against the SERVER leg, where exactly one
adapter process starts, emits one line, and runs for the whole run. It is a
**single-writer** assumption, and nothing in the module states it.

The client leg violates it by construction. The harness spawns one adapter
process *per scenario*, all inside one `Promise.all`, so on this suite **39
processes append to one file at once**. An interleaved append would produce a
line whose JSON does not parse, or two half-lines that parse as one.

### Why it is worth its own entry

Because of **which** thing it breaks. A corrupted beacon does not move a single
conformance figure: the scores come from `checks.json`, which each scenario
writes to its own directory. What it breaks is the **attestation underneath**
them — `adapter_count`, and `adapter_sources`, which is how
`Census.corroborate_role/2` tells a control run from a measurement run without
taking the manifest's word for it.

So the failure mode is a run whose numbers are all correct and whose evidence
that they measured *this SDK* is quietly gone. That is the inverse of the usual
hazard, and it is why nothing was looking: every existing check is aimed at the
figures.

### Why it did not fire

POSIX `O_APPEND` writes below `PIPE_BUF` (4096 bytes on Linux) are atomic, and a
beacon line is ~200 bytes. So the current shape is safe *by accident of size*,
not by design — nothing in `Beacon` bounds the line length, and `source` is an
absolute path.

### What is in place now

`Manifest.judge/3` already refuses a run with `foreign_lines > 0` or
`unparseable_lines > 0` (both `ARTEFACTS_INCONSISTENT`). MES-57 checks and
**reports** both on every run rather than relying on the refusal being silent
when it passes: "checked, and zero" and "never asked" read identically when only
the answer is printed.

### What would have to change

If a future beacon line grows past `PIPE_BUF` — a longer `source`, an added
field, a deeper path — atomicity is lost with no warning and no test would
notice. The fix at that point is a bounded line length asserted at emit time,
not a lock. **Do not add a lock now**: it would serialise 39 adapters to buy a
guarantee the platform already gives at this size.

### Transferable form

When a tool grows a second execution shape, ask which of its assumptions were
about the *first* shape's concurrency. Then ask what the violation would damage:
if the answer is "the evidence rather than the result", nothing that watches the
result will ever tell you.

---

## S5-24 — A guard's stated justification can LAPSE without the guard changing, and a lapsed justification reads as considered

**Found:** MES-57, 2026-08-21, by the CODE_CREATOR.
**Recurred:** MES-57 review round 1, same file, found by the CODE_REVIEWER —
see *Recurrence* below.
**Recurred again:** MES-57 review round 2, same file, found by the
CODE_REVIEWER — and by a **different mechanism**, which is why the transferable
form below has two shapes rather than one. See *Second shape* below.
**Recurred a third time:** MES-57 review round 3, found by the CODE_REVIEWER,
and this one is the subclass that matters: **it was GENERATED INTO A PUBLISHED
ARTEFACT rather than read by a human.** The first two instances were comments
and prose a reader might trip over; this one was a string the renderer wrote
into `docs/conformance/*.json`, which MES-58 publishes. Same family, larger
blast radius. See *Third shape* below.
**Recurred a fourth time:** MES-57 review round 4, found by the CODE_REVIEWER,
and the distinguishing feature is one emitter boundary out from round 4's own
sweep: **the sweep found what the code prints when it RUNS, and missed what it
prints when asked to DESCRIBE ITSELF.** See *Fourth shape* below.
**Status:** fixed — `Console.announced/1` now reads both legs' header shapes,
the membership arms are live on both, the prose stating the lapsed bound has
been corrected in seven places, the one sentence that round-2's own rewriting
re-pointed has been corrected in round 3, and round 4 corrected the two
published strings (`@auth_scored_why`, the markdown control section) plus six
non-published siblings of the same claim — three in `client_adapter.exs` (two
comments and the `NOT DRIVEN` stderr message) and three console strings in
`mix conformance.census`, which printed "a do-nothing server" over client-leg
censuses whose controls are null clients. Round 5 corrected the same
noun where the task *documents* it — `mix conformance.census`'s `--control`
option description, printed by `mix help` — and one sibling the same sweep
turned up, `mix conformance.run`'s usage line, which enumerated the adapter
names as `sdk|null` (the SERVER leg's set) to operators of both legs.

### The defect

`MCP.Conformance.Console` suppressed two membership checks — orphaned SUMMARY
marks and orphaned not-scored entries — on a client console, with an explicit
and, at the time, correct justification:

> Same client-leg bound as `mark_faults/3`, for the same reason: with no
> `=== Running scenario:` headers every line here is an orphan by construction
> [...] **The console is refused either way, so the bound costs a diagnosis and
> never a verdict.**

That last sentence was the whole argument, and it was true only because
`parallel_leg_faults/1` refused every client console outright. MES-57's
`RunIndex` made client runs adjudicable. The moment it did, the justification
became false — and **not one character of the comment or the code had to change
for that to happen**.

### Why this class is hard to catch

A stale comment that contradicts its code is findable: the two disagree. This
one did not contradict its code. It described the code correctly and was wrong
about the *world*, and the world was changed by a different file. A reader
reviewing `Console` in isolation would have found nothing wrong, and a reader
reviewing `RunIndex` had no reason to open `Console`.

Left alone, the client leg would have shipped with two membership guards dark
and a comment explaining why that was safe — which is worse than no guard,
because it reads as considered.

### The fix, and why it is byte-safe on the other leg

`announced/1` now recognises the client leg's `Starting scenario:` header as
well as the server's `=== Running scenario: ... ===`. Both are MEMBERSHIP facts
and neither is an ORDER fact, so this does not reintroduce the positional
reading MES-57 exists to rule out. `attributable?` became
`parallel_leg == [] or announced != ∅`, whose first disjunct decides every
server console exactly as before — MES-56's three committed artefacts re-render
byte-identically.

### Recurrence, in the same file and in the same round

The fix above changed the mechanism and left the **prose that stated the old
bound** standing: the moduledoc's block × guarantee table (the `marks` and
`not_scored` membership cells) and the two helper comments still said membership
was bounded on the client leg because there are no headers and the console is
refused either way. The CODE_REVIEWER found three sites by reading. So the same
lapse happened twice, in one file, in one ticket — and the second time the
sentence was falsified by *this entry's own fix*.

That is the mechanism working exactly as described rather than a second,
different defect. It is worth recording because of what it says about the
remedy: fixing the guard does not discharge the claim, because the claim lives
somewhere the compiler never reads. A sweep of `conformance/` for the same claim
shape found **four more** beyond the reviewer's three — the moduledoc's
"this parser is SERVER-LEG ONLY" heading and its closing paragraph, a
name-parsing sentence written before `RunIndex` existed to do it safely, the
`parallel_leg_faults/1` fault message, and a `total_sum_faults/3` comment — all
of which asserted the pre-`RunIndex` state of the world. One published claim
outside `conformance/` was superseded too: S5-20's *bounded* example.

Two things follow, and only the first was in this ticket's scope. **A reviewer
finding one instance bounds nothing** — the count was seven, not three, and the
gap between those numbers is the whole argument for enumerating rather than
patching. And the class wants a machine check: **MES-60** is raised for that
over `lib/`. This sweep suggests it should cover `conformance/` too, and that
the check worth having is not spell-checking prose but binding a named claim to
a named function, since every one of the seven sites cited a real function
correctly while describing a world that had changed.

### Second shape: the correction falsified a TRUE neighbour by moving what its pronoun bound to

Round 2's sweep asked one question — *which sentences assert the pre-`RunIndex`
state of the world?* — and answered it thoroughly: seven, against the
reviewer's three. Round 2 was nonetheless BLOCKING, on an eighth site the
question could not have found, because that site **asserts nothing false on its
own**.

`console.ex`'s first moduledoc bullet ended "On this leg the console states the
mapping outright and is therefore the only non-guessing key." That sentence is
true of the **server** leg and always was. What changed is the sentence before
it: round 2 rewrote the preceding clause to describe the CLIENT leg's key
(`RunIndex`, exact-match against the frozen set), so "this leg" — whose
referent is supplied by the neighbouring prose rather than stated — silently
re-bound to *client*, where the same file says the opposite. **The fix created
the defect**, in text the fix did not touch.

Round 3 swept `conformance/` for that second shape: every deictic whose
referent comes from neighbouring prose — *this/that leg*, *this/that
block/cell/section*, *the former/the latter*, *this one*, *these two*, *the
same &lt;noun&gt;*. **39 sites examined, 1 wrong** — the one above. The other 38
bind to what they bound to before, and 15 of the 39 have a LEG as their
referent, which is the class this ticket's change could move. No *former*/
*latter* appears anywhere in the tree.

A third shape was searched for in the same round rather than left for a fourth:
**a count or ordinal referring into a neighbouring list, which an edit to the
list falsifies without touching the sentence.** Two sites, neither a live
defect: `console.ex`'s "only the first two bullets" (true; the bullets are now
NAMED as the mapping-block ones so a reorder cannot falsify it) and
`classification.ex`'s source count — recorded separately as S5-28.

### Transferable form

When a guard is deliberately narrowed, its justification is a claim about
something OUTSIDE the file. Write down which fact it depends on, and when a
later ticket changes that fact, grep for the guards that were resting on it. Ask
of every bounded check: *what would have to become true for this bound to be
wrong?* — and then notice when your own ticket makes it true.

And when you fix such a guard, the fix is not done at the code: **grep for the
sentences that were resting on the old bound, including the ones you wrote
yourself in the same ticket.** Report the count, including zero — "I looked and
found none" is a result, and "a reviewer found three" is not a bound.

That is shape one, and it is the incomplete half. Shape two is the more useful
one and it cost three review rounds to learn: **a correction can falsify a
neighbouring sentence that was true and that you never touched, by moving what
its pronouns bind to.** So re-read the PARAGRAPHS you edited, not only the
CLAIMS you edited — a deictic (*this leg*, *that block*, *the same reason*)
takes its referent from whatever now sits beside it, and rewriting the
neighbour re-points it in silence. The generalisation of both shapes: a
sentence's truth can depend on text outside it, so the unit of review after a
correction is the passage, not the diff.

### Third shape — the string that LEAVES THE REPO, and the sweep that closes over it

Rounds 1-3 each found a false claim of this family by searching **by shape**:
what kind of sentence goes wrong. Round 4's finding says that was the wrong
axis. `@auth_scored_why` in `classification.ex` said the scored `auth/*`
failures "are an EMPTY" and that "the census marks `empty`". Both halves were
false, and the artefact contradicted them **in the same object**: the scenario
carries `empty: false`, `totals.empty_scenarios` is `[]`, and the rendered row
prints `empty | no`.

What makes it the worst instance is not that it was wrong for longer. It is
that **the run had already falsified it and everything else was corrected**:
round 1's close-out says, in as many words, "There are ZERO empty scenarios on
this leg. My plan's R7 paragraph was wrong... they are not empty, each carries
real FAILURE checks." The plan, the understanding, the delta document and the
register were all fixed on that finding. The one thing left standing was the
string the RENDERER emits.

So the closing sweep is by **blast radius**, not by shape, and it is a closed
set rather than a judgement about where to look: **every human-written string a
renderer or classification table emits into a published artefact.** Enumerate
it from the code that emits it, and check each against the data it accompanies.

**The sweep, MES-57 round 4: 29 units in the set, 2 false, both fixed.** The set
is closed and enumerable from the emitters: **14 distinct human-written string
VALUES** reaching the committed JSON (7 classification `why`, 4 classification
`owner`, 3 reducer `source`) and **15 prose PASSAGES** in the two Markdown
renderers (9 in `Census.Markdown`, 6 in `Discounts.to_markdown/2`). Everything
else that is prose in those artefacts is the harness's own — `failed_checks`
`name` and `message` — and is not ours to check. `delta-vs-sprint-4.md` is
outside the set by construction: it is hand-written and says so in its first
line.

The two false ones were `@auth_scored_why` (above) and `Census.Markdown`'s
null-control paragraph, which described **"a server that answers `-32601` to
every method"** two lines above a bullet naming `null_client_connect.py` — a
Python **null client** that opens a TCP socket, sends no byte and exits 0.
Leg-blind renderer prose, rendered into the client census; the server leg's
wording is unchanged and MES-56's three artefacts re-render byte-identically
from their own run directories.

The remaining 27 hold, with two recorded as imprecise-but-not-false rather than
silently passed (below). The
three reducer `source` strings were re-verified against the harness
`dist/index.js` whose sha256 matches the one the run recorded: the requirements
exit is `+!!scored.some(...FAILURE)`, the server mark is `failed === 0 ? ✓ : ✗`,
and the client suite exit is `+(failed > 0 || warnings > 0)`. All three hold.

**The two imprecise ones, reported rather than changed.** (1)
`Census.Markdown`'s reducer section opens "the harness applies three different
rules and they do not agree" — true of the rules, and on the client measurement
run all three rows read `8/32`, so the sentence sits above a table that agrees.
It is a claim about the reducers, not about the run, and rewriting it would
weaken the reason it exists. (2) `delta-vs-sprint-4.md` says "There are ZERO
empty scenarios on this leg"; that is true of the MEASUREMENT run and of
`null-request`, and false of the other three client runs, where
`http-standard-headers` is an empty. The next sentence names
`totals.empty_scenarios`, which disambiguates it to one census. Both are left
for the PM to rule on: neither moves a number, and the file in (2) is
hand-written and outside this sweep's set.

### The near-miss, which is the part worth keeping

The obvious replacement for `@auth_scored_why` was to state the corrected fact
the way every other artefact states it: *`empty_scenarios` is `[]` on this leg*.
**That would have committed the same defect again, and in more files.** A
classification reason is rendered into **every** census that contains the
scenario — here five: the measurement, three null controls and the
strict-connect probe. `empty_scenarios` is `[]` in two of them and contains
`http-standard-headers` in the other three, because a null client passes that
scenario on eleven SKIPPED checks and no FAILURE, which is the definition of an
empty.

**Transferable:** a string attached to a SCENARIO may assert only what is true
of that scenario in every run the string can be rendered into. A run-level fact
belongs in a run-level field. Before writing a corrected claim, ask *how many
artefacts does this render into, and is it true in all of them?* — the check
that caught this was mechanical: all 5 x 24 = 120 entries carry >= 1 FAILURE
check and `empty: false`. It also killed a second tempting phrasing, "no SUCCESS
checks", which is false for `auth/authorization-server-migration` (2 SUCCESS, in
every run).

### What now guards it, and what does not

`ClassificationTest` gained the JSON counterpart of the markdown projection
test: every classification block in every committed census must equal
`Classification.fetch/1`. Mutating either side fails it, both directions
checked. **It proves derivation, not truth** — round 4's defect was a false
claim faithfully copied into five artefacts and this test would have been green
the whole time. Nothing mechanical catches a reason that is simply wrong. That
is why this is a register entry, and it is the strongest evidence yet for
MES-60.

### Fourth shape — what the code prints when it RUNS vs. what it prints when asked to DESCRIBE ITSELF

Round 4 swept the console strings `mix conformance.census` emits **at runtime**
and corrected three: each said "a do-nothing server" where a client census's
control is a null client. The fix was real and it was verified by re-running the
task. It was also bounded by the emitter it was searched in.

A mix task has a **second** emitter that no amount of running it exercises: the
`@shortdoc`, `@moduledoc` and option descriptions that `mix help TASK` prints —
what the task documents *about itself*. `conformance.census`'s `--control`
option still read "so the passes a do-nothing **server** also earns are visible",
and `mix help conformance.census` printed it verbatim. Same sentence, same
falsity on the client leg, different emitter — so a sweep keyed on *runtime
output* could not see it however carefully it was run.

**The sibling the boundary-crossing turned up.** Checking every mix task in the
project rather than only the one under correction found a second instance of the
class in a task nobody had touched this round: `mix conformance.run`'s `@usage`
line enumerated `[--adapter sdk|null]`. `null` is the SERVER leg's control; the
client leg's adapters are `null_exit0`, `null_connect`, `null_request`,
`strict_connect` and `sdk`. An operator on the client leg following the printed
usage got a raise. That line is doubly instructive: it is printed **at runtime**
(with any usage rejection) *and* it documents the options, so it sits in both
emitters and had been missed by sweeps of each. Fixed by not restating a per-leg
enum in a leg-neutral line at all — the admissible set is already printed, per
leg, from `MCP.Conformance.Adapters.names/1`, at the point where it can be
correct.

**Enumerated, because a count is only evidence if the set is closed.** The
project has exactly four mix tasks — `grep "use Mix.Task"` over the tree outside
`deps/` and `_build/` returns `conformance.adjudicate`, `conformance.census`,
`conformance.discounts`, `conformance.run`, and nothing else. All four had their
`@shortdoc`, `@moduledoc`, option descriptions and `@usage` read. **Two carried
the defect** (census, run — both fixed); `adjudicate` names a leg only inside an
example run-directory path (`.../server-20260820T193000Z`), which is an
invocation and not a claim; `discounts` names the client leg throughout and is
client-only by construction
(it reads `client_summary` and hardcodes `Adapters.scope(:client,
"strict_connect")`), so its leg nouns are true rather than leaked.

**Considered and left, with the reason stated.** (1) `conformance.census`'s two
`@moduledoc` examples both write to `server-2026-07-28.*` paths, and
`conformance.adjudicate`'s example adjudicates a `server-*` run directory. An
example is a valid invocation, not a universal claim, so none of the three is
false — but the file is
the reason the leg-skew keeps recurring: server is this codebase's default noun
and the examples are where a reader learns it. (2) `mix conformance.discounts`
prints a `CLIENT LEG` header derived from nothing in the census it was handed;
its `read!/2` checks `run.role` (measurement / control / probe) and never
`run.leg`, so a *server* measurement census would be accepted and reported under
a client-leg heading. Not blocking and no committed number depends on it — the
one pipeline that invokes the task passes client censuses — but it is the same
hardcoded-leg-noun shape one layer down, and a `run.leg` check in `read!/2`
would close it by construction. Both are outside round 5's ratified contract and
are recorded here for the PM to rule on rather than absorbed silently.

**Transferable, and this is the generalisation of all four shapes:** when a
false claim is found, the question is not only *what shape of sentence went
wrong* (rounds 1-3) or *how far does it travel* (round 4), but **which emitters
can utter it**. Runtime output, generated artefacts and self-documentation are
three different emitters over the same source strings, and a sweep names one of
them whether or not its author noticed choosing.

---

## S5-25 — Reading a NARROW instrument as a wide one produced a catastrophic-looking headline with no bug anywhere

**Found:** MES-57, 2026-08-21, by the CODE_CREATOR — from the first output the
derivation produced.
**Status:** fixed; the probe's scope is declared once in
`MCP.Conformance.Adapters` and `Discounts.derive/1` refuses a probe given
without one.

### The defect

The drive-policy discount is established by a PROBE: the SDK client driven under
one changed policy (halt on a `connect/1` error). The probe drives **one**
scenario — the only one the claim is about — and takes its not-driven path for
the other 38, exiting 0 so the fail-closed checks decide.

The first derivation compared the probe's whole sheet against the measurement's
and subtracted every scenario the probe did not pass. That removed 6 of 7
in-scope scenarios and reported the client leg as **0 of 7**.

Nothing was broken. The probe was correct, the measurement was correct, the
censuses were correct and both runs were ACCEPTED. The number was manufactured
entirely by reading "said nothing" as "failed".

### Why it would have survived review

**Its shape is right.** It is a subtraction, over the correct denominator, under
the correct reducer, computed from adjudicated runs, with every scenario named.
Every discipline this project enforces was satisfied. A reader checking the
arithmetic would have found it sound.

The only thing wrong was the *width of the instrument*, which is not a number
and appears nowhere in either census. And "0 of 7" is a plausible thing for a
conformance report to say.

### The fix

`scope` is now a field of the adapter registry: `:all`, or the explicit list.
Two consumers read the same declaration — the probe, to decide what to drive,
and the derivation, to decide what silence means — so they cannot disagree.
`derive/1` **raises** on a probe supplied without a scope rather than defaulting
to `:all`, because a default would have made the wrong reading the quiet one.

### Transferable form

Before subtracting one run from another, ask whether both were asked the same
questions. `Census.control_covers_measurement/2` already enforces exactly this
for the null control — it refuses a control that did not run every scored
scenario the measurement did — and the probe comparison was a second instance of
that concept with no such check. **When a guard exists for one comparison, look
for the comparison it does not cover.**

---

## S5-26 — The null control's own inversion bites the DISCOUNT computed from it, so "which null" is a number-moving choice

**Found:** MES-57, 2026-08-21, by the CODE_CREATOR, while deriving discount 2.
**Status:** treated — the discount takes the union over all three nulls, and each
null's own figure is reported separately.

### The finding

On the client leg a **stricter** null scores **lower**: measured on this tree at
`f4be9eb`, `null_exit0` 2/32, `null_connect` 2/32, `null_request` **1/32**. The
mechanism is that for a do-nothing client `http-standard-headers` is a pass
assembled from **eleven SKIPPED checks and not one that could fail**; the
strictest null sends one request, a twelfth check appears, and it fails.

That inversion is already known. What is new is that it propagates into the
**discount**. The null-passable subtraction removes any in-scope scenario a null
also passes, and the only such scenario is `http-standard-headers`:

* union over all three nulls → `http-standard-headers` subtracted → **5 of 7**;
* `null_request` alone → it FAILS there, nothing is subtracted → **6 of 7**.

So the headline moves by one on a choice that looks like housekeeping, and the
flattering choice is the one that sounds most rigorous — "we used the strictest
null".

### Treatment

Take the **union**: a scenario is null-passable if *any* null passes it. That is
the reading least flattering to the SDK, and it is the one Sprint 4's figure was
computed under, so the two remain comparable. Report each null separately beside
it so the choice is visible rather than folded into the number.

### Transferable form

When a control set is not totally ordered by strength, "the control" is not a
value and any function of it is a choice. Enumerate the controls, state the
aggregation rule, and check whether the flattering answer is the one that sounds
most rigorous — because that is the one that gets published without argument.

---

## S5-27 — A documented procedure a seat cannot execute: the gate-6a cleanup line is rejected by the local command guard

**Found:** MES-57 review round 2, 2026-08-21, by the CODE_REVIEWER, while
running gate 6.
**Status:** recorded, deliberately NOT fixed here. The PM holds the decision on
whether `CLAUDE.md`'s snippet is amended; MES-57 was instructed not to change
`CLAUDE.md`.

### The finding

`CLAUDE.md`'s gate-6a snippet ends with a cleanup line that removes the
temporary positive-control checkout it created. The CODE_REVIEWER ran gate 6a
at `b2787da`, and the **local command guard refused that cleanup form**, so the
directory `/tmp/mes57-gate6a.MaAnOC` was left behind. The gate itself passed —
all 22 baseline advisory ids present — so nothing about the advisory result is
in doubt.

**It is per-seat, not universal — measured rather than assumed.** The
CODE_CREATOR ran the same cleanup form on its own gate-6a control directory in
round 3 and it succeeded (exit 0, directory gone). So the snippet is not
unrunnable in this container; it is runnable under one seat's command guard and
refused under another's. That distinction decides the remedy: rewriting the
snippet would be fixing the wrong thing if the guards are simply configured
differently, and the question to answer first is which guard is right.
CR's directory has deliberately been left in place, since it is the evidence.

### Why it is worth an entry rather than a shrug

A litter directory is trivial. **A DoD procedure that a seat cannot run as
written is not**, and the two are easy to confuse because the visible symptom is
the trivial one. The gate-6 snippet is the most-copied block in `CLAUDE.md`: it
is run per ticket, by every seat, and it is the one gate whose correctness rests
on a shell fragment rather than on a `mix` task. A step that silently cannot
execute is a step that will be silently skipped, and the next reader will assume
the snippet was verified end-to-end because it is written down.

The residue also accumulates in a way that reads as evidence: `/tmp` now carries
several `mes57-*gate6a*` directories from different seats and different rounds,
each a full `deps.get` of the baseline lock. Anyone reconstructing a run from
`/tmp` later will find several trees that look like measurement material and are
not.

### Transferable form

A procedure written in a repo is a claim that a seat can execute it. When a step
of one fails **for reasons of the environment rather than the code** — a command
guard, a missing tool, a permission — that is a finding about the procedure, not
a housekeeping nuisance: record it against the procedure, and do not let the
tidy-up cost hide the fact that the documented form did not run.

---

## S5-28 — `Classification`'s collision guard checks the three TOP-LEVEL merges, while the file's own prose now counts four sources

**Found:** MES-57 review round 3, 2026-08-21, by the CODE_CREATOR, from the
third-shape sweep described in S5-24 (a count referring into a neighbouring set).
**Status:** recorded, not fixed — **no live defect**: measured, nothing overlaps
today. Backlog, per the merge stopping rule (it moves no number, breaks no gate
and falsifies no published claim).

### The finding

`MCP.Conformance.Classification` builds `@table` as
`@ours |> Map.merge(@client_table) |> Map.merge(@harness_table)`, and refuses at
COMPILE time if any of the **three** pairs among those three tables shares an
id — the guard MES-56 added after `Map.merge/2` was found to resolve a collision
silently in favour of its second argument, always in the flattering direction.

MES-57 added the client table and wrote, correctly, that "the table is now four
sources, not three". Both of the merged tables are themselves merges:

* `@client_table` = `@auth_scored_scenarios` ⊎ `@auth_extension_scenarios`;
* `@harness_table` = `@extension_scenarios` ⊎ `@pending_scenarios`.

So the leaves are **five id-lists**, and `@collisions` covers only the three
pairs *between* the top-level three. An id appearing in both halves of
`@client_table`, or both halves of `@harness_table`, collapses exactly as B2
described — silently, second argument winning — and the compile-time guard does
not see it. The prose one paragraph above ("if the sources ever overlap, this
file must not compile") is therefore **wider than the check beneath it**, which
is the MES-51 theme applied to a guard rather than to a printed field.

### Measured, so the entry states a fact and not a worry

`Classification.table()` has **43** entries. The five leaf lists hold
24 + 6 + 9 + 2 + 2 = **43**. Equality over the union means no id is shared
between any two lists and none is repeated within one, so today the unchecked
pairs are empty and no scenario is mis-classified. That is a property of the
current lists, not of the code: the auth ids come from an upstream frozen set,
which is precisely the kind of input that changes without anyone editing this
file.

### Transferable form

When a guard enumerates pairs, check that its enumeration is over the **leaves**
and not over an intermediate layer someone introduced later. A merge of merges
looks like one operation in the expression that reads it, and a collision inside
an inner merge is invisible to a guard written against the outer one. The tell
is a count in the prose that no longer matches the count in the check — here,
"four sources" beside three pairs.

---

## S5-29 — A classification's prose restated the TOOL'S generic message as an observation, and named a defect the run never saw

**Found:** MES-58, 2026-08-21, by the CODE_CREATOR, while citing the gap register to the
saved check sheet rather than to the census summary.
**Status:** recorded, not fixed — **no figure moves**: the scenario's class (`real_gap`),
owner and check counts are all correct, and only the free-text `why` is wrong. Backlog, per
the merge stopping rule.

### The finding

`server-2026-07-28.json`'s `classification.why` for `server-stateless` decomposes its 17
failures into four sub-causes, of which (d) reads:

```text
(d) error.data.requiredCapabilities is an array where the schema defines an
    object of capability objects
```

The run's own saved check sheet says otherwise. `sep-2575-server-rejects-undeclared-capability`
captured this response:

```json
{"jsonrpc":"2.0","id":401,
 "error":{"code":-32021,
          "message":"Missing required client capability: sampling (requiredCapabilities: {\"sampling\":{}})"}}
```

There is **no `error.data` at all**. The value is stringified into the error *message*. The
mechanism is the one `docs/sprint_4_issues.md` recorded as **R5** — *a handler error return
has no `data` slot* — and its owner is MES-43 gap 4.

### The mechanism, which is the transferable part

The harness's check reads `error.data.requiredCapabilities`, finds `undefined`, and emits
**one generic message** covering every way the field can be wrong:

```js
!t(e) || !t(e.sampling) ? {error: `… is not a ClientCapabilities object naming 'sampling'
  (the schema defines it as an object of capability objects, e.g. { "sampling": {} },
   not an array)`} : …
```

The trailing *"not an array"* is the tool **explaining the schema**, not **reporting what it
saw**. Reading it as an observation converts "the field is absent" into "the field is an
array" — a different defect, with a different fix, in the flattering direction: absent is
worse than mis-shaped.

**Why it is worth an entry.** A classification is written once and read by whoever schedules
the fix. A fixer sent to "change an array to an object" would look for an array that does not
exist, find the field missing, and have to re-derive the cause from scratch — after
concluding the register was unreliable. The classification survived a review round because
it is *plausible*: it quotes the tool almost verbatim.

### Transferable form

When a check fails, the tool's message describes **the predicate that failed**, not
necessarily **the state that failed it** — a fail-closed check emits the same sentence for
absent, null, and wrongly-typed. Before writing a cause into a register, read the **captured
response**, not the **error string**. The tell is a message that enumerates what the value
*should* be: that phrasing is written for every failing case at once, so it cannot be
evidence about this one.

---

## S5-30 — An enumeration of causes covered 16 of 17 checks, and the one it dropped was the one with no owning ticket

**Found:** MES-58, 2026-08-21, by the CODE_CREATOR, mapping the census's sub-causes onto the
root causes in `docs/sprint_4_issues.md` in order to cite an owner per row.
**Status:** recorded, not fixed — same artefact and same stopping-rule verdict as
S5-29. Distinct mechanism, so a distinct entry.

### The finding

The same `classification.why` decomposes `server-stateless` into **four** sub-causes. Counted
against the run's check sheet, they account for **16** of the **17** failing checks:

```text
(a) _meta absent/invalid         3 request-meta-invalid-* + 3 http-server-meta-invalid-400   = 6
(b) unsupported protocolVersion  1 server-unsupported-version-error + 1 …-version-400        = 2
(c) removed methods -> 404       5 …-404-<method> + 1 …-method-not-found-404                 = 6
(d) requiredCapabilities         1 server-rejects-undeclared-capability + 1 …-http-400       = 2
                                                                                      total   16
```

The seventeenth is `sep-2575-http-server-header-mismatch-400`, and it appears under none of
the four. It is the check for **R4** — no cross-check of the `MCP-Protocol-Version` header
against `_meta.protocolVersion` — which the MES-43 escalation list also never routed. **The
one check the enumeration drops is the one root cause with no owning ticket.** That is not a
coincidence to shrug at: the same reader who wrote the summary is the reader who would have
noticed the gap had no owner.

### Why it is a different mechanism from S5-29

S5-29 is a *wrong* statement — one that can be falsified by reading the evidence. This is a
statement that is *true as far as it goes* and **silently short of its set**. Nothing in the
prose is false; the sentence merely says "four distinct defects" without saying "…covering
sixteen of seventeen checks", so there is **no number in the text for a reviewer to check
against**. The failure is invisible by construction: an enumeration with no stated count
cannot be seen to be incomplete.

### Transferable form

**An enumeration in prose must carry the count it claims to cover, and the count must be of
the leaves.** "Four distinct defects" is unfalsifiable; "four distinct defects, accounting for
all 17 failing checks" is a claim a reviewer can test in one subtraction — and would have
failed here. This is the same shape as S5-28 (a guard whose enumeration ran over an
intermediate layer rather than the leaves) and the same shape as the A2d rule the project
already applies to counts: **enumerate, and state the total, so that "covered everything"
cannot be read into a list that did not.**

---

## S5-31 — Two different things are named `totals` in one library, and the console one has no consumer

**Found:** MES-58, 2026-08-21, by the CODE_CREATOR, answering the PM's MES-59 precondition
question; recorded at the PM's direction (ratification comment 25183).
**Status:** recorded, **nothing renamed here** — a rename inside a publish-only ticket is out
of scope, and the collision is latent rather than live.

### The finding

`conformance/lib` contains two unrelated things called `totals`:

* `MCP.Conformance.Console.totals/1` — a parse of the harness's printed SUMMARY block;
* `census["totals"]` — the census's own map, built by `MCP.Conformance.Census.totals/5` from
  scenario check data.

They are computed from different inputs by different code and mean different things. A grep
for `totals` across `conformance/lib` outside `console.ex` returns **only** the census map —
`census["totals"]`, `Census.totals/5`, `control_totals/2`, `classification_totals/1`. **No
consumer outside `console.ex` reads the parsed console `totals` value at all.** The
`Console.blocks/1` fields that *are* read outside it are `mappings` and `faults`
(`RunIndex`) and `marks` and `not_scored` (`Census`'s `corroborate_reducer/3` and
`corroborate_not_scored/4`).

**Stated precisely, because the loose version would overclaim.** `totals` is not inert
*inside* `console.ex`: `totals_faults/1` and `total_sum_faults/3` cross-check it against the
marks block, and `faults` **is** read outside. So a defect in how `totals` is parsed can
still reach a consumer — as a spurious fault, or a missing one. What has no consumer is the
**value**.

**Consequence, and it is the reason the PM asked:** per-leg printer-shape enforcement on the
console *totals* block has **no consumer for its value today**, so MES-59's precondition
resolves to "speculative guard" — with the qualification above, which is the PM's to weigh
rather than mine to decide.

### Transferable form

Two things sharing a name in one library is how a future reader wires the wrong one — and it
is worst when one of the two is **unused**, because the unused one is the one a search for
the name surfaces first, with nothing downstream to go red when it is picked. Record the
collision even when nothing is broken: the entry is cheaper than the debugging session, and
the moment to rename is a ticket that already touches the file, not this one.

---

## S5-32 — Three guards are justified by a NAMED future consumer; the consumer has now arrived and reads none of them

**Found:** MES-58, 2026-08-21, by the CODE_CREATOR, while answering the PM's MES-59
precondition question at the delivered tip.
**Status:** recorded, not fixed — **no live defect**. Every guard involved is correct and
cheap; what has lapsed is the *reason written beside it*. Nothing renamed, nothing removed.

### The finding

`conformance/lib/mcp/conformance/console.ex` carries three sites whose stated justification is
that **MES-58 will consume** the field they guard:

```text
:694  "Nothing in this project reads `not_scored` yet — MES-57 and MES-58 will"
:718  "... into an IR that MES-57 and MES-58 are documented consumers of"
:785  "Same reasoning as the block above: unread today, load-bearing for MES-58"
```

**MES-58 consumes none of them.** It reads the committed censuses
(`docs/conformance/*-2026-07-28.json`) and their rendered markdown; it starts no harness and
parses no console. Two of the three are rescued by the *other* named consumer — `Census`
gained a `blocks.not_scored` reader in MES-57 — but the `totals` site at `:785` has **no
consumer for its value at all** (see S5-31), and the one it named has now arrived and does
not read it.

### The mechanism, which is what makes it worth an entry rather than a comment fix

A guard justified by *"X will need this"* has a property no other justification has: **it
becomes checkable exactly once, when X lands, and nothing schedules that check.** X's author
is working on X and has no reason to grep for prophecies about it; the guard's author has
moved on. So the justification survives its own falsification and keeps reading as
considered — the S5-24 mechanism, arriving through a different door. S5-24's lapsed
justifications lapsed because the *world* moved; these lapse because the *prediction was
wrong*, and the difference matters for the remedy: no amount of re-reading the guard reveals
it, only the arrival of the named consumer does.

It is also the argument that *sounds* strongest at review time. "Guarded now rather than
after it is load-bearing" is good practice and was the right call — the guards would be
worth keeping even with no consumer at all, because they cost nothing and the failure they
prevent is silent. **The defect is not the guard; it is having written a falsifiable claim
about the future into the place a reader looks for the reason.**

### Transferable form

**Do not justify a guard by naming a ticket that does not exist yet.** Justify it by the
property it protects — "a duplicate here fails silently and in whichever direction the file
is ordered" is true forever and needs no consumer. If a future consumer *is* the reason,
write it as a *prediction* rather than a *fact* and expect to be wrong: the first thing the
named ticket should do is check the claim made in its name, and that check belongs in the
brief, not in the reader's luck.

---

## S5-33 — A test globs `docs/conformance/*-2026-07-28*.json` and `Map.fetch!`es `"scenarios"`, so the FIRST non-census file in that directory breaks gate 5

**Found:** MES-58, 2026-08-21, by the CODE_CREATOR — **by hitting it**, not by reading for
it. Adding the Confluence mirror payload to `docs/conformance/` turned gate 5 red.
**Status:** **worked around in MES-58, not fixed.** The payload moved to
`docs/conformance/confluence/`, a subdirectory the glob does not descend into. The latent
defect is untouched and is reported here rather than repaired, per the ticket's scope
boundary — a publish-only ticket does not fix instruments.

### The finding

`test/conformance/classification_test.exs:157` reads:

```elixir
for path <- Path.wildcard(Path.join(docs, "*-2026-07-28*.json")),
    scenario <- path |> File.read!() |> Jason.decode!() |> Map.fetch!("scenarios"),
```

The glob's predicate is **"a filename in this directory containing the revision string"**.
The code's assumption is **"a census"**. Those are not the same set, and nothing narrows the
first to the second: any JSON file whose name happens to carry `-2026-07-28` is opened and
`Map.fetch!("scenarios")` is applied to it. A file without that key does not fail the
assertion the test exists to make — it raises `KeyError` and takes the test out before it can
make any assertion at all.

**Measured, not predicted:** committing
`docs/conformance/report-2026-07-28.confluence.json` — a Confluence payload, not a census —
produced

```text
1) test ... every classification block equals what Classification.fetch/1 returns
   ** (KeyError) key "scenarios" not found in: %{"_readme" => ..., "content" => [...]}
   13 doctests, 826 tests, 1 failure
```

### Why it is worth an entry rather than a rename and silence

**The directory is a natural home for non-census artefacts and will attract more of them.**
`docs/conformance/` already holds four `.md` files that are not censuses; the JSON half has
simply been homogeneous so far, and the glob quietly depends on that continuing. The next
non-census JSON — a fixture, a payload, a captured denominator, a second revision's
manifest — breaks a gate for a reason that has nothing to do with what the test checks, and
does so **at whatever moment someone adds a file**, which is the worst time to be debugging a
test about classification drift.

**The workaround is not the fix, and the difference is worth stating.** A subdirectory keeps
*this* file out of the way; it does nothing about the next one placed alongside the censuses,
and it leaves a glob whose stated domain is wider than the domain it can actually handle.
The fix is to make the selection say what it means — filter on shape (`Map.has_key?("scenarios")`)
or on the census's own `census_schema_version`, rather than on a substring of a filename.

### Transferable form

**A glob is a claim about a directory's future contents, and it is the weakest kind of
claim available** — it selects on *names*, then the code proceeds on *structure*, and nothing
connects the two. When a `Path.wildcard` result feeds a `fetch!`, the pairing is a latent
crash waiting for the first file that satisfies the name and not the shape. Select on the
property you actually depend on; if that means reading each file and skipping the ones that
do not qualify, the extra line is cheaper than a red gate on someone else's ticket. This is
the same family as S5-30 — a set defined one way and consumed as if it were defined another.

---

## S5-34 — A statement about how well something is CHECKED is itself a claim, and it was the one claim in the report the check did not cover

**Found:** MES-58 review round 1, 2026-08-21, by the **CODE_REVIEWER**, at `cdb19e4` —
**by mutating the report and watching the check stay green**, not by reading the script.
**Status:** **fixed in MES-58 round 2**, by broadening the check rather than narrowing the
claim (PM correction contract, comment 25192, C1).

### The finding

`docs/conformance/report-2026-07-28.md:6-8` published this guarantee about itself:

```text
Every number below is quoted from an adjudicator-accepted run and is
transcription-checked against the census JSON.
```

The reviewer changed the client headline — the single most quotable sentence in the
document — from `5 survive` to `6 survive`, changing nothing else, and re-ran the check:

```text
MES-58 transcription check: 134 assertions
PASS — every figure in the report matches the artefact it was derived from.
```

134 assertions, and not one of them was about that sentence. The **figure itself was
correct**; what was false was the report's statement about how well the figure was checked.

### The mechanism, and why it is not "a missing assertion"

Calling this an oversight understates it. The check *did* carry needles containing the
headline's numbers — but they were matched against **the whole report as one string**, so an
assertion nominally about the headline was satisfied by any paragraph anywhere that happened
to contain the same words. The §4 body says `The raw figure is 8 of 32, and it may not be
quoted bare`; the §2 headline says `The raw figure is 8 of 32 and`. **A body paragraph was
standing in for the headline**, which is why the coverage looked complete while a headline
mutation slipped through. Coverage measured as *"is there an assertion mentioning this
number?"* was not coverage of *"is this sentence checked?"*.

The three targets combined into the worst case:

* **The most-copied sentence** — the report's own §2 says the headlines are written to
  survive being copied out alone, so they are precisely what a transcription guarantee most
  needs to cover.
* **The broadest wording** — "every number below", with no bound stated.
* **A verifier that could not distinguish** — the substring match had no notion of *where*
  in the document the needle was satisfied.

### Why it belongs beside S5-24 rather than in the same bucket as a wrong figure

This is the assurance-layer form of S5-24 (*a guard's stated justification can lapse without
the guard changing*). There, a true-then-false justification made a guard read as considered;
here, an over-broad coverage statement made a check read as complete. In both, **nothing in
the artefact was numerically wrong** — what was wrong was a sentence about the artefact's own
reliability, and that is the kind of sentence a reader has no independent way to test. It is
also the same shape as two of this sprint's own defects one level down: a PM close-out saying
gate 6a's cleanup line "is rejected by the seat command guards" when it was rejected by one
seat's, and the `@auth_scored_why` attribute justified by a consumer that read nothing.

**A claim about verification gets no exemption from the standard it describes.**

### The fix, and the shape it takes

Two changes, and the second is the one that generalises:

1. **Headline assertions are bound to the headline text.** The check now extracts the two §2
   blockquotes and asserts against *those strings*, so a needle satisfied elsewhere cannot
   stand in. The reviewer's exact mutation now fails, as do `passes 35 → 36` and
   `6 of those 35 → 7 of those 35`.
2. **The coverage statement was made testable instead of merely more careful.** Every
   assertion is filed under a *kind of figure*; the kinds are closed by the report's own
   structure; the per-kind tally is printed; and **the report's §11 coverage table is
   asserted against that tally** — one assertion per row, plus the forbidden-shape count and
   the grand total. Mutating any cell of that table now fails the check. The one kind that
   **cannot** be asserted (the R1–R6 root-cause attribution, whose evidence is the harness
   run directory and is not committed) is published as a **0** with its reason, rather than
   omitted.

> **Corrected at round 3 — the zero in item 2 was wrong about a committed artefact, and the
> fix in item 2 was the wrong *kind* of fix.** The censuses do carry the check-name sheet
> (`failed_checks`), so the names and counts were assertable all along and are now asserted;
> only the *attribution* survives as uncheckable. And broadening the check a second time was
> what invited a third round. Both are **S5-35**, which is the entry to read after this one.

### Transferable form

**Write the coverage claim as a number the checker produces, not as a sentence the author
believes.** "Everything below is checked" is unfalsifiable prose; "these 14 kinds of figure,
with these 14 assertion counts, one of them zero" is a statement a reader can test by running
the thing — and it fails loudly when the artefact grows a kind of figure nobody covered.

**And test the verifier where the claim is loudest, not where the code is easiest.** A
substring match over a whole document reports coverage of *vocabulary*, not of *sentences*;
bind each assertion to the region whose correctness it is standing for. The way to find this
class is the way the reviewer found it: **mutate the most quotable sentence and see whether
anything goes red.**

## S5-35 — Broadening a check to catch each new instance is unbounded; the terminating move is to bound the claim

**Round 2 of the MES-58 review found the report's §11 coverage claim over-claiming in five
places. Round 1 had found the same class in one place, and the fix then was to broaden the
check. That fix is what produced round 2.** The report says "every figure above is checked".
That is a claim about a **hand-written document**, and no finite script closes it: for any
check, a new sentence can be written that the check does not cover. Broadening is therefore
a move with no last step, and each round costs a full review cycle.

CODE_REVIEWER's mutation sweep is what made the shape visible rather than arguable: it
mutated **every numeric token in the report — 595 of them**, one at a time, each scored by a
full run of the check. 262 caught, 333 not. Most of the 333 are identifiers a transcription
check has no business asserting (`SEP-2322`, `ADR-003`, JSON-RPC codes, HTTP statuses, dates,
list markers). What was left after setting those aside was five real over-claims — and the
point is that **the sweep enumerated them instead of finding one more**, which is what turns
"broaden again" into a decision that can be refused with a reason.

### The five, and the two different remedies they needed

| # | over-claim | remedy |
|---|---|---|
| (a) | the R1–R6 row published as **0** because "no committed artefact carries the mapping" | **assertions** — the premise was false |
| (b) | the §9 row titled "…and exit codes" while no assertion read the report's exit-code sentence | one assertion + honest labelling |
| (c) | §8 had **no row at all** in a table published as complete | give it a row |
| (d) | the guarantee covered a figure's *first* statement; every restatement was unguarded | **wording** |
| (e) | §11's own self-check count was the one number in its closing sentence nobody asserted | assert it |

**(a) is the one worth keeping.** The zero was not an omission — it was published *with a
stated reason*, which is the discipline that is supposed to make a zero honest. **The reason
was wrong about a committed artefact.** `docs/conformance/server-2026-07-28.json` carries
`failed_checks`: all 17 failing check ids for `server-stateless`, by name. Every check name
in the R1–R6 table is in it, and every count in that column reproduces from it. So the
answer to "cannot be asserted, or merely was not?" was **merely was not** — and the
difference matters downstream, because §11 was telling a Sprint 6 planner that S5-30's "16 of
the 17" and "the seventeenth" were unverifiable when the census verifies the names and the
17. What genuinely cannot be asserted is narrower: the **attribution**, which cause a given
check belongs to, whose evidence is the uncommitted run directory.

**A stated reason for a zero is a claim like any other, and it is the claim least likely to
be re-read.** It is written once, by the person who has just decided not to do the work, and
every later reader takes it as settled. The check on it is cheap and specific: *name the
artefact the reason says does not carry the data, and open it.*

**(d) is the one that terminates the round.** Rather than binding every restatement — which
is the broadening move again, one level down — the guarantee now says what it binds: **the
primary statement of each figure, not every restatement of it**. That is true today, it took
one sentence, and it cannot decay into a sixth instance. The same move handles (b): four of
that row's assertions are **artefact-side** (they assert a property of the census and never
open the report), so the table gives them their own column instead of counting them as report
coverage.

### The bounded claim, tested the way the broad one was broken

A bound is worth no more than the sweep that fails to break it, so the same exhaustive,
position-aware mutation was re-run against the **bounded** claim at the delivered tip.

```
numeric literal occurrences in the report: 619
mutations scored: 619   caught: 304   uncaught: 315   phantom (refused, not scored): 0
```

**All 315 uncaught were read by hand, position-aware.** Every one is an identifier (spec id,
Jira key, sprint or gap number, `R1`–`R6` label, `§` reference, function arity, version,
commit, hash, port, flag name), a list marker or heading number, a claim the report quotes in
order to call it false (`"29 of 37"`, `"78% conformant"`, `"100% conformance (Tier 1)"`), or a
**restatement of a figure whose primary statement is caught**. Spot-checked in both
directions: mutating the primary statement of three figures whose restatements are uncaught —
the §5 `extension` table row (`9`), the null-control score (`6 of 37`), the §2 client
headline (`leaving 7 in scope`) — fails the check every time.

**So the bound is exactly right, rather than merely safer than the old claim.** No primary
statement is uncovered; restatements are uncovered and are now *stated* to be. That is the
difference between a guarantee that holds and one that has survived two rounds of patching.

**This sweep is a function of the report and the check, not of the tree that records it** —
the commit carrying this entry changes neither, so recording the result here does not
outdate it (contrast **S5-16**'s tip problem, where committing the measurement moved the
thing measured).

**One thing the sweep cannot do, stated because a green sweep invites the opposite reading.**
It mutates the report and asks whether the check notices. It says nothing about whether the
census is right — every figure could be faithfully transcribed from a wrong measurement and
the sweep would look exactly like this. Transcription is all that is being proved, and the
adjudicator is the control on the other half.

### The named uncovered restatements — where the edit-time drift risk sits

**The bound is right, and the residual it leaves is edit-time drift.** A restatement is
uncovered *by design* now, which is honest but not free: whoever edits this report next can
change a primary statement, watch the check go green on it, and leave a restatement behind
saying the old number. The mitigation that fits is a **note naming where that sits**, not
another assertion — an assertion would be the broadening move this entry exists to refuse.

**A sub-class is worth naming: restatements that, if they drift, make a sentence contradict
*itself*.** Measured at the delivered tip, one mutation at a time, each scored by a full run
of the check:

| report site | the restatement | mutated | check |
|---|---|---|---|
| §3 | `35` in "So 35 − 6 = **29**" | `35` → `34` | **uncaught** |
| §3 | the `6` in the same sentence | `6` → `7` | caught |
| §3 | the `29` in the same sentence | `29` → `28` | caught |
| §5 | ``Server `extension` (9)`` before a 9-name list | `(9)` → `(8)` | **uncaught** |
| §5 | ``Server `pending` (2)`` before a 2-name list | `(2)` → `(3)` | **uncaught** |
| §5 | ``Client `extension` (6)`` before a 6-name list | `(6)` → `(7)` | **uncaught** |
| §5 | ``Client `out_of_scope_adr_003` (24)`` before a 24-name list | `(24)` → `(23)` | **uncaught** |

**Every one of the five uncaught has its primary statement caught** — §3's subtraction is
checked on both of its other terms, and each §5 parenthetical restates a §5 classification
table row that the check does assert (mutating all four rows fails it). So the bound holds
exactly as stated; these are the figures it declines to bind, listed by name.

**Why it is left alone rather than fixed.** A drifted one of these reads `"34 − 6 = 29"`, or
a `(8)` over a list of nine names — the **loudest** failure mode available to a human reader,
not the quietest. The quiet failure is a stale figure with nothing beside it to disagree
with, and that is the one the check covers.

**And the count is the point.** This started as two instances the author looked at hardest;
CODE_REVIEWER's hand-read of the 315 uncaught added ``Server `pending` (2)`` and ``Client
`extension` (6)``; enumerating the §5 bullet list mechanically then added ``(24)``. Three
passes, three different totals — **"no sentence may contradict itself" is a judgement over
prose and not a closed set**, which is why this is a register note and not an assertion. The
table above is the set as enumerated, not a proof that no sixth exists.

### Transferable form

**A bounded guarantee that holds beats a broad one that does not.** When a review finds
instance *n* of a claim outrunning its evidence, the question is not "how do I catch instance
*n*" but "what is the largest guarantee I can actually discharge". Patch the instance and you
have bought one round; narrow the claim and you have closed the class.

**Two markers that you are on the unbounded side:** the claim quantifies over a
*hand-written* artefact ("every figure", "all sections", "each of these"), and the fix for the
last instance was to make the checker bigger. Either alone is survivable; together they
predict the next round.

**And the diagnostic that ends the argument is exhaustive mutation, not another example.**
One more counter-example invites one more patch. An enumeration over every candidate — with
the position recorded, not just the line, so a caught primary statement and an uncaught
restatement on the same line do not collapse into one entry — turns the choice between
broadening and bounding into a decision with the whole set in view.

This is the assurance-layer twin of the sprint's own **S5-17** (*fixing the instance does not
answer the class*), and it is the second time this sprint the same pattern has cost a review
round. The difference here is that the class was **named and refused** rather than
rediscovered: MES-56 spent five rounds patching instances of a claim, and that history is
what justified stopping at two here.

## S5-36 — Capability was verified from the wrong seat: "X is reachable" is a claim about ONE seat, and a lane ruling is a claim about a DIFFERENT one

**Found by PROJECT-MANAGER, on themselves, at the last possible moment — after review, after
the squash-merge, with the only remaining step being the one that could not run.** MES-58's
acceptance says the report is *published*. Everything upstream of publication was correct and
had survived four review rounds. The step that failed was the one nobody had tested.

### What happened

CODE_CREATOR reported that `confluence_create_page` was reachable from **its** seat and asked
the PM to rule which lane publication belonged to. The PM ruled it into the **PM lane** —
correctly, on the merits, since the page must name the squash-merge commit and that commit did
not exist at CC's handback. At execution time the PM seat turned out not to have
`confluence_create_page` at all. It has the Rovo page tool, which takes HTML/markdown/ADF and
not the wrapper's typed blocks.

**Nothing in the reachability report was wrong.** It was accurate, and it was accurate *about a
different seat*. The defect is entirely in the inference: a lane ruling silently re-scopes a
capability claim from the seat that made it to the seat that will execute it, and no step in
between re-asks the question.

### The cost, which is the part that makes it worth an entry rather than a note

The PM did not simply stop. They built the bridge: converted the payload's typed blocks to ADF
and verified the conversion properly — substitution `{{MERGE_COMMIT}}` → SHA in `content` only,
`_readme` untouched, flattened token comparison **4962 == 4962, identical**. The conversion was
sound. **The delivery was not, and the PM said so rather than proceeding:** the ADF is 108,098
bytes and every one of them would have had to be emitted verbatim through a tool parameter —
hand-reproducing a 108 KB document from a summary is precisely the transcription defect this
ticket exists to prevent, and "I will verify it afterwards" is the same bargain as a green
sweep over a check nobody read.

So the wrong-seat check cost a full PM→CC→PM round *plus* a sound-but-unusable conversion,
and it bought nothing that a single `tools/list` from the executing seat would not have
settled before the first plan.

### The second defect underneath it: a ruling outlives its own reason silently

Ruling 2's entire justification was temporal — *the mirror must name the merge commit, and the
commit does not exist yet*. Once `ef7fc48` existed the premise was discharged, and with it the
conclusion. But nothing in a ruling carries an expiry: it reads as a standing allocation of
work long after the condition that produced it has been satisfied. **The PM caught this by
re-reading their own reasoning, not by any mechanism** — which is the honest description, and
the reason it is recorded here rather than presented as a process that worked.

### How the 108 KB was actually delivered, since the same wall stood in front of CODE_CREATOR

Amending the ruling moved the hop, not the payload. CC's seat *has* the tool, but CC would
still have had to emit ~86 KB of typed blocks verbatim through a tool parameter — the same
transcription bargain, one seat over.

**It was not retyped. The delivery path was made to read the file.** The wrapper is an MCP
server over HTTP (`.mcp.json`: `${EMFA_WRAPPER_URL}/mcp`, per-seat `Bearer
${EMFA_SEAT_INBOUND}`), so the tool call was POSTed to that endpoint as an ordinary
`tools/call` for `confluence_create_page`, with the request body built from
`docs/conformance/confluence/report-2026-07-28.json` by a script. **Same wrapper, same seat
credential, same tool, same validator** — the only thing removed from the path is the hand-copy
in the middle. The substitution, the `_readme` exclusion and the argument set were assertions in
that script rather than intentions in a paragraph:

```
assert exactly 1 substitution inside `content`      -> 1
assert `_readme` still holds its own occurrence     -> unchanged, not passed to the call
assert no `{{MERGE_COMMIT}}` survives in `content`  -> 0
assert the SHA appears exactly once                 -> 1
arguments = space_key, parent_id, title, content    -> `_readme` absent by construction
```

**The transferable half:** when a payload is too large to retype faithfully, the answer is not
to retype it carefully. It is to give the delivery path the file. A tool parameter is not the
only way to reach a tool.

**What this does NOT establish, stated because the obvious reading is wrong.** It does not show
the PM could have done the same. The wrapper resolves a role from the bearer, so whether the
HTTP route exposes `confluence_create_page` to the PM seat depends on whether tools are gated by
**role** or only by **transport** — and that was not tested, because testing it means using
another seat's credential. `jira_whoami` takes no arguments precisely so that no seat can ask
about another; borrowing a bearer to answer a convenience question would defeat that on the
first occasion it was inconvenient.

### Publication, verified rather than assumed

| check | result |
|---|---|
| page created | id `275841149`, version 1, space `ElixirMCPS`, parent `209682736` (*MCP_Elixir_SDK*) |
| payload vs page, flattened tokens | **5158 == 5158**, md5 `0003b852…` on both sides, token-for-token identical |
| structure | 90 top-level blocks; 6 panels / 21 headings / 8 tables / 297 paragraphs / 1087 text nodes, sent and stored |
| silent Confluence damage | **0** `extension` / `bodiedExtension` / `inlineExtension` nodes; marks `strong` 228, `code` 262, `em` 51 — equal on both sides |
| the panel | renders `ef7fc4844998edcd6c9b2b9b8d4a0663b4d990bd`; `{{MERGE_COMMIT}}` occurs **0** times on the page |

The comparison is against an **independent read-back** (`confluence_get_page`), not the create
call's own echo — the create tool returns the page as stored, but a tool reporting on its own
write is the weaker of the two available checks and both were free. The flattener is stated so
the figure is interpretable: every `text` node's text in document order, whitespace-split; it is
**not** the 4864-token mirror-fidelity number, which pairs the payload against the repo markdown
under a different definition. Two numbers named `tokens` measure two different things, which is
S5-31's shape and is why both are spelled out here.

### Gates

**The PM waived gates for a register-only edit. Gate 5 was run anyway, and the waiver is
otherwise stated rather than assumed.** This commit changes `docs/sprint_5_issues.md` and
nothing else. Gates 1–4 cannot see it *by configuration*: `.formatter.exs` inputs are
`{mix,.formatter}.exs`, `{config,lib,test}/**/*.{ex,exs}`, `conformance/lib/**/*.{ex,exs}` and
`.credo.exs`; compile and dialyzer read `lib/`; `.credo.exs` restates credo's default
`files.included`. None reaches `docs/`.

Gate 5 is the exception and was run for exactly one reason: **S5-33 in this same register is a
docs file turning gate 5 red.** Two tests read `docs/` — `classification_test.exs:157` and
`census_markdown_test.exs:35` — and both are scoped to `docs/conformance/`, which this commit
does not touch; no test references `sprint_` at all. That is an argument, so it was checked
against a run rather than left as one. Gate 6: not applicable, no `mix.exs` / `mix.lock` change,
established by three-dot diff.

### Transferable form

**A capability claim names a seat. A lane ruling names a different seat. The two are not
transitively composable, and the gap between them is invisible in the text of either.** "X is
reachable from here" and "X happens in lane L" read as though they compose into "L can do X";
they do not, and the sentence that would have caught it — *which seat will run this, and has
that seat been asked?* — costs one tool call.

**The marker that you are in this failure mode:** the capability was reported by one party and
relied upon by another, and no message in between names the executing seat. Every hop after
that point is spent on work that cannot be delivered by whoever is holding it.

**And the detection cost is the argument for checking early.** This surfaced after the plan,
after four review rounds, after the merge gate, after the squash-merge and the tag — the last
step before Done. Every one of those rounds was spent on a document whose route to publication
had never been tested. **Verify the capability from the lane that will execute it, at the
moment the lane is chosen** — not when the lane is finally asked to move.

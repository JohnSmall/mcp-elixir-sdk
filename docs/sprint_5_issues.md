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

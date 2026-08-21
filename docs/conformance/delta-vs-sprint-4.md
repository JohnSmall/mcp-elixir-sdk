# Delta against Sprint 4's server-leg figure

**Written by hand, unlike its neighbours in this directory.** The census and the
per-scenario table are projections of `census.json`; this file is an argument
about two runs and cannot be. Every number on the MES-56 side is quoted from
`server-2026-07-28.json` and is therefore adjudicated; every number on the
Sprint 4 side is quoted from `docs/sprint_4_issues.md` and is **not**.

## The historical side cannot be adjudicated, and that is structural

`mix conformance.adjudicate` accepts only a run whose worktree was clean at the
commit measured. A tree that predates the adjudicator does not contain it, so
transplanting the tooling into that tree makes the worktree dirty
(`WORKTREE_DIRTY`) and pointing `--cwd` at the old worktree refuses with
`CWD_NOT_PROJECT_ROOT`. There is no third route, and this is not a defect to be
fixed: **no run of any tree predating the adjudicator can ever be accepted**
(`docs/sprint_5_issues.md` S5-14).

Reconstructing "Sprint 4's tree + MES-51's tooling" on a throwaway branch was
considered and **refused**. It would produce an *accepted* manifest attesting a
tree nobody ever shipped — not weak provenance but **false** provenance,
manufactured by the tool built to prevent exactly that.

So: **Sprint 4's 35/37 is quoted below as a historical claim under review, not
as an accepted figure.** It is an operator's record, tied to its tree by an
assertion, which is the whole reason MES-51 exists. The comparison is still
worth making — it just cannot be dressed up as two adjudicated numbers.

## Compared as a FINGERPRINT, not as a headline

A headline-to-headline comparison would let two different runs agree on one
total by coincidence. Every axis Sprint 4 recorded is compared instead, so zero
delta means *the fingerprints match* and any drift lands on a named scenario and
a named check id.

| axis | Sprint 4 (claim under review) | MES-56 (adjudicated at `940445c`) | delta |
|---|---|---|---|
| server, FAILURE-only (`requirements_exit`) | 35/37 | **35/37** | zero |
| server, warnings-also-fail (`client_summary` rule) | 33/37 | **33/37** | zero |
| server, scored check census | 98 S / 19 F / 2 W / 0 SKIPPED | **98 / 19 / 2 / 0** | zero |
| the two failing scored scenarios | `server-stateless`, `input-required-result-non-tool-request` | **identical** | zero |
| their check split | 13 S / 17 F and 0 S / 2 F | **identical** | zero |
| the 19 FAILUREs by family | sep-2575 ×17, sep-2322 ×1, wire-schema-valid ×1 | **identical** | zero |
| the 2 WARNINGs | `sep-2164-data-uri`, `sep-2322-ignore-unexpected-params` | **identical** | zero |
| null control, FAILURE-only | 6/37 | **6/37** | zero |
| null control, warnings-also-fail | 3/37 | **3/37** | zero |
| null ⊆ ours (what makes the subtraction legal) | superset holds | **holds — 0 null passes outside our 35** | zero |
| discriminating (35 − 6) | 29/37 | **29/37** | zero |

Zero on every axis.

**Re-derived at each correction tip, never carried over.** Two rounds have moved
the census converter — B1 in round 1, B2 and the collapse-site audit in round 2 —
and each time both runs were re-taken and every axis above recomputed from the
new `server-2026-07-28.json` rather than copied from the file it replaced. Round
2's re-take is at `940445c`.

No figure has moved across either. Round 1 added two fields
(`not_in_control_not_scored`, `in_control_only`); round 2 added refusals and no
fields at all, and its regenerated census is **identical to round 1's on every
substantive key** — the only bytes that differ are the per-scenario
`artefact_dir` timestamps and the `started` stamp, which name when the run
happened rather than what it measured. All fourteen compared axes were
re-derived independently from the new files, over a fresh pair of runs, and each
is zero.

That is the falsifiability check this table exists for: a converter that had
started refusing correct runs would have shown up as a missing run, and one that
had started accepting incorrect ones would have shown up as a moved axis.

## What zero delta does and does not mean

**It is a self-consistency check, not a measure of progress.** No SDK code
changed between the two measurements; MES-51 and MES-56 added tooling under
`conformance/`, which the server adapter does not load on the protocol path.
A non-zero delta would have meant something was wrong with the *measurement*,
not that the SDK had moved.

**One dependency did move, and the fingerprint did not.** `bandit` went from
1.12.1 to 1.12.5 in MES-27's advisory remediation, on the transport path this
leg exercises. Every axis above is unchanged across that bump — evidence about
`bandit`, weak but real, and the reason the brief named it as the first
hypothesis to check had the delta been non-zero.

**What is different is the STANDING of the figure, not the figure.** Sprint 4's
35/37 was measured with the official suite and recorded by an operator. This
one is tied to `940445cef85ebad7ad7181db93ca1d7fbe4d98ad` by a manifest the
adjudicator re-verified from disk, over a denominator captured into the run
directory and cross-checked against the harness's own listing of it, with every
non-pass classified and owned. That is the change MES-56 was for.

---

# Delta against Sprint 4's client-leg figure

Added by MES-57. Same discipline as the server section above, and the same
caveat: every MES-57 number is quoted from `client-2026-07-28.json` and is
therefore adjudicated; every Sprint 4 number is quoted from the MES-57 brief's
record of it and is **not**. S5-14 applies unchanged — no run of a tree
predating the adjudicator can ever be accepted, so the historical side stays a
claim under review.

## Compared as a FINGERPRINT

| axis | Sprint 4 (claim under review) | MES-57 (adjudicated at `f4be9eb`) | delta |
|---|---|---|---|
| client, scored (`client_summary`) | 8/32 | **8/32** | zero |
| client, driven-and-passing core | 7 | **7 of 7 in-scope** | zero |
| all-scenario check census | 66 S / 59 F / 2 SKIPPED / 1 INFO | **66 / 59 / 2 / 1** | zero |
| null `exit 0` | 2/32 | **2/32** | zero |
| null connect-and-say-nothing | 2/32 | **2/32** | zero |
| null one-request | 1/32 | **1/32** | zero |
| the inversion (stricter null scores lower) | holds | **holds** | zero |
| drive-policy discount (`request-metadata`) | holds | **holds, re-measured** | zero |
| null-passable discount (`http-standard-headers`) | holds | **holds** | zero |
| figure surviving both discounts | 5 of 7 | **5 of 7** | zero |

Zero on every axis, including the two discounts — which were **re-derived by
measurement on this tree**, not carried across. See
`client-2026-07-28-discounts.md`, which is rendered from the censuses.

## What the fingerprint does NOT say, stated by enumeration

**1. The measurement run contains no WARNING at all, so its own headline is
reducer-independent — and that is a coincidence of this run, not a property.**
`requirements_exit`, `server_summary` and `client_summary` all read 8/32 here
because the measurement's 128 checks include zero WARNINGs.

The reducer choice is nevertheless load-bearing, and the PROBE is where it
bites. Under the strict-connect probe `request-metadata` scores 7 SUCCESS and
**1 WARNING**:

| reducer | probe verdict on `request-metadata` | discount 1 |
|---|---|---|
| `requirements_exit` | PASS (a WARNING is ignored) | would not fire |
| `server_summary` | PASS (a WARNING is ignored) | would not fire |
| `client_summary` | **FAIL** (a WARNING fails) | fires |

So a derivation reading the wrong reducer would have found no drive-policy
discount and published **6 of 7** — with every scenario named, over the right
denominator, from two adjudicated runs. The discipline is what produces the
difference, not the arithmetic.

**2. There are ZERO empty scenarios on this leg, and that corrects an
expectation MES-57 started with.** The plan expected the 25 scored `auth/*`
scenarios to land as empties — scenarios with a check sheet nobody exercised.
They do not. Each carries real FAILURE checks (`auth/metadata-default` 5,
`auth/scope-retry-limit` 1, and so on) because those checks are fail-closed and
the adapter emits nothing to satisfy them. `totals.empty_scenarios` is `[]` in
both directions, and no scored scenario has `SUCCESS + FAILURE == 0`.

The distinction matters for Sprint 6's queue: these are not unmeasured, they are
**measured failures of an absent surface**, and the reason they cost nothing is
ADR-003 rather than emptiness.

**3. The raw 8/32 exceeds the in-scope numerator by exactly one scenario, and
that scenario's pass is inherited from the null.** `auth/resource-mismatch` is
the 8th. It passes on a **single** SUCCESS check, and every null control passes
it too — it is in `totals.control.inherited`. It is outside the in-scope
denominator on the ADR-003 ground, and it would be worth nothing inside it.

**4. Zero delta is a self-consistency check, not progress.** No SDK code on the
client path changed between Sprint 4 and MES-57; what changed is the standing of
the figure. A non-zero delta would have meant something was wrong with the
*measurement*.

## What is different is the STANDING

Sprint 4's client figures came from the official suite at `@0.2.0-alpha.11`
driven through `conformance/client_adapter.exs` — they were never self-derived,
and the ticket body corrects that. What they lacked was provenance: no manifest,
no adjudication, no captured denominator, and **no way to adjudicate them at
all**, because `Console.parse/1` refuses a client console and every gate that
depended on it therefore refused the run.

MES-57's figure is tied to `f4be9eb4624813ebcf5418898180f0ca433ab562` by a
manifest the adjudicator re-verified from disk, over a denominator captured into
the run directory and cross-checked against the harness's own listing of it,
with every one of the 30 non-passing scenarios classified and owned, and with
the scenario→artefact map derived by a key that refuses rather than guesses.

## The fixed point does not exist, and this is the bound rather than a claim

Committing a census moves the tip the census attests. What is guaranteed is
narrower and is stated instead: **no code commit falls between the measurement
run and delivery.** All five runs were taken at `f4be9eb`, the last code commit
on this branch; only censuses, rendered tables and documents land after it. The
same shape MES-56 delivered.

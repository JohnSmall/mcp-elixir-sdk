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

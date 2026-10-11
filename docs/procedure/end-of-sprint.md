# End-of-Sprint Procedure

> **Moved verbatim from `CLAUDE.md` by MES-177** (lines 611-751 at e74bf3f; heading promoted
> one level). "The gate-6 applicability rule above" and gate 5 are in `CLAUDE.md`,
> *Definition-of-Done Gates*; "the two-step gate 6" (6a, 6b) is `docs/procedure/gate-6.md`;
> the push rule (D8) is `docs/procedure/publication.md`. **One content change, MES-177 AC7:**
> step 4's sweep cost ("~22 s per mutation cycle × 50 directions … 25–30 minutes", and "a
> 25–30 minute gate") is replaced by the figure measured on MES-174.

**Runs in the gap between sprints — after the last ticket is Done, before the next
sprint's first dispatch. PM-owned.** Seats run strict-sequentially, so at a sprint
boundary there is by construction no work in flight; that is what makes this the one
moment an advisory can be acted on without disrupting anything.

1. **Write up `docs/sprint_{N}_issues.md`** — the sprint's findings register.

2. **Dependency-advisory sweep.** Run the **two-step gate 6** (6a baseline sentinel,
   then 6b) against `main` at the sprint's final tip.

   - **The gate-6 applicability rule above does NOT apply here.** That rule is about
     *tickets*; this is a cadence sweep and it runs every sprint regardless of what
     changed. Do not skip it because no ticket touched `mix.lock` — the whole point
     is to catch advisories published against dependencies nobody touched.
   - **Two-step, never bare.** Known limitation 1 still holds: a bare `mix hex.audit`
     exits 0 over an outstanding advisory when the local cache is incomplete. 6a is
     what makes a green mean something.
   - **Record the result in `docs/sprint_{N}_issues.md`, including a clean one.**
     "Checked, and zero" and "never asked" read identically when only the answer is
     printed — so print the question.

3. **Any advisory becomes a Jira ticket. Do not fix it in place.** Raising it on the
   board is the reason this sits between sprints rather than inside one: it gets
   scoped, prioritised and scheduled like any other work, instead of being absorbed
   silently into whatever ticket happened to notice it.

4. **Boundary-liveness sweep** (added by MES-88 under PM ruling `26994`). Re-run the
   ET-CC boundary-liveness measurement against `main` at the sprint's final tip and
   diff it against the committed table:

   ```bash
   mix conformance.sweep --check
   ```

   - **Why it is here and not on a ticket.** The ET-CC register's `boundary` field and
     its liveness verdict are the register's only **measurements**; every other field
     is a judgement. A judgement goes stale when the *criterion* changes, and the
     criterion is under change control. A measurement goes stale when the *code*
     changes, which happens constantly and under none. `etcc_register.ex`'s guard 19
     validates the register against the **recorded table**, never the table against
     the **tree**, so it stays green while the verdicts under it rot. Nothing else
     re-runs the sweep.
   - **The per-ticket half is gate 8** (MES-175). `mix conformance.sweep --verify` checks,
     on every ticket that changes `lib/`, that the `mutation_spec` anchors still resolve.
     It re-measures nothing, so liveness stays here (`docs/procedure/gate-8.md`).
   - **Cost, measured not assumed:** **119 min 26 s, measured on MES-174 (31981) at 1790 tests**, all of it on the
     critical path of whoever runs it. That is why it is a cadence check and not a
     per-ticket gate, the same reasoning gate 6's applicability rule uses.
   - **A verdict that has drifted fails loudly**, naming the direction, the old and
     new verdict, and the ET-CC register rows it would move. Like an advisory, it
     becomes a **Jira ticket** — it is not fixed in place.

   **The three-condition skip, and all three conditions are required.** The sweep may be
   skipped only when **all three** of these come back clean at the sprint's final tip:

   ```bash
   # (a) no lib/ change since the last sweep tip -- THREE dots, per the gate-6 rule
   git diff --name-only <last-sweep-tip>...HEAD -- lib/

   # (b) no change to the UNIT POPULATION since the last sweep tip
   git diff --name-only <last-sweep-tip>...HEAD -- test/ test/support/ conformance/lib/

   # (c) this HOST is the host the committed table was measured on. Exits 0 on a match
   #     and 1 otherwise; prints both fingerprints either way. Seconds, no sweep.
   mix conformance.sweep --host
   ```

   **Either diff non-empty, or `--host` nonzero ⇒ run the sweep.** Condition (b) is not
   belt-and-braces. L1 — the liveness proxy — quantifies over the **suite**, not over
   `lib/`, so a **test-only** change moves a verdict in either direction: a new unit
   outside a dead direction's own-tests that reddens under its mutation raises the live
   count above zero (dead → live), and deleting the last such unit drops it to zero,
   firing L2's mechanical trigger (live → dead). *"`lib/` unchanged ⇒ no verdict moved"*
   is **unsound**, and it was in use here until MES-88 measured the population moving
   **979 → 1021 with `lib/` byte-unchanged**. This is ratified criterion, not local
   practice: `docs/conformance/etcc-membership.md` §2.3(e) as extended,
   `[authored 26988 | ratified 26995]`.

   **Condition (c) exists because (a) and (b) are `git diff`s and the population is not a
   function of the repository.** `test/test_helper.exs` excludes the three
   `:requires_live_harness` conformance tests where `node` or the pinned harness is
   absent — deliberately, per MES-56, because a silent skip reads absence as
   satisfaction. Measured on MES-88 at **one unchanged tip, with (a) and (b) both
   empty**: `13 doctests, 1021 tests, 0 failures` with `node` on PATH and
   `13 doctests, 1018 tests, 0 failures (3 excluded)` without. Two conditions alone would
   therefore permit a skip on a host whose population is not the one the verdicts were
   taken on, and **both commands would print nothing while it happened**. `--host`
   compares this host's fingerprint against the one the committed table's generated
   `control` block records, and is **fail-closed**: it refuses the skip when the
   fingerprints differ, when no host is recorded, and when the current one cannot be read.
   "I could not tell" means *run the sweep*. Shown firing — on a real host difference,
   not a fabricated string — by
   `mix run conformance/controls/etcc_boundary_sweep_controls.exs host`.

   **Record the result in `docs/sprint_{N}_issues.md`, including a skip** — with all
   three commands and all three outputs, **the host fingerprint among them**, not just
   the conclusion. "Checked, and zero" and "never asked" read identically when only the
   answer is printed; and "checked, and zero" without the host does not say *where* it
   was zero.

   **What this cadence gives up, stated because a rule that states only its benefit is
   not honest.** Between sprint boundaries a merged `lib/` change can rot a verdict and
   nothing notices — guard 19 goes on passing over the rotted table, which is the exact
   failure MES-88 was raised for, merely **bounded to one sprint instead of forever**.
   That is a bound, not a guarantee. The trade is taken because a ~2-hour gate on a
   ticket that touches no `lib/` file yields no information about the work under review,
   and because a verdict that rotted mid-sprint is not the reviewing seat's to fix.

   **And what condition (c) does not do.** It makes a *skip* answer for the host. It does
   **not** stop a sweep being **run** on a host where the exclusion fires: that run
   measures 1018 units instead of 1021 and records a table taken over the smaller
   population. That is now **visible rather than silent** — `control.host` records
   `harness=unavailable` and every `suite_summary` carries `(3 excluded)` — and the next
   `--host` refuses a skip against it, so it cannot propagate. Whether the sweep should
   additionally **refuse** an incomplete host, the way `CLAUDE.md` already says a run
   reporting "3 excluded" is not a complete gate 5, is a policy question and is not
   settled here.

5. **Publication sweep** (added by MES-95; run point (c) of the push rule, D8).
   Run `mix origin.sync` against `main` at the sprint's final tip and record its
   output in `docs/sprint_{N}_issues.md`.

   - **Never skipped, and it has no applicability rule.** It costs seconds and is
     read-only. The question it answers — *is what we hold what we published?* — is
     a function of `origin` and wall-clock, not of what any ticket changed, so no
     diff over the sprint's commits can excuse it. That is the same reason the
     dependency sweep at step 2 ignores the gate-6 applicability rule.
   - **Record it, including a clean one.** "Checked, and zero" and "never asked"
     read identically when only the answer is printed.
   - **A red becomes a Jira ticket only if the remedy is more than the push.**
     Ordinarily it is not: `git push origin main` and the missing tag close it on
     the spot, and the finding belongs in the sprint's register as a lapse of the
     merge gate. A red that the push does **not** fix — C3, C4-as-different-object
     or C5 — is a damaged tag or a rewritten `main`, and that is a ticket.

**Relationship to release.** A release only ever follows a completed sprint — never
mid-sprint. So this sweep is always upstream of any release, and no release can ship
on advisory data older than the last sprint boundary. It does **not** replace MES-19's
whole-tree OSV cross-check at release: `hex.audit` reads the **local registry cache**
and OSV queries a **live external feed**, so the two fail differently and neither
subsumes the other. Both, in that order.

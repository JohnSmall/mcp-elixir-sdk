# Sprint 19 — findings register

**Sprint goal, as set at planning on 2026-11-15.** Sprint 19 is Jira sprint 2289 on board 267.
Its planning page is Confluence 362676245. The PO completed Sprint 18 (2280) on 2026-11-15 and
moved MES-214 into this sprint. The PO approved the plan in session the same day (Q1–Q3, all YES):

- MES-239 runs as its own ticket before MES-231, linked "MES-239 blocks MES-231".
- The list, all in epic MES-118: MES-239, 231, 234, 236, 240, 241, with MES-214 as the stretch item.
- acm problems go on a new ACM ticket, now that ACM-38 is closed: **ACM-49**.

> Rebuild the ET-CC register so keysets and reproduce are green at main; make G30 green again; run
> gate 7 on mix.lock-only changes; add a sprint-end re-capture and a per-ticket reproduce check.

**Start state.** main = origin/main = `c7979b3`, `2.0.0-dev.118`.
- The `keysets` and `reproduce` controls in `conformance/controls/etcc_register_controls.exs` are
  red at main until MES-231 ("state B", PO-approved at the MES-230 merge).
- G30 (`crosswalk_controls.exs statements`) is red at main until MES-234.
- No DoD gate is red.

## Size survey at `c7979b3` (before the list was drafted)

| ticket | measured |
|--------|----------|
| MES-239 | 17 decisions with an `MCP.Transport.SSE (decode)` boundary carry no MES-230 hop-2 adjudication: SSETest 11, SSEDispatchTest 2, SSELineEndingsTest 3, SubscriptionsStreamTest 1. Excluding the MES-230 G2 units is part of the plan hop |
| MES-231 | A trial rebuild via `ETCCRegister.write/1` gives 579 → 811 rows: the 232 MES-230 rows, with 0 existing rows changed (sorted-row diff 232 lines). The G33 ledger holds **21** `held` (attribution_citations) cites in `etcc-attribution.md`, against the brief's "87", which comes from MES-194 comment 32781; to be reconciled at the plan hop. It also holds 7 `stale` cites owned by MES-194 |
| MES-234 | `crosswalk_controls.exs statements` still refuses: G30, 14 quoted byte-strings |
| MES-236 | The gate 7 applicability text in `CLAUDE.md` and `docs/procedure/gate-7.md`, and the `oc_gate` task's own path match |
| MES-214 | 38 mutation records carry a `reddens` field: D1-server-i 9, D1-server-ii 13, D1-server-iii 16 |

## Findings

(none yet)

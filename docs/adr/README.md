# Architecture Decision Records (ADR)

Register of architectural decisions for **MCP_Elixir_SDK** (Jira key MES).
WP pin Global v2 · Methodology pin Global v1.

## Convention

- **Canonical location:** this directory, `docs/adr/NNNN-title.md`, so decisions travel with the code
  and are reviewed like code. **The repo files are the source of truth**; the Confluence ADR pages are
  the drafting/ratification surface and the human-readable mirror.
- **One decision per record.** Keep them short: context, the decision, why, consequences, alternatives.
- **Status lifecycle:** `Proposed` → `Accepted` → (later) `Superseded by ADR-NNN` / `Deprecated`.
- **An ADR is a Product-Owner decision.** The Active-sprint PM drafts; the PO accepts. Weighty adoption
  decisions (e.g. a spec-version migration) are framed with the affected consumer (EMFA) in the loop.

## Register

| ADR | Title | Status | Supersedes | Superseded by |
| --- | --- | --- | --- | --- |
| [ADR-001](0001-target-2025-11-25-defer-2026-07-28.md) | Target MCP spec revision 2025-11-25 only; defer 2026-07-28 | Accepted (retroactive) · **deferral superseded** | — | ADR-002 (deferral only) |
| [ADR-002](0002-adopt-2026-07-28-stateless-core-migration.md) | Adopt MCP 2026-07-28; migrate transport to the stateless core (2.0.0) | **Accepted** (2026-07-20) | ADR-001 (the deferral) | — |

**Next ADR number: ADR-003.**

ADR-002 supersedes **only the deferral** in ADR-001, not the whole decision: ADR-001's choice to _ship_
1.1.0 against 2025-11-25 stands and is already released. ADR-002 governs what comes next — adopt
2026-07-28, package-level cutover to 2.0.0, EMFA rides the migration.

Confluence mirror: [ADR register](https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/232980491)
· [ADR-001](https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/232194078)
· [ADR-002](https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/232620042).

## Verification notes

Before landing these records, CC independently verified the MCP 2026-07-28 release-candidate specifics
quoted in ADR-002 against the upstream authoritative surfaces — the spec **changelog**
(`modelcontextprotocol.io/specification/draft/changelog`) and the individual **SEP pull requests** in
`modelcontextprotocol/modelcontextprotocol`, plus the C# `2.0.0-preview` release notes. The ADR text is
landed **as ratified**; nothing below was silently edited. Items flagged here are for PM/PO to reconcile.

**Confirmed against the upstream changelog / SEP PRs (exact matches):**

| Claim in ADR-002 | Upstream source | Result |
| --- | --- | --- |
| `initialize`/`initialized` handshake removed — **SEP-2575** | Changelog major #2; PR title "SEP-2575: Make MCP Stateless" | ✅ Confirmed |
| Session state / `Mcp-Session-Id` removed; state handles — **SEP-2567** | Changelog major #1 (server-minted handles as tool args) | ✅ Confirmed |
| Multi Round-Trip Requests / `InputRequiredResult` — **SEP-2322** | Changelog #7–8 | ✅ Confirmed |
| Extensions framework — **SEP-2133** | PR title "SEP-2133: Extensions framework for MCP" | ✅ Confirmed |
| Conformance gate: Standards-Track SEP → Final needs a conformance scenario — **SEP-2484** | PR title "SEP-2484: Require Conformance Tests for Standards Track SEPs to Reach Final Status" | ✅ Confirmed |
| `HeaderMismatch -32020`, `MissingRequiredClientCapability -32021`, `UnsupportedProtocolVersion -32022` | Changelog minor #12 (`-32001→-32020`, `-32003→-32021`, `-32004→-32022`) | ✅ Confirmed (target codes exact) |
| missing-resource `-32002` → `-32602` | Changelog minor #6 | ✅ Confirmed |
| RC locked 2026-05-21; final publishes 2026-07-28 | RC blog post | ✅ Confirmed |
| C# reference SDK keeps both eras / negotiates down to the legacy handshake (basis for the deliberate divergence in sub-decision 5) | C# `2.0.0-preview` release notes | ✅ Confirmed (directionally) |

**Discrepancy raised and now RESOLVED (corrected in the ADR, not waived):**

- **"22 SEPs" total count** (originally in ADR-002 Context, sub-decision 4, Consequences, Next steps —
  four places). CC's landing-verification pass could not substantiate the total against any authoritative
  source: the 2026-07-28 RC blog post, the SDK-betas post, and the changelog give no headline "N SEPs"
  figure (the RC post references ~20 distinct SEPs). A PM re-check confirmed no official total is
  published. **Actioned by the PM with PO approval (2026-07-23):** the unsupported count was removed and
  replaced with accurate framing — stateless core = six SEPs, authorization hardening = a further six,
  plus extensions/lifecycle/routing/caching/trace-context/error-code changes — pointing to the
  authoritative inventory (draft changelog "Key Changes" + the [SEP index](https://modelcontextprotocol.io/seps));
  sub-decision 4 was reworded to "the revision in its entirety, not a subset." Newly-confirmed anchors
  (SEP-2164, SEP-2243, SEP-2260, SEP-2577/2596, SEP-414) were folded in. Repo copy re-synced from
  Confluence v3; see the ADR's own **Amendment log**. **No sub-decision, scope, or version choice
  changed.**

No objective typos were found in any SEP number or error code — all specific anchors matched upstream
exactly, so no corrections were applied.

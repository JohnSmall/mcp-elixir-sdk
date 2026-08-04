# Sprint 4 — Issues and Decisions log

Per Overrides **A8**, this file is a **gated deliverable** in every Sprint 4 ticket's DoD
(not an afterthought — closes the I14 gap where Sprint 3's issues file lapsed for four
tickets). Entries are appended per ticket. Canonical narrative lives on the ticket's
Confluence child pages (Rule #10); this file is the repo-side surfacing (Rule #8).

---

## MES-13 — Conformance baseline measurement + schema re-pin (2026-08-03)

### Issue: Two conformance-suite artefacts disagree on version
**Description:** `/workspace/samples/mcp-conformance/` is a git checkout at tag **v0.1.13**
(`git -C /workspace/samples/mcp-conformance log -1` → `a1b8aaae … 2026-02-05`), while
`npx @modelcontextprotocol/conformance` resolves the **npm-published latest = 0.1.16**
(`npm view @modelcontextprotocol/conformance dist-tags` → `{ latest: '0.1.16', alpha:
'0.2.0-alpha.10' }`). Two artefacts, same name, different versions — the Sprint 3
divergence class (evidence-log I2). All MES-13 measurement used **npm 0.1.16** (matching
MES-7), pinned explicitly on every invocation; the samples checkout was not used.
**Recommendation:** When a future ticket runs the harness, pin the npm version explicitly
and record it; do not run the samples checkout without stating its version.
**Priority Hint:** Low · **Blocking?:** No · **Suggested Jira Ticket?:** No (hygiene)

### Issue: Conformance adapters are pinned to 2025-11-25 and cannot exercise the stateless core (C3)
**Description:** `conformance/server_adapter.exs` sets `protocol_version: "2025-11-25"`, and
`conformance/server_handler.ex` references **removed** APIs
(`MCP.Server.ToolContext.request_sampling/2`, `request_elicitation/2` — the held-open
server→client path deleted for MRTR, SEP-2322; compiler emits "undefined or private"
warnings). `conformance/client_adapter.exs` routes only `initialize`/old `tools-call`.
Against the 2026-07-28-only SDK the 0.1.16 baseline is therefore near-total old-revision
failure by design (server **1 pass / 31 fail** of 32 scenarios — only version-agnostic
`dns-rebinding-protection`; client full suite **1 pass / 55 fail** of 26 scenarios — only
the out-of-scope `auth/resource-mismatch`, ADR-003 #3 — see D1). The adapters can drive the
old suite but not a 2026-07-28 suite.
**Owner + trigger (C3):** adapter rework is **out of MES-13 scope** (analysis ticket; the
rework is contingent on the alpha finding below). **If** a 2026-07-28 conformance suite is
adopted (the alpha, or its eventual stable release), adapter rework — 2026-07-28
server/client adapters + a refreshed `server_handler.ex` using MRTR — **becomes a named
Sprint 4/5 ticket**; **if not**, it stays deferred and the 2.0.0 claim is worded per
ADR-003 sub-decision 6. The PM carries this decision at **MES-19 planning**.
**Priority Hint:** Medium · **Blocking?:** No (for MES-13) · **Suggested Jira Ticket?:** Yes (conditional)

### Decision/Finding: a 2026-07-28 conformance suite now exists — but only as a pre-release alpha (C2)
**Description:** `latest` (0.1.16) carries **zero** 2026-07-28 scenarios — its version
universe tops at 2025-11-25 (`list --spec-version 2026-07-28` → *"Unknown spec version …
Valid versions: 2025-03-26, 2025-06-18, 2025-11-25, draft, extension"*). The **pre-release
`0.2.0-alpha.10`** however carries a full 2026-07-28 surface: **40 core server** scenarios
(incl. `server-stateless`, 14× `input-required-result-*` (MRTR), `caching`,
`http-header-validation`, `http-custom-header-server-validation`, `sep-2164-resource-not-found`)
and **7 core client** scenarios (`request-metadata`, `sep-2322-client-request-state`,
`http-standard/custom/invalid-tool-headers`, `json-schema-ref-no-deref`), plus 25 auth-profile
(out per ADR-003 #3) and 16 Tasks-extension (out per ADR-003 #2) scenarios.
**Consequence:** a harness-based 2.0.0 conformance claim is now *possible* — but only via a
**pre-release alpha**, and only after adapter rework (above). Whether a pre-release alpha is
an acceptable basis for the published claim is a **PO/PM call at MES-19**. Absent that, the
claim rests on our ported acceptance evidence and says so (ADR-003 #6). This supersedes the
Sprint-3/MES-7 understanding that the revision was "labelled draft only, no dated schema."
**Priority Hint:** High (shapes MES-19/Sprint 5) · **Blocking?:** No · **Suggested Jira Ticket?:** Yes (MES-19 input)

### Finding: schema pin re-verification surfaced stale line citations in `mrtr.ex` (A4)
**Description:** Re-pinning to the published-final schema (D4) required verifying the cited
line numbers at the pinned commit. `lib/mcp/protocol/messages/discover.ex` and
`elicitation.ex` citations resolved correctly; **`mrtr.ex`'s did not** — it cited `Result`
at `schema.ts:658` (actual `:223` at the pinned commit), `InputRequiredResult` at `:1253`
(actual `:584`), etc. The numbers resolved to neither the pinned draft commit nor 2025-11-25.
Corrected as part of the re-pin (comment-only, symbol names unchanged and independently
verified). This is exactly the drift A4 (schema-level verification, cited to a pinned
commit) exists to catch.
**Recommendation:** Keep A4's file+line citations in the DoD; the symbol-name anchor is what
makes them re-verifiable when the schema shifts.
**Priority Hint:** Low · **Blocking?:** No · **Suggested Jira Ticket?:** No (fixed here)

### Finding: MES-18 (client conformance) is bounded to one ticket — the "1/42" fear is stale (D3)
**Description:** The only client figure on record was **1/42 against 2025-11-25** (a 1.1.0
artefact). The **current** client (`main` @ `2c9a71a`) already carries the stateless-core
migration: `server/discover` probe, MRTR (`input_required` detect + `on_input_required`
resolver + retry with `requestState`/`inputResponses`), per-request `_meta` with the three
fully-qualified `io.modelcontextprotocol/*` keys, and new error-code awareness. The residual
client gap (D3): **CG1** client transport omits `Mcp-Method`/`Mcp-Name` on POST (SEP-2243,
a direct FIX — our own server validates them); **CG2–4** client-side wiring of the
extensions-negotiation, `subscriptions/listen`, and JSON-Schema-2020-12 surfaces that
MES-16/15/17 add (hence the dep graph MES-15/16 → MES-18); **CG5–6** client cache-honoring
and trace-context `_meta` (SHOULD, deferrable).
**Recommendation:** Ratify MES-18 as one ticket scoped to CG1 + client-side wiring of the
MES-15/16/17 surfaces, gated on those tickets. No split required; no A1 escalation (R4).
**Priority Hint:** Medium · **Blocking?:** No · **Suggested Jira Ticket?:** Sizes MES-18

### Discipline instance (A2c): D1's first "client 0" was scoped narrower than its claim
**Description:** D1 initially reported the client baseline as "**0**", but the backing check
was an `initialize`-only repro, not a full client-suite run — a claim scoped wider than the
check that supported it (Overrides **A2c**). Codex review (252182550, F1) caught it. The
**full** client suite (`client --suite all`) reports **1 passed / 55 failed** across 26
scenarios; the single pass is the **out-of-scope** `auth/resource-mismatch` (ADR-003 #3), so
the 2026-07-28-core client denominator remains **0**. Also corrected: stable-suite totals are
**32 server / 26 client** (not 33 / 27), and `tools-call-*` is **10** server scenarios (not 9).
**Recommendation:** A summary figure must be backed by the run it summarises — a
single-scenario repro evidences the mechanism, not the baseline. Keep A2c in the reviewer's
checklist.
**Priority Hint:** Low · **Blocking?:** No · **Suggested Jira Ticket?:** No (fixed here)

### Forward finding (F4): the final schema's `subscriptions/listen` envelope differs from the draft — MES-15 must build against the final
**Owner:** **MES-15** (`subscriptions/listen` implementation).
**Final schema target:** MES-15 builds against
`5f5440bb26a62e2cf3440b92da5a667efa03b267:schema/2026-07-28/schema.ts` **only** (the pinned
published-final revision). The old draft snapshot `7634684382c3d14cf7e9f14073fe40a2d8ace3fa:schema/draft/schema.ts`
is superseded and must not be used.
**Re-check instruction:** the final schema's `subscriptions/listen` **result envelope and type
names differ from the draft** (interface rename + a new response-envelope interface). Any design
sketch or prior reading based on `schema/draft/schema.ts` **must be re-checked against the final
schema before implementation** — this is precisely the surface the D4 re-pin moved.
**Evidence (Note C — literally reproducible; 6 hunks total, the two below are the
`subscriptions/listen` ones; the four `_meta` doc-link path changes are omitted):**

```
$ git clone --filter=blob:none --no-checkout \
    https://github.com/modelcontextprotocol/specification.git && cd specification
$ git diff 7634684382c3d14cf7e9f14073fe40a2d8ace3fa:schema/draft/schema.ts \
           5f5440bb26a62e2cf3440b92da5a667efa03b267:schema/2026-07-28/schema.ts

@@ -1323,7 +1323,7 @@ export interface SubscriptionsListenRequest extends JSONRPCRequest {
  * @see {@link MetaObject} for key naming rules and reserved prefixes.
  * @category `subscriptions/listen`
  */
-export interface SubscriptionsListenResultMeta extends ResultMetaObject {
+export interface SubscriptionsListenResultMetaObject extends ResultMetaObject {
   /**
    * Identifies the subscription stream this response closes, so the client can
    * correlate it with the originating subscription — mirroring the same key on
@@ -1347,7 +1347,20 @@ export interface SubscriptionsListenResultMeta extends ResultMetaObject {
  * @category `subscriptions/listen`
  */
 export interface SubscriptionsListenResult extends Result {
-  _meta: SubscriptionsListenResultMeta;
+  _meta: SubscriptionsListenResultMetaObject;
+}
+
+/**
+ * A successful response from the server for a {@link SubscriptionsListenRequest | subscriptions/listen}
+ * request, sent when the server tears the subscription down gracefully.
+ *
+ * @example Subscription closed gracefully response
+ * {@includeCode ./examples/SubscriptionsListenResultResponse/listen-closed-response.json}
+ *
+ * @category `subscriptions/listen`
+ */
+export interface SubscriptionsListenResultResponse extends JSONRPCResultResponse {
+  result: SubscriptionsListenResult;
 }
```

**Net for MES-15:** the result-meta interface is renamed `SubscriptionsListenResultMeta` →
`SubscriptionsListenResultMetaObject`, and a new `SubscriptionsListenResultResponse` (extends
`JSONRPCResultResponse`, wraps `SubscriptionsListenResult`) is added — the graceful-teardown
response envelope. Model the wire shape against these final names.
**Priority Hint:** Medium (gates MES-15's schema-level DoD) · **Blocking?:** No (for MES-13) · **Suggested Jira Ticket?:** MES-15 input

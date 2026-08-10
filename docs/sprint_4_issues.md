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

---

## MES-14 — Notification plumbing hardening: request-local collector + config-time cache-scope warning (2026-08-04)

Canonical narrative: in-flight exchange [254541825], /plan [254902274], PM ratification
[254345238] (RATIFIED WITH CONDITIONS C1–C5). Branch `MES-14` off `da1fe64`.

### Decision: process-dictionary notification collector replaced by a per-request process (AC1/AC2/AC8)
**Description:** The HTTP driver's notification collector was a process-dictionary slot
(`@notifications_key` in `plug.ex`) — a process-keyed store that, because request processes
are reused, the *next* request could address. That is the Sprint 3 cross-request identity
leak (evidence-log I10); MES-10 Ruling 7 held it shut with a start-clear + `try/after`
stopgap. Replaced with `MCP.Server.NotificationCollector`, a small per-request process whose
pid is held only by that request's `reply_sink` closure on `ctx`. A later request holds no
reference by which it could name a prior collector, so residue is **unaddressable, not merely
cleared** — the AC2 property (amended at ratification C1 from "call-frame-lifetime-bounded"
to "reachability-bounded", since Elixir has no mutable stack-local cell). The Ruling 7 stopgap
was removed in the same diff (AC8); its removal is justified by the AC1–AC4 evidence.
**Resolution:** New module `lib/mcp/server/notification_collector.ex`; `dispatch/5` rewritten;
`@notifications_key`, `notification_collector/0`, `take_notifications/0` deleted.
**Priority Hint:** n/a (ticket scope) · **Blocking?:** No · **Suggested Jira Ticket?:** n/a

### Decision: AC4 negative direction demonstrated before implementation (ratification C2)
**Description:** A by-construction mechanism resists being made to fail, which is in tension
with A7's fail-then-pass requirement. Per C2, the reverted (leaky) state was defined and the
AC3 SSE-level regression made to fail **before** writing implementation code: the reverted
state is `dispatch/5` with the two Ruling-7 guards removed (restoring proc-dict cleanup on
the normal branch only), not "delete the new collector" (which would be a compile error, not
a leak). The test executes against that state without a shim (it asserts on `resp_body`, not
collector internals). Observed failure — REVIEWER's request 2 received PM's
`notifications/message` with `"data":{"identity":"PM"}` — pasted on the in-flight page.
**Priority Hint:** n/a · **Blocking?:** No (discharged) · **Suggested Jira Ticket?:** n/a

### Finding: E1 cache-field reality matches the gap register (ratification C4)
**Description:** Gap-register E1's `ttlMs`/`cacheScope` are produced today via
`MCP.Server.Dispatch.cacheable/2` (default `{0, "public"}`) on the five CacheableResult
methods (`tools/list`, `resources/list`, `resources/read`, `resources/templates/list`,
`prompts/list`); `cacheScope ∈ {public, private}` via `:cache_defaults`. Established from
code with `git grep` widened repo-wide over `lib/` (C4): the only additional production site
is `discover.ex` (client-side parse of the same fields). Reality does not differ from E1 — no
A1 escalation. Cache-field *emission* semantics remain out of scope; MES-14 only adds a
config-time warning about a risky *configuration* of the existing fields (AC7).
**Priority Hint:** n/a · **Blocking?:** No · **Suggested Jira Ticket?:** n/a

### Finding: AC7 warning surfacing under real deployment shapes (ratification C3)
**Description:** The config-time cache-scope warning is emitted from `Plug.init/1`, so it
fires once per configuration, never per request (AC7c is structural — `call/2` has no path to
it). C3 asked where it actually surfaces. Established empirically: `Bandit.start_link(plug:
{Module, opts})` — this SDK's documented deployment — calls `init/1` at **server startup**,
so the warning reaches the runtime log (test: "C3: warning reaches the runtime log when
started via Bandit plug: {Mod, opts}"). A module-based pipeline mounted with
`plug_init_mode: :compile` (a Phoenix production default) runs `init/1` at compile time, so
the warning would land in the build log; documented in the `Plug` moduledoc with the remedy
(`plug_init_mode: :runtime`, or the Bandit `plug: {Module, opts}` form). The warning surfaces
for the documented shape → discharged without escalation, with the caveat documented.
**Priority Hint:** Low (doc caveat) · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Note: `da1fe64` provenance (ratification C5)
**Description:** The ADR-003 landing-status correction (`da1fe64`) is a ticketless docs-only
commit with no /plan or review; the PM's independent verification was rate-limited. Provenance
posted on the in-flight page: `git log -1 --format='%H %s' da1fe64` and `git show --stat` —
one file (`docs/adr/0003-2.0.0-conformance-scope.md`), +4/−3. Carried onto Codex's MES-14
review checklist.
**Priority Hint:** n/a · **Blocking?:** No · **Suggested Jira Ticket?:** n/a

### Defect found in review: collector start failure broke MC-6 (correction round 1, 2026-08-05)
**Description:** `plug.ex` started the per-request notification collector with an unguarded
match — `{:ok, collector} = NotificationCollector.start_link()`. A start failure raised
`MatchError` instead of taking the controlled JSON-RPC internal-error path, so **MC-6 (clean
failure) was not satisfied** — while the /plan §2 MC-6 row and the close-out's AC5 both
reported it satisfied. AC5 was the one acceptance criterion discharged by narrative rather
than an executable check (PM finding V6); it was the one that carried a false claim. Codex
demonstrated the crash by injecting `{:error, :collector_start_failed_for_review}`.
**Resolution:** collector start moved into the `handle_post/2` with-chain via
`start_collector/1`, which maps `{:error, reason}` to `{:error, {:collector_start_failed,
reason}}`; the else clause logs the reason server-side and returns a controlled `-32603`
("notification collector unavailable") with **no handler invoked** and no internal detail in
the client body — after identity resolution, before dispatch. An injectable `:collector_start`
seam (0-arity, defaults to `&NotificationCollector.start_link/0`) turns Codex's manual
injection into a **permanent** regression test (A7): shown FAILING against the reverted
unguarded match (`MatchError` at `start_collector/1`) and passing after the fix.
**Lesson:** an AC backed by prose survived to review; every AC backed by a command did not.
A2 is not ceremony (→ the point behind the newly codified A2d: grouped/narrative claims hide
real items). Diff figure also reconciled: the committed `9522ef7` is **431 insertions / 46
deletions** over 7 files (two-dot and three-dot agree, merge-base is `da1fe64`); the close-out's
"+419" was measured before the final amend that added a 12-line test and was not refreshed.
**Priority Hint:** n/a (in-ticket correction) · **Blocking?:** Was (merge-gate) — resolved · **Suggested Jira Ticket?:** n/a

---

## MES-26 — Dependency advisory audit (2026-08-08; corrected 2026-08-09)

Read-only audit on `main` @ `9a233c0` (tag `2.0.0-dev.2`), per PO policy Overrides A11.
**Corrected 2026-08-09 (correction round 1)** in response to Codex REJECT (257523725): the
`bandit` target moves 1.11.1 → 1.12.1 (1.11.1 is itself advisory-bearing). Canonical
deliverable: MES-26 audit page (257818626, v2 + correction-response child). `mix.lock` sha256
`957e291a7a61f98e77aef4d12e241a5c8d017913369c330cd2e98e9e44878f9e` unchanged before/during/
after the audit, cycle-1 and correction-round (C4) — no dependency mutated. **Nothing was
remediated; this ticket measures.**

### Finding: affected set = 5 packages / 22 advisories (enumerated, not counted — C1)
**Description:** `mix hex.audit` (hex 2.5.0) reports advisories against `req` (2), `plug` (4),
`bandit` (7), `hpax` (1), `mint` (8) — **22 total, by counting rows**. The /plan's §0.1 stated
counts summed to 20 (plug written as 3, bandit as 6); the enumerated ids are 4 and 7. Corrected
here and in the deliverable per A2d. Denominator matches Codex's incidental five packages, now
verified by full enumeration.

### Finding: a clearing version exists for every advisory (branch (a) covers all — field 6)
**Description:** Lowest **clean** targets (≥ every fixed event AND itself advisory-free):
`req` 0.5.17→**0.6.1** (0.x minor); `plug` 1.19.1→**1.19.5** (patch, within 1.19.x);
`bandit` 1.10.2→**1.12.1** (minor); `hpax` 1.0.3→**1.0.4** (patch, transitive); `mint`
1.7.1→**1.9.3** (minor, transitive; allowed by finch `~> 1.7`, no override). A11 branch (b)
is therefore **not required by this remediation**; it is a forward concern only.
**Correction (round 1):** the earlier `bandit` target 1.11.1 cleared the 7 locked advisories
but is itself advisory-bearing — EEF-CVE-2026-65623 (GHSA-vg8x-66vg-5pxh) affects bandit from
1.11.0 before 1.12.1 (i.e. 1.11.0, 1.11.1, 1.12.0). Lowest clean target is **1.12.1** (1.11.1
and 1.12.0 both rejected; verified lowest, not merely clean — A6-2). 65623 does **not** affect
locked 1.10.2, so `mix hex.audit` correctly omits it and the locked-tree denominator stays 22
(A6-5).

### Finding: bandit's clearing bump moves behaviour under the HTTP/SSE surface (trigger 2 — strengthened)
**Description:** bandit 1.10.2→**1.12.1** (corrected endpoint) changelog (verbatim), every
intervening release: 1.10.3 "Improve http2 sendfile streaming" / "Detect client disconnect on
timeout"; 1.10.4 `{:shutdown, :disconnected}` WebSocket result code; 1.11.0 `max_frame_size`
default `:infinity`→8MB, new `max_inflate_ratio`/`max_fragmented_message_size`, "Zero length
non-fin continuation frames are now disallowed", "Multiple content-length fields in an HTTP/1
request are now disallowed"; 1.11.1 "large chunked request bodies" + "request trailers"; 1.12.0
"Incorporate changes from Thousand Island 1.5, improving the separation of local GenServer
timeouts and network facing timeouts" + mixed-case Transfer-Encoding + HTTP/1 body-read
internals; 1.12.1 fragmented-WebSocket DoS fix (CVE-2026-65623). These sit directly beneath the
transport MES-15 builds a long-lived SSE stream on. **Sequencing trade-off for the PM→PO
(A11/AC4): bandit remediation should precede MES-15, or MES-15 must build against post-1.12.1
behaviour.** More transport behaviour moves than the cycle-1 read showed, so the conclusion is
**strengthened**. plug 1.19.5 is a low-risk patch; mint's streaming change is client-side; hpax
is a pure fix. **Trigger 2 read from the changelog, not pre-judged.**

### Finding: the corrected resolved tree is clean (A6-1 — thousand_island)
**Description:** bandit 1.12.1 requires `thousand_island ~> 1.5`; locked is 1.4.3, which would
resolve to **1.5.0** under the corrected target — a version never in the 22-advisory
denominator. OSV lists **no advisories** for `thousand_island` (checked 2026-08-09), so 1.5.0 is
clean. No other package's resolved version changes because of the bandit bump, and no new
package is introduced (plug/hpax already in the remediation set; websock `~> 0.5` unchanged).
Determined by constraint analysis + OSV — **no resolver run, `mix.lock` untouched (T4 clear)**.
A clean-target check is not a clean-tree check; the tree is clean. **T3 does not fire.**

### Finding: trigger 1 corrected — the ignore mechanism exists in hex ≥ 2.5.1, not only in mix_audit
**Description:** The /plan asserted "no ignore mechanism in the runnable tool." Corrected: hex
**2.5.1** (changelog 2026-07-09) added `ignore_advisories`/`ignore_retirements` in the `mix.exs`
`:hex` block (or `HEX_IGNORE_ADVISORIES`/`HEX_IGNORE_RETIREMENTS` env vars). The installed hex
is **2.5.0** — one patch behind — so branch (b) is unavailable *as installed*, but a **hex
toolchain upgrade to ≥2.5.1 (developer/CI, not a project dependency, not in the 2.0.0 artefact)**
supplies it natively — cheaper than adopting `mix_audit`. Trigger 1's substance (policy has one
usable branch on the installed toolchain today) holds; the remedy is trivial. Escalated to PO.

### Finding: the two gate tools' advisory data sources cannot be shown equal or different from docs (C2)
**Description:** `mix_audit` documents its source ("elixir-security-advisories repository hosted
on GitHub"). `mix hex.audit` names **no** source in its task docs or the hex CHANGELOG (both
"SOURCE NOT NAMED"). Advisories carry `EEF-CVE-*` ids (Erlang Ecosystem Foundation) with
osv.dev links — circumstantial, not a documented-source quote. **Per C2, no equivalence or
difference is asserted.** If the PO needs denominator certainty for the gate-tool choice, it
requires empirically running both tools (needs installing `mix_audit` — remediation scope).

### Note: severity labels differ between hex.audit and osv.dev for five advisories (C2-adjacent)
**Description:** hex.audit vs an osv.dev CVSS-vector reading diverge on qualitative severity for
`req`-49756, `plug`-56813, `bandit`-42788, `mint`-48861, `mint`-59246. The deliverable reports
hex.audit's label (gate tool of record) plus the osv CVSS vector verbatim, asserting no label of
its own. Evidence that source choice affects classification, not only membership.

### Gate command (AC5) — established, not added
**Description:** `mix hex.audit` is available (hex 2.5.0), read-only, **exits 1 today**. `mix
deps.audit` (`mix_audit`) is **not installed** (`task could not be found`). The dependency-audit
gate lands with the MES-25 remediation, never before (A9/A11.5) — a gate failing on `main`
blocks every subsequent DoD.
**Priority Hint:** n/a (analysis) · **Blocking?:** No · **Suggested Jira Ticket?:** remediation under epic MES-25 (bandit before MES-15); dependency-audit gate = MES-27; hex ≥2.5.1 upgrade for branch (b) = MES-28; PO decision on gate tool

### Note: this close-out commit has no independent reviewer (CO-3 / PA-2)
**Description:** This `[MES-26]` docs-only commit lands **after** Codex's ACCEPT (re-review
260505601), so nothing independently verifies it — the same class as the ADR ticketless
landings and `da1fe64`. Per the interim D1 remedy (PA-2), it goes onto **MES-28's reviewer
checklist**, which must confirm: single-parent; subject `[MES-26] <title>`; **exactly two
paths** (`docs/sprint_4_issues.md` and `.gitignore`); **no version bump; no tag**; `mix.lock`
untouched. **Third demonstration of PA-2** (after the ADR-001/002/003 landings and `da1fe64`
verified at MES-14). The `.gitignore` change adds `node_modules/` and `package*.json` (Codex's
tooling, left on disk, now ignored).
**Priority Hint:** n/a (process) · **Blocking?:** No · **Suggested Jira Ticket?:** MES-28 reviewer checklist

---

## MES-28 — hex archive upgrade 2.5.0 → 2.5.1 (make A11 branch (b) implementable); advisory delta (2026-08-10)

Toolchain-only + measurement, per PO ruling 2026-08-06. Deliverable: MES-28 deliverable
(child of in-flight 261029889); ratified /plan 259817542 (C1–C6). Read at `main` @ `f900111`.
`mix.lock` sha256 `957e291a7a61f98e77aef4d12e241a5c8d017913369c330cd2e98e9e44878f9e`
**unchanged before/during/after** (guarded around the upgrade and every audit run — T2 clear).
No `mix.exs` deps change, no version bump, no tag (D4 toolchain-only). No advisory was
ignore-listed (branch (a) covers all 22).

### AC1 — hex upgraded to 2.5.1
`mix hex --version`: **before `Hex v2.5.0`**, **after `Hex v2.5.1`** (`mix local.hex --force`;
archive `~/.mix/archives/hex-2.5.1` created). Toolchain archive — not in `mix.exs` deps,
`mix.lock`, or the 2.0.0 artefact.

### AC3 / C3 — advisory delta = ∅ (the finding that could have unravelled MES-26/27)
Full raw `mix hex.audit` captured at both 2.5.0 and 2.5.1. Ids derived from raw text
(format-robust, not a `grep EEF-CVE`); **extracted id count == reported row count = 22 at
each version.** Set diff empty both directions; **the two raw outputs are byte-identical** —
so **neither the advisory set nor the rendering changed.** **MES-26's 22-advisory denominator
and MES-27's target table stand at 2.5.1.** Exit 1 at both (22 active). **T1 does not fire.**

### AC4 / A6-3 / C2 — the ignore mechanism works, and the exit code tracks the remaining set
Three measurements (C2b), exit code the signal:
- **0 ignored →** exit 1, 22 active, 0 ignored (baseline).
- **21 ignored →** exit 1, **1 active** (`EEF-CVE-2026-8468` left un-ignored), 21 ignored — the decisive case: the exit code tracks the **remaining** advisories, not "ignore is set." **T3 does not fire.**
- **22 ignored →** **exit 0**, 0 active, 22 ignored — branch (b) clears the gate.

- **C2a:** the `:hex` block form (`hex: [ignore_advisories: ["EEF-CVE-2026-49755"]]` in `mix.exs` project config) and `HEX_IGNORE_ADVISORIES` produce **identical** output for the same id — env var is a valid proxy; the `:hex` block is branch (b)'s durable, version-controlled form. The all-22/21 runs used the env var (no repo state to revert).
- **C2c:** the throwaway `:hex` block was reverted (`git checkout -- mix.exs`); a re-run **restored the baseline exactly** (exit 1 / 22 active / 0 ignored).
- **Id-form agnostic:** EEF-CVE, CVE, and GHSA id forms all produce identical ignore behaviour.
- **A6-4 (failure mode):** a misspelled/non-existent id is **not silently accepted** — hex warns `ignore_advisories entry "…" … does not match any advisory for the locked dependencies and can be removed` (exit 1, nothing ignored). A typo cannot masquerade as an applied policy.

### C6 — ignore scope (from hex 2.5.1 source, not docs)
`lib/mix/tasks/hex.audit.ex` @ v2.5.1 reads `Hex.State.fetch!(:ignore_advisories)`, splits via
the shared `Hex.Ignores.split_advisories`, and sets exit 1 on the **non-ignored** set only.
`lib/hex/registry/server.ex` @ v2.5.1 has **no ignore-config reference** — advisory metadata is
cached/fetched but not ignore-filtered at the registry layer. **Scope: `ignore_advisories`
affects `mix hex.audit` (the gate MES-27 adds); it does NOT suppress advisories in
`deps.get`/`deps.update`.** Docs and source agree. Established without running deps resolution
(T2/T4-safe).

### A6-1 / C1 — target 2.5.1 is clean (retirement AND advisory)
2.5.1 is the **lowest** hex with `ignore_advisories` (2.5.0 has none) **and** the **latest**
release (`v2.5.1 [Latest]`, 2026-07-09; v2.5.2 is unreleased `-dev`), **not yanked/retired**,
no later fix/revert. **C1:** OSV package query for the `hex` package (2026-08-10) — **no
advisories for `hex` at 2.5.0 or 2.5.1**; upgrading is not adopting an advisory-bearing tool.

### AC2 / C4 / C5 — hex is unpinned; no CI (re-confirming A9, not a new finding)
No pin exists in-repo: `.tool-versions`, `Dockerfile`, `.github/` (absent entirely),
`.gitlab-ci.yml`, `.circleci/`, `asdf`/`mise`/`nix`, setup scripts — all absent (each named).
Per **C5** this **re-confirms Overrides A9** (established MES-14 V1, 2026-08-10): there is no CI
and no `mix` gate alias, so **all six gates are DoD gates run per ticket on the reviewer's
checklist — not automation.** Per **C4** the toolchain **pin obligation is placed on MES-27's
DoD** (a gate whose tool version is unpinned is not reproducible); MES-28 reports the absence,
does not add a pin (new scope; MES-28 is deliberately cheap).

### Triggers — none fired
T1 (set differs) ✗ — delta ∅. T2 (`mix.lock` changes) ✗ — sha256 unchanged throughout. T3
(ignoring doesn't clear exit code) ✗ — 22-ignored → exit 0, 21-ignored → exit 1. T4 (deps
change/bump) ✗ — only a throwaway `:hex` project-config entry, reverted; no deps/version touch.

### PA-2 — the `[MES-26]` commit `f900111` rides on THIS ticket's reviewer checklist (CO-3)
`f900111` landed after Codex's MES-26 verdict; **Codex verifies it, not CC.** Checklist: single
parent `9a233c0` · subject `[MES-26] <title>` · exactly two paths (`docs/sprint_4_issues.md`,
`.gitignore`) · no `mix.exs` bump · no tag · `mix.lock` untouched · present on `origin/main`
(pushed 2026-08-10). PA-2's third demonstration.
**Priority Hint:** n/a (toolchain) · **Blocking?:** unblocks MES-27 · **Suggested Jira Ticket?:** MES-27 (gate + pin), MES-15

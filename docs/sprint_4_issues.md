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

> **Reproduction-path correction (MES-15, 2026-08-19).** The recipe below originally
> named `github.com/modelcontextprotocol/specification`. That repo is **not gone** — it
> **reproduces today**, because GitHub serves a 301 rename redirect and git follows it:
>
> ```
> $ git ls-remote https://github.com/modelcontextprotocol/specification.git HEAD
> 4df2d6b6e3588efb46e7542d98498e5c630a0a86    HEAD          # exit 0
> $ curl -sI https://github.com/modelcontextprotocol/specification | head -1
> HTTP/2 301                                                 # -> /modelcontextprotocol
> ```
>
> The defect is **fragility, not breakage**: the path survives only by that rename
> redirect, which GitHub withdraws the moment anyone re-creates the old name — at which
> point every future ticket inheriting this A4 reproduction path silently clones the
> wrong repository. The canonical path is
> `github.com/modelcontextprotocol/modelcontextprotocol`, used below. For a single-file
> read, no clone is needed:
>
> ```
> https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/<SHA>/<path>
> ```

```
$ git clone --filter=blob:none --no-checkout \
    https://github.com/modelcontextprotocol/modelcontextprotocol.git && cd modelcontextprotocol
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

---

## MES-27 — clear all 22 Hex advisories to lowest-clean targets; add the dependency-audit gate (2026-08-11)

Branch remediation across five packages, `mix.exs` `2.0.0-dev.2 → 2.0.0-dev.3`, sixth gate
recorded in `CLAUDE.md`. Deliverable: Confluence 262242305 child. Full detail there; findings
below.

### AC1 / AC2 — five named packages at exact lowest-clean targets; all 22 cleared, audit exit 0
Resolver landed each named package at its lowest-clean target (not latest — PO ruling):
`bandit 1.10.2→1.12.1` · `plug 1.19.1→1.19.5` · `req 0.5.17→0.6.1` · `mint 1.7.1→1.9.3` ·
`hpax 1.0.3→1.0.4`, plus `thousand_island 1.4.3→1.5.0` (forced by bandit `~> 1.5`). Latest
versions (plug 1.20.x, req 0.7.2, bandit 1.12.x) were **avoided** by temporary exact-pin
resolution, then constraints reverted so no consumer floor was raised (C6). `mix hex.audit`
after: **exit 0**, all 22 cleared by **branch (a)** bumps — **none by package removal** (A6-4:
26 packages before and after; all five present). Denominator (C4): the 22 were measured
**twice** — at `9a233c0` under hex 2.5.0 and at `d697093` under hex 2.5.1, `mix.lock`
byte-identical across both — two agreeing measurements, not one current + one stale.

### A7c — the AC2 green is instrument-verified, not a false green
The post-bump audit printed `Error opening ETS file …/cache.ets: :badfile` (hex's ephemeral
HTTP cache, not the advisory source) yet exited 0. Instrument check: baseline lock + `deps.get`
+ audit **re-reports all 22** (exit 1); target lock + `deps.get` + audit reports **0** (exit 0).
The green is real.

### AC3 / A6-1 — the resolver moved 10 packages; the derivation predicted 1
Full `mix.lock` diff (named-only `mix deps.update`, **no `--all`** — C5): 5 advisory-driven +
`thousand_island` (forced, derivation-**confirmed**) + **4 unpredicted cascades** —
`finch 0.21.0→0.22.0`, `jason 1.4.4→1.4.5`, `plug_crypto 2.1.1→2.2.0`, `telemetry 1.3.0→1.4.2`
— shared transitives re-resolved when the named subtrees unlocked. Constraint analysis
under-predicted by four; the observed diff governs. All 10 changed versions OSV-clean.

### AC4 / A7c — OSV cross-check of the whole tree, with a positive control
All **26** post-bump package/versions queried against OSV (`api.osv.dev/v1/querybatch`,
2026-08-11T12:09:57Z): **zero** vulns each. Positive control `bandit@1.10.2` on the same
endpoint returned **14 records** — the nulls are real, not an unrun query. **T6 does not fire**
(no in-range advisory OSV reports that hex.audit missed).

### C6 — the shipped constraint floor still admits advisory-bearing versions (report, don't fix)
`mix.lock` is not shipped; `mix.exs` constraints are, and all five are `optional: true`. The
floors are **unchanged** (not raised — raising is release-scope, PO): `req ~> 0.5` admits
0.5.0 (EEF-CVE-2026-49755) · `plug ~> 1.16` admits 1.16.0 (all four plug CVEs) · `bandit ~> 1.5`
admits 1.5.0 (six of seven bandit CVEs) — OSV-confirmed 2026-08-11T12:10:35Z. A consumer
resolving fresh against 2.0.0 can still pull a vulnerable version; the lock-scoped gate cannot
see this. `mint`/`hpax` have no direct constraint. **PO-visible at release (Sprint 5).**

### AC5 — per-package behavioural attribution (no grouped "no impact")
`bandit`: SDK runs it as an **HTTP/1 server** (POST + JSON/SSE), no WebSocket, no sendfile.
Exercised/served-path hardening: chunked request-body cap (CVE-2026-39803), request trailers
(39806), mixed-case Transfer-Encoding, internal HTTP/1 body-read, multiple content-length
(39805). Not exercised: all WebSocket items (inflate 39804, continuation 42786, fragmented
**65623**, max_frame_size), sendfile, HTTP/2 frame-size (42788). CVE-2026-39807 (scheme from
transport): SDK does **not** read `conn.scheme` — unaffected either way.
`req` (client, **NOT exercised** — A6-3): 0.6.0 dropped auto archive/CSV decoding (**JSON
decode stays on by default**; SDK only handles JSON + SSE, and decodes both by hand); 0.6.0
multipart fix (SDK uses no multipart); **0.6.1 made decompression opt-in** (`compressed: true`,
which the SDK does not set) — for conformant peers (uncompressed JSON/SSE) behaviour is
identical, so the SDK's own public API is unchanged. **T4 assessed not-fired**; the one residual
(a peer that force-compresses `application/json` would no longer be transparently decompressed)
is a latent capability change, never a specified/tested SDK behaviour — flagged for Codex.
`thousand_island 1.5.0`: timeout isolation (network timeouts enforced despite mailbox traffic)
→ MES-15 (AC9).

### AC6 / A6-3 — suite green unchanged, and what green does NOT cover
`mix test`: **225 tests, 0 failures**, no test or `lib/` file touched (**T2 does not fire**).
But the suite exercises only the **server** transport (Bandit + Plug end-to-end, HTTP/1;
`thousand_island` transitively). It does **not** exercise the **client** path: no test drives
`StreamableHTTP.Client` (`Req.post`), and no HTTP/2 anywhere — so **`req`, `mint`, `hpax`,
`finch` have no test coverage**. The green says nothing about them; OSV + changelog attribution
(AC4/AC5) carry those four, not the suite.

### AC7 — hex toolchain: documented minimum + DoD check, honestly not a pin
No declarative mechanism binds a Mix archive (no `.tool-versions`/asdf — confirmed). Documented
minimum **hex ≥ 2.5.1**, actionable via `mix local.hex 2.5.1 --force` (`mix local.hex [version]`
is documented), DoD check `mix hex --version`. Recorded in `CLAUDE.md`. Guarantees nobody runs
the gate below the floor unnoticed; does **not** prevent drift above it — stated as such.

### AC8 / A6-5 / A6-6 — sixth gate added last, in CLAUDE.md; staleness & offline behaviour
Six gates enumerated in `CLAUDE.md` (`format`, `compile --warnings-as-errors`, `credo`,
`dialyzer`, `test`, `hex.audit`), stated **DoD gates, not automation** (no CI). Added only after
AC2 green, so it never lands red. **A6-5:** `hex.audit` reads advisories from the local registry
(`Registry.open`/`prefetch`, hex 2.5.1 source) with **no staleness warning** — a stale snapshot
audits silently; refresh via `deps.get`. **A6-6:** it **runs offline** (`HEX_OFFLINE=1
mix hex.audit` → exit 0), auditing against local data, not failing closed.

### Gates — all six green on the branch
`format` ✓ · `compile --warnings-as-errors` ✓ · `credo` ✓ (no issues) · `dialyzer` ✓ (0 errors)
· `test` ✓ (225/0) · `hex.audit` ✓ (exit 0, instrument-verified).

### Triggers — none fired
T1 (audit ≠ 0) ✗ · T2 (test/`lib` change) ✗ · T3 (advisory-bearing package in post-bump tree) ✗
· T4 (req changes SDK's own public API) ✗ (assessed; decompression residual flagged) · T5 (gate
not reproducible) ✗ · T6 (OSV finds what hex.audit missed) ✗. Branch (b) not used — not chosen.

**Priority Hint:** high (unblocks MES-15) · **Blocking?:** blocks MES-15 · **Suggested Jira Ticket?:** MES-27; C6 floor-raise → Sprint 5 release decision (PO)

### MES-27 correction round 3 (CR-11 + CR-3/CR-4-req/CR-5, 2026-08-13) — CC/CODE_CREATOR

PO ruled T7 = option (c): `req` stays 0.6.1; the client sends `accept-encoding: identity`
and fails cleanly on an unexpected `content-encoding`. **CR-11** (`lib/` + `test/`
sanctioned): observed-request evidence first — req 0.6.1 sets no `accept-encoding` by
default (server saw `[]`), exposes response `content-encoding` (does not strip it at
`compressed: false`), and `identity` is legal (RFC 9110 §12.5.3, "synonym for no
encoding"). Client now sends `accept-encoding: identity` and a guard **before the
content-type branch** (covers JSON **and** SSE — one outbound call site, `Req.post`;
the GET SSE stream is unimplemented → MES-15) returns `{:error,
{:unexpected_content_encoding, coding}}` for any non-`identity` coding, matching the
transport's `{:error, {tag, …}}` convention. **A7 discriminating regression** (first
test to drive the client path — A6-3): asserts the exact tuple; FAILS at `95115ec`
(`{:json_decode_error, …}`), passes after. **CR-11.4 (conformance, honest):** MCP
2026-07-28 Streamable HTTP is silent on content coding (A4), so RFC 9110 governs; §12.5.3
makes honoring `Accept-Encoding` a **SHOULD not a MUST** — a compressing peer is
**discouraged, not non-conformant**. **T9 does not fire**; MES-19 wording → "deliberate,
documented client limitation." **CR-3:** the four cascades held at baseline (`finch`
0.21.0, `jason` 1.4.4, `plug_crypto` 2.1.1, `telemetry` 1.3.0); `mix deps.get` accepts
them; diff vs `d697093` is now the minimal **6** packages; held `finch` 0.21.0 admits
`mint` 1.9.3 (`~> 1.6.2 or ~> 1.7`). **CR-4-req:** 49755 (decompression bomb) was
peer-reachable at 0.5.17's auto-decode — residual after 0.6.1 + CR-11 is **none** (SDK
neither requests nor decodes coding); 49756 (multipart injection) is not constructible
(SDK builds no multipart). **CR-5 re-exec** at the corrected head: audit exit 0 / all 22
clear; whole-tree OSV 0 hits + positive control `bandit@1.10.2` 14 records
(2026-08-13T10:44:59Z); six gates green incl. gate-6 two-step; `mix test` **230/0**;
`mix.lock` sha `0b469b90…`; `mix.exs` unchanged `2.0.0-dev.3`, no tag.
**Priority Hint:** high · **Blocking?:** blocks MES-15 · **Suggested Jira Ticket?:** MES-27; MES-19 (conformance wording); MES-15 (client HTTP/2 + GET-SSE guard)

### MES-27 correction round 4 (CR-12…CR-16, 2026-08-15) — CC/CODE_CREATOR

Reviewer (now Claude Code) returned APPROVE-WITH-CORRECTIONS with two blocking finds
from its own probes. **CR-12 (blocking):** the guard read only the first
`content-encoding` value (`get_header/2`), so `identity` then `gzip` on **separate
field lines** (RFC 9110 §5.3 = comma form; §8.4 codings in applied order — the natural
ordering) still gave `{:json_decode_error, …}` at `a6bd999`, byte-identical to pre-fix.
Fixed with a new `get_header_values/2` accessor (get_header/2 untouched — shared with
content-type; **T11 does not fire**); `unexpected_content_encoding/1` now flattens all
values. Sixth/seventh tests cover both orderings; the identity-then-gzip one FAILS at
`a6bd999` (A7 discriminating). **CR-13 (blocking):** CLAUDE.md's "irreducible residual"
said 3 packages; enumeration gives **21 of 26** (named; incl. runtime `finch` and
`thousand_island`). Corrected: 6a **narrows** limitation 1 to the five advisory-bearing
packages, does not compensate; the compensating control is the live whole-tree OSV
cross-check (AC4, owned by MES-19); did NOT extend the sentinel (AC7 error), and PA-9
(OSV in the per-ticket gate) is the PO's. **CR-15:** cite §8.4/§8.4.1 for the response
`Content-Encoding` (§8.4 says `identity` SHOULD NOT appear — tolerating it is deliberate
leniency), §12.5.3 for request `Accept-Encoding`; documented (not changed) that a
caller-supplied `accept-encoding` in `:headers` is **appended** and would hard-fail the
client. **CR-14/CR-16:** MES-15 forward note refresh + round-3 line-number fix
(Confluence). C7 correction is the PM's (PM-18). **Re-exec:** six gates green incl.
gate-6 two-step; **232/0**; mix.lock unchanged (`0b469b90…`, no dep change); mix.exs
`2.0.0-dev.3`, no tag.
**Priority Hint:** high · **Blocking?:** blocks MES-15 · **Suggested Jira Ticket?:** MES-27; MES-15; MES-19

---

## MES-15 — `subscriptions/listen`, the missing core method (server-side, HTTP) (2026-08-19)

Canonical narrative: PM dispatch [24322], /plan parts 1–3 [24324] [24325] [24326], C1 spike
report [24361], PM ratification [24360] (RATIFIED WITH CONDITIONS C1–C7). Branch `MES-15` off
`5cf1c23`. **Re-scoped at ratification:** stdio → **MES-29** (backlog), client-side → **MES-18**
(already owned it). DoD bullet 5's stdio half moved with the work, and epic MES-21's exit
condition 3 was narrowed to match.

### Decision: the gap is real and the capability was lost, not migrated (gap-register D2)
**Description:** Sprint 3 executed D2's DELETE — the GET SSE endpoint and the
`resources/subscribe` / `resources/unsubscribe` pair — but no Sprint 3 brief named the
replacement, so `subscriptions/listen` was never implemented. Resource-subscription capability
has therefore been **absent from a required core method** since that sprint. This ticket adds
it for the HTTP transport, server side.
**Resolution:** `MCP.Protocol.Messages.Subscriptions` (wire shapes), `MCP.Server.Subscription`
(a live subscription + `frame/3`), handler callbacks `handle_listen/3`, `handle_listen_closed/3`
and `supported_subscriptions/0`, `ToolContext.stream_sink` + `ToolContext.stream/3`, a third
`Dispatch` return shape `{:stream, subscription, state}`, and the HTTP stream loop.
**Priority Hint:** high · **Blocking?:** last open item in epic MES-21's exit condition ·
**Suggested Jira Ticket?:** MES-15; MES-29 (stdio); MES-18 (client)

### Finding (D-1, corrects the brief): the A4 clone recipe is FRAGILE, not broken
**Description:** The brief stated that `docs/sprint_4_issues.md:115-118`'s clone recipe names a
repo path that **404s**. Run end to end, it **reproduces**: `git ls-remote` on
`.../specification.git` exits 0 and `git clone` succeeds, because GitHub serves a 301 rename
redirect that git follows (`curl -sI` → `301 → /modelcontextprotocol`). The real defect is that
the path survives only by that courtesy redirect, which is withdrawn the moment anyone
re-creates the old name — silently cloning the wrong repository for every future ticket that
inherits this reproduction path.
**Resolution:** recipe corrected to the canonical
`github.com/modelcontextprotocol/modelcontextprotocol`, with the raw-URL form documented for
single-file reads and the `ls-remote` evidence recorded **as "fragile", not "404"** (C6).
Writing 404 into the permanent record would have propagated an unverified claim.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No (corrected here)

### Finding (D-2, spec divergence): two normative texts give two stdio teardown mechanisms
**Description:** `schema.ts:637` states that on stdio the **server** also sends
`notifications/cancelled`, "solely to terminate a `subscriptions/listen` stream". But
`subscriptions.mdx:128-153` gives exactly one server-initiated teardown signal — the listen
**response** — and builds the client's clean-close-versus-drop discrimination on the
response/no-response asymmetry. Two normative texts at the same pinned commit, two mechanisms.
**Resolution (PO ruling, RECORD ONLY):** implement the response; do **not** emit a server-side
`notifications/cancelled`; do not raise upstream. Recorded here so **MES-19** can revisit it
when the conformance claim is drafted — the record is what makes that possible.
**Priority Hint:** low · **Blocking?:** No · **Suggested Jira Ticket?:** MES-19 (conformance wording)

### Finding (D-3, corrects PM adversarial item 9): `ResourceCapabilities.subscribe` is STARTED, not retired
**Description:** Adversarial item 9 invited retiring the dead subscribe surface wholesale. But
`ServerCapabilities.resources.subscribe` **survives into the final schema** (`schema.ts:846-855`,
field at `:850`) with a dedicated example, "Resources — subscription to individual resource
updates (only)" (`:837-838`): it is how a server advertises that it honours
`resourceSubscriptions`. Nine sites are dead and go; this one field goes live.
**Resolution (deletions ledgered — content preserved at pinned SHA `5cf1c23`, not file-in-tree):**
`methods.ex` `resources_subscribe/0` + `resources_unsubscribe/0`; `resources.ex`
`SubscribeParams` + `UnsubscribeParams`; `handler.ex` `handle_subscribe/2` +
`handle_unsubscribe/2` and their two `@optional_callbacks` entries;
`conformance/server_handler.ex` two implementations + its now-dead `subscriptions:` state field.
Tests updated (`methods_test.exs`, `resources_test.exs`) to assert the **absences**, so re-adding
one has to argue with a test. Retained: `ResourceCapabilities.subscribe` and the client-side
capability-parsing tests (`initialize_test.exs`, `capabilities_test.exs`).
**Correction to my own enumeration (A2d).** The /plan listed **5** doc claims to correct
(`prd.md:90`; `onboarding.md:85`, `:451`; `implementation-plan.md:90`, `:202`, `:242`). Grepping
the retired names after the code change found **8 sites across two further files the plan's
enumeration missed**: `architecture.md:240-241` (client API map), `:318` (dispatch map), `:339-340`
(behaviour listing), `:395` (capability auto-detection), and `README.md:393-394` (two callback-table
rows). All corrected. Recorded rather than quietly widened, because an enumeration that was wrong
once is the thing a reader needs to know about.
**Not corrected, and deliberately so:** `docs/architecture.md` carries much broader **pre-existing**
drift — it still describes the `initialize` handshake, the `:ready` gate and per-session server
state, all removed in MES-9. Rewriting it is a separate piece of work with its own review; only the
subscribe-surface claims this ticket retires were touched. Flagged so the drift has a witness.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Defect on `main` (C3, sanctioned scope A9): three advertised capabilities the SDK cannot deliver
**Description:** `Config.detect_capabilities/1` set `listChanged: true` for tools, resources and
prompts whenever the corresponding list callback existed. Since Sprint 3 deleted the standing GET
stream there has been **no mechanism anywhere in `lib/`** by which a `list_changed` notification
could reach a client — `grep -rn list_changed lib/` returns only the method-name constants and
the capability structs. `main` therefore advertised three capabilities it could not honour, to
every client, on every `server/discover`. **Independent of this ticket**, and found from a
question about something else.
**Resolution:** own commit, own before/after evidence. `detect_capabilities/2` gates each claim
on the deployment actually having a channel: `:streaming` (declared by the driver — the Plug says
`not enable_json_response`, `MCP.Server.Connection` says `false`) **and** `handle_listen/3` on the
handler. An undeliverable capability is `nil`, not `false`, so it is **absent** from the wire
rather than present-and-false. `resources.subscribe` is never inferred — it requires the explicit
`supported_subscriptions/0` declaration, because inferring it would reproduce the same over-claim.
**A7 evidence (regression, not positive control):** the "cross-SHA regression" case calls
`detect_capabilities/1`, callable unchanged on both sides, and fails at `main` with a plain
assertion error — `left: true, right: nil`.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No (fixed here)

### Spike S-1 (C1, stop-and-escalate point): Thousand Island 1.5.0 does NOT kill a write-only long-lived request
**Description:** MES-27 moved Thousand Island to 1.5.0 — whose headline change is improved
isolation between network and GenServer timeouts — directly underneath this stream. If an idle
**read** timeout fired on a request that only ever writes, every long-lived stream would be killed
spuriously, and a keep-alive interval chosen to dodge it would be a workaround wearing a design's
clothes. Probed, not assumed.
**Result — PASS.** Bandit 1.12.1 / TI 1.5.0, `read_timeout: 1000` (60× below Bandit's default), 20
chunks at 300 ms intervals, zero inbound bytes after the request line: **20/20 arrive** over 7 s,
i.e. six consecutive read-timeout windows survived. Mechanism, from
`deps/thousand_island/lib/thousand_island/handler.ex`: `handle_data/3` runs **synchronously**
inside `handle_info({:tcp,...})` (`:407-408`), and `handle_continuation/2` — which cancels the read
timer and flushes an already-delivered `:read_timeout` (`:557-568`, `:578-579`) — runs only on its
return; the only consumer is `handle_info(:read_timeout, ...)` (`:427`), unreachable while inside
the callback. A timer firing mid-stream queues and is discarded. **The read timeout governs the
gap between requests, not the duration of one.**
**Bound, not overclaimed (A2c):** established for HTTP/1 with the body already read. **Not**
established, because not probed: HTTP/2 (Bandit's h2 handler multiplexes and does return to the
loop), and a listen request with an unread body — which cannot arise on our path because params
are read and validated before the stream starts. That is now a design constraint, recorded in code.
**Priority Hint:** high · **Blocking?:** No (gate cleared) · **Suggested Jira Ticket?:** No

### Spike S-2: the orphan-detection bound, measured — and one case it cannot see
**Description:** How many `Plug.Conn.chunk/2` calls succeed after the peer goes away? That number
is the bound the docs quote, so it was measured rather than asserted.
**Result (three probes; a negative result enumerates too, A2d):**

| Client teardown | Result | Reading |
|---|---|---|
| `shutdown(:write)` — half-close | **all 50 writes succeed** | Correct: a half-close is "I have finished sending", not cancellation. |
| `close/1`, 100 ms settle | `{:error, :closed}` on write **1** | Zero chunks absorbed. |
| `close/1`, 0 ms settle | `{:error, :closed}` on write **1** | Same with no settling delay. |

So orphan detection costs **one write, and that write is the keep-alive** — bounded by the
keep-alive interval plus a round trip rather than unbounded. Two qualifications, both of which
changed what was implemented: the measurement is **loopback**, so a real network adds an RTT (docs
say "one to two intervals", and the cancellation test asserts a **window**, not a write count — an
exact-count assertion would encode a loopback artefact); and **a half-closing client is invisible
to us indefinitely**, which is precisely the case `:max_stream_lifetime` catches. That is a second,
independent justification for R-2's finite default, beyond bounding identity freshness.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Limitation (C2, identity residual): identity is frozen at stream open
**Description:** MC-1…MC-7 constrain identity **sharing**, not **duration** — MC-3 forbids identity
being "cached, shared, or reused *across requests or instances*" and names the AC6′/round-robin
guarantee as its purpose. A listen stream is **one** request whose context no second request can
obtain, so the distinguishing test returns no and there is no MC violation (PM ratification R-3:
an uncovered case, not a violation; no A1). But no MC says anything about credential **expiry or
revocation during a request**, because until now no request lasted long enough for it to matter.
**The residual, stated rather than read as compliance:** a principal revoked mid-stream keeps
learning **that** a subscribed URI changed — never **what** it now says, since
`notifications/resources/updated` carries a URI and nothing else (`schema.ts:1409-1418`), and
reading it still costs a fresh `resources/read` under a freshly resolved identity — until the
stream closes. Bounded by `:max_stream_lifetime` (default **1 h**, PO ruling R-2) and by
`handle_listen/3`'s open-time decision about which URIs this principal may observe at all.
**Authorization is open-time only**, by design: the honoured-subset return *is* the authorization
hook, because a second place to say no is a second place to forget to. Documented on the
`handle_listen/3` callback and in the Plug moduledoc — where a consumer actually meets it — not
only here (I14: a residual living only in a Jira comment is a finding with no owner).
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Boundary (PO Ruling 1): multi-instance fan-out is the consumer's responsibility
**Description:** Notifications reach a client only when the handler emits them **on the node
holding that client's stream**. A change on instance B does not appear on a stream held by
instance A. No fan-out seam, no broadcast dependency, no new public API.
**Resolution:** stated in the Plug moduledoc as a **deliberate deferral** — the 2026-07-28 core is
specifically stateless and a long-lived stream is the one thing in it genuinely pinned to a node;
it is acknowledged that this forgoes something Elixir would serve better than most runtimes — and
made **executable** (a documented boundary with no test is an unverified claim, A2c). The test runs
two independent Bandit instances in SSE mode and asserts (i) a change emitted on B does **not**
appear on A's stream within a bounded window, **and** (ii) the positive control: the same
notification emitted on A's own sink **does** arrive. Without (ii), (i) passes just as happily on a
completely broken stream.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision (adversarial item 1 / R-4): JSON mode refuses `subscriptions/listen` with `-32601`
**Description:** With `enable_json_response: true` there is no way to hold a stream open, and the
listen response **is** an SSE stream (`streamable-http.mdx:107-113`, `:217-234`) — so there is no
conforming way to render it as a single JSON body. A silent black hole was rejected.
**Resolution:** `-32601`. `-32020..-32099` is spec-reserved and off limits; allocating from the
implementation-defined `-32000..-32019` range would invent SDK-private semantics no client
understands. `-32601` is already what this endpoint returns for an unimplemented method and is what
the spec's own compatibility guidance treats as the "not supported" signal (`stdio.mdx:131-141`).
**Declining to allocate a code was the call.** It is honest only because such a deployment also
advertises **no** subscription capability, so a conforming client never calls it — which is why the
C3 fix and this refusal are one decision, not two.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision (adversarial item 2): the dispatch contract widened without being able to break a driver
**Description:** A third return shape breaks a two-shape contract both drivers match exhaustively.
A missing `case` clause is a **runtime** `FunctionClauseError` — not a compile error, and dialyzer
does not flag runtime case exhaustiveness — so the risk is real and is not caught by any gate.
**Resolution:** `{:stream, ...}` is returned **only** when `config.streaming` is true, a flag a
driver sets to declare it can hold a response open. A driver that does not set it gets `-32601` and
can **never receive the shape**, so the guarantee extends to third-party drivers this project never
compiles. `MCP.Server.Connection` declares `streaming: false` (stdio is MES-29) and additionally
carries an explicit, loud rejection clause: the alternative to an explicit refusal is a
`FunctionClauseError`, and a stream opened then silently dropped looks to a client exactly like a
working subscription that never fires.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** MES-29 (flips it to true)

### Decision (adversarial item 3): sink separation is structural, not disciplinary
**Description:** Sprint 3's cross-request identity leak (I10) came from plumbing that trusted its
callers. Both directions must be impossible, not merely untested.
**Resolution (three separate constructions, not one rule applied three times):** (1)
`MCP.Server.Dispatch` clears `ctx.stream_sink` **once, for every method other than
`subscriptions/listen`**, so a tool/resource/prompt callback has no value to emit through and
routes added later inherit the guarantee without knowing it exists — a handler that tries gets
`{:error, :no_stream}`. (2) `Subscription.frame/3` is the single place a message becomes a stream
frame, and **both** stream MUST NOTs are the *same* rule there: no `SubscriptionFilter` key maps to
`notifications/progress` or `notifications/message`, so a request-scoped type can never enter an
honoured set — there is no second check to forget. (3) The listen path starts **no**
`NotificationCollector`, so the request path's `drain/1` + `stop/1` has nothing to act on; the two
sinks are two fields with disjoint lifetimes, not two modes of one. Notifications emitted via
`reply_sink` *during* `handle_listen/3` are discarded with a **loud warning** — a silently
swallowed notification looks to the handler author exactly like a delivered one.
**CORRECTION (review F4, correction round 1, 2026-08-19) — construction (3) as written above is
FALSE, and is left standing rather than quietly edited because this file is the permanent record.**
`plug.ex` starts a `NotificationCollector` for **every** POST, a `subscriptions/listen` included,
and drains and stops it; the loud warning named in the same sentence is the proof, since there
would be nothing to warn about if no collector had collected. The claim overreached the code in
the **safe** direction, which is why nothing broke and why no test caught it. **The true property,
which does hold and is what the driver relies on:** the collector's lifetime ends **strictly
before** the stream's — it is drained and stopped *before* the stream is opened, deliberately,
because a subscription can be open for an hour and holding a per-request process for it would be a
leak measured in hours. So the two cannot overlap. Corrected in the same three places the false
version appeared: this entry, the `MCP.Server.ToolContext` moduledoc, and the close-out comment.
The test that was supposed to guard the claim could not fail (see the round-1 entry below); it has
been replaced by one that asserts the true property end to end, with a deliberate break shown
turning it red.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision (adversarial item 7): the SSE encoder could not emit a keep-alive; the parser was already correct
**Description:** `SSE.encode_event/1` unconditionally appends a `data:` line (`sse.ex:141-151`), so
it **cannot** produce the bare comment line the spec encourages on long-lived streams
(`streamable-http.mdx:145-155`, whose own example is `:\r\n`). The parser side was already right:
`parse_field(":" <> _rest, acc), do: acc` (`sse.ex:154`).
**Resolution:** new `SSE.comment/0`. Both directions tested — the encoder emits it, and the parser
ignores one arriving **between two events** mid-stream. The end-to-end keep-alive test reads the
**raw de-chunked payload**, not parsed events: the parser discards comment lines by design, so
asserting through it would pass identically whether or not a single keep-alive was ever written.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Verified-benign (CC-1): response compression over a long-lived stream needs no change
**Description:** Bandit compresses chunked responses, which could in principle stall SSE delivery.
**Result:** for a streamable response `gzip`/`zstd` fall through to identity (the literal `false`
streamable argument, `bandit/compression.ex:88-100`), while `deflate` is used with
`:zlib.deflate(_, _, :sync)` **per chunk** (`:102-108`) — a per-chunk flush, so delivery is not
stalled. Our own client is unaffected: it sends `accept-encoding: identity` (`client.ex:216-218`,
MES-27). **Considered and rejected:** forcing `cache-control: no-transform` to disable compression
(`compression.ex:65-70`) — it would disable it for the ordinary POST path too. Recorded so the next
reader does not re-derive it.
**Priority Hint:** low · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Limitation (CC-2, forward to MES-18): `MCP.Client` cannot consume a listen stream
**Description:** `streamable_http/client.ex:299-300` parses a **complete** SSE body
(`SSE.feed(SSE.new_parser(), body)`) returned by a blocking `Req` call — there is no incremental
path, so it can never receive a second message on a held-open stream. Separately, its moduledoc
claimed it "optionally opens a GET SSE stream", which its own inline comment already contradicted
(A2a).
**Resolution:** moduledoc corrected here (in scope, cheap, and it was a false claim); a streaming
client path is **MES-18**, which already owned client-side listen. The end-to-end tests therefore
use a raw `:gen_tcp` client — also the only way to control FIN timing, which T-9 and T-12 need.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** MES-18

### Transferred to MES-29 (CC-3): `notifications/cancelled` has no plumbing at all
**Description:** `dispatch.ex` returns `{:noreply, state}` for every unrecognised notification, so
stdio cancellation is currently **swallowed**. This is new work rather than a modification.
**Resolution:** transferred with the stdio half of the ticket, to **MES-29**, which also owns the
shared-channel subscription registry, per-subscription-id ack ordering, the interleaving/ordering
tests, and the no-state-across-reconnect statement (`stdio.mdx:109-115`,
`subscriptions.mdx:159-161`). An obligation that transfers arrives with an owner (A8).
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** MES-29

### Evidence (C4): which tests are regressions and which are positive controls
**Description:** A7b requires this to be stated per test rather than left to read as a caught
regression.
**Regressions (fail at a pre-fix SHA for the right reason):** `capability_honesty_test.exs` only —
the C3 defect predates this ticket. Demonstrated failing at `main` with `left: true, right: nil`.
**Positive controls (the observability seam is new; nothing to regress):** every test in
`subscriptions_dispatch_test.exs` and `subscriptions_stream_test.exs`. `subscriptions/listen` did
not exist before, so there is no SHA at which they could fail for the right reason.
**How the positive controls were shown capable of failing** — **six** deliberate breaks against
the finished implementation, each confirming the *right* tests go red, enumerated one per break:
(1) filter disabled in `frame/3` → 5 failures, all MUST NOT tests; (2) keep-alive frame never
written → the keep-alive + teardown tests; (3) `close_frame` writes on `:peer_closed` → the
close-asymmetry test; (4) `stream_sink` not stripped by Dispatch → the sink-separation test; (5)
ack deferred until after the loop → 6 failures including the ordering test; (6) teardown callback
skipped on stream-start failure → the MC-6 test. **CORRECTED in correction round 1 (review F7):
this sentence said "five" while the close-out table it was written from listed six — (6) was the
missing row.** A grouped count with no per-item enumeration behind it is exactly the A2d error, and
it was findable only by holding the two reports side by side (A3). **Three assertions were rewritten during that check because they were weaker than
their names claimed:** the ack-ordering test *raced* the ack rather than ordering against it (fixed
by having the handler emit **inside** `handle_listen/3`); the keep-alive test asserted only that
the stream survived and never looked for a keep-alive frame; and the abrupt-close test asserted
teardown rather than the asymmetry (fixed by extracting the decision into
`Subscription.close_frame/2`, since end to end it is **not** observable — once the peer is gone,
"sent nothing" and "tried and failed" are indistinguishable from outside).
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### MES-15 correction round 1 (K1–K7, 2026-08-19) — CC/CODE_CREATOR

Review verdict BLOCKING on F1 and F2; PM accepted all seven findings and issued a frozen
seven-item contract (K1–K7, comment 24366). C1, C2, C3, C5, C6, C7 were discharged at review;
C4 was discharged **in form and incomplete in substance**, which K2 closes.

**K1 / F1+F2 (blocking) — teardown was reachable from two of the exits, not all of them.**
`release_stream/1` and `notify_listen_closed/4` were called only from inside `open_stream/7`, so
a listen **refused** by the handler (`{:error, code, message, state}`) and a **raise anywhere in
the stream loop** ran neither: the handler was left holding a sink it had been given, and
`ToolContext.stream/3` went on answering `:ok` — on the one ticket whose theme is not claiming
what you cannot deliver. On HTTP/1 keep-alive the `{:mcp_stream, …}` messages then accumulated in
the Bandit connection process, which outlives the request, for the life of the connection.
**This is the same defect `145f4cb` was written to fix, on a neighbouring branch of the same
function** — finding one instance of a shape and fixing only that instance, which is the A2c error
in structural form. Fixed as a property over exits rather than as two patches: **five exits,
enumerated in the code at the `subscriptions/listen` section header, all reaching one idempotent
`teardown/4`** — (1) handler refusal, (2) stream-start failure, (3) lifetime expiry, (4) peer
close, (5) an exception anywhere in the loop. (3) and (4) are one code path differing only in what
goes on the wire; they are counted separately because what is being counted is ways **out**, not
close reasons. There is no sixth for a server-initiated `:shutdown` — this driver cannot yet
initiate one, and saying otherwise would be a padded count. (5) is an `after` around the whole
stream lifecycle, which is what makes the enumeration a **property** rather than a checklist: an
exit nobody named still unwinds through it. `teardown/4` is safe to call twice — `release_stream/1`
already was, and the handler notification is claimed exactly once through a second `:atomics` slot
via `compare_exchange` — so every exit calls it without needing to know whether another already
has.
**Contract change, and why it is not the driver's to infer:** `MCP.Server.Dispatch` gains a fourth
return shape, `{:listen_refused, response, state}`, **gated on the same `config.streaming` flag as
`{:stream, …}`** so the "a driver opts in; it is never surprised" guarantee is unchanged and a
driver that already handles `{:stream, …}` has one clause to add and no new condition to check.
It exists because the driver must distinguish a listen the handler **refused** (it ran, it holds a
sink, it is owed a teardown) from the two refusals that never reach the handler — a malformed
filter, and a non-streaming deployment — which are owed nothing: telling a handler that a
subscription closed when it never opened is the same class of false claim, pointed the other way.
Deriving that distinction from the response would mean re-deriving the dispatch's routing decisions
outside the dispatch, from an error code a handler is free to choose itself.
**A7b (new seams, failing direction demonstrated against the unfixed tree at `145f4cb`):** refusal
test → `assert_receive {:listen_closed, "refuse-me", "denied"}` fails, "no matching message after
2000ms, the process mailbox is empty"; raise test → same on `{:listen_closed, "raises", _}`. With
the first assertion removed so the second could be reached, **both** show
`assert {:error, :closed} = sink.(…)` failing with `right: :ok`. Both halves, both paths. These are
positive controls shown capable of failing, **not** caught regressions.
**Priority Hint:** high · **Blocking?:** was blocking · **Suggested Jira Ticket?:** No
**CORRECTED in correction round 2 (review R1) — the count above is wrong and the shape it argues
for is wrong.** There are **seven** exits, not five: a `handle_listen/3` that raises after
capturing the sink, and a `:stream_start` that raises rather than returning `{:error, _}`, were
neither listed nor covered. The paragraph above is left standing because the reasoning error in it
is the useful part: "fixed as a property over exits rather than as two patches" was still a fix
per **branch**, and a branch only exists once `Dispatch.dispatch/3` has returned a value to branch
on — so no amount of enumerating branches could ever have reached the two exits that raise before
there is one. See the round-2 entry below. (fixed here)

**K2 / F4 — a false structural claim in three places, and a test that could not fail.**
"The listen path starts no `NotificationCollector`" is false: `plug.ex:389` starts one for **every**
POST, a listen included, and `:404-407` drains and stops it — `warn_dropped_request_scoped/2` exists
precisely because it can have collected something. The claim overreached the code in the **safe**
direction, which is why nothing broke. Corrected in all three places it appeared: the
`MCP.Server.ToolContext` moduledoc, the adversarial-item-3 entry above (**by appended note, not by
quiet edit** — this file is the permanent record, and a false claim silently deleted from it teaches
the next reader nothing), and the close-out comment. The **true** property, which the plug's own
comment already stated correctly: the collector's lifetime ends **strictly before** the stream's, so
the two cannot overlap.
T-7's first case could not fail — `refute is_pid(sub.honoured)` on a filter map, `assert
%Subscription{} = sub` after it had already matched, and an `assert_raise FunctionClauseError` on
`NotificationCollector.drain(sub.id)` that asserted a fact about the collector's own guard. All
three pass unchanged against an implementation that starts a collector, which is the implementation.
Replaced by an end-to-end test of the true property, in the driver where it lives, with a **positive
control** (the same sink DID reach a live collector during `handle_listen/3` — the driver drained
exactly one notification out of it and warned) and shown red under a deliberate break (collector not
stopped before the stream opens): *"Expected to catch exit, got nothing"*.
**This was the fourth weak assertion in the ticket.** Three were found by the author and reported;
this one was found by the reviewer, **under the claim the author had flagged as least testable by
its own tests**. The instinct was right and did not save it: the tests written by whoever wrote the
construction were the ones that could not catch it.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

**K3 / F3 — `usage-rules.md` ships in the Hex package, and three of its claims are now false.**
It is in `mix.exs:47`'s package `files` and `:58`/`:63`'s docs `extras`, and it is the file aimed at
**AI agents consuming this SDK** — so a false claim there is shipped instruction, not stale prose.
Corrected: `:133-134` (`handle_subscribe/2` / `handle_unsubscribe/2` listed live with signatures →
replaced by the surface that exists, `handle_listen/3`, `handle_listen_closed/3`,
`supported_subscriptions/0`); `:199` ("GET for SSE listening" → there is no GET endpoint, GET is
405); `:214` ("the server only advertises capabilities for callbacks your handler implements" — the
exact rule C3 replaced → a callback is necessary and not sufficient).
**Not corrected here, and it is a fence rather than an oversight:** `:199`'s `Mcp-Session-Id` half
and `:203`'s "always call `connect/1` first" are pre-existing **MES-9** drift. **`usage-rules.md` is
hereby added to MES-30's file list** (alongside `architecture.md`, `prd.md`, `onboarding.md`,
`implementation-plan.md`) so the obligation arrives with an owner (A8) rather than being left in a
review comment.
**The enumeration went 5 → 13 → 16, and why is more useful to a later reader than the number:** the
third pass found more **because it was a different grep, not a better one** (the reviewer's own
observation, kept in its words). The first was the /plan's list of doc sites; the second re-grepped
the retired callback names after the code change and found 8 more across `architecture.md` and
`README.md`; the third reached `usage-rules.md` — a **shipped** doc that sits in neither `docs/`
nor the source tree, so the first two questions were never going to touch it. An enumeration is
only as wide as the question that generated it, which is why "I grepped again" is worth less to a
later reader than **what** was asked the third time.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** MES-30 (inherits `usage-rules.md`)

**K4 / F5 — C3 removed the SDK's over-claim and handed the same failure mode to the consumer.**
"Ack ⊆ advertised" is structural and enforced (`restrict_to_advertised/2`, T-5). "Advertised ⊆
honourable" **cannot** be: `supported_subscriptions/0` is static and zero-arity, `handle_listen/3`'s
answer is per-request and per-principal, so at the moment the declaration is read there is no
request and no principal to compare it against. **The unenforceability is the acceptable answer; its
absence from the repo was not.** The callback doc now says the SDK takes the declaration on trust,
and states what a handler declaring `resourceSubscriptions` and then refusing every URI leaves
`server/discover` advertising.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

**K5 / F6 — a silent drop behind an `:ok`.** `Subscription.uri_allowed?/3` read
`Map.get(params, "uri")`, so a `notifications/resources/updated` emitted with atom-keyed params
(`%{uri: …}`) was dropped while the sink answered `:ok`. Every **other** notification type is
indifferent to key style, because `Jason` encodes both to identical wire bytes — so this was an
asymmetric footgun on one type, not a uniform rule anyone could learn. Of the two mechanisms the PM
offered (accept both styles, or reject atom keys loudly), this takes the one that makes the
behaviour **uniform**: the filter is now as indifferent as the encoder. Stated in the `stream/3`
doc where a handler author meets it. The test asserts **both** directions — an atom-keyed allowed
URI is framed **and** an atom-keyed disallowed one is still dropped — so the fix cannot have
widened the filter into "atom keys bypass the check".
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

**K6 / F7 — two count corrections, and the control that caught both.** (1) The close-out's
`+2969/-150` was the diffstat at `091b9d7`, one commit early; the tip at review was `+3036/-150`.
Quoted from the final tip with its SHA in the hand-back. (2) The "five deliberate breaks" sentence
in the C4 evidence entry above is corrected to **six**, per-item enumerated — the MC-6 row was the
missing one. **Both were findable only by holding two reports side by side**, which is exactly the
cheap cross-report control A3 names as owned by nobody; this ticket is now two more instances of it
working, in a ticket that already carried per-item enumeration as an explicit DoD bullet.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

**K7 — mechanics.** All six gates re-run individually **after** the corrections (a gate result from
before a code change is not evidence about the tree being handed back); `mix hex --version` still
`2.5.1`, above the floor. Corrections land as their own commits on branch `MES-15`; the six reviewed
commits are neither amended nor rebased, so the re-review can see exactly what changed. No version
bump and no tag — still `2.0.0-dev.4`, the PM's to write, one increment for the whole ticket
regardless of correction rounds (D4, as clarified at MES-14). No pre-granted merge gate: this goes
back to the CODE_REVIEWER, because a fix to a found defect is written by the party now most
convinced the failure is understood.
**Out of scope and left alone, so the fence is explicit:** the h2 caveat (MES-19), the
`supported_subscriptions/0` input validation (fails loudly at boot), `architecture.md` and the MES-9
drift in `usage-rules.md` (MES-30).
**One thing surfaced while fixing K1 and is REPORTED here rather than absorbed silently, because
the contract does not grow while you are inside it:** the context handed to
`handle_listen_closed/3` carried a live `:reply_sink` pointing at a collector the driver had
**already stopped**. `NotificationCollector.push/3` is an `Agent.update` — a `GenServer.call` — so
a handler emitting from its own teardown callback did not get "dropped", it **exited** with
`{:noproc, {GenServer, :call, …}}`; `notify_listen_closed/4` rescues but does not catch exits, so
that took the request process with it. The comment sitting on that line claimed the opposite ("a
handler that emits from here is dropped"), which makes it a false claim in code as well as a crash
path. Pre-existing on the stream exits, but **K1 makes it newly reachable on the refusal exit,
where it would land before the refusal response is written and turn a clean `-32xxx` into a dropped
connection** — a regression this round would have introduced. Fixed in the same commit (both sinks
`nil`, the callback doc says so, and a test asserts it), *and* flagged here and in the hand-back so
the PM can rule it out of scope and revert it if it judges the fence tighter than that. Evidence
against the unfixed sink: `right: {:exit, {:noproc, {GenServer, :call, …}}}`.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No


### MES-15 correction round 2 (L1–L4, 2026-08-19) — CC/CODE_CREATOR

Re-review verdict BLOCKING on **R1 alone**; K2–K7 discharged and frozen. PM contract L1–L4
(comment 24370). R2 and R3 ride along in the same code.

**L1 / R1 (blocking) — the exit count was wrong for the third time, and the count was the finding.**
The PM's contract said six exits, the executor said five with a reason the PM accepted, and the
reviewer counted against the code and found **seven** — two of them running less than the full
teardown, one of them running neither call. Three parties, and the two who were confident were
wrong in the same direction. **The reason it was findable at all is that round 1 put the
enumeration in the code with an invitation to check it against the source; a count nobody can
check is a claim, a count next to the code it describes is a test.** That property is kept, with
the number corrected and the history of the number stated in situ (four → five → seven).

The two missed exits — probed by the reviewer, reproduced here as tests:

| Probe | Before | After |
|---|---|---|
| `handle_listen/3` raises after capturing the sink | wire 500, `handle_listen_closed/3` **not** called, sink still answering `:ok` | 500 unchanged; callback called; sink `{:error, :closed}` |
| a custom `:stream_start` raises instead of returning `{:error, _}` | `release_stream/1` ran, `handle_listen_closed/3` **not** called | both halves run |

**The diagnosis is F1's, one level up, and it is structural rather than arithmetic.** Round 1
moved teardown from "reachable from two branches" to "reachable from five branches" and called it
a property. It was not: a branch is chosen from a value `Dispatch.dispatch/3` must return in order
to exist, so an exit that raises *before* that return has no branch to be reached from. **Fixed by
establishing teardown ONCE around the whole listen lifecycle** — a `try/after` in `dispatch/6`
that opens **before** the dispatch call, which is the seam the reviewer named. The seven exits are
still enumerated at the section header, but they are now documentation of a shape rather than the
mechanism: 2, 4 and any eighth nobody has thought of are covered by construction. The four exits
that also tear down explicitly keep doing so — that buys nothing for reachability and buys the
handler a more accurate `state` than the pre-request one the bracket can offer.

**The one thing the bracket cannot do by construction: know whether `handle_listen/3` ran.** The
obligation is armed for any `subscriptions/listen` request before anything can fail, and cleared
**only** by a return value that proves the handler never ran — `{:reply, …}` (JSON mode's -32601,
a malformed or absent filter's -32602, no `handle_listen/3` exported) or `{:noreply, …}` (a listen
sent as a notification). `MCP.Server.Dispatch` returns those for a listen only from above the
handler call, so the clearing is exact; a **raise** leaves it armed. That is deliberately
conservative and it is an over-approximation: a raise inside dispatch but above the handler call
would notify a handler that never ran. Over-telling costs one `handle_listen_closed/3` for an id
the handler can recognise as unknown; under-telling is a leak nothing else reaps — and the PM's
ruling picks the same tie-break ("a raise is *it ran*"). **The guard against over-telling is a
test in its own right** (`a listen answered ABOVE the handler is owed no teardown callback`),
without which the fix could have passed by simply always notifying.

> **Appended in correction round 3 (review R4) — two sentences above were not true when written,
> and neither is quietly edited.** (1) *"armed for any `subscriptions/listen` request"* was
> **simply mis-stated**: it described the predicate that was intended, not the one that was
> written. `listen_request?/1` read `Map.get(raw_message, "method")`, which arms for a strictly
> **wider** class than "a listen request" — a message that is not a request at all arms it too.
> M1 makes the code match the sentence rather than the sentence match the code. (2) *"an id the
> handler can recognise as unknown"* was **wrong about the cost, and M1 repairs the cost**: the id
> is whatever the client put in the message, so before M1 it could name a subscription that was
> live on another connection. After M1 the over-approximation is reachable only through a raise
> inside `MCP.Server.Dispatch` above the handler call — an SDK-internal fault, not a message a
> stranger can post. **Residual, stated rather than left to be inferred:** subscription ids are
> client-chosen JSON-RPC ids, so "an id the handler can recognise as unknown" describes the
> ordinary case and is not a guarantee the SDK can make. That is now said in the shipped
> `handle_listen_closed/3` doc (R5), not only here.

**A7b (new seams; failing direction demonstrated against the unfixed tree at `c4b6578`, with
`lib/` alone reverted so the new tests ran against the old driver):** raise-in-`handle_listen`
test → `assert_receive {:listen_closed, "raise-in-listen", "alice"}` fails, "no matching message
after 2000ms"; with that assertion removed so the next could be reached,
`assert {:error, :closed} = sink.(…)` fails with `right: :ok` — **both** halves. Stream-start-raise
test → `assert_receive {:listen_closed, "start-raises", _}` fails the same way; its sink assertion
**passed** at the unfixed tree, because `release_stream/1` did run there. That is the reviewer's
"half the property", reproduced rather than restated, and it is recorded because a test whose two
assertions had different failing directions is evidence about the defect's shape. The
owed-nothing guard test **passes at the unfixed tree** by construction — it guards against a
regression this round could have introduced, not against the defect it fixed. These are positive
controls shown capable of failing, **not** caught regressions.
**Priority Hint:** high · **Blocking?:** was blocking · **Suggested Jira Ticket?:** No

**L2 / R2 — an `after` is not a catch-all, and the code said it was.** The claim, not the
behaviour, is the defect. Measured by the reviewer and not re-derived here: `after` runs for
`raise`, `throw` and a self-initiated `exit`, and **not** for termination by signal — confirmed
against the real driver by killing the Bandit connection process holding a live stream
(`handle_listen_closed/3` not called, sink still `:ok`). Guaranteeing cleanup against a kill needs
a monitoring process, which is construction, not a correction round; **the PM ruled the wording is
what changes.** Narrowed in all three places the claim is made: the `subscriptions/listen` section
comment in `plug.ex`, the shipped `handle_listen_closed/3` callback doc (a `.warning` admonition
naming the one exit it is not called on, plus the pre-request-`state` consequence), and a new
CHANGELOG *Known limitations* bullet. Written in the same voice as S-1's HTTP/1-only bound: the
bound is stated, the reason it cannot be closed here is stated, and what a handler should do
instead is stated. **Claiming a bound that does not hold is the one error this ticket has been
most careful about everywhere else, and it should not survive in its own cleanup code.**
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

**L3 / R3 — a fault in the handler's teardown callback must not change what the client receives.**
The residue of `c4b6578`, the round's own least-scrutinised commit. `notify_listen_closed/4`
rescues but does not catch **exits**, and on the refusal exit `teardown/4` ran *before*
`send_response/4` — so a handler whose `handle_listen_closed/3` exits for its own reasons (a call
to a process the handler owns and has lost, not to anything the SDK gave it) turned a clean
`-32603` refusal into a bare 500 with an empty body. Fixed both ways, deliberately: the guard now
catches exits and throws as well as rescuing (that is the property, and it holds on every exit),
and the refusal and stream-start-failure exits write the response **before** telling the handler
(defence in depth, and the ordering `close_stream/7` already used for the stream exits). The test
asserts the wire outcome and carries a **positive control** — the callback really did exit, and
the driver logged it — without which a callback that quietly succeeded would satisfy it just as
happily.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

**L4 — two recordings, no behaviour change.** (1) The T-7 replacement asserts
`catch_exit {:noproc, _}`, coupling it to `NotificationCollector.push/3` being a `call`; if push
ever became a `cast` the test would go red while the ordering property it guards still held.
Brittle in the **safe** direction — a false red on a refactor, never a false green — so it is
noted in situ and left as written. (2) On a **refused** listen, request-scoped notifications
emitted during `handle_listen/3` ride the refusal response rather than being dropped with a
warning, because `warn_dropped_request_scoped/2` is reached only from `open_stream/7`. That is
correct — no stream opened, so the response stream is exactly where they belong — and the rule is
"not on a listen stream", not "not on this request". Recorded next to the warning itself so the
next reader does not read the asymmetry as an inconsistency.
**Priority Hint:** low · **Blocking?:** No · **Suggested Jira Ticket?:** No

**Mechanics.** All six gates re-run individually **after** the last code change; `mix hex --version`
above the 2.5.1 floor. New commits on `MES-15` under the CC service identity; the thirteen existing
commits are neither amended nor rebased, so the re-review sees the delta. No version bump and no
tag — still `2.0.0-dev.4`, the PM's to write, one increment for the ticket regardless of rounds.
**Out of scope and left alone, per the PM's fence:** cleanup against process kill (needs a
monitor — L2 is a wording fix); the h2 caveat (MES-19); `supported_subscriptions/0` input
validation; `architecture.md` and the MES-9 drift in `usage-rules.md` (MES-30).
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### MES-15 correction round 3 (M1–M3, 2026-08-19) — CC/CODE_CREATOR

Re-review verdict BLOCKING on **R4 alone**; L1–L4 discharged and frozen — the reviewer confirms
the round-2 bracket is established at the right seam and went looking for an eighth and a ninth
exit, both of which the bracket ate. PM contract M1–M3 (comment 24374). **The bracket was right;
the predicate deciding whether the bracket owed anything was not.**

**M1 / R4 (blocking) — the thing that ARMS the obligation was not the thing that decides the
request is a listen.** `listen_request?/1` read `Map.get(raw_message, "method")` — a string in the
undecoded map. `MCP.Protocol.decode_message/1` classifies by **shape**, and its `cond` tests
Response (`id` + `result`/`error`) **before** Request (`id` + `method`), so a message carrying all
three decodes as a `%Response{}`, for which `MCP.Server.Dispatch` has no clause at all. It armed,
raised a `FunctionClauseError` above every routing decision, and the bracket's `after` paid
`handle_listen_closed/3` with a **client-chosen** subscription id.

| Probe | At `0f12936` | After M1 |
|---|---|---|
| POST `{"jsonrpc":"2.0","id":"victim-sub-42","result":{},"method":"subscriptions/listen"}` | wire 500; `handle_listen/3` never routed, never reached; **`handle_listen_closed("victim-sub-42")` called** | 500 unchanged; no teardown callback |
| the SAME message with `"method":"tools/list"` (the control — the method string is the only difference) | 500; no teardown callback | unchanged |
| two connections, one instance: A holds a genuine live `sub-A`; B posts the crafted message with id `sub-A` | **`handle_listen_closed("sub-A")` fired on B's request** while A's stream stayed live and A's own sink still answered `:ok` | no teardown callback; A's stream still delivers; teardown for `sub-A` arrives only when A closes |

**Why this was blocking and the round-2 over-approximation was not.** The PM's ruling covers a
raise *inside* `Dispatch`, above the handler call, on a genuine listen request, and it was priced
on a specific cost — "one `handle_listen_closed/3` for an id the handler can recognise as
unknown". That price did not hold: **the id is whatever the client put in the message**, so it can
be one that is currently live, on someone else's connection. The SDK told a handler a
subscription had closed while it was open, on a stranger's say-so, and its own sink for that
subscription disagreed. The previous two defects in this ticket needed a buggy handler; **this one
needed a client.** It is also round 1's own principle — "telling a handler its subscription closed
when it never opened is the same false claim pointed the other way" — broken in the other
direction, and the guard test written for exactly that principle **passed**, because the hole is
upstream of every branch that test can see.

**Fixed by arming off the DECODED message:** `listen_request?/1` now matches
`%MCP.Protocol.Messages.Request{method: method}` with a `false` fallback, called as
`listen_request?(decoded)`. `decoded` is produced by `handle_post/2`'s `with`-chain strictly
before `dispatch/6` is entered, **so nothing of R1's arm-before-anything-can-fail property is
given up** — the arm still happens before the first thing that can fail. What changes is only
*what* it is armed from: the driver's answer to "is this a listen?" is now the same one `Dispatch`
will act on, so nothing arms an obligation that routing will not honour. One consequence recorded
in situ: a listen sent as a **notification** now never arms at all, so the `{:noreply, _}` clause's
clear is defence in depth rather than a live path — correct either way, and the comment there says
which it is instead of describing a path that no longer exists.

**A7 in its ORDINARY form — these two are CAUGHT REGRESSIONS, not positive controls, and they are
kept in their own `describe` so they cannot be read as part of the round-1/round-2 control set.**
R4 is a defect present at `0f12936`; both tests were demonstrated failing against it with `lib/`
alone reverted:

* *a Response-shaped message naming the method is not a listen (R4)* → `refute_receive
  {:listen_closed, "crafted-listen", _}` fails with **"Unexpectedly received message
  `{:listen_closed, "crafted-listen", "alice"}`"**. With that first refutation removed so the rest
  of the test could be reached, the run **passes** at `0f12936` — which isolates the defect to the
  method string: the identical message with `"method":"tools/list"` fires nothing, and the
  positive control (a genuine listen that raises) is received.
* *a second client cannot tear down a live subscription it does not own (R4)* → `refute_receive
  {:listen_closed, "sub-A", _}` fails with **"Unexpectedly received message `{:listen_closed,
  "sub-A", "alice"}`"** — on client B's request, while A's stream is live. This is the one that
  shows the reach. Its positive control is that the same teardown **does** arrive for `sub-A` when
  A itself closes, so the refutation cannot pass by the callback being unreachable in the fixture.

**Priority Hint:** high · **Blocking?:** was blocking · **Suggested Jira Ticket?:** No

**M2 / R5 — the bound was recorded where the SDK's authors read it, not where the people it
constrains read it.** The over-approximation was stated honestly in a **private** comment on
`arm_listen_teardown/1`. The **shipped** `@doc` on `handle_listen_closed/3` — what a handler
author actually reads — said the callback is "called on every exit from a `subscriptions/listen`
request" and never warned that it can arrive for a subscription that never opened. Round 2 added a
`.warning` naming the one exit the callback is **not** called on; there was no counterpart naming
the case where it **is** called and should not be. Both directions are now stated, in the callback
doc and as a CHANGELOG *Known limitations* bullet, together with what a handler should do about
it: the id is the listen request's JSON-RPC id, **chosen by the client**, so treat an unrecognised
id as a no-op and make teardown idempotent. This applies **after** M1: the residual the PM ruled
acceptable survives the fix, and it is precisely the bound the doc owes its reader.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

**M3 — the round-2 entry is corrected by appending, above.** Which of its two statements the fix
repairs and which was simply mis-stated is stated there rather than here, so the correction sits
where the false sentence is. **The finding worth carrying forward is not the fix — it is the
question that found it:** *is the thing that arms an obligation the same thing that decides the
request is the kind that owes it?* Round 1 asked "which branches reach teardown", round 2 asked
"is teardown reachable from a branch at all", and both were about the **discharging** side. R4 is
the **arming** side, and no amount of care on the discharge side could see it — the guard test
built for the exact principle R4 violates passes, because it can only observe branches, and the
defect is upstream of all of them.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

**Found while fixing M1 (in-family, this ticket's own artifact): the R3 test is FLAKY at
`0f12936`, and it is a race in the test, not in the SDK.** `a handler-side exit in teardown does
not replace the refusal response (R3)` fails on `assert log =~ "handle_listen_closed/3 exit:"`
with `left: ""` — reproduced on the **untouched branch tip** at seeds 0 and 1, passing at seed 2,
so it predates this round's changes and is not caused by them. Diagnosis: `Req.post!` returns as
soon as the response body is complete, and the driver runs teardown — and logs — **after** writing
the response, so the line the test asserts on can land after the `capture_log/1` block has already
ended. The callback assertion passes; only the log capture loses the race. Fixed in the test, not
in the driver: the request goes over the file's raw client with `Connection: close` and reads to
EOF, which makes the socket close a signal that the plug has **returned** (hence after teardown),
followed by `Logger.flush/0` inside the block. Seeds 0–5 now green, including the two that failed.
**A flaky test is a claim that is sometimes not checked**, and this one guards the R3 property the
PM ruled on last round; reported rather than absorbed, in the same shape as round 2's in-family
find.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

**Not fixed here, and it has an owner: MES-31 (backlog).** A non-map JSON body — a batch array, a
bare string, a number, `null` — returns 500 rather than a `-32600` 400, because
`check_routing_headers/2` calls `Map.get/2` on it before `decode_message/1` ever runs
(`BadMapError`). Found by the reviewer while discharging the PM's item 6, **verified pre-existing
on `main`** (`plug.ex:310`; `git diff main..0f12936` matches `check_routing_headers` zero times),
and ruled by the PM to be MES-31 rather than absorbed into this ticket. Recorded here so the
ticket that owns it is named next to the finding.
**Priority Hint:** low · **Blocking?:** No · **Suggested Jira Ticket?:** MES-31 (raised)

**Mechanics.** All six gates re-run individually **after** the last code change; `mix hex --version`
above the 2.5.1 floor. New commits on `MES-15` under the CC service identity; the fourteen existing
commits are neither amended nor rebased. No version bump and no tag — still `2.0.0-dev.4`, the
PM's to write, one increment for the ticket regardless of rounds. **Out of scope and left alone,
per the PM's fence:** cleanup against process kill (needs a monitor); the h2 caveat (MES-19);
`supported_subscriptions/0` input validation; `architecture.md` and the MES-9 drift in
`usage-rules.md` (MES-30); the non-map-body 500 (MES-31).
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

---

## MES-16 — Extensions negotiation surface (SEP-2133), negotiation only, zero extensions (2026-08-19)

Epic MES-22. Gap register **J1**. Scope contract: ADR-003 sub-decisions 1 and 2 — the
*negotiation surface* is core and in; specific extensions (Tasks SEP-2663, MCP Apps) are
extension-track and out. All citations below are to the published-final `2026-07-28` schema at
commit `5f5440bb26a62e2cf3440b92da5a667efa03b267` (`schema/2026-07-28/schema.ts`, md5
`48a009165e07f6732e38baf91291de87`) and to spec pages at the same pin — never to the ticket brief.

### Decision/Finding: D-1 — SEP-2133 is stale on the envelope; the schema is not, and the mapping is written upstream

**Description:** `seps/2133-extensions.md:121`/`:150` describe advertising extensions in the
`initialize` request/response, with worked examples carrying `"protocolVersion": "2025-06-18"` — a
handshake SEP-2575 removed in the revision we target. A future reader hits the SEP first, so the
divergence is recorded rather than left to be re-discovered.

| | SEP-2133 (stale) | Schema + versioned spec at the pin (normative) |
|---|---|---|
| client declares | `:121`, in the `initialize` request | per request in `_meta["io.modelcontextprotocol/clientCapabilities"]` — `schema.ts:91-98`, Required, *"Servers MUST NOT infer capabilities from prior requests"*; `docs/extensions/overview.mdx:120` |
| server declares | `:150`, in the `initialize` response | in the `server/discover` result's `capabilities` — `schema.ts:678-687`; `docs/extensions/overview.mdx:152` |
| the field itself | `:117` map of identifier → settings; `:26` mandatory prefix | `extensions?: { [key: string]: JSONObject }` — `schema.ts:785` (client), `:882` (server). **Agrees with the SEP.** |

**The divergence is confined to the envelope the map rides in.** The map's own shape and naming
rules are identical in both texts, which is why this is a recording obligation and not a design
fork. **Resolution:** implement the schema, leave the SEP alone, record both citations.

**And the mapping was already written down upstream** — `docs/extensions/overview.mdx:114-179`
("Negotiation"), with current `2026-07-28` examples, plus `schema.ts:91-98` stating the
replacement mechanism normatively. The brief framed writing it as the first deliverable; it was
"record and cite", not "invent" (see C-2). The risk the brief named — building against a handshake
that does not exist — was retired by upstream text rather than by our inference.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Finding: C-1, C-2, C-3 — three PM-brief claims did not survive, and the method is the finding

**Description:** The `/plan` re-derived every citation instead of trusting the brief, and three
claims failed. The PM verified all three independently and amended the ticket body before
implementation. **The facts matter less than what they have in common.**

**All three were NEGATIVE claims — "there is no X", "nobody has written Y", "Z never reaches W" —
and each was stated at the width of the *topic* but checked at the width of a *grep* (A2c).
A2d's own extension says negative results are exactly where enumeration gets dropped.**

- **C-1** — brief: *"there is no versioned spec page for extensions at the pin."* False.
  `docs/specification/2026-07-28/basic/versioning.mdx:80-124` is a section headed **Extension
  Negotiation** carrying RFC-2119 MUSTs — the mandatory-prefix MUST at `:86-87`, the
  graceful-degradation MUST at `:121-124`. **The method error: filenames were enumerated and a
  conclusion was drawn about coverage. A section inside a differently-named page is invisible to
  that check.**
- **C-2** — brief: *"nobody has written that mapping down."* False, and written in a file the
  brief's author had already downloaded and read: `schema.ts:91-98`. **The method error: the file
  was grepped for "extension", which found the two fields and never reached `RequestMetaObject`.
  A grep answers the question you typed, not the question you have.**
- **C-3** — brief: *"the `%Meta{}` never reaches `ToolContext` and never reaches a handler."* Half
  true, and the load-bearing half false. True: the parsed `%Meta{}` struct is built at
  `dispatch.ex:146`, used only for the version gate, discarded. **False: that the data is
  dropped.** The raw `_meta` map travels a second path and reaches every identity-capable callback
  as `ctx.meta` — `tool_context.ex:84` (typed `map() | nil`), populated at `plug.ex:396` and
  `connection.ex:133,210`. **The method error: "the parsed struct is discarded" was read as "the
  data is dropped"; two different objects, one conclusion.**

**Consequence:** all three made the ticket *smaller*. C-2 turned the first deliverable from invent
into cite; C-3 removed the threading change entirely, and with it any new MC-4 adjudication — the
client-composed channel beside `ctx.identity` already existed and was accepted when `ctx.meta` was
added. The useful sentence for a later reader is not "the brief was wrong about a spec page"; it
is **"a filename enumeration cannot answer a coverage question, and a negative claim is only as
wide as the check that produced it."**
**Priority Hint:** high (method, reusable) · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Finding: F-2 — no conformance scenario exercises extensions negotiation, and MES-19's J1 claim rests entirely on this ticket's tests

**Description:** Measured first-hand rather than inherited from MES-13.
`@modelcontextprotocol/conformance@0.2.0-alpha.10`, `list --spec-version 2026-07-28` returns **74**
scenarios: **40 server**, **32 client** (25 `auth/*` + 7 core), **2 authorization-server**. This
reproduces `sprint_4_issues.md:47-52` exactly. **Zero of the 74 exercise extensions negotiation** —
no scenario name in the 74 contains "extension" or "negotiat" at all, and the only near-match by
name is `input-required-result-capability-check`, which is MRTR (SEP-2322), not SEP-2133.

**Why that negative is true for our scope rather than true by luck.** The nearest real match is
`tasks-capability-negotiation`, which *does* negotiate through the `extensions` map — it is the
only scenario in the whole 106-scenario catalogue whose name mentions negotiation. It is tagged
**`[extension]`**, not `[2026-07-28]`, so it is outside the 74; and passing it requires
implementing Tasks, which is out per ADR-003 #2. Left unstated, "no extensions-negotiation
scenarios" would read as "the harness has no interest in this", when the truth is "the harness
tests it only behind an extension we deliberately do not implement".

**Consequence:** MES-19's J1 evidence rests **entirely** on the tests written under this ticket. No
external suite corroborates it, and no future harness run will, unless Tasks comes into scope.
**Priority Hint:** high (MES-19 input) · **Blocking?:** No · **Suggested Jira Ticket?:** No (MES-19 owns it)

### Correction (A2d): the "16 Tasks-extension scenarios" count at `sprint_4_issues.md:52` is superseded

**Description:** Appended rather than edited in place, per the file's role as the permanent record.
**`docs/sprint_4_issues.md:52` (MES-13's alpha entry) says "16 Tasks-extension … scenarios". The
count of 16 is right; the attribution is not.** The 16 `[extension]`-tagged scenarios are
**10 `tasks-*` plus 6 `auth/*`**, enumerated:

- `tasks-*` (10): `tasks-lifecycle`, `tasks-capability-negotiation`, `tasks-wire-fields`,
  `tasks-request-state-removal`, `tasks-mrtr-input`, `tasks-request-headers`,
  `tasks-dispatch-and-envelope`, `tasks-status-notifications`, `tasks-required-task-error`,
  `tasks-mrtr-composition`.
- `auth/*` (6): `auth/client-credentials-jwt`, `auth/client-credentials-basic`,
  `auth/enterprise-managed-authorization`, `auth/dpop`, `auth/dpop-nonce`, `auth/wif-jwt-bearer`.

Six of the 16 are therefore **authorization**-track (out per ADR-003 #3), not Tasks (out per
ADR-003 #2). Both are out of scope, so nothing downstream changes — which is exactly why an
un-enumerated count survives unchallenged.

**Second precision point, discovered while re-measuring.** MES-13 recorded `extension` as a valid
`--spec-version` value in 0.1.16. **It is not valid in 0.2.0-alpha.10:** `list --spec-version
extension` returns *"Unknown spec version: extension. Valid versions: 2025-03-26, 2025-06-18,
2025-11-25, 2026-07-28 (or 'draft' as an alias for 2026-07-28)"*. The `[extension]` tag still
appears in the bare `list` output, so the 16 are discovered there and are **not** selectable as a
spec version. Anyone reproducing this count with the 0.1.16 invocation will get an error, not a
smaller number.
**Priority Hint:** low · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision: validation is enforced OUTBOUND and deliberately NOT enforced INBOUND

**Description:** `MCP.Protocol.Extensions` implements the key rules from `schema.ts:39-49`
(`valid_meta_key?/1`, the general rule with an optional prefix) and `schema.ts:779-780`/`:876-877`
(`valid_identifier?/1` = the general rule **plus** a mandatory prefix — the one place an extension
identifier is stricter than a `_meta` key generally).

- **Outbound** (`normalise/1`, on our own declarations at `MCP.Server.Config.build/2` and
  `MCP.Client`'s `:client_capabilities`) — invalid identifiers and non-object settings are
  **dropped**, and an empty result becomes `nil`, i.e. **absent** from the wire rather than `{}`.
  This follows `Subscriptions.normalise/1`'s unknown-key posture rather than establishing a second
  convention: a declaration that cannot be honoured, dropped, leaves a wire that tells the truth.
- **Inbound** (`from_meta/1`, reading a peer's declarations) — **not validated, and never an
  error.** Two reasons, both cited. `versioning.mdx:121-124` puts the graceful-degradation
  obligation on the **supporting** party, and we support zero, so rejecting would be over-building
  against the spec. And silently rewriting a peer's claim would misreport what the peer said. A
  shape guard only (non-object → `%{}`), so a handler is never handed a crash; a key we would
  refuse to emit still reaches the handler verbatim.

**Reserved prefixes (`schema.ts:45`) are classified, never blocked, in either direction.**
Declaring support for an *official* extension **is** a reserved-prefix identifier —
`io.modelcontextprotocol/tasks` is the schema's own `ServerCapabilities` example — and on the wire
that is indistinguishable from inventing a private extension under a reserved prefix. The
reservation governs who may **define** an identifier, not who may **declare support for** one, so a
block would break the common legitimate case and a warning would fire on it every time.
`reserved_prefix?/1` ships as a documented predicate the SDK itself does not act on.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision: zero-by-default is structural, and the two lifetimes are kept apart by shape

**Description:** `seps/2133-extensions.md:99` requires extensions to be "disabled by default and
require explicit opt-in". Met by construction, not by a default value someone can forget:
`Config.detect_capabilities/2` never sets the field (extension support is **declared, never
detected** — there is nothing in a handler's shape to infer it from), and the nil-dropping
capability encoders make absence automatic. This is the same absent-not-false convention MES-15
established for undeliverable capabilities.

**The two lifetimes are different and the API does not imply otherwise.** The server's set is a
`build/2` key beside `:instructions` and `:server_info` — unmistakably launch-static, frozen at
`init/1`, which is honest because a server's supported set does not vary per request. The client's
is read through `from_meta/1`, whose *argument* is that request's `ctx.meta`; nothing is cached
between requests, so `schema.ts:96` ("Servers MUST NOT infer capabilities from prior requests")
holds by shape rather than by discipline. **No config-lifetime change was made, so there is nothing
to report under that heading.**
**Priority Hint:** low · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision: `extensions` is not `experimental`, and the handler-visible read is not identity

**Description:** `experimental` (`schema.ts:720` client / `:797` server) is free-form
"experimental, non-standard capabilities"; `extensions` (`:785`/`:882`) carries SEP-2133
identifiers with a mandatory prefix. `experimental` was already a field on both structs, parsed
inbound and never emitted, so reusing it would have looked like tidiness and been wrong. They are
separate fields, separate parse lines, separate wire keys, proved 2×2 (encode and decode × both
capability objects) with each test asserting the value lands under its own key **and** refuting its
appearance under the other.

**`from_meta/1` creates no new client-controlled channel** — `ctx.meta` already carried the raw
client `_meta` (C-3), so MC-1…MC-7 are satisfied without adaptation and no new MC-4 adjudication
arises. **The hazard the PM's item 6 pointed at survives its own false premise, and is addressed
anyway:** a handler author who has just learned to read client capability data off the context is
one step from gating access on it. The accessor's `@doc` therefore opens with the rule rather than
burying it — extension declarations are client-composed and self-asserted, they say what a peer
*supports* and never who it *is*, and they MUST NOT gate access to anything; caller identity is
`ctx.identity` alone. Anchored to `schema.ts:85-88`'s own warning that self-reported `clientInfo`
is "not verified by the protocol" and servers "SHOULD NOT rely on it for security decisions", so it
is the spec's stance and not a house rule. A test asserts a client declaration shaped to look like
identity cannot influence `ctx.identity`.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Correction (A2a): two doc sites enumerated the capability fields without `extensions`

**Description:** `docs/prd.md:146-147` (§5.2 Capability Types) and
`docs/implementation-plan.md:67-68` (task 1.4) both listed the server and client capability fields
and omitted `extensions` — pre-`2026-07-28` lists. Corrected in place (they are living
specifications rather than a permanent record, unlike this file), each noting that `extensions` is
a different field from `experimental` and that this SDK supports zero. `usage-rules.md` gains the
supported-extensions list SEP-2133:99 asks for; **the list is empty, and saying so is the point.**
**Priority Hint:** low · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Finding: F-1 — an oversized request body crashes instead of being refused (owner: MES-31)

**Description:** Surfaced while adjudicating "untrusted, unbounded input". `plug.ex:320` calls
`Plug.Conn.read_body(conn)` with no options inside a `with` chain whose `else` (`:327-369`) has
five clauses, all 2-tuples beginning `:error`. `read_body/2` returns `{:more, partial, conn}` when
the body exceeds its `:length` (Plug's default, 8 MB); that 3-tuple matches no clause, so the
`with` raises `WithClauseError` — a 500 where a clean 413 or `-32600` belongs. The bound is 8 MB,
inherited from Plug rather than chosen, and exceeding it fails loudly in the wrong way.

**Confidence, carried verbatim:** established by reading the code and Plug's documented return
contract; **not demonstrated with a failing test**, so it is reported as a defect to confirm, not
one confirmed. It does not block MES-16 — this ticket adds **no retention**: `from_meta/1` reads
through `ctx.meta` and copies nothing, so the answer to "does storing extension data change the
bound?" is **no**. **Owner: MES-31**, ruled by the PM — the same class as its existing two (non-map
body, `plug.ex:310`; by-position params, `:396`), all three on `handle_post/2`'s entry path, each
found by a question about something else. MES-31's DoD owes the demonstration.
**Priority Hint:** low · **Blocking?:** No · **Suggested Jira Ticket?:** MES-31 (recorded)

### Mechanics: A7 in its own words, and one deviation from the ratified plan

**A7 — every test written here is a positive control, and not one is a caught regression.** A
regression test earns its name by failing at a pre-fix SHA. None of these can: "extension" occurred
**zero** times in `lib/`, `test/` and `conformance/` before this ticket (re-counted, not inherited).
This is entirely new surface, so there is no pre-fix behaviour to regress from, and **none of them
is described as a caught regression anywhere.**

The assertions most flattering to themselves — the absence assertions (T1, T2) and the no-error
assertions (T10, T11) — pass trivially against a codebase that does nothing. Each was therefore
demonstrated **red against a deliberately-wrong fixture at the pre-code SHA**, in a scratch file
run before any `lib/` change existed and deleted afterwards: 6 controls, 6 failures, covering the
absence assertion against a present key and against a present-and-empty key, the no-error assertion
against a genuinely erroring `tools/call` and `tools/list`, the extensions/experimental separation
assertion against a value planted under `experimental`, and the client-side omission assertion
against a declared key. The presence halves are kept permanently in the suite (T3, T4, the
2×2), so each trivially-passing assertion has a live counterpart that would go red if the
implementation stopped discriminating.

**Deviation from the ratified plan, reported rather than absorbed:** the plan's file list named
`config.ex` but not `client.ex` for outbound validation. Outbound normalisation is applied on
**both** sides — `MCP.Client.init/1` normalises the consumer-supplied
`%ClientCapabilities{}.extensions` exactly as `Config.build/2` does the server's. D-4 states the
guarantee as "our own declarations are validated"; applying it to one direction only would have
left the guarantee false on the other, which is the over-claim class this project treats as a
defect. Also: `from_meta/1` is typed `%{optional(String.t()) => term()}` rather than the plan's
`=> map()`, because inbound data is deliberately **not** validated — typing the values as objects
would claim a bound the function does not enforce.

**Sizing, as reported before implementation and as it turned out:** smaller than briefed, and it
stayed smaller. One new module, ~11 lines across four existing files, and **no changes to
`dispatch.ex`, `plug.ex`, `connection.ex` or `tool_context.ex`** — no threading change, no
config-lifetime change, no new handler-visible channel, no new error path, no transport change.
`-32021 MissingRequiredClientCapability` (`error.ex:101-107`) still has zero call sites and, per
the graceful-degradation ruling, should keep them.

**Gates.** All six run individually after the last change; gate 6 as the two-step 6a+6b procedure,
never bare; `mix hex --version` = 2.5.1, at the floor. Branch `MES-16` under the CC service
identity. No version bump and no tag — still `2.0.0-dev.4` on `main`; `2.0.0-dev.5` is the PM's to
write in the squash-merge.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### MES-16 correction round 1 (P1–P6, 2026-08-19) — CC/CODE_CREATOR

Review verdict BLOCKING on R-1; the PM accepted the finding and issued a frozen six-item contract
(P1–P6, comment 24426) with P1 as the blocker and P2–P6 riding along because they are the same
files open once. Everything below is at the round-1 tip, on top of `29046c1`, which is **not**
amended — the re-review needs to see the delta.

**The lesson worth keeping, because it is not about regexes.** R-1 was found by probing the
identifier strings **between** the schema's worked examples — the region where neither the
implementation nor its tests had to think, because both were derived from the same five strings.
**A test suite built from the spec's own examples inherits the spec's blind spots**, and it does so
invisibly: the suite was green, comprehensive-looking, and could not tell a working validator from
a leaky one. The reviewer's mutation run (MUT-C) is the measurement of that — breaking
`normalise/1` so it stopped dropping invalid identifiers turned 7 tests red, but making it accept a
trailing newline turned **none** red. The generalisation for later tickets: when a validator is
written from a spec's examples, the cases worth writing are the ones the spec never wrote down.

**P1 (blocking) — `^…$` accepted a trailing newline, so a MUST-violating identifier reached the
wire.** In PCRE `$` also matches immediately before a final `\n`, so `@prefix_regex` and
`@name_regex` (`extensions.ex:114`, `:120` at `29046c1`) admitted a `\n` at the end of either
segment. `valid_identifier?("io.example/tasks\n")` was `true`, `normalise/1` passed it through, and
`server/discover` advertised `{"extensions":{"io.example/tasks\n":{}}}` — against schema.ts:48-49,
"MUST start and end with an alphanumeric character". Only `\n` slipped through (`\r` was already
refused), which is the tell that the fault was the **anchor** and not the character class. Fixed by
anchoring both patterns `\A … \z`, which match only at the true ends of the string.

Two things make this worth blocking on an input nobody types. First, the module's own moduledoc
says `normalise/1` *"is the only point at which the SDK could help a consumer emit a key that
violates a MUST"* — an **absolute** claim, false for this class, in the one function the whole
ticket exists to provide; that is the over-claim class this project logs as a defect. Second it
compounds: `valid_meta_key?/1` ships explicitly as *"the primitive"* for a later ticket to wire into
general `_meta` handling, where the input is **peer**-controlled rather than consumer-controlled. A
leaky primitive left in place now is a leaky validator on hostile input later, and the seam was
deliberate, so the fix belongs with the seam.

Closed in the same window: **`valid_meta_key?("") == true`**. schema.ts:48's *"unless empty"*
licenses an empty **name** after a prefix (`"com.example/"` is a valid key, and stays one); it does
not license a key that is empty in its entirety, which has no prefix and no name. Unreachable for
extensions today — `valid_identifier?("")` was already `false` for want of a slash — but it is in
the same advertised primitive.

**A7b — the new cases demonstrated red against the unfixed regexes.** With the tests in place and
only the two anchors and the `[""]` clause reverted: **3 failures**, exactly one per new case, each
failing on the newline/empty assertion while the `\r` control in the same test passed. That last
detail is the discriminating part: a fix that had merely widened a character class would have
turned the `\r` control red too. Restored, suite green.

**P2 — R-2 + R-3 ruled together as one property: nothing a consumer puts in `:extensions` may fail
later than the call that normalises it.** Two failures of that property existed. (a) A settings
value that is a map but not a **JSON object** (`%{"t" => {1, 2}}`) survived `is_map/1`, was
advertised, and then raised `Protocol.UndefinedError` out of Jason on **every** `server/discover`,
forever — a launch-time mistake surfacing at an unrelated place and time, to someone who cannot fix
it. (b) A **struct** passed as the whole `:extensions` value passed `is_map/1` and raised out of the
`for` comprehension inside `Config.build/2` itself, because a struct has no `Enumerable`.

One posture now covers all of it — **drop, warn, never raise, never defer**: a malformed identifier,
an unencodable settings value, and a wrong-shaped `:extensions` value are each dropped and named in
a `Logger.warning` carrying the identifier, the reason, **and the seam** (`MCP.Server.Config.build/2
:extensions` or `MCP.Client.start_link/1 :client_capabilities`). Not raising is deliberate: raising
would turn a typo in one identifier into a server that will not start. Dropping keeps the wire
truthful, which is what D-4 promised; the warning supplies the diagnosability that dropping alone
loses — the difference between a five-minute and a five-hour diagnosis of "my server never
advertises the extension I implemented".

Objecthood is now decided by **the encoder that will actually have to do it** — `is_map/1` **and**
`Jason.encode/1` returning `{:ok, _}` — rather than by `is_map/1` alone. Verified while choosing the
mechanism: `Jason.encode/1` **returns** `{:error, %Protocol.UndefinedError{}}` rather than raising,
for tuples, pids and structs with no encoder, nested and top-level alike, so the predicate is total
on any term and needs no `rescue`. **Corrected in round 2 (R-7): this did NOT make the module doc
claim true — it made it true of the *un*encodable half only.** "Encodes" and "is an object" are
different properties and the predicate checked the wrong one; the claim was made true in round 2,
by checking the encoding rather than the type. The round-1 sentence claiming otherwise is the
over-claim class this project logs as a defect, committed in the entry recording a fix for it. **This is also where the `Subscriptions` precedent stops transferring** (R-3, answering
CC's own round-0 question): a *peer's* malformed key has no channel back to whoever made it, so
dropping silently is the only truthful option there; a *consumer's* declaration is launch config in
a process the consumer is starting, so there **is** a channel, and using it is obligatory.

**P3 — R-4: the empty/absent collapse is inbound, deliberate, and now stated.** Outbound the module
is emphatic that `%{}` and absent are different claims; `from_meta/1` collapses them, and a peer
sending `"extensions": {}`, a peer omitting the key, and a peer sending something malformed all
read as `%{}`. The collapse is kept — we support zero, so all three are peers whose extensions we do
not support, and distinguishing them would be complexity with no consumer — but a reader told forty
lines earlier that the distinction carries meaning is entitled to know it is dropped on the way back
in. Said on `from_meta/1`, and the missing `{}` half is now asserted beside the omission half.

**P4 — R-6: a test name that asserted a property its assertion did not test.** `test "T10 — the
result is byte-identical …"` compares two **decoded** Elixir maps with `==`; nothing on that path is
serialised and map equality is key-order-insensitive, so it is not a byte comparison and could not
be one. In a project that logs over-claims as defects, that is the same error in miniature. Renamed
to "identical to"; the substance was sound and is unchanged (the reviewer confirmed independently
that it can discriminate — the two calls differ in `ctx.meta`, and the compared value is a whole
JSON-RPC response).

**P5 — R-5: the CHANGELOG entry, an open gap rather than a deviation.** CC asked whether to add one
and the PM's "yes" post-dated the close-out by five minutes. Added as an *Added* bullet under
`## [Unreleased]`, naming `MCP.Protocol.Extensions` and both options. The file's own defer-to-release
convention is overridden **with the reason recorded in the file**: that convention was written for
internal changes, and this ticket adds **public API**, which is precisely what a consumer scans a
CHANGELOG for.

**P6 — the two silent decisions in the reserved classifier, now stated.** The reviewer probed
between the schema's worked examples and found no defect but two undecided corners.
`io.ModelContextProtocol/tasks` is **not** classified reserved: schema.ts:45 is silent on case and
reverse-DNS labels are conventionally case-insensitive, so the other reading is available. A
**single-label** prefix (`mcp/thing`) is not reserved either: :45 is written about the *second*
label, and a rule about a label that is not there does not fire. Behaviour is **unchanged** — the
SDK never acts on the predicate — but it ships for consumers to make their own judgement with, and
this is the answer they get, so both are now on `reserved_prefix?/1` and the case decision is pinned
by a test so the doc cannot drift from it.

**Test delta, per item (A2d).** 12 new tests, plus 7 new assertions inside 2 existing tests: P1 —
3 newline assertions in *label rules*, 4 in *name rules*, 1 new empty-string test (3 red pre-fix);
P2 — 5 new tests (2 unit drop cases, warning-content, warning-silence, plus the client-seam
"unencodable value never reaches the wire") and 4 new end-to-end tests in
`extensions_negotiation_test.exs` asserting the property as `Jason.encode!/1` over a real
`server/discover` response; P3 — 1 new test; P6 — 1 new test. Two existing files gained
`@moduletag :capture_log` because the drop-and-warn posture makes deliberately-bad fixtures log by
design.

**Priority Hint:** high · **Blocking?:** No (closes the blocker) · **Suggested Jira Ticket?:** No

### MES-16 correction round 2 (Q1–Q5, 2026-08-19) — CC/CODE_CREATOR

Re-review verdict BLOCKING on two: **R-7**, a defect the PM found in round 1's own P2 fix, and
**R-8**, the reviewer working PM item 3 and answering it yes. The PM issued a frozen five-item
contract (Q1–Q5, comment 24430) with a ruling on the R-8 repair. Third commit on `MES-16`; neither
`29046c1` nor `57d49a0` amended.

**The lesson, and it now has three instances rather than one.** R-1, R-7 and R-8 are the **same
defect**: a guarantee stated at the width of the *intent* and checked at the width of a *proxy for
it*. An **anchor** stood in for "the whole string" (R-1); **encodability** stood in for
"is a JSON object" (R-7); a **struct pattern** stood in for "the value a consumer passed" (R-8).
Each proxy is correct on the cases anyone had thought to write down and comes apart just outside
them. What makes it actionable rather than a slogan is the measurement, and it is the same in all
three: **the full suite stayed green with the fix applied** — MUT-C for R-1, the reviewer's
`362 tests, 0 failures` under the corrected predicate for R-7, and for R-8 the 27 pre-existing
client tests that were green *with* the bypass and are green without it. "Tests pass" did not discriminate *once* across three defects in one ticket. A suite
written from the failure modes already named cannot see the next one; the case that discriminates
has to be written deliberately, and each of these three was found by a human reading the predicate
against the property, not by running anything.

**Q1 / R-7 (blocking) — encodability is not objecthood, and the gap is reachable from stdlib.**
`json_object?/1` asked `is_map/1` **and** "does `Jason.encode/1` return `{:ok, _}`?" and called the
answer "is it a JSON object?". Those come apart on any struct whose encoder emits a non-object, and
it takes **no custom `Jason.Encoder`** to reach one: `Jason.encode(~D[2026-08-19])` is
`{:ok, "\"2026-08-19\""}`, a JSON **string**, and `%Time{}`, `%NaiveDateTime{}` and `%DateTime{}`
behave identically. Such a value was KEPT and advertised — `{"com.example/date":"2026-08-19"}` on
the server seam and inside `_meta` on the client seam — against schema.ts:785/:882, which type the
field `{ [key: string]: JSONObject }` (`JSONObject` at :12). Fixed by checking the **encoding**
rather than the type: `match?({:ok, "{" <> _rest}, Jason.encode(settings))`. Narrowing the doc claim
instead was available and was rejected by the reviewer and the PM for the right reason — it would
have made the prose honest and left the SDK putting a schema-violating value on the wire at the one
seam whose stated job is to stop that. **The asymmetry the round-1 entry argued for survives**: a
struct that *derives* `Jason.Encoder` encodes to `{…}`, so it really is a JSON object and is still
kept. That is now a test, so "drop non-objects" cannot quietly become "drop every struct" — a rule
about Elixir types rather than about JSON.

**Q2 / R-8 (blocking) — the guarantee had a door round the side of the code implementing it.**
`normalise_extensions/1` matched `%ClientCapabilities{}` and passed **everything else** through
untouched (`client.ex:508`), into state and then into `encode/1` on every request. Both halves of
round 1's property failed there, and both were driven end to end rather than read: a plain map
`%{"extensions" => %{"no-prefix" => %{}}}` put a MUST-violating identifier on the wire with no drop
and no warning (R-1's class), and `%{"extensions" => %{"com.example/x" => %{"t" => {1,2}}}}` let
`start_link/1` return `{:ok, pid}` and then killed the client with `Protocol.UndefinedError` on its
**first** request (R-2's class — the deferred failure the whole property exists to rule out).

The trap is that **the neighbouring option invites the input**: `:client_info` accepts
`%Implementation{}` *or* a plain map and converts it, and `build_client_info/1` sits eleven lines
from the pass-through in the same `init/1` literal. Mirroring that leniency was the tempting repair
and the PM ruled against it: `%Implementation{}` has two fields a map can supply in full, while
`%ClientCapabilities{}` has five, so a conversion keeping the keys it recognised would trade a known
loud failure for a **fresh silent drop** — the exact class this ticket has spent two rounds closing.
Ruling taken as issued: **discard the whole value, warn naming what was lost, fall back to
`%ClientCapabilities{}`** — drop/warn/never raise/never defer, one level up from
`Extensions.normalise/2`. The latitude to convert instead was conditional on the conversion being
total, and `ClientCapabilities.from_map/1` is not: it reads string keys only and keeps just the five
it knows. The asymmetry with `:client_info` is now documented on the option itself and in
`usage-rules.md`, because an undocumented asymmetry *is* the trap.

**Q3 — the seven false absolutes, re-read after the fixes rather than re-worded.** The reviewer
swept twelve doc absolutes and found seven false, every one of them falsified by R-7 or R-8 rather
than by a third thing. All seven now hold with the code fixed: `extensions.ex:76` ("the only point",
= R-9, which needed no separate work), `:82-89` ("nothing may fail later" / "everything is checked
here"), `:74-75` ("settings values that would not encode as a JSON object"), `usage-rules.md` item 9
("never a failure at request time"), the CHANGELOG *Added* bullet, and this file's round-1 claim
(corrected in place above). One was **not** repaired by the code and had to be rewritten:
`extensions.ex:275-278` said the settings value is "a map that `Jason.encode/1` can encode — *i.e.*
it really will be a JSON object", and **that "i.e." is the defect itself**, the false inference
written into the documentation. It now states the check (the encoding begins with `{`) and both
ways a value can fail it, rather than the consequence someone hoped the check had.

**Q4 — R-10, R-11, R-12.** R-10: 500 dropped declarations made a single **42,004-byte** log line,
the bulk being one reason string repeated per entry. Now grouped by reason and capped at 10 named
identifiers per reason — and **the line says how many it elided**, because a truncated list that
does not admit it truncated is the silent-drop class wearing a different hat (measured: the same 500
now produce a **341-byte** line ending `(+490 more, not listed)`). R-11: the `Enum.reverse/1`
restored the order of a reduce over a **map**, whose iteration order is arbitrary — the reviewer's
1..500 run came out starting at `bad-127` — so it was restoring an order that never existed.
Replaced with a sort, which is an order the code can actually promise, and pinned by a test. R-12:
the empty-string decision was attributed to schema.ts:48 as though the schema settled it. It does
not — read literally, prefix-optional plus "unless empty" licenses `""` as much as it licenses
`"com.example/"`. **Refusing `""` is an interpretive narrowing we chose**, and the honest ground is
the reasoning already on the code: there is nothing there to name anything. Behaviour unchanged in
all three.

**A7b — each fix demonstrated red against exactly its own pre-fix mechanism, one at a time.**
Three separate runs, each reverting one mechanism with all the tests and the other two fixes in
place: the predicate → **2 failures**, both new R-7 cases (module-level and end-to-end), nothing
else; the client catch-all → **2 failures**, both new R-8 cases, the second one by the linked client
process actually dying, which is the defect rather than an assertion about it; `warn_dropped/2` →
**2 failures**, the cap test and the ordering test. The struct-derives-`Jason.Encoder` control
stayed green in the first run, which is what distinguishes "the check got tighter" from "the check
started banning structs".

**Test delta (A2d).** 362 → 369 (+7), 0 failures: R-7 — 1 unit drop test (4 stdlib date/time
structs), 1 kept-struct control, 1 end-to-end `server/discover` test asserting every advertised
settings value is an object after a real `Jason` round trip; R-8 — 2 client tests (the identifier
that must not reach the wire + the warning naming the discard; the first request that must not kill
the client); R-10/R-11 — 1 cap test, 1 ordering test.

**Priority Hint:** high · **Blocking?:** No (closes both blockers) · **Suggested Jira Ticket?:** No

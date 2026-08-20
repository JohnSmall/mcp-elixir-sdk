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

---

## MES-17 — JSON Schema 2020-12 for tool schemas (SEP-2106), server-side (2026-08-19)

Epic MES-22, which this closes. Gap register **K1**. All citations are to the published-final
`2026-07-28` schema at commit `5f5440bb26a62e2cf3440b92da5a667efa03b267`
(`schema/2026-07-28/schema.ts`, md5 `48a009165e07f6732e38baf91291de87`), to spec pages at the same
pin (`docs/specification/2026-07-28/server/tools.mdx`, md5 `c302125aae381e9be1feb96305341d4b`), and
to SEP-2106 itself — never to the ticket brief.

### Decision: what MES-17 delivers, and why validation is NOT part of it

**Description:** The ticket was dispatched as "make a validator work". It ships as SEP-2106's four
implementation obligations plus the gap that blocks the third one. **The reason validation is
deferred is not that the SEP is silent about it — it is not silent, and saying so would be a
permanent wrong reference in this log.** SEP-2106's Security Implications section opens:

> "JSON Schema validation already handles type checking, value constraints, and required field
> validation, and implementations MUST continue to validate all inputs and outputs against declared
> schemas."

A MUST, about inputs and outputs, in a Final Standards-Track SEP. Two properties of that sentence
bound it: it says MUST **continue**, so its function is "this SEP loosens the vocabulary and does
not thereby relax any existing duty", and it says "implementations", not "servers", so it does not
allocate the duty to a party.

Validation is deferred for two measured reasons, neither of which is the SEP's silence:

1. **It cannot be built where it would have to live.** There is no tool registry. `inputSchema`
   occurs in `lib/` on exactly four lines, all in `types/tool.ex` (`:15`, `:26`, `:39`, `:59`) and
   all pure decode/encode. The server's tool list is whatever raw maps `handle_list_tools/3`
   returns — cursor-paginated, handler-owned, with no ordering or stability guarantee relative to
   `tools/call`. So at `tools/call` time the dispatcher has a name and an arguments map and **no way
   to obtain that tool's schema** short of walking every page of `handle_list_tools` on every call.
   Closing that needs a new public API on the same `handle_list_tools` surface MES-18 touches: a
   ticket, not a task.
2. **It earns zero conformance credit.** Measured first-hand in both harness releases — see the
   finding below.

**MES-34 owns server-side argument validation**, and inherits: the registry design; the two security
risks a validator *acquires* (SSRF via `$ref`, composition-keyword CPU) with SEP-2106's own
mitigations; the settled `-32602` error shape; the dependency evidence below; the gate-6 residual
arithmetic; and `type: "object"` root enforcement. **MES-35 owns `x-mcp-header`.**
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** Raised — MES-34, MES-35

### Finding: F-2 — a server built on this SDK could not emit `structuredContent` at all

**Description:** The dispatched brief named two defects in `Tools.CallResult`'s encoder. Behind them
was a larger one it did not have. `dispatch.ex:175-199` is the only `tools/call` route in the tree,
and its result-shaping function had exactly four clauses — `{:ok, content, state}`,
`{:ok, content, is_error, state}`, `{:input_required, ...}` and `{:error, ...}` — **none carrying
structured content**. `handler.ex:54-79` offered no such return shape in either arity.

Consequence: a handler **could** advertise an `outputSchema` (tool maps come back raw and unchecked
from `handle_list_tools`) and could **never** satisfy it. A shipped over-claim of the same family as
the capability-honesty work in `MCP.Server.Config`. It also means SEP-2106's third obligation —
"`structuredContent` accepts any JSON value" — was not a type-widening on a live path here: **the
path did not exist.**

Closed by a fourth return shape: a **map** in slot 3, `{:ok, content, %{structured_content: v,
is_error: b}, state}`. Slot 3 was `boolean()` and nothing else, so a map is a new, non-colliding
shape and every existing handler keeps working untouched — asserted, not assumed.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No (closed here)

### Decision: absent versus JSON `null` is carried by KEY PRESENCE, and it needs no sentinel where a map is available

**Description:** `schema.ts:1819-1821` enumerates `structuredContent` as "any JSON value (object,
array, string, number, boolean, **or null**)". So "absent" and "present and null" are different
results and `nil` cannot stand for both. Both directions now distinguish them:

- **Handler → wire** (`t:MCP.Server.Handler.call_tool_extras/0`): the extras **map** carries the
  distinction in the key itself. Key absent → field omitted. Key present with value `nil` → JSON
  `null`. No sentinel is needed because a map already has a third state.
- **`Tools.CallResult`**: a struct does **not** have a third state — its key set is fixed at
  `defstruct` — so the distinction is carried by the field's default, the atom `:absent`, exposed as
  `CallResult.absent/0`. An atom other than `nil`/`true`/`false` is not producible by JSON decoding,
  so the sentinel cannot collide with a decoded value. `from_map/1` reads the same distinction off
  `Map.fetch/2`.

**Behaviour change, stated because it is one:** a consumer who previously wrote
`%CallResult{structured_content: nil}` to mean "absent" now gets `"structuredContent": null`. That
is the only way to express null, this is the 2.0.0 major window, and the type is reachable only
from dead code (below).
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Finding: F-1 — D-1 is real, but it is a PUBLIC-API defect, not a wire defect; `CallResult` and `ListResult` are both reachable only from dead code

**Description:** The brief's measured table (`structuredContent: false` dropped by
`tools.ex:141`'s falsy `if`) reproduces exactly. But nothing in `lib/` constructs, encodes or
decodes `Tools.CallResult`: the server assembles a bare map at `dispatch.ex:184-198`, and the client
replies `{:ok, result}` with the raw decoded map at `client.ex:385-397`. So the table measured the
struct's encoder **in isolation**, not any request this SDK can serve. It stays in scope — it is a
public, exported, documented type with a hand-written encoder, and a consumer using it directly hits
exactly that drop — but it is a public-API defect, and describing it as a wire defect would
over-claim.

**Say "reachable only from dead code", not "referenced by nothing".** `Types.Tool` *is* referenced
once (`tools.ex:43` aliases it, `:57` calls `Tool.from_map/1`) — from `Tools.ListResult`, which is
itself referenced nowhere in `lib/` outside its own definition. **The dead public-type family has
two members, `CallResult` and `ListResult`**, and the second is worth someone knowing.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Finding: F-4 — the behaviour's own moduledoc example produces a handler the dispatcher answers `-32601` to

**Description:** Found while building F-2's fix, measured rather than reasoned.
`dispatch.ex:412-422` builds `ctx_args = leading_args ++ [ctx, state]` and calls
`function_exported?(mod, name, length(ctx_args))` — so `tools/call` only ever invokes the
**context-bearing 4-arity** `handle_call_tool/4`, and replies `-32601 Method not found` when it is
absent. `MCP.Server.Handler`'s moduledoc example defines `handle_call_tool/3`. A handler written
exactly as the behaviour documents it therefore fails every `tools/call`; run at this ticket's tip,
it returns `{"code" => -32601, "message" => "Method not found", "data" => "handle_call_tool"}`.
`test/support/echo_handler.ex` is the same shape and is itself referenced by nothing.

Same over-claim family as F-2, on the documentation surface. **Deliberately not fixed here:**
whether the non-context arities are supported, or should be removed from the behaviour, is a
callback-surface decision that belongs with MES-34/MES-18, and changing the example either way
would assert that decision.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** Yes — PM to raise

### Decision: the dialect question — we implement none, so we neither honour nor refuse one

**Description:** `schema.ts:1962-1963` carries a worked example titled "With explicit draft-07 input
schema", beside the default-2020-12 one; `schema.ts:1995`/`:2003` make 2020-12 the **default** when
no `$schema` is given, not the only dialect. The brief offered three outcomes for a dialect we do
not implement — refuse at registration, validate under 2020-12 anyway, or skip validation for that
tool. **None of the three describes this SDK.** We do not implement *any* dialect, so a tool
declaring draft-07, 2020-12, or a dialect that does not exist is carried verbatim to the client,
which is the party that validates. It is not "skip validation for that tool" (we skip it for all
tools) and emphatically not "validate under 2020-12 anyway". The spec's draft-07 example is a case
we pass by construction rather than by effort, and there is a test that says so.

**CORRECTED IN ROUND 1 (S3/R-6): the decision stands; the justification was stated against the
absence of a normative text rather than against it.** `server/tools.mdx:291` and `:300` — the lines
defining `inputSchema` and `outputSchema`, the two fields this ticket owns — each say "Follows the
[JSON Schema usage guidelines]" and link to `docs/specification/2026-07-28/basic/index.mdx`
§"JSON Schema Usage" (`:247`–`:319`). I fetched that file at the pin
(`5f5440bb26a62e2cf3440b92da5a667efa03b267`, md5 `1b680a56e96533ff28f6eac07bd51bdc`, confirming the
reviewer's hash) and it carries four dialect obligations, verbatim:

- `:257` — "**Supported dialects**: Implementations MUST support at least 2020-12 and SHOULD
  document which additional dialects they support"
- `:291` — "Clients and servers **MUST** support JSON Schema 2020-12 for schemas without an
  explicit `$schema` field"
- `:292` — "Clients and servers **MUST** validate schemas according to their declared or default
  dialect. They **MUST** handle unsupported dialects gracefully by returning an appropriate error
  indicating the dialect is not supported."
- `:297` — "Schemas **MUST** be valid according to their declared or default dialect"

`:292` prescribes precisely one of the three outcomes this entry said none of applied to us, so
"none of the three describes this SDK" cannot stand on `schema.ts` alone. **The bound that makes
the decision survive is C-1's own:** every one of these four addresses "clients and servers" *as
validating parties* — each is a duty of the party performing validation. This SDK validates
nothing on either side, so, exactly as with SEP-2106's Security Implications MUST, the duty lands
on the consumer, and the honest sentence is "the duty is yours and this SDK neither discharges nor
polices it" rather than "the obligation does not exist". `:293`'s SHOULD ("Clients and servers
**SHOULD** document which schema dialects they support") is discharged by this entry and by
`MCP.Protocol.Types.Tool`'s moduledoc: **the answer is none, and every dialect is carried
verbatim.** All four are handed to **MES-34** with the rest, and MES-19 must draft K1 wording from
*this* paragraph rather than from the one above it.

**Two citation corrections while I was in there, because MES-19 inherits these strings.** The
review and the correction contract both cite `tools.mdx:290` and `:299`; the "Follows the JSON
Schema usage guidelines" lines are at **`:291`** and **`:300`** in the file at the pin (md5
`c302125aae381e9be1feb96305341d4b`, re-verified by me). And the page's path at the pin is
`docs/specification/2026-07-28/basic/index.mdx`, not `basic.mdx` — it renders at
`/specification/2026-07-28/basic`, which is where `tools.mdx` links. One more line on the same
page that nothing here had cited: `tools.mdx:293`, "`inputSchema` **MUST** be a valid JSON Schema
object (not `null`)", which belongs with the deferred root-`type` enforcement question (MES-34).
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision: the `$ref` sizing question is answered by the spec forbidding the expanding part

**Description:** The roadmap's named depth risk. SEP-2106's Security Implications section:
"Implementations **MUST NOT** automatically dereference `$ref` values that resolve to a network URI
(i.e. anything that is not a same-document JSON Pointer such as `#/$defs/Foo` or an internal
`$anchor`)"; an opt-in fetching mode MAY exist but "MUST be disabled by default"; and schemas
failing on an unresolved external `$ref` "SHOULD be rejected rather than silently treated as
permissive". So the required surface is **same-document JSON Pointer plus internal `$anchor`, and
nothing else** — a bounded, enumerable subset, and the spec's own bound rather than one we chose.

This SDK dereferences nothing at all, so the MUST NOT holds **by construction**. That is a stronger
guarantee than a check, and it is pinned by a canary test rather than by an argument: a real
listening socket, a tool whose `inputSchema` `$ref`s it, both `tools/list` and `tools/call` driven,
zero connections asserted — the same instrument the alpha harness's own
`sep-2106-no-network-ref-deref` client scenario uses.

**The canary's `tools/call` half was inert at round 1 and controlled nothing — corrected under S2
below.** The sentence "pinned by a canary test rather than by an argument" was itself half an
argument until then.

**Second normative surface for the same rules (S3/R-6), which this entry cited as SEP-2106-only:**
`basic/index.mdx:301-302` carries the network-`$ref` MUST NOT, `:304-307` the
opt-in-disabled-by-default MAY with its allowlist/loopback/timeout/size conditions, `:309-310` the
SHOULD-reject-on-unresolved-external-`$ref`, and `:312-318` the composition-keyword resource bound
("Implementations **SHOULD** apply reasonable bounds, such as a maximum schema depth, a cap on the
total number of subschemas, or a per-validation time budget"). Same content, so the sizing
conclusion is unchanged; recorded so MES-34 and MES-19 start from both surfaces rather than one.
The `:312-318` SHOULD is a duty of the *validator*, so it arrives with MES-34 rather than here.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision: no dependency was added; the evidence is recorded for MES-34 anyway

**Description:** A validator would sit on the tools path, which is not optional, and would have been
**the first mandatory runtime dependency added to this SDK since it was built** (`jason` and
`elixir_uuid` are the only two; `req`/`plug`/`bandit` are all `optional: true`). None was added.
The measurement is kept here so MES-34 starts from data rather than a survey.

`jsv` 0.22.0 (Apache-2.0), run in a scratch project outside the repo — `mix.exs` and `mix.lock`
untouched:

```text
1. Builds the alpha harness fixture VERBATIM (ref+anchor+allOf/anyOf+if/then/else) -> OK
2. Rejects 3 hand-built invalid arguments, accepts the valid one, with per-instance
   error paths (e.g. instanceLocation "#/address/city")
3. NO MUTATION: validate() returned a value IDENTICAL to its input
4. NO DEFAULT INJECTION: {"n":{"type":"integer","default":7}} + %{} -> %{}
5. draft-07: the spec's own explicit-dialect example builds and validates
6. NETWORK $ref, DEFAULT CONFIG: build ERROR {:resolver_error, ...}; canary NEVER
   connected to. Default resolver chain is Embedded+Internal, no HTTP resolver at all.
   It REJECTS rather than silently permitting -- the SHOULD in the same paragraph.
7. draft-04 (unimplemented dialect): build ERROR, not a silent fallback to 2020-12
8. $ref CYCLE (#/$defs/a <-> #/$defs/b): build OK, validate OK, 3 ms
9. 4 resource probes: 2000-deep nested object 15 ms; allOf x18 of anyOf pairs 0 ms;
   200,000-key argument 128 ms

COST: mix.lock is 26 packages; jsv adds FOUR new (jsv Apache-2.0, abnf_parsec MIT,
idna MIT, texture Apache-2.0). All permissive, compatible with our MIT. 26 -> 30.
```

**Honest width of that evidence, because it is narrower than it looks.** Probes 8 and 9 are four
probes, **not a bound**. `jsv` documents no maximum depth, no subschema cap and no per-validation
time budget, so the true statement is "no pathological behaviour was found in four attempts" and
**not** "validation is bounded in time and depth". SEP-2106 §5a asks for the second one. **Any
validation ticket must supply the bound itself; it does not come with the library.** Also not
verified here: the brief's disqualification of `ex_json_schema` as draft-4-only, and `xema`,
`json_xema`, `exonerate` and `jesse` were not surveyed at all — moot under this scope, and MES-34
should measure the field rather than inherit the one package that happened to be probed.
**Priority Hint:** high (MES-34 input) · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Decision: output validation — we do not, and will not; and the TextContent fallback is noticed, not injected

**Description:** Two obligations about output, decided together because they pull the same way.

**Output validation.** `schema.ts:2467` makes `structuredContent`'s conformance to `outputSchema` a
**SHOULD**. Failing a call because *our own handler* misbehaved converts that SHOULD into a MUST and
breaks working tools. A handler's `structured_content` reaches the wire verbatim, conforming or not,
and that is now written into `MCP.Server.Handler`'s docs as a stated policy rather than left as an
omission. **A divergence between the two normative surfaces at the same pin, recorded because it
looks like it contradicts this:** `server/tools.mdx` says "Servers **MUST** provide structured
results that conform to this schema", where `schema.ts:2467` says SHOULD. It does not change the
decision — that MUST binds the **server author**, who is our consumer, and this SDK cannot discharge
it for them; it only declines to enforce it against them.

**The TextContent fallback (SEP-2106 Backward Compatibility).** "To remain interoperable with older
clients, servers using array or primitive `structuredContent` **MUST** also emit a `TextContent`
block containing the serialized JSON (as already recommended in the tools specification)." Resolved
against `server/tools.mdx` at the pin rather than against the SEP's parenthetical: the tools page
states the **wider** form of the rule as a **SHOULD** ("a tool that returns structured content
SHOULD also return the serialized JSON in a TextContent block"), so the SEP narrows the subject
(array or primitive only) and strengthens the modality (MUST). Both readings are recorded because
the pair is easy to mis-cite in either direction.

**We notice; we do not inject.** The `content` list is model-visible data the handler authored, and
silently adding to it would change what every existing tool shows an LLM — the same instinct as
refusing to fail a call over our own output. Instead, when a result carries array or primitive
structured content and no content block's text is the serialized JSON, `dispatch.ex` emits a
`Logger.warning` naming the tool and citing the MUST. **The check is the exact condition, not a
proxy for it:** each text block is JSON-decoded and compared to the structured value, so a prose
summary does not count as compliance and a serialized-JSON block is never double-reported.

One consequence of the exactness worth stating: `server/tools.mdx`'s own array example emits a prose
text block ("Found 2 users: Alice…"), which does **not** satisfy the SEP's literal MUST. That is a
divergence in the spec's own material, not in our reading of it, and it is why an "any text block
counts" check would have been the wrong width.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Finding: F-5 — the conformance harness is preservation-only in both releases, and K1's evidence rests entirely on this ticket's tests

**Description:** Measured first-hand rather than inherited from MES-13, because MES-16's F-2
established this pattern repeats.

- Local `mcp-conformance` 0.1.13, `src/scenarios/server/json-schema-2020-12.ts`, 181 lines: four
  checks — tool found, `$schema` preserved, `$defs` preserved, `additionalProperties` preserved. Its
  only RPC is `listTools()`.
- `@modelcontextprotocol/conformance@0.2.0-alpha.11`, read out of the bundle: extended with the
  SEP-2106 vocabulary and **still preservation-only**. Its own sentence: "The test verifies that
  `$schema`, `$defs` and `additionalProperties` are preserved (SEP-1613), and that the composition
  (`allOf`/`anyOf`), conditional (`if`/`then`/`else`) and `$anchor` keywords are preserved
  (SEP-2106), *in the tool listing response*."
- **Neither release ever issues a `tools/call` in this scenario, and neither ever sends invalid
  arguments.** There is no conformance check anywhere in either suite that a server *rejects*
  arguments failing its own `inputSchema`.
- Scoring: the alpha's frozen `requirements/2026-07-28.yaml` omits `json-schema-2020-12` (server
  leg) from the required `server:` list (lines 38–76) and lists it under `not_scored:` at line 183
  with `reason: pending`. The header states pending scenarios "are never scored".

Same shape as MES-16's J1 (`sprint_4_issues.md:1352`): the scenario runs and is reported but
contributes zero to the SEP-1730 pass rate, so **MES-19's K1 evidence rests entirely on the tests
written here**. The difference from J1 is that the scenario at least exists, and gave us a free,
exact fixture — used verbatim in `test/support/schema_handler.ex`.
**Priority Hint:** high (MES-19 input) · **Blocking?:** No · **Suggested Jira Ticket?:** No (MES-19 owns it)

### Finding: `x-mcp-header` is entirely absent, and grepping its error code gives a false all-clear

**Description:** Reported, not scoped, per the brief. `schema.ts:1990-1993`: "Property schemas may
carry an `x-mcp-header` annotation to mirror the argument value into an HTTP header on the
Streamable HTTP transport." Zero occurrences of `x-mcp-header` in `lib/`, `test/` or `docs/`: not
implemented, not tested.

**The trap worth recording.** `-32020` **is** implemented — for a different thing: `Mcp-Method`/
`Mcp-Name` routing-header agreement (SEP-2243) at `plug.ex:332`, with three tests in
`streamable_http_stateless_test.exs`. So grepping the error code that `x-mcp-header` connects to
returns working, tested code and gives a false all-clear on a surface that is entirely absent.

The alpha harness has a whole `x-mcp-header` scenario family with MUST-reject validity rules,
extracted from the bundle: the annotation may sit only on **primitive** property types (`array` and
`null` MUST be rejected); duplicate header names across two properties MUST be rejected
**case-insensitively** (`MyField` vs `myfield`); and the name MUST NOT contain a space, a colon, a
control character or any non-ASCII character. The sibling scenarios `http-header-validation` and
`http-custom-header-server-validation` are also `not_scored: pending`. These are validity checks
**on `inputSchema`**. **MES-35 owns it.**
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** Raised — MES-35

### Decision: adversarial items with empty answers, recorded as empty rather than skipped

**Description:** Three of the brief's eight items have no defect behind them under this scope. Each
is recorded with *why it is empty*, because "empty by construction" and "empty because we looked"
age differently.

- **Where validation runs / what a handler sees — empty by construction.** No gate is added, so
  nothing sits between the peer and the handler: `dispatch.ex:177` passes `args` through untouched.
  Pinned anyway by a test that asserts argument **identity** (a nested map with a `null` inside,
  echoed back and compared) rather than absence of a crash — the assertion that will still mean
  something after MES-34 lands.
- **Two trust levels in one validator / remote DoS — unreachable today, real the moment we
  validate.** We never parse, resolve or evaluate a consumer schema, so a `$ref` cycle costs nothing
  and pathological arguments cost only JSON decoding (bounded elsewhere; MES-16's F-1 → MES-31).
  Under validation it becomes real and SEP-2106 §5a makes bounds a SHOULD.
- **When is the schema itself checked — satisfied vacuously, and that is what it is.** MES-16's rule
  (nothing a consumer supplies may fail later than the call that accepts it) holds here only because
  we never interpret the schema, so there is no "later". It bites the moment validation lands, and
  then it has teeth this codebase cannot currently satisfy: there is no registration call to fail
  at (no registry), and the nearest accepting call is `tools/list`, itself a per-request handler
  callback. Named now so MES-34 inherits it stated rather than rediscovering it in review round
  three.

**`type: "object"` at the `inputSchema` root: NOT enforced, in either direction, deliberately.**
`tool.ex:39` is a bare `Map.fetch!(map, "inputSchema")` on the client-decode side; the server never
inspects an advertised schema. The asymmetry is real — `schema.ts:1997` demands `type: "object"` and
`:2005` imposes nothing — and is now documented on `MCP.Protocol.Types.Tool` so it is not flattened
by accident. It is not enforced because a shape check without a validator is half a gate, and the
drop-versus-warn choice is a behaviour break that should be made **once**, with the validator, by
whoever owns MES-34.

**What a validation failure tells the caller: settled by the spec's own example, not by us.**
`examples/InvalidParamsError/invalid-tool-arguments.json` at the pin is
`{"code": -32602, "message": "Invalid arguments for tool calculate: Missing required property
'expression'"}` — **no `data` member**, one sentence naming the tool and the single failing
constraint, echoing the property *name* and no argument *value*. The disclosure dilemma dissolves:
the spec's own shape is already the conservative one and is still self-correctable by a model,
because it names what was missing. `schema.ts:241` permits `data` and leaves it undefined, so the
spec models the answer by example rather than by rule. Binds MES-34; MES-17 emits no such error.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### A7 evidence — which tests are caught regressions and which are positive controls

**Description:** Split pre-committed in the plan, then measured. **Genuine fail-then-pass, run
against `e1f5904` in a separate worktree with the new tests and none of the fixes:**

- `test/mcp/protocol/messages/tools_test.exs` — **7 failures**, all `CallResult`: `encodes false`
  and `from_map/1 decodes false…` (D-1's falsy `if`); the four absent-vs-null cases (D-2's harder
  half, which the old struct could not represent in either direction); and `isError` explicit
  `false` (the same falsy guard on the next line, which the brief flagged). The other nine
  `structuredContent` values (`true`, `0`, `1.5`, `""`, `"str"`, `[]`, `[1,2]`, `%{}`, `%{"a"=>1}`)
  passed pre-fix and are enumerated controls: **`false` is the only enumerated value Elixir's `if`
  treats as absent, and a suite that only tested the other nine would have stayed green.**
- `test/mcp/server/json_schema_2020_12_test.exs` — **17 failures of 30**, F-2's whole surface: every
  `structuredContent` emission case, the absent/null pair, the extras `isError` case and all four
  C-2 warning cases, because the return shape did not exist.

**Positive controls, green at `e1f5904` and labelled as controls — each with its discriminating
mutation demonstrated, one run per mutation:**

| Control | Mutation | Result |
|---|---|---|
| W-3 keyword preservation | strip `$defs` from each tool's `inputSchema` in `dispatch.ex`'s `list_result/3` | **2 red**, one naming `$defs` by keyword |
| C-2 exactness (compliant result is silent) | `serialized_json_of?/2` always `false` | **1 red**, exactly the "silent" case |
| C-2 exactness (prose is not compliance) | `serialized_json_of?/2` always `true` | **1 red**, exactly the "prose" case |
| C-2 trigger width (objects are outside the MUST) | drop the `is_list or not is_map` guard | **1 red**, exactly the "object never warns" case |
| W-4 `$ref` canary | ~~—~~ **round 1: no mutation was run, and the control was inert** — see S2 | round 1: **0 red** under a call-path resolver. Corrected: **1 red** |

**The W-3 mutation is worth its own line, because the first attempt at it failed to go red.**
Stripping `$defs` in `Types.Tool`'s encoder changed nothing: **that encoder is not on the
`tools/list` path at all** — the handler's raw maps go straight through `list_result/3`, which is
F-1 and F-3 showing up as a mutation that does not bite. The mutation had to be applied to the real
path before it discriminated. The preservation guarantee holds *because nothing touches the map*,
and a struct-level test would have measured a different thing entirely — exactly the trap MES-16's
R-1/R-7/R-8 named.

**W-5 is a control, not a regression, and the distinction matters:** a boolean `outputSchema`
already reached the wire correctly at `e1f5904` — the `Types.Tool` encoder drops `nil`, not
`false`. Only the **typespec** was wrong, so **dialyzer had been agreeing with a spec narrower than
the wire**. All its tests pass pre-fix. Nothing was caught; a future narrowing is now pinned.

**Its justification was over-wide, and is corrected in round 1 (R-7).** This entry read "a wire
that admits any JSON Schema", i.e. that MCP admits a boolean `outputSchema`. It does not:
`schema.ts:2005` types the field `{ $schema?: string; [key: string]: unknown }` — an **object**
type, to which `false` is not assignable — and the doc comment opens "An optional JSON Schema
**object**" (`:2000`). The sentence the wide reading came from is the next one, `:2001`, "This can
be any valid JSON Schema 2020-12"; generic 2020-12 does admit boolean schemas at any position, but
the TS type is the narrower and more specific of the two and governs. SEP-2106 removes the
requirement that the schema *declare* `type: "object"`, not that it *be* a JSON object. The
widening is kept — a permissive typespec on a field this SDK only copies costs nothing and pins a
future narrowing, which is what D-2 was — but **`json_schema_2020_12_test.exs`'s W-5 test is NOT
conformance evidence and MES-19 must not cite it as such.** It and `tool_test.exs`'s pair now say
so in the files, as does `MCP.Protocol.Types.Tool`'s moduledoc.

**Test delta (A2d).** 369 → 429 (+60), 0 failures. Enumerated: `tools_test.exs` +26 (20 value cases
× encode/decode for 10 values, 4 absent-vs-null, 2 `isError`); `tool_test.exs` +4 (2 boolean
`outputSchema`, 1 absent control, 1 keyword-verbatim case covering `not` and `$anchor`);
`json_schema_2020_12_test.exs` +30 (6 W-3 preservation, 1 W-5, 1 W-4 canary, 15 W-1 emission,
6 C-2, 1 argument identity).

**Suite flake — WAS REPORTED FIXED HERE AND WAS NOT. Corrected in round 1; see S1 below.**
`extensions_negotiation_test.exs:221` asserted `log == ""` inside an `async: true` test.
`capture_log/1` captures the **whole VM's** log for its duration, so any concurrent async test that
logs anything failed it — and C-2's warning is the first such logger. That diagnosis is right and
the narrowing to `refute log =~ "MCP extensions (SEP-2133)"` is a strict improvement, kept. **The
claim that it fixed the flake was not.** Round 1 evidenced "fixed" with "zero failures in six full-suite
runs"; the reviewer got a red in 23 seeds and it then reproduced 4 times out of 4 at `--seed 7819`,
which the PM and I have each reproduced independently. Six runs was never a bound. The sentence that
stood here — "it failed twice in eight full-suite runs before the fix and zero times in six after" —
was a false record in the entry that exists to document exactly this failure mode, and is struck.
**What actually closes it is `async: false`, not a narrower pattern:** the polluting module emits the
very string being refuted, so no pattern is narrow enough. Full account, including the two further
sites in this ticket's own new test file that nobody had named, under S1 in the round-1 section.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Method note: eight instances now of one failure mode, each found by the seat that did not write the claim

**Description:** The recurring defect on this project is **a claim and its evidence at different
widths**. MES-16 found three (R-1 an anchor for a boundary, R-7 encodability for objecthood, R-8 a
struct pattern for a value's shape) and in all three the full suite stayed green under the fix.
MES-17 adds a fourth, and it is the sharpest instance yet because of where it occurred: the plan
that diagnosed the failure mode contained it. Its §6 reason 1 said "SEP-2106 does not ask an SDK to
validate arguments", checked at the width of one section (Implementation Guidance, where the claim
is true) and stated at the width of the whole SEP — which contains a MUST about validating inputs
and outputs in its Security Implications section. The PM caught it before a line of code was
written; it is corrected at the head of this entry.

**Round 1 added three more, and the count is now seven.** R-1 ("fixed", evidenced by six runs),
R-2 ("the canary goes red the day someone adds a resolver", evidenced by a mutation never run) and
R-6 ("the dialect question is settled", evidenced by one of the two normative surfaces) — all three
in *this* entry, the one that names the mode. See the round-1 section at the end of this file.

**Round 2 added the eighth, and it is a different shape from the first seven.** F-9: the struct
clause of `warn_unusable_extras/2` — written in round 1, to fix this exact failure mode — told the
operator "structuredContent and isError are IGNORED" while dispatch read both fields off the struct
and put both on the wire. A claim stated wider than its check, in the code added to close that
class, in the one branch nobody probed.

**The finding is not the irony. It is that this failure mode is unrelated to care.** All eight
instances were produced by careful work, none was caught by the seat that produced it, and every
one was caught by a second reader with a different starting point. That is the strongest argument
this project has that **A6's authorship separation is load-bearing rather than ceremonial** — a
reviewer who inherits the author's starting point cannot find this class of defect, and more care
by the author does not either.

**Two corollaries, both now in force.** For prose: when you state a guarantee, state in the same
sentence how it is checked, make the two the same width, and where they cannot be, state the gap.
For tests, the narrower rule this ticket proposed and the PM adopted — **a stated discriminating
mutation is not evidence until it has been run; planning one is the same act as claiming one.**
That second rule is mechanical, needs no second seat, and is exactly what R-2 was: the mutation
table's one row marked "positive control by design" was the one row where no mutation had been run,
and it was the row that was wrong.

**And the eighth instance bounds that second corollary: it is necessary and NOT sufficient.** The
struct branch *did* get a test in round 1, and every mutation run against round 1 was run. The test
used `%URI{}` — the one struct that carries neither field, and therefore the one struct for which
the false sentence reads true. Running the mutation you thought of does not reach the branch you did
not: **the case you enumerate is the case you imagined.** That is why the mechanical rule cannot
replace A6 and why the argument for a second seat is not that they try harder — it is that they
imagine a different set. Applied here: when a warning's text depends on what the value *contains*,
the case that varies the contents is the discriminating one, and the empty-of-everything value is
the control, not the test.
**Priority Hint:** high (method, reusable) · **Blocking?:** No · **Suggested Jira Ticket?:** No

### Finding: the header provider had to be UNLINKED, and the failure contract said so before the code did

**Description:** The ratified contract promised that a misbehaving `:header_provider` fails *that
request* and never the transport. The first implementation used `Task.async/1`, which **links** —
and this transport does not trap exits, so a provider process killed outright would have travelled
the link and taken the transport (and `MCP.Client` behind it) down, in exactly the case the contract
excludes. `catch` covers raise/throw/exit; only an unlinked process also covers a kill. Rewritten as
`spawn_monitor/1` with a selective `receive` on our own ref and monitor — selective so it cannot
swallow an unrelated message from the GenServer's mailbox.

**Mutation run:** restoring `Task.async/1` turns exactly one test red — "a provider process killed
outright still only fails the request" — and nothing else. The claim was written down before it was
true, which is how it got checked.

### Finding: the seed sweep caught a flaky TEST — the instrument, not the behaviour

**Description:** Gate 5's sweep found `"a miss warns ONCE per tool name"` red on roughly half of
seeds. `capture_log/1` captures the **global** logger, so in an `async: true` suite it also sees the
identical cache-miss warning emitted by *other* tests for *their* tools; counting the generic phrase
measured the suite's concurrency rather than this client's behaviour. Fixed by counting a tool name
unique to the test. Two other log assertions in async files were tightened the same way, for the
milder failure of passing for the wrong reason.

**Worth recording because it is the sprint's own pattern once more, this time in a test:** a claim
("this warned once") checked at a width larger than the claim ("this phrase appeared once anywhere
in the suite's logs"). A single-seed run would have shipped it, and it is precisely what the sweep
exists to find.

### Gates — all six run individually at the final tip

```text
1  mix format --check-formatted        clean
2  mix compile --force --warnings-as-errors   clean (69 files)
3  mix credo                           1087 mods/funs, found no issues
4  mix dialyzer                        Total errors: 0, Skipped: 0, Unnecessary Skips: 0
5  mix test                            13 doctests, 541 tests, 0 failures
                                       + two disjoint 20-seed sweeps, 40/40 green
                                         (17/23/88/314/777/1601/2024/3607/4242/5000/
                                          6180/7777/8888/9999/10007/11235/12321/
                                          13337/14400/16180, and the earlier set)
6  mix hex --version                   Hex v2.5.1  (>= 2.5.1 floor met)
   6a baseline sentinel @ d697093      PASS — all 22 known advisory ids present
   6b mix hex.audit                    "No retired or security advisory packages
                                        found", exit 0
```

### Gate 6 — unchanged residual

**Description:** No dependency was added, so `mix.lock` is untouched and **MES-27's 6a residual is
unchanged at 21 unvalidated of 26 packages**. Stated rather than restated. `mix hex --version` is
Hex v2.5.1, meeting the documented floor; gate 6 was run as the two-step 6a sentinel + 6b audit,
never bare. Had `jsv` been ratified, all four new packages would have landed in the UNVALIDATED set
(none has ever carried an advisory, so the sentinel cannot cover them by construction) — 25 of 30,
with `jsv` on the non-optional tools path, joining `finch` and `thousand_island` as runtime residual
rather than dev/build residual.
**Priority Hint:** medium · **Blocking?:** No · **Suggested Jira Ticket?:** No

### MES-17 correction round 1 (S1–S6, 2026-08-20) — CC/CODE_CREATOR

Review verdict BLOCKING on R-1 and R-2; the PM reproduced R-1 independently and issued a frozen
six-item contract (S1–S6, comment 24445). Everything below is on top of `e9806c4`, which is **not**
amended — the re-review needs the delta. No version bump, no tag; still `2.0.0-dev.6`, the PM's at
the squash.

**The finding the PM adopted for the ticket, and it is the entry's own conclusion turned on the
entry.** R-1, R-2 and R-6 are one pattern — **a claim and its evidence at different widths**:
"fixed" evidenced by six runs; "the canary goes red the day someone adds a resolver" evidenced by a
mutation never run; "the dialect question is settled" evidenced by one of the two normative
surfaces. **The entry documenting that failure mode contained three fresh instances of it**, which
is the strongest confirmation yet of what it concluded: the mode is unrelated to care, and only a
second reader with a different starting point finds it. Two details sharpen it further. The
W-4 row of the mutation table was the *one* row marked "—, positive control by design" — the single
place no mutation was run — and it is the row that was wrong; the rule that would have caught it is
the one **I proposed in the same comment** ("a stated discriminating mutation is not evidence until
it has been run"). And R-1's evidence — "zero failures in six runs" — is a *narrower* width than the
sentence it was written to support, in the paragraph whose subject is that exact error. Neither was
carelessness, and neither was findable from where I was standing.

**S1 (blocking) — the flake is live, six runs was never a bound, and narrowing the pattern could
not have closed it.** Reproduced by me at `e9806c4`: `mix test --seed 7819` → 429 tests, **1
failure**, the same test and the same captured log the reviewer and the PM each got. `ExUnit.CaptureLog`
attaches a **VM-wide** `:logger` handler with no per-process filter, and `test/mcp/client_test.exs`
is `async: true` and declares `"no-prefix"` and `"bad"` as invalid extension identifiers **on
purpose** — so it emits `"MCP extensions (SEP-2133) — …"`, the very string the round-1 narrowing
refutes. **No pattern is narrow enough when the polluter emits the same string**; that is why the
narrowing was a strict improvement to the *assertion* and not a fix for the *flake*, and round 1
conflated the two.

Fixed by `async: false` on the modules that assert silence, and the mechanism was read off the
ExUnit this suite actually runs on — the abstract code of the installed `ExUnit.Runner` beam
(Elixir 1.19.5), not a doc claim: `async_loop/4` calls `ExUnit.Server.take_sync_modules/0` only once
`take_async_modules/1` stops returning modules, and then asserts `0 = map_size(...)` over the
running set — every async module waited down — before spawning sync modules one at a time. So a
sync module's capture window contains **no other test module**.

**Six sites, not four.** The contract named `extensions_negotiation_test.exs:237` and
`extensions_test.exs:267`, `:287`, `:351`. Grepping the class across `test/` turns up **two more, in
this ticket's own new file**: `json_schema_2020_12_test.exs:224` and `:231` (`refute log =~
"SEP-2106"`), which nobody had named and which are the identical defect — I wrote them in round 1
while fixing an instance of the same class three files away. The same module's *presence*
assertions (`assert log =~ "SEP-2106"`) are the same class in the other direction: a concurrent
module emitting that string would satisfy them falsely. `async: false` closes both directions. The
only other silence-assertion module in the suite,
`streamable_http_cache_scope_warning_test.exs` (MES-14), was already `async: false`.

**Bound, stated rather than implied:** `async: false` removes concurrently-scheduled *test modules*.
It does not make the capture per-process, so a process that outlives the module which started it
and logs during the window would still pollute. Nothing in this suite does that today; if it ever
does, the fix is a per-process capture, not a wider pattern. That is written into the test file so
the next reader inherits the bound with the fix.

**A7 for S1 — the fix is not evidenced by the sweep, and saying so is the point.** 43 green runs is
*the same width of evidence* that was wrong last round; it cannot distinguish "fixed" from "did not
reproduce". Two things do. (a) The **mechanism** above, read off the installed beam. (b) A
**mutation**: making `Extensions.normalise/2` warn on declarations that are perfectly valid turned
**all four** extensions silence assertions red, one each — so `async: false` did not buy green by
making them vacuous; they still discriminate. The sweep is reported as corroboration, not as proof:

```
seed 7819 x4              4/4 GREEN   (it was deterministic 4/4 RED at e9806c4)
reviewer's 23-seed set    23/23 GREEN (1117*k, k=1..8; 631*k, k=20..34 —
                                       includes 7819, 13882 and 15144)
second disjoint sample    20/20 GREEN (977*k, k=1..20)
```

**S2 (blocking) — the `$ref` canary's `tools/call` half was inert; fixed and the mutation run both
ways.** `json_schema_2020_12_test.exs` called `"echo_args"` — a tool that is not advertised and
whose schema contains no `$ref` — while the comment above it says "calling *that* tool". The
`$ref`-bearing tool is `network_ref_tool`. Corrected, plus two things the one-word fix does not
cover: `SchemaHandler` now has a `handle_call_tool` clause for it (without one the call fell to the
unknown-tool error, and a canary that measures an error path cannot see a resolver that runs on a
successful one), and the test now asserts the call **succeeded** before asserting no connection.

I ran the mutation the control exists to catch — a resolver on the `tools/call` path that looks the
called tool up through `handle_list_tools` and TCP-connects to any `http` `$ref` in its schema —
against both versions:

```
as shipped in round 1  ("echo_args")        -> 30 tests, 0 failures   INERT
corrected              ("network_ref_tool") -> 30 tests, 1 failure    DISCRIMINATES
   assert {:error, :timeout} = :gen_tcp.accept(listen, 200)
   right: {:ok, #Port<0.12>}
```

The mutation was reverted and the worktree re-verified clean before the gates were run. The W-4 row
of the mutation table above is corrected in place.

**S3 — the `basic/index.mdx` MUSTs.** Fetched at the pin and verified first-hand (md5
`1b680a56e96533ff28f6eac07bd51bdc`, matching the reviewer's); quoted at `:257`, `:291`, `:292` and
`:297` with the C-1 bound applied, in the dialect decision above, and handed to MES-34. Two
citation corrections came out of doing it: the linking lines in `tools.mdx` are `:291` and `:300`,
not `:290`/`:299`, and the page's path at the pin is `basic/index.mdx`, not `basic.mdx`. Both are
strings MES-19 will copy, which is the only reason they are worth a sentence.

**S4 (ruled) — the extras map is now dropped AND named.** MES-16 settled this posture on
`:extensions`; the extras map is a new consumer-supplied surface and did not follow it. Four
plausible mistakes each produced a successful, silently empty result, with no dialyzer complaint
(the type is all-`optional()`, so a misspelled key is not a mismatch). `dispatch.ex` now emits one
`Logger.warning` naming the tool and the unusable keys — a camelCase or string key by name, a
struct by its module, a non-boolean `:is_error` by its value — and **never raises**: a stray key
must not fail a tool call that otherwise works. A **correct** extras map, and in particular an
**empty** one (what a handler that adds keys conditionally returns, as `SchemaHandler` itself does),
is silent — pinned by a control, because a warning that also fires on correct input is noise and
then the case that matters is lost in it.

**S5 (ruled) — a cheap gate before the decode, and it does not help the case that decided the
ruling.** `serialized_json_of?/2` now checks that the block's first significant byte is the one the
value's JSON form must begin with (RFC 8259 leading whitespace skipped first) before decoding. It
can never reject a block that would have matched — the mapping is the JSON grammar's own
first-character rule. Measured on the dispatch path, 200 calls per case, gate off then on, same
machine:

```
array[2] + a 20k-key JSON object text block   4.671 -> 0.001 ms/call
array[20k] + its own serialized JSON          1.075 -> 1.109 ms/call   <-- UNCHANGED
object structuredContent (outer guard skips)  0.001 -> 0.001 ms/call
```

**The compliant case is the one the ruling named as deciding it, and the gate does nothing for
it** — a block that really is the serialized JSON passes the gate and is then parsed in full, as it
must be. No sound cheap check exists there: confirming equality needs either this decode or an
encode of the value (the same order of cost), and a byte comparison would be *wrong*, because JSON
key order inside an array element is not semantic. So a fully compliant server does still pay a
re-parse of what it just serialized, per call. Stated in the code and here rather than left to be
inferred from a number that did not move. No dedup and no throttle were added, per the ruling.

**S6 — R-5, R-7, R-8.** R-5: the test named "byte-identical" compares decoded maps; renamed to
"arrives intact — decoded-map equality, not bytes", assertion unchanged, with the reason written
down (byte identity would be the *wrong* check here). R-7: the boolean-`outputSchema` justification
is corrected in the `Types.Tool` moduledoc, in both test files and in the W-5 paragraph above —
the widening is kept as a permissive pass-through typespec, and the wire test is marked **not
conformance evidence**. R-8: the match was widened rather than the sentence narrowed, because a
compliant result should not warn — `serialized_json_of?/2` now accepts a string-keyed map, an
atom-keyed map and a `%MCP.Protocol.Types.Content.TextContent{}` struct (one clause covers the last
two, since a struct matches a map pattern on its fields). `handler.ex`'s promise now states that
width explicitly.

**A7 evidence for the new tests — measured, not asserted.** The 11 new tests were run against
`e9806c4` in a git worktree, tests only, none of the fixes:

```
GENUINE FAIL-THEN-PASS  (6 of 11 red at e9806c4)
  R-3  camelCase key named            \
  R-3  string key named                |  S4: nothing warned at all,
  R-3  struct in slot 3 named          |  so every naming assertion failed
  R-3  non-boolean :is_error named    /
  R-8  %TextContent{} struct is silent      \  the latent defect made live:
  R-8  atom-keyed content map is silent     /  a compliant result WAS warned at

ENUMERATED CONTROLS, green at e9806c4 and labelled as controls (5 of 11)
  R-3  a correct/empty extras map warns about nothing
  R-8  a %TextContent{} carrying PROSE still is not compliance
  gate leading JSON whitespace is still compliance
  gate a large non-matching JSON block is still not compliance
  gate every enumerated JSON value's own serialization still counts
```

Every one of those five controls has its discriminating mutation **run**, one per mutation, and each
turns exactly one test red — disjoint, so each measures its own condition rather than something
correlated with it:

| Control | Mutation applied | Result |
|---|---|---|
| correct/empty extras map is silent | treat every extras key as unrecognised | **1 red**, exactly that case |
| prose in a struct is not compliance | any atom-keyed text block counts as the JSON | **1 red**, exactly that case |
| leading whitespace is still compliance | drop the whitespace skip in the gate | **1 red**, exactly that case |
| enumerated values still count | wrong first-byte mapping for `false` (`~c"f"` → `~c"t"`) | **1 red**, exactly that case |
| corrected `$ref` canary | a resolver on the `tools/call` path | **1 red** (and **0 red** on the round-1 version — see S2) |

**Test delta (A2d).** 429 → 440 (+11), 0 failures, 9 doctests unchanged. All eleven in
`json_schema_2020_12_test.exs`: R-3 +5 (4 naming cases, 1 silence control), R-8 +3 (2 spellings,
1 prose control), first-byte gate +3 (whitespace, large non-matching, all ten enumerated values).
No test was removed. Three modules moved `async: true` → `async: false`.

**Gates — all six run individually at the round-1 tip.**

```
1  mix format --check-formatted        clean
2  mix compile --warnings-as-errors    clean (forced full rebuild, 68 files)
3  mix credo                           934 mods/funs, found no issues
4  mix dialyzer                        Total errors: 0, Skipped: 0, Unnecessary Skips: 0
5  mix test                            9 doctests, 440 tests, 0 failures
                                       + 43 seeds and 4x7819, all green (see S1)
6  mix hex --version                   Hex v2.5.1  (>= 2.5.1 floor met)
   6a baseline sentinel @ d697093      PASS — all 22 known advisory ids present
   6b mix hex.audit                    "No retired or security advisory packages
                                        found", exit 0
```

**Gate 6 residual: unchanged.** No dependency was added and `mix.lock` is untouched, so MES-27's 6a
residual stays at **21 unvalidated of 26** packages. Stated, not restated.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No


### MES-17 correction round 2 (T1–T4, 2026-08-20) — CC/CODE_CREATOR

Review verdict **MERGE**, nothing blocking; the PM took a round anyway for T1 alone and let T2–T4
ride along. Everything below is on top of `209999e`, which is **not** amended. No version bump, no
tag; still `2.0.0-dev.6`, the PM's at the squash.

**T1 (F-9) — the struct warning stated the opposite of what the code did.** A struct IS a map, so
`tool_extras/4` reads `:structured_content` with `Map.fetch/2` and `:is_error` with `Map.get/2` off
a struct exactly as it does off a plain map, and both reach the wire. The clause nevertheless
logged "structuredContent and isError are IGNORED" — a **universal claim over a conditional code
path**, false for precisely the struct that carries those field names. The behaviour is the right
one and is unchanged; the sentence now names what could not be used:

```text
%MCP.Test.ExtrasStruct{structured_content: [1,2], is_error: true}
  209999e  log  "...structuredContent and isError are IGNORED. Nothing is raised."
           wire {"content":[],"isError":true,"structuredContent":[1,2],"resultType":"complete"}
  round 2  log  "...its [:structured_content, :is_error] field(s) ARE read, exactly as a
                 plain extras map's would be, and DO reach the wire; every OTHER field is
                 IGNORED. Nothing is raised."
           wire unchanged, byte for byte

%URI{} (carries neither field)
  round 2  log  "...it has none of [:structured_content, :is_error] as fields, so NO extras
                 are read from it and every field is IGNORED. Nothing is raised."
```

**Why one sentence was worth a round, and it is the round's real finding.** This is a *live false
statement the SDK emits into an operator's log*, at the moment they are trying to work out where
their output went — and it points them away from the one place the value actually is. It is worse
than the silent drop the same code was written to fix. And it is **instance eight** of the claim/
evidence-width mode: written in round 1, in the code that closes that class, in the one branch
nobody probed. The round-1 test used `%URI{}` — the single struct for which the false sentence
reads true — so the case that could falsify it was never written. See the method note above for the
corollary that bounds: running the mutation you thought of does not reach the branch you did not.

**T2 (F-10) — S4's enumeration was four of five; the fifth is now dropped AND named.** The dispatch
clause is guarded `when is_map(extras)`, so a slot 3 that is neither a map nor the legacy `boolean()`
fell through to the legacy clause and was dropped by `maybe_error/2` without `warn_unusable_extras/2`
ever running. The **drop is inherited and unchanged** — this adds a warning and nothing else. A
keyword list matters most: it is the idiomatic Elixir spelling of an options map, and newly
plausible *because* this ticket made slot 3 a map.

```text
slot 3 value                    209999e            round 2
[structured_content: %{a: 1}]   dropped, silent    dropped, "...IGNORED in full..."
[]                              dropped, silent    dropped, named
:structured_content             dropped, silent    dropped, named
"true"                          dropped, silent    dropped, named
true  / false  (legacy)         isError / none     UNCHANGED, and still silent
```

**T3 (F-11) — the unrecognised-key line is capped at 10 and states the elided count.** The key
count is consumer-controlled and unbounded while Logger truncates at ~8 KB, so the join built a
string Logger provably discarded. A cap alone would be the silent-drop class again, so the count is
in the same line. Measured on the dispatch path, 20 calls per case, both versions on this machine:

```text
unrecognised keys   log chars 209999e -> round 2   ms/call 209999e -> round 2
        1               272   ->   272                0.037 ->  0.031
      100              2445   ->   486                0.248 ->  0.056
     5000              8131   ->   503                8.747 ->  1.626   (8131 = Logger's cut)
correct extras map        0   ->     0                0.002 ->  0.001
```

**Stated at its real width: the cap removes the string building, not the enumeration.** The residual
1.626 ms at 5000 keys is `Map.keys |> Enum.reject |> Enum.sort` over the map — work proportional to
what the handler itself built, and irreducible if the count in the message is to be true. Sorting is
kept so the ten keys shown are deterministic rather than whatever the map iteration order yields.

**T4 (F-12) — citation corrected, verified first-hand at the pin, not inherited.** Re-fetched
`docs/specification/2026-07-28/basic/index.mdx` at `5f5440bb26a62e2cf3440b92da5a667efa03b267`, md5
`1b680a56e96533ff28f6eac07bd51bdc`, 498 lines: the network-`$ref` MUST NOT is `:301-302`, and
`:303` is blank. Corrected in this entry and in the `json_schema_2020_12_test.exs` comment, both of
which MES-19 copies. `:304-307`, `:309-310` and `:312-318` re-read at the same fetch and are
correct as already written.

**A7 evidence — four discriminating mutations, each run, each turning exactly its own test red.**
Full revert of `dispatch.ex` to `209999e` with the new tests in place: **5 red of 47** — both F-9
tests, the F-10 four-shapes test, the F-11 truncation test, and the R-3 `%URI{}` test's new
assertions. **That is 4 of the 6 new tests; the other 2 are positive controls and are named as
such** rather than left to read as regressions: the legacy-boolean test and the `≤10` test are
green at `209999e` *and* after the fix, because each exists to pin that a fix did **not** reach
where it should not.

| Mutation applied to the fix | Result |
|---|---|
| restore the old universal struct sentence | **3 red** — both F-9 tests and R-3's `%URI{}` test, nothing else |
| remove the non-map slot-3 clause (and its `is_boolean` guard) | **1 red** — the F-10 test only |
| raise the cap to 1,000,000 (cap removed, suffix kept) | **1 red** — the F-11 truncation test only |
| keep the cap, drop the ", and N more" suffix | **1 red** — the F-11 truncation test only |

The last two are a pair on purpose: they are the two halves of T3's claim, and the truncation test
fails under *either*, so it measures "capped **and** says so" rather than only one of them. The
`≤10` test stays green under both, so it is the control that the cap does not fire early. The
legacy-boolean test (`true`/`false` still work, still silent) is the control for T2's new clause —
it is a **positive control**, not a caught regression, and is labelled as such here because the F-10
clause could otherwise have swallowed the legacy shape unnoticed.

**Test delta (A2d).** 440 → **446 (+6)**, 0 failures, 9 doctests unchanged. All six in
`json_schema_2020_12_test.exs`: F-9 +2 (a struct carrying both fields; a struct carrying one, which
also pins that a nil-valued *field* still puts an explicit JSON `null` on the wire), F-10 +2 (four
non-map shapes in one test; the legacy-boolean control), F-11 +2 (>10 truncated with the count;
≤10 listed in full). Two assertions were added to R-3's existing `%URI{}` test. No test was removed.
One new test-support module, `MCP.Test.ExtrasStruct` (`test/support/extras_struct.ex`) — a struct
whose fields are named like `call_tool_extras/0`, which is the thing round 1 had no way to express.

**Gates — all six run individually at the round-2 tip.**

```text
1  mix format --check-formatted        clean
2  mix compile --force --warnings-as-errors   clean (68 files)
3  mix credo                           936 mods/funs, found no issues
4  mix dialyzer                        Total errors: 0, Skipped: 0, Unnecessary Skips: 0
5  mix test                            9 doctests, 446 tests, 0 failures
                                       + seeds 3037*k, k=1..20 (disjoint from every
                                         earlier sweep) all green, and 7819 / 13882 /
                                         15144 green — 23/23
6  mix hex --version                   Hex v2.5.1  (>= 2.5.1 floor met)
   6a baseline sentinel @ d697093      PASS — all 22 known advisory ids present
   6b mix hex.audit                    "No retired or security advisory packages
                                        found", exit 0
```

**Gate 6 residual: unchanged.** No dependency was added and `mix.lock` is untouched, so MES-27's 6a
residual stays at **21 unvalidated of 26** packages.
**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

## MES-18 — Client-side core conformance closure (2026-08-20)

Epic MES-23. Gap register items **CG1, CG2, CG4, CG7**, plus four defects the register does not
contain and the deferred rotating-bearer item. All citations are to the pinned spec commit
`5f5440bb26a62e2cf3440b92da5a667efa03b267` — `server/tools.mdx` (md5
`c302125aae381e9be1feb96305341d4b`), `basic/transports/streamable-http.mdx`, `basic/index.mdx` (md5
`1b680a56e96533ff28f6eac07bd51bdc`), `basic/versioning.mdx` (md5 `6b2476585e9e10e1b4c3706a832f5fb5`)
— and to the conformance harness **pinned at `@modelcontextprotocol/conformance@0.2.0-alpha.11`**,
never to "the alpha": it moved from `alpha.10` to `alpha.11` between MES-13 and this ticket.

`basic/versioning.mdx` was **not** in the local `/tmp/spec2026` pin and was fetched from
`raw.githubusercontent.com` at the same commit during this ticket, as `basic/index.mdx` was during
planning. Anyone re-checking those two citations on a fresh container must fetch them first.

### Decision: the sizing outcome and the A1 split boundary — CG3 leaves, everything else stays

**Description:** The register's "MES-18 is one-ticket-sized" verdict predated CG7 and three landed
tickets, so it was re-derived rather than inherited. By volume the whole set fits: ~3000–3200
insertions estimated against MES-15's 4410 actual. **That measurement argues against a split and is
recorded here because it does.** The split was requested and ratified on a different ground —
contract count. CG7 changes the `MCP.Transport` behaviour once (a per-message header channel); CG3
would change it again and differently (a long-lived, non-blocking request that outlives the call
that started it), because `handle_call({:send_message, ...})` at
`streamable_http/client.ex:120-129` performs the POST **synchronously inside the GenServer**, so a
held-open stream blocks the whole transport and every other request on that client. CG3 is a second
execution mode, not incremental parsing.

**Boundary:** out of MES-18 is *client-side `subscriptions/listen` stream consumption, in full*.
Nothing else moved; everything on the request/response path stayed. **Owner: MES-38**, ruled a new
ticket rather than folded into MES-29 (stdio listen) — a ticket spanning two transports and two
roles has the same review problem the split was granted to avoid. Whichever of MES-38/MES-29 lands
first extracts the shared demux-by-`subscriptionId`. CG3 is also the only item worth **zero** scored
credit — no client scenario for `subscriptions/listen` exists in alpha.11's client list or its
`not_scored` block — so deferring it costs the conformance number nothing.

Two stale in-tree pointers to the old owner were corrected:
`streamable_http/client.ex:8-18` and `:275` now say MES-38.

### Decision: the CG7 ruling, and the `Mcp-Name` / `Mcp-Param` distinction

**Description:** CG7 (`x-mcp-header`) was absent from the gap register and is **2 of the 7** scored
core client scenarios; the PM ruled its client half in on ADR-003 sub-decision 4's standing
authority. Implemented as `MCP.Protocol.HeaderMirror`, derived from `tools.mdx:346-368` and
`streamable-http.mdx:371-545` — **not** from the harness fixtures, which are narrower than the spec.

**A2d — what is IN: all six annotation constraints and all four encoding rules. What is OUT:
nothing.** Three of the six earn **no harness credit** and are ours alone: `number`-exclusion, the
integer safe range, and static reachability. The alpha.11 fixture's ten invalid tools (its own `Ua`
map, read first-hand) cover only four classes — not-empty (1), primitive-only (3), uniqueness (2),
charset (4) — and each of those ten is named in a test in `header_mirror_test.exs`, so the
harness-covered subset is checkable rather than asserted. This confirms MES-35's "the
harness-derived list was narrower than the spec" from the fixture itself.

**The server-side `Mcp-Name` Base64 decode landed HERE, and `Mcp-Param-*` decode did not.** The rule
applied is not a ticket boundary but a breakage: `streamable-http.mdx:501-504` requires a server to
decode an encoded `Mcp-Name` before comparing it to the body, and `plug.ex:882-883` compared raw.
That was dead code while our client sent no `Mcp-Name`; the moment CG1 landed it became a
**deterministic self-rejection** — our own conformant client refused by our own server with `-32020`
on any non-header-safe tool name. `Mcp-Param-*` decode stays with **MES-35** because this server
never compares those headers at all (zero occurrences in `lib/`): no comparison, no
self-incompatibility, no urgency. `Mcp-Name` is in because it breaks; `Mcp-Param` is out because it
does not.

The self-rejection was **demonstrated, not argued**: reverting the one-line decode with the new
tests in place turns `self_compatibility_test.exs` red twice, including the end-to-end
client→server call, with HTTP 400 / `-32020`.

### Finding: four defects on the path of scored scenarios, two of them refuting the register

**Description:** None of these are in the register or the brief; three sit on scenarios the register
calls conformant or unexamined.

- **D-1 — MRTR is NOT conformant; the register's `CONFORMANT` verdict is refuted.** `client.ex:409`
  put `requestState` unconditionally, so a server that sent none got a **present key holding JSON
  `null`** on the retry. The `sep-2322-client-no-state-omitted` check tests presence
  (`n !== undefined`) and JSON `null` decodes to JS `null`, which is `!== undefined` — so
  `sep-2322-client-request-state`, one of the seven, failed. **A register entry marked done that is
  not done is more expensive than one marked open: nobody would ever have looked.**
- **D-2 — transport send failures were discarded.** `send_request/4` ignored `send_message/2`'s
  return value and registered the request as pending regardless, so an HTTP 400, a refused
  connection or a rejected content-coding all became `{:error, :timeout}` after the full 30s, with
  the real reason only in a log line. A conformance defect and not merely an ergonomic one: a
  scenario that rejects the first request and waits for a retry gets a 30-second stall instead, and
  **a client timeout fails a scenario outright**.
- **D-3 — `request-metadata` was not the free pass the register implied.** The scenario rejects the
  **first** request — whatever it is — with `-32022` and seeds
  `sep-2575-client-retry-supported-version` at WARNING, and **a WARNING fails the scenario**
  (`overallFailure` disjoins `s>0` in the harness's own reducer). Left alone the check stays WARNING
  and the 30s stall from D-2 risks the client timeout as well. **C-1 discharged:** the retry is
  required by normative text, not by a check name — `basic/versioning.mdx:69-71`, "The client
  **SHOULD** select a mutually supported version from the `supported` list and retry the request, or
  surface an error to the user if no compatible version exists." The retry is gated on an
  intersection with `@supported_versions`, which holds the stateless core alone, so ADR-003
  sub-decision 5 is untouched: it can never reach for 2025-11-25.
- **D-4 — the protocol version was configured twice and could diverge.** The header came from the
  transport's `:protocol_version`, the body `_meta` from `MCP.Client`'s, and `start_transport/1`
  forwarded only `:owner`. Latent (the defaults agreed) but a MUST
  (`streamable-http.mdx:255-259`) and a precondition of D-3: after a retry changes the version the
  header must change with it. Fixed structurally — the transport now derives the header from the
  message's own `_meta`, falling back to its configured default. One source of truth, so lockstep is
  no longer a thing two modules have to remember.

### Correction: two register entries are wrong, in opposite directions (for MES-19)

**Description:** MES-19 walks the register item by item, so both belong there rather than only here.

1. **CG2 is stale in the OPPOSITE direction from the brief's reading.** The brief said the inbound
   half was absent because `discover.ex` contains no "extensions". True grep, wrong file:
   `Discover.Result.from_map/1` delegates at `discover.ex:74` to `ServerCapabilities.from_map/1`,
   which parses it (`server_capabilities.ex:36`), and `MCP.Client` stores and exposes it. CG2 was
   **functionally closed, evidentially open** — had the brief been taken at face value, this ticket
   would have built a parser that already exists. It now has tests and a doc line.
2. **CG3's register entry and the MRTR entry disagree with reality in opposite ways:** MRTR is
   marked CONFORMANT and is not (D-1 above).

Also for MES-19, on mechanism rather than conclusion: the sibling server scenarios
(`http-header-validation`, `http-custom-header-server-validation`, `json-schema-2020-12`) **are**
present in alpha.11's `requirements/2026-07-28.yaml` as `not_scored` with `reason: pending`
(`:183-197`) — they are not "absent from the scored list". Same conclusion (no server-side scoring
credit), different mechanism; "run and reported, never counted" and "absent" are different claims
about the same zero.

### Decision: CG5 and CG6 deferred, with owners that can act

**Description:** Both are SHOULD-level and earn zero scored credit; both are adjudicated rather than
left silent.

- **CG5 (`ttlMs`/`cacheScope`) → MES-39.** `discover.ex:77-78` parses both; no store exists. The
  deferral originally cited MES-9, read off `discover.ex:20-22`'s own moduledoc — and **MES-9 is
  `Done`, resolved, in the closed Sprint 3**. A deferral to a finished ticket reads as owned in a
  register walk and cannot act. The general form is worth carrying: *"there is an owner" checked at
  the width of "something names a ticket" rather than "that ticket can still act".* Neither seat got
  it from the moduledoc; it took reading the issue's status. The stale prose is fixed in this
  commit.
- **CG6 (trace-context `_meta`) → MES-32.** `meta.ex:53-57` defines the three W3C keys and nothing
  writes them; the write side is `with_meta/2`'s closed three-key map, which is MES-32's defect.
  CG6 has exactly two implementations: add a fourth hard-coded key to a function whose defect is
  that its key set is closed, or fix MES-32 first and then CG6 is ~10 lines. MES-32 owns both and
  is cheaper for doing them together.

### Decision (C-2): the cache-miss and staleness policy, decided rather than defaulted

**Description:** `Mcp-Param-*` mirroring needs the tool's `inputSchema`, which only `MCP.Client`
holds, so `call_tool/4` can only mirror for tools this client has listed. A miss is a **normal
event**: nothing in this SDK requires `tools/list` first and the protocol is stateless.

The chosen policy is **announce, then recover through the spec's own path**, and explicitly **not**
an implicit list (which would spend a round trip on every cold call whether or not the tool has
annotations) and **not** an error (which would break working code):

1. On a miss the call goes out unmirrored and logs a warning naming the tool, **once per name**.
   Without it the request is indistinguishable on the wire from a tool that has no annotations —
   F-9's shape again.
2. If the server actually needed the headers it answers `-32020`, and the client then does what
   `streamable-http.mdx:533-539` prescribes: refresh via `tools/list` and retry the call **once**.
   The same mechanism covers a **stale** cached schema, which has no local signal at all and is the
   half a miss-only policy cannot reach.

**Stated bound (A2d):** the refresh fetches the **first page only**. A tool on a later page is not
found, the retry goes out unmirrored, and the server's second rejection reaches the caller —
correct, one round trip more expensive than necessary, and not silent. A failed refresh surfaces
the **original** `-32020`, not the refresh's error: the caller asked for a `tools/call`.

**The pagination trap, separately:** a cursor-bearing `tools/list` is a page, not a listing, and
`list_all_tools/2` walks `nextCursor`. Replacing the cache per response would leave it holding only
the last page and every earlier tool would silently stop mirroring. Rule: **reset on a cursor-less
request, merge on a cursor-bearing one** — applied to the excluded-tools record too.

### Decision: tool exclusion is visible, and the encoder is the safety boundary

**Description:** Two adversarial items with real answers.

**Exclusion (F-9 again).** `tools.mdx:360-366` requires a client to exclude a tool whose
`x-mcp-header` annotations are invalid, so `list_tools/2` can return fewer tools than the server
sent with no error. The spec asks for a log line (SHOULD); this does that **and** exposes
`MCP.Client.excluded_tools/1` returning `[{name, reason}]`, so an operator can *ask* where their
tool went instead of grepping for a line that may have scrolled away.

**Injection.** `x-mcp-header` puts model-controlled values into HTTP headers by design. Sanitisation
does not happen before or after the Base64 step — **the Base64 step *is* the safety decision**:
convert to string → test safety (every octet 0x20–0x7E, no leading/trailing whitespace, not
sentinel-shaped) → emit as-is or replace wholesale with the sentinel. There is no branch on which an
unsafe octet reaches the transport, so CR/LF request-splitting is closed **structurally** rather
than by a filter a later edit could reorder. The SDK does **not** rely on Finch or Mint rejecting a
bad value — that would be the unguarded-property mistake one layer down. A second, independent gate:
header *names* are validated at `tools/list` time and an invalid one excludes the whole tool, so a
hostile name never reaches assembly. Critical Rule 6 is untouched — identity still comes only from
the transport pipeline; what crosses here is tool *arguments*.

Horizontal tab (0x09) is treated as **unsafe** and encoded, though RFC 9110 admits it in a field
value: a tab is not "safely represented as a plain ASCII header value" and encoding costs nothing.
The harness's own predicate agrees.

### Decision: CG4 needs no production code, and gets a test anyway

**Description:** `basic/index.mdx:299-310` — "Implementations **MUST NOT** automatically
dereference `$ref` values that resolve to a network URI." It is a **prohibition, not a capability**,
and the scored scenario inverts on a canary counter (FAILURE iff the canary was hit). We satisfy it
**by construction of an absence**: nothing in `lib/` walks a schema, `Jason` is a pure codec with no
socket, and `Req` only fetches the URL it is handed — only ever `state.url`. That is not luck, but
it is **unguarded**: the property holds because a feature is missing. T-CG4 therefore stands a
canary HTTP server up, serves an `inputSchema` whose `profile` is a `$ref` at it, runs
`list_tools` + `call_tool`, and asserts zero hits — plus a **control on the control** proving the
canary registers a hit when one is made, because an instrument that silently no-ops reports the same
thing as a clean tree.

**Zero production code, zero dependency, and the largest cost item in the original brief evaporates.**

### The scenario-mapped prediction (DoD item 2)

Every row presupposes MES-24 ships an adapter that drives the method under test; today
`conformance/client_adapter.exs` routes only `initialize` (which does not exist in the stateless
core) and an old `tools-call`. Where a row's risk is adapter-shaped rather than client-shaped it is
said in the row.

| # | Scenario | Before | After | CG / item | Proving test |
|---|---|---|---|---|---|
| 1 | `tools_call` | PASS | **PASS** | CG1 + CG7 | `self_compatibility_test.exs` end-to-end; `routing_headers_test.exs` |
| 2 | `request-metadata` | **FAIL** | **PASS** | D-2, D-3, D-4 | `client_defects_test.exs` D-3 (one-shot retry), D-4 (lockstep), D-2 (propagation) |
| 3 | `sep-2322-client-request-state` | **FAIL** | **PASS** | D-1 | `client_defects_test.exs` D-1 (absent, null, echoed) |
| 4 | `http-standard-headers` | FAIL | **PASS** | CG1 | `routing_headers_test.exs` T-CG1a/b/c |
| 5 | `http-custom-headers` | FAIL | **PASS** | CG7 | `header_mirror_test.exs` (fixture vector); `routing_headers_test.exs` end-to-end |
| 6 | `http-invalid-tool-headers` | FAIL | **PASS** | CG7 | `header_mirror_test.exs` (ten fixture classes); `client_tool_schemas_test.exs` (exclusion) |
| 7 | `json-schema-ref-no-deref` | PASS | **PASS** | CG4 (no code) | `client_conformance_test.exs` T-CG4 canary |

**NAMED PREDICTION RISK — row 4 is the one to look at hardest (C-3, carried verbatim from the
plan).** alpha.11's `http-standard-headers` fixture still serves `mcp-session-id` and handles
`initialize`, so it cannot be determined from source alone whether the runner drives it at the
stateless wire. If it does not, the scenario is an ADR-003 sub-decision 5 **expected failure** and
this PASS is wrong. **MES-24 settles it by running it; this ticket cannot.** What *is* settled: our
not sending `initialize` is harmless, because those rows go SKIPPED and SKIPPED is excluded from the
denominator entirely.

Two scoring facts from the harness's own reducer that change how these rows should be read: **a
WARNING fails a scenario** (it is a disjunct of `overallFailure`), and **a client timeout fails one
outright**, independent of every check.

### A7 evidence — which tests are caught regressions and which are positive controls

**Exactly two are genuine caught regressions**, both written against the unfixed tree at `2829769`,
run there, and observed to fail for the stated reason before any fix was made:

| Test | Observed failure at `2829769` |
|---|---|
| T-D1 `client_defects_test.exs` | `retry params carried nil under a PRESENT requestState key` — and the null-variant clause too |
| T-D2 `client_defects_test.exs` | `left: {:error, {:transport_send_failed, {:http_error, 400, _}}}` / `right: {:error, :timeout}` |

**Everything else is a positive control and is labelled as one in its own file** — T-CG1a/b/c,
T-CG7val, T-CG7enc, T-CG4, T-CG2, T-D3, T-D4, the exclusion/cache tests and the rotating-bearer
tests. None of that surface existed at `2829769`, so "the suite is green" discriminates nothing
about it, and it is not offered as if it did.

One test is neither, and is labelled as a third thing: the **reachability control** in
`self_compatibility_test.exs`. It cannot be a regression against `2829769` (the client sent no
`Mcp-Name`, so the server's raw comparison was unreachable) but it *is* discriminating against the
intermediate state where CG1 has landed and W2 has not. **Mutation run:** reverting
`decode_header_name/1` turns exactly two tests red — the reachability control (400 instead of 200)
and the end-to-end client→server call — and nothing else.

### Test delta (A2d)

446 → **541 (+95)**, 9 → **13 doctests (+4)**, 0 failures. Per file: `header_mirror_test.exs` +34
(+4 doctests, which are the spec's own encoding-examples table); `routing_headers_test.exs` +22;
`client_defects_test.exs` +14; `client_tool_schemas_test.exs` +13; `client_conformance_test.exs` +6;
`self_compatibility_test.exs` +6. No test was removed. `MCP.Test.MockTransport` gained a
`:send_result` failure mode (D-2 needs a transport that refuses), per-message opts recording (the
CG7 seam), and `send_message/3`.

**One transcription error caught by a doctest, recorded because it is the shape this project keeps
finding:** the sentinel example was first written `PT9iYXNlNjQvbGl0ZXJhbD89`; the spec table at
`streamable-http.mdx:518` says `PT9iYXNlNjQ/bGl0ZXJhbD89`. The implementation was right and the
citation was wrong — a claim checked at the width of what was remembered rather than what was read.

### Gate 6 — unchanged residual

**No dependency was added** and `mix.lock` is untouched, so MES-27's 6a residual stays at **21
unvalidated of 26** packages. CG7 needs only `Base` from stdlib; CG4 needs nothing (it is a
prohibition); the header provider needs only `spawn_monitor/1` and `receive`, both stdlib. (This
line first read "the header provider needs only `Task`" — corrected in the correction round below,
where M-3 records why that word is not a nit.)

**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### MES-18 correction round (M-1–M-4, 2026-08-20) — CC/CODE_CREATOR

Review verdict **NON-BLOCKING, recommend merge** — with R-3 named as something the reviewer "would
not merge without". The PM resolved that tension toward one short round and issued a **frozen**
four-item contract (M-1–M-4, comment 24474), overruling CR's *severity reasoning* on R-1 while
accepting their measurement. Everything below is on top of `29297be`, which is **not** amended. No
version bump, no tag; still `2.0.0-dev.6`, the PM's at the squash.

**The round's own finding, and it is this sprint's recurring one wearing a third set of clothes.**
CR classified R-1 non-blocking because "the class is pre-existing and unchanged by this ticket".
That is a true statement about the *class* and it does not settle the question, which is what **this
change did to this path**: on `main` a `tools/list` answered `"result": null` fell to the generic
`finish_response/4` and returned `{:ok, nil}`; on this branch the same bytes raised `BadMapError`
inside the GenServer and took the client, every other pending request and the linked transport down.
A severity assessed at the width of the class rather than the width of the change — the same shape
as the claim/evidence-width mode logged eight times above, now in a *review verdict* rather than in
code or a test.

**M-1 — a malformed `tools/list` result fails the REQUEST, not the client** (`client.ex:564`).
`protocol.ex:63` classifies any message carrying `id` + the `result` **key** as a Response, so a
non-object under it decodes cleanly and reaches the `{:list_tools, _}` clause. That clause now
carries `when is_map(result)`, and a new clause below it logs and replies
`{:error, {:malformed_result, result}}`.

```text
tools/list answered with            29297be                      round
  "result": null                    ** (BadMapError) client DOWN  {:error, {:malformed_result, nil}}
  "result": "oops"                  ** (BadMapError) client DOWN  {:error, {:malformed_result, "oops"}}
  caller                            EXIT (not {:error, _})        an ordinary error reply
  other pending requests            lost with the GenServer       unaffected
  tool caches                       n/a                           untouched (not read as "no tools")
```

The reply is an **error, not `{:ok, nil}`** — restoring `main`'s benign value would leave the caller
unable to distinguish "the server sent something unusable" from "the server has no tools", which is
F-9's shape and the very defect this ticket spent D-2 on. **Deliberately NOT widened** to the rest of
the class per the contract: `tools/call`'s `input_required?/1` at `:602` and its siblings are
**MES-42**'s.

**Reported, not fixed (contract freeze).** The `{:refresh_for_retry, entry, _error}` clause at
`client.ex:579` (`29297be`) does the same unguarded `Map.get(result, "tools")`, and unlike `:602` it
is code **this ticket added** — so it is *not* purely another instance of a pre-existing class, and
MES-42's scope should say so. **Measured at the round's tip**, so it is not an inference from the
shape of the code: a server that answers `-32020` and then answers the refresh with `"result": null`
still kills the client, M-1's guard notwithstanding.

```text
call_tool -> -32020 -> refresh answered "result": null
  ** (BadMapError) Map.get(nil, "tools", nil)
      lib/mcp/client.ex:602: MCP.Client.finish_response/4   <- the refresh clause
  client alive afterwards? false      caller got: an EXIT, not {:error, _}
```

Not widened into, per the freeze — a class-wide defensive sweep inside a correction round is how a
short round stops being short. **The PM subsequently amended the contract to include it: it is M-5,
in the round-2 entry below.**

**M-2 — the warn-once record shares the cache's GENERATION** (`client.ex:851`).
`mirror_misses_warned` is a statement about the *current* cache ("we have already told the operator
about this name"), so it now resets in the cursor-less clause of `update_tool_cache/4` and is left
alone in the merge clause. CR measured the defect end to end; both halves are now tests.

```text
warn -> list [t] -> list [] (cursor-less) -> call t     29297be SILENT   round WARNS
warn -> list [other] (cursor-BEARING)     -> call t     29297be silent   round silent (unchanged)
```

The second row is the reason the fix is not "reset it everywhere": a page merges rather than
replaces, so re-arming there would make `list_all_tools/2` re-warn once per page walked.

**M-3 — two public statements documented the contract this ticket's own finding 1 REJECTED**
(`streamable_http/client.ex:69`, `usage-rules.md:100`, plus the `Gate 6` line of the entry above,
found while editing it). Both said the header provider "runs in a `Task` with a bounded timeout".
It does not, and **the link is the defect**: `Task.async/1` links, this transport does not trap
exits, and a killed provider comes back down the link. The wrong version was in the moduledoc, in
the user-facing rules and in the PM's own ratification while only a private comment 325 lines from
the code carried the right one — so a maintainer "tidying" `spawn_monitor/1` into a `Task` would be
**following the documentation** and would reintroduce a proven process-death defect. That is why a
wording change gates a merge here and an ordinary doc nit would not.

**Mutation, run for this round rather than inherited** — swap the `spawn_monitor/1` for
`Task.async/1` and 2 tests go red, both with `** (EXIT ...) killed` arriving through the link: the
killed-provider test (`routing_headers_test.exs:429`) and the hanging-provider test (`:459`). The
doc now states that mutation, so the next reader can re-run the thing the sentence rests on.

**M-4 — the one `capture_log` assertion the round-1 sweep did not reach**
(`client_tool_schemas_test.exs:100`). `assert log =~ "bad"` is a three-character substring against
the **global** logger in an `async: true` file — finding 2's mechanism, milder failure mode: it
passes for the wrong reason rather than going seed-dependently red. Now
`assert log =~ ~s(EXCLUDING tool "bad" from tools/list)`.

**Discriminating mutation (the first one chosen did not discriminate, and that is recorded rather
than tidied away).** Deleting the name from the warning entirely reddens *both* the old and the new
assertion — the reason string contains only capitalised `"Bad"` — so it proves nothing about the
tightening. The mutation that separates them is a warning naming the **wrong** tool:

```text
warning names          assert log =~ "bad"    assert log =~ ~s(EXCLUDING tool "bad" ...)
  "bad" (correct)      PASS                   PASS
  no name at all       fail                   fail
  "bad_other"          PASS  <-- wrong reason fail
```

**R-5's relocation, and my named risk was on the wrong row.** C-3 named row 4
(`http-standard-headers`) as the row to watch hardest, on the grounds that alpha.11's fixture still
serves `mcp-session-id` and handles `initialize`, and said it could not be settled from source. CR
settled it from source (`@modelcontextprotocol/conformance@0.2.0-alpha.11`, `dist/index.js`): row 4
pushes **SKIPPED** for each method the client never exercises — free, exactly as C-3 said SKIPPED
is — while rows 5 (`http-custom-headers`) and 6 (`http-invalid-tool-headers`) push **FAILURE** for
each check never emitted. So an un-exercised check **fails closed** on the two rows I did not flag and
degrades harmlessly on the one I did. Every row's predicted PASS still stands on the behaviour;
what moves is where the adapter risk lives. **Recorded on MES-24 by the PM**, because a later run
cannot recover it: row 5 needs the adapter to call `test_custom_headers` *and*
`test_custom_headers_null`, row 6 needs a `tools/list` *and* a call to `valid_tool`. The method
point is the one worth keeping: a risk assessed at "which row is hardest to reason about" rather
than "which row fails worst when the assumption breaks" — the same width error as R-1's severity,
made by the author instead of the reviewer.

**Test delta.** 541 → **545 (+4)**, 13 doctests unchanged, 0 failures. All four are in
`client_tool_schemas_test.exs`: two for M-1 (null result, string result) and two for M-2 (the reset
re-arms, the merge does not). **All four are positive controls for behaviour that did not exist at
`29297be`** — but each was run against `29297be`'s logic by mutation and observed to fail for the
stated reason, so they discriminate rather than merely pass. No test was removed; M-4 tightened one
in place. No production dependency, no `mix.lock` change, so **MES-27's 6a residual stays at 21
unvalidated of 26**.

**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

### MES-18 correction round 2 (M-5, 2026-08-20) — CC/CODE_CREATOR

**The reusable part of this item is the exchange, not the guard clause.** M-1's round found a second
instance of the same defect *inside M-1's own subject*, on the `-32020` refresh path. The contract
was frozen at four items, so it was **reported and not fixed** (comment 24475, quoted evidence and
all) — and the PM then **amended the contract** (comment 24476) rather than the author widening it.
That is the division of labour the freeze exists to produce: the seat that finds something under a
freeze reports it; the seat that owns the scope decides whether the freeze moves.

The PM's stated reason for moving it is the same rule they used to overrule CR's severity on R-1,
applied to themselves: *"the class is pre-existing" is a claim about the class; the check that
matters is what this ticket did to this path*. M-1's path existed on `main` and was merely benign
there; **this path does not exist on `main` at all** — the `-32020` recovery is this ticket's. So
merging would have meant refusing to ship a client-kill on a path this ticket *worsened* while
shipping one on a path this ticket *created*, purely because the contract was written before the
second was known. The amendment is declared **final**: anything further in this class, including a
third instance of the same guard, goes to a ticket.

**M-5 — the refresh clause, guarded the same way** (`client.ex:596`). `{:refresh_for_retry, entry,
original_error}` now carries `when is_map(result)`; a new clause below it logs and replies. Scope
held to that one clause: `input_required?/1` at `:602` and every other sibling remain **MES-42**'s.

```text
call_tool -> -32020 -> refresh answered   145efb7                       round 2
  "result": null                          ** (BadMapError) client DOWN  an error reply
  caller                                  EXIT (not {:error, _})        {:error, {:malformed_refresh_result, nil, %Error{code: -32020}}}
  other pending requests                  lost with the GenServer       unaffected
  the retry                               never sent (client dead)      abandoned deliberately; 3 messages total
  tool caches                             n/a                           untouched (a cursor-less refresh RESETS)
```

**Which error the caller sees, chosen rather than fallen into.** Two rules in this file pull opposite
ways and the reply satisfies both instead of dropping one. `route_response/3`'s failed-refresh clause
surfaces the **original** `-32020`, because "tools/list also failed" answers a different question than
the caller asked. But the PM's constraint is that "the refresh came back unusable" must not be
**indistinguishable** from "the refresh found no tools" — and that second case ends in a bare
`-32020` from the server's *second* rejection one round trip later (the existing "a SECOND -32020 is
surfaced" test shows exactly that shape). A bare `-32020` here would therefore collapse the two. So
the reply carries **both**: the tag naming the refresh as malformed, the term that arrived, and the
caller's own true answer. The tag is `:malformed_refresh_result`, deliberately **not** M-1's
`:malformed_result`: that one failed the request the *caller* made, this one failed a request the
*client* made on their behalf, and a caller matching on the M-1 tag should not silently absorb it.

**Discriminating mutation.** Remove `when is_map(result)` from the refresh clause and exactly one
test goes red — the new one — with `** (BadMapError) Map.get(nil, "tools", nil)` at
`lib/mcp/client.ex:602` arriving as an `(EXIT from ...)`, i.e. the caller loses the client rather
than receiving an error. The compiler also warns the new clause "cannot match", which is the
mutation announcing itself. 17 other tests in the file stay green, so the test pins this clause and
not the file's general behaviour.

**Test delta.** 545 → **546 (+1)**, 13 doctests unchanged, 0 failures. **A positive control** — the
`-32020` recovery it exercises did not exist at `2829769` — but run against `145efb7`'s logic by the
mutation above and observed to fail for the stated reason. No production dependency, no `mix.lock`
change, so **MES-27's 6a residual stays at 21 unvalidated of 26**.

**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** No

---

## MES-24 — Conformance adapter rework for 2026-07-28, CLIENT LEG (2026-08-20)

Phase 1 of two. The server leg (`server_adapter.exs` + `server_handler.ex` + the 37-scenario run)
is phase 2 on the same branch. Every figure below is pinned to
`@modelcontextprotocol/conformance@0.2.0-alpha.11` run as
`conformance client --command "mix run conformance/client_adapter.exs" --requirements 2026-07-28`,
against the tree at `bb573d1` + this branch's adapter commits. Results adjudicated from the saved
`-o` artefacts, never from terminal scrollback.

**Revised after CODE_REVIEWER's round-1 review (verdict: CHANGES REQUIRED).** Three BLOCKING
findings, **none of them in the SDK** — every one was a claim in this report, or in the instrument
that produced it, that was **wider than what had actually been checked**. The measurement did not
move: 8/32 scored, and every per-scenario check count is unchanged. What needed correcting was what
the report said the measurement meant. The three, and where each is now answered: the
`request-metadata` 8/8 is contingent on a **drive policy** (BLOCKING 1 → the three-figure table
below and its own finding); row 6's eleven checks were **insensitive to the SDK** (BLOCKING 2 → the
derived drive, with a no-SDK control and a mutation); and RULING 3's recorded justification was
**false for the gate this project runs** (BLOCKING 3 → the restated ruling near the end). The
findings are left in place rather than tidied — that a ratified ruling was checked and failed is
itself the record MES-19 needs.

**The PO ruling this sits under, unchanged:** the 2.0.0 conformance claim rests on our own ported
acceptance suite; the harness supplies *supporting evidence* with its numbers reported. A bad figure
is a finding to classify, not a claim to retract — and a good figure does not upgrade the claim.

### The measured client-leg figure, and the honest way to state it

**THREE figures, each with its axis named, and none of them is the headline** (PM RULING 2 as
amended after review). The first is about what the harness reports; the second about what this SDK
implements; the third about what the *adapter* chose to keep doing after a failure. A reader given
one number recovers neither of the other two, so MES-19 may pick a headline only by publishing all
three.

| # | Figure | Value | Axis it measures |
|---|---|---|---|
| 1 | Scored scenarios reported PASS | **8 / 32** | what the harness reports |
| 2 | — DRIVEN by this adapter **and** passing | **7 / 32** | what the SDK implements |
| 3 | — core (non-`auth/*`), under a **consumer-realistic drive** | **6 / 7** | what the *drive policy* contributes |

| Supporting figure | Value |
|---|---|
| Scored client scenarios in the frozen 2026-07-28 set | **32** |
| — of which passed WITHOUT THE SDK DOING ANYTHING | **1** (`auth/resource-mismatch`) |
| Core (non-`auth/*`) subset **as driven** | **7 / 7** |
| Scored scenarios FAILING | **24 / 32**, all `auth/*` |
| `not_scored` run and reported, never counted | **7 run, 6 failing** — enumerated below |

**Figure 1 → 2, the delta:** `auth/resource-mismatch` passes on a negative check with no
implementation behind it (see the finding below). **Figure 2 → 3, the delta:** `request-metadata`'s
8/8 is contingent on `drive/2` carrying on past a failed `Client.connect/1` — see the drive-policy
finding below. Both deltas are subtractions from a number that would otherwise read as tested
behaviour.

**`7/7` is a legitimate sub-figure and a dangerous headline.** The 25 `auth/*` scenarios are not
absorbed into a denominator — they are *deleted* from it, which reads as a better result than the
honest one. The denominator is **32**. Enumerated (A2d), the 25 scored `auth/*` empties, reason
*"this SDK has no OAuth client surface: no token acquisition, no metadata discovery, no
`WWW-Authenticate` handling"*: `metadata-default`, `metadata-var1`, `metadata-var2`, `metadata-var3`,
`basic-cimd`, `scope-from-www-authenticate`, `scope-from-scopes-supported`,
`scope-omitted-when-undefined`, `scope-step-up`, `scope-retry-limit`, `token-endpoint-auth-basic`,
`token-endpoint-auth-post`, `token-endpoint-auth-none`, `pre-registration`, `resource-mismatch`,
`offline-access-scope`, `offline-access-not-supported`, `authorization-server-migration`,
`iss-supported`, `iss-not-advertised`, `iss-supported-missing`, `iss-wrong-issuer`, `iss-unexpected`,
`iss-normalized`, `metadata-issuer-mismatch`. That is a bounded, nameable gap MES-19 can price.

### Finding: a scenario can score PASS *because* the implementation is absent — measured, not derived

`auth/resource-mismatch` reports **OVERALL: PASSED**, one check, `SUCCESS`: *"Client rejects
mismatched resource"*. This adapter drives nothing for it; the SDK has no OAuth client. The check is
**negative** — it asserts the client did NOT do something — and a client that does nothing satisfies
every negative check trivially. Two of the three checks in `auth/authorization-server-migration`
scored `SUCCESS` the same way (that scenario still fails on its one positive check).

This is worse than the zero-denominator hollow PASS predicted during planning: there the denominator
is 0 and a careful reader can notice. Here the denominator is 1, the check is a genuine `SUCCESS`,
and **nothing in the output distinguishes it from a capability we implemented**. A naive `8/32`
credits this SDK with a scenario it has no code for.

**Consequence for MES-19: a scored pass rate over a suite containing negative checks is not a
measure of implemented behaviour unless the empties are enumerated first.**

**Correction after review — this section originally counted the shape as occurring ONCE, and it
occurs at least ELEVEN times.** Ten more instances were inside a *driven* scenario this report was
citing as CONFIRMED evidence (`http-invalid-tool-headers`), and a twelfth of a different kind sits
in `json-schema-ref-no-deref`. See the BLOCKING 2 finding and the F-3 enumeration below. Reading the
referee's source is what found the instance above; it could not have found the others.

### Finding: an un-exercised check does not fail uniformly — CR's asymmetry, confirmed by running it

Confirmed first-hand at alpha.11, and the adapter is built to the resulting obligation:

| Scenario | Un-driven cost | What the adapter drives | Observed |
|---|---|---|---|
| `tools_call` | FAILURE | discover; `tools/list`; `add_numbers` with **numeric** `a`,`b` | 2/2 SUCCESS |
| `request-metadata` | FAILURE (NotObserved) | discover; `tools/list`; `tools/call` | 8/8 SUCCESS |
| `sep-2322-client-request-state` | FAILURE ×5 | all four `test_mrtr_*` tools with an `:on_input_required` resolver bound | 5/5 SUCCESS |
| `http-standard-headers` | **SKIPPED (free)** | all **six** watched methods that exist at this wire | 9 SUCCESS + 2 SKIPPED |
| `http-custom-headers` | FAILURE | `tools/list`, then **both** context tool calls verbatim | 18/18 SUCCESS |
| `http-invalid-tool-headers` | FAILURE ×2 | `tools/list`, then **every tool the listing kept** — derived, not named in the adapter | 11/11 SUCCESS |
| `json-schema-ref-no-deref` | FAILURE | `tools/list`, and no canary fetch | 1/1 SUCCESS |
| `json-schema-2020-12-preservation` (`not_scored`) | FAILURE ×2 | `tools/list`; echo the focal `inputSchema` back verbatim via `json_schema_echo` | 9/9 SUCCESS |

The coverage obligation was treated as an acceptance criterion and every row is shown met.

### Finding: THREE scoring rules, not two — and the third one governs the adapter's exit code

From the reducer at alpha.11 (`dist/index.js`, `function qo`), verbatim:

```text
  i = checks with status SUCCESS or FAILURE      <- the denominator
  a = SUCCESS   o = FAILURE   s = WARNING
  c = clientOutput.timedOut        l = (clientOutput.exitCode !== 0)

  overallFailure = o>0 || s>0 || c || (l && !allowClientError)
```

So: **a WARNING fails a scenario** *and* is excluded from the denominator; **a timeout fails one
outright**; and **a non-zero exit fails one independently of every check** unless the scenario sets
`allowClientError` — which, across the seven core client scenarios, **only `http-invalid-tool-headers`
does**.

That third rule is why `client_adapter.exs` exits **0** for a scenario it does not drive and carries
on past a failed call rather than raising: a non-zero exit decides the verdict *instead of* the
checks, hiding what they would have said. Non-zero is reserved for a genuine adapter crash, which
keeps a self-consistency failure of ours distinguishable from a conformance failure. Every error is
printed to stderr with the call that produced it and reported beside the check table — this is
error *reporting*, not error swallowing.

### GENUINE SDK GAP (A1, raised as MES-44 — NOT MES-43's class): a JSON-RPC error carried on a 4xx HTTP response is discarded, so BOTH of `MCP.Client`'s recoveries are unreachable over Streamable HTTP

`lib/mcp/transport/streamable_http/client.ex:301-304` turns any non-2xx, non-202 response into
`{:error, {:http_error, status, body}}` — the JSON-RPC error body is logged and dropped, never
decoded, never delivered to `MCP.Client`. Both one-shot recoveries in `lib/mcp/client.ex` live in
`route_response/3`, which is only reached for a *delivered* message. The spec puts both of their
triggers behind a 4xx:

* `streamable-http.mdx:263-268` — an unsupported protocol version **MUST** be answered
  `400 Bad Request` + `UnsupportedProtocolVersionError` (`-32022`).
* `streamable-http.mdx:259-261` and `:596-598` — a header-validation failure **MUST** be answered
  `400 Bad Request` + `HeaderMismatch` (`-32020`).
* `streamable-http.mdx:654-664` is explicit that a client **SHOULD** *inspect the body* on a 400:
  *"If the body contains a recognized modern JSON-RPC error … retry using the advertised `supported`
  versions or correct the request."*

**A7 evidence — positive control and subject, identical but for the HTTP status:**

```text
=== CONTROL  200 + -32022 ===   (the SDK's own documented path)
requests seen by server: ["server/discover", "server/discover"]   <- retried
connect/1 returned: {:ok, %{...}}

=== SUBJECT  400 + -32022 ===   (what streamable-http.mdx:263-268 MANDATES)
requests seen by server: ["server/discover"]                      <- did NOT retry
connect/1 returned: {:error, {:transport_send_failed, {:http_error, 400, ...}}}
```

**The `-32020` half is self-inconsistent and needs no harness to see it.** Our *own* server sends
HeaderMismatch as `400` (`lib/mcp/transport/streamable_http/plug.ex:332`, per the same MUST), and
our own client discards a 400 body. So MES-18's headline SEP-2243 recovery —
*"a `-32020` triggers a `tools/list` refresh and one retry"* (`client.ex:511-538`,
`streamable-http.mdx:533-539`) — **can never fire over the only transport on which `Mcp-Param-*`
headers exist**. That path is reachable in the unit suite only because the tests deliver the
`-32020` as a 200. Derived from the two line references plus the mechanism the control above
demonstrates empirically; not separately run.

Third consequence, same mechanism: `streamable-http.mdx:270-274` requires `404 Not Found` +
`-32601` for an unimplemented method, which today surfaces as `{:http_error, 404, _}` rather than a
JSON-RPC `Method not found`.

**Not fixed here, on purpose.** The adapter is a translator; a genuine gap escalates (A1). No SDK
behaviour was changed to move a harness number.

### Finding: `request-metadata` PASSES while the property its check names is BROKEN

`sep-2575-client-retry-supported-version` scored `SUCCESS`. Our client did **not** retry. Both are
true, and the report must say so.

The fixture rejects the *first* request with `-32022`, marks the check `WARNING`, and then — on
**every subsequent request**, not on a retry of the rejected one — sets the check to `SUCCESS` if
that request carries `2026-07-28` in the header and in `_meta`. So a client with no retry at all
scores `SUCCESS` provided it sends anything afterwards. The run's own stderr shows exactly that:

```text
DRIVE ERROR server/discover: {:transport_send_failed, {:http_error, 400, %{"error" => %{"code" => -32022, ...}}}}
DRIVE ok    tools/list
DRIVE ok    tools/call any_tool
```

**Verdict: the scenario PASSES; the property does not hold.** Classified as a **genuine SDK gap**
(above) and, separately, as a **harness-side weakness** worth reporting upstream: the check's name
and description claim more than its mechanism tests.

### Finding (BLOCKING 1, CR): that 8/8 is manufactured by the DRIVE POLICY, not only by the SDK — core is 6/7 under a consumer-realistic drive

The previous finding says the scenario passes while the property fails. It does not say **why** the
scenario passes, and the reason is not an SDK property at all. `drive/2` returns `nil` on
`{:error, reason}` and execution continues (`conformance/client_adapter.exs`, `drive/2`), so
`run_scenario("request-metadata", …)` issues `tools/list` and `tools/call` **after
`Client.connect/1` has already failed**. Those two later requests are the whole of what flips
`sep-2575-client-retry-supported-version` off WARNING. **A real `MCP.Client` consumer stops at a
failed connect.**

**A7 evidence — CR ran the counterfactual; one line differs between the arms:**

```text
SUBJECT (adapter as committed)      8 checks, 8 SUCCESS               -> OVERALL: PASSED
CONTROL (stop when connect errors)  7 checks, 7 SUCCESS + 1 WARNING   -> OVERALL: FAILED
                                    (the reducer's s>0 disjunct: the WARNING is never
                                     re-evaluated because no later request is sent)
Same SDK, same commit, same fixture.
```

**The carry-on policy stays, and the disclosure is what was missing.** Its justification is in
`drive/2`'s comment and it is sound — a raise would abort the drive, silently costing every check
the *later* calls would have emitted, and those checks are fail-closed, so the loss would be
attributed to the SDK rather than to the adapter giving up. What the policy must not do is go
unstated: it is a **third axis** of the figure, larger than the 8-vs-7 one, and it is why figure 3
above reads **6 / 7** rather than 7/7.

*Provenance: the counterfactual arm was run by CODE_REVIEWER, not re-run here; the mechanism was
verified in the adapter source by CODE_CREATOR and independently by the PM.*

### Finding (BLOCKING 2, CR): row 6's eleven checks were insensitive to the SDK — proved with a no-SDK control, then made falsifiable

Ten of `http-invalid-tool-headers`'s eleven checks are `calledTools.has(name) ? FAILURE : SUCCESS`
— **pure negatives**. As first committed, the adapter's call list was a **literal** (`"valid_tool"`),
never derived from what `Client.list_tools/1` kept, so those ten SUCCESSes could not distinguish our
CG7 exclusion from its total absence. The `IO.puts` of kept/excluded tools was observability, not a
check input: the fixture scores `calledTools`, which the literal alone determined.

**A7 evidence — five arms, controls labelled. The first two are CR's; the last three are this leg's.**

```text
CONTROL  a "client" with NO MCP SDK AT ALL — raw :httpc, sends
         tools/list, IGNORES the listing entirely, calls valid_tool     11/11 PASSED   (CR)
FIX ARM  adapter driving every tool list_tools KEPT                     11/11 PASSED   (CR)

SUBJECT  committed fix, derived drive, SDK pristine                     11/11 PASSED
  stderr:  tools kept: ["valid_tool"]
           tools excluded: [all ten, each with the correct reason]
           DRIVE ok  tools/call valid_tool          <- one call, and it is the DERIVED one

MUTANT   same derived adapter; HeaderMirror.validate_tool/1 forced to
         {:ok, []} so CG7's exclusion is DISABLED                        1/11 FAILED
  all ten ClientRejectsInvalidTool_* checks FAILURE, each naming the tool
  the client called: "Client called 'invalid_empty_header' which has an
  invalid x-mcp-header. Clients MUST reject (exclude) such tools."

MUTANT + OLD ADAPTER   the decisive arm: same disabled exclusion,
         driven by the adapter as originally committed                  11/11 PASSED
```

**That last arm is the point of the whole item.** With CG7's exclusion switched off — a regression
that breaks the exact MUST the row cites — the *original* adapter still scored a clean 11/11. The
row's evidence could not have gone red. Derived, it goes red on the first invalid tool the client
fails to exclude, so the 11/11 is now evidence about `MCP.Client` rather than about this file.

**Generalisation, and it is C-1's shape one level up.** C-1 found a scenario that passes because the
implementation is absent, and counted the shape as occurring **once**
(`auth/resource-mismatch`). It occurs **at least eleven times**: once in an undriven scenario, and
ten more inside a *driven* one that the report was citing as CONFIRMED evidence. Reading the
referee's source is what found C-1; it could not find this, because reading a fixture tells you a
check is negative and does not tell you that your own call list is what satisfies it. **Only a
control that is not our implementation does that.** PM RULING 4 makes it binding on the server leg,
where 14 of 37 scored scenarios are MRTR and a hard-coded drive list is the obvious way to write
them.

### Class closure for the above (F-3): every adapter-supplied value a check consumes, across all eight driven scenarios, adjudicated

BLOCKING 2 was one instance of a class — *a value this file supplies that a check reads, where an
SDK regression would not change the verdict*. The enumeration is on the record here rather than
"CR looked", because MES-19 inherits the table and a review remark is not citable. The question
asked of each row is exactly: **would a regression in the SDK change this check's verdict?**

| Scenario | Adapter-supplied values a check consumes | Regression-sensitive? |
|---|---|---|
| `tools_call` | tool name `add_numbers`; arguments `a=2`, `b=40` | **Yes.** The check reads the *recorded* `tools/call` and requires `typeof a === "number" && typeof b === "number"` — a regression that failed to send the call, dropped the arguments, or stringified them goes FAILURE. The name is not read by the check; the fixture advertises exactly one tool, so deriving it would give the same string. |
| `request-metadata` | the *fact* of two further requests after the rejection (`tools/list`, `tools/call any_tool`); the three declared `client_capabilities` | **PARTLY — the one row that is not clean.** No check reads the method or the tool name: the fixture evaluates every request identically, so `any_tool` is not a check input, and *"another request was sent"* is. That is BLOCKING 1's axis exactly. The three capability checks read `_meta.clientCapabilities` and so *are* sensitive to the SDK forwarding the declaration — but not to the capability behind it, which the report already states. The other five checks read the version header, `_meta` and `clientInfo`: all SDK-produced, all sensitive. |
| `sep-2322-client-request-state` | four `test_mrtr_*` names (the fixture's own protocol); the `:on_input_required` resolver's response bodies | **Yes.** Every check reads SDK-produced wire structure — `requestState` echoed verbatim, a fresh JSON-RPC id on retry, the key **omitted** when the server sent none, no retry when `resultType` is absent. A regression in `MCP.Client`'s MRTR handling turns each red irrespective of what the resolver returned. (Structural caveat on one of the five: see the `MRTRClientParallelIsolation` finding below.) |
| `http-standard-headers` | which of the eight watched methods are driven; names `test_headers`, `test_prompt`; the resource URI, **derived** from `resources/list` | **Yes for verdicts, with a denominator caveat.** Each check compares the `Mcp-Method`/`Mcp-Name` header against the body value — both built by the SDK from whatever name it was handed, so a missing or wrongly encoded header goes FAILURE for any name. What the adapter's choice *does* control is the **denominator**: an undriven method SKIPs, which is free. That is the hollow-PASS risk already recorded on row 4, not a verdict-insensitivity. |
| `http-custom-headers` | nothing of its own — the `toolCalls` come **verbatim from `MCP_CONFORMANCE_CONTEXT`** | **Yes.** The fixture compares each `Mcp-Param-*` header against the argument value *it* sent. There is no adapter-invented value in the loop. |
| `http-invalid-tool-headers` | the call list, now **derived** from `Client.list_tools/1` | **Yes — demonstrated by mutation** (BLOCKING 2 above). Before the fix: **no**, demonstrated by the no-SDK control. |
| `json-schema-ref-no-deref` | nothing beyond issuing `tools/list` | **ASYMMETRICALLY — name it.** The single check is negative (the canary must NOT be fetched). It is fail-closed on `tools/list` never arriving, so it does distinguish *"listed and did not dereference"* from *"never listed"*. It cannot distinguish a deliberate refusal from **the absence of any `$ref` handling at all**: only a regression that *added* network dereferencing would turn it red, and there is no implemented behaviour here whose breakage it would catch. This is C-1's shape again, in the one place the report had not looked. |
| `json-schema-2020-12-preservation` | two fixture-protocol tool names; the echoed schema, **derived** from `list_tools/1` | **Yes — demonstrated by mutation** (see the F-6 section below). |

**A2d, the empties — the rows where the answer is yes for every input:** `tools_call`,
`sep-2322-client-request-state`, `http-standard-headers`, `http-custom-headers`,
`http-invalid-tool-headers` (post-fix) and `json-schema-2020-12-preservation`. **Six of eight.**

**The two that are not clean, and neither is a defect in this file:** `request-metadata`, whose
verdict turns on the drive policy (BLOCKING 1 — disclosed, policy kept), and
`json-schema-ref-no-deref`, whose single negative check cannot credit implemented behaviour
(disclosed here for the first time). **Neither is fixable by driving harder**, which is why both are
recorded as reading instructions for MES-19 rather than as work.

### A2d (F-6): the seven `not_scored` scenarios, NAMED — and the one that was the client-side 2020-12 measurement is now DRIVEN

The entry previously gave these as a bare count — *"7 (6 extension, 1 added-after-release) — all
failing"* — while the 25 `auth/*` empties got full enumeration. A count is the shape this report
keeps telling MES-19 not to publish. Enumerated from the run:

| `not_scored` scenario | Reason it is unscored | Result |
|---|---|---|
| `auth/client-credentials-jwt` | `extension` | fails — `auth/*` empty, no OAuth client surface |
| `auth/client-credentials-basic` | `extension` | fails — same |
| `auth/enterprise-managed-authorization` | `extension` | fails — same |
| `auth/dpop` | `extension` | fails — same |
| `auth/dpop-nonce` | `extension` | fails — same |
| `auth/wif-jwt-bearer` | `extension` | fails — same |
| `json-schema-2020-12-preservation` | `added-after-release` | **now PASSES 9/9** — was 0/2 as an undriven empty |

**The seventh is not like the other six, and nobody had named it.** It is the **only** scenario in
the alpha.11 catalogue that measures **client-side** JSON Schema 2020-12 preservation (SEP-1613 /
SEP-2106). The brief already flags that MES-17's *server-side* 2020-12 work earns no scoring
credit; this is the client-side counterpart, and left undriven it failed as an **empty** — no
adapter clause — which on the result sheet is indistinguishable from a measured gap.

**Decision: DRIVEN, in this leg.** It is `not_scored`, so this moves **no figure** — 8/32 before and
8/32 after — which is precisely why it would otherwise have been dropped. What it buys is a real
measurement where there was a blank.

**A7 evidence, fail-then-pass, controls labelled:**

```text
SUBJECT  SDK pristine; adapter echoes the focal inputSchema back verbatim
         via json_schema_echo                                             9/9 PASSED
  stderr: echoing inputSchema keys: ["$defs", "$schema", "additionalProperties",
                                     "allOf", "else", "if", "properties",
                                     "then", "type"]
  9 SUCCESS, enumerated: tools/list called and focal tool advertised ·
           echo completed with a schema object · $schema preserved ·
           $defs preserved (nested defs) · additionalProperties = false
           preserved · allOf/anyOf preserved · if/then/else preserved ·
           $anchor inside $defs.address preserved · wire-schema-valid

MUTANT   one line in MCP.Client.partition_tools/1 strips "$schema" from every
         kept tool's inputSchema — i.e. a client that discards it while parsing 8/9 FAILED
  FAILURE JsonSchema2020_12Client$SchemaPreserved:
          "$schema missing from echoed inputSchema — client likely stripped it
           during parsing"
```

The mutant arm is what makes the 9/9 evidence rather than decoration: **the checks are positive and
they can go red.** Both mutations in this leg were reverted immediately and the tree rebuilt; `git
status` is clean but for this ticket's two files.

### Finding (F-8, from CR): `MRTRClientParallelIsolation` does not reach the property its description names — structural, ours to report and not ours to fix

The check's description is *"`inputRequests` and `requestState` MUST NOT be used for any other
request the client **may be sending**"*. As driven, `test_mrtr_unrelated` is issued strictly **after**
the `test_mrtr_echo_state` round has fully completed: `MCP.Client.call_tool/4` is a blocking
`GenServer.call` (`lib/mcp/client.ex:156-159`), and the run's stderr shows the strict sequence.

So the SUCCESS is **real and it tests leakage across SEQUENTIAL calls** — it does not reach the
concurrent property the description claims. **This is structural, not an adapter defect:** the SDK
exposes no mid-round point at which a second request could be issued, so *no* drive of this API
reaches it. Report it upstream-shaped alongside the `checkMcpNameHeader` finding — same family
(a check whose description is wider than its mechanism), same disposition: **worth reporting,
not worth fixing here.**

### Finding (harness-side, DORMANT — do NOT change our encoder): `checkMcpNameHeader` never decodes the sentinel

Confirmed at alpha.11: `checkMcpNameHeader` compares `Mcp-Name` to the body value with a raw `!==`
and does not decode the Base64 sentinel — unlike its own `Mcp-Param-*` comparator, which does.
`streamable-http.mdx:486-506` is unambiguous that the client MUST encode and the server MUST decode
before comparing.

**It did not bite, and here is why, measured rather than assumed** — every name and URI the alpha.11
fixtures use is header-safe, so we send it plain and the raw comparison succeeds:

```text
PLAIN    "test_headers"                          -> "test_headers"
PLAIN    "my-hyphenated-tool"                    -> "my-hyphenated-tool"
PLAIN    "file:///path/to/file%20name.txt"       -> "file:///path/to/file%20name.txt"
PLAIN    "https://example.com/resource?id=123"   -> "https://example.com/resource?id=123"
PLAIN    "test_prompt"                           -> "test_prompt"
PLAIN    "valid_tool"                            -> "valid_tool"

negative control — a name that WOULD trip the harness bug:
SENTINEL "tool wíth spaces"  -> "=?base64?dG9vbCB3w610aCBzcGFjZXM=?="
```

All three `Mcp-Name` checks scored `SUCCESS`. If a later alpha adds a non-header-safe fixture name,
our spec-correct encoding scores FAILURE against a harness bug: **classify harness-side, report
upstream-shaped, leave the encoder alone.**

### The seven-row prediction (MES-18 DoD item 2) — adjudicated row by row

Three verdicts, not two. `NOT SETTLED` exists because a PASS built of SKIPPED checks settles
nothing, and rounding one to CONFIRMED would be this sprint's own recurring defect.

| # | Scenario | Predicted | Observed | Verdict | Reason |
|---|---|---|---|---|---|
| 1 | `tools_call` | PASS | PASS 2/2 | **CONFIRMED** | `tool-add-numbers` + `wire-schema-valid` both SUCCESS |
| 2 | `request-metadata` | PASS (D-2/3/4) | PASS 8/8 | **CONFIRMED at the verdict, REFUTED at the mechanism** | see below |
| 3 | `sep-2322-client-request-state` | PASS (D-1) | PASS 5/5 | **CONFIRMED** | `sep-2322-client-no-state-omitted` SUCCESS — D-1's fix is exactly what that check tests |
| 4 | `http-standard-headers` | PASS (named risk) | PASS, **9 SUCCESS + 2 SKIPPED** | **CONFIRMED, and the named risk REFUTED** | see below |
| 5 | `http-custom-headers` | PASS (CG7) | PASS 18/18 | **CONFIRMED** | all five declared check ids emitted, incl. all six `sep-2243-client-base64-unsafe` values |
| 6 | `http-invalid-tool-headers` | PASS (CG7) | PASS 11/11 | **CONFIRMED — but only after the drive was made falsifiable** | see below |
| 7 | `json-schema-ref-no-deref` | PASS (CG4) | PASS 1/1 | **CONFIRMED at the verdict, NOT SETTLED as evidence for CG4** | see below |

**Row 2 — the prediction was right about the scenario and wrong about the reason, and the wrong half
matters more.** D-3 (the one-shot `-32022` retry) is the item the row cited and it did **not**
execute: the transport discarded the 400. The scenario passes on the fixture's weaker re-evaluation
rule, not on D-3. Reported unsoftened; this is a refuted mechanism inside a confirmed row, and the
underlying defect is escalated as a genuine SDK gap.

**Row 7 — restated at close-out (PM carry-in CI-1, comment 24496). The verdict stands; the
evidence column did not.** It read a bare `CONFIRMED` / *"canary never fetched"*, which reads as
*we were measured not to dereference `$ref`*. This ticket's own F-3 table above
(`json-schema-ref-no-deref` row) says the opposite in the same document: the scenario's single
check is negative and **cannot distinguish a deliberate refusal from the absence of any `$ref`
handling at all** — only a regression that *added* network dereferencing would turn it red, and
there is no implemented behaviour of ours whose breakage it would catch.

So the honest reading, and the one MES-19 must inherit:

* **What the row confirms:** the prediction *"this scenario will pass"* was correct, and the
  check is fail-closed on `tools/list` never arriving — so it does distinguish *"listed and did not
  dereference"* from *"never listed"*. That much is measured.
* **What it does NOT confirm:** that CG4's `$ref`-non-dereferencing behaviour was exercised. A
  client with no `$ref` handling whatsoever scores the same SUCCESS.

Row 6 was restated for exactly this defect — a verdict wider than what its check can support — and
row 7 carried it too. **F-3 is not softened to match the row; the row moves.** Rows 1, 3, 4, 5 are
among the six F-3 cleared and row 2 already carries its refutation, so row 7 was the only one left.

**Row 6 — the verdict stands and its evidence had to be rebuilt.** The original evidence column
read *"ten exclusion checks + `ClientKeepsValidTool`"*, which claims the SDK's exclusion was tested.
It was not: with a hard-coded call list those ten checks scored SUCCESS for a client with no MCP SDK
in it at all, and — the decisive arm — they still scored 11/11 with CG7's exclusion **disabled**.
What the eleven checks measure **now that the drive is derived from `Client.list_tools/1`** is:
`ClientKeepsValidTool` — the client kept the one valid tool *and called it*; ten
`ClientRejectsInvalidTool_*` — the client called **none** of the ten tools it was required to
exclude, *having been asked to call everything the listing left it*; and the `tools-list-gate` check
was never pushed, i.e. the listing was sent. A regression in CG7 now turns the row red, demonstrated
by mutation. **CONFIRMED, on evidence that could have refuted it.**

**Row 4 — the risk CC named was the wrong risk, twice over, and both corrections are worth keeping.**
CR relocated it first (the fixture routes `server/discover` in its base class, and `mcp-session-id`
is only ever a *response* header the fixture sets — the client is never checked for echoing it).
Running it settles the rest: the runner **does** drive it at the 2026-07-28 wire under
`--requirements`, `initialize` and `notifications/initialized` degrade to **SKIPPED**, and the
scenario is **not** an ADR-003 sub-decision 5 expected failure. The real risk on row 4 was the
opposite one — a **hollow PASS**: had the adapter driven none of the eight watched methods,
FAILURE=0, WARNING=0, exit 0, and the scenario would have reported **PASS with a denominator of
zero**. It reports 9 measured SUCCESS only because the adapter drives all six methods that exist at
this wire. **A PASS on row 4 is evidence only when the emitted check statuses are quoted with it.**

### Correction (A2d): the planned "roughly 13 minutes of wall clock" for the client run was wrong

The plan predicted the 25 `auth/*` empties would each burn the 30 s timeout. They do not: the
adapter exits **0** immediately on an undriven scenario, so nothing times out. The full
`--requirements 2026-07-28` client leg (39 scenarios) completed in **about ten seconds**.

**A hazard found in its place, and it is the more important one.** The requirement-set runner starts
all 39 scenarios **in parallel**, each spawning `mix run`, and they contend on the `_build` lock —
`Waiting for lock on the build directory` appears throughout the run's stderr. A driven scenario
starved long enough would hit the 30 s timeout and **fail outright, independent of every check**, in
a way indistinguishable on the result sheet from a conformance failure. It did not bite here: all
seven driven scenarios produced check-for-check identical results in the parallel run and in
individual serial runs (2, 8, 5, 9, 18, 11, 1 successes respectively). The correction round adds an
eighth, `json-schema-2020-12-preservation`, and the same holds for it and for the re-derived
`http-invalid-tool-headers`: 9/9 and 11/11 both serially (`--scenario`) and in the parallel
`--requirements` run. **Anyone re-running this must compare against the serial results before
trusting a timeout-shaped failure.**

**F-10 — the answer to *"bound or observation?"* is OBSERVATION, and it is stated in those words.**
Two things were measured after the fact, both by CODE_REVIEWER and recorded here rather than
re-run: (1) `mix run --no-compile` does **not** remove the contention — *"Waiting for lock on the
build directory"* still appears in **every** driven scenario's stderr, and **more** often than in
the plain run (13, 28, 11, 1, 23, 2, 19 occurrences), because `mix` takes the lock regardless of
`--no-compile`; (2) the whole 39-scenario parallel run finished in **5.2 s** wall on this box, so no
single scenario came within roughly **6×** of the 30 s budget — corroborated at the correction tip,
where the same run took **4.9 s** (`time`, same box, eight driven scenarios now instead of seven).

**That headroom is an observation about this machine, not a bound.** The re-run protocol above is
the right shape and stays. The only real bound available is the harness's own `--timeout` flag:
**MES-19 should pin `--timeout` explicitly and record the headroom it chose**, rather than inherit a
margin that happened to hold here. A margin nobody set is not a margin anybody can rely on.

### Decision: three capabilities are declared, and the checks they satisfy are shape checks

The adapter declares `roots`, `sampling` and `elicitation` in `client_capabilities`, because it
genuinely provides all three — the `:on_input_required` resolver answers elicitation-, sampling- and
roots-shaped input requests. That converts three `request-metadata` checks from SKIPPED to SUCCESS.

**Stated so nobody reads them as three tested capabilities:** those checks are `SKIPPED` when the
key is absent and `SUCCESS` when it is present *and an object*. They test the **shape of a
declaration**, not the capability behind it. Three of `request-metadata`'s eight successes are
therefore cheap, and the honest core of that scenario is the other five.

### Decision (RULING 3, RESTATED after its primary reason was FALSIFIED): `conformance/` stays out of `elixirc_paths` for MES-24 — as a DEFERRAL, not a rejection

**The falsification is itself the finding, and it is recorded rather than tidied away.** This entry
previously gave, as *"the reason that must survive into the record"*: *"no build-based gate could
have caught the defect this ticket was pointed at, because the file builds. An undefined remote call
is a warning, not an error."* **That is false for the gate this project actually runs.** Gate 2 is
not plain `elixirc`; it is `mix compile --force --warnings-as-errors`, which promotes exactly that
warning. Measured twice, independently — by CODE_REVIEWER, then re-run by the PM rather than taken
on report — with `"conformance"` added to `elixirc_paths(_)` at `mix.exs:36` and then restored:

```text
$ mix compile --force --warnings-as-errors
Compiling 70 files (.ex)                        (69 without conformance/)
  warning: MCP.Server.ToolContext.request_sampling/2 is undefined or private
           conformance/server_handler.ex:179:22
  warning: MCP.Server.ToolContext.request_elicitation/2 is undefined or private
           conformance/server_handler.ex:201:22, :233:22, :283:22
  Compilation failed due to warnings while using the --warnings-as-errors option
EXIT=1

CONTROL for the confusion that produced the false claim:
$ elixirc --warnings-as-errors <same file>      EXIT=0   (warnings printed, exit not set)
```

**All four sites named, on the first run.** So *"the file builds"* is true of `elixirc` and false of
the gate we run: **the gate would have caught this ticket's defect before the measurement run ever
started.**

**The second reason SURVIVES intact:** `elixirc` compiles `.ex` only, so gating `conformance/` would
cover `server_handler.ex` and **neither `.exs` adapter** — putting *"`conformance/` is gated"* into
the record as a claim wider than its check, this sprint's signature defect in miniature. That reason
is endorsed by CR and by the PM. But the two reasons do not point the same way, and with the first
gone the second does not carry the decision on its own: **a claim wider than its check is an
argument for narrowing the claim, not for declining the coverage.**

**RULING 3 as restated by the PM (who ratified it, and who restated it):** `conformance/` stays out
of `elixirc_paths` **for MES-24**, because a build-configuration change mid-ticket, on a branch
already reviewed once, is outside this ticket's scope — **and that is the whole of the reason it is
not happening here.** This is now a **DEFERRAL**. The follow-up ticket the PM owes carries a
materially different brief from the one originally promised: the open question is no longer
*"would a gate help"* — it demonstrably would, by four named sites — but ***"how do we cover the two
`.exs` adapters so the recorded claim matches the check"***. Partial coverage stated as partial is
acceptable; partial coverage stated as total is the defect this sprint keeps finding.

**For MES-19's reader:** a ratified decision was checked, its main reason failed, and the decision
was restated rather than quietly kept. That sequence is the point of recording it.

### Class closure for the falsified ruling (F-5): every claim in this entry about what a TOOL does, swept — run it or mark it unverified

The falsified reason in RULING 3 was not a typo. It was **a claim about what a tool does, reasoned
rather than executed, that reached the deliverable** — the same habit that produced the wrong
13-minute estimate earlier in this entry, landing this time on a ratified ruling. So every assertion
here about the behaviour of a `mix` task, the compiler, the harness CLI or `hex` was swept:

| Claim in this entry | Status |
|---|---|
| *"no build-based gate could have caught it, because the file builds"* | **FALSIFIED and corrected** — was reasoned, never run. See RULING 3 restated. |
| *"`mix test` would stay green if `client_adapter.exs` were deleted"* (the gate-5 positive-control disclosure) | **WAS reasoned; NOW RUN.** File moved out of the tree, `mix test` → `13 doctests, 546 tests, 0 failures`; file restored. The claim holds, and it now holds on evidence. |
| *"the adapter exits 0 on an undriven scenario, so nothing times out"* | **RUN.** CR's exit-code matrix: undriven → 0; driven with required context missing (a genuine crash) → **1**; driven against a dead server, every call failing → 0 with each error on stderr. Distinguishability holds; exit 0 did not become universal. |
| *"the full client leg completed in about ten seconds"* | **RUN** — observed wall-clock, and CR measured 5.2 s for the 39-scenario parallel run. Recorded as an observation, not a bound (F-10). |
| *"the requirement-set runner starts all 39 scenarios in parallel and they contend on the `_build` lock"* | **RUN** — `Waiting for lock on the build directory` observed throughout the run's stderr. |
| *"`mix run --no-compile` would avoid the contention"* | **RUN by CR and REFUTED** — the lock waits get *more* frequent, not fewer. Recorded under F-10; never asserted in the entry unverified. |
| *"the runner drives `http-standard-headers` at the 2026-07-28 wire under `--requirements`"* | **RUN** — `initialize` and `notifications/initialized` observed degrading to SKIPPED. |
| *"`mix hex --version` meets the ≥ 2.5.1 floor"*, gates 6a/6b | **RUN** — see the gate block below. |
| *"the reducer fails a scenario on `exitCode !== 0` unless `allowClientError`"* and the rest of the three scoring rules | **READ FROM SOURCE, and labelled as such** — `dist/index.js`, `function qo`, quoted verbatim; CR read the same reducer independently and matched it check for check, and the exit-code matrix above corroborates it behaviourally. |

**A2d, the empties:** every other assertion in this entry is about our own code or about a fixture's
source, not about a tool's behaviour, so the sweep found **one** falsified claim (RULING 3) and
**one** unverified-but-true claim (the gate-5 disclosure), both now closed. Nothing else in the
entry rests on reasoning about a tool that was never run.

**Provenance note for the single-scenario arms.** The controls and mutants in this leg were run as
`--scenario <name> --spec-version 2026-07-28`, **not** under `--requirements`: the CLI refuses the
combination outright — *"--requirements cannot be combined with --scenario: a requirement set
already fixes which scenarios run"* — which is itself a tool behaviour observed rather than assumed.
The full-suite figures are all from `--requirements 2026-07-28` runs.

### Gates — all six run individually at the client-leg phase tip, and AGAIN at the correction tip

```text
   mix hex --version                          Hex v2.5.1   (>= 2.5.1 floor met)
1  mix format --check-formatted               clean
2  mix compile --force --warnings-as-errors   clean (69 files)
3  mix credo                                  1089 mods/funs, found no issues
4  mix dialyzer                                Total errors: 0, Skipped: 0, Unnecessary Skips: 0
5  mix test                                   13 doctests, 546 tests, 0 failures
                                              + 20-seed sweep, 20/20 green
                                              (0 1 2 3 5 7 11 13 17 23 42 97 314
                                               777 1601 2024 4242 7777 9999 16180)
6a baseline sentinel @ d697093                PASS — all 22 known advisory ids present
6b mix hex.audit                              "No retired or security advisory
                                               packages found", exit 0
```

Re-run in full after the correction round (F-1…F-10); every line above is the correction tip's
result, and it is identical to the phase tip's. The correction round touches
`conformance/client_adapter.exs` and this document only — `lib/` is byte-identical to `6b16cac`
(both mutation controls were reverted and the tree rebuilt before the gates ran).

**Gate 5 is a POSITIVE CONTROL for this phase and nothing more — and that is now MEASURED, not
reasoned (F-5).** This phase changes exactly one code file, `conformance/client_adapter.exs`, which
no test loads. The entry used to *assert* that `mix test` would stay green if the file were deleted;
it was run instead:

```text
CONTROL  conformance/client_adapter.exs moved OUT of the tree
         $ mix test        ->  13 doctests, 546 tests, 0 failures
         file restored; git status clean but for this ticket's two files
```

So gate 5 discriminates **nothing** about this work and is not offered as if it did. The
discriminating evidence for this phase is the harness run itself plus the controls above: the
`-32022` status probe, the `Mcp-Name` encoding vector with its negative control, the **no-SDK
control** and **disabled-CG7 mutant** on `http-invalid-tool-headers`, and the **`$schema`-stripping
mutant** on `json-schema-2020-12-preservation`.

**Gate 6 residual: UNCHANGED at 21 unvalidated of 26.** No dependency added; `mix.lock` untouched.

### Upstream-shaped findings this leg produced (none is ours to fix)

Three, all of the same family — **a check or a comparator whose stated scope is wider than its
mechanism** — and all left alone deliberately:

1. `checkMcpNameHeader` compares `Mcp-Name` to the body with a raw `!==` and never decodes the
   Base64 sentinel, unlike its own `Mcp-Param-*` comparator. **Dormant at alpha.11** (every fixture
   name is header-safe); a later non-safe fixture name would score our spec-correct encoding
   FAILURE against a harness bug. `streamable-http.mdx:486-506` is unambiguous. **Do not change the
   encoder.**
2. `MRTRClientParallelIsolation` claims *"any other request the client may be sending"* and tests
   sequential leakage only (F-8 above). Structural — no drive of this SDK's blocking API reaches
   the concurrent property.
3. `sep-2575-client-retry-supported-version` marks SUCCESS on *any* subsequent well-formed request,
   not on a retry of the rejected one — so its name and description claim a property it does not
   test. This is what lets `request-metadata` pass while our retry is unreachable.

**Priority Hint:** high · **Blocking?:** No · **Suggested Jira Ticket?:** Yes — the 4xx-body gap
is **MES-44** (a distinct gap from MES-43's class: it disables MES-18's headline `-32020` recovery
over the only transport on which `Mcp-Param-*` headers exist); `elixirc_paths` coverage for
`conformance/` is PM's to raise, now as a **deferral with a changed brief** (see RULING 3 restated).

---

## MES-24 — Conformance adapter rework for 2026-07-28, SERVER LEG (2026-08-20)

Phase 2 of two, same branch. The client leg is the section above and its figures are unchanged by
anything here. Every figure below is pinned to `@modelcontextprotocol/conformance@0.2.0-alpha.11`
run as `conformance server --url http://127.0.0.1:3001/mcp --requirements 2026-07-28 -o <dir>`,
against the tree at this branch's tip. Results are adjudicated from the saved `-o` artefacts, never
from terminal scrollback.

**The PO ruling this sits under, unchanged:** the 2.0.0 conformance claim rests on our own ported
acceptance suite; the harness supplies *supporting evidence* with its numbers reported. A bad figure
is a finding to classify, not a claim to retract — and a good figure does not upgrade the claim.

**The spine, unchanged:** no SDK behaviour was changed to satisfy a scenario. Where the SDK cannot
express what a scenario requires, the fixture implements the closest thing the SDK's public contract
allows and the gap is escalated. Four such gaps are named below; all four are visible in the figure
as failures, and none of them was smoothed.

### RULING 4 — the pre-run classification, and why it is in its own commit

PM RULING 4 (comment 24493) binds this leg to classifying all 37 scored server scenarios by check
polarity **before** the run, and to showing any scenario cited as evidence to be falsifiable. The
client leg established why: `http-invalid-tool-headers` scored a clean 11/11 with the MUST it was
cited for switched off, because the drive list was hard-coded — *"it passed" is not evidence for a
row unless failing was possible.*

**So this classification, and the per-scenario PASS/FAIL prediction derived from it, are committed
in a separate commit made before the harness was started.** Not because a claim in a document is
worth less than a claim in a commit, but because a prediction that can be edited after the result is
not a prediction. Where the run contradicts a row below, the row is reported refuted at full
strength rather than corrected.

**Polarity, defined.** A check is **POSITIVE** when SUCCESS requires the harness to *observe*
something this SDK did; **NEGATIVE** when SUCCESS is the default and only an observed bad thing
turns it red — so an implementation that does nothing at all scores the same green; **MIXED** when a
scenario carries both.

Read from `dist/index.js` at alpha.11, each scenario's own `run()` and every `push({status: …})`
in it.

| # | Scenario | Checks | Polarity | Predicted | Why |
|---|---|---|---|---|---|
| 1 | `server-stateless` | ~30 | MIXED | **FAIL** | HTTP status mapping (gap 3) + `-32021` data (gap 4) |
| 2 | `completion-complete` | 1 | POSITIVE | PASS | needs a `completion.values` array |
| 3 | `tools-list` | 2 | POSITIVE | PASS | structure + SEP-986 name format |
| 4 | `tools-call-simple-text` | 1 | POSITIVE | PASS | |
| 5 | `tools-call-image` | 1 | POSITIVE | PASS | |
| 6 | `tools-call-audio` | 1 | POSITIVE | PASS | |
| 7 | `tools-call-embedded-resource` | 1 | POSITIVE | PASS | |
| 8 | `tools-call-mixed-content` | 1 | POSITIVE | PASS | |
| 9 | `tools-call-error` | 1 | POSITIVE | PASS | needs `isError: true` **and** text |
| 10 | `tools-call-with-progress` | 1 | POSITIVE | PASS | needs ≥3 increasing progress notifications |
| 11 | `server-sse-multiple-streams` | 2 | POSITIVE | PASS | 3 concurrent POSTs, each stream readable |
| 12 | `resources-list` | 1 | POSITIVE | PASS | |
| 13 | `resources-read-text` | 1 | POSITIVE | PASS | |
| 14 | `resources-read-binary` | 1 | POSITIVE | PASS | |
| 15 | `resources-templates-read` | 1 | POSITIVE | PASS | needs `123` to appear in the substituted body |
| 16 | `sep-2164-resource-not-found` | 3 | MIXED | **FAIL** | `data.uri` SHOULD → WARNING → scenario fails (gap 4) |
| 17 | `prompts-list` | 1 | POSITIVE | PASS | every prompt needs `description` |
| 18 | `prompts-get-simple` | 1 | POSITIVE | PASS | |
| 19 | `prompts-get-with-args` | 1 | POSITIVE | PASS | |
| 20 | `prompts-get-embedded-resource` | 1 | POSITIVE | PASS | |
| 21 | `prompts-get-with-image` | 1 | POSITIVE | PASS | |
| 22 | `dns-rebinding-protection` | 2 | POSITIVE | PASS | 4xx on `evil.example.com`, 2xx on localhost |
| 23 | `caching` | 7 | POSITIVE | PASS | `ttlMs`/`cacheScope` on all five endpoints |
| 24 | `input-required-result-basic-elicitation` | 2 | POSITIVE | PASS | |
| 25 | `input-required-result-basic-sampling` | 2 | POSITIVE | PASS | |
| 26 | `input-required-result-basic-list-roots` | 2 | POSITIVE | PASS | |
| 27 | `input-required-result-request-state` | 2 | POSITIVE | PASS | round 2 must contain `state-ok` |
| 28 | `input-required-result-multiple-input-requests` | 2 | POSITIVE | PASS | ≥3 requests of 3 distinct methods |
| 29 | `input-required-result-multi-round` | 3 | POSITIVE | PASS | R2's `requestState` must differ from R1's |
| 30 | `input-required-result-missing-input-response` | 1 | POSITIVE | PASS **for the wrong reason** | see "passes hollowly" below |
| 31 | `input-required-result-non-tool-request` | 2 | POSITIVE | **FAIL** | `prompts/get` is not MRTR-wired (gap 1) |
| 32 | `input-required-result-result-type` | 1 | POSITIVE | PASS | |
| 33 | `input-required-result-unsupported-methods` | 1 | **NEGATIVE** | PASS, unfalsifiable | see below |
| 34 | `input-required-result-tampered-state` | 1 | POSITIVE | PASS | HMAC verify must reject |
| 35 | `input-required-result-capability-check` | 1 | MIXED (weak) | PASS | see below |
| 36 | `input-required-result-ignore-extra-params` | 1 | POSITIVE | **FAIL** | retry without `requestState` is invisible (gap 2) |
| 37 | `input-required-result-validate-input` | 2 | **NEGATIVE** | PASS, unfalsifiable | see below |

Plus **one further check appended to every scenario** by the runner (`u.push(...nt(c))`):
`wire-schema-valid`, which validates **every JSON-RPC message this server sent** against the
official 2026-07-28 JSON schema. It is POSITIVE and it is the single most load-bearing check on the
sheet: it is what makes the otherwise-negative scenarios below carry any information at all.

**Predicted total: 33 / 37.** Four predicted failures, all four attributed to a named SDK gap
before the run rather than after it.

#### The empties, enumerated FIRST (C-1's generalisation, applied prospectively)

Three scored server scenarios cannot distinguish this SDK from its absence, and are named here
rather than discovered afterwards:

* **`input-required-result-unsupported-methods`** — sends `tools/list` and `prompts/list` and
  scores SUCCESS unless one comes back with `resultType: "input_required"`. A server that answers
  `-32601` to both scores the same SUCCESS. There is no implemented behaviour of ours whose
  breakage it would catch.
* **`input-required-result-validate-input`** — both checks are of the form *SUCCESS unless the
  server accepted the invalid input and returned a complete result*. A server that errors on
  everything passes both.
* **`input-required-result-capability-check`** — weakly mixed rather than empty. It fails a server
  that includes an undeclared `elicitation/create`, but a degenerate `InputRequiredResult` carrying
  **no `inputRequests` at all** takes neither branch and scores SUCCESS. So it can catch
  over-asking and cannot catch not-asking.

And one that will pass for a reason that is not the reason it tests:

* **`input-required-result-missing-input-response`** — expects the server to answer a retry with
  *wrong* `inputResponses` by re-requesting. Ours does. But it does so because gap 2 means the
  handler **cannot see `inputResponses` at all** when no `requestState` accompanies them, so it
  takes the first-attempt branch. The check cannot tell that apart from a server that inspected the
  responses, found them wrong, and deliberately re-requested. **A green here is not evidence that
  we validate input responses.** It is the same shape as the client leg's row 6 and it is recorded
  before the run for the same reason.

#### Falsifiability of what this leg will cite

Nothing in this leg is cited as evidence for a gap-register row on the strength of a green alone.
The four gaps below are each evidenced by a **failure** that names its cause, and the MRTR tools
are driven by the harness's own fixture rather than by any list this repository controls — the
`BLOCKING 2` shape from the client leg cannot recur here, because the drive list is the harness's.

### The four SDK gaps this leg exercises — escalated, not routed around

All four join **MES-43** under the PM's standing pre-authorisation (RULING 2, comment 24485:
"further instances of this class join MES-43 rather than spawning a ticket each"). None is fixed
here.

1. **MRTR is wired to `tools/call` and nothing else.** `MCP.Server.Dispatch` sets `ctx.input` at
   `dispatch.ex:195` and carries the `{:input_required, …}` clause at `:223`, both inside the
   `tools/call` route; `prompts/get` at `:297-312` does neither, and its shape function has exactly
   two clauses. SEP-2322 says InputRequiredResult is universal across `prompts/get`,
   `resources/read`, `tools/call` and `tasks/result`. Escalated during planning; unchanged.
2. **`MRTR.continuation_from_params/1` drops `inputResponses` when `requestState` is absent.** It
   returns `nil` unless `params["requestState"]` is present, so a retry carrying only
   `inputResponses` — which the schema explicitly permits, both fields being optional on
   `InputResponseRequestParams` — never reaches the handler. An MRTR flow that needs no server-side
   continuation is therefore **not expressible in this SDK**, and a handler cannot tell "first
   attempt" from "retry with no state".
3. **No JSON-RPC-code → HTTP-status mapping.** `MCP.Transport.StreamableHTTP.Plug` sends every
   dispatch result — success or error — with HTTP 200 (`plug.ex:1005`, `:1016`); only the four
   errors raised *before* dispatch get a non-200 (`:329`, `:332`, `:342`, `:364`). SEP-2575
   requires 400 for `-32602`/`-32022`/`-32021` and 404 for `-32601`.
4. **A handler error return has no `data` slot.** `{:error, code, message, state}` becomes
   `%MCP.Protocol.Error{code: code, message: message}` with `data: nil`, and there is no other
   handler-reachable path to it. Two spec requirements are unreachable from any handler as a
   result: `-32021`'s `error.data.requiredCapabilities` (SEP-2575) and SEP-2164's
   `error.data.uri`.

And one **documentation/typespec defect**, distinct from the four because it misleads rather than
blocks: `MCP.Protocol.Messages.MRTR.input_required/2` is spec'd `list() | nil` and its moduledoc
says *"the list of input-request objects"*, while the wire type `InputRequests` is a JSON **object**
keyed by input name (schema `$defs.InputRequests`, `type: "object"`; `InputRequiredResult.
inputRequests` `$ref`s it). **A handler following this SDK's own typespec emits non-conforming
wire.** This fixture sends a map, and `wire-schema-valid` in the run below is what settles which of
the two is right.

### The measured server-leg figures, and the honest way to state them

Run at `@modelcontextprotocol/conformance@0.2.0-alpha.11`, `--requirements 2026-07-28`, against the
branch tip. **35 of 37 scored server scenarios pass** — and that number on its own is misleading in
two independent directions, so it is never reported alone.

| | **FAILURE-only** (the `--requirements` verdict) | **warnings also fail** (the harness's own stricter reducer) |
|---|---|---|
| **this SDK** | **35 / 37** | **33 / 37** |
| **null-implementation control** | **6 / 37** | **3 / 37** |
| **discriminating (ours − null)** | **29 / 37** | **30 / 37** |

Three axes, three numbers, none of them the headline:

| # | Figure | Value | Axis it measures |
|---|---|---|---|
| 1 | Scored scenarios the harness reports PASS | **35 / 37** | what the harness's `--requirements` verdict reports |
| 2 | — under the harness's own **stricter** reducer (WARNING fails) | **33 / 37** | *which of the harness's two disagreeing verdicts you read* |
| 3 | — scenarios a **null implementation does not also pass** | **29 / 37** | what this SDK actually contributes |

Check-level, for the 37 scored scenarios: **98 SUCCESS · 19 FAILURE · 2 WARNING · 0 SKIPPED**
(117 in the SUCCESS+FAILURE denominator). All 19 failures are in two scenarios.

MES-19 may pick a headline only by publishing all three. Figure 1 alone reads as *"the server is
94% conformant"*; figure 3 says *"29 of 37 scenarios would have gone red had this SDK been absent,
and 6 would not."*

#### CORRECTION, measured: "a WARNING fails a scenario" is TRUE FOR ONE RUNNER AND FALSE FOR THE OTHERS

The ticket brief (adversarial item 2), the MES-18 review input, and **this document's own client-leg
entry** all state the rule unqualified: *a WARNING fails a scenario (`s>0` is a disjunct of
`overallFailure`)*. Read again at alpha.11, in the three places that decide a verdict:

```text
CLIENT, single scenario   (function qo)   overallFailure = failed>0 || warnings>0
                                                          || timedOut
                                                          || (exit!=0 && !allowClientError)
                                          -> WARNING FAILS.  This is the reducer the rule came from.

CLIENT, suite summary                     mark = (failures===0 && warnings===0) ? '✓' : '✗'
                                          -> WARNING marks a scenario ✗ in the printed summary.

SERVER, suite summary     (function Qo)   mark = (failures===0) ? '✓' : '✗'
                                          -> WARNING does NOT fail, and is not even printed.

BOTH legs, --requirements exit code (Bc)  exit = scored.some(s => s.checks.some(FAILURE))
                                          -> WARNING does NOT fail.
```

So the harness's **own scenario verdict depends on which output you read**, and the rule as this
project recorded it is the client single-scenario one generalised. **Measured consequence, not
inferred:** `sep-2164-resource-not-found` and `input-required-result-ignore-extra-params` each emit
a WARNING and each is reported **✓ / passing** by the server runner and by the `--requirements`
exit code.

**Does this move the client-leg figure? No, and that is checked rather than assumed.** Across every
`checks.json` the client leg saved (`/tmp/mes24/client/**`, 33 scenarios), the status totals are
**57 SUCCESS · 61 FAILURE · 8 SKIPPED · 1 INFO · 0 WARNING**. Not one client check emitted a
WARNING, so 8/32 stands under either rule. The correction is to a **claim**, not to a number — which
is this sprint's signature defect, found this time in our statement of the referee's own rules.

#### The pre-run prediction, adjudicated — TWO ROWS REFUTED

Predicted 33/37; measured 35/37. Both discrepancies are refutations of my own pre-run rows, and
neither is the SDK doing better than predicted:

| Scenario | Predicted | Observed | Verdict | Why the prediction was wrong |
|---|---|---|---|---|
| `sep-2164-resource-not-found` | FAIL | **PASS** (3 SUCCESS, 1 WARNING) | **REFUTED** | The `data.uri` SHOULD **is** unmet — `sep-2164-data-uri` is WARNING, exactly as predicted. The prediction failed on the **scoring rule**, not on the behaviour: I applied the client reducer to a server run. |
| `input-required-result-ignore-extra-params` | FAIL | **PASS** (1 SUCCESS, 1 WARNING) | **REFUTED** | Identical cause. `sep-2322-ignore-unexpected-params` is WARNING with the message *"Server did not return complete result…"* — gap 2 bit exactly as predicted, and the scenario passes anyway. |
| `server-stateless` | FAIL | FAIL (13 SUCCESS, 17 FAILURE) | CONFIRMED | but see the root-cause decomposition: I predicted 2 causes and the run found 6. |
| `input-required-result-non-tool-request` | FAIL | FAIL (0 SUCCESS, 2 FAILURE) | CONFIRMED | gap 1, as predicted |

**Both refutations point the same way: two scenarios are green over behaviour the harness itself
described as unmet.** The prediction was wrong; the SDK's behaviour was exactly as predicted in both
cases. That is the most useful thing a refuted prediction can do — it moved the error out of the
implementation and into the account of the referee.

#### The null-implementation control (PM RULING 4, comment 24493)

RULING 4: *"run something that is not our implementation and see whether it scores the same green."*
The control is a 25-line HTTP server that answers **`-32601 Method not found` to every method**, HTTP
200, and implements no MCP behaviour whatsoever (`/tmp/null_server.py`, reproduced in this leg's
artefacts). Same harness, same `--requirements 2026-07-28`.

```text
NULL CONTROL — scored server scenarios it PASSES: 6 / 37

  server-sse-multiple-streams                    accepts-multiple-post-streams SUCCESS
                                                 sse-streams-functional        INFO
  sep-2164-resource-not-found                    no-empty-contents  SUCCESS  (never returned contents)
                                                 error-code         WARNING
                                                 data-uri           WARNING
  input-required-result-missing-input-response   missing-response-rerequests WARNING
  input-required-result-unsupported-methods      not-on-unsupported-requests SUCCESS
  input-required-result-ignore-extra-params      ignore-unexpected-params    WARNING
  input-required-result-validate-input           validate-input-responses    SUCCESS
                                                 error-on-protocol-error     SUCCESS
```

Every one of those 6 is also in our 35, so the set difference is well defined: **29 of our 35 passes
are scenarios a do-nothing server does not get.** The subset relation is what makes the subtraction
legitimate, and it makes the control *harder* on us, not easier: a null that answered 500 or closed
the connection would pass fewer, so 29 is a floor obtained against the most generous null available.

**The sentence MES-19 should quote, verbatim, whenever the 29 appears** (PM ruling, comment 24503):

> a conservative floor on scenario-level evidence contributed beyond a minimal valid-envelope null,
> not a conformance-rate estimate.

It is not 29/37, it is not a pass rate, and it must not be reported as one. Three of the six were named as empties *before*
the run (`unsupported-methods`, `validate-input`, and `missing-input-response`'s hollow green); the
control added three the pre-run reading had not caught — `server-sse-multiple-streams` (three HTTP
200s is the whole test), and the two WARNING-only scenarios, which the pre-run reading had
mis-scored as failures rather than as empties.

**`server-sse-multiple-streams` deserves naming separately.** Its second check went `INFO` for the
null server and `SUCCESS` for us (we do serve SSE), but `INFO` is outside the SUCCESS+FAILURE
denominator, so it cannot fail anything. The scenario's only FAILURE-capable check is *"three
concurrent POSTs each returned `res.ok`"*. **SEP-1699 multiple-stream support is, at this revision,
measured by the ability to return HTTP 200 three times.**

### Falsifiability: every claim this leg makes is backed by an arm that could have come out the other way

RULING 4's second clause: *"'it passed' is not evidence for a row unless failing was possible."*
Six mutations, each run against the harness or the suite, each reverted with `git status` clean
afterwards.

| # | Mutation | Scenario / suite run | Result | What it establishes |
|---|---|---|---|---|
| C-A | `inputRequests` emitted as a **list**, as `MRTR.input_required/2`'s own typespec says | `input-required-result-basic-elicitation` | `sep-2322-elicitation-incomplete` **FAILURE**; `wire-schema-valid` **FAILURE** — *"InputRequiredResult/inputRequests: must be object"* | `wire-schema-valid` is falsifiable **and** the SDK's `list()` typespec produces non-conforming wire |
| C-B | `RequestState.verify/2` replaced by an unverified `peek/1` | `input-required-result-tampered-state` | `sep-2322-reject-tampered-state` **FAILURE** — *"Server accepted tampered requestState"* | the tampered-state green is earned by the HMAC, not by the scenario being weak |
| C-C | `test_logging_tool` logs unconditionally | `server-stateless` | `sep-2575-server-no-log-without-loglevel` **FAILURE** | the no-log MUST NOT is a live check, not a free green |
| C-D | `broadcast/2` made a no-op (lists still mutate, nothing is notified) | `server-stateless` | both `…-list-changed-on-subscription` → **WARNING**; ack / subscriptionId / filter stayed **SUCCESS** | the two list-changed checks are SHOULD-level and **cannot fail the scenario**; and `ServerTagsSubscriptionId` is satisfied by the acknowledgment frame alone |
| C-E | `test_input_required_result_prompt` returns an ordinary `GetPromptResult` | `input-required-result-non-tool-request` | 1 FAILURE (`non-tool-incomplete`), `wire-schema-valid` **SUCCESS** | separates the SDK gap from the fixture's choice of how to surface it — see below |
| C-F | `RequestState.verify/2`'s tag comparison short-circuited to `true` | `mix test` | **5 of 12** requestState tests fail | the unit tests are evidence, not decoration |

Plus the **gate-5 control**, measured rather than argued (the client leg's F-5 discipline):

```text
CONTROL  conformance/server_handler.ex AND conformance/server_adapter.exs moved OUT of the tree
         $ mix test  ->  13 doctests, 558 tests, 0 failures
         both restored; git status clean but for this ticket's files
```

So `mix test` discriminates **nothing** about the two files that are the substance of this leg. It
discriminates exactly one thing: `conformance/request_state.ex`, via the 12 new tests, and C-F shows
those tests fail when the mechanism does. Gate 5 is a positive control for the fixture and real
evidence for the token.

### The 19 failing checks, decomposed by root cause — and the three-way classification

**`server-stateless` — 13 SUCCESS, 17 FAILURE.** I predicted it would fail from two causes; it
failed from **six**. Four of the six were named before the run, two were not, and saying which is
which is the point of having predicted at all.

| Root cause | Failing checks | Predicted pre-run? | Class |
|---|---|---|---|
| **R1** `server/discover` performs **no `_meta` structural validation** — a request with no `_meta` at all, or missing `protocolVersion`, or missing `clientCapabilities`, gets a normal result instead of `-32602` | `…request-meta-invalid-missing-meta`, `…-missing-protocol-version`, `…-missing-client-capabilities` (3) | **NO** — discovered by the run | genuine gap |
| **R2** no JSON-RPC-code → **HTTP-status mapping**: every dispatch result leaves as HTTP 200 | `…http-server-meta-invalid-400` ×3, `…unsupported-version-400`, `…header-mismatch-400`, `…missing-capability-http-400`, `…method-not-found-404-{initialize,ping,logging-setlevel,resources-subscribe,resources-unsubscribe}`, `…method-not-found-404` (12, overlapping R1/R3/R4/R5/R6) | yes (gap 3) | genuine gap |
| **R3** `server/discover` has **no version gate at all** (`dispatch.ex:158-168`, deliberately), so an unsupported requested version yields a result, not an `UnsupportedProtocolVersionError` carrying `data.supported`/`data.requested` | `…server-unsupported-version-error` (1) | **NO** — discovered by the run | genuine gap **against an explicit SDK design decision** |
| **R4** no cross-check of the `MCP-Protocol-Version` **header** against `_meta.protocolVersion`; `check_routing_headers/2` covers `Mcp-Method`/`Mcp-Name` only | `…http-server-header-mismatch-400` (1) | no | genuine gap |
| **R5** a handler error return has **no `data` slot**, so `-32021` cannot carry `error.data.requiredCapabilities` | `…server-rejects-undeclared-capability` (1) | yes (gap 4) | genuine gap |
| **R6** `initialize` is answered `-32022 UnsupportedProtocolVersion`; the scenario requires `-32601` + HTTP 404 for every removed method | `…method-not-found-404-initialize` (also under R2) | no | genuine gap **against an explicit SDK design decision** (`dispatch.ex:131-139`) |

R3 and R6 are worth separating from the rest because they are not oversights: `dispatch.ex` documents
both choices in prose. `server/discover` is exempted from the version gate because it *is* the
version-discovery probe — but SEP-2575, as the scenario reads it, says the rejection **carries** the
supported list, so discovery still works through the error and the exemption is not needed. And
`initialize` is answered `-32022` to tell a 2025-11-25 client what happened — helpful, and not what
the revision requires. **Two documented decisions contradicted by the referee is a different kind of
finding from four gaps**, and MES-19 should not read them as the same thing.

##### PM RULING (comment 24503): R3 and R6 are **decisions, not defects**. Settled.

I flagged the class rather than pre-judging it; the PM read the prose at both sites before ruling,
rather than taking the flag on trust. Both citations re-verified here at the branch tip:

* **R3** — `dispatch.ex:146`: *"server/discover: the version-discovery probe (no version gate)"*.
  The absence of the gate is named as the design, not left implicit.
* **R6** — `dispatch.ex:66-68` states the removed-method behaviour including `initialize` →
  `-32022`, and `:131-139` carries the reason inside the error string itself — *"carry protocol
  version in per-request _meta"*.

**The ruling: both go to MES-19 as decisions requiring a PO call at release — NOT to MES-43's class
as gaps to fix.** The distinction is load-bearing in both directions: MES-19 must not publish "by
design" over an accident, and must not publish "gap" over a deliberate reading of the revision.
Recorded here so MES-19 inherits the ruling instead of re-deriving it from the table above. The
table's *"genuine gap against an explicit SDK design decision"* class is the **measurement** and
stands unchanged; this ruling is the **routing** decision taken on top of it.

The 13 SUCCESSes in `server-stateless` are not filler and one group of them is a correction to a
PM-ratified finding — see *"P-4, partly refuted"* below.

**`input-required-result-non-tool-request` — 0 SUCCESS, 2 FAILURE, and only ONE of them is cleanly
the SDK's.**

* `sep-2322-non-tool-incomplete` FAILURE — *"Expected InputRequiredResult from prompts/get"*. This
  is gap 1, unambiguously: no handler can produce one.
* `wire-schema-valid` FAILURE — *"GetPromptResult: must have required property 'messages'"*. The
  fixture put the input-required **body** through `{:ok, result, state}`, and
  `MCP.Server.Dispatch.complete/1` overwrote `resultType: "input_required"` with `"complete"`,
  producing a result that is neither a `GetPromptResult` nor an `InputRequiredResult`. The
  **overwrite** is the SDK's; **putting the body there** was the fixture's choice.

**C-E is the control that separates them**: with the prompt returning an ordinary `GetPromptResult`,
the scenario still fails `non-tool-incomplete` and `wire-schema-valid` goes SUCCESS. So the honest
statement is *"one failure is the gap; the second is the gap made visible on the wire by a fixture
choice, and a different choice removes it."* The choice is kept because
`Dispatch.complete/1` overwriting a handler-supplied `resultType` unconditionally is itself worth
having on the record as measured wire rather than as a code reading. The alternative — returning
`{:input_required, …}` from `handle_get_prompt/4`, which is what a handler author would actually
write — **raises**, measured below.

#### Correction to my own planning claim (comment 24484): it is a `FunctionClauseError`, not a `CaseClauseError`

Probed directly, with a positive control, at the branch tip:

```text
POSITIVE CONTROL  tools/call, handler returns {:input_required, requests, "st", state}
  -> %{"inputRequests" => %{...}, "requestState" => "st", "resultType" => "input_required"}

SUBJECT           prompts/get, handler returns the SAME shape
  -> RAISED FunctionClauseError: no function clause matching in
     anonymous fn/1 in MCP.Server.Dispatch.route/5
```

The shape function is an anonymous `fn` with clauses, not a `case`. The consequence is unchanged and
the correction is small, but the claim was mine and it was stated in a plan the PM ratified. **Not
added as a permanent test**: a test asserting broken behaviour becomes a maintenance trap the moment
MES-43 fixes it, so this is a recorded probe (`/tmp/mes24_prompts_mrtr_probe.exs`, reproduced in the
close-out) rather than a suite entry.

### Three-way classification of every failure (ticket DoD item 2)

**1 — genuine SDK gap (all 19 scored failures).** R1–R6 above plus gap 1. Every one is escalated;
none is fixed here. No scored failure on this leg is attributable to the harness or to an
old-revision scenario.

**2 — scenario targets an old revision: EMPTY, and re-derived rather than inherited.** MES-13's
ADR-003 #5 enumeration of expected-failures against `0.1.16` is **SUPERSEDED, not dropped**: the
frozen set scopes itself to one revision (*"Scenarios run at THIS revision's wire version"*) and
`--requirements 2026-07-28` selects exactly that, so no `--expected-failures` baseline is used and
none is needed. The concrete demonstration that the frozen set does the job the old list did:
`server-stateless` probes `initialize`, `ping`, `logging/setLevel`, `resources/subscribe` and
`resources/unsubscribe` — five methods that do not exist at this revision — and treats their absence
as the *requirement*, not as an exclusion.

**3 — harness-side: TWO, neither fatal, both upstream-shaped.**

* **The WARNING asymmetry** documented above: the same scenario is `✗` under the client
  single-scenario reducer and `✓` under the server summary and the `--requirements` exit code. A
  harness that publishes conformance figures should not have two verdicts. Reported as an
  inconsistency, not a bug in our favour — it *helps* our number, which is exactly why it is stated.
* **`input-required-result-capability-check` cannot catch under-asking.** Its check fails a server
  that includes an undeclared `elicitation/create`, but an `InputRequiredResult` carrying **no
  `inputRequests` at all** takes neither branch and scores SUCCESS. The check's description claims
  *"Server only includes inputRequests for declared client capabilities"*; it tests only the
  *"only"* half. Our green is real (C-A's neighbouring evidence shows the requests are emitted and
  schema-valid), but the check would not have caught the degenerate case.

And carried forward from the client leg, still dormant and still not ours to fix: `checkMcpNameHeader`
compares `Mcp-Name` to the body with a raw `!==` and never decodes the Base64 sentinel. It did not
bite on this leg either — every server-leg name is header-safe. **The encoder is not touched.**

### The `not_scored` scenarios — run and reported, never counted, and two of them are the most informative results on this leg

The brief's instruction, kept: *a reader who sees 35/37 must not conclude that 2020-12 was
measured.* It was measured, it passed perfectly, and **it counts for nothing**.

| Scenario | Reason it is unscored | Result | What it tells MES-19 |
|---|---|---|---|
| `json-schema-2020-12` | `pending` (the suite's own reference fixture cannot pass it) | **8 SUCCESS, 0 FAILURE** | **MES-17's entire server-side surface verified and worth zero.** `$schema`, `$defs`, `additionalProperties` (SEP-1613) **and** `allOf`/`anyOf`, `if`/`then`/`else`, `$anchor`-in-`$defs` (SEP-2106) all preserved verbatim through `tools/list`. |
| `http-header-validation` | `pending` (SEP-2243) | 9 SUCCESS, 3 FAILURE, 2 WARNING | found a **genuine defect in MES-18's own just-landed work** — see below |
| `http-custom-header-server-validation` | `pending` (SEP-2243) | 4 SUCCESS, 6 FAILURE | the server does **no `Mcp-Param-*` validation at all**; and 4 of the 4 greens are hollow |
| `tasks-*` (10) | `extension` (SEP-2663) | 12 SUCCESS, 30 FAILURE | this SDK implements no tasks extension. Expected, and optional by definition (SEP-1730). |

**The `json-schema-2020-12` result only exists because this leg added the tool the scenario names.**
Before that, it reported *"Tool 'json_schema_2020_12_tool' not found"* — one FAILURE that measured
the **fixture**, not the SDK. The requirements file's own words are the justification: *"invisible
coverage is how gaps hide."* The same applies to `http-custom-header-server-validation`, which
reported five *"Not testable: server exposes no tool with x-mcp-header annotations"* failures until
this leg added one. **Neither tool can move a scored figure — both scenarios are `not_scored` — and
the scored figure is byte-identical before and after adding them (35/37, 98/19/2).** That is stated
because "added a tool, number went up" is precisely the move this ticket exists to not make.

#### GENUINE DEFECT found by a `not_scored` scenario, in MES-18's surface: trailing OWS is not trimmed from routing headers

`sep-2243-server-accepts-whitespace-header-value` FAILURE — *"HTTP spec requires trimming OWS around
field values"*. Reproduced directly, with both controls, against the branch tip:

```text
A  Mcp-Name: test_simple_text          (exact — control, MUST accept)   -> HTTP 200  result
B  Mcp-Name: "test_simple_text  "      (trailing OWS — MUST accept)     -> HTTP 400  -32020
       data: "Mcp-Name test_simple_text   != \"test_simple_text\""
C  Mcp-Name: "  test_simple_text"      (leading OWS — MUST accept)      -> HTTP 200  result
D  Mcp-Name: other_tool                (real mismatch — MUST reject)    -> HTTP 400  -32020
```

The leading/trailing asymmetry is the evidence that this is accidental rather than policy: the HTTP
layer strips leading OWS before `plug.ex:890` ever sees the value, and trailing OWS survives into a
raw `!=` comparison. RFC 9110 §5.5 requires recipients to strip both. **Control D shows the
rejection path itself is correct** — a genuinely different name is still rejected — so this is a
narrow comparator defect, not a broken feature.

**This is a distinct class from MES-43's** (SEP-2322/MRTR): it is SEP-2243, it is in code that
landed yesterday under MES-18, and it makes a conforming client's request fail. **It needs its own
ticket — PM's to raise** (the same shape as MES-44, which the client leg produced).

#### The 4 hollow greens in `http-custom-header-server-validation`

`sep-2243-server-decode-base64` and `sep-2243-server-validate-param-match` ×2 score SUCCESS, and the
reason is that **we accept everything**: `check_routing_headers/2` (`plug.ex:887-903`) validates
`Mcp-Method` and `Mcp-Name` and reads no `Mcp-Param-*` header at all. Every "accept" case therefore
passes, and every "reject" case fails. **A green in an accept-case check is not evidence of decoding
when the implementation has no decoder.** Named here so nobody reads 4/10 as partial support: the
correct reading is **zero** server-side `x-mcp-header` validation, with 4 checks that cannot detect
its absence.

### P-4, partly REFUTED: MES-15's `subscriptions/listen` IS measured — inside a scenario that fails for other reasons

The plan's finding P-4, which the PM verified personally, said no `subscriptions/listen` and no
extensions scenario exists anywhere in alpha.11, and concluded that three of this sprint's four
feature tickets earn zero scoring credit with two not representable at all.

**Measured, `server-stateless` emits five checks that drive `subscriptions/listen` directly, and all
five are SUCCESS:**

```text
SUCCESS  sep-2575-server-sends-subscription-ack       ack is the FIRST frame on the stream
SUCCESS  sep-2575-server-tags-subscription-id         frames carry _meta.../subscriptionId
SUCCESS  sep-2575-server-honors-notification-filter   a prompts-only stream got no tools/list_changed
SUCCESS  sep-2575-server-sends-prompts-list-changed-on-subscription
SUCCESS  sep-2575-server-sends-tools-list-changed-on-subscription
```

**So P-4 splits:**

* **REFUTED as to coverage.** MES-15's surface is exercised and passes, by five checks whose
  behaviour is exactly what MES-15 built.
* **STANDS as to scoring.** They live inside `server-stateless`, which fails on R1–R6, so they move
  no scenario. No row anywhere in the results says "subscriptions work".
* **STANDS entirely for extensions (MES-16).** Zero checks anywhere in the run touch extension
  negotiation. That ticket's surface remains unrepresentable, exactly as P-4 said.

**And the coverage is thinner than five checks suggests**, which C-D measured rather than assumed:
with `broadcast/2` a no-op, the two `…-list-changed-on-subscription` checks degrade to **WARNING**
(SHOULD-level, and warnings cannot fail a server scenario), and `ServerTagsSubscriptionId` **stays
SUCCESS** because the acknowledgment frame is itself a tagged notification. So of the five, exactly
**two** — `ServerSendsSubscriptionAck` and `ServerHonorsNotificationFilter` — are FAILURE-capable
checks of implemented behaviour, and the second is a negative check that only fires on a leak. **The
honest claim is one positive FAILURE-capable check on the entire subscriptions surface.**

#### What the correction does and does not do to the client leg's D-3

D-3 in the section above says *"a WARNING fails the scenario (`overallFailure` disjoins `s>0`)"* and
uses that to argue the `-32022` retry had to be implemented. Under the measurement above:

* The parenthetical is **the client single-scenario reducer**, and the client leg was run with
  `--requirements`, whose **exit code** is FAILURE-only. So the parenthetical is not the rule that
  governed the run.
* The client suite summary's per-scenario mark **does** count warnings
  (`(failures===0 && warnings===0) ? '✓' : '✗'`), and the client leg's 8/32 was read from those
  marks. **So the reported figure is the one the parenthetical implies, and it does not move.**
* And D-3's justification never rested on the scoring rule anyway: it is discharged on normative
  text (`basic/versioning.mdx:69-71`, the client SHOULD retry). **The fix is right for the reason
  D-3 gave, and the scoring parenthetical beside it is narrower than it reads.**

### The empties, on the record — the whole ticket (A2d, both legs)

Named by count and by name, because "not run" absorbed into a denominator is the one thing MES-19's
published claim cannot survive.

| Empty | Count | What it is |
|---|---|---|
| `auth/*` scored **client** scenarios | **25** | no OAuth surface in this SDK. Deleted from the client denominator would read *better* than the truth, so the client leg reports N/32 with 7 as the core sub-figure and all 25 named. |
| Server `not_scored / pending` | **3** | `json-schema-2020-12`, `http-header-validation`, `http-custom-header-server-validation`. All three are **now driven** by this leg and reported above. Run, reported, never counted. |
| `extension` scenarios | **16** | 10 `tasks-*` (server) + 6 `auth/*` (client). Optional by definition (SEP-1730). |
| `added-after-release` | **1** | `json-schema-2020-12-preservation` (client). |
| **Leaves no row in any results file at all** | — | **MES-16's extensions negotiation.** Zero checks anywhere in either leg touch it (P-4, confirmed). **MES-15's `subscriptions/listen` is no longer in this bucket** — it moved to "measured but uncounted" (P-4 partly refuted, above). |
| Scored scenarios a **null implementation also passes** | **6** | server leg, enumerated above. The client leg's equivalent — `auth/resource-mismatch` passing with no implementation — was already named as its figure-1-vs-2 delta. |

### The combined ticket figure, both legs, one sentence each

```text
CLIENT  (conformance client --command "mix run conformance/client_adapter.exs"
         --requirements 2026-07-28 @ 0.2.0-alpha.11)
          8 / 32  harness-reported scored passes
          7 / 32  driven AND passing        (delta: auth/resource-mismatch, negative check)
          6 /  7  core, consumer-realistic drive

SERVER  (conformance server --url http://127.0.0.1:3001/mcp
         --requirements 2026-07-28 @ 0.2.0-alpha.11)
         35 / 37  harness-reported scored passes (--requirements verdict, FAILURE-only)
         33 / 37  under the harness's own stricter reducer (WARNING fails)
         29 / 37  scenarios a null implementation does NOT also pass

NOT COMPARABLE AND NOT ADDED TOGETHER. The client denominator is 78% auth scenarios this SDK
does not implement; the server denominator has none. A combined "43/69" would be arithmetic
without a meaning.
```

### Adversarial items — the server leg's answers

Items 1, 2, 3, 4, 5, 6, 7 and 8 were adjudicated in the plan (comment 24484) and again on the client
leg. What the server leg **changes**:

1. **Coverage obligation as an acceptance criterion — met, and by a different mechanism.** On the
   server leg the harness drives us, so there is no adapter drive list to get wrong: the
   `BLOCKING 2` shape (a hard-coded list that makes checks insensitive) **cannot recur**. The
   server-leg equivalent of "what the adapter must drive" is "what the fixture must **implement**",
   and it is met by construction — every check that ran found the tool or prompt it names. The two
   places it was *not* met before this leg were `json_schema_2020_12_tool` and the `x-mcp-header`
   tool, both now added and both `not_scored`.
2. **The scoring rules — CORRECTED by measurement.** Three rules, not two, and one of them is
   leg-dependent. See the correction section above.
3. **`checkMcpNameHeader`** — still dormant, still classified harness-side, encoder untouched.
4. **Handler-shaped friction — five findings, all reported even though fixing them is out of
   scope.** (a) no `data` slot on a handler error return (R5); (b) no mint/verify for `requestState`
   — the fixture had to invent `MCP.Conformance.RequestState`, and getting that wrong is a security
   defect rather than a rough edge; (c) `MRTR.input_required/2`'s `list()` typespec produces
   non-conforming wire (C-A); (d) `continuation_from_params/1` makes an ephemeral MRTR flow
   inexpressible (gap 2); (e) `Dispatch.complete/1` overwrites a handler-supplied `resultType`
   unconditionally. **MES-36 re-checked: our handler uses `/4` throughout, so the advertised-but-
   never-invoked 3-arity tool callback was not tripped over — recorded either way, as asked.**
   Separately: every callback in the old fixture used the **legacy** no-context arities, which
   `Dispatch` never invokes (MC-1 strict). That file could not have served a single scored scenario.
5. **Does `conformance/` compile — and now, does it FORMAT?** RULING 3 (restated) keeps it out of
   `elixirc_paths` for MES-24 and defers the question. This leg adds a second instance of the same
   shape, found while running gate 1: **`.formatter.exs` inputs are `{config,lib,test}/**` — so
   `conformance/` is outside gate 1 as well as gate 2.** Both files here were formatted by naming
   them explicitly (`mix format --check-formatted conformance/*.ex*` → clean), but nothing enforces
   that. The deferred ticket's brief should be *"which gates see `conformance/`, and which of its
   file types can they see"*, not just `elixirc_paths`. **RAISED as MES-46 (PM, comment 24503) with
   RULING 3 restated and the brief widened to both gates** — two of six are blind to `conformance/`,
   not one.
6. **Two modes, one SDK — still structurally empty, and now with the server half demonstrated.**
   Under `--requirements 2026-07-28` the server leg is driven by the harness's own stateless client
   (`wt`, a raw-fetch client in `dist/index.js`) and the client leg by the harness's own mock
   servers. **There is no run in this ticket in which our client talks to our server**, so a
   self-consistency failure cannot present as a conformance number. The residual risk is the other
   direction — our own fixture crashing and reading as a gap — and it did not materialise: no
   scenario failed with a transport-level error, and the one place a crash was possible
   (`{:input_required, …}` from `prompts/get`) was deliberately routed away from the shared server
   and probed in isolation instead.
7. **Old-revision exclusion — re-derived, superseded, not dropped.** See classification bucket 2.
8. **The empties — enumerated first this time**, per RULING 4, and then corrected by the null
   control which found three the reading had missed. **That is the finding under the finding: an
   empties list derived by reading was 50% complete; running a null implementation completed it.**

### CI-2 (PM carry-in, comment 24496): the two register corrections, now in the MES-24 entry

DoD item 6 requires this entry — the one MES-19 reads for the measurement — to carry the two
corrections MES-18 produced, rather than leaving them only in the MES-18 entry above.

1. **MRTR was marked `CONFORMANT` in the gap register and is not.** MES-18 refuted it client-side
   (D-1: `requestState` was sent as a present key holding JSON `null` when the server sent none).
   **This leg refutes it server-side as well, and more broadly:** SEP-2322 makes
   `InputRequiredResult` universal across `prompts/get`, `resources/read`, `tools/call` and
   `tasks/result`, and this SDK implements it on **`tools/call` alone** — measured, not read, by
   `input-required-result-non-tool-request` failing 0/2. A register entry marked done that is not
   done is more expensive than one marked open, because nobody looks again.
2. **CG2 was stale in the OPPOSITE direction.** The brief said the inbound extensions half was
   absent; it was functionally closed and evidentially open — `Discover.Result.from_map/1` delegates
   to `ServerCapabilities.from_map/1`, which parses it. Taken at face value the brief would have had
   MES-18 build a parser that already existed. **The server leg adds the other half of the picture:**
   extensions negotiation earns **zero** conformance coverage in either direction — no scenario in
   alpha.11 touches it — so CG2's status can only ever be evidenced by our own tests, never by the
   harness. That is a permanent property of the register entry, not a gap waiting to close.

### Gates — all six, individually, at the branch tip

```text
   mix hex --version                          Hex v2.5.1   (>= 2.5.1 floor met)
1  mix format --check-formatted               clean
   (+ mix format --check-formatted conformance/*.ex conformance/*.exs   clean — see item 5
      above: conformance/ is OUTSIDE the formatter's inputs, so this arm is manual)
2  mix compile --force --warnings-as-errors   clean (69 files)
3  mix credo                                  1090 mods/funs, found no issues
4  mix dialyzer                               Total errors: 0, Skipped: 0, Unnecessary Skips: 0
5  mix test                                   13 doctests, 558 tests, 0 failures   (546 -> 558, +12)
                                              + 20-seed sweep, 20/20 green
                                              (0 1 2 3 5 7 11 13 17 23 42 97 314
                                               777 1601 2024 4242 7777 9999 16180)
6a baseline sentinel @ d697093                PASS — all 22 known advisory ids present
6b mix hex.audit                              "No retired or security advisory
                                               packages found", exit 0
```

**Gate 6 residual: UNCHANGED at 21 unvalidated of 26.** No dependency added; `git diff main..HEAD --
mix.exs mix.lock` is empty. The `requestState` token uses `:crypto` from OTP, deliberately, so the
residual could not move.

**Gate 5's status on this leg is mixed and both halves are stated.** The 546 pre-existing tests are
a **positive control** — measured, not argued: with both `conformance/server_handler.ex` and
`conformance/server_adapter.exs` removed from the tree, `mix test` still reports 558 tests, 0
failures. The **12 new** `MCP.ConformanceRequestStateTest` tests are **evidence**: C-F short-circuits
the tag comparison and 5 of the 12 go red. The `test/` → `conformance/` coupling this creates is a
**deliberate cost, ratified by the PM (RULING 4, comment 24485)**, taken because a tamper-evident
token whose only evidence is "one scenario went green" is a single-instance check of a property
whose whole point is the rejection path.

### What this leg did NOT do

* **No SDK change.** `git diff main..HEAD -- lib/` is empty. Every one of the seven gaps and the one
  defect below is escalated, none is fixed. The single place the temptation was concrete —
  `test_missing_capability` needs `error.data.requiredCapabilities`, and adding a `data` slot to the
  handler error return is a ten-line change — was declined, and the check is red because of it.
* **No re-run of the client leg.** Its figures are unchanged and the WARNING correction was shown
  not to move them by reading its saved artefacts, not by re-measuring.
* **No `--expected-failures` baseline.** None is needed; MES-13's is superseded, with the reason
  recorded rather than the enumeration silently dropped.

### Escalations this leg produced

**To MES-43 (SEP-2322 / stateless-core surface), under the PM's standing pre-authorisation
(RULING 2, comment 24485):**

| # | Gap | Evidence |
|---|---|---|
| 1 | MRTR wired to `tools/call` only | `input-required-result-non-tool-request` 0/2; probe raising `FunctionClauseError` with a passing `tools/call` control |
| 2 | `continuation_from_params/1` drops `inputResponses` without `requestState` | `…ignore-extra-params` WARNING; `…missing-input-response`'s hollow green |
| 3 | no JSON-RPC-code → HTTP-status mapping | 12 of `server-stateless`'s 17 failures |
| 4 | handler error return has no `data` slot | `…rejects-undeclared-capability`; `sep-2164-data-uri` WARNING |
| 5 | `server/discover` does no `_meta` structural validation | 3 `…request-meta-invalid-*` failures |
| 6 | `server/discover` has no version gate; `initialize` answers `-32022` not `-32601` | `…unsupported-version-error`, `…404-initialize`. **Both contradict a documented SDK design decision.** **RE-ROUTED by PM ruling (comment 24503): this row does NOT join MES-43.** R3/R6 go to **MES-19** as decisions requiring a PO call at release. Kept in the table so the measurement is not lost, struck from the MES-43 hand-off. |
| 7 | `MRTR.input_required/2` typespec/doc say `list()`; the wire type is an object | C-A: the list form fails `wire-schema-valid` |
| 8 | `Dispatch.complete/1` overwrites a handler-supplied `resultType` unconditionally | the second failure in `…non-tool-request`, isolated by C-E |

**Needed its own ticket, a different class from MES-43 — RAISED by the PM as MES-45 (comment
24503), which carries both items below:**

* **SEP-2243 routing headers do not trim trailing OWS.** In MES-18's surface, landed 2026-08-20.
  Minimal reproducer with both controls above; a conforming client's request is rejected `-32020`.
* **SEP-2243 server-side `x-mcp-header` / `Mcp-Param-*` validation is absent entirely.**
  `check_routing_headers/2` reads no `Mcp-Param-*` header. 6 failures in
  `http-custom-header-server-validation`, and 4 greens there that cannot detect its absence.

**Upstream-shaped (not ours to fix):** the WARNING verdict asymmetry between the harness's three
reducers; `input-required-result-capability-check` cannot catch under-asking; and, carried forward
and still dormant, `checkMcpNameHeader`'s non-decoding comparison.

**Priority Hint:** high · **Blocking?:** unblocks MES-19 · **Suggested Jira Ticket?:** Yes — gaps
1–5, 7 and 8 join **MES-43**; **gap 6 (R3/R6) does not** — PM ruling, comment 24503, routes it to
**MES-19** as a decision requiring a PO call at release. The two SEP-2243 server-side items are
raised as **MES-45**; `elixirc_paths` **and now `.formatter.exs` inputs** coverage for `conformance/`
is **MES-46**, with RULING 3 restated in its brief.

---

## MES-19 — Conformance closure: re-measure, close the gap register, draft the claim (2026-08-20)

Sprint 4's closing ticket. Four deliverables: **(1)** confirm the measurement at the release commit,
**(2)** deterministic `tools/list` ordering (gap-register **E2**, the only code), **(3)** the
gap-register walk, **(4)** the conformance-claim wording, drafted and **not published**.

Plan on the ticket in five parts (comments 24507–24511); ratified by the PM in two parts (24512,
24513). Six ratification items were ruled — **RAT-5 overruled**, so the whole-tree OSV cross-check
runs in this sprint rather than at release (executed on **MES-49** after the split); **item 3
expanded 29 → 36 rows**; the register-adjacent scope
additions (README excision, ADR-003 amendment) are sanctioned scope under A9.

**The split, and what actually landed where (PM contract, comment 24529).** At 09:12 the PM cut
three sub-tasks off this parent. **MES-49** — confirm the measurement, plus RAT-5's OSV cross-check
— landed on its own branch from `7480f2f` and **merges separately**; the late split took for that
one, and its entry follows this one. **MES-48** (E2, deterministic `tools/list` ordering) and
**MES-47** (the README excision) did **not**: both were already committed on this branch before the
split — `07a8b26` and `45054d1` — and the PM retires them as delivered here rather than re-cutting
reviewed work into two extra merges. **Two of the three sub-tasks merge inside this ticket's squash;
one does not**, said in those words so the board neither implies extra merges nor hides the real one.
And MES-47's excision was **incomplete until CODE_REVIEWER found it**: it removed *100% conformance
(Tier 1)* and left a wrong-*revision* implementation claim standing in the same paragraph, in
`README.md` and in a fourth shipped file nobody had looked at (round 2, below). MES-47 is retired as
delivered by `45054d1` **plus** its completion in `d158e68`, not by `45054d1` alone.

### Pre-run prediction — committed before the harness was started

C-1 rewrote deliverable 1 from *re-run* to *confirm at the release commit*: MES-24 measured both legs
five hours earlier, and the tree it measured is content-identical to merged `main` (verified by the
PM at the squash; **inherited here, not re-derived by me** — the MES-24 branch was deleted at the
squash, so I cannot diff against it and I will not imply that I did).

That makes this confirmation, not discovery — which is exactly the shape in which a re-run gets
quietly adjusted to the number everyone expects. So the prediction below is in **its own commit,
made before the harness was started**, and it is on the ticket (comment 24509) timestamped before
any run. Where the run contradicts a line, the line is reported **refuted at full strength** rather
than corrected.

```text
PREDICTION @ 7480f2f, @modelcontextprotocol/conformance@0.2.0-alpha.11,
--requirements 2026-07-28, both legs, adjudicated from saved -o artefacts.

SERVER  conformance server --url http://127.0.0.1:3001/mcp
  35 / 37   harness-reported PASS (--requirements verdict, FAILURE-only)
  33 / 37   under the harness's own stricter reducer (WARNING fails)
  29 / 37   discriminating = ours minus the null control's 6
  98 SUCCESS / 19 FAILURE / 2 WARNING / 0 SKIPPED over 117 SUCCESS+FAILURE
  all 19 FAILUREs in exactly TWO scenarios:
      server-stateless                          13 SUCCESS / 17 FAILURE
      input-required-result-non-tool-request      0 SUCCESS /  2 FAILURE
  the 2 WARNINGs, one each, in two scenarios that nonetheless PASS:
      sep-2164-resource-not-found  (sep-2164-data-uri)
      input-required-result-ignore-extra-params  (sep-2322-ignore-unexpected-params)

NULL CONTROL (25-line always -32601 server, not our implementation)
   6 / 37   FAILURE-only        3 / 37   warnings-also-fail
  and our 35 is a SUPERSET of its 6, which is what makes the subtraction legal

CLIENT  conformance client --command "mix run conformance/client_adapter.exs"
   8 / 32   harness-reported scored passes
   7 / 32   driven by the adapter AND passing
   6 /  7   core (non-auth/*), under a consumer-realistic drive
  0 WARNING across every client check (57 SUCCESS / 61 FAILURE / 8 SKIPPED / 1 INFO)

not_scored, run and reported, never counted:
  server  json-schema-2020-12                    8 S /  0 F
          http-header-validation                 9 S /  3 F / 2 W
          http-custom-header-server-validation    4 S /  6 F
          tasks-* (10)                          12 S / 30 F
  client  6 auth/* extension scenarios, all failing
          json-schema-2020-12-preservation       9 / 9 PASS
```

**Predicted delta against MES-24: ZERO, and it is a self-consistency check, not a measure of
progress.** The tree is content-identical and no dependency moved, so any non-zero delta means
something moved that should not have — and the first hypothesis to test is not *the SDK regressed*
but *the tree I am measuring is not the tree MES-24 measured*.

**Two ways this run can lie, and what is done about each.**

1. **A starved scenario is indistinguishable from a conformance failure.** The requirement-set runner
   starts all scenarios in parallel, each spawning `mix`, and they contend on the `_build` lock.
   MES-24's F-10 instructs this ticket to pin `--timeout` explicitly and record the headroom, because
   "a margin nobody set is not a margin anybody can rely on". Any timeout-shaped failure is
   re-checked serially before it is believed. `mix run --no-compile` does **not** help — CR measured
   that it makes the waits more frequent, not fewer.
2. **`--requirements` and `--scenario` are mutually exclusive** by the CLI's own refusal, so
   single-scenario arms run as `--scenario X --spec-version 2026-07-28` and are labelled as a
   different invocation. They are never quoted as suite figures.

**The null control is re-run here rather than inherited.** Its 6/37 is a property of the harness, not
of `7480f2f`, so inheriting it would be defensible. But the 29 is the figure with the largest blast
radius in deliverable 4, and inheriting the subtrahend for a number about to be certified is the
exact shape this sprint keeps finding. It is a 25-line script and one run.

### Item 1 and RAT-5 — de-duplicated into the MES-49 entry (PM contract, comment 24529)

Deliverable 1's two halves — the measurement at the release commit, and the whole-tree OSV
cross-check — were **run twice**: here on this branch (`9d662ab`, 08:31 UTC), and again on the
sub-task the PM split out afterwards (`4edd6d8`, 09:00 UTC). Two independent runs that agree check
for check is worth having. **Two copies of the same measurement in the A8 record is not**, and the PM
ruled the sub-task's copy the surviving one. Deleted here rather than summarised, because a summary
of a measurement beside the measurement is a second place for the figures to drift.

**The record is under the heading `## MES-49 — Confirm the measurement at the release commit;
whole-tree OSV cross-check` in this file.** Cited by heading and deliberately *not* by line number:
a line number into an append-only log is stale the next time anybody appends to it, and every figure
this ticket certifies would then point somewhere else.

**What left this entry, enumerated, so the de-duplication is not silently a deletion (A2d):**

| dropped from here | where it lives in the MES-49 entry |
|---|---|
| the axis-by-axis measurement table and its **zero** delta against MES-24 | `### Part A — the measurement at 7480f2f, adjudicated` |
| the refuted all-scenario client census, and the stale-artefact adjudication that settled it | `#### The refuted row, at full strength, and it is not the SDK` |
| the re-run null **server** control (6/37) and the `null ⊆ ours` superset check that makes the subtraction legal | `### Part A — the measurement at 7480f2f, adjudicated` |
| `--timeout` pinned on the leg that has it, and named as absent on the leg that does not | `#### --timeout: pinned where it exists, and named where it does not` |
| **C-2** — there is no comparable baseline, so "what moved" answers *nothing, and nothing could have* | `#### C-2 — there is no comparable baseline, and this report says so` |
| **C-3** — the old-revision bucket, re-derived against the frozen set and found **empty** | `#### C-3 — the old-revision exclusion, re-derived against the frozen set, and found empty` |
| **RAT-5** — the OSV cross-check, its positive control, Sprint 5's re-run obligation, and the unchanged 21-of-26 gate-6 residual | `### Part B — RAT-5, the whole-tree OSV cross-check, with its positive control` |

Two of those — the `--timeout` reading and the stale-artefact refutation — were **first recorded on
this branch** and independently re-derived on the sub-task half an hour later. Saying so is the point
of the table: de-duplication moves the record, and it should not quietly move the provenance with it.

**And one control the MES-49 entry has that this one never had: the null CLIENT.** It is why the
claim draft below now reads **5 of 7** and not 6 of 7 — see *Round 3* at the end of this entry.

**The pre-run prediction commit is dropped from this branch outright.** `498f7b1` is on `main` as
MES-49's `b4c2f9c`, cherry-picked with its author date `07:56:30 UTC` preserved; `git diff 498f7b1
b4c2f9c` is empty — verified by the PM and re-verified here immediately before the drop. The
prediction text is anchored outside git on MES-19 comment **24509** (07:43:31 UTC) in any case, so
what was predicted does not depend on which branch carries the commit.

#### The one finding that stays here, because the MES-49 entry cites it by name

Three of the repeat client runs were invoked with the harness's cwd rather than the project's.
`mix run` outside a Mix project cannot start the adapter — and the harness **said nothing**. It
produced a full 39-scenario sheet, 39 saved `checks.json`, a plausible check census
(13 S / 83 F / 17 SKIPPED / 1 INFO) and a scored figure of **2/32**.

**A misconfigured run and a measured gap are the same shape on the result sheet.** 2/32 does not
announce itself as *"your adapter never started"*; it reads exactly like a poor implementation.
Recorded as a **control**: it discriminates the measurement apparatus, not the SDK — and it is why
every figure in the surviving record is quoted with its invocation and cwd attached. MES-49 then
reproduced that census check for check **on purpose**, with a null client whose entire body is
`exit 0`, which is what turned an accident into a control.

### Item 2 — E2, deterministic `tools/list` ordering. The only code.

**Normative anchor (A4).** `docs/specification/2026-07-28/server/tools.mdx:71-74` at pin
`5f5440bb26a62e2cf3440b92da5a667efa03b267`, md5 `c302125aae381e9be1feb96305341d4b` (verified today
against the local `/tmp/spec2026` pin **and** re-fetched from `raw.githubusercontent.com` at that
commit, both md5s identical — see RAT-4 below):

> Servers **SHOULD** return tools in a deterministic order (i.e., the same ordering across requests
> when the underlying set of tools has not changed). Deterministic ordering enables clients to
> reliably cache the tool list and improves LLM prompt cache hit rates when tools are included in
> model context.

**It is a stability rule, not a sortedness rule.** Alphabetical is *sufficient* and is not
*necessary*: a curated order that never changes already conforms. That governs the whole item and it
is why the PM's brief calling E2 "an obvious one-line implementation" was withdrawn at RAT-1 — an
unconditional sort implements one sufficient way of meeting the SHOULD while overriding another way
that already meets it, which is precisely what `handler.ex:57-61` refuses to do for `outputSchema`
two callbacks away.

**Shape (RAT-1, ratified):** `MCP.Server.Config` gains `:tool_order` — `:name` by default (sort each
response by the tool's `"name"`), `:handler` to pass the handler's order through verbatim. Sort
applied in `dispatch.ex` between the handler's return and `list_result/3`. Config-time validation
follows the `:extensions` precedent: an unrecognised value warns and falls back to `:name` rather
than refusing to start.

**The bound, in the code and the docs and this row — not only in the report.** The guarantee is
*deterministic within each **response**, given a deterministic page*. `tools/list` is paginated and
the sort is per response: sorting a page does not make a concatenated listing sorted, and if the
handler's own paging returns different page *contents* per request, per-page sorting neither fixes
that nor reveals it. Written as "this SDK makes your listing deterministic" it would be a claim
wider than its check, in the ticket about claims wider than their checks.

#### The trap, which is real, and which my own plan walked into

The plan named the risk correctly — *the SDK introduces no ordering nondeterminism today, so a test
against an already-deterministic handler is a green that cannot go red* — and then proposed a
fixture that would have been exactly that. **Measured before writing a line** (`/tmp/mes19/ets_probe.exs`):

```text
tab2list, 50 reads of ONE UNCHANGED :set table          -> 1 distinct order
Map.keys, 50 reads of a 24-key map                      -> 1 distinct order
Map.keys, two maps, same keys, different insertion       -> IDENTICAL
20 :set tables, same keys, SHUFFLED insertion            -> 4 distinct orders
```

So "list twice from an ETS set" **cannot go red**, and the `Map`-backed registry is not a source of
nondeterminism at this size either. The realistic violation is across **differently-populated**
registries — which is the **2026-07-28 stateless core's own deployment model**: any instance behind a
round-robin balancer may serve any request, so two instances holding the identical tool set can
disagree on its order and invalidate the client's tool-list cache. That is the harm `tools.mdx:73-74`
names, and it is what the fixture models.

Pinned deterministic pair: forward vs reversed insertion of the same 24 names, reproducible across
BEAM restarts (`tool_20`/`tool_11` transpose at index 9, `tool_23`/`tool_7` at index 19).

#### A7 — the arms, controls labelled as controls

```text
RED (before the fix, saved at /tmp/mes19/e2-RED.txt)          8 tests, 3 failures
  SUBJECT two instances                    left/right differ at indices 9 and 19
  SUBJECT default order is by name         left = ETS order, right = sorted
  BOUND   per-page sort                    page returned in ETS order

GREEN (after the fix)                                         8 tests, 0 failures

MUTANT — source mutation, `order_tools/2` call site disabled   8 tests, 3 failures
  exactly the three E2-sensitive arms go red again; GUARD and both controls stay
  green. The test is sensitive to THIS mechanism, not to something incidental
  about the fixture.                        (saved at /tmp/mes19/e2-MUTANT.txt)

MUTANT (in-tree, permanent) — `:tool_order = :handler` on both instances
  reproduces the pre-fix divergence inside the suite, so the falsifiability
  evidence runs on every `mix test` rather than living in a shell transcript.

GUARD — the fixture precondition, asserted
  the two population orders MUST actually diverge. If a future ERTS makes them
  agree, the SUBJECT arm would start passing for a reason unrelated to the SDK;
  the guard fails loudly instead of passing vacuously.

CONTROL-1 — :tool_order = :handler with a curated non-alphabetical order
  order survives to the wire unchanged -> the default is what does the work and
  the escape hatch is real, not decorative.

CONTROL-2 (DISCRIMINATES NOTHING, and is labelled so in the test name itself)
  an already-deterministic handler under default config: green before AND after.
  Present so that nobody can quote it as evidence for E2.
```

#### Harness coverage: zero, and it is now *measured* zero rather than read zero

The plan established by grepping alpha.11's `dist/index.js` that no ordering check exists — the
`tools-list` family is `tools-list`, `tools-list-caching-hints`,
`tools-list-changed-on-subscription`, `tools-list-gate`, and none reads order. That is reading. The
run makes it a measurement:

```text
tools-list scenario, PRE-E2  first five: test_simple_text, test_image_content, …   sorted? False
tools-list scenario, POST-E2 first five: json_schema_2020_12_tool, test_audio…     sorted? True
scenario verdict lines, PRE vs POST:     IDENTICAL — not one verdict moved
scored figures, PRE vs POST:             35/37, 33/37, 98 S / 19 F / 2 W — identical
```

**The wire behaviour demonstrably changed, observed by the harness in its own artefact, and the
score did not move by one check.** "Added code, number went up" is not available here, and its
absence is stated rather than left implied. E2's row cites this file's mutation arm and nothing else.

#### RAT-4 — the negative claim, verified against the documents that would have carried the positive

E2 is scoped to tools because **the spec** scopes it there, and that is a negative claim about
`prompts/list` and `resources/list`. The local pin holds only `server/tools.mdx`, so asserting the
absence from it would have been asserting an absence from a document that does not contain the
subject. Both pages fetched at the same commit:

```text
POSITIVE CONTROL  server/tools.mdx    @5f5440bb -> md5 c302125aae381e9be1feb96305341d4b
                  == the local pin's md5. The fetch path returns THIS revision,
                  not a redirect, a 404 page or main.
server/prompts.mdx   @5f5440bb -> md5 5b4a22a4ec8413f2a0e117186b327d60  (336 lines, 9490 B)
server/resources.mdx @5f5440bb -> md5 5b2993e19109d73138c78803edfba6cc  (435 lines, 12958 B)

grep -i 'deterministic|order' :  tools.mdx -> 2 hits (:71, :72)
                                 prompts.mdx   -> ZERO
                                 resources.mdx -> ZERO
```

**Scoping E2 to tools is the spec's scoping, not ours.** Anyone re-checking these two citations on a
fresh container must fetch them first — the pin does not contain them.

### Item 3 — the gap-register walk. 36 rows. The sprint's exit criterion.

**Scope: 29 + 7 = 36, PM-ratified.** D1 v5 (Confluence 239861761) has **29** rows — A1–A6, B1–B4,
C1–C3, D1–D4, E1–E2, F1–F4, G1, the §H `_meta` block (one row, seven prefixed keys), I1–I2, J1, K1.
**It is a server-side register and does not contain the client series at all**; CG1–CG7 come from
MES-13's D3 finding, and MES-18 recorded in as many words that "CG7 was absent from the gap
register". ADR-003 sub-decision 4 holds the client to the server's bar, so walking 29 and calling the
register closed would be a claim wider than its check **inside the sprint's own exit criterion**. The
two registers' provenance is labelled separately below so no CG row is later read as having been in
D1 v5.

**Method — RULING 4 applied per row, not quoted at the top.** Four fields. The third does the work.

1. **Verdict** — implemented / implemented on unfalsifiable evidence / deliberately excluded (ADR-003
   sub-decision cited) / outstanding.
2. **Evidence** — the specific test, check id or measurement, cited to file or scenario.
3. **Could that evidence have gone red?** A mutation that turns it red, or a plain statement that
   its checks cannot distinguish our implementation from its absence. **A row whose answer is "no"
   is NOT marked implemented** — it is marked *implemented on unfalsifiable evidence*, which is a
   different promise and reads as one.
4. **If outstanding** — owner, ticket key, and **raised** vs **scheduled**.

**Field 4's answer is uniform and unflattering, and is not softened.** Measured by JQL, not by
opening tickets one at a time: the thirteen escalation tickets (MES-29, 32, 35, 36, 38, 39, 40, 41,
42, 43, 44, 45, 46) are **all `To Do` with no sprint** — `status = "To Do" AND sprint is EMPTY`
returns **13**, i.e. all of them — and `sprint in ("MES Sprint 5")` returns **0 issues**. So
**thirteen raised, none scheduled**, and no row can honestly be marked scheduled today. Per the PM's
RAT-3 ruling the DoD bullet means *has a named owner ticket*, not *is in the sprint*; reading it the
second way would make the sprint unclosable until the next sprint is planned, which is circular.
A consumer is entitled to the difference between the two promises, so both words appear.

#### Register 1 — D1 v5 (server-side), 29 rows

| # | Requirement | Verdict | Evidence | Could it have gone red? | Owner |
|---|---|---|---|---|---|
| A1 | `initialize`/`initialized` handshake removed (SEP-2575) | implemented | `dispatch.ex:131-139` answers `-32022`; `streamable_http_stateless_test.exs` | **yes** — `server-stateless` `…404-initialize` FAILS today, so the path is demonstrably driven (it fails on the *transport status*, not on the removal) | — |
| A2 | Per-request version / client caps / client info via prefixed `_meta` | implemented | `meta.ex:41-44`; `dispatch.ex:162-168` gate; `meta_test.exs` | **yes** — `sep-2575-request-meta-*` checks are positive and three of them FAIL today on the status mapping | — |
| A3 | `server/discover` advertises versions, capabilities, identity | implemented | `dispatch.ex:148-158`; `discover.ex` | **yes** — the null control fails `server-stateless`'s discover checks; we pass them | — |
| A4 | `ping` removed | implemented | `dispatch.ex:141-144` | **yes** — `…404-ping` FAILS on the status mapping, so the method is probed | — |
| A5 | `logging/setLevel` removed; level per request via `_meta` | **implemented (removal); OUTSTANDING (the `_meta` half)** | removal: `dispatch.ex:141-144`. `io.modelcontextprotocol/logLevel` is *parsed* (`meta.ex:44`) but the **client never writes it** — `client.ex:821-829` `with_meta/2` is a closed three-key map | removal **yes** (`…404-logging-setlevel` probes it). The write half: **no scenario anywhere** | **MES-32**, raised, **not scheduled** |
| A6 | Old-shape requests fail fast `-32022` | implemented | `dispatch.ex:167`; `error.ex:18` | **yes** — `sep-2575-server-unsupported-version-error` FAILS today (R6: we answer `-32022` where the referee wants `-32601`+404) | PO call at release |
| B1 | Session + `Mcp-Session-Id` removed (SEP-2567) | implemented | `plug.ex:6,29-30` — no session handling exists | **partly** — the `server-stateless` scenario would notice a session header; but *absence* is the safe direction, so this is close to a negative check | — |
| B2 | Server becomes request-scoped | implemented | `MCP.Server.Dispatch` is a pure per-request function; `dispatch_test.exs` | **yes** — every scored scenario drives it | — |
| B3 | Cross-call state = server-minted state handles (SEP-2567) | implemented | `state_handle_test.exs`; `conformance_request_state_test.exs` | **yes** — `input-required-result-tampered-state` and `-request-state` both drive it and both would fail on a forged handle | — |
| B4 | Identity MUST NOT use the state-handle mechanism | implemented | `dispatch_test.exs` MC-4 (a spoofed `identity` arg never reaches `ctx.identity`) | **yes** — MC-4 is a positive assertion with an adversarial input | — |
| C1 | **MRTR** (SEP-2322): `InputRequiredResult` replaces held-open server→client requests | **OUTSTANDING, bounded** — *the register marks this CONFORMANT and it is not* | refuted server-side by `input-required-result-non-tool-request` **0/2**, and client-side by MES-18's D-1. SEP-2322 makes `InputRequiredResult` **universal**; we implement it on `tools/call` alone | **yes, and it went red** | **MES-43**, raised, **not scheduled** |
| C2 | Server-initiated requests only while processing a client request (SEP-2260) | implemented **by construction** | there is no server-initiated request path left at all — MRTR replaced it | **no — the property holds because the feature is absent.** Nothing can distinguish us from an implementation that never considered the rule | — |
| C3 | `resultType` required on every result | implemented | `dispatch.ex:489-490` | **yes** — `input-required-result-result-type` is positive and drives it | — |
| D1 | Routing headers `Mcp-Method`/`Mcp-Name`; custom headers via `x-mcp-header` (SEP-2243) | **implemented (client + server read); OUTSTANDING (server-side `Mcp-Param-*` validation, trailing OWS)** | client: `streamable_http/client.ex:44-60,146`; mirroring: `header_mirror.ex`. Scored evidence: `http-standard-headers` 9/9, `http-custom-headers` 18/18, `http-invalid-tool-headers` 11/11 | **yes** — MES-24 showed `http-invalid-tool-headers` scoring 11/11 with the MUST switched off until the drive was made falsifiable; it is falsifiable now | **MES-45**, raised, **not scheduled** |
| D2 | `subscriptions/listen` replaces the GET SSE endpoint and `resources/(un)subscribe` | **implemented, HTTP server-side only** | `subscriptions_dispatch_test.exs`, `subscriptions_stream_test.exs` | **weakly.** P-4 was partly refuted — five checks do drive it — but with `broadcast/2` a no-op, two degrade to WARNING and a third stays SUCCESS on the ack frame alone. **The honest count is ONE positive FAILURE-capable check on the entire subscriptions surface**, and this row carries that number, not the five | stdio **MES-29**; client **MES-38**; both raised, **neither scheduled** |
| D3 | SSE resumability removed (no `Last-Event-ID`, no event ids) | implemented | `plug.ex:30,671` — no resumption path exists | **no — negative by construction.** An implementation that never had resumability scores identically | — |
| D4 | localhost / Origin enforcement carried forward | implemented | `plug.ex:301-306,1049` | **yes** — `dns-rebinding-protection` requires a 4xx on `evil.example.com` *and* a 2xx on localhost; the null control **fails** it | — |
| E1 | `ttlMs` + `cacheScope` REQUIRED on the five cacheable results (SEP-2549) | implemented | `dispatch.ex:492-501`; `streamable_http_cache_scope_warning_test.exs` | **yes** — `caching` is 7 positive checks across all five endpoints; the null control fails 6 of them | — |
| E2 | Deterministic `tools/list` ordering (**SHOULD**) | **implemented — this ticket** | `test/mcp/server/tool_order_test.exs`; `dispatch.ex` `order_tools/2` | **yes — by mutation, and by nothing else.** alpha.11 has **zero** ordering checks in either leg; measured, not merely read (the wire order changed from unsorted to sorted and not one scored verdict moved). The row cites the mutation arm and the harness contributes nothing in either direction | — |
| F1 | Reserved range `-32020..-32099`; policy | implemented | `error.ex:12,46` | **no — a policy statement in a doc comment.** No check anywhere tests that we *refrain* from using the range | — |
| F2 | `-32020` / `-32021` / `-32022` | implemented | `error.ex:16-18` | **yes** — `sep-2575-server-rejects-undeclared-capability` observes our `-32021` (and FAILS on the transport status, R1) | — |
| F3 | Resource-not-found `-32002 → -32602` (SEP-2164) | implemented | `error.ex:52,125`; `error_test.exs` | **yes** — `sep-2164-error-code` is positive; **but** the sibling `sep-2164-data-uri` is **WARNING against us today** (see the two-greens note below) | — |
| F4 | `-32042` url-elicitation helper removed | implemented | `error.ex:22,27` — helper absent | **no — negative.** Absence is not observable by any check | — |
| G1 | Remove `elicitationId` + `notifications/elicitation/complete` + `-32042`; URL-mode **retained** | implemented | `elicitation.ex:18` | **no — negative for the removals.** The retained half (`mode`/`url`, `elicitation.url`) has no scored scenario either | — |
| §H | Seven prefixed `_meta` keys | **implemented ×5, OUTSTANDING ×2** | present: `protocolVersion`, `clientCapabilities`, `clientInfo`, `serverInfo`, `subscriptionId` (`meta.ex:41-52`). **Absent on the write side: `logLevel` and the three SEP-414 trace keys** — `meta.ex:54-57` *defines* `traceparent`/`tracestate`/`baggage` and nothing writes them; `client.ex:821-829` is a closed three-key map | the five present: **yes** (`request-metadata` 8/8, positive). The two absent: **no scenario exists** | **MES-32**, raised, **not scheduled** |
| I1 | Roots / Sampling / Logging deprecated, functional in-window | implemented | `handler.ex:242-245` | **no — a documentation annotation.** Nothing tests that a deprecation notice exists | — |
| I2 | HTTP+SSE transport & `includeContext` reclassified | implemented | `plug.ex` is Streamable HTTP only | **no — negative** | — |
| J1 | Extensions negotiation surface, core, supporting **zero** extensions (SEP-2133) | **implemented on unfalsifiable evidence (harness); implemented on our own tests** | `extensions.ex`; `extensions_test.exs`, `extensions_negotiation_test.exs`, `capabilities_test.exs` | **no, from the harness — and this is permanent, not a gap waiting to close.** **Zero** checks in either leg touch extensions; the row leaves **no result-file row at all**. Our own tests are falsifiable and are the only evidence that will ever exist unless the suite adds a scenario | — |
| K1 | JSON Schema 2020-12 for tool schemas (SEP-2106/1613) | implemented, **server and client** | `json_schema_2020_12_test.exs`; `client_tool_schemas_test.exs` | **yes, and it earns ZERO scoring credit.** Server `json-schema-2020-12` is 8/8 but `not_scored` (`reason: pending`); client `json-schema-2020-12-preservation` is 9/9 but `not_scored` (`added-after-release`). Measured and uncounted — a *different kind of zero* from J1's, which leaves no row at all | — |

#### Register 2 — the CG client series (MES-13 D3; **never in D1 v5**), 7 rows

| # | Requirement | Verdict | Evidence | Could it have gone red? | Owner |
|---|---|---|---|---|---|
| CG1 | Client transport omits `Mcp-Method`/`Mcp-Name` on POST (SEP-2243) | implemented — MES-18 | `routing_headers_test.exs` T-CG1a/b/c; scored `http-standard-headers` 9/9 + 2 SKIPPED | **yes** — MES-18 ran the reverting mutation | — |
| CG2 | Client-side wiring of extensions negotiation | implemented — MES-18; **and the register entry was stale in the OPPOSITE direction** | `discover.ex:74` → `server_capabilities.ex:36`; `MCP.Client` stores and exposes it. It was **functionally closed, evidentially open** — taken at face value MES-18 would have built a parser that already exists | **no, from the harness** — zero checks, as J1 | — |
| CG3 | Client-side `subscriptions/listen` stream consumption | **OUTSTANDING, in full** | not implemented. `streamable_http/client.ex:120-129` POSTs synchronously inside the GenServer, so a held-open stream would block the whole transport | **no scenario exists** — no client `subscriptions/listen` scenario in alpha.11's client list **or** its `not_scored` block, so deferring it costs the figure nothing and the figure says nothing about it | **MES-38**, raised, **not scheduled** |
| CG4 | `$ref` never dereferenced (SEP-2106 security MUST NOT) | **implemented on unfalsifiable evidence** | `client_conformance_test.exs` T-CG4 canary; scored `json-schema-ref-no-deref` 1/1 | **NO — and this is the clearest instance in the register.** The single check is **negative**: a client with no `$ref` handling at all scores the same SUCCESS. MES-24 restated its own row 7 to say exactly this, and MES-18 admitted the T-CG4 canary is likewise unguarded. **The property holds because a feature is missing** | — |
| CG5 | Client honours `ttlMs` / `cacheScope` | **OUTSTANDING** | `discover.ex:77-78` parses both; **no store exists** | no scenario | **MES-39**, raised, **not scheduled**. *(Not MES-9 — MES-9 is `Done` in a closed sprint, and a deferral to a finished ticket reads as owned and cannot act. MES-39's own body instructs this ticket in those words.)* |
| CG6 | Client writes trace-context `_meta` (SEP-414) | **OUTSTANDING** | `meta.ex:54-57` defines the three W3C keys; nothing writes them. The write side is `with_meta/2`'s closed three-key map — which is MES-32's defect | no scenario | **MES-32**, raised, **not scheduled** |
| CG7 | `x-mcp-header` / `Mcp-Param-*` mirroring, client side | implemented — MES-18 | `header_mirror.ex`; `header_mirror_test.exs` (all ten of alpha.11's invalid-tool classes named); scored `http-custom-headers` 18/18, `http-invalid-tool-headers` 11/11 | **yes — by mutation.** With CG7's exclusion switched off, `http-invalid-tool-headers` went 1/11 FAILED. **Three of the six annotation constraints earn no harness credit at all** (`number`-exclusion, integer safe range, static reachability) and are ours alone | — |

#### Two rows that are decisions, not gaps (carried-in ruling — not re-derived, not routed to MES-43)

| | Behaviour | Status |
|---|---|---|
| **R3** | `server/discover` has **no version gate** | a **documented SDK decision the referee contradicts**. Arrives as a **decision requiring a PO call at release** |
| **R6** | `initialize` answers **`-32022`**, not `-32601` + HTTP 404 | same |

Both are consumer-visible whichever way the PO rules, so both are named in the claim draft.

#### The two greens over unmet SHOULDs — adversarial item 3, answered

`sep-2164-resource-not-found` and `input-required-result-ignore-extra-params` each **pass while
carrying a WARNING the harness raised against us**, and both are inside the 35. **Position: the claim
can stand over them, but only with a sentence saying so.** A SHOULD is not a MUST — but "we pass"
over a SHOULD the referee itself recorded as unmet needs stating, not least because **which verdict
you read decides it**: the same two are ✗ under the client single-scenario reducer and ✓ under the
server summary and the `--requirements` exit code. Quoting **35** without that sentence is the single
most quotable-back-at-us thing available, so the sentence is in the draft, not only here.

#### Walk outcome

```text
36 rows walked  =  29 (D1 v5, server)  +  7 (CG series, client)

                                        D1 v5    CG    TOTAL
  implemented, falsifiable evidence        16      2      18
  implemented ON UNFALSIFIABLE EVIDENCE     8      2      10   <- a different promise, and it reads as one
  implemented in part, rest outstanding     4      0       4   (A5, D1, D2, §H)
  OUTSTANDING in full                       1      3       4   (C1/MRTR, CG3, CG5, CG6)
  deliberately excluded (sub-decision)      0      0       0   <- see below
                                          ----   ----   -----
                                            29      7      36

  decisions requiring a PO call at release   2   (R3, R6 — rows in neither register; recorded, not re-derived)

OUTSTANDING ITEMS (the 4 whole rows + the 4 remainders of the part-done rows) = 8
  with a named owner ticket                8/8   C1->MES-43 · CG3->MES-38 · CG5->MES-39 · CG6->MES-32
                                                 A5->MES-32 · D1->MES-45 · D2->MES-29+MES-38 · §H->MES-32
  SCHEDULED                                0/8
rows with NO owner, needing a new ticket     0   <- nothing for the PM to raise at close-out
```

**Zero rows are "deliberately excluded".** ADR-003 sub-decision 1 puts the *entire* core register in
scope and sub-decision 4 holds the client to the same bar, so there was no sub-decision available to
cite for an exclusion — and sub-decision 5's exclusion clause is the one C-3 found empty and
recommends recording as superseded. **A register walk that produced no exclusions is the correct
outcome here, and it is stated rather than left as an absence.**

**Ten rows carry `implemented on unfalsifiable evidence`** — C2, D3, F1, F4, G1, I1, I2, J1 in D1
v5, and CG2, CG4 in the client series. (E2 is *not* among them: it is unfalsifiable from the
**harness's** side and falsifiable from ours, by mutation — which is exactly the distinction the
verdict is for.)

**The plan named three of the ten before the walk** — CG4, and J1/CG2 as a pair — and predicted the
walk would **add** to the list rather than confirm it. **It added seven: C2, D3, F1, F4, G1, I1,
I2.** Every one of the seven is a *removal* or a *policy statement*: absence is not observable, so no
check can distinguish us from an implementation that never considered the requirement. That is the
same "reading gets you halfway, running the control gets you the rest" result MES-24 obtained from
the null implementation, arriving one ticket later in a different medium.

### Item 4 — the conformance-claim wording. **DRAFT. NOT PUBLISHED.**

Smallest deliverable, largest blast radius, and the only artefact here that outlives the harness
version it was measured against. Drafted to ADR-003 sub-decision 6, landing per **C-4** in the repo
and on the ticket rather than as a Confluence child page. **Published by Sprint 5's release ticket,
which owns the wording under ADR-003.** It is reproduced here in full and is not in `README.md`.

---

> #### DRAFT — MCP conformance statement for `mcp_elixir_sdk` 2.0.0
> *Not published. Sprint 5's release ticket owns publication and the PO owes the final wording.*
>
> **Scope.** This release targets the **core** specification of MCP **2026-07-28** — the stateless
> core — on both the server and the client side. **The authorization profile is not implemented**
> (client OAuth 2.1 and the revision's client-side auth-hardening SEPs). **The extension track is
> not implemented** (Tasks, MCP Apps); the extensions *negotiation surface* is core and is
> implemented, supporting **zero** extensions. **2025-11-25 is not supported on either side** — an
> old-shape request fails fast with `UnsupportedProtocolVersion` (`-32022`) and nothing negotiates
> down.
>
> **What the claim rests on.** Our own ported acceptance suite. **Nobody has certified this SDK**,
> and nothing here should be read as certification by the MCP conformance project.
>
> **Supporting evidence, and what it is worth.** Measured against
> `@modelcontextprotocol/conformance@**0.2.0-alpha.11**` — a **pre-release** — using the frozen
> `2026-07-28` requirement set. All three axes, because no single one of them is the number:
>
> * **35 of 37** scored server scenarios pass under the harness's `--requirements` exit rule, which
>   fails a scenario only on a FAILURE.
> * **33 of 37** under the harness's own stricter reducer, in which a WARNING also fails.
> * **29 of 37** are scenarios a **null implementation does not also pass** — a 25-line server
>   answering `-32601` to everything scores 6 of 37 against the same suite. The 29 is *a
>   conservative floor on scenario-level evidence contributed beyond a minimal valid-envelope null,
>   not a conformance-rate estimate.* It is not "29/37" and it is not a pass rate.
> * On the client side, **8 of 32** scored scenarios pass — of which **25 of the 32 are `auth/*`
>   scenarios for the authorization profile this release does not implement**. That 8 means nothing
>   until **two independent subtractions** have been applied to it. They are independent in the strict
>   sense: they remove **different** scenarios, and they compose.
>
>   ```text
>   8 of 32  harness-reported scored passes
>     −2     the two scenarios a NULL CLIENT also passes — auth/resource-mismatch and
>            http-standard-headers. (Control: a client whose entire body is `exit 0`,
>            handed the mock server's URL and doing nothing with it, scores 2/32.)
>   6 of 32  scored AND discriminating, whole-suite axis
>
>   Restricted to the 7 core (non-auth/*) scenarios, which is where a consumer of this
>   release actually lives:
>
>   7 of 7   core, AS DRIVEN by our conformance adapter
>     −1  A  DRIVE POLICY — request-metadata survives only because the adapter carries on
>            driving after MCP.Client.connect/1 has already returned an error, and a real
>            consumer stops at a failed connect
>     −1  B  NULL-PASSABLE — http-standard-headers is passed by the exit-0 null client,
>            because the scenario SKIPs every method that is never exercised
>   5 of 7   survives BOTH:  tools_call · sep-2322-client-request-state ·
>            http-custom-headers · http-invalid-tool-headers · json-schema-ref-no-deref
>
>   A alone -> 6 of 7.   B alone -> 6 of 7.   TWO DIFFERENT SIXES, and a reader cannot
>   tell them apart from the figure. Neither may be quoted bare.
>   ```
>
>   **5 of 7 is the figure a consumer should read.** It is what survives **these two named
>   discounts** — it is **not** a demonstration that each of the five discriminates; showing that
>   would need a stricter null client, and none was built. 7 of 7 is a property of the adapter's
>   drive policy, not of this SDK; each 6 of 7 is true only of the one subtraction it names. The two
>   discounts are not nested — the null client fails `request-metadata`, so B does not contain A.
>   This gives the client leg **the same null-subtraction treatment the server leg's 29 already has**,
>   *in addition to* the drive-policy axis rather than instead of it; applying one treatment to one
>   leg and the other treatment to the other, in parallel bullets, was itself a claim wider than its
>   check (Round 3, below).
>
> **What the figures do not cover, stated because a zero is easy to read as a pass.**
> Two of this release's features earn **no scored credit at all, for two different reasons**:
> JSON Schema 2020-12 support (SEP-2106) **was measured** — 8/8 server, 9/9 client — and both
> scenarios are `not_scored`, so the work counts for nothing in any figure above; the **extensions
> negotiation surface** (SEP-2133) is not measured at all — no scenario in either direction touches
> it, so it leaves no row on the result sheet in any direction. Those are different kinds of zero
> and neither is evidence of anything.
>
> **Two scored passes sit over a SHOULD the referee recorded as unmet.**
> `sep-2164-resource-not-found` and `input-required-result-ignore-extra-params` each pass while
> carrying a WARNING raised against this implementation, and both are inside the 35. A SHOULD is not
> a MUST and the claim stands over them — but which verdict you read decides it, so it is said here
> rather than left inside the number.
>
> **Known limits a consumer will meet.**
> * **Multi Round-Trip Requests (SEP-2322) are implemented on `tools/call` only.** SEP-2322 makes
>   `InputRequiredResult` universal; a non-tool request that needs input does not get it.
> * **A JSON-RPC error carried on an HTTP 4xx is discarded by the client**, which makes `-32020`
>   header-mismatch recovery unreachable over Streamable HTTP.
> * **No server-side `Mcp-Param-*` validation**, and trailing whitespace is not trimmed from
>   routing headers.
> * **`subscriptions/listen` is server-side, HTTP transport only.** No stdio support and no
>   client-side stream consumption.
> * **`server/discover` has no protocol-version gate**, and **`initialize` answers `-32022`** rather
>   than `-32601` with an HTTP 404. Both are deliberate, documented decisions on which the
>   conformance harness takes the other view.
> * **The HTTP/2 surface is a real, unconditional exposure**, not an unused protocol path: Bandit
>   sniffs the cleartext HTTP/2 prior-knowledge preface whenever HTTP/2 is enabled and this SDK
>   disables it nowhere, including its own port-8080 example. The `bandit` 1.12.1 floor hardens it.
> * **Content coding: the client sends `accept-encoding: identity`** and fails cleanly and
>   structurally on an unexpected `content-encoding`. RFC 9110 §12.5.3 permits a peer to send a
>   coded response regardless, so this is a **deliberate documented limit**, not an omission.
>
> **The referee moves and this claim does not.** Scenario **membership** is frozen by the
> requirement set; scenario **implementations and check ids are not**, and `alpha.11` will move.
> Concretely: `checkMcpNameHeader` is dormant today only because every alpha.11 fixture name happens
> to be header-safe — one non-safe fixture name in a later alpha turns this SDK's spec-correct
> encoding red with no change to its code. That is what "supporting evidence, not certification"
> means in practice, and it is why every figure above carries its harness version.

---

#### Two obligations the draft carries to Sprint 5's release ticket

1. **The published 1.x docs still carry the false claim — on all FOUR released versions, not one.**
   MES-19 removed it from the repo (see RAT-2 below), but **`v1.0.0`, `v1.0.1`, `v1.0.2` and
   `v1.1.0` are all on Hex carrying it** (measured, A2d — `git show <tag>:README.md` finds
   *"100% conformance … (Tier 1)"* at `:7` and *"Conformance tested — 30/30 scenarios, 40/40
   checks"* at `:16` in **each** of the four), and `README.md` is `main: "readme"`, so it is the
   HexDocs landing page of **every one** of them. Deleting lines from the repo **does not retract a
   published page**. Retracting or superseding those four published doc sets is a **named obligation
   on the release ticket**, and writing "the false claim has been removed" without that qualifier
   would itself be a claim wider than its check.
2. **A green `mix hex.audit` is not publish-blocking evidence on its own.** The whole-tree OSV
   cross-check with its positive control was run for this sprint on **MES-49** (RAT-5) against
   **today's** lock. A run today
   certifies today's lock and nothing else, so **Sprint 5 must re-run it against the final locked
   tree at publish**.

#### The draft, attacked. Six targets named in the plan before drafting, so easier ones could not be substituted.

| | Target | Verdict |
|---|---|---|
| a | "35 of 37" quoted anywhere without the other two axes | **cut** — all three axes appear in one bullet list; there is no sentence in which 35 stands alone |
| b | any sentence a reader could take as *"the conformance project tested us"* | **cut** — "Nobody has certified this SDK" is its own sentence, before any figure |
| c | any phrasing under which 2020-12 or extensions reads as harness-verified | **cut, and the two are deliberately not collapsed** — one was measured and counts for nothing, the other is not measured at all |
| d | "conformant" applied to MRTR, true only of `tools/call` | **cut** — MRTR appears only in *Known limits*, with the bound |
| e | any client claim without its `auth/*` denominator | **cut** — 8/32 is never written without "25 of the 32 are `auth/*`". **Amended twice, and both amendments are recorded rather than the row being silently rewritten.** *Round 2 (CR BLOCKING 1): the first draft quoted the core subset as **7/7**, the **as-driven** axis, and the fix published **6 of 7** on a drive-policy subtraction. Round 3 (PM, comment 24529): that 6 of 7 and MES-49's independently-derived 6 of 7 are **different sets** — the bullet now carries **both** subtractions by name and publishes **5 of 7** as what survives both. The row's own target was never the defect either time: it names a denominator problem, and neither amendment was one.* |
| f | **"conformance tested" as a bare phrase** | **cut — and this is the finding.** That exact phrase is in the README **today** (RAT-2) |

**Sentences cut rather than softened.** An unqualified headline figure was drafted and removed; there
is no "conformance tested" phrase and no Tier claim in the draft, because a tier is a claim about
*rate* and every rate here needs three axes to be true.

### RAT-2 — the false conformance claim that was shipping, and the bound on removing it

**This is the finding I did not expect to make while planning a ticket about drafting an honest
claim.** Adversarial item 1 says the claim wording is the only thing a stranger ever reads. A
stranger reading this package today read:

```text
README.md:7   **100% conformance** with the official MCP test suite (Tier 1).
README.md:14  - **Full protocol support** - initialization handshake, capability
                negotiation, notifications, pagination
README.md:16  - **Conformance tested** - 30/30 scenarios, 40/40 checks against the
                official MCP conformance suite
README.md:20  Implements MCP specification **2025-11-25**.
docs/architecture.md:7   - **Status**: Phase 7 Complete - 100% Conformance (Tier 1)
mix.exs:41               links "MCP Specification" -> .../specification/2025-11-25
```

Both `README.md` and `docs/architecture.md` are in the hex package's `files:` list (`mix.exs:46-47`)
and `README.md` is `main: "readme"` in `defp docs` (`mix.exs:51-53`) — **it is the HexDocs landing
page**. So the unqualified "100% conformance (Tier 1)" that ADR-003 forbids was not a risk being
drafted against; it was **the status quo, on the shelf, on the page a consumer lands on**. Against
the 2026-07-28 measurement it is false three times over: not 100%, not Tier 1, not that suite. Line
14 advertises an `initialize` handshake this revision **deletes**.

**The ruling (PM, RAT-2, sanctioned scope A9): removing a known-false claim is not publishing a new
one.** ADR-003 gives the release ticket ownership of *what we assert*; it does not oblige anyone to
preserve what has been measured to be false. The DoD's "drafted, not published" constrains the *new*
claim and says nothing about the old one.

Removed at this ticket: `README.md:7`, `:14` (reworded to the per-request context that replaced the
handshake), `:16`, `:20`, `docs/architecture.md:7`, the `mix.exs` package link, and — added at CR
round 2 — five stale-revision claims in `usage-rules.md`, which ships in `files:` **and** is a
HexDocs `extra`.
**CHANGELOG 1.x entries stay — history.** *The `:20` rewrite was incomplete on the first pass and was
finished after CR round 2 — see the CR round 2 section at the end of this entry.*

> **THE BOUND, and it is the class this sprint keeps catching.** **Four released versions are on Hex
> carrying that README** — `v1.0.0`, `v1.0.1`, `v1.0.2` and `v1.1.0` — and because `mix.exs` sets
> `main: "readme"`, that README is the HexDocs landing page of **each** of them. **Deleting the lines
> from the repo does not retract a published page.** MES-19's excision is **forward-looking only**;
> writing "the false claim has been removed" without that qualifier would be a claim wider than its
> check, in the ticket whose subject is claims wider than their checks. Retracting or superseding
> those four published doc sets is a **named obligation on Sprint 5's release ticket**, and it is in
> the claim draft above rather than in a footnote.
>
> *Corrected at CR round 2: this bound was first written as **v1.0.0 only**, which was itself
> narrower than the fact — the same error one direction down. Measured, not assumed:*
>
> ```text
> git show v1.0.0:README.md | grep -n "100% conformance\|Conformance tested"   -> :7, :16
> git show v1.0.1:README.md | grep -n "100% conformance\|Conformance tested"   -> :7, :16
> git show v1.0.2:README.md | grep -n "100% conformance\|Conformance tested"   -> :7, :16
> git show v1.1.0:README.md | grep -n "100% conformance\|Conformance tested"   -> :7, :16
> ```

*Eight tickets of this sprint were spent finding claims wider than their checks. The widest one was
on the front page of the package the whole time.*

### RAT-5 — the whole-tree OSV cross-check

Run, with its positive control, and **recorded in the MES-49 entry** under the heading
`### Part B — RAT-5, the whole-tree OSV cross-check, with its positive control`. See the
de-duplication note under *Item 1 and RAT-5* above for why one copy and not two. Sprint 5's
obligation to re-run it against the **final locked tree at publish** is carried in the claim draft's
obligation 2, and the unchanged gate-6 residual — **21 unvalidated of 26** — is restated in the gates
block below rather than left to a green.

### A2d — the empties, enumerated. Nothing is absorbed into a denominator.

**Adversarial item 6.** Anything that cannot be measured — no scenario exists, no adapter surface, a
harness limitation — is named and classified, negatives included. "Not run" absorbed silently into a
denominator is the failure mode the published claim cannot survive.

| class | count | enumerated |
|---|---|---|
| Client scored scenarios for the **authorization profile this release does not implement** | **25** | `auth/` + `metadata-default`, `metadata-var1`, `metadata-var2`, `metadata-var3`, `basic-cimd`, `scope-from-www-authenticate`, `scope-from-scopes-supported`, `scope-omitted-when-undefined`, `scope-step-up`, `scope-retry-limit`, `token-endpoint-auth-basic`, `token-endpoint-auth-post`, `token-endpoint-auth-none`, `pre-registration`, `resource-mismatch`, `offline-access-scope`, `offline-access-not-supported`, `authorization-server-migration`, `iss-supported`, `iss-not-advertised`, `iss-supported-missing`, `iss-wrong-issuer`, `iss-unexpected`, `iss-normalized`, `metadata-issuer-mismatch` |
| Client `not_scored` — `extension` | **6** | `auth/client-credentials-jwt`, `auth/client-credentials-basic`, `auth/enterprise-managed-authorization`, `auth/dpop`, `auth/dpop-nonce`, `auth/wif-jwt-bearer` |
| Client `not_scored` — `added-after-release` | **1** | `json-schema-2020-12-preservation` (9/9 SUCCESS, counts for nothing) |
| Server `not_scored` — `pending` | **3** | `json-schema-2020-12` (8/8), `http-header-validation` (9 S/3 F/2 W), `http-custom-header-server-validation` (4 S/6 F). **These are present in `requirements/2026-07-28.yaml:183-197` as `not_scored, reason: pending` — they are NOT "absent from the scored list".** Same conclusion, different mechanism; "run and reported, never counted" and "absent" are different claims about the same zero |
| Server `not_scored` — `extension` (tasks suite) | **10** | `tasks-lifecycle`, `-capability-negotiation`, `-wire-fields`, `-request-state-removal`, `-mrtr-input`, `-request-headers`, `-dispatch-and-envelope`, `-status-notifications`, `-required-task-error`, `-mrtr-composition` — 12 SUCCESS / 30 FAILURE / 1 SKIPPED |
| Scored **server** scenarios a **null implementation also passes** | **6** | `server-sse-multiple-streams`, `sep-2164-resource-not-found`, `input-required-result-missing-input-response`, `input-required-result-unsupported-methods`, `input-required-result-ignore-extra-params`, `input-required-result-validate-input`. Re-measured here, not inherited |
| Scored **client** scenarios a **null client also passes** — the subtrahend behind *5 of 7* | **2** | `auth/resource-mismatch`, `http-standard-headers`. Measured on **MES-49**, not here: a client whose entire body is `exit 0` scores 2/32. Only `http-standard-headers` is inside the core 7, which is what makes it discount **B** |
| Core client scenarios discounted for **drive policy** rather than for scoring | **1** | `request-metadata` — discount **A**. It passes as driven and goes red under the counterfactual arm that stops at a failed `MCP.Client.connect/1` (MES-24, run by CODE_REVIEWER). Disjoint from the row above, which is why 5 of 7 and not 6 |
| Register rows that leave **no result-file row at all**, in either direction | **4** | J1 / CG2 (extensions negotiation), CG3 (client `subscriptions/listen` — no scenario in the client list *or* its `not_scored` block), **E2 (new with this ticket)**, CG5/CG6 (client cache-honouring, trace context) |
| Register rows marked implemented on evidence that **cannot go red** | **10** | C2, D3, F1, F4, G1, I1, I2, J1, CG2, CG4 — see the walk |
| Scenarios in the null-control run that produced **no `checks.json` at all** | **1** | `tasks-capability-negotiation` aborted with `JsonRpcError: Method not found` before any check. `not_scored`, so it touches no figure — named because a missing artefact and a passing one are not the same absence |
| Server-leg `--timeout` headroom | **n/a** | **the flag does not exist on `conformance server`.** Named rather than silently omitted; the server leg spawns no `mix` per scenario, so it is not exposed to the contention the flag is for |

### Gates — all six, individually

Run **after the rebase onto `main` at `bc130a8`**, in this seat's own `git worktree`
(`/tmp/cc-mes19-gates`, detached at the rebased tip) and never in the shared clone — a
concurrent seat can move the shared clone's branch mid-run, which is exactly what F-11 in the
MES-49 entry caught. A rebase is a different tree, so the gates are re-run even though CR asked
for none, and then run once more on the branch tip as handed back — the figures below are that
final run, not the mid-rebase one.

```text
mix hex --version                     Hex v2.5.1  (>= the 2.5.1 floor; checked FIRST because the
                                                   container has been observed resetting to 2.5.0)
1. mix format --check-formatted       PASS  rc=0
2. mix compile --warnings-as-errors   PASS  rc=0
3. mix credo                          PASS  rc=0 — 1107 mods/funs, no issues, 121 files
4. mix dialyzer                       PASS  rc=0 — Total errors: 0, Skipped: 0
5. mix test                           PASS  rc=0 — 13 doctests, 566 tests, 0 failures
                                      + 20-seed sweep, 20/20 green, WITH A CONTROL THAT FIRED
6a. baseline-lock sentinel @ d697093  PASS — 22 of 22 known advisory ids present
                                      + negative control: FIRED (7 missing when bandit's rows
                                        are stripped from the captured output)
6b. mix hex.audit                     PASS  rc=0 — "No retired or security advisory packages found"
```

**566 is the predicted number, not a discovered one.** The PM predicted 566 before the run — 558 on
MES-49, which has no E2, plus E2's 8 — and 566 is what ran. Stated because a figure that matches a
prediction made in advance is worth more than the same figure quoted after the fact.

**Gate 5's sweep has a control, because 20 greens from a harness that cannot go red are 20 pieces of
nothing.** Both traps the PM named were checked by construction rather than by care:

```text
CONTROL ARM (must go RED or the sweep is void):
  MIX_ENV=dev mix test --seed 1   ->  rc=1  RED
  "MCP.Test.ExtrasStruct.__struct__/1 is undefined"
  (elixirc_paths drops test/support outside :test, so the suite cannot compile)

The rc-capture shape used throughout, and the one it avoids:
  out=$(cmd 2>&1); rc=$?      <- rc of cmd            USED
  cmd 2>&1 | tail -1; rc=$?   <- rc of TAIL, always 0  NOT USED
```

The control fires, so a red seed would have been reported red. Seeds: 0, 1, 7, 42, 99, 137, 256,
512, 1024, 2718, 3141, 4096, 5150, 6180, 7777, 8191, 9001, 12345, 31337, 65535 — **20 arms, 20
green, 566 tests each.** And per the standing bound: a clean sweep is **corroboration, not proof**;
the evidence for E2 is the mechanism plus item 2's mutation arm, not the sweep.

**Gate 6a's negative control fires too**, and it is the same shape: the sentinel is a "did the local
cache answer" check, so a sentinel that cannot report a miss proves nothing. Stripping `bandit`'s
seven ids from the captured baseline output makes 6a report **7 missing of 22** and fail — so the
22-of-22 above is a positive result rather than an unfalsifiable one.

**The gate-6 residual is unchanged and is said out loud rather than letting a green stand alone:
21 unvalidated of 26.** No dependency moved on this branch — `mix.lock` is untouched — so the
baseline-lock sentinel still validates advisory rows only for the five packages that have ever
carried an advisory in this tree (`bandit`, `hpax`, `mint`, `plug`, `req`), and the other 21,
including the runtime deps `finch` and `thousand_island`, are covered not by gate 6 but by the live
whole-tree OSV cross-check in the MES-49 entry.

**Gate 1 and gate 2 are blind to `conformance/`** — `.formatter.exs` inputs are `{config,lib,test}/**`
and `elixirc_paths` is `["lib"]` (`mix.exs:34-35`). That is **MES-46** and is not closed here. This
ticket changed nothing under `conformance/`, so no manual arm was needed.

**How gate 5 differs from MES-24, and it is worth stating.** On both MES-24 legs gate 5 was a
*positive control* that discriminated nothing about the work — no `lib/` change, no `test/` change.
Here it is **real evidence**: item 2 puts its change in `lib/` and its test in `test/`, and the
mutation arm shows the test failing when the mechanism is disabled. The other 558 tests remain the
positive control they have always been, and are labelled as such.

### What this ticket found, and the tripwire

**The tripwire did not trip.** The PM grew this ticket at ratification — four deliverables plus the
README excision, the ADR amendment, the OSV run and a 36-row walk — and said so, with an A1 escalation
standing by if it stopped converging or if the walk changed what the claim could say. Neither
happened: the walk sharpened the claim (ten unfalsifiable rows, up from three named in advance) but
changed nothing it was able to assert, and every deliverable landed. **Recorded because a tripwire
that is never reported on is not a control.**

**Six things this ticket found that reading would not have.**

1. **The false claim was already shipping.** Found while planning how to draft an honest one. The
   widest claim-wider-than-its-check in the sprint was the front page of the package.
2. **My own E2 fixture would have been a green that cannot go red** — the exact trap the plan named
   one paragraph earlier. An unchanged ETS `:set` reads back in one order every time; only
   differently-*populated* registries diverge. Measured before a line was written.
3. **Two different numbers were both called "6 of 7"** — this branch's drive-policy figure and
   MES-49's null-passable figure subtract *different* scenarios from the same seven. The honest
   figure is **5 of 7**, and it was reachable only by reading two units' evidence side by side
   (Round 3). Neither unit could have found it alone, and it is recorded as a property of the
   mediation rather than as anyone's miss.
4. **A misconfigured client run is indistinguishable from a bad implementation** — 2/32, a full
   39-scenario sheet, 39 saved artefacts, no error. Discovered by making the mistake; MES-49 later
   reproduced the same census on purpose with a null client.
5. **The false claim ships on FOUR released versions, not one** — `v1.0.0`, `v1.0.1`, `v1.0.2`,
   `v1.1.0`, each with its own HexDocs landing page. **The one error this sprint found that ran the
   other way**: a claim *narrower* than the fact, which understated a live Sprint 5 obligation by a
   factor of four. Found only because correcting `README.md` forced the question *which* published
   line implements 2025-11-25.
6. **E2 changes the wire and moves the score by zero checks** — observed in the harness's own
   artefact (`tools/list` unsorted → sorted, every verdict identical). "Added code, number went up"
   was not available, and that is stated rather than implied.

**Two findings that were on this list are no longer on it, and that is de-duplication rather than
retraction.** `--timeout` does not exist on `conformance server` (F-10 is dischargeable on one leg),
and MES-24's not-scored client census was computed over a **stale artefact** (settled by running the
leg four times, not by re-reading it; no scored figure moves). Both were first recorded on this
branch and both are now in the MES-49 entry, which is the surviving record of the measurement — see
*Item 1 and RAT-5* above.

**Sprint 4 exit criterion: MET.** 36 of 36 register rows walked and marked; every outstanding item
owned by a named ticket; **thirteen raised, none scheduled**, said in those words because the
difference is a different promise to a consumer.

### CR round 2 — two BLOCKING wording defects, and both were in what the claim SAYS

CODE_REVIEWER reviewed `9d662ab` and blocked on two defects, neither of them in the diff's code. The
PM had told CR not to re-run the six gates and to spend the budget on the wording; **both findings
came from the wording, which is the outcome that instruction was aiming at.** The amendment below is
docs-only — no `lib/`, `test/`, `mix.exs` or `mix.lock` change — and CR asked for no gate re-run.

**BLOCKING 1 — the draft widened the client figure back to 7/7.** The client bullet said *"Of the 7
remaining core scenarios, **7 pass**"*. That is the **as-driven** axis. It contradicted this same
the pre-run prediction section of this same entry, and the measurement record, both of which
preserve MES-24's three-axis distinction: **8/32** harness-reported, **7/32** driven-and-passing, and
a core figure under a consumer-realistic drive. *(Cited by section rather than by the line numbers
this paragraph originally carried: the de-duplication and the rebase both moved them, which is the
argument for never citing an append-only log by line.)* The attack table's row (e) then certified the wrong shape by saying "the
7/7 carries its own denominator" — a denominator is not the defect; **the axis is**.

**How the defect got in, because that is the reusable part.** My own plan named target (e) as *"any
client claim without its `auth/*` denominator"*, and I checked the draft against exactly that. The
draft passes target (e): 8/32 never appears without the 25. **The target was too narrow.** 6/7 is not
a denominator problem — 7/7 and 6/7 share a denominator — it is the drive-policy axis, which
MES-24's BLOCKING 1 established and which my attack list did not name. **A pre-named attack list
bounds substitution; it does not bound blindness**, and this is a measured instance of the
difference.

Fixed in the client bullet of the draft above: all three client axes appeared in the one bullet,
each subtraction with its reason (`auth/resource-mismatch` is a purely negative check with nothing
behind it; `request-metadata` survives **only** because the adapter carries on past a failed
`MCP.Client.connect/1` — the counterfactual that licenses that *only* is cited in Round 3), and the
bullet said which figure a consumer should read: **6 of 7**.

**That fix was itself incomplete, and Round 3 below supersedes this paragraph.** The 6 of 7 it
published is the drive-policy set; MES-49's null-client control produces a *different* 6 of 7 by
subtracting a different scenario, and the figure that survives both is **5 of 7**. What stands from
round 2 is the diagnosis — the axis, not the denominator, was the defect — and the diagnosis is what
round 3 extended. Row (e) of the attack table records both amendments.

**BLOCKING 2 — `README.md` still carried an unqualified 2025-11-25 implementation claim.** RAT-2's
excision reworded `README.md:20` to mention the unreleased 2.0.0 line but left the *leading* sentence
unqualified — `README.md:17` read **"Implements MCP specification 2025-11-25."** and only then said
2.0.0 targets 2026-07-28 — and `README.md:409` still linked an **unqualified** *MCP Specification
(2025-11-25)* while `mix.exs:43` had already been moved to 2026-07-28. On the 2.0.0 branch that is a
claim the draft itself contradicts under `#### DRAFT — MCP conformance statement for
mcp_elixir_sdk 2.0.0`, in its **Scope** paragraph (*"2025-11-25 is not supported on either side"*).

**This is the same class RAT-2 is about, one revision along.** RAT-2 caught *100% conformance (Tier
1)*; what it left behind was a wrong-revision implementation claim in the same paragraph. Fixed: the
Protocol Version section now leads with the 2.0.0 line implementing **2026-07-28**, states plainly
that 2025-11-25 is **not** supported and fails fast with `-32022` rather than negotiating down, and
attributes 2025-11-25 to the **published 1.x line** (latest `1.1.0`); the Documentation list now
carries **both** specification links, each labelled with the line it belongs to.

**A third defect, found while fixing the second, and it runs the other way.** Writing the corrected
Protocol Version section forced me to say *which* published line implements 2025-11-25 — so I checked
what is actually on Hex instead of reusing the phrase already in the entry. **Four released versions
carry the false claim, not one.** RAT-2's bound and the claim draft's obligation 1 both said
*v1.0.0*; `v1.0.0`, `v1.0.1`, `v1.0.2` and `v1.1.0` each carry *"100% conformance … (Tier 1)"* at
`README.md:7` and *"Conformance tested — 30/30 scenarios, 40/40 checks"* at `:16`, and `mix.exs` sets
`main: "readme"`, so each has its own HexDocs landing page carrying it. **This one is a claim
NARROWER than the fact** — the mirror image of everything else this sprint caught, and it understates
a live obligation on Sprint 5 by a factor of four. Both statements are corrected above, with the four
`git show <tag>:README.md` greps recorded so the count is checkable rather than asserted.

**A fourth defect, in the third shipped doc — `usage-rules.md`, which nobody had looked at.** CR's
BLOCKING 2 named `README.md`. RAT-2's excision had covered `README.md`, `docs/architecture.md` and
`mix.exs`. **`mix.exs:46-47` ships a fourth consumer-visible file** — `usage-rules.md` — and
`defp docs` lists it as an `extra`, so it is on HexDocs too. It was **half-migrated**: `:245-246`,
`:251-252` and `:272-275` had been rewritten for 2026-07-28 (MES-18 even left a note in the text),
while five claims from the previous revision were untouched and one of them **contradicted a line
in the same file**:

| line | claim as it stood | why it is wrong on this line |
|---|---|---|
| `:8` | *"Protocol version: **2025-11-25**"* | the same defect CR blocked on in `README.md:17`, in a file that also ships; contradicted by `:245` in the same file |
| `:41` | *"You **must** call `connect/1` before any other operation. It performs the MCP initialization handshake"* | there is no `initialize` handshake at 2026-07-28, and the precondition is false — **measured**, below |
| `:54` | table row *"`connect/1` \| Initialize handshake (required first)"* | same, in the operations table |
| `:255` | gotcha 1, *"No operations work before the initialization handshake completes (except ping)"* | **measured false** |
| `:269` | *"IDs are unique per session"* | there is no session; `:245` says so eight lines earlier |

**The precondition was measured, not reasoned about** — a throwaway probe against the in-process
`BridgeTransport` pair, run and then deleted (it is not in the diff; the finding is):

```text
PROBE status-before                => :ready          # MCP.Client.start_link/1 alone
PROBE list_tools-without-connect   => {:ok, %{"tools" => [%{"name" => "echo", ...}], ...}}
```

`lib/mcp/client.ex:267` sets `status: :ready` in `init/1`, so `connect/1` gates nothing; its `@doc`
at `:139-141` already called itself a `server/discover` probe. **The code was migrated and the
usage rules were not.** The bounded claim is what is now written: *measured, `list_tools/1` succeeds
with no prior `connect/1`* — not the wider "no operation requires it", which one probe does not
support.

*Scope note, flagged rather than buried: CR asked for a narrow amendment on `README.md` and I
changed a second shipped doc. The reason is that fixing only `README.md` would have left the
identical wrong-revision claim one file over, on a page HexDocs also publishes — which is the exact
argument CR made about `README.md:409`. **PM: this is mine to own if you judge it out of scope.***

**The bound itself is unchanged and worth restating.** This is still a repo-only correction: neither
RAT-2 nor this amendment retracts a published page. That obligation stays named on Sprint 5's release
ticket, in the claim draft above — now sized at four doc sets.

### Round 3 — the PM's correction contract (comment 24529): two different sixes, and the honest figure is 5 of 7

**This is the important one, and neither unit could have seen it alone.** Round 2 fixed the 7/7 axis
by subtracting `request-metadata` on a **drive-policy** argument and published **6 of 7**. On a
different branch, on a sub-task this seat had already handed off, MES-49 built the **null client**
this entry never had — a file whose entire body is `#!/bin/sh` and `exit 0`, handed the mock server's
URL and doing nothing with it — and subtracted `http-standard-headers` on a **null-passable**
argument, arriving independently at **6 of 7**.

**Two different sets, the same name.** The PM verified from both units' saved artefacts that the two
discounted scenarios are distinct, that both sit inside the core 7, and that they compose:

```text
core (non-auth/*) scenarios, all 7:
  tools_call   request-metadata   sep-2322-client-request-state   http-standard-headers
  http-custom-headers   http-invalid-tool-headers   json-schema-ref-no-deref

DISCOUNT A (drive policy)   this branch, round 2   -> removes request-metadata
DISCOUNT B (null-passable)  MES-49's control       -> removes http-standard-headers

survives A only : 6 of 7      <- what round 2 published
survives B only : 6 of 7      <- what MES-49 measured
survives BOTH   : 5 of 7   -> tools_call, sep-2322-client-request-state,
                              http-custom-headers, http-invalid-tool-headers,
                              json-schema-ref-no-deref
```

The two are **independent, not nested**: the null client scores 2/32 and passes exactly
`auth/resource-mismatch` and `http-standard-headers`, so it **fails** `request-metadata`. A is
therefore not a special case of B, and the composition is legal.

**Why this is a defect and not a rounding argument.** The round-2 draft said *"6 of 7 is the figure a
consumer should read"*, and three bullets above it the server leg's **29** is a **null-subtraction**
figure. So the draft applied null-subtraction to the server and drive-policy to the client, in
parallel bullets, in the same voice — as though they were the same treatment. **That is a claim
stated wider than its check, one level up from the one CR caught, and it was inside the fix for the
one CR caught.** The client bullet now carries both subtractions by name, publishes **5 of 7** as
what survives both, keeps 7 of 7 and each 6 of 7 visible and labelled with *which* scenario it drops,
and gives the client leg the same null-subtraction treatment the server leg already had — in addition
to the drive-policy axis, not instead of it. **No bare "6 of 7" remains in the draft.**

#### How it was found, and it is a different mechanism from round 2's

Round 2's lesson was: **a pre-named attack list bounds substitution; it does not bound blindness.**
This is its **second instance inside one hour** — and the difference worth recording is *how* the
second one surfaced.

**Correction, round 4 (CR BLOCKING 2, upheld by the PM against the PM's own instruction).** What
stood here said *neither unit could have found it by re-reading its own evidence*, and that MES-49
did not have this branch's drive-policy analysis because that analysis was written in round 2, after
MES-49 was handed off. **That was written to the PM's contract 24529 item 2 and it is false.** CR
attacked it, the PM checked CR's citations rather than accepting them, and so did this seat. The
drive-policy discount was **already in this same file, in MES-24's own entry, on `main`, before
MES-49's entry was written**:

```text
docs/sprint_4_issues.md:3114        "the `request-metadata` 8/8 is contingent on a DRIVE POLICY"
docs/sprint_4_issues.md:3294        heading: "...core is 6/7 under a consumer-realistic drive"
docs/sprint_4_issues.md:3272-3300   the mechanism, with CR's counterfactual arm
docs/sprint_4_issues.md:3374-3393   the per-scenario table: request-metadata -> "PARTLY"

git log main -- docs/sprint_4_issues.md
  7480f2f  08-20 07:29  [MES-24]   <- the entry above lands on main
  bc130a8  08-20 09:41  [MES-49]   <- MES-49's entry, written after it
```

The heading at `:3294` states Discount A's conclusion — *6/7* — in as many words, two hours before
MES-49's entry. So the record is this:

- **The null-client half (Discount B) was genuinely local.** It did not exist as evidence anywhere
  until MES-49 built and ran the `exit 0` control on another branch; no amount of re-reading would
  have produced it.
- **The drive-policy half (Discount A) was already recorded and simply not cross-read.** It was on
  `main`, in this file, under a heading that names the figure. This branch's round-2 write-up was
  new prose over an old fact, not a new finding.

**Those two halves want different fixes and collapsing them flattered everyone, including this
seat.** Locality argues for the mediation — a split that makes work tractable also makes each half's
evidence local, and a cross-read is the only thing that sees between the halves. An unread record
argues something less comfortable and not fixable by mediation: **`docs/sprint_4_issues.md` is
growing faster than anyone re-reads it**, so a fact can be correctly written down, survive review,
and still be absent from the next unit's reasoning. The first is a process property; the second is a
scale problem, and this file is now 5.4k lines.

**It was still found by cross-reading two units' evidence rather than by either unit auditing
itself** — that part holds. What does not hold is the exoneration attached to it. Recorded here in
the shape CR forced, not the shape the PM first asked for; the PM has said so on the ticket
(comment 24581 item 2) and asked explicitly that it not be softened back.

#### The word "only", checked rather than assumed (the PM's one open question)

The draft says `request-metadata` passes **only** because the adapter carries on driving after
`MCP.Client.connect/1` has returned an error. The PM took the mechanism as established from MES-24's
lineage but flagged that *only* is doing real work in a consumer-facing sentence: support it or
weaken it. **It is supported by a counterfactual arm that was actually run**, not by reading
`drive/2`. Under the heading `### Finding (BLOCKING 1, CR): that 8/8 is manufactured by the DRIVE
POLICY, not only by the SDK` in the MES-24 entry of this file:

```text
SUBJECT (adapter as committed)      8 checks, 8 SUCCESS             -> OVERALL: PASSED
CONTROL (stop when connect errors)  7 SUCCESS + 1 WARNING           -> OVERALL: FAILED
Same SDK, same commit, same fixture.   (arm run by CODE_REVIEWER on MES-24, not re-run here)
```

Remove the carry-on and the scenario goes red. That is what licenses *only*, and the bound is stated
with it rather than left implicit: **this fixture, at `@modelcontextprotocol/conformance@0.2.0-alpha.11`**
— the same pre-release caveat every other figure in the draft carries, and a later alpha may
re-implement the fixture. Kept at full strength, because the falsifier exists and was run; not
widened past the arm that supports it.

#### The scope questions the PM ruled, recorded with their outcomes

| raised in round 2 | ruling (comment 24529) |
|---|---|
| `usage-rules.md` amended beyond CR's `README.md` ask | **ALLOWED — kept.** The PM checked rather than took it: `mix.exs:47` ships it in `files:` and `:58` lists it as a HexDocs `extra` under `groups_for_extras`, so it is consumer-visible on exactly the same footing as `README.md` and RAT-2's bound reaches it. Fixing only `README.md` would have relocated CR's own defect one file over |
| no CHANGELOG entry for the claim excision | **OMISSION UPHELD — do not add one.** RAT-2 licenses *removing* a false claim, not publishing a new sentence about our conformance posture; ADR-003 sub-decision 6 routes that wording to Sprint 5's release ticket |
| the false claim ships on **four** released versions, not one | **ACCEPTED**, and verified independently by the PM: `v1.0.0`, `v1.0.1`, `v1.0.2` and `v1.1.0` each carry both lines in their own README. Four published HexDocs landing pages, not one. The four `git show <tag>:README.md` greps stay in the record so the count is checkable rather than asserted |
| the same stale claim in `docs/prd.md`, `docs/onboarding.md`, `docs/implementation-plan.md` | **OUT OF SCOPE here, and not this seat's to raise.** Repo-internal: not in `mix.exs` `files:`, not HexDocs extras, so RAT-2's consumer-visible bound does not reach them. Still false, and a contributor reads them — **the PM raises the ticket**. Named rather than left |

Also out of scope by the same contract and stated so the absences are not mistaken for coverage: no
code; no re-run of either conformance leg (MES-49 ran them twice and the PM re-adjudicated both from
artefacts); no new controls — including the stricter null client that would be needed to discount the
remaining five, which is **not** built here; no ADR edits beyond `45054d1`. **MES-50** (shared-clone
concurrency) and **MES-51** (artefact provenance) are the PM's and are raised.

#### Rebase and de-duplication, as executed

```text
git diff 498f7b1 b4c2f9c            -> empty  (re-verified immediately before the drop)
git rebase --onto main 498f7b1 MES-19

498f7b1  Pre-run prediction              DROPPED — it is on main as MES-49's b4c2f9c
07a8b26 -> a909b1c  E2 (MES-48)          clean
45054d1 -> 6a915d7  RAT-2 + ADR (MES-47) clean
9d662ab -> bf2ef39  the big entry        conflict, resolved
d158e68 -> c0c542c  CR round 2           conflict, resolved
d357bc4 -> e3044bd  round 3              conflict, resolved   <- the REBASED tip; this is the
                                                                 one the content check below
                                                                 compares against d357bc4

then, on top of the rebase (no further rebase — nothing to rebase onto):
e3044bd -> f62eb9c  round-3 write-up appended after the rebase. Docs only,
                    +95/-14 in docs/sprint_4_issues.md.  f62eb9c IS the tip handed
                    to CR, and the tip the PM ran the merge gate on.
f62eb9c -> HEAD     round 4 (this section). Docs only.
```

**The row above used to stop at `e3044bd` and call it "this round"** (CR's non-blocking cleanup 2,
upheld). `e3044bd` was the intermediate content-check tip and `f62eb9c` the tip actually handed
back, so the table named a hash that was not the deliverable — the exact failure mode a provenance
table exists to prevent. Corrected rather than explained away.

**All three conflicts were the same conflict**, and it is worth naming because the shape recurs
whenever two branches append to one log: both branches append at the identical point in
`docs/sprint_4_issues.md`, so every hunk of mine landed on top of MES-49's entry rather than before
it. Resolved the same way each time — **MES-19's content first, MES-49's entry after it, so each
ticket's entry is contiguous** — and verified structurally rather than by eye: `git diff main --
docs/sprint_4_issues.md` for the first of the three is **639 insertions, 0 deletions**, i.e. a pure
insertion that removes nothing of MES-49's, and `c0c542c` reproduces `d158e68`'s stat exactly
(149 insertions / 28 deletions, same three files).

**But a matching diffstat is the weaker check, so it is not the one relied on.** The check that
settles it compares the *content*: extract everything from `## MES-19` to the `## MES-49` heading
out of the pre-rebase tip `d357bc4` and out of the rebased tip `e3044bd`, and diff the two. The
result is **byte-identical apart from two blank lines and the `---` separator** that now divides
this entry from MES-49's. Nothing in this entry was dropped, reordered or reworded by the conflict
resolutions. (The one place a diffstat *did* wobble — `e3044bd` reads 231/162 where `d357bc4` read
230/163 — is that blank line, and it is an artefact of how diff aligned an unchanged paragraph, not
a content change. The content check is what proves that; the stat could not have.)

`mix.exs` now carries `@version "2.0.0-dev.9"` **from main, untouched by this branch** — MES-49's
D4 bump. This ticket's bump is the PM's to write in the squash-merge.


### Round 4 — CR's three BLOCKINGs, all upheld by the PM, all fixed (contract 24581)

Docs only. No code, no conformance re-runs, no new instruments. One of the three (item 2) was a
defect in **the PM's own instruction**, and the correction is written against the PM rather than
around it — see *How it was found*, above, which is the fix for item 2 and is deliberately placed
in the section it corrects rather than appended here where it would read as an afterthought.

#### Item 1 — `README.md` instructed the 2025-11-25 handshake. The CLASS, enumerated (A2d)

RAT-2 has now been "complete" three times, and each round fixed exactly what was pointed at:
round 1 removed the Tier-1 claim; round 2 fixed the revision line and `:409` after CR found them;
round 4 fixes handshake instructions after CR found those. So this round does not fix the two hits
CR named — it **greps the whole class across every consumer-visible surface and adjudicates every
hit, keeps included**. The count is not the deliverable; the table is.

**Class terms grepped** (case-insensitive): `handshake`, `initiali[sz]`, `notifications/initialized`,
`session`, `Mcp-Session-Id`, `:waiting`, `:ready`, `Server not initialized`.

**Provenance of the one positive claim the replacement text makes.** The new blockquote asserts
`list_tools/1` works with no prior `connect/1`. That is **carried in, not re-measured this round**:
it was measured on this branch in round 2 with a throwaway probe (commit message of `c0c542c` —
*"client is `:ready` from `start_link/1`; `list_tools/1` returns `{:ok, …}` with no prior
`connect/1`"*), and it is corroborated structurally by `lib/mcp/client.ex:267`, where `init/1` sets
`status: :ready` before any request is sent. Everything else the replacement says is a **negative**
— what the line does not have — and each negative is stated in `lib/` at the sites enumerated in
row 17. Labelled rather than left to look like this round's measurement (A7).

**Surfaces grepped, and why exactly these.** The bound is the PM's own round-2 ruling test —
consumer-visible = shipped in `mix.exs` `files:` (`:47`) or a HexDocs `extra` (`:54-60`). That is
`README.md`, `usage-rules.md`, `CHANGELOG.md`, `docs/architecture.md`, `LICENSE`, `lib/`. Grepping
only the two files CR named would have repeated the instance-fixing this item exists to stop.

| # | Hit (pre-fix line) | Adjudication |
|---|---|---|
| 1 | `README.md:19` — "no `initialize` handshake and no session, and an old-shape request fails fast with `-32022`" | **KEEP.** Correct negative; this is the sentence the other two contradicted |
| 2 | `README.md:64` — `# Perform the initialization handshake` | **FIXED.** Now: optional `server/discover` probe, "discovery, not a precondition" |
| 3 | `README.md:121` — `# Connect and use the server` | **FIXED**, and CR did not name it. Not a handshake claim, but it tells a reader `connect/1` is a step before use, which is the same false precondition in softer words. Now: "Optional discovery probe (`server/discover`) — not a gate on the calls below" |
| 4 | `README.md:354-362` — the nine-line `> **Client handshake (Streamable HTTP).**` blockquote | **REPLACED.** It carried a MUST, an ordering, a header this revision does not have, `:waiting`/`:ready`, "Server not initialized", and "`MCP.Client.connect/1` performs this handshake for you". Replaced with the stateless model stated positively: what a request carries instead (`_meta` under `io.modelcontextprotocol/*`), `-32022` fails fast rather than negotiating down, no request depends on a previous one, and `connect/1` is discovery. A closing parenthetical points 1.x readers at `CHANGELOG.md` so the removal does not read as "the handshake never existed" |
| 5-11 | `usage-rules.md:8, 41, 245, 246, 255, 269, 273` | **KEEP, all seven.** Every one is already a correct negative or a correct statement of the stateless model (`:41` "discovery, not a precondition"; `:245` "There is **no `MCP-Session-Id`**"; `:255` "the client is `:ready` from `start_link/1`"). Round 2 fixed this file; this grep confirms it rather than assuming it |
| 12 | `CHANGELOG.md:10` — "no `initialize` handshake, no session" | **KEEP.** Correct negative, in the `[Unreleased] — 2.0.0` section |
| 13 | `CHANGELOG.md:102` — "no `Mcp-Session-Id`, no `Last-Event-ID` resumption" | **KEEP.** Correct negative, under `### Removed` |
| 14 | `CHANGELOG.md:159-161` — "documented the required client handshake ordering … stays `:waiting`" | **KEEP.** This is the `[1.1.0]` entry and it is a true statement about what 1.1.0 shipped. A changelog that rewrote its own history to match the current line would be the worse defect |
| 15 | `CHANGELOG.md:222` — "Initialization handshake and capability auto-detection" | **KEEP.** Under `## [0.1.0] - 2025-02-08` (`:213`), not `[1.0.0]` — checked rather than assumed. Same reason |
| 16 | `docs/architecture.md` — 33 in-class hits over 548 lines | **NOT FIXED, and named rather than left.** See below. This is the one adjudication in this table that is a judgement rather than a reading |
| 17 | `lib/**` — **42 hits**, counted not estimated | **36 KEEP, 6 NAMED across 3 files (not fixed — `lib/` is code, A9).** 36 + 6 = 42; the keeps split three ways. **28** are *correct negatives* stating the stateless model (`client.ex:6,141,819`, `dispatch.ex:5,7,8,66,135,419`, `connection.ex:9,10`, `plug.ex:6,29`, `streamable_http/client.ex:97,611`, `meta.ex:5,7`, `methods.ex:9`, `extensions.ex:13,24,25,31`, `discover.ex:5`, `config.ex:6`, `tool_context.ex:9,68,81`, `state_handle.ex:6`), and the rest are **live identifiers, not claims** — `methods.ex:7` `def initialize` and `dispatch.ex:131` still exist because the method name must be *recognised in order to be rejected* (`-32022`, `dispatch.ex:135`), `methods.ex:33`/`dispatch.ex:418` because `notifications/initialized` is *tolerated as a no-op*, `client.ex:213/267/349` because `:ready` is the client's own status atom and still real (**7** such). One is neither — `handler.ex:81` *"Initialize handler state"*, the ordinary English verb (28 + 7 + 1 = 36). **A grep cannot tell a token from a claim; that is why this column exists.** The three non-keeps: `messages/initialize.ex:1,3,8,51` (below), and `capabilities/server_capabilities.ex:3` + `capabilities/client_capabilities.ex:3`, both reading *"declared … during initialization"* — there is no initialization on this line; both are public modules and both ship to HexDocs |

**Item 16, stated at its real strength because it is the weakest cell in the table.**
`docs/architecture.md` ships in `mix.exs` `files:` and is a HexDocs extra under *Guides*, so it is
consumer-visible on the same footing as `README.md`. It still carries the 2025-11-25 model
throughout: `MCP-Session-Id: <sid>` and `MCP-Protocol-Version: 2025-11-25` in the transport diagram
(`:171-172`), an ETS session registry (`:171`, `:186`, `:202`), `DELETE → terminate session`
(`:169`, `:174`, `:182`), the `:waiting`/`:ready` state machine (`:286`, `:312`), and at `:205-209`
a *"clients MUST drive `initialize → notifications/initialized → tools/call`"* bullet that is
word-for-word the defect CR found in `README.md`.

**Why it is nevertheless not the same defect, and this is the argument to attack.** README asserted
2026-07-28 at `:19` and then instructed 2025-11-25 at `:354` **with nothing between them saying
which line the reader was in** — one page, two incompatible clients. `docs/architecture.md` declares
its scope in its own first eight lines — `**Version**: 1.0.2`, `**Protocol**: MCP 2025-11-25`, and
`**Status**: … Superseded by the unreleased 2.0.0 stateless-core rewrite` (that Status line is this
branch's own `6a915d7`). A reader is told which line the document describes before reading a word of
it, so its handshake prose is *consistent with its declared scope* rather than contradicting a claim
on the same page.

**That is a real distinction and it is also a convenient one, so: it does not make the document
correct.** A document that describes 1.0.2 while shipping inside 2.0.0's docs is a rewrite waiting
to be owned, and nobody owns it — it is not in this round's four items, it is not in A9's named
exclusions (`prd.md`, `onboarding.md`, `implementation-plan.md` → MES-52), and it is not
`README.md`. It is left **unfixed and named** rather than half-fixed: patching the four instruction
bullets while the diagrams above them still draw a session registry would produce inside
`architecture.md` exactly the two-readings-one-page defect this item is fixing in `README.md`.
**Routed to the PM: either widen MES-52 to cover it or raise it, before 2.0.0 publishes.** This seat
did not silently expand scope to a 548-line rewrite, and did not silently drop it either.

**Item 17's non-keeps, and the first is not a docs defect at all — it is a shipped module.**
`lib/mcp/protocol/messages/initialize.ex` defines `MCP.Protocol.Messages.Initialize` (plus nested
`Params` and `Result`) with the `@moduledoc` *"Message types for the MCP initialize handshake."*
The 2.0.0 line has no `initialize` handshake, and the module is **referenced nowhere in `lib/`** —
checked: `grep -rn "Messages.Initialize" lib/` outside its own file returns nothing. It is a public
module, so `ex_doc` publishes it: a consumer browsing 2.0.0's HexDocs finds documented message types
for a handshake this line rejects with `-32022`. Not fixed here, because deleting a public module is
**code** and a breaking removal that needs its own `CHANGELOG` `### Removed` entry — precisely what
this round's A9 excludes. **Named for the PM to route.** It is also the sharper form of the general
point: the grep for a *class of claim* found a hit that is not prose, and the fix for it is not an
edit.

The other two are one word each and could not be more different in cost:
`MCP.Protocol.Capabilities.ServerCapabilities` and `…ClientCapabilities` both open *"Capabilities
declared by an MCP {server,client} during initialization"* (`server_capabilities.ex:3`,
`client_capabilities.ex:3`). Both modules are load-bearing on this line — capabilities are still
declared, just **per request in `_meta`** rather than once at a handshake — so the modules stay and
only the sentence is wrong. Left unfixed **solely** because `lib/` is code and this round is docs
only; if the PM would rather have them in, they are a one-line change each and this seat will take
them in round 5 or in whatever ticket picks up the two above.

#### Item 3 — the caveat now travels with the figure

The draft said **"5 of 7 is the figure a consumer should read"** at `:4915`; the caveat that a
stricter null client would be needed to discount the remaining five, and was not built, sat at
`:5385-5388` in the round-3 audit prose — **outside the blockquote**. CR's point is the one that
matters: the blockquote is the part that gets lifted into a README at release and the audit prose is
not, so a caveat at that distance is a caveat that will not be published with the figure.

One sentence now sits inside the blockquote, immediately after the claim it bounds: *it is what
survives these two named discounts — it is not a demonstration that each of the five discriminates;
showing that would need a stricter null client, and none was built.* Short enough to survive being
quoted, which was the constraint. The audit-prose copy at `:5385-5388` stays where it is; the point
was that the caveat must travel with the figure, not that it must travel only there.

#### Item 4 — the two non-blocking cleanups

- **Trailing whitespace, `docs/sprint_4_issues.md:4789` (the CG5 register row).** Removed.
  `git diff --check bc130a8..HEAD` was exiting 2 on it. Worth one line of record: **gate 1 cannot
  catch this** — `.formatter.exs` `inputs:` is `{config,lib,test}/**`, so every markdown file in the
  repo is outside the formatter's reach. Another green that does not cover the thing, which is this
  ticket's recurring subject. `git diff --check main..HEAD` is run explicitly this round for that
  reason and is recorded with the gates below.
- **The rebase provenance table named a hash that was not the deliverable.** `:5402` read
  `d357bc4 -> e3044bd  this round` while the tip handed to CR was `f62eb9c`. `e3044bd` was the
  intermediate content-check tip — the round-3 write-up was appended on top of it, `+95/-14`, docs
  only — and both hashes belong in the table for different reasons: `e3044bd` is what the
  byte-identity content check compares against `d357bc4`, and `f62eb9c` is what was reviewed. The
  table now carries the full chain through to this round's commit.


#### Round 4 gates, run individually in this seat's own worktree (`/tmp/cc-mes19-r4`, detached at `f62eb9c`)

| Gate | Command | Result |
|---|---|---|
| — | `mix hex --version` | `Hex v2.5.1` — meets the ≥ 2.5.1 floor, checked before gate 6 rather than after |
| 1 | `mix format --check-formatted` | `rc=0` |
| 2 | `mix compile --warnings-as-errors` | `rc=0` |
| 3 | `mix credo` | `rc=0` — 1107 mods/funs, no issues |
| 4 | `mix dialyzer` | `rc=0` — `Total errors: 0, Skipped: 0, Unnecessary Skips: 0` |
| 5 | `mix test` | `rc=0` — **13 doctests, 566 tests, 0 failures**. 566 is the PM's pre-run prediction and this round changed no code, so it had to be 566; it was |
| 5+ | 20-seed sweep: `0 1 7 13 42 99 101 256 512 777 1024 2048 3141 4096 5555 8192 12345 31337 65535 99999` | all `rc=0`, all `566 tests, 0 failures` |
| 5c | **Control** — `MIX_ENV=dev mix test --seed 1` | **`rc=1`, RED as required** (`json_schema_2020_12_test.exs:358` fails to load in `dev`). Proves the harness captures a nonzero rc |
| 6a | baseline-lock sentinel at `d697093` | **PASS — all 22 known advisory ids present** |
| 6b | `mix hex.audit` | `rc=0` — "No retired or security advisory packages found" |
| + | `git diff --check main..HEAD` | `rc=0`. Added explicitly this round per the PM, because gate 1 is blind to markdown |

**The sweep's first attempt was written in the broken shape, and that is recorded rather than
quietly re-run.** The first pass captured the seed's result as `out=$(mix test --seed $s 2>&1 | tail
-2 | tr '\n' ' '); rc=$?` — and `$?` after a **pipeline** is the exit status of `tr`, which is
always 0. Twenty seeds reported `rc=0` and **every one of those twenty numbers was meaningless**:
that harness could not have reported a failure. It was re-run with the status taken directly from
`mix test` (redirecting to a file rather than piping), and only that second table is above. This is
the exact trap the PM named in comment 24577 item 2 — and it caught this seat one round after being
told about it, in the same file that argues a green is only as good as its instrument.

**What the sweep is worth, stated at its own bound (the PM's round-3 question, answer unchanged).**
The control fires for a *different reason* than the sweep exists to catch: it proves the rc capture
works, not that the suite would go red under an unlucky order. No test in this suite is known to be
order-sensitive, and nothing here was mutated to make one. So the 20 clean seeds are
**corroboration, not proof** — the standing bound, restated rather than assumed, and this round has
no code in it for a seed to reorder anyway.

---

## MES-49 — Confirm the measurement at the release commit; whole-tree OSV cross-check (2026-08-20)

Split out of MES-19 by the PM at 09:12 local (MES-19 comment 24514, MES-49 comment 24515), together
with **MES-48** (E2, deterministic `tools/list` ordering) and **MES-47** (the README excision). This
entry covers **only** MES-49's two halves: **Part A**, confirming the measurement at the release
commit `7480f2f`; and **Part B**, the whole-tree OSV cross-check that `CLAUDE.md` assigns here by
name (RAT-5, PM ruling — my reading that it belonged to Sprint 5 was overruled).

### Branch provenance, said plainly rather than implied

The PM asked which of the two paths was taken and why the answer matters. **Started fresh from
`7480f2f`**, not renamed: the pre-split `MES-19` branch carries MES-48's and MES-47's commits as
well, and renaming it would have put another sub-task's code on this sub-task's branch.

The pre-run prediction commit was **cherry-picked** (`498f7b1` → `b4c2f9c`) with its original author
date `07:56:30 UTC` preserved; only the subject key was rewritten `MES-19` → `MES-49`. `git diff
498f7b1 b4c2f9c` is **empty**, so the tree is byte-identical, and the prediction text itself is
anchored *outside git* on MES-19 comment **24509**, posted **07:43:31 UTC** — earlier than the commit
and earlier than every run in this entry. No rewrite on this branch could alter what was predicted.

**What this branch is, relative to the certified commit:** `git diff 7480f2f HEAD --stat` is *one
file*, `docs/sprint_4_issues.md`. **Zero code difference from the release commit.** That statement is
first-hand and is the one provenance claim I can make myself.

**The one I cannot, and do not.** C-1's content-identity between `7480f2f` and the tree MES-24
measured is **inherited on the PM's verification at the squash, not re-derived here** — the MES-24
branch was deleted at the squash, so there is nothing to diff against. "I checked" and "the PM
checked and I am relying on it" are different claims and only the second one is mine.

### F-11 — a concurrent seat switched the branch out from under a live measurement

**This is the ticket's most transferable finding and it was found by accident, which is the point.**

Partway through Part A, `git status` reported branch **`MES-19`** in a shell that had checked out
`MES-49` six minutes earlier. Nothing in this session issued that checkout. `git reflog --date=iso`:

```text
9d662ab HEAD@{2026-08-20 08:42:25 +0000}: checkout: moving from MES-49 to MES-19
b4c2f9c HEAD@{2026-08-20 08:40:09 +0000}: commit (amend): [MES-49] Pre-run prediction …
7480f2f HEAD@{2026-08-20 08:39:52 +0000}: checkout: moving from MES-19 to MES-49
```

`/tmp/emfa-seat-dispatch.log` names the cause:

```text
2026-08-20T08:37:40 MES CODE_CREATOR  ASSIGNED ticket=MES-49 epic=MES-23 engine=claude
2026-08-20T08:41:03 MES CODE_REVIEWER ASSIGNED ticket=MES-19 epic=MES-23 engine=codex
2026-08-20T08:41:03 MES CODE_REVIEWER PICKUP   ticket=MES-19
```

**The three seats share one clone** (`CLAUDE.md`, seat-based procedure). CODE_REVIEWER was dispatched
MES-19 at 08:41:03 and checked it out at 08:42:25 — into the working tree this seat was measuring
from. The two branches differ in `lib/mcp/server/{config,dispatch,handler}.ex`, i.e. **exactly the
server code the server leg exercises.**

**Why it is a measurement hazard and not just an annoyance.** A conformance run reads its subject off
the working tree. A branch switch mid-run yields a result sheet with **no record of which tree
produced it** — the artefacts carry a harness version, a requirement-set md5 and timestamps, and
**not one field naming the commit**. Had the switch landed 80 seconds earlier, this entry would have
certified `7480f2f` from figures produced partly on a different tree, and nothing in the artefacts
would have shown it. That is the ticket's own subject arriving as an accident against the ticket.

**Adjudicated by timestamp rather than by assumption.** Every arm's first and last check timestamp
was extracted from the saved `checks.json` files and compared against the switch at `08:42:25Z`:

| arm | first check | last check | vs switch | tree-dependent? |
|---|---|---|---|---|
| server (ours) | 08:41:04.116Z | 08:41:06.079Z | **79 s before** | yes |
| server null control | 08:41:29.829Z | 08:41:30.025Z | **55 s before** | no — a 25-line Python server |
| client (ours) | 08:42:10.118Z | 08:42:12.770Z | **12 s before** | yes |
| client null control | 08:43:05.516Z | 08:43:05.593Z | *after* | no — `/bin/sh; exit 0` |

So no arm is contaminated. **A 12-second margin is not a control, it is a near miss**, and reporting
it as "fine" would be the reasoning this sprint keeps catching.

**Fixed structurally, not by asking the other seat to wait.** The remaining work moved to a dedicated
`git worktree` at `/workspace/elixir_code/mcp_ex_MES49`, and the shared clone was left on `MES-19`
where CODE_REVIEWER expects it. Both seats then hold their own working tree over one object store,
and neither can move the other's. **Both legs were then re-run from the worktree** — see below.

**Raised for the working procedure, because it is not specific to this ticket.** `CLAUDE.md` says the
seats execute "strict-sequentially (one ticket in flight)"; here CODE_CREATOR held MES-49 while
CODE_REVIEWER held MES-19, in one clone, concurrently. Any seat running a build, a test sweep or a
conformance leg is exposed. This is a **PM/PO decision** and is not taken here; the options that
present themselves are a worktree per seat, a lock, or an actually-enforced single ticket in flight.

### Part A — the measurement at `7480f2f`, adjudicated

Every figure is pinned to `@modelcontextprotocol/conformance@**0.2.0-alpha.11**` (a **pre-release**),
requirement set `requirements/2026-07-28.yaml`, md5 **`d6eb2061b2d35c7c71a86059b08bb928`** — the same
md5 MES-24 recorded, checked rather than assumed. Adjudicated from saved `-o` artefacts under
`/tmp/mes49/`, never from terminal scrollback. Invocations, in full:

```text
SERVER  conformance server --url http://127.0.0.1:3001/mcp --requirements 2026-07-28 -o <dir>
        (adapter: mix run --no-halt conformance/server_adapter.exs 3001)
NULL    same invocation against http://127.0.0.1:3002/mcp — a 25-line Python server answering
        -32601 to every method, HTTP 200. No MCP behaviour at all.
CLIENT  conformance client --requirements 2026-07-28 --timeout 30000 -o <dir> \
          --command "cd <project> && mix run conformance/client_adapter.exs"
NULLC   same invocation, --command "/tmp/mes49/null_client.sh"  (a script whose body is `exit 0`)
```

The **cwd matters and is quoted with every figure**: MES-19's run recorded a control in which the
harness's own cwd was used, `mix run` could not start the adapter outside a Mix project, the harness
said nothing, and the sheet read **2/32** — indistinguishable from a poor implementation.

| axis | predicted | measured | verdict |
|---|---|---|---|
| server, FAILURE-only (`--requirements` exit rule) | 35/37 | **35/37** | CONFIRMED |
| server, warnings-also-fail | 33/37 | **33/37** | CONFIRMED |
| server, scored check census | 98 S / 19 F / 2 W / 0 SKIPPED | **98 / 19 / 2 / 0** | CONFIRMED |
| the 19 FAILUREs, scenario split | `server-stateless` 13 S/17 F, `input-required-result-non-tool-request` 0 S/2 F | **identical** | CONFIRMED |
| the 2 WARNINGs | `sep-2164-data-uri`, `sep-2322-ignore-unexpected-params` | **identical** | CONFIRMED |
| null control, FAILURE-only | 6/37 | **6/37** | CONFIRMED |
| null control, warnings-also-fail | 3/37 | **3/37** | CONFIRMED |
| null ⊆ ours (what makes the subtraction legal) | superset | **holds — 0 null passes outside our 35** | CONFIRMED |
| discriminating (35 − 6) | 29/37 | **29/37** | CONFIRMED |
| client, harness-reported scored | 8/32 | **8/32** | CONFIRMED |
| client, driven-and-passing | 7/32 | **7/32** | CONFIRMED |
| client, core (non-`auth/*`) | 6 of 7 | **6 of 7** | CONFIRMED — *by a different mechanism than predicted; see below* |
| client, scored check census | — | **57 S / 46 F / 2 SKIPPED / 1 INFO / 0 WARNING** | recorded |
| client, WARNINGs anywhere | 0 | **0 across all 39 saved scenarios** | CONFIRMED |
| **client, ALL-scenario check census** | **57 S / 61 F / 8 SKIPPED / 1 INFO** | **66 S / 59 F / 2 SKIPPED / 1 INFO** | **REFUTED** |

**Delta against MES-24: ZERO on every scored axis — and that is a self-consistency check, not a
measure of progress.** The tree is content-identical and no dependency moved, so a non-zero scored
delta would have meant something moved that should not have. **"What moved" has the honest answer
"nothing, and nothing could have."**

#### Both legs were run twice, and the second run is the one that certifies

Not for confidence in the number — for provenance. Run 1 executed in the shared clone before the
branch switch; run 2 executed in the isolated worktree, where the branch is `MES-49` throughout and
no other seat can move it. Compared **check-by-check**, not summary-to-summary:

```text
SERVER: run1 (50 scenarios) vs run2-in-worktree (50) -> IDENTICAL on every (check-id, status) pair
CLIENT: run1 (39 scenarios) vs run2-in-worktree (39) -> IDENTICAL on every (check-id, status) pair
```

A repeat that agrees is also the answer to "is any of this flaky": **it is not**, at n=2 per leg on
top of MES-19's four client repeats.

#### The refuted row, at full strength, and it is not the SDK

The predicted all-scenario client census was **inherited from MES-24's entry**, which recorded it
across *"33 scenarios"*. The artefact set holds **39** `checks.json` (8 top-level + 31 under `auth/`),
and the run contradicts the figure. MES-19 tested the two hypotheses that fit — a stale artefact
versus a starved scenario — by running the client leg four times; all four gave
`json-schema-2020-12-preservation` **9/9 SUCCESS** and byte-identical censuses, so the scenario is
not flaky and the **stale-artefact** explanation stands. **Both runs here reproduce 9/9 SUCCESS and
66/59/2/1, making it six independent confirmations.** The `-o` directory MES-24 censused was not the
run MES-24 reported.

**What it touches: no scored figure.** 8/32, 7/32, 6/7, 35/37, 33/37 and 29/37 are all unchanged, and
`json-schema-2020-12-preservation` is `added-after-release`, i.e. never scored. It is a defect in
MES-24's reporting of a *not-scored* census, found by running the thing rather than re-reading it.

#### A control the prediction implied but never defined: the null CLIENT

The server leg has had a null control since MES-13. The client leg has not, and my own prediction
line — *"6 / 7 core (non-`auth/*`), under a consumer-realistic drive"* — was not operationally
defined: it asserted that one of the seven core passes was worth less than the others without saying
how anyone would tell. **Built and run here** as `--command "/tmp/mes49/null_client.sh"`, whose
entire body is a `#!/bin/sh` shebang and `exit 0`: it is handed the mock server's URL and does
nothing with it. No MCP SDK, no HTTP request of any kind, and exit 0 so the harness's exitCode
reducer cannot be the thing that fails it.

```text
NULL CLIENT scored pass: 2/32  ->  auth/resource-mismatch, http-standard-headers
null ⊆ ours: EMPTY difference -> superset holds, so the subtraction is legal on this leg too
client discriminating = 8 - 2 = 6 / 32
core (non-auth/*) scored passes            : 7 of 7
core the NULL CLIENT also passes           : http-standard-headers
core DISCRIMINATING                        : 6 of 7
```

**The figure 6/7 is confirmed and the reasoning behind it was wrong.** The prediction leaned on the
adapter's own moduledoc note that a raw `:httpc` client with no MCP SDK scores 11/11 on
`http-invalid-tool-headers` — so I expected *that* to be the non-discriminating one. It is not:
`http-invalid-tool-headers` **is** discriminating here (the null client fails it), and the
non-discriminating core scenario is **`http-standard-headers`**, which pushes SKIPPED for any method
never exercised and therefore passes a client that does nothing at all. **A right number reached by
wrong reasoning is a finding, not a confirmation**, and it is recorded as one.

**And a control that closes MES-19's accidental one by construction.** The null client's
all-scenario census is **13 S / 83 F / 17 SKIPPED / 1 INFO, scored 2/32** — *identical* to the census
MES-19 recorded for its misconfigured run whose adapter never started. So the two are not merely
similar: **a run whose adapter never starts is indistinguishable, check for check, from having no
client implementation at all.** MES-19 found that by accident; it is now demonstrated on purpose.

#### `--timeout`: pinned where it exists, and named where it does not

MES-24's **F-10** instructs this ticket to pin `--timeout` and record the headroom. Read from the
CLI's own `--help` rather than assumed:

```text
conformance client --help  ->  --timeout <ms>   Timeout in milliseconds (default: "30000")
conformance server --help  ->  (no --timeout option exists)
```

So F-10 is dischargeable on **one leg only**, and the reason the other does not need it is
structural, not an omission: the server leg drives one already-running server over HTTP and spawns no
`mix` per scenario, so it is not exposed to the `_build` contention F-10 is about.

Client leg, pinned at `--timeout 30000` (the same value as the default — pinned so that it is *a
margin somebody set*, which is F-10's whole point):

| quantity | measured | headroom vs the 30 s pin |
|---|---|---|
| whole-leg wall clock | 5.420 s (run 1) / 5.705 s (run 2) | ~5× |
| check-timestamp span across the parallel suite | 2.652 s | **11×** |
| widest single-scenario check span | 0.029 s (`http-standard-headers`) | **~1034×** |

**Timeout-shaped failures: zero, and that was checked rather than assumed.** Every FAILURE in all
four arms was scanned for `timed out` / `timeout` / `ETIMEDOUT` / `ECONNREFUSED` / `EADDR`: **0
matches in all three saved arms, and 0 in the three run logs**, so no serial cross-check was
triggered. A first, deliberately over-broad scan produced 10 apparent hits; each was read rather than
counted, and every one was a check whose *own text* contains "not"/"could not" — e.g.
`sep-2663-tasks-get-status-working`, *"Not testable: no task was created by the preceding step"*.
**Recorded because a pattern that over-matches and gets counted rather than read is exactly how a
false clean bill is issued.**

#### C-2 — there is no comparable baseline, and this report says so

MES-13 measured against the **stable** harness `0.1.16`, whose 2026-07-28 denominator is **zero**;
its client figure was 1 passed / 55 failed at the **old** revision, and the single pass was the
out-of-scope `auth/resource-mismatch`. **A delta against an empty denominator is not a delta**, and
quoting "0 → 35" would be a manufactured movement. The only defensible comparison available is
against MES-24 five hours earlier, and **by construction that delta must be zero**. It is a
self-consistency check and is labelled as one everywhere it appears.

#### C-3 — the old-revision exclusion, re-derived against the frozen set, and found empty

Re-derived from **this run's own artefacts** rather than inherited from MES-24:

* The frozen requirement set carries **no exclusion mechanism of any kind**. A scenario is scored, or
  `not_scored` with `reason: extension | pending | added-after-release` (grepped: 16 / 4 / 1
  occurrences, 20 entries). There is no "old-revision" bucket to put anything in.
* **No `--expected-failures` baseline** is passed on any invocation and none exists in the tree
  (MES-13's `conformance/expected_failures.yml` was retired at MES-13 and is gone).
* All **19** scored server FAILUREs decompose by check-id prefix as **`sep-2575` ×17, `sep-2322` ×1,
  `wire-schema-valid` ×1** — every one a 2026-07-28 requirement. SEP-2575 *is* the stateless core.
* Five of the seventeen (`…-404-initialize`, `-ping`, `-logging-setlevel`, `-resources-subscribe`,
  `-resources-unsubscribe`) probe methods this revision **removed** and require HTTP 404. **The
  scenario treats their absence as the requirement** — the exact opposite of targeting the old
  revision.

**Bucket 2 (scenario-targets-old-revision) is EMPTY.** MES-13's three-way classification therefore
resolves as bucket 1 (genuine gap) and bucket 3 (harness-side) only.

**Recommended wording for ADR-003 sub-decision 5, supplied and not applied here.** Recording a
PO-accepted sub-decision as superseded is an edit to a PO decision. Per the PM's RAT-6 ruling this
sub-task supplies **the measurement and the recommended wording**; the ADR edit itself belongs to the
parent, MES-19:

> Sub-decision 5's exclusion clause is **superseded on the measurement** — recommended by MES-49,
> **pending PO ratification at release**. It was written against stable harness `0.1.16`, which had no
> way to scope a run to a revision; it does not transfer to a frozen requirement set that already
> scopes itself to one. Measured at `7480f2f` with `0.2.0-alpha.11` / requirement set md5
> `d6eb2061b2d35c7c71a86059b08bb928`: the set has no exclusion mechanism, no baseline is used, and
> all 19 scored server FAILUREs are 2026-07-28 requirements. **The set to enumerate and exclude is
> empty.** Not applied silently, not dropped.

### Part B — RAT-5, the whole-tree OSV cross-check, with its positive control

`CLAUDE.md` assigns this to MES-19 by name, twice, and the PM overruled my reading that it belonged
to Sprint 5. My argument was that `mix.lock` is untouched so there is nothing new to measure — a good
argument for why the **result** would be uninteresting, and not an argument for leaving an assigned
obligation undischarged. The PM was right; "the answer is probably boring" is the reasoning that
leaves controls unrun.

**Why this control exists at all.** Gate 6 (`mix hex.audit`) reads advisory data from the **local
registry cache** and cannot detect staleness: a complete-but-old snapshot passes 6a and exits 0 on 6b
while missing every advisory published since. OSV is queried **live over the network**, so it is
**freshness-independent** in the one way the gate is not.

```text
QUERY   POST https://api.osv.dev/v1/querybatch   <- 26 queries, one per mix.lock entry
        HTTP=200 ; 26 results for 26 queries (1:1) ; packages with advisories: 0
CONTROL POST https://api.osv.dev/v1/querybatch   <- bandit@1.10.2, the pre-remediation version
        HTTP=200 ; 14 records: EEF-CVE-2026-39803/39804/39805/39806/39807/42786/42788,
        GHSA-375f-4r2h-f99j, -9q9q-324x-93r2, -c67r-gc9j-2qf7, -frh3-6pv6-rc8j,
        -pf94-94m9-536p, -q6v9-r226-v65f, -rf5q-vwxw-gmrf
```

**The control is the point and it is why the zero can be believed**: an OSV query returning nothing
looks *identical* whether the feed answered or the request silently failed. Same endpoint, same batch
shape, same session — one returns 14 records, the other returns 26 empty objects. **The empty tree
result is the feed answering.** Whole locked tree: **0 advisories across 26 packages.**

**Two obligations, recorded rather than assumed discharged.**

1. **Sprint 5 must re-run this against the final locked tree at publish.** A run today certifies
   today's lock and nothing else. `mix.lock` is untouched by MES-47/48/49, but the release ticket may
   move a dependency, and a green measured before that move would be a claim wider than its check.
   **Both halves, or the gate is exactly that.**
2. **The gate-6 residual is unchanged at 21 unvalidated of 26**, said out loud rather than letting a
   green stand alone. Gate 6a's baseline sentinel validates advisory rows only for the five packages
   that carry the 22 baseline ids (`bandit`, `hpax`, `mint`, `plug`, `req`). The other **21** —
   `bunt`, `credo`, `dialyxir`, `earmark_parser`, `elixir_uuid`, `erlex`, `ex_doc`, `file_system`,
   **`finch`**, `jason`, `makeup`, `makeup_elixir`, `makeup_erlang`, `mime`, `nimble_options`,
   `nimble_parsec`, `nimble_pool`, `plug_crypto`, `telemetry`, **`thousand_island`**, `websock` —
   are untouched by it, and `finch` and `thousand_island` are **runtime deps on this SDK's transport
   path**, so the residual is not confined to dev tooling. **This OSV run is the compensating control
   that covers them**: it queried all 26 by name and version, not the five the sentinel can reach.
   It does not shrink the residual on gate 6 itself, which stays 21 of 26 for any ticket that runs
   the gate without this cross-check.

### A2d — the empties, enumerated. Nothing is absorbed into a denominator.

Anything that cannot be measured is named and classified rather than left inside a fraction.

| # | class | count | members |
|---|---|---|---|
| 1 | Scored **client** scenarios for the authorization profile this release **does not implement** | **25** | `auth/` `metadata-default`, `metadata-var1`, `metadata-var2`, `metadata-var3`, `basic-cimd`, `scope-from-www-authenticate`, `scope-from-scopes-supported`, `scope-omitted-when-undefined`, `scope-step-up`, `scope-retry-limit`, `token-endpoint-auth-basic`, `token-endpoint-auth-post`, `token-endpoint-auth-none`, `pre-registration`, `resource-mismatch`, `offline-access-scope`, `offline-access-not-supported`, `authorization-server-migration`, `iss-supported`, `iss-not-advertised`, `iss-supported-missing`, `iss-wrong-issuer`, `iss-unexpected`, `iss-normalized`, `metadata-issuer-mismatch` |
| 2 | **Server** `not_scored`, `reason: pending` — run, reported, never counted | **3** | `json-schema-2020-12` (**8 S / 0 F — passes, and counts for nothing**), `http-header-validation` (9 S / 3 F / 2 W), `http-custom-header-server-validation` (4 S / 6 F) |
| 3 | `not_scored`, `reason: extension` — optional by definition (SEP-1730) | **16** | server: `tasks-lifecycle`, `tasks-capability-negotiation`, `tasks-wire-fields`, `tasks-request-state-removal`, `tasks-mrtr-input`, `tasks-request-headers`, `tasks-dispatch-and-envelope`, `tasks-status-notifications`, `tasks-required-task-error`, `tasks-mrtr-composition` · client: `auth/client-credentials-jwt`, `auth/client-credentials-basic`, `auth/enterprise-managed-authorization`, `auth/dpop`, `auth/dpop-nonce`, `auth/wif-jwt-bearer` |
| 4 | `not_scored`, `reason: added-after-release` | **1** | `json-schema-2020-12-preservation` (**9 S / 0 F — passes, and counts for nothing**) |
| 5 | Scored **server** scenarios a **null implementation also passes** — the subtrahend in 35 − 6 = 29 | **6** | `input-required-result-ignore-extra-params`, `input-required-result-missing-input-response`, `input-required-result-unsupported-methods`, `input-required-result-validate-input`, `sep-2164-resource-not-found`, `server-sse-multiple-streams` |
| 5b | Scored **client** scenarios a **null client also passes** — the subtrahend in 8 − 2 = 6 | **2** | `auth/resource-mismatch`, `http-standard-headers` |
| 6 | Rows leaving **no result-file row at all**, or a row with **no measurable outcome** | **see below** | — |

**Class 6, enumerated exactly, because "no row" and "a green row" look the same from a summary:**

* **No `checks.json` written at all.** Our two legs: **none** — 50/50 server and 39/39 client
  scenarios produced a result directory. The **null control** arm dropped one:
  `tasks-capability-negotiation` (extension, not scored). Recorded because a scenario that leaves no
  row cannot be distinguished from one that was never required, and only a per-scenario reconciliation
  against the frozen set surfaces it. It is *outside* both scored denominators, so no figure moves.
* **A row with only SKIPPED checks — measured nothing, and the console prints it with a green tick.**
  `tasks-status-notifications` reports `✓ tasks-status-notifications: 0 passed, 0 failed`. It is
  `not_scored`/extension so it touches no figure, but **`✓` over a scenario that measured nothing is
  precisely the shape this sprint exists to catch**, and it is named here rather than left to read as
  a pass. The null client shows the same shape on `http-standard-headers`, which is *why* that
  scenario is non-discriminating (class 5b).
* **Features with no scenario in either direction — a zero that is not a measurement.** The
  **extensions negotiation surface (SEP-2133)** leaves no row anywhere: grepping the whole harness
  (`dist/` and `src/`) for `2133` returns **nothing**. Likewise **deterministic `tools/list` ordering**
  — MES-48's subject — has **no ordering check** in either leg. These are *unmeasured*, not *passed*,
  and the distinction is the difference between "we have evidence" and "no one looked".

**Two kinds of zero, and neither is evidence of anything.** JSON Schema 2020-12 (SEP-2106) **was
measured** — 8/8 server, 9/9 client — and both scenarios are `not_scored`, so the work earns nothing
in any figure. SEP-2133 is **not measured at all**. Both read as "0 scored credit" on a summary sheet.

### Gates — all six, individually, on this branch

Run in the isolated worktree at `7480f2f` + this branch's two docs commits.

| # | gate | result |
|---|---|---|
| — | `mix hex --version` ≥ 2.5.1 (gate-6 floor, checked first) | **Hex v2.5.1** — at the floor |
| 1 | `mix format --check-formatted` | exit **0** |
| 2 | `mix compile --force --warnings-as-errors` | exit **0**, 69 files |
| 3 | `mix credo` | exit **0** — 119 files, 1090 mods/funs, **no issues** |
| 4 | `mix dialyzer` | exit **0** — **Total errors: 0**, skipped 0, unnecessary skips 0 |
| 5 | `mix test` | exit **0** — 13 doctests, **558 tests, 0 failures** |
| 5 | **seed sweep, 20 varied seeds** | **20 / 20 green**, 558 tests each: seeds 0, 1, 7, 42, 99, 123, 256, 512, 1024, 2048, 4096, 7777, 11111, 24680, 31415, 54321, 65535, 80808, 99991, 123456 |
| 6a | baseline-lock sentinel at `d697093` | **PASS — all 22 known advisory ids present** (44 advisory lines reported) |
| 6b | `mix hex.audit` on this project | exit **0** — *No retired or security advisory packages found* |

**Gate 6 was run as the two-step procedure, never bare.** A bare 6b green is not trustworthy on its
own: `mix hex.audit` false-greens on absent or corrupt local advisory data, per-package and silently.

**No dependency moved on this branch, so the gate-6 residual is unchanged at 21 of 26**, exactly as
predicted. What changed is not the residual but the **coverage of the compensating control**: Part B
queried all 26 live.

**Gates 1 and 2 remain blind to `conformance/`** — `.formatter.exs` inputs are `{config,lib,test}/**`
and `elixirc_paths` excludes it, so neither gate sees the adapters this entry's figures depend on.
Raised as **MES-46**, unchanged and unscheduled; restated here because a green that does not cover
the instrument is worth saying twice.

### What this sub-task found that reading would not have

1. **A concurrent seat moved the branch under a live measurement** (F-11) — caught by a routine
   `git status`, adjudicated by timestamp, and fixed with a worktree. Margin was **12 seconds**.
2. **The prediction's `6/7` was right and its reasoning was wrong** — the non-discriminating core
   scenario is `http-standard-headers`, not `http-invalid-tool-headers`. Only building the null
   **client** — a control the prediction implied but never defined — could show that.
3. **A run whose adapter never starts is check-for-check identical to having no client at all**
   (13 S / 83 F / 17 SKIPPED / 1 INFO, 2/32). MES-19 hit that by accident; it is now reproduced by
   construction.
4. **A scenario that measures nothing prints as `✓`** (`tasks-status-notifications`, 0 passed /
   0 failed).
5. **An over-broad grep for "timeout" produced 10 false hits** that would have read as a fleet of
   starved scenarios had they been counted rather than read. All 10 were checks whose own text says
   "not testable" / "could not".
6. **`--timeout` does not exist on the server leg** — read from the CLI's own `--help`. F-10 is
   dischargeable on one leg, and the other's exemption is structural rather than an oversight.

**Delta on the certified figures: zero.** Every scored number MES-24 reported is reproduced here, on
a tree whose only difference from `7480f2f` is one documentation file, twice, in two independent runs
that agree check for check. That is the whole of what Part A was asked to establish, and it is worth
no more than that.

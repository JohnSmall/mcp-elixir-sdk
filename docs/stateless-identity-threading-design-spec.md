# Identity-threading design spec (stateless successor to the MES-2 seam)

**Ticket:** MES-7 deliverable 2 · **Status:** ACCEPTED WITH COMMENTS (PO, 2026-07-26; comments folded into this v4) · **Type:** design, no implementation code.
**Gate:** PO acceptance of this spec unlocks MES-8/9/10. **Security-critical** — a dedicated invariant-focused Codex review recurs at MES-10.
**Supersedes (as design):** the MES-2 spec `docs/handler-opts-identity-seam-spec.md` (2025-11-25), whose binding point (`initialize`) the target revision removes.

## 1. Problem

The shipped seam (1.1.0) resolves caller identity **once, at the** `initialize` request, from the authenticated Plug pipeline (`conn.assigns`), and binds it into the per-session `MCP.Server` handler state for the session's life (`plug.ex:232-259`, `Handler.init/1`). The stateless core removes **both** anchors: the `initialize` handshake (SEP-2575) and the protocol session / `Mcp-Session-Id` (SEP-2567). The timing anchor and the storage location both disappear, and any request may land on any instance behind a round-robin balancer. A new mechanism must bind pipeline-established identity **per request, without a session**, preserving the security property.

## 2. The invariant (non-negotiable)

> **Caller identity comes from the authenticated transport/Plug pipeline, never from model-controlled input.**

Specced in MES-2, implemented in MES-3, proven end-to-end in MES-6 (a tool-call argument of the same name is _ignored_ in favour of the pipeline-bound identity, verified live against real Jira). Any stateless redesign that lets identity arrive as, or be influenced by, a model-passed value is a **regression of the security property**, not a migration.

**Why the generic stateless answer is forbidden for identity.** The spec's replacement for cross-call state is an explicit **state handle** — a server-minted token the model passes back as an ordinary tool argument (SEP-2567). Identity **must not** use this: a model-passed handle is model-controlled input by definition. Identity is a special case the generic mechanism does not cover — this is the crux.

## 3. Candidate evaluation

Candidates from the [design-input §4](https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/234422273):

* **C1 — per-request resolution at the Plug boundary.** Resolve identity from `conn.assigns` on every request; thread it into the per-request handler invocation. (Design-input's stated likely front-runner.)
* **C2 —** `_meta`/header-carried, pipeline-set context. Identity rides a transport-level channel the pipeline controls and the model cannot forge.
* **C3 — keep the seam's _shape_ (a** `handler_opts`-style factory over the conn) but re-anchor it per-request. Best backward-familiarity for EMFA.

Criteria (design-input §4): **(a)** upholds the §2 invariant; **(b)** works under any-instance/round-robin routing; **(c)** minimal churn to EMFA's `handler_opts` pattern; **(d)** testable by the AC-style assertions (esp. AC3).

### 3.1 Invariant screen (criterion a — a hard gate, not a score)

| Candidate | Passes the invariant gate? | Reason |
| --- | --- | --- |
| **C1** | **Yes** | Identity derived by SDK code from `conn` (pipeline), placed in a per-request context the model cannot write. No model-controlled path. |
| **C2** | **Conditional / risky** | `_meta` on a request is part of the JSON-RPC envelope the _client_ composes. If identity rides client-supplied `_meta`, it is model/client-influenced → **fails the gate**. It passes _only_ if the channel is transport-layer state the server sets from the pipeline and never trusts from the client body — at which point it collapses into C1 with a more spoofable-looking surface. **"Careful this doesn't just relocate the spoofing surface" (design-input §4).** |
| **C3** | **Yes** (it is a _shape_, not a _mechanism_) | The factory reads `conn` (pipeline); its result is SDK-controlled. C3 layered on C1's mechanism inherits C1's gate pass. |

**C2 is eliminated as a standalone mechanism** — it either reduces to C1 or risks trusting a client-composed channel. C1 and C3 survive.

### 3.2 Matrix (surviving candidates)

| Criterion | C1 (per-request resolution) | C3 (handler_opts shape, per-request) |
| --- | --- | --- |
| (a) invariant | ✅ by construction | ✅ (inherits C1) |
| (b) any-instance routing | ✅ no server-side per-session store; each instance reconstructs from that request's conn | ✅ same |
| (c) EMFA churn | ⚠ mechanism only — needs a consumer-facing shape | ✅ preserves `handler_opts: fn conn -> [...] end` verbatim |
| (d) AC-testable | ✅ AC3 by construction (see §4.2) | ✅ same |

> **PO ruling (2026-07-26, [acceptance page](https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/240549984)):** criterion (c) is **struck as a decision factor**. The matrix is retained as the historical record of how the recommendation was reached; future Sprint 3/4 design and implementation decisions must not weight EMFA familiarity or EMFA impact. The `handler_opts` factory shape survives on its own justification: the SDK cannot know which `conn.assigns` key a consumer's authenticated pipeline establishes, so a `(Plug.Conn.t() -> keyword())` function is the minimal extraction seam, and the static `keyword()` form covers launch-time resolution. The shape is the pipeline-extraction seam, not backward familiarity.

**C1 is the mechanism; C3 is the consumer-facing extraction-seam shape. They are not rivals — they compose.**

### 3.3 Reference-SDK cross-check (answers Q3) — a strong converging idiom

**Provenance caveat.** The only reference SDK on the **native 2026-07-28 stateless line** consulted is **C# 2.0.0-preview.1** (read via the web — not in `/workspace/samples`). The local Python/TS/Go checkouts are **pre-stateless** (Python 1.25.0 @ protocol 2025-11-25; TS 2.0.0-alpha.0 — an SDK-API restructure still on protocol 2025-11-25; Go v1.3.0-pre.1 @ protocol 2025-06-18). The official stateless betas are Python 2.0.0b1 / TS v2 / Go v1.7.0-pre.1 / C# 2.0.0-preview.1 (blog, 2026-07-28). So C# is cited as the authoritative stateless pattern; the other three corroborate the **auth-threading idiom**, which is already per-request in their pre-stateless code and carries forward.

**The idiom converges hard:** every SDK hands the tool handler a **per-request context object whose principal field is populated by the transport/HTTP auth layer, on a path separate from the model-controlled tool arguments.**

| SDK | Per-request principal accessor | Type | Binding granularity |
| --- | --- | --- | --- |
| **C# 2.0.0-preview.1** (stateless-native) | `RequestContext.User` (base `MessageContext.User`), backed by per-message `JsonRpcMessageContext.User`; or inject `ClaimsPrincipal` as a tool param (excluded from the JSON schema) | `ClaimsPrincipal?` | per JSON-RPC **message**; `Stateless=true` is the default |
| **Go** v1.3.0-pre.1 | `CallToolRequest.Extra.TokenInfo` / `auth.TokenInfoFromContext(ctx)` | `*auth.TokenInfo` | per message; separate from `input` |
| **TS** 2.0.0-alpha.0 | `ServerContext.http.authInfo` | `AuthInfo` | per dispatched message |
| **Python** 1.25.0 | `get_access_token()` (ambient contextvar set by bearer-auth middleware) | `AccessToken` | per ASGI request |

**Convergence → our design.** The cross-SDK-idiomatic shape is exactly §4's recommendation: a **per-request server-context struct carrying a distinct** `identity` field, populated only by the transport auth pipeline, passed to the handler alongside — never merged into — the validated tool arguments. C# (the one true stateless reference) hangs identity on the **per-message** context precisely _because_ it has no session — the pattern to mirror in Elixir on the `ToolContext` successor. We are **adopting the reference idiom, not inventing one** (the ratification's stated preference). Elixir lacks C#'s DI-parameter-injection ergonomics, so the explicit context-field form (Go/TS style) is the natural fit; C#'s optional `ClaimsPrincipal`-as-parameter is an ergonomic variant, not a different model.

## 4. Recommended design — **C1 mechanism wearing the C3 face**

### 4.1 Shape

1. **Consumer-facing extraction seam (C3 shape):** the Plug keeps a `handler_opts`-style option — a static `keyword()` **or** a `(Plug.Conn.t() -> keyword())` factory. This is not justified by backward familiarity: the SDK cannot know which `conn.assigns` key a consumer's authenticated pipeline establishes, so an extraction seam must exist; `(Plug.Conn.t() -> keyword())` is the minimal honest form, and static `keyword()` covers launch-time resolution. For HTTP, the factory is evaluated per request, not once at `initialize`.
2. **Mechanism (C1):** on each request, after localhost/Origin (and any auth) enforcement passes, the transport resolves the factory against that request's `conn` and places the result into a **per-request handler-invocation context** — the stateless successor to today's `MCP.Server.ToolContext` (`tool_context.ex`; already per-request, carrying `request_id`/`meta`). Identity becomes a first-class field on that context (e.g. `context.identity` / `context.assigns`).
3. **Handler read-site:** the handler reads identity from the **context**, never from `arguments`. The `Handler.init/1`-opts vehicle (which bound identity per-session) is replaced by the per-request context field.

This is the design-input's front-runner (C1) using the C3 option shape as the pipeline-extraction seam. It reuses an existing architectural element (`ToolContext` is already the per-request context object — the MES-2 design-input §3.1 named it as the correct home for per-call request context), and it matches the reference-SDK idiom (§3.3: C#'s `RequestContext.User`, Go's `Extra.TokenInfo`, TS's `ServerContext.http.authInfo`).

### 4.2 The AC3 drop path — SDK-enforced boundary vs handler-author responsibility

**Definition — "normal callback-contract path" = the SDK-owned construction of the per-request handler context, _before_ the handler callback is invoked.** The SDK builds `context.identity` **solely** from the authenticated pipeline (the resolved `conn`), on a code path that never reads the JSON-RPC `params`/`arguments`.

**What the SDK ENFORCES (hard guarantee, machine-checkable):** `params`/`arguments` **never** populate `context.identity`. Every enumerated callback (§6 MC-1) receives `arguments` and `context` as **distinct** parameters; an argument named `identity` — on a tool call _or_ a `prompts/get` _or_ any other enumerated callback — lands in `arguments`, and **there is no SDK code path that copies it into** `context.identity`. A model-supplied `identity` value is dropped from the identity channel **by construction**. This mirrors the reference SDKs (principal field vs schema-bound `input`).

**What remains handler-author responsibility (NOT SDK-enforceable):** the SDK cannot stop arbitrary handler code from reading a model-controlled argument and (wrongly) treating it as identity. The guarantee is scoped to the SDK's own plumbing, not to user code. **Therefore the SDK's docs and tests MUST warn:** identity is `context.identity` _only_; model-controlled `arguments`/`params` must never be read as identity.

**"AC3 by construction" = this split precisely:** the SDK guarantees the plumbing (arguments can't reach the identity channel); the handler contract + the ported ACs guarantee author discipline. The ported ACs (D4) assert the SDK guarantee on **both a tool path (AC3) and a non-tool path (**`prompts/get`, AC3′) — a competing model-controlled `identity` value is ignored in favour of the pipeline value on each.

### 4.3 Why not leak `conn` into the handler

Same rationale as MES-2 §6: `conn` in `handle_call_tool` would couple every handler to Plug and break stdio/in-process transports. Identity arrives as **resolved data** on the per-request context, not as a `conn`. Transport-agnostic; the resolution happens in the Plug, only the keyword/identity flows onward (as the factory result did at `initialize` before).

## 5. Answers to the design-input §7 questions

* **Q1 — does the stateless request→handler path expose a clean per-request threading point (analogue of** `Handler.init/1` opts)? **Yes.** Today's `handle_call_tool/4` already receives a per-request `ToolContext`. The stateless design mandates identity be a first-class field on that per-request context, populated by the transport before the handler runs. The threading point exists and aligns with both an existing local pattern and the reference-SDK idiom. _(This assumes properties of the MES-8 call path — see the numbered constraints in §6.)_
* **Q2 — can we keep the** `handler_opts`-style factory ergonomics? **Yes** for configuration: the Plug option remains static keyword or `conn -> keyword()` factory because that is the SDK's pipeline-extraction seam. The **handler read-site** moves from `state.identity` to `context.identity`, and the **guarantee** changes from "bound once per session" to "resolved fresh per request" for HTTP (AC5 re-interpretation). Both belong in the upgrade notes.
* **Q3 — how do the reference SDKs solve authenticated identity under stateless; is there a converging idiom?** **Yes — a strong one** (§3.3). All reference SDKs thread the authenticated principal on a **per-request context field distinct from tool args**; C# 2.0.0-preview.1 (stateless-native) uses `RequestContext.User` on the per-message context. We mirror it via the per-request `ToolContext`-successor's `identity` field. **Adopted, not invented.**
* **Q5 — what's the AC set?** Port AC1–AC8 per the ported AC draft (D4); AC3 unchanged (the invariant's test, tool path), **AC3′ added (the same invariant test on a non-tool path,** `prompts/get`), AC6 → AC6′ (instance/request isolation), AC5 re-interpreted, AC7/AC8 re-confirmed on the rewritten transport.

## 6. MES-8 constraints (Condition 1 of the /plan ratification)

The seam contract assumes the following properties of the stateless request→handler call path that **MES-8 defines**. MES-8's /plan must demonstrate conformance to each; **if any constraint is infeasible, MES-8 STOPS and escalates to the PM** rather than adapting this design ad hoc (per the ratification Condition 1 / the MES-9 escalation rule). MES-7 owns this contract; MES-8 owns the call path.

**Identity-capable retained handler callbacks** — read from `lib/mcp/server/handler.ex` (`@optional_callbacks`, lines 135–148), the **source of truth**, not the protocol method list. These are the callbacks MC-1..MC-6 govern:

| Handler callback (arity) | MCP method | Identity-capable? |
| --- | --- | --- |
| `handle_list_tools/2` | `tools/list` | ✅ (which tools this principal may see) |
| `handle_call_tool/3,4` | `tools/call` | ✅ (act as the principal) |
| `handle_list_resources/2` | `resources/list` | ✅ |
| `handle_read_resource/2` | `resources/read` | ✅ (per-principal authorization) |
| `handle_list_resource_templates/2` | `resources/templates/list` | ✅ |
| `handle_list_prompts/2` | `prompts/list` | ✅ |
| `handle_get_prompt/3` | `prompts/get` | ✅ (per-principal prompt content) |
| `handle_complete/3` | `completion/complete` | ✅ |

**Removed in the stateless core (out of the identity surface):** `handle_subscribe/2` + `handle_unsubscribe/2` (`resources/subscribe`/`unsubscribe` → replaced by `subscriptions/listen` — changelog Key Changes **Major #4**) and `handle_set_log_level/2` (`logging/setLevel` **removed**; log level now per-request via `io.modelcontextprotocol/logLevel` — changelog **Major #5**). The required `init/1` (handler.ex:41) is not a client-request dispatch and binds no identity in the stateless model. Any successor surface (e.g. `subscriptions/listen`) inherits MC-1..MC-6 if it dispatches an identity-capable consumer callback. This callback breadth matches the reference SDKs, which expose the authenticated principal to tool **and** resource **and** prompt handlers alike (C# `RequestContext`/`MessageContext.User` across families; Python `get_access_token()` in tools/resources/prompts; Go `RequestExtra.TokenInfo`; TS `ctx.http.authInfo`).

* **MC-1 (per-request context on EVERY identity-capable callback).** The stateless request→handler invocation MUST pass a per-request context object, constructed once per request, to **every retained client-originated handler callback that can make an identity-dependent decision** — **all eight callbacks enumerated in the table above**, **not** merely `tools/call`.
* **MC-2 (pipeline-populated, pre-handler — all enumerated callbacks).** The transport/Plug layer MUST populate that context's identity field from the authenticated request pipeline (`conn`) **before** any enumerated callback runs, and MUST NOT derive it from the JSON-RPC `params`/`arguments`. This applies uniformly to tool, resource, and prompt callbacks — not just `tools/call`.

**PO Comment B — transport instantiation of MC-2 (verbatim, accepted for D2 v4):**

* **HTTP (Streamable-HTTP transport): identity is resolved per request** — the factory is evaluated against that request's authenticated `conn`, after enforcement passes (MC-5), populating the per-request context's identity field.
* **stdio / in-process:** identity is resolved **once at launch** via the static `keyword()` form (the trust boundary is the pipe/process, not the request) and stamped onto the same per-request context field for every request. All other constraints (MC-1, MC-3, MC-4, MC-6) apply identically.
* **Per-caller multiplexing over a single stdio pipe is out of contract:** the only channels that could signal a caller switch (`arguments`, `_meta`) are model/client-composed — exactly what the invariant forbids. One process per principal, or use the HTTP transport.

* **MC-3 (per-request, non-shared).** The context MUST be per-request; identity MUST NOT be cached, shared, or reused across requests or instances (no session-scoped identity storage). This is the AC6′ / round-robin guarantee.
* **MC-4 (no model write path — all enumerated callbacks).** For **every** enumerated callback, no SDK-owned context-construction path may copy `arguments`/`params` into the context identity field. The SDK's plumbing cannot substitute a model-supplied value into identity (AC3 by construction; see §4.2 for the enforced-vs-author boundary). **Notification stance:** client-originated _notifications_ (`notifications/cancelled`; `notifications/initialized` is removed by SEP-2575) are handled **SDK-internally** and are **never dispatched to a consumer** `Handler` callback, so there is no consumer notification callback that could make an identity-dependent decision. Server-_originated_ notifications/requests (progress, logging, list-changed, MRTR input-required) may only be emitted **while processing a client request** (SEP-2260), so any identity-dependent side effect is gated by that enclosing request's authenticated per-request context. **Rule: no consumer handler may make an identity-dependent decision for a notification; any notification side effect MUST be preceded by transport/auth gating (the enclosing client request's authenticated context).** If a future design dispatches client notifications to consumer code, that surface falls under MC-1..MC-4 too.
* **MC-5 (enforcement precedes resolution).** The transport MUST run the identity-resolution factory **only after** localhost/Origin (and any auth) enforcement passes, so a rejected request never invokes the factory (AC7).
* **MC-6 (clean failure).** A factory that raises or returns a non-keyword MUST fail that request cleanly (controlled, non-leaking error) **without** invoking the handler and without orphaning anything (AC8). Error-code choice per gap register §F.
* **MC-7 (consumer-facing shape preserved as extraction seam).** The consumer-facing configuration MUST accept a `handler_opts`-style value — a static `keyword()` or a `(Plug.Conn.t() -> keyword())` factory. This is preserved as the pipeline-extraction seam, not because consumer churn is a decision factor.

## 7. Consumer impact — upgrade notes preview

* **Config line pattern:** `handler_opts: fn conn -> [identity: conn.assigns.identity] end` remains the HTTP extraction seam; it now fires per request.
* **Handler change:** read identity from the per-request context (`context.identity`) instead of from `init`-stored state; identity-dependent **resource** and **prompt** handlers read the same `context.identity` (MC-1).
* **Guarantee change (AC5):** for HTTP, "bound once per session, reused" → "resolved fresh per request from the authenticated pipeline." For consumers such as EMFA that use per-request bearer tokens, this is stronger than the 1.1.0 behaviour: identity no longer freezes at the `initialize` token if later requests present updated tokens.

## 8. Open items / risks

* **R1 (MES-8 coupling):** mitigated by the MC-1..MC-7 constraints + the stop-and-escalate rule.
* **R2 (reference-SDK idiom) — RESOLVED:** the reference SDKs converge on exactly the "per-request context field" shape this spec recommends (§3.3), so the design mirrors the idiom rather than inventing one. Residual: the local Python/TS/Go checkouts are pre-stateless, so the stateless confirmation rests on **C# 2.0.0-preview.1** (web) plus the pre-stateless per-request-auth idiom in the other three; if MES-8/9 later read the Python/Go/TS _stateless betas_ and find a materially different shape, §3.3/§4 are revisited.
* **Out of scope:** the state-handle mechanism for _non-identity_ cross-call state (SEP-2567) — a separate MES-8 concern; this spec only rules it **out** for identity.

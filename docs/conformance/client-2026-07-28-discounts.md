# Client leg — the in-scope figure and the two discounts

Rendered from `MCP.Conformance.Discounts`, which reads the committed censuses.
Do not edit: regenerate with `mix conformance.discounts`.

Measurement run: commit `f4be9eb4624813ebcf5418898180f0ca433ab562`, harness
`0.2.0-alpha.11`, requirements `2026-07-28`.

## The headline, and every subtraction behind it

Every verdict below is under the leg's own summary reducer
(`client_summary`), which **fails a WARNING** that `requirements_exit` and
`server_summary` both ignore.

| figure | value | scenarios removed |
| --- | --- | --- |
| as driven | **7 of 7** | — |
| after drive-policy only | **6 of 7** | `request-metadata` |
| after null-passable only | **6 of 7** | `http-standard-headers` |
| **surviving BOTH** | **5 of 7** | `request-metadata`, `http-standard-headers` |

The two middle rows are published rather than the endpoints because they are
the same number over **different sets**. Two units independently produced
"6 of 7" from those two rows before anyone noticed they were answering
different questions.

Surviving both: `http-custom-headers`, `http-invalid-tool-headers`, `json-schema-ref-no-deref`, `sep-2322-client-request-state`, `tools_call`.

## The in-scope denominator

7 scenarios: `http-custom-headers`, `http-invalid-tool-headers`, `http-standard-headers`, `json-schema-ref-no-deref`, `request-metadata`, `sep-2322-client-request-state`, `tools_call`.

In-scope is the scored client scenarios **not in the `auth/` namespace** —
the authorization profile, which ADR-003 puts out of 2.0.0.
25 scored scenarios are excluded on that ground, and
they are named rather than counted: `auth/authorization-server-migration`, `auth/basic-cimd`, `auth/iss-normalized`, `auth/iss-not-advertised`, `auth/iss-supported`, `auth/iss-supported-missing`, `auth/iss-unexpected`, `auth/iss-wrong-issuer`, `auth/metadata-default`, `auth/metadata-issuer-mismatch`, `auth/metadata-var1`, `auth/metadata-var2`, `auth/metadata-var3`, `auth/offline-access-not-supported`, `auth/offline-access-scope`, `auth/pre-registration`, `auth/resource-mismatch`, `auth/scope-from-scopes-supported`, `auth/scope-from-www-authenticate`, `auth/scope-omitted-when-undefined`, `auth/scope-retry-limit`, `auth/scope-step-up`, `auth/token-endpoint-auth-basic`, `auth/token-endpoint-auth-none`, `auth/token-endpoint-auth-post`.

The raw figure is **8 of 32**,
and it may appear only beside that exclusion, never as a bare pass rate. It
is larger than the in-scope numerator by exactly the auth scenarios that
pass: `auth/resource-mismatch`.

## Discount 1 — drive-policy, re-derived by measurement

The `strict_connect` probe drives one scenario under one changed policy: it
halts the moment `MCP.Client.connect/1` errors, where the measurement adapter
logs and carries on. A scenario that goes red under the probe and stays green
under the measurement adapter is one whose pass depends on our policy rather
than on a property of the SDK.

The probe drives **only** `request-metadata` — the scenario the claim is
about. Every other scenario takes its not-driven path, so its other rows are
not results and are not shown. Reading them as failures would report
"0 of 7".

| scenario | measurement | strict-connect probe |
| --- | --- | --- |
| `request-metadata` | PASS | FAIL |

## Discount 2 — null-passable, and which null

A scenario is null-passable if **any** null client passes it — the reading
least flattering to this SDK, and the one Sprint 4's figure was computed
under. Which null matters, because a **stricter** null scores **lower**:

| null control | scored (client_summary) | in-scope scenarios it passes |
| --- | --- | --- |
| `2026-07-28-null-connect` | 2/32 | `http-standard-headers` |
| `2026-07-28-null-exit0` | 2/32 | `http-standard-headers` |
| `2026-07-28-null-request` | 1/32 | none |

Removed on this ground: `http-standard-headers`.

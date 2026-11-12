# ADR-004: An error reply whose request id cannot be read carries `"id": null` (JSON-RPC 2.0 §5), not an omitted id

**Status: ACCEPTED**: PO, 2026-11-08, recorded by the PM in MES-226 comment 34768. The rule extends to
-32020, -32602 and -32603 (see *Decision*). That extension is the PM's application of the PO's stated
reason, recorded 2026-11-12 in comment 35038, and the PM has reported it to the PO.
**Supersedes:** nothing. **Refines:** nothing. This record is a ruled deviation from the pinned schema,
inside ADR-003's core-conformance scope.
**Canonical location:** `docs/adr/0004-error-reply-id-null-on-unreadable-id.md`. The repo is the source of
truth. The Confluence mirror is published by the PM after the merge.

---

## Context

When the server cannot read the id of the request it is refusing, it builds a JSON-RPC error reply with
`"id": null`. Two normative sources disagree about that reply.

**The pinned MCP schema** (`modelcontextprotocol/modelcontextprotocol` @ `5f5440bb`,
`schema/2026-07-28/schema.ts`, md5 `48a009165e07f6732e38baf91291de87`, the md5 that
`conformance/build_etcc_register.exs:16` already records) types the id as optional, and as not nullable:

```
schema.ts:261  export type RequestId = string | number;
schema.ts:298  export interface JSONRPCErrorResponse {
schema.ts:299    jsonrpc: typeof JSONRPC_VERSION;
schema.ts:300    id?: RequestId;
schema.ts:301    error: Error;
```

The prose at the same commit (`docs/specification/2026-07-28/basic/index.mdx`, md5
`1b680a56e96533ff28f6eac07bd51bdc`) makes the same id optional. It also binds every message to JSON-RPC 2.0:

```
index.mdx:27-28  All messages between MCP clients and servers **MUST** follow the
                 [JSON-RPC 2.0](https://www.jsonrpc.org/specification) specification.
index.mdx:47     - Unlike base JSON-RPC, the ID **MUST NOT** be `null`.        (the Requests section)
index.mdx:94       id?: string | number;                                       (the Error Responses block)
index.mdx:103    - Error responses **MUST** include the same ID as the request they correspond to
                   (except in error cases where the ID could not be read due a malformed request).
```

`:47` governs requests. `:103` exempts the unreadable case from the same-ID rule. It does not say what the id
is then.

**JSON-RPC 2.0 §5** (<https://www.jsonrpc.org/specification>, fetched 2026-11-12T09:12:49Z, html md5
`18284c0d0f103f78dc3cb5b7896faac0`) does say, for the Response object's `id` member:

> This member is REQUIRED.
> It MUST be the same as the value of the id member in the Request Object.
> If there was an error in detecting the id in the Request object (e.g. Parse error/Invalid Request), it MUST be Null.

So no reply satisfies both sources. An omitted id satisfies the schema and breaks §5's *REQUIRED*. A null
id satisfies §5 and breaks `schema.ts:300`.

**How this was found.** CODE_REVIEWER raised it on MES-210 (comment 34564, F2), against the stdio refusals
that ticket added. Those refusals send the same null the HTTP Plug has sent since MES-157. The PM kept null
on MES-210 so the two transports would not split (comment 34566), and passed the question to the PO here.

### Where the server sends a null id (measured at `main` `d270313`)

| Site | Code | When the id is null |
| --- | --- | --- |
| `lib/mcp/transport/streamable_http/plug.ex:347` | -32700 | always: the body is not JSON |
| `plug.ex:374-381` | -32600 | always: the body is not a JSON object (an array or a scalar) |
| `plug.ex:1326-1333` | -32600 | always: the body could not be read |
| `plug.ex:1323`, `:414-416` | -32600 | always: HTTP 413, the body exceeds `:max_body_length` |
| `plug.ex:370-371`, `:398` (from `:1157`, `:1160`) | -32600 | an object with no readable id |
| `plug.ex:352-353`, `:395` (from `:1198`) | -32020 | a header mismatch on a message with no readable id |
| `plug.ex:349-350`, `:389` (from `:1150`) | -32602 | an invalid `_meta` on a message with no readable id |
| `plug.ex:355-368`, `:697` (from `:342-343`) | -32603 | a `handler_opts` factory or collector failure on a message with no readable id. **Reasoning only:** reachable for a notification; no test pins it |
| `lib/mcp/transport/stdio.ex:286` | -32700 | always: the line is not JSON |
| `lib/mcp/server/connection.ex:237` | -32600 | JSON that is not a request, with no readable id |

"Readable" means one rule in both places: a string or a number in an object
(`plug.ex:1246-1247`, `connection.ex:252-253`). Anything else gets `null`.

### The measured consequence

A peer that validates against the published TypeScript SDK's schema rejects the reply. CODE_REVIEWER
measured this on MES-210 (34564 F2), and CODE_CREATOR reproduced it on 2026-11-12:

```
@modelcontextprotocol/sdk 1.32.1 (npm install --ignore-scripts), node v24.13.0
dist/esm/types.js:110  export const RequestIdSchema = z.union([z.string(), z.number().int()]);
dist/esm/types.js:178      id: RequestIdSchema.optional(),          (JSONRPCErrorResponseSchema, :175)

JSONRPCErrorResponseSchema.safeParse({jsonrpc: "2.0", <id>, error: {code: -32700, message: "Parse error"}})
  id null            success: false [{"path":["id"],"code":"invalid_union","message":"Invalid input"}]
  id omitted         success: true
  id 7               success: true
  id "server-error"  success: true
```

## Decision

**Keep `"id": null` on both transports, for every error reply the server builds when the request id cannot be
read. A readable id is echoed as before.**

The PO's reason, verbatim (MES-226 comment 34768): *"the MCP schema allows leaving out the error id, and
JSON-RPC 2.0 says leave it null. Since the communication layer is JSON-RPC 2.0 then we have to keep it null"*.

The PO's question named the Plug's -32700/-32600 and the stdio replies. Applying the same answer to the
-32020, -32602 and -32603 sites in the table is **the PM's application of the PO's stated reason**:
JSON-RPC 2.0 governs, so the id is null. It was recorded 2026-11-12 (MES-226 comment 35038).

## Why

**MCP defers to JSON-RPC 2.0, and JSON-RPC 2.0 decides this case.** `index.mdx:27-28` makes every MCP message
a JSON-RPC 2.0 message. For the unreadable-id case, §5 names exactly one value: Null. The MCP sources do not
override §5 here. `index.mdx:47` overrides JSON-RPC only for *request* ids, and `:103` exempts the unreadable
case without choosing a value. Only the schema's TypeScript type rules null out.

**The reference SDKs make the same choice, at the versions measured on 2026-11-12.** MES-226's original
report said none of them sends null. That holds only for a pre-2026-07-28 Python checkout. The PM corrected
it in comment 35039.

```
TS SDK 1.32.1  dist/esm/server/webStandardStreamableHttp.js:120-128
  createJsonErrorResponse(status, code, message, options) { ... JSON.stringify({ jsonrpc: '2.0', error, id: null })
  used for -32700 at :501, :520 and for -32600 at :506, :536, :540
  -> this SDK's own server reply fails this SDK's own JSONRPCErrorResponseSchema (above).

Python mcp 2.3.0 (wheel md5 221a310cb352d8678b051da78b3ca52c) with mcp-types 2.3.0 (md5 24246786378257e0de0b519bb97c7664)
  mcp_types/version.py:41    MODERN_PROTOCOL_VERSIONS: Final[tuple[str, ...]] = ("2026-07-28",)
  mcp_types/jsonrpc.py:136-139
    id: RequestId | None
    """The id of the request this error responds to.

    Required but nullable per JSON-RPC 2.0: `None` encodes `"id": null` (the id could not be determined).
  mcp/server/_streamable_http_modern.py:193-196
    if isinstance(msg, JSONRPCError) and msg.id is None:
        # JSON-RPC requires `id: null` to appear on the wire when the request
        # id couldn't be parsed; `exclude_none` would otherwise drop it.
        body["id"] = None
  :415 (-32700) and :204-208 (-32600) are built with id=None.

The "server-error" placeholder exists only in /workspace/samples/mcp-python-sdk @ dda845a (v1.25.0-89, 2026-02-07):
  src/mcp/types/jsonrpc.py:78             id: str | int
  src/mcp/server/streamable_http.py:301   id="server-error",  # We don't have a request ID for general errors
```

The C# and Go SDKs were not examined. This record makes no claim about them.

## Consequences

* **A peer that validates against the schema rejects these replies.** That is measured above for the TS SDK
  1.32.1 `JSONRPCErrorResponseSchema`. The rejection is confined to replies whose id could not be read. Every
  reply with a readable id carries that id and is unaffected.
* **No official-conformance check is affected.** The server leg was run at `d270313` against the pinned
  harness build (`dist/index.js` sha256 `a10085d0…`):
  `mix conformance.run --leg server`, then `mix conformance.adjudicate`, which returned ACCEPTED. Results:
  194 checks (151 SUCCESS, 40 FAILURE, 2 WARNING, 1 SKIPPED). `HttpServerErrorJsonrpcId` is SUCCESS with
  `{"errorResponsesObserved": 12}`. `WireSchemaValid` has 45 SUCCESS and 1 FAILURE, an unrelated
  `GetPromptResult` without `messages` in `input-required-result-non-tool-request`. No failing or warning
  check mentions a null id. Every pinning test below carries `oc: :none`. The HTTP tests say no OC check
  sends such a body. The stdio tests say no OC scenario drives the stdio transport.
* **The 2.0.0 conformance claim must name this exception.** ADR-003 sub-decision 6 requires the claim to be
  worded to its scope. No 2.0 claim exists yet: `README.md` has none, and `CHANGELOG.md` mentions conformance
  only at `:182` and `:204`, which are the 1.0.0 history. So the release ticket, which owns that wording, must
  include this deviation.
* **A future schema-shape assertion on these paths must expect null.** For example, applying the remedy in
  `docs/conformance/adjudications/adjudication-D2a-ii-2026-07-28.json:1984` ("Assert the reply's wire shape as
  the schema's JSONRPCErrorResponse") to an unreadable-id path must expect null. That row's own path,
  `resources/read` with an unknown URI, has a readable id and is unaffected.
* **The SDK's HTTP client handles null and absent differently.** *Reasoning from the source, not a
  measurement.* `lib/mcp/transport/streamable_http/client.ex:697-698` matches a null-id 4xx error to the
  request its POST carried and delivers the error object. An error with no id at all falls to
  `:uncorrelated` (`:700`) and reaches the caller as `{:http_error, status, body}` (`:688`). The caller
  still fails at once, but without the error object.
* **The code comments cite the wrong source for null.** `plug.ex:1071-1073` and `:1243-1245`, and the
  moduledoc of `test/mcp/transport/error_id_test.exs` at `:3-5`, cite `basic/index.mdx:103` for the null.
  `:103` does not say null, and `:94` makes the id optional. The source is JSON-RPC 2.0 §5, as recorded
  here. This record makes no `lib/` or `test/` edit. The correction is **MES-237** (backlog).
* **The behaviour is pinned by these tests, unchanged by this record.** Each asserts that the `id` key is
  present *and* null. `body["id"] == nil` alone would also pass for an absent key.

  | Transport | Test | Code |
  | --- | --- | --- |
  | HTTP | `test/mcp/transport/error_id_test.exs:70-72` (helper `:57-63`, `Map.has_key?` at `:61`) | -32700 |
  | HTTP | `error_id_test.exs:77-80`, `:85-87` | -32600 (array body, string body) |
  | HTTP | `error_id_test.exs:189-192`, `:197-200` | -32020 (notification, object id) |
  | HTTP | `test/mcp/transport/request_body_limit_test.exs:82-84` (helper `:66`), `:180-195` (`:190`) | -32600 (413) |
  | HTTP | `test/mcp/transport/error_data_test.exs:128-136`, `:141-147`, `:152-160`, `:247-273` (exact-map equality) | -32600 |
  | HTTP | `test/mcp/server/required_meta_types_test.exs:256-263` (`:261`, `:262`) | -32602 |
  | stdio | `test/mcp/transport/stdio_invalid_line_test.exs:159-176` (S1; `parse_error/0` at `:53-58`) | -32700 |
  | stdio | `stdio_invalid_line_test.exs:181-201` (S2; rows `:183-189`) | -32600 |
  | stdio | `stdio_invalid_line_test.exs:236-274` (C1, the Connection; rows `:238-250`) | -32600 |

  `test/mcp/transport/client_sent_response_test.exs:86-88` is **not** a pin. It asserts only
  `body["id"] == nil`, which an absent id also passes.
* **No conformance artefact is amended.** MES-226 searched every artefact that could need to cite this
  record:
  * The repo search was `git grep` over `docs/conformance`, `conformance/data`, `docs/adr`, `README.md`,
    `CHANGELOG.md`, `docs/conformance-testing.md` and `docs/architecture.md` for null-id phrasings,
    `readable id`, `JSONRPCErrorResponse`, `HttpServerErrorJsonrpcId`, `index.mdx:103`, MES-157, MES-210,
    MES-226 and `schema.ts:261`/`:298-301`. It hit 22 files, about 130 lines.
    * None of the hits needs a citation. `HttpServerErrorJsonrpcId` probes with readable ids only. The
      `:261` and `:298-308` ET-CC anchors are readable-id paths.
    * `adjudication-D1-server-ii-2026-07-28.json:589` is a record. Records are surfaced, not edited
      (ADR-003 Amendment 3).
    * The rest are false positives.
  * The Confluence search covered the gap-register pages D1 v5 (`239861761`), D2 v4 (`239796226`) and D5 v1
    (`239927297`), the conformance-testing page (`272367618`), the ADR-003 mirror (`249724984`) and the ADR
    register mirror (`232980491`). It found no relevant hit.
  * D3, D4 and D6 carry no page id in any of those bodies, so they were not checked.

## Alternatives considered

* **(a) Omit the id**, which is what the schema admits. **Rejected.** It breaks JSON-RPC 2.0 §5, which makes
  the id *REQUIRED* and, in this case, Null, and `index.mdx:27-28` binds MCP to JSON-RPC 2.0. A supporting
  reason, *reasoning and not a measurement*: the SDK's own HTTP client would then stop delivering the error
  object to its caller. An absent-id error is `:uncorrelated` and surfaces as `{:http_error, …}`
  (`client.ex:688`, `:700`), where a null-id error is matched to its request (`:697-698`).
* **(b) A placeholder id**, such as the `"server-error"` string in the pre-2026-07-28 Python SDK.
  **Rejected.** A made-up id asserts a match to a request that does not exist. A string placeholder can
  collide with a client-chosen string id: `RequestId` admits any string (`schema.ts:261`). It also breaks
  §5's "it MUST be Null". The Python SDK itself has since dropped the placeholder for null (see *Why*).

## Acceptance log

* **2026-11-08: ACCEPTED by the PO.** The PO answered NO to "omit the id": keep null on both transports
  (MES-226 comment 34768).
* **2026-11-12: PM application of the PO's reason** to -32020, -32602 and -32603 (MES-226 comment 35038),
  reported to the PO.

## Amendment log

* None.

defmodule MCP.Conformance.BucketZero do
  @moduledoc """
  Bucket 0 — the OC checks that are **out of the match denominator** because no
  conforming 2026-07-28 implementation can cause them to evaluate.

  The rule this module applies was ratified on MES-66 (A1) and is carried here
  **verbatim**, never paraphrased:

  > #{"A check is a match target only if a conforming 2026-07-28 implementation can cause it to evaluate."}

  ## Unmatchable is not "can't pass", and it is not "SKIPPED"

  Two collapses would each hollow out the denominator, in opposite directions.

    * **Verdict for evaluability.** An R3/R6 divergence is a FAILURE we cannot
      make pass while the current design stands, and it is still *matchable*:
      an ET test can assert our behaviour, which is a claim about the check
      even when the claim is "we diverge". Sweeping every check we fail into
      bucket 0 would leave a denominator of things we already pass.
    * **SKIPPED for unreachable.** SKIPPED is a *proxy* for unreachable and the
      two come apart under measurement. On the null-exit0 control the same
      scenario reports **11** SKIPPED rows where the truth is **2** — the other
      nine are methods a conforming client may drive and that client did not.
      Those are coverage gaps (bucket 2), not exclusions. `control/0` carries
      that measurement, and `classify/2` is run against it so the difference is
      a test result rather than a claim.

  ## Why the sweep is over skip SITES and not over statuses

  A run sheet cannot tell "skipped by construction" from "skipped because we
  did not drive it": both print `SKIPPED`. Only the harness source can, so the
  sweep starts from the instrument's complete **skip vocabulary** — every site
  in `dist/index.js` that can emit a non-evaluated verdict — and asks, per
  check, whether any of those sites can reach it.

  A check no skip site can reach evaluates unconditionally. That is a *source*
  reason for matchability, not a judgement about the run, and it covers the
  bulk of the 175 by construction rather than by getting through a list.

  The vocabulary is enumerated by a complete rule, not by greps for known
  shapes: every occurrence of the token, and every producer and consumer of the
  `skipped` flag, classified. A reader re-runs one grep, gets the same count,
  and finds that many rows. `verify_sites/1` is that check, run by the
  generator against a live harness.

  ## Three things the enumeration turned up that a partial one would not

    * A **homonym**. `{index, type, skipped: true}` at 1538:18221 is a
      per-STREAM record inside `server-sse-multiple-streams`, not a check
      verdict, and nothing ever reads it as one. Counting `skipped:!0`
      producers alone would mark that scenario skip-reachable; it is not.
    * A helper that **cannot** skip at our revision.
      `function kn(e,t){return e?`SUCCESS`:t===`2026-07-28`?`FAILURE`:`SKIPPED`}`
      returns SKIPPED only below 2026-07-28. That is a matchability argument
      the source makes for us.
    * A **branch with no row of its own**. The `subscriptions/listen`
      applicability branch at 1153:22300 is not a member of the 175; it is
      consumed by three named checks that are. Enumerating it as a member
      would have inflated bucket 0's candidate set by one.

  ## The scenario-level skip is the one this sweep cannot see, so it is answered separately

  Two sites gate an entire scenario on `source.introducedIn` / `source.removedIn`
  and emit **no rows at all**. A scenario stopped there contributes nothing to
  A1's 175, so a sweep *over* the 175 is blind to it by construction.
  `scenario_gate/0` answers it from source instead of by silence: the harness's
  applicability predicate is

      Po(source, v) = not extension and introducedIn <= v and (removedIn == nil or v < removedIn)

  and all 44 in-scope scenarios carry a non-extension `source` with
  `introducedIn <= 2026-07-28` and no `removedIn`, so none of them can reach
  that gate at this revision.

  It is the same predicate that supplies the strongest evidence for member 1:
  the harness's own `initialize` scenario declares `removedIn: F` where
  `F = "2026-07-28"`.

  ## What this module does NOT establish

  **Matchability, and nothing else.** That a check *can* be claimed by an ET-CC
  member — never that one does. Whether any member claims it is D2b's question
  and it may well leave some of these in bucket 2b as unmatched. "matched" in
  an A5 artefact would pre-empt a count this ticket does not own and cannot see.
  """

  alias MCP.Conformance.MatchKey

  @rule "A check is a match target only if a conforming 2026-07-28 implementation can cause it to evaluate."

  @revision "2026-07-28"

  # The harness build every citation below addresses. Version AND sha, because a
  # third copy of this package on the same disk is 0.2.0-alpha.10 at a different
  # sha, and npx picks its cache directory by spec hash — someone re-deriving
  # without a pin can land on it.
  @harness %{
    package: "@modelcontextprotocol/conformance",
    version: "0.2.0-alpha.11",
    file: "dist/index.js",
    sha256: "a10085d0cfc9dd9192cc227f0f4dd6f1af9a94f6a0d3e30af08d4a0bcf268aae",
    audit: "grep -o SKIPPED dist/index.js | wc -l"
  }

  # Every occurrence of the token, classified. The KEY is the address; the quote
  # is lifted live from the harness by `verify_sites/1`, so this table cannot
  # drift into citing bytes that are not there.
  #
  #   :emits_check     — sets a CHECK's status to SKIPPED
  #   :emits_scenario  — skips a whole SCENARIO; emits no rows
  #   :compares        — reads a status value and compares against SKIPPED
  #   :message_only    — the token appears inside prose
  @token_sites %{
    {1128, 10_941} => {:compares, "severity rank table for the run reducer"},
    {1128, 14_832} => {:emits_check, "request-metadata ClientVersionHeaderMatchesMeta"},
    {1128, 15_125} => {:emits_check, "request-metadata capability-declaration lambda"},
    {1153, 64} => {:message_only, "server-session-lifecycle description prose"},
    {1153, 1843} => {:emits_check, "server-session-lifecycle, HTTP 405 branch"},
    {1153, 3605} => {:emits_check, "helper nn/2, called only from server-session-lifecycle"},
    {1153, 7282} => {:emits_check, "server-stateless check helper"},
    {1483, 2172} => {:emits_check, "helper kn/2 — CANNOT return SKIPPED at 2026-07-28"},
    {1493, 3178} => {:compares, "json-schema-2020-12 errorMessage suffix"},
    {1493, 3668} => {:compares, "json-schema-2020-12 errorMessage suffix"},
    {1493, 4133} => {:compares, "json-schema-2020-12 errorMessage suffix"},
    {1790, 4634} => {:emits_check, "caching ResourcesReadCachingHints"},
    {2053, 1933} => {:emits_check, "helper Sr/5, called only from tasks-status-notifications"},
    {2179, 4724} => {:emits_check, "authorization-code-grant skippedCheck/1"},
    {2181, 1993} => {:emits_check, "http-standard-headers, Mcp-Method 8-method loop"},
    {2181, 2432} => {:emits_check, "http-standard-headers, Mcp-Name 3-method loop"},
    {2201, 292} => {:message_only, "json-schema-2020-12-preservation description prose"},
    {2201, 2238} => {:message_only, "json-schema-2020-12-preservation errorMessage prose"},
    {2201, 2566} => {:emits_check, "json-schema-2020-12-preservation $schema"},
    {2201, 2802} => {:emits_check, "json-schema-2020-12-preservation $defs"},
    {2201, 3083} => {:emits_check, "json-schema-2020-12-preservation additionalProperties"},
    {2201, 3356} => {:emits_check, "json-schema-2020-12-preservation composition"},
    {2201, 3630} => {:emits_check, "json-schema-2020-12-preservation conditional"},
    {2201, 3867} => {:emits_check, "json-schema-2020-12-preservation $anchor"},
    {2201, 6192} => {:compares, "json-schema-2020-12-preservation errorMessage suffix"},
    {2201, 6693} => {:compares, "json-schema-2020-12-preservation errorMessage suffix"},
    {2201, 7147} => {:compares, "json-schema-2020-12-preservation errorMessage suffix"},
    {2203, 1021} => {:emits_scenario, "applicability gate Wo/4 in the runner"},
    {2210, 828} => {:emits_scenario, "applicability gate in Xo/5 in the runner"}
  }

  # Producers of a `skipped` flag. `:check` reaches a check verdict; `:scenario`
  # skips a whole scenario; `:homonym` is the same property name on a different
  # object and is never read as a verdict.
  @flag_writes %{
    {1153, 12_520} => {:check, "sep-2575-server-identifies-in-result-meta prerequisite"},
    {1153, 22_300} => {:check, "shared branch ie/1 — NO ROW OF ITS OWN, consumed by 3 checks"},
    {1153, 25_325} => {:check, "sep-2575-server-sends-prompts-list-changed-on-subscription"},
    {1153, 26_468} => {:check, "sep-2575-server-sends-tools-list-changed-on-subscription"},
    {1538, 18_221} => {:homonym, "per-STREAM record field, never read as a check verdict"},
    {2203, 1387} => {:scenario, "runner Ko/6, scenario-level; emits no rows"},
    {2210, 989} => {:scenario, "runner Xo/5, scenario-level; emits no rows"},
    {2249, 5367} => {:scenario, "runner, PROPAGATION of the scenario-level flag"},
    {2249, 5588} => {:scenario, "runner, explicit undefined on the error path"}
  }

  # Consumers. Exactly one reads a check-level flag; the other four are the
  # scenario-level flag in the runner and the CLI.
  @flag_reads %{
    {1153, 7270} => {:check, "s?.skipped ? SKIPPED : SUCCESS — the ONLY check-level reader"},
    {2249, 5375} => {:scenario, "r.skipped"},
    {2251, 43} => {:scenario, "e.skipped"},
    {2253, 245} => {:scenario, "c.skipped"},
    {2254, 1433} => {:scenario, "t.skipped"}
  }

  # `this.skippedCheck(` at 2179:126 and 2179:538 match a naive `\\.skipped`
  # regex and are NOT reads of the flag — they are calls to a method whose name
  # begins with it. Named here so the count reconciles for the next reader.
  @flag_read_false_positives [{2179, 126}, {2179, 538}]

  # The 22 in-scope rows a skip site can reach, and the gate that would skip
  # them. Every other in-scope row evaluates unconditionally.
  @skip_reachable [
    {"request-metadata", "ClientVersionHeaderMatchesMeta", {1128, 14_832},
     "MCP-Protocol-Version header or _meta.protocolVersion absent"},
    {"request-metadata", "ClientDeclaresRootsCapability", {1128, 15_125},
     "client declared no roots capability (the check reads \"if present\")"},
    {"request-metadata", "ClientDeclaresSamplingCapability", {1128, 15_125},
     "client declared no sampling capability (the check reads \"if present\")"},
    {"request-metadata", "ClientDeclaresElicitationCapability", {1128, 15_125},
     "client declared no elicitation capability (the check reads \"if present\")"},
    {"server-stateless", "ServerIdentifiesInResultMeta", {1153, 12_520},
     "a prerequisite request failed"},
    {"server-stateless", "ServerSendsSubscriptionAck", {1153, 22_300},
     "server advertises no subscription-delivered capability"},
    {"server-stateless", "ServerTagsSubscriptionId", {1153, 22_300},
     "server advertises no subscription-delivered capability"},
    {"server-stateless", "ServerHonorsNotificationFilter", {1153, 22_300},
     "server advertises no subscription-delivered capability"},
    {"server-stateless", "ServerSendsPromptsListChangedOnSubscription", {1153, 25_325},
     "server did not declare prompts.listChanged"},
    {"server-stateless", "ServerSendsToolsListChangedOnSubscription", {1153, 26_468},
     "server did not declare tools.listChanged"},
    {"caching", "ResourcesReadCachingHints", {1790, 4634}, "resources/read was not exercised"},
    {"http-standard-headers", "ClientMcpMethodHeader_initialize", {2181, 1993},
     "client sent no initialize request"},
    {"http-standard-headers", "ClientMcpMethodHeader_notifications_initialized", {2181, 1993},
     "client sent no notifications/initialized request"},
    {"http-standard-headers", "ClientMcpMethodHeader_tools_list", {2181, 1993},
     "client sent no tools/list request"},
    {"http-standard-headers", "ClientMcpMethodHeader_tools_call", {2181, 1993},
     "client sent no tools/call request"},
    {"http-standard-headers", "ClientMcpMethodHeader_resources_list", {2181, 1993},
     "client sent no resources/list request"},
    {"http-standard-headers", "ClientMcpMethodHeader_resources_read", {2181, 1993},
     "client sent no resources/read request"},
    {"http-standard-headers", "ClientMcpMethodHeader_prompts_list", {2181, 1993},
     "client sent no prompts/list request"},
    {"http-standard-headers", "ClientMcpMethodHeader_prompts_get", {2181, 1993},
     "client sent no prompts/get request"},
    {"http-standard-headers", "ClientMcpNameHeader_tools_call", {2181, 2432},
     "client sent no tools/call request"},
    {"http-standard-headers", "ClientMcpNameHeader_resources_read", {2181, 2432},
     "client sent no resources/read request"},
    {"http-standard-headers", "ClientMcpNameHeader_prompts_get", {2181, 2432},
     "client sent no prompts/get request"}
  ]

  # The two members, and what would have to change for each to leave the bucket.
  #
  # Source 1 of the plan — "the 2026-07-28 schema declares neither type" — was
  # WITHDRAWN on measurement. The file carrying that zero is `spec.types.js`,
  # the VALUE emission of a TypeScript module whose type surface lives in the
  # sibling `.d.ts`; type names are erased from the `.js` by construction, so
  # the same grep returns 0 for `Tool`, which the `.d.ts` declares 37 times.
  # It is also labelled `DRAFT-2026-v1`, which is not 2026-07-28 and so is not
  # authority for what 2026-07-28 removed. A measurement that cannot fail is
  # not evidence.
  @members %{
    "ClientMcpMethodHeader_initialize" => %{
      method: "initialize",
      lead_source: "harness scenario metadata",
      sources: [
        "harness `initialize` scenario declares source:{introducedIn:`2025-06-18`,removedIn:F}, F = `2026-07-28` (dist/index.js 2:3379)",
        "requirements/2026-07-28.yaml lines 15-16: the dated revisions through 2025-11-25 use the stateful initialize handshake and 2026-07-28 is stateless with per-request _meta",
        "cross-leg: the SAME build requires a 2026-07-28 SERVER to answer initialize with 404 + -32601 (in-scope check sep-2575-http-server-method-not-found-404-initialize)"
      ]
    },
    "ClientMcpMethodHeader_notifications_initialized" => %{
      method: "notifications/initialized",
      lead_source: "frozen requirements file",
      sources: [
        "requirements/2026-07-28.yaml lines 15-16: 2026-07-28 has no stateful initialize HANDSHAKE, and notifications/initialized is that handshake's acknowledgement rather than a separate method — one sentence covering both members as a unit",
        "SEP-2575 removed the handshake; our client omits both halves BECAUSE it is conformant"
      ],
      corroboration_limit:
        "the cross-leg argument does NOT reach this member: the server-leg removed-method loop is [initialize, ping, logging/setLevel, resources/subscribe, resources/unsubscribe] and a notification has no response to assert on"
    }
  }

  @doc "The ratified rule, verbatim. Never rendered as \"SKIPPED is excluded\"."
  @spec rule() :: String.t()
  def rule, do: @rule

  @doc "The harness build every source citation addresses."
  @spec harness() :: map()
  def harness, do: @harness

  @doc "The complete skip vocabulary: token sites, flag producers, flag consumers."
  @spec vocabulary() :: map()
  def vocabulary do
    %{
      token_sites: @token_sites,
      flag_writes: @flag_writes,
      flag_reads: @flag_reads,
      flag_read_false_positives: @flag_read_false_positives
    }
  end

  @doc "The 22 in-scope rows a skip site can reach, and the gate that would skip each."
  @spec skip_reachable() :: [{String.t(), String.t(), {pos_integer(), pos_integer()}, String.t()}]
  def skip_reachable, do: @skip_reachable

  @doc "The bucket-0 members, keyed by check name, with per-member sources."
  @spec members() :: map()
  def members, do: @members

  @doc """
  Re-derive the skip vocabulary from a live harness `dist/index.js` and check it
  against the committed classification.

  Returns `{:ok, quotes}` — a map from `{line, col}` to the bytes at that
  address — or `{:error, reason}` naming the addresses that appeared, vanished
  or moved. Refusing is the point: a citation whose bytes have shifted is worse
  than no citation, because it still reads as one.
  """
  @spec verify_sites(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_sites(path) do
    lines = path |> File.read!() |> String.split("\n")

    found = %{
      token: scan(lines, ~r/SKIPPED/),
      write: scan(lines, ~r/skipped:\s*[^,}]+/),
      read: scan(lines, ~r/[A-Za-z_$][A-Za-z0-9_$]*\??\.skipped(?![A-Za-z0-9_$])/)
    }

    reads = Map.drop(found.read, @flag_read_false_positives)

    with :ok <- same_addresses(found.token, @token_sites, :token_sites),
         :ok <- same_addresses(found.write, @flag_writes, :flag_writes),
         :ok <- same_addresses(reads, @flag_reads, :flag_reads) do
      {:ok, Map.merge(found.token, Map.merge(found.write, found.read))}
    end
  end

  @doc """
  Classify every row of A1's manifest and return the committed artefact.

  `control` is the extracted null-exit0 fixture (see the mix task); `quotes` is
  `verify_sites/1`'s output, or `%{}` when no harness is at hand.
  """
  @spec classify(map(), map(), map()) :: map()
  def classify(manifest, control, quotes \\ %{}) do
    rows = Enum.flat_map(manifest["scenarios"], &classify_scenario/1)
    {out, in_denom} = Enum.split_with(rows, &(&1["bucket"] == 0))

    %{
      "generated_by" => "mix conformance.bucket_zero",
      "artefact_schema_version" => 1,
      "revision" => @revision,
      "match_target_rule" => %{
        "text" => @rule,
        "wording_note" => manifest["match_target_rule"]["wording_note"],
        "byte_equal_to" => "in-scope-2026-07-28.json match_target_rule.text",
        "establishes" => "MATCHABILITY only — never that any ET-CC member claims the check (D2b)"
      },
      "keyed_by" => %{
        "manifest" => "docs/conformance/in-scope-2026-07-28.json",
        "fields" => MatchKey.key_fields(),
        "total" => manifest["arithmetic"]["total"],
        "note" =>
          "A5's term is keyed BY A1's key, not stored IN A1's file. A1's manifest stays " <>
            "byte-untouched and both its denominator terms stay null; the cross-file test " <>
            "fails if these two disagree on the total or on any key."
      },
      "arithmetic" => %{
        "equation" => "total = in_denominator + out_of_denominator",
        "total" => length(rows),
        "in_denominator" => length(in_denom),
        "out_of_denominator" => length(out),
        "word" => "MATCHABLE, never MATCHED"
      },
      "harness" => @harness,
      "vocabulary" => emit_vocabulary(quotes),
      "scenario_gate" => scenario_gate(),
      "control" => control,
      "subset_hypothesis" => subset_hypothesis(rows),
      "members" => emit_members(out),
      "checks" => rows
    }
  end

  @doc """
  The scenario-level gate, answered from source rather than by silence.

  A sweep over A1's 175 cannot see this mechanism: a scenario stopped here emits
  no rows, so it is absent from the population being swept.
  """
  @spec scenario_gate() :: map()
  def scenario_gate do
    %{
      "sites" => ["2203:1021", "2210:828"],
      "predicate" =>
        "Po(source, v) = not extension and introducedIn <= v and (removedIn == nil or v < removedIn)",
      "version_order" => ["2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28"],
      "result" =>
        "NONE of A1's 44 in-scope scenarios can reach this gate at 2026-07-28. All 44 carry a " <>
          "non-extension source with introducedIn <= 2026-07-28 and no removedIn, resolved from " <>
          "the scenario class or its base class (the http-* client scenarios inherit " <>
          "source={introducedIn:F} from base class Ia).",
      "contrast" =>
        "The `initialize` scenario DOES reach it — source:{introducedIn:`2025-06-18`,removedIn:F} " <>
          "— which is the harness's own statement that the method is removed at 2026-07-28, and " <>
          "the strongest single source for member 1.",
      "stated_as" => "a result, not by silence (A2d)"
    }
  end

  defp classify_scenario(%{"leg" => leg, "scenario" => scenario, "checks" => checks}) do
    Enum.map(checks, fn check -> classify_check(leg, scenario, check) end)
  end

  defp classify_check(leg, scenario, check) do
    name = check["name"]
    status = check["status"]
    reach = Enum.find(@skip_reachable, fn {s, n, _site, _gate} -> s == scenario and n == name end)

    {bucket, code, reason} = verdict(reach, status, name)

    %{
      "key" => check["key"],
      "token" => MatchKey.encode!(check["key"]),
      "leg" => leg,
      "scenario" => scenario,
      "name" => name,
      "status" => status,
      "matchable" => bucket != 0,
      "bucket" => bucket,
      "reason_code" => code,
      "reason" => reason,
      "skip_site" => skip_site(reach),
      "skip_gate" => skip_gate(reach)
    }
  end

  # No skip site can reach it: it evaluates unconditionally. A source reason,
  # not a judgement about how the run happened to go.
  # A SKIPPED status with no site able to produce it means the vocabulary is
  # incomplete. Refusing here is the point: the alternative is reporting
  # "evaluates unconditionally" about a row that demonstrably did not.
  defp verdict(nil, "SKIPPED", name) do
    raise "#{name} is SKIPPED but no committed skip site reaches it — the skip vocabulary is incomplete"
  end

  defp verdict(nil, _status, _name) do
    {nil, "no_skip_site",
     "No site in the harness's complete skip vocabulary can reach this check, so it evaluates " <>
       "unconditionally on any run that reaches its scenario. Matchable."}
  end

  # Reachable, and it evaluated. The ratified "can" is EXISTENTIAL over
  # conforming implementations, and ours is the witness.
  defp verdict({_s, _n, _site, gate}, status, _name) when status != "SKIPPED" do
    {nil, "skip_reachable_evaluated",
     "A skip site can reach this check (#{gate}), and it evaluated as #{status} in the in-scope " <>
       "run. The rule's \"can cause it to evaluate\" is existential over conforming " <>
       "implementations; ours is the witness. Matchable — the verdict is not the question."}
  end

  defp verdict({_s, name, _site, gate}, "SKIPPED", name) do
    case @members[name] do
      nil ->
        {nil, "skip_reachable_optional_available",
         "Skipped because an OPTIONAL BUT AVAILABLE path went unexercised (#{gate}). A conforming " <>
           "implementation could have driven it. That is a COVERAGE GAP — bucket 2 — not an " <>
           "exclusion, and it stays in the denominator."}

      member ->
        {0, "removed_by_spec",
         "Making this check evaluate would require the client to send a #{member.method} request, " <>
           "which 2026-07-28 removed (SEP-2575). Driving it would mean being LESS conformant, " <>
           "which is the bucket-0 definition. Out of denominator."}
    end
  end

  defp skip_site(nil), do: nil
  defp skip_site({_s, _n, {line, col}, _gate}), do: "#{line}:#{col}"

  defp skip_gate(nil), do: nil
  defp skip_gate({_s, _n, _site, gate}), do: gate

  # Both directions, with the zeros reported (A2d). A hypothesis tested only in
  # the direction it is expected to hold is not tested.
  defp subset_hypothesis(rows) do
    unmatchable = Enum.filter(rows, &(&1["bucket"] == 0))
    skipped = Enum.filter(rows, &(&1["status"] == "SKIPPED"))
    non_skipped_unmatchable = Enum.filter(unmatchable, &(&1["status"] != "SKIPPED"))
    skipped_matchable = Enum.filter(skipped, & &1["matchable"])

    %{
      "hypothesis" => "unmatchable is a subset of SKIPPED",
      "direction_1" => %{
        "question" => "any NON-SKIPPED check unmatchable?",
        "count" => length(non_skipped_unmatchable),
        "members" => Enum.map(non_skipped_unmatchable, & &1["token"]),
        "candidates_tested" => direction_1_candidates(rows),
        "result" =>
          "ZERO. The R3/R6 FAILUREs are the tempting false members and both are MATCHABLE: a " <>
            "conforming server would evaluate them SUCCESS where we evaluate them FAILURE. " <>
            "Conformance moves the VERDICT, never the evaluation."
      },
      "direction_2" => %{
        "question" => "any SKIPPED check matchable?",
        "count" => length(skipped_matchable),
        "members" => Enum.map(skipped_matchable, & &1["token"]),
        "result" =>
          "ZERO on this population — both SKIPPED rows are bucket 0. This direction is " <>
            "CONTINGENT, not structural: on the null-exit0 control the same classifier returns " <>
            "nine of them. See `control`.",
        "holds" => skipped_matchable == []
      },
      "verdict" =>
        "SKIPPED is NECESSARY but not SUFFICIENT for bucket 0, and the sufficiency half is what " <>
          "the control measures rather than asserts."
    }
  end

  defp direction_1_candidates(rows) do
    evaluated_but_reachable =
      rows
      |> Enum.filter(&(&1["reason_code"] == "skip_reachable_evaluated"))
      |> Enum.map(& &1["token"])

    r3_r6 =
      rows
      |> Enum.filter(
        &(&1["name"] in ["ServerUnsupportedVersionError", "HttpServerMethodNotFound404initialize"])
      )
      |> Enum.map(& &1["token"])

    %{
      "skip_reachable_yet_evaluated" => evaluated_but_reachable,
      "r3_r6" => r3_r6,
      "not_a_member" => %{
        "what" => "the subscriptions/listen applicability branch at 1153:22300",
        "ruling" =>
          "It has NO ROW OF ITS OWN and is therefore not a member of the 175 at all. It is a " <>
            "shared branch, consumed by three checks that ARE members — " <>
            "sep-2575-server-sends-subscription-ack, sep-2575-server-tags-subscription-id and " <>
            "sep-2575-server-honors-notification-filter — all three SUCCESS, all three " <>
            "classified skip_reachable_evaluated above."
      }
    }
  end

  defp emit_members(out_rows) do
    Enum.map(out_rows, fn row ->
      member = Map.fetch!(@members, row["name"])

      %{
        "token" => row["token"],
        "key" => row["key"],
        "name" => row["name"],
        "removed_method" => member.method,
        "lead_source" => member.lead_source,
        "sources" => member.sources,
        "corroboration_limit" => Map.get(member, :corroboration_limit),
        "harness_source" => row["skip_site"],
        "what_would_make_it_evaluate" =>
          "The client sending #{article(member.method)} #{member.method} request — i.e. becoming NON-conformant with " <>
            "2026-07-28. That is the bucket-0 definition, not a consequence of it.",
        "what_would_make_it_leave_the_bucket" =>
          "A future revision reinstating #{member.method}, or the harness dropping it from the " <>
            "hardcoded synthesis loop at #{row["skip_site"]}. Neither is a change to OUR " <>
            "implementation: nothing we can write moves this member."
      }
    end)
  end

  # "a initialize request" reads as a typo in a published artefact.
  defp article(<<c, _rest::binary>>) when c in ~c"aeiou", do: "an"
  defp article(_method), do: "a"

  defp emit_vocabulary(quotes) do
    %{
      "complete_by" =>
        "every occurrence of the token, and every producer and consumer of the `skipped` flag, " <>
          "classified. Re-run the audit grep, get #{map_size(@token_sites)}, find " <>
          "#{map_size(@token_sites)} rows.",
      "token_sites" => emit_sites(@token_sites, quotes, "category"),
      "token_site_totals" => totals(@token_sites),
      "flag_writes" => emit_sites(@flag_writes, quotes, "level"),
      "flag_write_totals" => totals(@flag_writes),
      "flag_reads" => emit_sites(@flag_reads, quotes, "level"),
      "flag_read_false_positives" => %{
        "addresses" => Enum.map(@flag_read_false_positives, fn {l, c} -> "#{l}:#{c}" end),
        "why" =>
          "`this.skippedCheck(` matches a naive `\\.skipped` regex and is a METHOD CALL, not a " <>
            "read of the flag. A regex sweep reports 7 reads; there are 5."
      },
      "grep_forms" => %{
        "note" =>
          "written as they actually grep. `{skipped:!0}` with the braces returns 0 — the bare " <>
            "form is what matches.",
        "token" => "SKIPPED",
        "writes" => "skipped:",
        "reads" => "\\.skipped"
      }
    }
  end

  defp emit_sites(table, quotes, kind_key) do
    table
    |> Enum.sort()
    |> Enum.map(fn {{line, col} = addr, {kind, site}} ->
      %{
        "at" => "#{line}:#{col}",
        kind_key => to_string(kind),
        "site" => site,
        "quote" => Map.get(quotes, addr)
      }
    end)
  end

  defp totals(table) do
    table
    |> Enum.group_by(fn {_addr, {kind, _site}} -> to_string(kind) end)
    |> Map.new(fn {kind, sites} -> {kind, length(sites)} end)
    |> Map.put("total", map_size(table))
  end

  defp scan(lines, regex) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, n} ->
      regex
      |> Regex.scan(line, return: :index)
      |> Enum.map(fn [{byte_at, _len} | _] ->
        # Addresses are CHARACTER columns, not byte offsets: several of these
        # lines carry em dashes, and a byte offset would print a column no
        # reader could find. `binary_part/3` is the conversion.
        at = line |> binary_part(0, byte_at) |> String.length()
        {{n, at + 1}, String.slice(line, max(0, at - 60), 120)}
      end)
    end)
    |> Map.new()
  end

  defp same_addresses(found, committed, what) do
    f = found |> Map.keys() |> MapSet.new()
    c = committed |> Map.keys() |> MapSet.new()

    if MapSet.equal?(f, c) do
      :ok
    else
      appeared = f |> MapSet.difference(c) |> MapSet.to_list() |> Enum.sort()
      vanished = c |> MapSet.difference(f) |> MapSet.to_list() |> Enum.sort()
      {:error, {what, appeared: appeared, vanished: vanished}}
    end
  end
end

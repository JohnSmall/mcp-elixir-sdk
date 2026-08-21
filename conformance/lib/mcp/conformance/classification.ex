defmodule MCP.Conformance.Classification do
  @moduledoc """
  Why each non-passing scenario does not pass — as **data**, keyed by scenario
  id, with an owner.

  ## Why a table and not prose in a report

  MES-24's defect was a hand-written table drifting from the run it claimed to
  describe. A classification written into a document is a copy of a judgement;
  a classification written here is the judgement, and
  `MCP.Conformance.Census` refuses **both ways**:

    * a scenario that does not pass and has **no entry** — so a new failure
      cannot arrive unclassified while a rate still prints;
    * an entry for a scenario that **now passes** — so a stale entry cannot rot
      quietly into a description of something that stopped being true.

  The second direction is the one that gets skipped, and it is the one that
  matters after a remediation sprint: MES-56 hands this file to Sprint 6, whose
  whole job is to make entries here obsolete.

  ## The six classes

  Three are the **harness's own** and are never a judgement of ours — they are
  read from the frozen requirement set's `not_scored` reasons and only
  cross-checked here:

    * `:extension` — optional by definition (SEP-1730).
    * `:pending` — the suite's own reference fixture cannot pass it yet.
    * `:added_after_release` — added to the suite after the anchor release the
      frozen set derives from.

  Three are **ours**, and each is an assertion someone has to own:

    * `:real_gap` — this SDK should pass and does not. Sprint 6's queue.
    * `:out_of_scope_adr_003` — outside the conformance target ADR-003 sets
      (core server; authorization profile and extension track excluded).
    * `:by_design_2025_11_25` — behaviour that belongs to the previous revision
      and is deliberately absent from the stateless core.

  `owner` names who carries it: a ticket key, or `"ADR-003"` for a decision
  already taken.
  """

  @harness_classes [:extension, :pending, :added_after_release]
  @our_classes [:real_gap, :out_of_scope_adr_003, :by_design_2025_11_25]

  # Mapping from the harness's own `not_scored` reason strings to our class
  # atoms. Defined once, so a reason the harness invents that we do not know
  # about fails loudly instead of being silently filed as a gap.
  @harness_reasons %{
    "extension" => :extension,
    "pending" => :pending,
    "added-after-release" => :added_after_release
  }

  @typedoc "One classification: the class, why it holds, and who owns it."
  @type entry :: %{class: atom(), why: String.t(), owner: String.t()}

  # ---------------------------------------------------------------------------
  # SERVER leg, requirement revision 2026-07-28.
  #
  # Populated from the run the adjudicator ACCEPTED at commit cf15d9a. Every
  # entry names a scenario that did not pass under `server_summary` in that run;
  # the census refuses if one is missing OR if one has outlived its failure.
  # ---------------------------------------------------------------------------
  @gap_owner "MES-58 gap register -> Sprint 6"
  @extension_owner "ADR-003 (extension track, out of 2.0.0)"
  @pending_owner "upstream conformance suite"

  # Every tasks-* scenario fails for one reason, so the reason is written once.
  @extension_scenarios ~w(
    tasks-lifecycle tasks-capability-negotiation tasks-wire-fields
    tasks-request-state-removal tasks-mrtr-input tasks-request-headers
    tasks-dispatch-and-envelope tasks-required-task-error tasks-mrtr-composition
  )

  @extension_why "io.modelcontextprotocol/tasks (SEP-2663). Not scored by the frozen " <>
                   "2026-07-28 set — extensions are optional by definition (SEP-1730) — and " <>
                   "excluded from 2.0.0 by ADR-003 sub-decision 3. It RUNS and is reported " <>
                   "so the coverage gap is visible rather than absent; failing it costs " <>
                   "nothing against the conformance denominator."

  @pending_scenarios %{
    "http-header-validation" => "SEP-2243 Mcp-Method/Mcp-Name routing headers",
    "http-custom-header-server-validation" => "SEP-2243 custom-header validation"
  }

  @pending_why "Not scored: the suite's own reference fixture cannot pass it yet, so a " <>
                 "failure here is not evidence about this SDK either way. Run for " <>
                 "visibility. Re-examine when the upstream fixture catches up."

  # --- SCORED. Both are ours, and both are inside ADR-003's denominator. -----
  @ours %{
    "server-stateless" => %{
      class: :real_gap,
      why:
        "17 sep-2575 checks, and four distinct defects rather than one: (a) a request " <>
          "whose _meta is absent or invalid is answered HTTP 200 with no error, where " <>
          "the SEP requires -32602 and HTTP 400; (b) an unsupported protocolVersion is " <>
          "answered 200 rather than 400, and the supported-versions payload does not " <>
          "have the shape the check reads; (c) methods REMOVED by the stateless core " <>
          "(initialize, ping, logging/setLevel, resources/subscribe, " <>
          "resources/unsubscribe) are answered HTTP 200 where the SEP requires 404 — " <>
          "the JSON-RPC code is already right, the HTTP status is not; (d) " <>
          "error.data.requiredCapabilities is an array where the schema defines an " <>
          "object of capability objects. Core server, squarely inside ADR-003's " <>
          "denominator, so none of it is excused by scope.",
      owner: @gap_owner
    },
    "input-required-result-non-tool-request" => %{
      class: :real_gap,
      why:
        "2 checks: sep-2322-non-tool-incomplete and wire-schema-valid. MRTR is " <>
          "implemented for tools/call and not for other request types — prompts/get " <>
          "returns a result carrying inputRequests but no `messages`, so it is neither " <>
          "a valid InputRequiredResult nor a valid GetPromptResult. The wire-schema " <>
          "failure is a consequence of the first, not a second defect.",
      owner: @gap_owner
    }
  }

  # ---------------------------------------------------------------------------
  # CLIENT leg, requirement revision 2026-07-28. MES-57.
  #
  # Populated from the run the adjudicator ACCEPTED on this branch. Every entry
  # names a scenario that did not pass under `client_summary` in that run — and
  # every one of the thirty is `auth/*`. That is not a coincidence to be noted
  # in passing, it is the whole shape of the client leg's result: outside the
  # authorization profile this SDK does not fail a single client scenario the
  # frozen set names.
  #
  # `auth/resource-mismatch` is deliberately ABSENT from this table, and the
  # absence is the second half of the census's both-ways refusal: it PASSES, so
  # an entry here would be a stale rationale for something that is not
  # happening. What its pass is worth is a question for the null control, not
  # for this table.
  # ---------------------------------------------------------------------------
  @adr_003_owner "ADR-003 (authorization profile, out of 2.0.0)"

  # The 24 SCORED auth scenarios that do not pass. Scored, and therefore inside
  # the raw `n/32` denominator — which is exactly why the in-scope figure is
  # reported as primary and the raw rate never appears without this exclusion
  # printed beside it.
  @auth_scored_scenarios ~w(
    auth/authorization-server-migration auth/basic-cimd auth/iss-normalized
    auth/iss-not-advertised auth/iss-supported auth/iss-supported-missing
    auth/iss-unexpected auth/iss-wrong-issuer auth/metadata-default
    auth/metadata-issuer-mismatch auth/metadata-var1 auth/metadata-var2
    auth/metadata-var3 auth/offline-access-not-supported
    auth/offline-access-scope auth/pre-registration
    auth/scope-from-scopes-supported auth/scope-from-www-authenticate
    auth/scope-omitted-when-undefined auth/scope-retry-limit auth/scope-step-up
    auth/token-endpoint-auth-basic auth/token-endpoint-auth-none
    auth/token-endpoint-auth-post
  )

  # MES-57 round 4. This reason said the scored auth failures were EMPTIES and
  # that the census marked them `empty`. Both halves were false, and the census
  # said so IN THE SAME OBJECT: `empty: false` on the scenario, `[]` in
  # `empty_scenarios`, `empty | no` in the rendered row. The run had already
  # falsified the plan's expectation in round 1 and every other artefact was
  # corrected then; this string was missed, and it is the one the renderer
  # writes into `docs/conformance/*.json`.
  #
  # Two constraints bind the replacement, and the second is why the obvious
  # rewrite is also wrong:
  #
  #   1. It must state what IS true — a scored failure of a surface that is not
  #      there — and locate the zero cost in ADR-003, which is what actually
  #      makes it free.
  #   2. It is rendered into FIVE censuses (the measurement, three null controls
  #      and the strict-connect probe), so it may assert nothing that is true of
  #      only one of them. "`empty_scenarios` is empty on this leg" would have
  #      been exactly the original defect committed again: it holds for the
  #      measurement and the null-request run and is FALSE for the other three,
  #      where `http-standard-headers` passes on eleven SKIPPED checks and is an
  #      empty. So the claim is scoped to the scenario the reason is attached
  #      to, and it was checked against all 5 x 24 = 120 entries: every one
  #      carries at least one FAILURE check and `empty: false`. Note it is NOT
  #      "no SUCCESS checks" — `auth/authorization-server-migration` has two, in
  #      every run.
  @auth_scored_why "The OAuth 2.1 authorization profile. This SDK's client has no " <>
                     "authorization surface at all — no metadata discovery, no token " <>
                     "acquisition, no WWW-Authenticate handling — so `client_adapter.exs` " <>
                     "does not drive it and the scenario's fail-closed checks score it as " <>
                     "never-emitted. Excluded from 2.0.0 by ADR-003. It is NOT an empty: " <>
                     "it carries at least one real FAILURE check, so the census records " <>
                     "`empty: false` — this is a MEASURED FAILURE OF AN ABSENT SURFACE, " <>
                     "not a scenario that asked nothing, and its cost is zero because " <>
                     "ADR-003 puts the profile out of 2.0.0 and for no other reason. The " <>
                     "absence is NAMED rather than silent: `client_adapter.exs` reports " <>
                     "the scenario as not driven on stderr, and it is enumerated here " <>
                     "rather than counted. SCORED by the frozen set, so it is inside the " <>
                     "raw n/32 and outside the in-scope figure — which is why the two are " <>
                     "never printed without the exclusion between them."

  # The 6 auth scenarios the frozen set does not score. They cost nothing
  # against any denominator and are reported so the coverage gap is visible
  # rather than absent.
  @auth_extension_scenarios ~w(
    auth/client-credentials-basic auth/client-credentials-jwt
    auth/dpop auth/dpop-nonce auth/enterprise-managed-authorization
    auth/wif-jwt-bearer
  )

  @auth_extension_why "An authorization EXTENSION, not scored by the frozen 2026-07-28 set " <>
                        "— extensions are optional by definition (SEP-1730) — and doubly out " <>
                        "of reach here: it is in the extension track AND in the " <>
                        "authorization profile, either of which ADR-003 excludes from 2.0.0. " <>
                        "It runs and is reported for visibility; failing it costs nothing " <>
                        "against the conformance denominator."

  @client_table Map.merge(
                  Map.new(
                    @auth_scored_scenarios,
                    &{&1,
                     %{
                       class: :out_of_scope_adr_003,
                       why: @auth_scored_why,
                       owner: @adr_003_owner
                     }}
                  ),
                  Map.new(
                    @auth_extension_scenarios,
                    &{&1,
                     %{
                       class: :extension,
                       why: @auth_extension_why,
                       owner: @extension_owner
                     }}
                  )
                )

  @harness_table Map.merge(
                   Map.new(
                     @extension_scenarios,
                     &{&1, %{class: :extension, why: @extension_why, owner: @extension_owner}}
                   ),
                   Map.new(@pending_scenarios, fn {id, what} ->
                     {id,
                      %{class: :pending, why: what <> ". " <> @pending_why, owner: @pending_owner}}
                   end)
                 )

  # MES-56 correction round 2, found by the same mechanical question that found
  # B2: where is a value valid only because an input is unique? The table is
  # three sources merged, and `Map.merge/2` resolves a collision silently in
  # favour of the SECOND argument. A scenario named in both `@ours` and
  # `@extension_scenarios` would therefore lose its `:real_gap` entry — owner
  # "MES-58 gap register -> Sprint 6", inside ADR-003's denominator — to an
  # `:extension` entry whose own text says failing it "costs nothing against the
  # conformance denominator". The collapse is silent and its direction is the
  # flattering one, which is B2's sentence in a different file.
  #
  # Nothing downstream can catch it: the census reads this table by id, and the
  # `classification_totals/1` buckets are keyed by CLASS, so a scenario that
  # changed class still appears exactly once and every count still adds up.
  #
  # A compile-time refusal rather than a test, because the table is a literal:
  # if the three sources ever overlap, this file must not compile into an
  # artefact anyone can quote a rate from.
  # MES-57 extends this over the CLIENT table by the same argument. The table is
  # now four sources, not three, and this file is keyed by scenario id ALONE —
  # it has no leg — so a scenario id shared between the two legs would collapse
  # here too, and in the same silent direction. Today no id is shared, and
  # "today no id is shared" is precisely the kind of fact that stops being true
  # without anyone editing this file: the ids come from an upstream frozen set.
  # Checking all three pairs, rather than the one pair that can collide today,
  # is the multiplicity half MES-56 spent two rounds learning to check.
  @collisions [{@ours, @harness_table}, {@ours, @client_table}, {@client_table, @harness_table}]
              |> Enum.flat_map(fn {a, b} ->
                a |> Map.keys() |> Enum.filter(&Map.has_key?(b, &1))
              end)
              |> Enum.uniq()
              |> Enum.sort()

  if @collisions != [] do
    raise "MCP.Conformance.Classification: #{inspect(@collisions)} is classified by more " <>
            "than one of this file's tables. Map.merge/2 resolves a collision silently in " <>
            "favour of its second argument, so one of the two entries would be discarded " <>
            "without a word and the scenario would stop being anyone's to own."
  end

  @table @ours |> Map.merge(@client_table) |> Map.merge(@harness_table)

  @doc "Every class this module recognises."
  @spec classes() :: [atom()]
  def classes, do: @harness_classes ++ @our_classes

  @doc "The classes that restate the harness's own `not_scored` reason rather than our judgement."
  @spec harness_classes() :: [atom()]
  def harness_classes, do: @harness_classes

  @doc "The class each harness `not_scored` reason maps to."
  @spec class_for_harness_reason(String.t()) :: atom() | nil
  def class_for_harness_reason(reason), do: Map.get(@harness_reasons, reason)

  @doc "The whole table, keyed by scenario id."
  @spec table() :: %{String.t() => entry()}
  def table, do: @table

  @doc "The classification for `scenario`, or `nil` if it has none."
  @spec fetch(String.t()) :: entry() | nil
  def fetch(scenario), do: Map.get(@table, scenario)
end

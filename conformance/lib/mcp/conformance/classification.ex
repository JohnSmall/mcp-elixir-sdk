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
  # The table. Server leg, requirement revision 2026-07-28.
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
  @collisions Map.keys(@ours)
              |> Enum.filter(&Map.has_key?(@harness_table, &1))
              |> Enum.sort()

  if @collisions != [] do
    raise "MCP.Conformance.Classification: #{inspect(@collisions)} is classified both by us " <>
            "and by the harness's own reason. Map.merge/2 would keep the harness entry and " <>
            "discard ours silently, so the scenario would stop being anyone's to own."
  end

  @table Map.merge(@ours, @harness_table)

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

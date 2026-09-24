# Controls for C1a's two instruments — the locator and the crosswalk (MES-97).
#
#     mix run conformance/controls/crosswalk_controls.exs noop
#     mix run conformance/controls/crosswalk_controls.exs keying
#     mix run conformance/controls/crosswalk_controls.exs locator
#     mix run conformance/controls/crosswalk_controls.exs pins
#     mix run conformance/controls/crosswalk_controls.exs guards
#     mix run conformance/controls/crosswalk_controls.exs vacuum
#     mix run conformance/controls/crosswalk_controls.exs selectors
#     mix run conformance/controls/crosswalk_controls.exs composition
#     mix run conformance/controls/crosswalk_controls.exs absence
#     mix run conformance/controls/crosswalk_controls.exs totality
#     mix run conformance/controls/crosswalk_controls.exs citations
#     mix run conformance/controls/crosswalk_controls.exs statements
#     mix run conformance/controls/crosswalk_controls.exs all
#
# ORDER IS PART OF THE DESIGN. `noop` runs FIRST and on its own, because a
# regeneration diff means nothing until an unchanged regeneration is known to
# produce an identical file (S8-4). Everything after it rests on that.
#
# WHY A SCRIPT AND NOT AN ExUnit TEST — the same reason B2a and B2b give: these
# mutate authored source files and re-run whole builds, and a file under
# `test/` would move the very unit population MES-88's boundary sweep measures.
# The DECISION LOGIC is unit-tested in `test/conformance/crosswalk_test.exs` and
# `test/conformance/locator_test.exs`, so gate 5 covers it; what lives here is
# the part that needs a mutated tree.
#
# EACH GUARD GETS A POSITIVE CONTROL AND A MUTATION. The positive control shows
# the sweep reached the population at all; only the mutation shows the predicate
# CAN fire. A guard that has never been seen to fire is a promise.

defmodule CrosswalkControls do
  alias MCP.Conformance.{Crosswalk, Locator, MatchKey}

  @harness "/tmp/conf11/node_modules/@modelcontextprotocol/conformance/dist/index.js"

  @client_edges "conformance/data/crosswalk-edges-client.json"
  # MES-105 (C1c-i) established the SERVER-leg file. Every "all the edges files"
  # list below has to carry it or the control silently runs over a smaller
  # crosswalk than the committed one — which is not a red, it is a QUIETER
  # GREEN, and the `drift` pin in the falsification controls is what caught it.
  @server_edges "conformance/data/crosswalk-edges-server.json"
  @edges "conformance/data/crosswalk-edges.json"
  @all_edges [@client_edges, @server_edges, @edges]
  @c1_axes "conformance/data/oc-axes-c1.json"
  # The single emitting site every `WireSchemaValid` row in `@c1_axes` is
  # decomposed at, and the field holding the leg-wide tally over it (MES-116).
  @wsv_site [325_368, 325_721]
  @wsv_tally_key "the_leg_wide_wire_schema_valid_tally_and_how_it_is_checked"
  # MES-117 (C1c-iv-a) — the escalation sweep record and the ticket that authored
  # this slice's bucket-1 rows. The `authored_by` value is what scopes the sweep's
  # population to THIS slice's 34 rather than to the whole leg.
  @sweep_key "the_divergent_despite_agreement_sweep_the_dispatch_asked_for_and_its_measured_zero"
  @this_ticket "MES-117 (C1c-iv-a)"
  # MES-121 (C1c-iv-b) — the none_determinable population, G24, and the sweep over
  # the 29. `@nd_member_modules` is HAND-WRITTEN and deliberately not derived: it
  # is compared set-wise against the committed file's own selector, so it is a pin
  # rather than a copy — it goes red when the file moves and the file goes red
  # when it does.
  @nd_sweep_key "the_divergent_despite_agreement_sweep_over_the_29_and_the_whole_crosswalk_zero_it_earns"
  @nd_ticket "MES-121 (C1c-iv-b)"
  @nd_member_modules [
    "MCP.IntegrationTest/",
    "MCP.Protocol.CapabilitiesTest/",
    "MCP.Protocol.ExtensionsTest/",
    "MCP.Protocol.HeaderMirrorTest/",
    "MCP.ProtocolTest/",
    "MCP.Transport.SSETest/",
    "MCP.Transport.SelfCompatibilityTest/",
    "MCP.Transport.StdioTest/",
    "MCP.Transport.SubscriptionsStreamTest/"
  ]
  @a3_axes "docs/conformance/oc-axes-2026-07-28.json"
  @manifest "docs/conformance/in-scope-2026-07-28.json"
  @denominator "docs/conformance/bucket-0-2026-07-28.json"
  @register "docs/conformance/etcc-register.json"
  @attribution "docs/conformance/etcc-attribution.json"
  @crosswalk_out "docs/conformance/crosswalk-2026-07-28.json"
  @locator_out "docs/conformance/oc-emitting-sites-2026-07-28.json"
  @sites @locator_out

  # HAND-WRITTEN, and deliberately not derived — see the two `selectors`
  # expectations that use them. Both are compared set-wise against the committed
  # file's own selector, so they are pins rather than copies: they go red when
  # the file moves and the file goes red when they do.
  @server_member_modules [
    "MCP.Protocol.CapabilitiesTest/",
    "MCP.Protocol.HeaderMirrorTest/",
    "MCP.Protocol.Messages.DiscoverTest/",
    "MCP.Protocol.MetaTest/",
    "MCP.Protocol.Types.ContentTest/",
    "MCP.Protocol.Types.ResourceTest/",
    "MCP.Protocol.Types.ToolTest/",
    "MCP.ProtocolTest/",
    "MCP.Server.CapabilityHonestyTest/",
    "MCP.Server.DispatchTest/",
    "MCP.Server.ExtensionsNegotiationTest/",
    "MCP.Server.JsonSchema202012Test/",
    "MCP.Server.NotificationCollectorTest/",
    "MCP.Server.SubscriptionsDispatchTest/",
    "MCP.Server.ToolOrderTest/",
    "MCP.Transport.SSETest/",
    "MCP.Transport.SelfCompatibilityTest/",
    "MCP.Transport.StreamableHTTP.ACTest/",
    "MCP.Transport.StreamableHTTPCacheScopeWarningTest/",
    "MCP.Transport.StreamableHTTPStatelessTest/",
    "MCP.Transport.SubscriptionsStreamTest/"
  ]

  @server_check_scenarios [
    "server-stateless",
    "input-required-result-basic-elicitation",
    "input-required-result-basic-list-roots",
    "input-required-result-basic-sampling",
    "input-required-result-capability-check",
    "input-required-result-ignore-extra-params",
    "input-required-result-missing-input-response",
    "input-required-result-multi-round",
    "input-required-result-multiple-input-requests",
    "input-required-result-non-tool-request",
    "input-required-result-request-state",
    "input-required-result-result-type",
    "input-required-result-tampered-state",
    "input-required-result-unsupported-methods",
    "input-required-result-validate-input",
    "completion-complete",
    "prompts-get-embedded-resource",
    "prompts-get-simple",
    "prompts-get-with-args",
    "prompts-get-with-image",
    "prompts-list",
    "resources-list",
    "resources-read-binary",
    "resources-read-text",
    "resources-templates-read",
    "sep-2164-resource-not-found",
    "tools-call-audio",
    "tools-call-embedded-resource",
    "tools-call-error",
    "tools-call-image",
    "tools-call-mixed-content",
    "tools-call-simple-text",
    "tools-call-with-progress",
    "tools-list",
    "caching",
    "dns-rebinding-protection",
    "server-sse-multiple-streams"
  ]

  def run(["noop"]), do: noop()
  def run(["keying"]), do: keying()
  def run(["locator"]), do: locator()
  def run(["pins"]), do: pins()
  def run(["guards"]), do: guards()
  def run(["vacuum"]), do: vacuum()
  def run(["selectors"]), do: selectors()
  def run(["composition"]), do: composition()
  def run(["absence"]), do: absence()
  def run(["totality"]), do: totality()
  def run(["citations"]), do: citations()
  def run(["statements"]), do: statements()
  def run(["wsv_tally"]), do: wsv_tally()
  def run(["sweep"]), do: sweep()
  def run(["legpins"]), do: legpins()
  def run(["g24"]), do: g24()
  def run(["ndsweep"]), do: ndsweep()
  def run(["ndbucket2"]), do: ndbucket2()

  def run(["all"]) do
    noop()
    keying()
    locator()
    pins()
    guards()
    vacuum()
    selectors()
    composition()
    absence()
    totality()
    citations()
    statements()
    wsv_tally()
    sweep()
    legpins()
    g24()
    ndsweep()
    ndbucket2()
  end

  def run(_) do
    IO.puts(
      "usage: noop | keying | locator | pins | guards | vacuum | selectors | composition | absence | totality | citations | statements | wsv_tally | sweep | legpins | g24 | ndsweep | ndbucket2 | all"
    )

    System.halt(2)
  end

  # --- sweep: the divergent_despite_agreement sweep, re-measured -------------
  #
  # MES-117 (C1c-iv-a). The dispatch required the last 34 server members to be
  # swept PER MEMBER against the leg's red checks, and the answer was ZERO. A
  # zero is the easiest result in the world to write down without having looked,
  # so the record is held to three measurements it cannot fake: the population
  # it claims to have swept, the red population it claims to have swept against,
  # and the class count in the artefact itself.
  #
  # THE COMPARISONS LIVE IN ONE NAMED FUNCTION, `sweep_disagreements/2`, and the
  # mutations re-drive THAT — the wsv_tally lesson (MES-116), where a mutation
  # compared inline reduced to `n + 1 != n` and passed over the defect it named.
  defp sweep do
    header("SWEEP — the divergent_despite_agreement sweep record, re-measured (MES-117)")

    srv = read(@server_edges)
    sites = read(@locator_out)
    crosswalk = read(@crosswalk_out)

    record = Map.fetch!(srv, @sweep_key)

    {bad, measured} = sweep_disagreements(record, {srv, sites, crosswalk})

    IO.puts("    members this slice homed, by module:")

    for {m, n} <- Enum.sort(measured.by_module) do
      IO.puts("      #{String.pad_trailing(m, 50)} #{n}")
    end

    IO.puts(
      "    red OC rows on the server leg: #{measured.red_rows} rows / " <>
        "#{measured.red_names} distinct names"
    )

    IO.puts("    `divergent_despite_agreement` rows in the crosswalk: #{measured.divergent}")

    for {what, recorded, m} <- measured.pairs do
      verdict(
        "RECORDED == MEASURED — #{what}: recorded #{inspect(recorded)}, measured #{inspect(m)}",
        recorded == m
      )
    end

    verdict("the sweep record disagrees with the artefacts in NOTHING", bad == [])
    halt_unless(bad == [])

    # THE ROW COUNT AND THE NAME COUNT DIFFER, and the record says so. Without
    # this the sweep could have been run over 15 checks while claiming 19 —
    # three `HttpServerMetaInvalid400` rows and three `RequestMetaInvalid` rows
    # share a name and are separated only by their descriptions.
    verdict(
      "the red population is NOT name-keyable — #{measured.red_rows} rows collapse to " <>
        "#{measured.red_names} names, so the record has to carry both",
      measured.red_rows != measured.red_names
    )

    halt_unless(measured.red_rows != measured.red_names)

    # (1) a per-module count moved by one. In memory, nothing on disk (S8-14).
    [{mod, n} | _] = Enum.sort(measured.by_module)

    bumped =
      update_in(record, ["per_module"], fn ms ->
        Enum.map(ms, &if(&1["module"] == mod, do: %{&1 | "members" => n + 1}, else: &1))
      end)

    {bumped_bad, _} = sweep_disagreements(bumped, {srv, sites, crosswalk})

    verdict(
      "MUTATION — #{mod} recorded at #{n + 1} against a measured #{n}: RE-DRIVEN, the " <>
        "comparison disagrees",
      bumped_bad != []
    )

    halt_unless(bumped_bad != [])

    # (2) A MODULE DROPPED ENTIRELY — the shape a sweep that stopped early would
    # have. The count limb above cannot catch it: every SURVIVING row still
    # agrees, and a check that only compared the rows present would be green
    # over a sweep of six modules claiming seven.
    short =
      update_in(record, ["per_module"], fn ms -> Enum.reject(ms, &(&1["module"] == mod)) end)

    {short_bad, _} = sweep_disagreements(short, {srv, sites, crosswalk})

    verdict(
      "MUTATION — #{mod} dropped from the sweep: RE-DRIVEN, the comparison disagrees " <>
        "(a sweep that stopped early is not a sweep that found nothing)",
      short_bad != []
    )

    halt_unless(short_bad != [])

    # (3) THE CLASS ITSELF. The zero is the record's headline and it is the one
    # figure no edit to this file can move — it is counted in the crosswalk. A
    # planted escalation row must break the claim, or the claim is unfalsifiable
    # prose sitting next to an artefact it never consults.
    planted =
      update_in(crosswalk, ["escalations", "rows"], fn rs ->
        [
          %{
            "escalation" =>
              "divergent_despite_agreement — planted by crosswalk_controls.exs sweep"
          }
          | rs
        ]
      end)

    {planted_bad, _} = sweep_disagreements(record, {srv, sites, planted})

    verdict(
      "MUTATION — one `divergent_despite_agreement` row planted in the crosswalk: RE-DRIVEN, " <>
        "the record's ZERO disagrees",
      planted_bad != []
    )

    halt_unless(planted_bad != [])
  end

  # Every comparison the sweep record makes, in ONE place, returning the
  # disagreements and the measurements. Both the positive control and all three
  # mutations call it, so weakening it reddens the positive control rather than
  # quietly passing the mutations.
  defp sweep_disagreements(record, {srv, sites, crosswalk}) do
    mine =
      srv["declared_unmatched"]
      |> Enum.filter(&(&1["authored_by"] == @this_ticket))
      |> Enum.map(&(&1["member"]["register_key"] |> String.split("/") |> hd()))
      |> Enum.frequencies()

    red =
      Enum.filter(
        sites["rows"],
        &(&1["leg"] == "server" and &1["status_at_accepted_run"] == "FAILURE")
      )

    divergent =
      crosswalk["escalations"]["rows"]
      |> Enum.count(&String.contains?(&1["escalation"] || "", "divergent_despite_agreement"))

    recorded_modules = Map.new(record["per_module"], &{&1["module"], &1["members"]})
    pop = record["the_red_population_swept_against"]

    pairs = [
      {"the modules swept and their member counts", recorded_modules, mine},
      {"red OC rows on the server leg", pop["rows"], length(red)},
      {"distinct red check names", pop["distinct_names"],
       length(Enum.uniq(Enum.map(red, & &1["name"])))},
      {"the red names themselves", pop["names"],
       Enum.sort(Enum.uniq(Enum.map(red, & &1["name"])))},
      {"`divergent_despite_agreement` rows in the crosswalk", 0, divergent}
    ]

    {Enum.reject(pairs, fn {_w, r, m} -> r == m end),
     %{
       by_module: mine,
       red_rows: length(red),
       red_names: length(Enum.uniq(Enum.map(red, & &1["name"]))),
       divergent: divergent,
       pairs: pairs
     }}
  end

  # --- legpins: X10 is not unique by id, and the pin address is the pair -----
  #
  # MES-117. The generator emits one X10 residual per ASSERTED LEG and
  # `required_phrases/2` used to address it by `id` alone. With one leg closed
  # that was indistinguishable from correct; with two it pins BOTH legs' figures
  # onto ONE leg's sentence. This mode measures the shape rather than arguing it.
  defp legpins do
    header("LEG PINS — one X10 per asserted leg, and the pin address is {id, leg} (MES-117)")

    a = read(@crosswalk_out)
    x10 = Enum.filter(a["residuals"], &(&1["id"] == "X10"))

    IO.puts("    X10 residuals in the committed artefact: #{length(x10)}")

    verdict(
      "MORE THAN ONE X10 EXISTS — without this the whole mode is vacuous and would pass " <>
        "over the very defect it is for",
      length(x10) > 1
    )

    halt_unless(length(x10) > 1)

    legs = Enum.map(x10, & &1["leg"])

    verdict(
      "each carries its own `leg` — #{inspect(legs)} — which is what makes {id, leg} an ADDRESS",
      Enum.all?(legs, &is_binary/1) and length(Enum.uniq(legs)) == length(legs)
    )

    halt_unless(Enum.all?(legs, &is_binary/1) and length(Enum.uniq(legs)) == length(legs))

    # THE DEFECT, MEASURED. Resolving by id alone yields ONE index for every
    # leg, so every leg's phrase is required of the FIRST leg's text.
    by_id = Enum.find_index(a["residuals"], &(&1["id"] == "X10"))

    by_pair =
      Map.new(legs, fn leg ->
        {leg, Enum.find_index(a["residuals"], &(&1["id"] == "X10" and &1["leg"] == leg))}
      end)

    IO.puts("    resolved by `id` alone:  #{inspect(Enum.map(legs, fn _ -> by_id end))}")
    IO.puts("    resolved by {id, leg}:   #{inspect(Enum.map(legs, &by_pair[&1]))}")

    verdict(
      "by id alone ALL #{length(legs)} legs resolve to index #{by_id}; by {id, leg} they resolve " <>
        "to #{length(Enum.uniq(Map.values(by_pair)))} distinct indices",
      length(Enum.uniq(Map.values(by_pair))) == length(legs)
    )

    halt_unless(length(Enum.uniq(Map.values(by_pair))) == length(legs))

    # AND THE TWO KINDS OF FAILURE, both shown. Each leg's member figure occurs
    # in ITS OWN text and NOT in the other's — so on this artefact the id-only
    # form is a false RED. Where two legs happened to share a figure it would be
    # a false GREEN instead, and that is the hazard the fix is really for: the
    # second leg's sentence would be pinned by nothing at all.
    for r <- x10 do
      leg = r["leg"]
      n = Enum.find(a["population"]["files"], &(&1["leg_totality"]["leg"] == leg))
      members = n["leg_totality"]["members"]
      phrase = "all #{members} of them"
      others = Enum.reject(x10, &(&1["leg"] == leg))

      verdict(
        "#{leg}: #{inspect(phrase)} is in its OWN X10 text and in no other leg's " <>
          "(so id-only pinning is a false RED here, and a false GREEN wherever two legs agree)",
        String.contains?(r["text"], phrase) and
          Enum.all?(others, &(not String.contains?(&1["text"], phrase)))
      )

      halt_unless(
        String.contains?(r["text"], phrase) and
          Enum.all?(others, &(not String.contains?(&1["text"], phrase)))
      )
    end
  end

  # --- g24: the WHOLE-CROSSWALK totality, and both directions shown ----------
  #
  # MES-121 (C1c-iv-b). G24 set-compares the register's ET-CC universe against
  # the union of every edges file's declared population. Three limbs, and the
  # first is not optional: without the POSITIVE control a guard that refused
  # everything would "pass" both mutations vacuously.
  #
  #   POSITIVE      the unmutated build exits 0 and reports the universe and the
  #                 union as the same set, with the outside-count at zero.
  #   FIRE          one `label: "ET-CC"` row added to the REGISTER whose key no
  #                 edges file carries. Every leg guard reads the ATTRIBUTION
  #                 register and so cannot see it; the per-file stray guard is a
  #                 subset test and the extra key is in no file. G24 alone
  #                 refuses, 282 against 281, naming the key.
  #   DISCRIMINATE  the CONVERSE — an ATTRIBUTION row dropped — and the control
  #                 REPORTS WHICH GUARD ACTUALLY CAUGHT IT rather than asserting
  #                 G24 did. It does not: the register is untouched and the union
  #                 is untouched, so G24 is green and G15a fires, because the
  #                 file now derives a member its own selector no longer denotes.
  #                 That is the property worth having — the guards PARTITION the
  #                 failure space rather than one subsuming the other — and a
  #                 control that only ever showed G24 going red would not
  #                 establish it.
  defp g24 do
    header("G24 — the whole-crosswalk totality, and the two directions it does NOT share")

    require_harness!()

    out = tmp("g24-positive")
    {os_out, status} = os_crosswalk(out, [])
    a = read(out)
    File.rm(out)

    u = a["population"]["outside_the_population"]["whole_crosswalk_totality"]

    IO.puts("  POSITIVE  the unmutated build exits #{status}")
    IO.puts("            universe #{u["universe"]} ET-CC rows, homed #{u["homed"]} members")

    IO.puts(
      "            outside every declared population: " <>
        "#{u["et_cc_members_outside_every_declared_population"]}"
    )

    verdict("the unmutated build exits 0", status == 0)
    halt_unless(status == 0 and String.contains?(os_out, "CROSSWALK"))

    verdict(
      "G24 is PRESENT in the artefact and reports a NON-EMPTY universe — without this the two " <>
        "mutations below would pass over a guard that never ran",
      u["guard"] == "G24" and u["universe"] > 0 and u["homed"] > 0
    )

    halt_unless(u["guard"] == "G24" and u["universe"] > 0 and u["homed"] > 0)

    verdict(
      "and the universe IS the union — #{u["universe"]} against #{u["homed"]}, set-equal in both " <>
        "directions, with the per-file figures never summed",
      u["universe"] == u["homed"] and u["et_cc_members_outside_every_declared_population"] == 0
    )

    halt_unless(u["universe"] == u["homed"])

    # --- FIRE ---------------------------------------------------------------
    reg = read(@register)

    probe =
      reg["rows"]
      |> Enum.find(&(&1["label"] == "ET-CC"))
      |> Map.put("key", "MCP.G24ProbeTest/test an ET-CC row the register has and no file homes")

    mutated_reg = update_in(reg, ["rows"], &(&1 ++ [probe]))
    etcc_after = Enum.count(mutated_reg["rows"], &(&1["label"] == "ET-CC"))
    reg_path = write_tmp("register-g24", mutated_reg)

    IO.puts(
      "\n  FIRE  one `label: \"ET-CC\"` register row whose key no edges file carries: " <>
        "#{etcc_after} against #{u["homed"]}"
    )

    verdict(
      "the mutation really moves the universe by one — #{u["universe"]} -> #{etcc_after}",
      etcc_after == u["universe"] + 1
    )

    halt_unless(etcc_after == u["universe"] + 1)

    try do
      os_refuses(
        "G24  an ET-CC member the register carries and no edges file homes",
        ["G24", "are not the\nsame set", probe["key"]],
        fn out -> os_crosswalk(out, register: reg_path) end
      )
    after
      File.rm(reg_path)
    end

    # AND that it is G24 alone — the leg guards cannot see a register row at all,
    # measured rather than asserted from the code's shape.
    src = read(@attribution)

    unseen =
      for path <- @all_edges, doc = read(path), doc["leg"] != nil do
        {:ok, denoted} =
          Crosswalk.select(doc["the_population_this_file_declares"]["selector"], src)

        {:ok, leg_only} =
          Crosswalk.select(
            %{
              "source" => @attribution,
              "rows_at" => "rows",
              "key_field" => "key",
              "all_of" => [%{"field" => "leg", "test" => "equals", "value" => doc["leg"]}]
            },
            src
          )

        {doc["leg"], length(denoted), length(leg_only)}
      end

    IO.puts("        the leg guards on the SAME mutation, per declared population:")

    for {leg, n, m} <- unseen do
      IO.puts("          #{String.pad_trailing(leg, 20)} G15a #{n}   G22b #{m}")
    end

    verdict(
      "every leg guard is UNMOVED by a register row — all #{length(unseen)} declared populations " <>
        "still agree with their own anchors, because their anchor is the ATTRIBUTION register " <>
        "and not this one. That is why G24 is not entailed by them.",
      unseen != [] and Enum.all?(unseen, fn {_l, n, m} -> n == m end)
    )

    halt_unless(unseen != [] and Enum.all?(unseen, fn {_l, n, m} -> n == m end))

    # --- DISCRIMINATE -------------------------------------------------------
    #
    # The anchor is substituted by RETARGETING, not by editing the repo:
    # `selected!/4` refuses a run whose `--attribution` is not the path the
    # selector NAMES, and all three files are retargeted so the probe does not
    # depend on file order (the lesson the server-leg limb of `totality` records).
    dropped_key = "MCP.Transport.StdioTest/test line buffering handles rapid sequential messages"
    dropped = update_in(src, ["rows"], fn rs -> Enum.reject(rs, &(&1["key"] == dropped_key)) end)

    halt_unless(length(dropped["rows"]) == length(src["rows"]) - 1)

    att_path = write_tmp("attribution-g24-drop", dropped)
    paths = Enum.map(@all_edges, &write_tmp("edges-g24-drop", retarget(read(&1), att_path)))

    IO.puts("\n  DISCRIMINATE  the CONVERSE — one ATTRIBUTION row dropped, register untouched:")
    IO.puts("                #{dropped_key}")

    {text, dstatus} =
      try do
        os_crosswalk(tmp("g24-drop"), attribution: att_path, edges: paths)
      after
        Enum.each([att_path | paths], &File.rm/1)
      end

    fired =
      ["G24", "G22b", "G22a", "G15a", "G15b"]
      |> Enum.filter(&String.contains?(text, &1 <> " —"))

    IO.puts("                exit #{dstatus}; the guard(s) that refused: #{inspect(fired)}")

    verdict(
      "it IS refused, by something — a dropped adjudication must not build",
      dstatus != 0
    )

    halt_unless(dstatus != 0)

    verdict(
      "and the guard that caught it is G15a and NOT G24 — REPORTED rather than predicted. The " <>
        "register still holds its ET-CC rows and the union still holds its members, so G24's " <>
        "two sets are unchanged; what changed is that the file derives a member its own " <>
        "selector no longer denotes. The two guards PARTITION the failure space.",
      fired == ["G15a"]
    )

    halt_unless(fired == ["G15a"])
  end

  # --- ndsweep: the 29 x 21 escalation sweep, re-measured ---------------------
  #
  # MES-121 (C1c-iv-b). C1c-iv-a closed `divergent_despite_agreement` at zero over
  # the SERVER leg and wrote that it had never gone live anywhere; its population
  # was the DECLARED crosswalk, which at that tip was 253 of the 281 (re-measured at
  # 9bdd1e8), and TWENTY-EIGHT of these 29 were outside every declared population by
  # construction. So the class had never been measured over those twenty-eight; the
  # twenty-ninth was C1a's residual member, already this file's declared population
  # of one. This slice swept the full cross-product and this mode
  # holds the record to measurements it cannot fake.
  #
  # THE MEMBER POPULATION IS TAKEN FROM B2b, NOT FROM THE FILE. C1c-iv-a's own
  # sweep control keys on `authored_by == <ticket>` over the file's
  # declared_unmatched rows; here that would be wrong twice over — 8 of the 29 are
  # edge-bearing and carry no such field, and a control whose universe comes out
  # of the file under validation measures LESS when a row is dropped instead of
  # going red (the self-declaring-population defect). The anchor is
  # `leg == none_determinable` in the attribution register.
  #
  # ALL COMPARISONS LIVE IN `nd_sweep_disagreements/2`, and the mutations re-drive
  # THAT — the wsv_tally lesson, where a mutation compared inline reduced to
  # `n + 1 != n` and passed over the defect it named.
  defp ndsweep do
    header("ND SWEEP — the 29 x 21 divergent_despite_agreement sweep, re-measured (MES-121)")

    nd = read(@edges)
    sites = read(@locator_out)
    crosswalk = read(@crosswalk_out)
    att = read(@attribution)

    record = Map.fetch!(nd, @nd_sweep_key)
    ctx = {att, sites, crosswalk}

    {bad, m} = nd_sweep_disagreements(record, ctx)

    # THE MODULE SET, PINNED BOTH WAYS. `@nd_member_modules` is hand-written here
    # and set-compared against the committed file's own selector leaves: the pin
    # goes red when the file moves and the file goes red when the pin does. It is
    # also compared against the modules B2b's own none_determinable rows fall in,
    # which is the limb that catches a tenth module appearing upstream.
    declared_prefixes =
      nd["the_population_this_file_declares"]["selector"]["all_of"]
      |> Enum.flat_map(&(&1["any_of"] || []))
      |> Enum.filter(&(&1["test"] == "starts_with"))
      |> Enum.map(& &1["value"])
      |> Enum.sort()

    from_b2b = m.by_module |> Map.keys() |> Enum.map(&(&1 <> "/")) |> Enum.sort()

    verdict(
      "the #{length(@nd_member_modules)} module prefixes this control pins ARE the file's own " <>
        "selector leaves, compared as a set in both directions",
      Enum.sort(@nd_member_modules) == declared_prefixes
    )

    halt_unless(Enum.sort(@nd_member_modules) == declared_prefixes)

    verdict(
      "and they are the modules B2b's own `none_determinable` rows fall in — so a tenth module " <>
        "appearing upstream reddens here as well as at G22b",
      Enum.sort(@nd_member_modules) == from_b2b
    )

    halt_unless(Enum.sort(@nd_member_modules) == from_b2b)

    verdict(
      "the sweep record is #{@nd_ticket}'s and says so",
      String.contains?(record["what_was_asked"], "C1c-iv-a") and
        String.contains?(nd["owner"], @nd_ticket)
    )

    halt_unless(String.contains?(nd["owner"], @nd_ticket))

    IO.puts("    the none_determinable population per B2b, by module:")

    for {mod, n} <- Enum.sort(m.by_module) do
      IO.puts("      #{String.pad_trailing(mod, 46)} #{n}")
    end

    IO.puts(
      "    non-green OC rows: #{m.red_rows} (#{m.failure_rows} FAILURE + #{m.warning_rows} " <>
        "WARNING) / #{m.red_names} distinct names"
    )

    IO.puts("    candidate pairs: #{m.members} x #{m.red_rows} = #{m.candidates}")
    IO.puts("    `divergent_despite_agreement` rows in the crosswalk: #{m.divergent}")

    for {what, recorded, measured} <- m.pairs do
      verdict(
        "RECORDED == MEASURED — #{what}: recorded #{inspect(recorded)}, measured " <>
          "#{inspect(measured)}",
        recorded == measured
      )
    end

    verdict("the sweep record disagrees with the artefacts in NOTHING", bad == [])
    halt_unless(bad == [])

    # The population is the WHOLE 29 and not the bucket-1 subset, which is the one
    # way this sweep could be quietly narrower than the one it claims.
    verdict(
      "the swept population is the WHOLE #{m.members} and not only the bucket-1 rows " <>
        "(#{m.declared_unmatched} of them) — a sweep over the unmatched rows alone would have " <>
        "missed the #{m.with_edges} edge-bearing members, which are the ones that could reach a " <>
        "check at all",
      m.members > m.declared_unmatched and m.with_edges > 0 and
        m.declared_unmatched + m.with_edges == m.members
    )

    halt_unless(m.declared_unmatched + m.with_edges == m.members)

    # THIS POPULATION IS WIDER THAN C1c-iv-a's, and that is asserted rather than
    # described: its 19 excluded the two WARNINGs on a leg-scoped reading, and a
    # member on no leg inherits neither leg's scoring rule.
    verdict(
      "the red population is WIDER than the server leg's — #{m.red_rows} against " <>
        "#{m.failure_rows}, the two WARNINGs included. A wider population can only make the zero " <>
        "harder.",
      m.red_rows > m.failure_rows and m.warning_rows == 2
    )

    halt_unless(m.red_rows > m.failure_rows)

    verdict(
      "and it is NOT name-keyable — #{m.red_rows} rows collapse to #{m.red_names} names, so the " <>
        "record has to carry both",
      m.red_rows != m.red_names
    )

    halt_unless(m.red_rows != m.red_names)

    # (1) a per-module count moved by one.
    [{mod, n} | _] = Enum.sort(m.by_module)

    bumped =
      update_in(record, ["per_module"], fn ms ->
        Enum.map(ms, &if(&1["module"] == mod, do: %{&1 | "members" => n + 1}, else: &1))
      end)

    {bumped_bad, _} = nd_sweep_disagreements(bumped, ctx)

    verdict(
      "MUTATION — #{mod} recorded at #{n + 1} against a measured #{n}: RE-DRIVEN, the comparison " <>
        "disagrees",
      bumped_bad != []
    )

    halt_unless(bumped_bad != [])

    # (2) a module dropped entirely — the shape a sweep that stopped early has.
    short = update_in(record, ["per_module"], &Enum.reject(&1, fn r -> r["module"] == mod end))
    {short_bad, _} = nd_sweep_disagreements(short, ctx)

    verdict(
      "MUTATION — #{mod} dropped from the sweep: RE-DRIVEN, the comparison disagrees (a sweep " <>
        "that stopped early is not a sweep that found nothing)",
      short_bad != []
    )

    halt_unless(short_bad != [])

    # (3) the candidate count recorded as something other than the product. This
    # is the limb the server leg's sweep record had no field for: a sweep that ran
    # over a subset and reported the full figure.
    lied =
      put_in(record, ["the_cross_product", "candidates_examined"], m.candidates - m.red_rows)

    {lied_bad, _} = nd_sweep_disagreements(lied, ctx)

    verdict(
      "MUTATION — the candidate count recorded one member short of the product: RE-DRIVEN, the " <>
        "comparison disagrees",
      lied_bad != []
    )

    halt_unless(lied_bad != [])

    # (4) THE CLASS ITSELF. The zero is the record's headline and it is the one
    # figure no edit to the edges file can move — it is counted in the crosswalk.
    planted =
      update_in(crosswalk, ["escalations", "rows"], fn rs ->
        [
          %{
            "escalation" =>
              "divergent_despite_agreement — planted by crosswalk_controls.exs ndsweep"
          }
          | rs
        ]
      end)

    {planted_bad, _} = nd_sweep_disagreements(record, {att, sites, planted})

    verdict(
      "MUTATION — one `divergent_despite_agreement` row planted in the crosswalk: RE-DRIVEN, the " <>
        "record's ZERO disagrees",
      planted_bad != []
    )

    halt_unless(planted_bad != [])
  end

  # Every comparison the ND sweep record makes, in ONE place. The positive control
  # and all four mutations call it, so weakening it reddens the positive control
  # rather than quietly passing the mutations.
  defp nd_sweep_disagreements(record, {att, sites, crosswalk}) do
    # The anchor is B2b, NOT the edges file — see the mode's header comment.
    population =
      att["rows"]
      |> Enum.filter(&(&1["leg"] == "none_determinable"))
      |> Enum.map(& &1["key"])

    by_module = population |> Enum.map(&(&1 |> String.split("/") |> hd())) |> Enum.frequencies()

    nd = read(@edges)

    with_edges =
      nd["edges"] |> Enum.map(& &1["member"]["register_key"]) |> Enum.uniq() |> length()

    unmatched = length(nd["declared_unmatched"])

    red = Enum.reject(sites["rows"], &(&1["status_at_accepted_run"] == "SUCCESS"))
    failure = Enum.filter(red, &(&1["status_at_accepted_run"] == "FAILURE"))
    warning = Enum.filter(red, &(&1["status_at_accepted_run"] == "WARNING"))
    names = red |> Enum.map(& &1["name"]) |> Enum.uniq() |> Enum.sort()

    divergent =
      crosswalk["escalations"]["rows"]
      |> Enum.count(&String.contains?(&1["escalation"] || "", "divergent_despite_agreement"))

    recorded_modules = Map.new(record["per_module"], &{&1["module"], &1["members"]})
    pop = record["the_red_population_swept_against"]
    xp = record["the_cross_product"]

    pairs = [
      {"the modules swept and their member counts", recorded_modules, by_module},
      {"the member population, anchored in B2b and not in the edges file", xp["members"],
       length(population)},
      {"non-green OC rows", pop["rows"], length(red)},
      {"FAILURE rows", pop["failure_rows"], length(failure)},
      {"WARNING rows", pop["warning_rows"], length(warning)},
      {"distinct non-green check names", pop["distinct_names"], length(names)},
      {"the names themselves", pop["names"], names},
      {"red rows in the cross-product block", xp["red_rows"], length(red)},
      {"candidates examined IS the product", xp["candidates_examined"],
       length(population) * length(red)},
      {"members reaching a red check", xp["members_reaching_a_red_check"], 0},
      {"`divergent_despite_agreement` rows in the crosswalk", 0, divergent}
    ]

    {Enum.reject(pairs, fn {_w, r, m} -> r == m end),
     %{
       by_module: by_module,
       members: length(population),
       with_edges: with_edges,
       declared_unmatched: unmatched,
       red_rows: length(red),
       failure_rows: length(failure),
       warning_rows: length(warning),
       red_names: length(names),
       candidates: length(population) * length(red),
       divergent: divergent,
       pairs: pairs
     }}
  end

  # --- ndbucket2: the bucket-2 entries this file closed, DERIVED --------------
  #
  # MES-121 (C1c-iv-b). Homing the none_determinable class moved checks out of
  # bucket 2 that no leg-scoped file could reach, and the plan predicted ONE
  # (`ResourcesNotFoundErrorCode`, the one MES-117 had named) where the
  # measurement found FIVE. Both this ticket's plan and C1c-iii's made the same
  # kind of error — a prediction from the checks somebody had already named, over
  # a population nobody had swept — so the remedy is not a better prediction, it
  # is a DERIVATION.
  #
  # THE PREDICATE: a check leaves bucket 2 because of this file iff it is in some
  # file's declared CHECK population and every cell addressing it comes from a
  # member THIS file homes. Set-compared against the file's own list in both
  # directions, so a sixth check closing and one of these five gaining a sibling
  # edge from another file are both red. Keyed on the SET and not on the count:
  # a count reconciles over one check leaving and another entering.
  defp ndbucket2 do
    header("ND BUCKET 2 — the checks this file moved out of bucket 2, derived not listed")

    nd = read(@edges)
    a = read(@crosswalk_out)

    recorded =
      Map.fetch!(nd, "the_bucket_2_entries_this_ticket_closed_and_the_measured_global_delta")

    listed = Enum.sort(recorded["the_five"])

    mine =
      (nd["edges"] ++ nd["declared_unmatched"])
      |> Enum.map(& &1["member"]["register_key"])
      |> MapSet.new()

    declared = MapSet.new(a["population"]["declared_checks"])

    by_tag =
      Enum.group_by(
        a["cells"],
        & &1["tag"],
        &get_in(&1, ["member", "register_key"])
      )

    derived =
      by_tag
      |> Enum.filter(fn {tag, ms} ->
        MapSet.member?(declared, tag) and Enum.all?(ms, &MapSet.member?(mine, &1))
      end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    IO.puts("    checks in a declared population whose ONLY cells come from this file:")
    for t <- derived, do: IO.puts("      #{t}")

    cmp = Crosswalk.set_compare(derived, listed)

    verdict(
      "DERIVED == RECORDED — #{length(derived)} checks, set-compared in both directions against " <>
        "the #{length(listed)} the file lists",
      cmp.equal
    )

    if not cmp.equal do
      IO.puts("      derived and not listed: #{inspect(cmp.missing)}")
      IO.puts("      listed and not derived: #{inspect(cmp.extra)}")
    end

    halt_unless(cmp.equal)

    # NOT VACUOUS: the file addresses more checks than it closed, so the predicate
    # has to discriminate rather than return everything it touches.
    addressed = nd["edges"] |> Enum.map(& &1["tag"]) |> Enum.uniq() |> Enum.sort()

    verdict(
      "the predicate DISCRIMINATES — this file addresses #{length(addressed)} checks and closed " <>
        "#{length(derived)} of them, so `every cell comes from this file` is not another spelling " <>
        "of `this file addresses it`",
      length(addressed) > length(derived) and derived != []
    )

    halt_unless(length(addressed) > length(derived) and derived != [])

    # And each of the five really IS out of bucket 2 in the committed artefact —
    # the derivation's own conclusion, checked against the projection rather than
    # inferred from it.
    b2 = MapSet.new(a["buckets"]["bucket_2"]["checks"])

    still_in = Enum.filter(listed, &MapSet.member?(b2, &1))

    verdict(
      "and none of the #{length(listed)} is in the committed bucket-2 view",
      still_in == []
    )

    halt_unless(still_in == [])

    # MUTATION — the list with one entry removed must go red. Without this the set
    # comparison could be passing over an empty derivation.
    {mcmp, _} = {Crosswalk.set_compare(derived, Enum.drop(listed, 1)), nil}

    verdict(
      "MUTATION — one of the five dropped from the file's list: the set comparison disagrees",
      not mcmp.equal
    )

    halt_unless(not mcmp.equal)

    # MUTATION — a check the file addresses but did NOT close, added to the list.
    intruder = Enum.find(addressed, &(&1 not in listed))
    icmp = Crosswalk.set_compare(derived, Enum.sort([intruder | listed]))

    verdict(
      "MUTATION — #{intruder} added to the list although another file also addresses it: the set " <>
        "comparison disagrees",
      not icmp.equal
    )

    halt_unless(not icmp.equal)
  end

  # --- noop: the control that makes every later diff mean something (S8-4) ---

  defp noop do
    header("NO-OP REGENERATION — unchanged inputs must produce a BYTE-IDENTICAL file")

    require_harness!()

    for {label, committed, regen} <- [
          {"locator", @locator_out, fn out -> run_locator(out) end},
          {"crosswalk", @crosswalk_out, fn out -> run_crosswalk(out) end}
        ] do
      out = tmp("#{label}-noop")
      regen.(out)
      a = File.read!(committed)
      b = File.read!(out)
      File.rm(out)

      if a == b do
        IO.puts("  identical  #{label}  md5 #{md5(a)}  (#{byte_size(a)} bytes)")
      else
        IO.puts("  DIFFERS    #{label}  committed #{md5(a)} vs regenerated #{md5(b)}")
        IO.puts("             The committed artefact is not what its own generator produces.")
        System.halt(1)
      end
    end

    IO.puts("""

      Without this, a later diff could be read either way — as a real change or as
      generator nondeterminism. With it, a diff is a change.
    """)
  end

  # --- keying: BOTH directions, measured on the real 173 ---------------------

  defp keying do
    header("KEYING — the obvious fields MERGE rows; A1's six-field key merges none")

    rows =
      @denominator
      |> read()
      |> Map.fetch!("checks")
      |> Enum.filter(& &1["matchable"])
      |> Enum.map(& &1["key"])

    k = Crosswalk.keying_control(rows)

    IO.puts(
      "  population: the #{k["rows"]} in-denominator rows.  Measure: ROWS LOST (A1's measure).\n"
    )

    for {label, field} <- [
          {"check_id alone", "by_check_id_alone"},
          {"name alone", "by_name_alone"},
          {"description alone", "by_description_alone"},
          {"check_id + name", "by_check_id_and_name"},
          {"the token's five fields", "by_the_token_five"},
          {"A1's six-field key", "by_a1s_six_field_key"}
        ] do
      IO.puts(
        "    #{String.pad_trailing(label, 26)} #{String.pad_leading(to_string(k[field]), 3)} rows lost"
      )
    end

    positive =
      k["by_check_id_alone"] > 0 and k["by_name_alone"] > 0 and k["by_description_alone"] > 0

    negative = k["by_a1s_six_field_key"] == 0

    IO.puts("")

    verdict(
      "POSITIVE — the hazard is real ON THIS POPULATION, not merely quoted from A1",
      positive
    )

    verdict("NEGATIVE — A1's six-field key loses nothing", negative)

    IO.puts("""

      Either direction alone is vacuous. A control that ran only the negative would pass
      over a crosswalk keyed on `id`; one that ran only the positive would not show the
      key in use is sound. A merged row is a match nobody made.
    """)

    halt_unless(positive and negative)

    # And the join actually in use must not merge: two cells may never share a
    # (member, claim, tag) triple.
    cells = @crosswalk_out |> read() |> Map.fetch!("cells")

    triples = Enum.map(cells, &{&1["member"]["register_key"], &1["claim"], &1["tag"]})
    dupes = triples -- Enum.uniq(triples)

    IO.puts(
      "  the crosswalk's own join: #{length(cells)} cells, #{length(Enum.uniq(triples))} distinct (member, claim, tag) triples"
    )

    verdict("no two cells share a triple", dupes == [])
    halt_unless(dupes == [])
  end

  # --- locator: the positive control, and the same control MUTATED ----------

  defp locator do
    header("LOCATOR — A3's 13 hand-cut rows, re-derived mechanically")

    require_harness!()
    {:ok, h} = Locator.load(@harness)
    axes = read(@a3_axes)

    case Locator.positive_control(h, axes) do
      {:ok, n} -> IO.puts("  POSITIVE  all #{n} of A3's excerpts re-derived BYTE-IDENTICAL")
      {:error, m} -> IO.puts("  FAILED    #{inspect(m)}") && System.halt(1)
    end

    # MUTATION 1 — move one committed span. The control must notice.
    moved =
      update_in(axes, ["checks"], fn cs ->
        List.update_at(cs, 0, fn c ->
          [from, to] = c["emitting_site"]["dist_byte_span"]
          put_in(c, ["emitting_site", "dist_byte_span"], [from + 16, to])
        end)
      end)

    shows_failure("MUTATION  one span moved 16 bytes", Locator.positive_control(h, moved))

    # MUTATION 2 — corrupt one committed excerpt's BYTES, leaving the span.
    # This is the one a span-only comparison would miss.
    retyped =
      update_in(axes, ["checks"], fn cs ->
        List.update_at(cs, 0, fn c ->
          Map.put(c, "evaluator_excerpt", c["evaluator_excerpt"] <> " ")
        end)
      end)

    shows_failure(
      "MUTATION  one excerpt's bytes changed, span left alone",
      Locator.positive_control(h, retyped)
    )

    # The rungs, and what each one PINS. A ladder whose rungs all claimed the
    # same thing would not need to be a ladder.
    loc = read(@locator_out)
    IO.puts("\n  ladder over the 173:")

    for {rung, n} <- Enum.sort_by(loc["ladder"]["per_rung"], &(-elem(&1, 1))) do
      IO.puts("    #{String.pad_trailing(rung, 22)} #{String.pad_leading(to_string(n), 3)}")
    end

    IO.puts("""

      The two rungs MES-76 does not name — id_bound_variable (generalising its CONSTANT
      case past a bare literal) and id_table_value — carry #{loc["ladder"]["per_rung"]["id_bound_variable"]} and #{loc["ladder"]["per_rung"]["id_table_value"]} rows.
      Without them those #{loc["ladder"]["per_rung"]["id_bound_variable"] + loc["ladder"]["per_rung"]["id_table_value"]} rows are unresolved, and an artefact that resolved 163 of 173
      while reading as total is the failure this ticket exists to avoid.
    """)

    # The structural test on the prefix rung, shown to matter rather than argued.
    parts = String.split("sep-2243-x-mcp-header-not-empty", "-")

    naive =
      Enum.find(length(parts)..1//-1, fn n ->
        p = parts |> Enum.take(n) |> Enum.join("-")
        Locator.count(h, "`" <> p <> "-${") > 0
      end)

    naive_prefix = parts |> Enum.take(naive) |> Enum.join("-")

    IO.puts(
      "  prefix rung WITHOUT the emitting-position test, on sep-2243-x-mcp-header-not-empty:"
    )

    IO.puts(
      "    resolves on the prefix #{inspect(naive_prefix)} — the harness's own `sep-${e}-todo` scaffolding."
    )

    verdict("the naive prefix search does resolve, and resolves WRONGLY", naive_prefix == "sep")

    row = Enum.find(loc["rows"], &(&1["check_id"] == "sep-2243-x-mcp-header-not-empty"))

    IO.puts(
      "    with the test: rung #{row["rung"]} — #{row["rung_detail"]["table"]}[#{row["rung_detail"]["table_key"]}]"
    )

    verdict(
      "the guarded ladder does NOT take the prefix rung for this row",
      row["rung"] == "id_table_value"
    )

    halt_unless(naive_prefix == "sep" and row["rung"] == "id_table_value")
  end

  # --- pins: the guard on what a resolution CLAIMS to address ---------------
  #
  # MES-97 CR finding. `rung_pins` said "the ROW" for six rows whose own
  # `row_key_matches` said the address that resolved them names a SIBLING. The
  # value was computed and nothing acted on it — which is S9-15's shape exactly,
  # so the control here drives the WHOLE generator rather than the predicate.
  #
  # The mutation is applied to the MECHANISM, not to an input file, because no
  # input can produce the state: it is a disagreement between two fields the
  # generator computes. Nothing on disk is touched — the module is recompiled in
  # this VM and restored in an `after`, so a death mid-run cannot leave the
  # clone mutated (S8-14).

  @locator_src "conformance/lib/mcp/conformance/locator.ex"

  defp pins do
    header("PIN LEVELS — a row may record a coarser pin than it wants, never a finer one")

    require_harness!()

    loc = read(@locator_out)

    IO.puts("  levels over the 173:")

    for {level, n} <- Enum.sort_by(loc["ladder"]["per_pin_level"], &(-elem(&1, 1))) do
      IO.puts("    #{String.pad_trailing(level, 8)} #{String.pad_leading(to_string(n), 3)}")
    end

    by_rung = Enum.count(loc["rows"], &(&1["rung"] in ["id_literal_pair", "id_table_value"]))
    by_level = Enum.count(loc["rows"], &(&1["rung_pin_level"] == "row"))

    IO.puts(
      "\n  counted BY RUNG, row-level would be #{by_rung}; by rung AND metadata it is #{by_level}."
    )

    verdict("the rung alone over-states row-level pinning by exactly 6", by_rung - by_level == 6)
    halt_unless(by_rung - by_level == 6)

    # The six, named, with the bytes that refute the row-level claim.
    six =
      Enum.filter(
        loc["rows"],
        &(&1["rung"] == "id_table_value" and &1["rung_pin_level"] == "loop")
      )

    IO.puts("\n  the six CR measured, now recorded at LOOP:")

    for r <- six do
      suffix = r["name"] |> String.split("_", parts: 2) |> List.last()
      in_site = Enum.any?(r["sites"], &String.contains?(&1["bytes"], suffix))

      IO.puts(
        "    #{String.pad_trailing(r["name"], 46)} key=#{String.pad_trailing(r["rung_detail"]["table_key"], 28)} own suffix in site bytes: #{in_site}"
      )
    end

    verdict(
      "none of the six has its own suffix in the bytes at its site",
      Enum.all?(six, fn r ->
        suffix = r["name"] |> String.split("_", parts: 2) |> List.last()
        not Enum.any?(r["sites"], &String.contains?(&1["bytes"], suffix))
      end)
    )

    # And the four that DO pin the row rest on the ENTRY, whose bytes name them.
    four =
      Enum.filter(
        loc["rows"],
        &(&1["rung"] == "id_table_value" and &1["rung_pin_level"] == "row")
      )

    verdict(
      "each of the four row-level table rows carries an ENTRY whose bytes name it",
      length(four) == 4 and
        Enum.all?(four, fn r ->
          String.contains?(
            r["rung_detail"]["table_entry"]["bytes"],
            r["rung_detail"]["table_key"]
          )
        end)
    )

    halt_unless(length(four) == 4)

    # POSITIVE CONTROL FIRST: the unmutated generator emits. Without it, the
    # refusal below could be a broken harness rather than the mutation.
    out = tmp("pins-positive")
    run_locator(out)
    IO.puts("\n  POSITIVE  the unmutated generator emits (#{byte_size(File.read!(out))} bytes)")
    File.rm(out)

    # MUTATION — make `pin_level/2` claim ROW for every id_table_value row, the
    # exact state CR found, and require the generator to REFUSE it.
    src = File.read!(@locator_src)

    mutated =
      String.replace(
        src,
        "def pin_level(:id_table_value, _meta), do: :loop",
        "def pin_level(:id_table_value, _meta), do: :row"
      )

    if mutated == src do
      IO.puts("  MUTATION COULD NOT BE APPLIED — the clause the control edits has moved.")
      IO.puts("  A mutation that does not mutate is a green that means nothing.")
      System.halt(1)
    end

    refused = tmp("pins-mutated")

    try do
      recompile!(mutated)

      refuses(
        "MUTATION  pin_level/2 claims ROW for every id_table_value row",
        "rows claim a ROW-LEVEL pin while their own rung_detail says",
        fn ->
          run_locator(refused)
        end
      )

      verdict(
        "and nothing was written — the guard runs before the file",
        not File.exists?(refused)
      )

      halt_unless(not File.exists?(refused))
    after
      recompile!(src)
      File.rm(refused)
    end

    # Restored: the same run that just refused now succeeds again.
    back = tmp("pins-restored")
    run_locator(back)
    verdict("the mechanism is restored — the generator emits again", File.exists?(back))
    File.rm(back)

    IO.puts("""

      The guard's predicate is stated independently of `pin_level/2` — it asks whether a
      ROW claim is backed by a row-naming address, whatever computed the claim. So it
      cross-checks that function instead of restating it, and the mutation above is the
      cheapest way the artefact could carry the defect CR found.
    """)
  end

  defp recompile!(source), do: recompile!(source, @locator_src)

  defp recompile!(source, path) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source, path)
  after
    Code.put_compiler_option(:ignore_module_conflict, false)
  end

  # --- guards: every refusal in the crosswalk generator, shown FIRING -------

  defp guards do
    header("GUARDS — each fail-closed condition, mutated and shown to refuse")

    require_harness!()
    # The mutations are applied to the CLIENT file, which is where MES-104's
    # composition ruling put every interesting row; the residual file rides
    # along unmutated on every run, so each refusal below is a refusal over a
    # REAL two-file crosswalk rather than over a single-file one.
    edges = read(@client_edges)
    first = hd(edges["edges"])

    # POSITIVE CONTROL FIRST: the unmutated build succeeds, so a refusal below
    # is the mutation's doing and not a broken harness.
    out = tmp("guard-positive")
    run_crosswalk(out)
    IO.puts("  POSITIVE  the unmutated edges build cleanly (#{byte_size(File.read!(out))} bytes)")
    File.rm(out)

    refuses(
      "1  a tag that does not resolve in A1's manifest (A3 §6 state 2)",
      "did not survive re-derivation",
      fn ->
        build_edges(put_first(edges, Map.put(first, "tag", first["tag"] <> "zzz")))
      end
    )

    refuses(
      "2  a well-formed tag naming a check that does not exist",
      "did not survive re-derivation",
      fn ->
        build_edges(
          put_first(
            edges,
            Map.put(first, "tag", "oc:client/request-metadata/no-such-check/NoSuchCheck")
          )
        )
      end
    )

    refuses("3  an `oc:none` tag used as an EDGE tag", "oc_none_tag_on_an_edge", fn ->
      build_edges(
        put_first(edges, Map.put(first, "tag", "oc:none/no-oc-scenario/CG2-outbound-meta"))
      )
    end)

    refuses(
      "4  an axis name the check's decomposition does not contain",
      "axis_not_in_decomposition",
      fn ->
        build_edges(
          put_first(
            edges,
            Map.put(first, "axes", [%{"axis" => "invented_axis", "verdict" => "agrees"}])
          )
        )
      end
    )

    refuses("5  an axis set that is not the decomposition's WHOLE set", "axes_not_total", fn ->
      two = Enum.find(edges["edges"], &(length(&1["axes"]) > 1))
      build_edges(replace(edges, two, Map.put(two, "axes", [hd(two["axes"])])))
    end)

    refuses("6  one axis named twice", "axis_named_twice", fn ->
      a = hd(first["axes"])
      build_edges(put_first(edges, Map.put(first, "axes", [a, a])))
    end)

    refuses("7  a member that is not ET-CC in the register", "not ET-CC in the register", fn ->
      build_edges(
        put_first(edges, put_in(first, ["member", "register_key"], "MCP.NoSuchTest/test nope"))
      )
    end)

    # MES-104 re-measured this one. The label used to say A3 §6 state 4, and
    # the state-4 guard is what it was written for — but that guard is ENTAILED
    # by G15a (residual X7) and cannot fire. What actually refuses an untagged
    # member is G15a's `extra` limb: the member is in the file and not in the
    # set its selector denotes. The mutation is unchanged and still caught; the
    # label now names the guard that catches it.
    #
    # MES-109 re-cut the PROBE, not the guard. It used to name a specific client
    # member, and C1b-iii homed that member — so the mutation started tripping
    # G14 (declared unmatched twice) and the control reported the wrong guard.
    # That is the failure mode `refuses/3` exists for. The probe became DERIVED:
    # the first ET-CC member the register holds that no edges file carries.
    #
    # MES-121 RE-CUT IT AGAIN, AND FOR THE SAME REASON ONE LEVEL UP — WORTH
    # RECORDING BECAUSE IT IS THE SECOND TIME THIS PROBE EXPIRED AND THE FIRST
    # FIX IS WHAT EXPIRED. `the first ET-CC member no edges file carries` was
    # derived over a `carried` set that unioned only TWO of the three files, so
    # it silently returned a SERVER member once the server file existed, and
    # planting that in the client file tripped G14 rather than G15a. The union
    # being incomplete was survivable while some member really was unhomed; this
    # ticket homes the last of them, so `an ET-CC member nobody carries` is now
    # THE EMPTY SET and no derivation over the real artefacts can produce one.
    # A probe whose premise the tree has falsified cannot be repaired by widening
    # the derivation.
    #
    # SO THE SITUATION IS FABRICATED INSTEAD, and both halves are needed or a
    # different guard answers first: a row is added to a COPY of the register
    # giving ET-CC status to a key no selector denotes (without it the ET-CC
    # stray guard fires — guard 7 above), and the same key is planted in the
    # client file's `declared_unmatched` (without it nothing derives the member).
    # G15a's `extra` limb is then the first guard that can see it. Nothing on
    # disk is written (S8-14).
    refuses("8  a member in the population that its own selector does not denote", "G15a", fn ->
      key = "MCP.G15aProbeTest/test an ET-CC member no file's selector denotes"

      register = read(@register)

      row =
        register["rows"]
        |> Enum.find(&(&1["label"] == "ET-CC"))
        |> Map.put("key", key)

      register_path = write_tmp("register-g15a", update_in(register, ["rows"], &(&1 ++ [row])))

      untagged = %{
        "member" => %{
          "module" => "MCP.G15aProbeTest",
          "test" => "test an ET-CC member no file's selector denotes",
          "register_key" => key
        },
        "tag" => "oc:none/fabricated/MES97-state-4-probe",
        "the_search_that_found_none" => "none — a probe, not an adjudication"
      }

      try do
        build_edges(update_in(edges, ["declared_unmatched"], &[untagged | &1]),
          register: register_path
        )
      after
        File.rm(register_path)
      end
    end)

    refuses(
      "9  an `oc:` token in declared_unmatched — state 1 masquerading as state 3",
      "state 3",
      fn ->
        d = hd(edges["declared_unmatched"])

        build_edges(
          update_in(edges, ["declared_unmatched"], fn [_ | t] ->
            [Map.put(d, "tag", first["tag"]) | t]
          end)
        )
      end
    )

    refuses("10  an edge with no tag at all", "edge_has_no_tag", fn ->
      build_edges(put_first(edges, Map.delete(first, "tag")))
    end)

    refuses("11  an ET verdict outside {green, red}", "bad_et_verdict", fn ->
      build_edges(put_first(edges, Map.put(first, "et_verdict", "amber")))
    end)

    # The axis artefacts must not both claim a check — D4, one fact one home.
    refuses(
      "12  A3's axes and C1's axes decomposing the SAME check (D4)",
      "one fact, two homes",
      fn ->
        a3 = read(@a3_axes)
        c1 = read(@c1_axes)
        clash = update_in(c1, ["checks"], &[hd(a3["checks"]) | &1])
        path = write_tmp("c1-axes", clash)

        try do
          run_crosswalk(tmp("d4"), c1_axes: path)
        after
          File.rm(path)
        end
      end
    )

    # The committed axis spans are addresses into /tmp. Move the bytes.
    refuses(
      "13  a committed axis expr that is not verbatim at its committed span",
      "not verbatim at their committed spans",
      fn ->
        c1 = read(@c1_axes)

        broken =
          update_in(c1, ["checks"], fn cs ->
            List.update_at(cs, 0, fn c ->
              update_in(c, ["axes"], fn ax ->
                List.update_at(ax, 0, &Map.put(&1, "expr", "o===void 1"))
              end)
            end)
          end)

        path = write_tmp("c1-axes", broken)

        try do
          run_crosswalk(tmp("spans"), c1_axes: path)
        after
          File.rm(path)
        end
      end
    )

    # POSITIVE CONTROL, AFTER — added by MES-99 (C3). This mode ran its positive
    # control only BEFORE its thirteen mutations, so "restored green" was never
    # established for it: every mutation here is a temp copy and none should
    # touch the tree, but that is the claim, and an unrun check and a null result
    # are the same artefact.
    back = tmp("guard-restored")
    run_crosswalk(back)
    restored = File.read!(back) == File.read!(@crosswalk_out)
    File.rm(back)

    verdict(
      "RESTORED — the unmutated edges rebuild the committed artefact byte-for-byte",
      restored
    )

    halt_unless(restored)

    IO.puts("""

      Thirteen guards, thirteen refusals, and a positive control on BOTH sides of them.
      Each mutation is the cheapest way the artefact could be wrong in that particular
      way.
    """)
  end

  # --- vacuum: the AC that a wrong artefact satisfied (S9-15 / D3) ----------

  defp vacuum do
    header("VACUUM — the empty crosswalk, which the ORIGINAL AC3 satisfied perfectly")

    require_harness!()
    edges = read(@edges)

    IO.puts("""
      MES-97's AC3 read: 'every one of the 173 appears exactly once as a match target;
      every ET-CC member appears; the unmatched sets are enumerated'. A crosswalk with
      ZERO edges satisfies it perfectly — all 173 fall into bucket 2, all 281 into
      bucket 1, every set enumerated, the arithmetic exact.
    """)

    empty = %{edges | "edges" => [], "declared_unmatched" => []}

    refuses("the empty crosswalk", "declares an EMPTY population", fn -> build_edges(empty) end)

    IO.puts("""
      It refuses because an empty population is a population with nothing to be total
      OVER, and `project/2` will not take a complement without a universe. Emptiness is
      what the guard fires on, which is what makes AC3 an AC (ruling 8).
    """)

    # And the projections themselves refuse, at the function level.
    for {label, arg} <- [
          {"no declared population", %{population: nil, with_edges: []}},
          {"an empty declared population", %{population: [], with_edges: []}}
        ] do
      r1 = Crosswalk.project(:bucket_1, arg)
      r2 = Crosswalk.project(:bucket_2, arg)

      verdict(
        "project/2 refuses bucket 1 and 2 with #{label}",
        match?({:error, _}, r1) and match?({:error, _}, r2)
      )

      halt_unless(match?({:error, _}, r1) and match?({:error, _}, r2))
    end

    # The other half of the vacuum: a set comparison that PASSES on counts.
    a = Crosswalk.set_compare(["a", "b"], ["a", "c"])

    verdict(
      "set_compare catches equal COUNTS over unequal SETS",
      a.equal == false and a.missing == ["b"] and a.extra == ["c"]
    )

    halt_unless(a.equal == false)

    # And the escalation that keeps an all-silent claim out of bucket 5.
    {:ok, e} =
      MatchKey.new_edge(%{
        member: %{module: "M", test: "t"},
        claim: "c",
        oc_key: [
          "client",
          "request-metadata",
          "sep-2575-client-populates-meta",
          "ClientPopulatesMeta",
          "d",
          ""
        ],
        verdicts: %{oc: :green, et: :green},
        axes: [%{axis: "a1", verdict: :silent}, %{axis: "a2", verdict: :silent}]
      })

    {bucket, _attrs, escalation} = Crosswalk.assign(e)
    {:ok, naive, _} = MatchKey.bucket(e)

    IO.puts("\n  an all-silent edge:")
    IO.puts("    MatchKey.bucket/1 alone would file it as bucket #{naive} (shape #{e.shape})")
    IO.puts("    Crosswalk.assign/1 escalates instead: #{String.slice(escalation || "", 0, 60)}…")
    verdict("the all-silent edge is NOT bucketed", is_nil(bucket) and naive == "5")
    halt_unless(is_nil(bucket))
  end

  # --- selectors: the new language, driven against the REAL anchor ----------
  #
  # `test/conformance/crosswalk_test.exs` unit-tests `select/2` on a five-row
  # synthetic source, which is where the decision logic belongs. What that
  # CANNOT show is that the selectors the committed files actually carry denote
  # the populations they claim, over B2b's real 281 rows — a unit passing on
  # five rows says nothing about the anchor this project ships. Both, because
  # neither subsumes the other.

  defp selectors do
    header("SELECTORS — the committed selectors, evaluated against B2b's real 281 rows")

    src = read(@attribution)
    client = read(@client_edges)
    server = read(@server_edges)
    resid = read(@edges)
    sites = read(@sites)

    rows = src["rows"]
    IO.puts("  anchor: #{@attribution} — #{length(rows)} rows\n")

    # POSITIVE, and compared against a set computed a DIFFERENT way: the
    # selector is evaluated by `select/2`, the expectation by `Enum.filter` over
    # the same rows. A selector checked against itself proves nothing.
    tagged? = fn r -> (r["tokens"] || []) != [] or r["contradicts_oc"] != nil end

    # `no_cg?` is written the way the LEAF is written, not the way the data
    # happens to be: `has_key? and == nil`, so that this independently computed
    # expectation would ALSO be empty on a source that dropped the field. An
    # expectation written as `&1["cg"] == nil` would agree with the weaker leaf
    # and the pair below could not separate them.
    no_cg? = fn r -> Map.has_key?(r, "cg") and Map.get(r, "cg") == nil end

    expectations = [
      {"the client file's members", client["the_population_this_file_declares"]["selector"], src,
       rows
       |> Enum.filter(
         &(&1["leg"] == "client" and
             (&1["cg"] in ~w(CG7 CG1 CG2 CG4) or no_cg?.(&1) or tagged?.(&1)))
       )
       |> Enum.map(& &1["key"])},
      # MES-121 (C1c-iv-b). The expectation was `tagged? and leg not in [client,
      # server]`, which was the file's selector until this ticket. Ratified Q2
      # DROPPED the tagged? conjunct and ratified Q1 put a MODULE conjunct in its
      # place, so the expectation is re-cut to match — and it is cut the same way
      # the server entry is, with a HAND-WRITTEN module list pinned set-wise
      # against the file's own leaves just below. Reading the modules out of the
      # file would make this the file compared against itself, which is the
      # objection recorded against that shape twice already.
      #
      # `leg not in ["client", "server"]` is kept as the expectation's own spelling
      # of the COMPLEMENT leaf rather than being simplified to `leg ==
      # "none_determinable"`: the file's selector is the complement form
      # deliberately (a fourth leg value must not be silently pulled in), and an
      # expectation written as the enumeration would agree with a selector that
      # had been weakened to it.
      {"the residual file's members", resid["the_population_this_file_declares"]["selector"], src,
       rows
       |> Enum.filter(fn r ->
         r["leg"] not in ["client", "server"] and
           Enum.any?(@nd_member_modules, &String.starts_with?(r["key"], &1))
       end)
       |> Enum.map(& &1["key"])},
      # MES-105 (C1c-i). The expectation is computed with `String.starts_with?`
      # over the same rows, which is a DIFFERENT route to the same set than
      # `select/2` takes — the point of every entry in this list.
      #
      # MES-116 (C1c-iii) took the module list from NINE to THIRTEEN and made it
      # HAND-WRITTEN here; MES-119 (C1c-iii-b) took it to FOURTEEN with
      # `MCP.Server.JsonSchema202012Test/`, the leg's largest module at 31
      # members, and the pin below is what made that a RED here rather than a
      # quieter green — the control failed on the module before the file's
      # figures were touched. It used to be read out of the file's own selector by
      # `server_modules/1`, which meant the route differed but the LIST did not:
      # a module added to the file arrived in the expectation with it, so the
      # entry could not notice a wrongly-widened member population. That is the
      # objection C1c-ii recorded against doing the same thing for the CHECKS,
      # and it applies here for the same reason. `@server_member_modules` is
      # compared set-wise against the file's own list just below, so the two can
      # no longer drift in EITHER direction: a module added to the file without
      # being added here goes red, and so does the reverse.
      {"the server file's members", server["the_population_this_file_declares"]["selector"], src,
       rows
       |> Enum.filter(fn r ->
         r["leg"] == "server" and
           Enum.any?(@server_member_modules, &String.starts_with?(r["key"], &1))
       end)
       |> Enum.map(& &1["key"])},
      # MES-115 (C1c-ii) took this population from ONE scenario to FIFTEEN and
      # MES-116 (C1c-iii) to THIRTY-FOUR. The list is written out HERE rather
      # than read from the file's own selector, which is the whole point of this
      # expectation: reading it from the file would make the comparison the file
      # against itself. It is the same shape the client entry below has carried
      # since C1b-iii.
      {"the server file's CHECKS", server["the_check_population_this_file_declares"]["selector"],
       sites,
       sites["rows"]
       |> Enum.filter(&(&1["scenario"] in @server_check_scenarios))
       |> Enum.map(& &1["token"])},
      {"the client file's CHECKS", client["the_check_population_this_file_declares"]["selector"],
       sites,
       sites["rows"]
       |> Enum.filter(
         &(&1["scenario"] in [
             "http-custom-headers",
             "http-invalid-tool-headers",
             "http-standard-headers",
             "json-schema-ref-no-deref",
             "request-metadata",
             "sep-2322-client-request-state",
             "tools_call"
           ])
       )
       |> Enum.map(& &1["token"])}
    ]

    for {label, selector, source, expected} <- expectations do
      {:ok, got} = Crosswalk.select(selector, source)
      c = Crosswalk.set_compare(expected, got)

      IO.puts(
        "    #{String.pad_trailing(label, 30)} #{String.pad_leading(to_string(length(got)), 3)} denoted"
      )

      verdict(
        "POSITIVE — #{label}: set-equal to an independently computed set, both directions",
        c.equal
      )

      halt_unless(c.equal)
    end

    # THE PIN THAT MAKES THE TWO HAND-WRITTEN LISTS ABOVE PINS RATHER THAN COPIES.
    # Without it a hand-written list is a second home for the file's own fact (D4)
    # that drifts in silence: the expectations would still be set-equal to a
    # population computed from the STALE list and the entry would go on passing.
    # Compared as SETS in both directions, so a dropped clause and an added one
    # are equally loud.
    for {label, mine, theirs} <- [
          {"the server file's member modules", @server_member_modules, server_modules(server)},
          # MES-121 — the third file's module list, pinned the same way and for the
          # same reason. `server_modules/1` reads the `any_of` leaf out of the
          # selector's `all_of` and works unchanged here: the residual file's
          # selector has the same two-conjunct shape, with the leg leaf in its
          # complement form.
          {"the residual file's member modules", @nd_member_modules, server_modules(resid)},
          {"the server file's check scenarios", @server_check_scenarios,
           server["the_check_population_this_file_declares"]["selector"]["any_of"]
           |> Enum.map(& &1["value"])}
        ] do
      c = Crosswalk.set_compare(mine, theirs)

      IO.puts(
        "    #{String.pad_trailing(label, 30)} #{String.pad_leading(to_string(length(theirs)), 3)} in the file, #{length(mine)} pinned here"
      )

      verdict("PIN — #{label}: the control's list is set-equal to the file's own", c.equal)
      halt_unless(c.equal)
    end

    # THE MUTATION THAT MATTERS, measured on the real anchor rather than argued:
    # `all_of` silently behaving as `any_of` does not error, does not change the
    # selector's shape, and changes the population.
    member_sel = client["the_population_this_file_declares"]["selector"]
    as_any = member_sel |> Map.delete("all_of") |> Map.put("any_of", member_sel["all_of"])

    {:ok, conj} = Crosswalk.select(member_sel, src)
    {:ok, disj} = Crosswalk.select(as_any, src)

    IO.puts("\n  MUTATION  the client file's `all_of` read as `any_of`:")

    IO.puts(
      "    #{length(conj)} members -> #{length(disj)}  (#{length(disj) - length(conj)} more)"
    )

    verdict(
      "the two combinators denote DIFFERENT populations on this anchor",
      length(disj) != length(conj)
    )

    halt_unless(length(disj) != length(conj))

    # And the `equals` value, which is the whole content of the leg conjunct.
    typo =
      update_in(member_sel, ["all_of"], fn [leg | rest] ->
        [Map.put(leg, "value", "cleint") | rest]
      end)

    {:ok, none} = Crosswalk.select(typo, src)

    IO.puts(
      "  MUTATION  one character wrong in the `equals` value: #{length(conj)} -> #{length(none)}"
    )

    verdict("a mistyped value denotes the EMPTY set rather than erroring", none == [])
    halt_unless(none == [])

    # MES-108 (C1b-ii). The two mutations C1b-i's pair could not make, because
    # its `any_of` held ONE `cg` leaf and a dropped leaf is indistinguishable
    # from a renamed one when there is only one. With four leaves both are
    # distinguishable and both change the population by a DIFFERENT amount, so
    # each says something the other does not.
    #
    # A dropped leaf and a mistyped leaf fail the SAME guard (G15a) but they are
    # not the same mistake: a drop silently narrows the declared population and
    # the file's own counts move with it, whereas a typo leaves the counts
    # standing and empties the leaf. Only measuring both on the real anchor says
    # which one a given red is.
    for cg <- ~w(CG1 CG2 CG4 CG7) do
      dropped =
        update_in(member_sel, ["all_of"], fn [leg, %{"any_of" => leaves}] ->
          [leg, %{"any_of" => Enum.reject(leaves, &(&1["value"] == cg))}]
        end)

      {:ok, fewer} = Crosswalk.select(dropped, src)

      IO.puts(
        "  MUTATION  the `#{cg}` leaf dropped from the member `any_of`: " <>
          "#{length(conj)} -> #{length(fewer)}"
      )

      verdict(
        "dropping `#{cg}` denotes a STRICTLY SMALLER population",
        length(fewer) < length(conj)
      )

      halt_unless(length(fewer) < length(conj))
    end

    # And a leaf that is PRESENT but names a CG that does not exist. This is the
    # one a count alone cannot catch in the other direction: the selector still
    # has four leaves and still parses, and the population is exactly the one a
    # dropped leaf gives — so the FILE's declared counts are what tell the two
    # apart, which is why G15a compares the set and not the shape.
    renamed =
      update_in(member_sel, ["all_of"], fn [leg, %{"any_of" => leaves}] ->
        [
          leg,
          %{
            "any_of" =>
              Enum.map(leaves, &if(&1["value"] == "CG1", do: %{&1 | "value" => "CG11"}, else: &1))
          }
        ]
      end)

    {:ok, wrong} = Crosswalk.select(renamed, src)

    IO.puts(
      "  MUTATION  the `CG1` leaf RENAMED to a CG that does not exist: " <>
        "#{length(conj)} -> #{length(wrong)}"
    )

    verdict(
      "a leaf naming an absent `cg` contributes NOTHING rather than erroring",
      length(wrong) < length(conj)
    )

    halt_unless(length(wrong) < length(conj))

    # The CHECK selector gets the same treatment, and its drop is the one that
    # would be invisible without it: remove `http-standard-headers` and the file
    # declares 30 checks instead of 39, bucket 2's universe shrinks with it, and
    # every bucket-2 figure stays internally consistent over the smaller set.
    check_sel = client["the_check_population_this_file_declares"]["selector"]
    {:ok, all_checks} = Crosswalk.select(check_sel, sites)

    without =
      update_in(check_sel, ["any_of"], fn leaves ->
        Enum.reject(leaves, &(&1["value"] == "http-standard-headers"))
      end)

    {:ok, fewer_checks} = Crosswalk.select(without, sites)

    IO.puts(
      "  MUTATION  `http-standard-headers` dropped from the CHECK `any_of`: " <>
        "#{length(all_checks)} -> #{length(fewer_checks)}"
    )

    verdict(
      "dropping a scenario removes exactly its checks from the declared population",
      length(all_checks) - length(fewer_checks) == 9
    )

    halt_unless(length(all_checks) - length(fewer_checks) == 9)

    # --- MES-109 (C1b-iii): the `is_null` leaf, and the ONE decision in it ----
    #
    # The leaf is `has_key?(row, f) and get(row, f) == nil`. The weaker reading
    # `get(row, f) == nil` is indistinguishable from it on the anchor this
    # project ships — all 281 rows carry `cg` — so live data cannot separate
    # them and only this pair can. The second half is what makes the first half
    # a measurement rather than a coincidence.
    is_null_leaf = %{
      "source" => @attribution,
      "rows_at" => "rows",
      "key_field" => "key",
      "all_of" => [
        %{"field" => "leg", "test" => "equals", "value" => "client"},
        %{"field" => "cg", "test" => "is_null"}
      ]
    }

    {:ok, nulls} = Crosswalk.select(is_null_leaf, src)

    expected_nulls =
      rows |> Enum.filter(&(&1["leg"] == "client" and no_cg?.(&1))) |> Enum.map(& &1["key"])

    cn = Crosswalk.set_compare(expected_nulls, nulls)

    IO.puts(
      "\n  IS_NULL  `leg = client AND cg is_null` on the real anchor: #{length(nulls)} denoted"
    )

    verdict(
      "POSITIVE — set-equal to an independently computed set, both directions",
      cn.equal
    )

    halt_unless(cn.equal)

    # THE LOAD-BEARING HALF. Strip the `cg` KEY from every row — not set it to
    # null, REMOVE it — and re-run the same selector against the same machinery.
    # Under the implemented leaf the denotation collapses to nothing and G15a
    # would red naming every member of the file as `extra`. Under
    # `get(row,f) == nil` it would denote ALL of them and the population would
    # be silently re-declared, reconciling perfectly over a universe nobody
    # chose. The two readings differ by 107 rows on this anchor and by 0 on the
    # live data, which is the whole reason this control exists.
    keyless = %{"rows" => Enum.map(rows, &Map.delete(&1, "cg"))}
    {:ok, on_keyless} = Crosswalk.select(is_null_leaf, keyless)

    weaker = fn r -> Map.get(r, "cg") == nil end

    would_be =
      keyless["rows"] |> Enum.filter(&(&1["leg"] == "client" and weaker.(&1))) |> length()

    IO.puts(
      "  MUTATION  the `cg` KEY removed from all #{length(rows)} rows: " <>
        "#{length(nulls)} -> #{length(on_keyless)}   (the weaker `get == nil` reading would give #{would_be})"
    )

    verdict(
      "an ABSENT field denotes NOTHING — fail-closed, so a dropped field reds at G15a " <>
        "instead of re-declaring the population",
      on_keyless == []
    )

    halt_unless(on_keyless == [])

    verdict(
      "and the two readings really are separable — the weaker one denotes #{would_be} here, " <>
        "not 0, so this is a measured difference and not a restatement",
      would_be > 0
    )

    halt_unless(would_be > 0)

    # And the leaf dropped from the file's OWN selector, which measures C1b-iii's
    # "42 new homes, not 55" from the other side — the same route the CG drops
    # above took for C1b-ii's 20.
    without_null =
      update_in(member_sel, ["all_of"], fn [leg, %{"any_of" => leaves}] ->
        [leg, %{"any_of" => Enum.reject(leaves, &(&1["test"] == "is_null"))}]
      end)

    {:ok, no_null} = Crosswalk.select(without_null, src)

    IO.puts(
      "  MUTATION  the `cg is_null` leaf dropped from the member `any_of`: " <>
        "#{length(conj)} -> #{length(no_null)}  (-#{length(conj) - length(no_null)})"
    )

    verdict(
      "dropping it removes 42 members and not 55 — the 13 no-CG rows carrying C1a tokens " <>
        "are still held by the `tokens` limb, which is C1b-iii's new-homes figure derived " <>
        "without counting homes",
      length(conj) - length(no_null) == 42
    )

    halt_unless(length(conj) - length(no_null) == 42)

    # --- MES-105 (C1c-i): the `starts_with` leaf, and the module cut ---------
    #
    # Three things are measured here and none of them is entailed by the
    # positive control above, which only says the selector denotes what an
    # independently written filter denotes.
    #
    #   1. THE LEAF CAN FIRE AND CAN BE WRONG. A one-character change to a
    #      module prefix must empty that leaf, exactly as the `equals` typo
    #      does. A leaf that denoted its population regardless of its value
    #      would pass the positive control.
    #   2. THE TRAILING `/` IS LOAD-BEARING, and by how much. Strip it from
    #      every prefix and `MCP.Transport.StreamableHTTP` stops naming one
    #      module and starts naming two — a widening no count of the declared
    #      population would predict from the selector's shape.
    #   3. THE `leg` CONJUNCT REMOVES SOMETHING. A conjunct entailed by its
    #      neighbours is a guard that cannot fire (S9-21), and this one is not:
    #      two rows outside the server leg carry one of these module prefixes.
    server_sel = server["the_population_this_file_declares"]["selector"]
    {:ok, server_members} = Crosswalk.select(server_sel, src)

    IO.puts("\n  STARTS_WITH  the server file's module cut: #{length(server_members)} denoted")

    for module <- server_modules(server) do
      typoed = replace_prefix(server_sel, module, String.replace_suffix(module, "/", "X/"))
      {:ok, fewer} = Crosswalk.select(typoed, src)

      IO.puts(
        "  MUTATION  one character wrong in the `#{String.trim_trailing(module, "/")}` prefix: " <>
          "#{length(server_members)} -> #{length(fewer)}"
      )

      verdict(
        "a mistyped prefix denotes the EMPTY set for that leaf rather than erroring, " <>
          "so the module really is what the leaf is doing",
        length(fewer) < length(server_members)
      )

      halt_unless(length(fewer) < length(server_members))
    end

    # THE TRAILING SLASH, and the claim it was MEASURED OUT OF. C1c-i's edges
    # file first said the trailing `/` was load-bearing because
    # `MCP.Transport.StreamableHTTP` would otherwise name two modules. Run, the
    # mutation moved the population by ZERO — and it had to, because that string
    # is not one of the prefixes the selector uses: the leaves carry FULL module
    # names, and over all 21 server modules (and all 30 in B2b) NOT ONE is a
    # plain string-prefix of another. So on the shipped anchor the slash removes
    # nothing, the prose was wrong, and both were corrected rather than the
    # control being softened to agree with the claim.
    #
    # It is still kept, and what it buys is stated as what it is: a bound
    # against a module ADDED LATER whose name extends one of these. That case
    # has no live instance, so it is CONSTRUCTED — one synthetic anchor row —
    # and both selectors are run against it. Anything less would be asserting a
    # property of a case nobody has produced, which is the thing this file
    # exists to refuse.
    {:ok, slashless_live} =
      Crosswalk.select(strip_slashes(server_sel), src)

    IO.puts(
      "  MUTATION  the trailing `/` stripped from every module prefix, on the LIVE anchor: " <>
        "#{length(server_members)} -> #{length(slashless_live)}"
    )

    collisions =
      for m <- server_modules(server),
          n <- Enum.map(rows, &(&1["key"] |> String.split("/") |> hd())) |> Enum.uniq(),
          n != String.trim_trailing(m, "/"),
          String.starts_with?(n, String.trim_trailing(m, "/")),
          do: n

    verdict(
      "on THIS anchor the slash removes NOTHING — #{length(collisions)} of B2b's modules " <>
        "extend one of these #{length(server_modules(server))} names, so the earlier claim that it was load-bearing " <>
        "HERE was wrong and is corrected in the file",
      length(slashless_live) == length(server_members) and collisions == []
    )

    halt_unless(length(slashless_live) == length(server_members) and collisions == [])

    # THE CONSTRUCTED CASE. One synthetic row on the server leg whose module
    # EXTENDS a declared one. The slashed selector must refuse it and the
    # slashless one must admit it — both directions on the same fixture, because
    # a fixture that fails to discriminate shows up as a green (S11 note).
    intruder = String.trim_trailing(hd(server_modules(server)), "/") <> "Extra"
    planted = %{"rows" => rows ++ [%{"key" => intruder <> "/test x", "leg" => "server"}]}

    {:ok, strict} = Crosswalk.select(server_sel, planted)
    {:ok, relaxed} = Crosswalk.select(strip_slashes(server_sel), planted)

    IO.puts(
      "  CONSTRUCTED  a synthetic server row in #{intruder}: " <>
        "with the `/` #{length(strict)} denoted, without it #{length(relaxed)}"
    )

    verdict(
      "the trailing `/` REFUSES a module that merely extends a declared name, and the " <>
        "slashless form ADMITS it — the bound the slash actually buys, shown on the one " <>
        "case that can show it",
      length(strict) == length(server_members) and length(relaxed) == length(server_members) + 1
    )

    halt_unless(
      length(strict) == length(server_members) and length(relaxed) == length(server_members) + 1
    )

    # THE `leg` CONJUNCT. Drop it and see whether anything joins. If nothing
    # did, the conjunct would be entailed by the module leaves and could never
    # fire — which is worth knowing either way, so it is MEASURED and the
    # verdict names the rows.
    legless = update_in(server_sel, ["all_of"], fn [_leg, any_of] -> [any_of] end)
    {:ok, without_leg} = Crosswalk.select(legless, src)
    strays = without_leg -- server_members

    IO.puts(
      "  MUTATION  the `leg equals server` conjunct dropped: " <>
        "#{length(server_members)} -> #{length(without_leg)}"
    )

    for k <- strays do
      leg = rows |> Enum.find(&(&1["key"] == k)) |> Map.get("leg")
      IO.puts("      would admit (leg #{inspect(leg)}): #{String.slice(k, 0, 84)}")
    end

    verdict(
      "the `leg` conjunct REMOVES rows the module leaves admit, so it is not a conjunct " <>
        "entailed by its neighbours (S9-21)",
      strays != [] and
        Enum.all?(strays, fn k ->
          rows |> Enum.find(&(&1["key"] == k)) |> Map.get("leg") != "server"
        end)
    )

    halt_unless(strays != [])

    IO.puts("""

      The generator catches every one of them — a population that is not the set its
      selector denotes is G15a, in both directions. What this shows is the SIZE of the
      mistake each one makes on the anchor this project actually ships, which is the
      thing a five-row unit cannot say.

      AND THE DROP FIGURES CONFIRM C1b-ii's OVERLAP MEASUREMENT FROM THE OTHER SIDE.
      B2b attributes 23 rows to CG1 + CG2 + CG4 on the client leg, but C1b-ii homes only
      20 of them, because 3 CG2 rows carry C1a `oc:none` tokens and were already inside
      C1b-i's 45 through the `tokens non_empty_list` limb. Dropping the leaves one at a
      time measures exactly that: CG1 -9, CG2 -10 (not -13 — the three are still held by
      the tokens limb), CG4 -1. 9 + 10 + 1 = 20, the number of new homes, arrived at
      without counting homes. A figure that two independent routes agree on is a figure;
      one route's arithmetic is a claim.

      C1b-iii's figure comes out the same way and the arithmetic closes over the whole
      leg. Dropping `cg is_null` removes 42, not the 55 B2b attributes: the other 13
      carry C1a tokens and the `tokens` limb still holds them. CG7 -27, CG1 -9, CG2 -10,
      CG4 -1, is_null -42 is 89, and the remaining 18 are the C1a rows the `tokens` and
      `contradicts_oc` limbs hold. Read that last step carefully rather than as an
      addition: every one of those 18 ALSO falls in some CG slice (13 no-CG, 3 CG2, 2
      CG7), which is precisely why each contributes nothing to that slice's marginal
      drop and why the marginals sum to 89 and not to 107. The 18 are the overlap the
      generator derives independently at G22a, arrived at here from the other side.
      Every one of these drop figures is measured on the shipped anchor by the same
      machinery that evaluates the committed selector.
    """)
  end

  # The module prefixes the server file's own selector names, read OUT of the
  # committed selector rather than listed here: a second copy would be a second
  # thing to keep true, and the copy is always the one that rots (D4).
  defp server_modules(server) do
    server["the_population_this_file_declares"]["selector"]["all_of"]
    |> Enum.find_value(fn
      %{"any_of" => leaves} -> Enum.map(leaves, & &1["value"])
      _ -> nil
    end)
  end

  defp strip_slashes(selector) do
    update_in(selector, ["all_of"], fn [leg, %{"any_of" => leaves}] ->
      [
        leg,
        %{
          "any_of" =>
            Enum.map(leaves, &Map.update!(&1, "value", fn v -> String.trim_trailing(v, "/") end))
        }
      ]
    end)
  end

  defp replace_prefix(selector, from, to) do
    update_in(selector, ["all_of"], fn [leg, %{"any_of" => leaves}] ->
      [
        leg,
        %{
          "any_of" =>
            Enum.map(leaves, &if(&1["value"] == from, do: %{&1 | "value" => to}, else: &1))
        }
      ]
    end)
  end

  # --- composition: what MES-104's multi-file crosswalk made possible -------
  #
  # G17, G18, G19 and G20 are refusals that could not exist before `--edges`
  # became repeatable and a file could declare its CHECK population. Each gets
  # a positive control — the unmutated two-file build — and a mutation.

  defp composition do
    header("COMPOSITION — the four refusals the two-file crosswalk needs, each shown firing")

    require_harness!()
    client = read(@client_edges)
    resid = read(@edges)
    sites = read(@sites)
    axes = read(@c1_axes)

    out = tmp("composition-positive")
    run_crosswalk(out)
    a = read(out)
    File.rm(out)

    IO.puts("  POSITIVE  the unmutated two-file build succeeds")

    IO.puts(
      "            #{length(a["population"]["files"])} files, #{a["population"]["member_count"]} members, " <>
        "#{a["population"]["declared_check_count"]} declared checks, #{length(a["cells"])} edges"
    )

    # --- G17: one member, one home -----------------------------------------
    #
    # The probe has to get PAST two earlier guards to reach G17, and that is
    # worth stating rather than discovering. Copying a declared_unmatched row
    # into the second file is caught by G14 (a member declared unmatched
    # twice); adding any row to a file its selector does not denote is caught
    # by G15a. So the second file below denotes exactly the one member it
    # carries — `key equals <that member>` — and gives it a DIFFERENT claim, so
    # neither earlier guard has anything to say and the overlap is the only
    # defect left.
    shared = hd(client["edges"])

    probe = %{
      "schema" => "crosswalk-edges/1",
      "the_population_this_file_declares" => %{
        "members" => 1,
        "members_with_edges" => 1,
        "members_declared_unmatched" => 0,
        "checks_addressed" => 1,
        "rule" => "one member, named — a G17 probe",
        "selector" => %{
          "source" => @attribution,
          "rows_at" => "rows",
          "key_field" => "key",
          "all_of" => [
            %{
              "field" => "key",
              "test" => "equals",
              "value" => shared["member"]["register_key"]
            }
          ]
        }
      },
      "edges" => [Map.put(shared, "claim", "a second claim, so G14 has nothing to say")],
      "declared_unmatched" => []
    }

    refuses(
      "G17  the same member declared by BOTH files",
      "G17 — two edges files declare the SAME member",
      fn -> run_two(client, probe) end
    )

    refuses(
      "G14 gets there first when the overlap is a REPEATED declared_unmatched row",
      "G14 — members declared unmatched more than once",
      fn ->
        dup = Map.put(probe, "declared_unmatched", [hd(client["declared_unmatched"])])
        run_two(client, dup)
      end
    )

    # And the same file given twice, which is the cheapest way to double a
    # population without editing anything at all.
    refuses(
      "G17  the same edges FILE given to --edges twice",
      "the same edges file was given twice",
      fn ->
        path = write_tmp("same", client)

        try do
          run_crosswalk(tmp("same-twice"), edges: [path, path])
        after
          File.rm(path)
        end
      end
    )

    # --- G18: the emitting span's provenance --------------------------------
    accepted = Enum.find(axes["checks"], &(&1["emitting_span_provenance"] == "locator_row"))

    rejected =
      Enum.find(axes["checks"], &(&1["emitting_span_provenance"] == "locator_row_rejected"))

    verdict(
      "G18 has BOTH kinds of row on real data — an acceptance and a rejection",
      accepted != nil and rejected != nil
    )

    halt_unless(accepted != nil and rejected != nil)

    IO.puts(
      "            rejected: #{Enum.at(rejected["key"], 3)} — locator rung " <>
        "#{Enum.find(sites["rows"], &(&1["key"] == rejected["key"]))["rung"]} at pin level " <>
        "#{Enum.find(sites["rows"], &(&1["key"] == rejected["key"]))["rung_pin_level"]}"
    )

    refuses(
      "G18  an accepted row whose span the locator does not name",
      "span_is_not_one_the_locator_names",
      fn ->
        run_axes(mutate_axis(axes, accepted["key"], &Map.put(&1, "emitting_byte_span", [0, 10])))
      end
    )

    refuses(
      "G18  a row claiming a provenance that is not one of the two",
      "unknown_emitting_span_provenance",
      fn ->
        run_axes(
          mutate_axis(axes, accepted["key"], &Map.put(&1, "emitting_span_provenance", "trust me"))
        )
      end
    )

    refuses(
      "G18  a rejection of a span the locator DOES pin to the row",
      "rejected_a_row_level_pin",
      fn ->
        run_axes(
          mutate_axis(axes, accepted["key"], fn c ->
            c
            |> Map.put("emitting_span_provenance", "locator_row_rejected")
            |> Map.put("emitting_span_provenance_why", "because")
            |> Map.put("emitting_byte_span", [0, 10])
          end)
        )
      end
    )

    refuses(
      "G18  a rejection that gives no reason",
      "rejection_gives_no_reason",
      fn ->
        run_axes(
          mutate_axis(axes, rejected["key"], &Map.delete(&1, "emitting_span_provenance_why"))
        )
      end
    )

    refuses(
      "G18  a rejection that then uses the very span it rejected",
      "rejection_uses_the_span_it_rejected",
      fn ->
        row = Enum.find(sites["rows"], &(&1["key"] == rejected["key"]))
        span = hd(row["sites"])["byte_span"]
        run_axes(mutate_axis(axes, rejected["key"], &Map.put(&1, "emitting_byte_span", span)))
      end
    )

    # --- the COMPOSED check id, MES-105 (C1c-i) -----------------------------
    #
    # The `server-stateless` RequestMetaInvalid trio emits with a TEMPLATE, and
    # its composed ids occur NOWHERE in the 809 KB build — so the literal guard
    # `the id is verbatim at a span this row names` could not be satisfied by
    # any choice of `check_id_found_in`. `check_id_composition` answers the same
    # question of every PART of the id instead.
    #
    # A weaker guard would have let the rows through, and a weaker guard is
    # exactly what a reader cannot tell from a stronger one by reading a green.
    # So each limb is planted separately and each refusal is required to NAME
    # ITS OWN failure: "it raised" is not "the planted defect was caught".
    composed =
      Enum.find(axes["checks"], &Map.has_key?(&1, "check_id_composition")) ||
        halt_with("no axis row uses `check_id_composition` — this block has nothing to test")

    IO.puts(
      "\n  COMPOSED CHECK ID — #{Enum.at(composed["key"], 2)}\n" <>
        "    template #{inspect(composed["check_id_composition"]["template"])} " <>
        "+ #{inspect(composed["check_id_composition"]["substitution"])}"
    )

    # POSITIVE CONTROL. The unmutated row builds — without it every refusal
    # below could be a refusal of something the row does wrong anyway.
    IO.puts("  POSITIVE  the unmutated composed row builds cleanly")
    run_axes(axes)

    mutate_comp = fn f ->
      run_axes(mutate_axis(axes, composed["key"], &update_in(&1, ["check_id_composition"], f)))
    end

    refuses(
      "COMPOSITION  the substitution changed, so the parts no longer make the id",
      "composition_does_not_yield_the_check_id",
      fn -> mutate_comp.(&Map.put(&1, "substitution", "missing-met")) end
    )

    refuses(
      "COMPOSITION  the template changed, so it is not verbatim in the build",
      "composition_part_not_verbatim",
      fn -> mutate_comp.(&Map.put(&1, "template", "sep-2575-request-meta-invalid-${e.slugg}")) end
    )

    refuses(
      "COMPOSITION  the substitution pointed at a span that does not carry it",
      "composition_part_not_verbatim",
      fn -> mutate_comp.(&Map.put(&1, "substitution_found_in", "evaluator_excerpt")) end
    )

    refuses(
      "COMPOSITION  a span the row does not name",
      "composition_names_no_such_span",
      fn -> mutate_comp.(&Map.put(&1, "substitution_found_in", "context:nowhere")) end
    )

    refuses(
      "COMPOSITION  a hole that occurs zero times — a literal wearing another name",
      "composition_hole_occurs_n_times",
      fn -> mutate_comp.(&Map.put(&1, "hole", "${e.nothing}")) end
    )

    refuses(
      "COMPOSITION  BOTH `check_id_found_in` and `check_id_composition` — two answers, one question",
      "check_id_is_both_located_and_composed",
      fn ->
        run_axes(
          mutate_axis(
            axes,
            composed["key"],
            &Map.put(&1, "check_id_found_in", "evaluator_excerpt")
          )
        )
      end
    )

    # AND THE ONE THAT MATTERS MOST: with the composition removed the row falls
    # back to the LITERAL guard, and the literal guard must refuse it — because
    # the id really is nowhere in the build. If this went green, the composition
    # field would be decoration on a row the old guard already accepted, and
    # every refusal above would be about a field nothing needed.
    refuses(
      "COMPOSITION  the field REMOVED — the literal guard refuses the row, which is why the " <>
        "field exists at all",
      "span_does_not_carry_the_check_id",
      fn ->
        run_axes(mutate_axis(axes, composed["key"], &Map.delete(&1, "check_id_composition")))
      end
    )

    # RESTORED.
    IO.puts(
      "  POSITIVE  the unmutated composed row still builds cleanly, after all seven mutations"
    )

    run_axes(axes)

    # --- G19: a declared check nobody decomposed ----------------------------
    refuses(
      "G19  a DECLARED check with no axis decomposition",
      "DECLARED check population have no axis",
      fn ->
        # It has to be a BUCKET-2 check. Dropping the decomposition of a check
        # that CARRIES an edge is caught earlier, by `cells!` — an edge cannot
        # re-derive without one — so G19's content is exactly the checks with
        # NO edge, which is the set bucket 2 reports. The check stays DECLARED
        # by the client file's selector, so reporting it in bucket 2 would be
        # saying 'we looked and found no ET counterpart' about a check nobody
        # read.
        name =
          a["buckets"]["bucket_2"]["checks"]
          |> Enum.sort()
          |> hd()
          |> String.split("/")
          |> List.last()

        dropped = Enum.find(axes["checks"], &(Enum.at(&1["key"], 3) == name))

        run_axes(
          update_in(axes, ["checks"], fn cs -> Enum.reject(cs, &(&1["key"] == dropped["key"])) end)
        )
      end
    )

    refuses(
      "G19  cells! gets there first when the undecomposed check CARRIES an edge",
      "check_has_no_axis_decomposition",
      fn ->
        edged =
          Enum.find(axes["checks"], fn c ->
            Enum.any?(a["cells"], &(&1["oc_key"] == c["key"]))
          end)

        run_axes(
          update_in(axes, ["checks"], fn cs -> Enum.reject(cs, &(&1["key"] == edged["key"])) end)
        )
      end
    )

    # --- G20: an inherited token lost in transit ----------------------------
    inherited =
      Enum.find(client["declared_unmatched"], fn u ->
        String.starts_with?(u["tag"], "oc:none/no-oc-fixture-case/CG7-static-reachability")
      end)

    verdict("G20 has a live subject — a B2b token carried by a MOVED row", inherited != nil)
    halt_unless(inherited != nil)

    refuses(
      "G20  a moved row whose inherited B2b token has been re-slugged",
      "G20 —",
      fn ->
        reslugged =
          update_in(client, ["declared_unmatched"], fn us ->
            Enum.map(us, fn u ->
              if u == inherited,
                do: Map.put(u, "tag", "oc:none/no-oc-fixture-case/CG7-static-reachability-x"),
                else: u
            end)
          end)

        run_two(reslugged, resid)
      end
    )

    # --- bucket 2: the thing all of this was for ----------------------------
    b2 = a["buckets"]["bucket_2"]

    IO.puts("\n  BUCKET 2 — non-empty for the first time in this project:")

    IO.puts(
      "    #{b2["count"]} of the #{a["population"]["declared_check_count"]} declared checks carry no edge"
    )

    for tag <- b2["checks"], do: IO.puts("      #{tag}")

    verdict("bucket 2 is DECLARED and non-empty", b2["declared"] and b2["count"] > 0)
    halt_unless(b2["declared"] and b2["count"] > 0)

    # THE MUTATION THAT SHOWS IT IS NOT VACUOUS: take the check population away
    # and the same edges report bucket 2 as NOT ASKED, not as zero. That is the
    # difference between C1a's answer and this one.
    #
    # EVERY declaring file, not just the client one. bucket 2's universe is the
    # UNION of the check populations the files declare, so with MES-105's server
    # file also declaring 30 the client-only mutation left a universe standing
    # and the control read 16-of-30 as `not reported`. The property being tested
    # is `no declared universe at all`, and the mutation has to produce that
    # state rather than a smaller one.
    without = tmp("composition-no-checks")
    undeclared = &Map.delete(&1, "the_check_population_this_file_declares")

    run_three_to(
      undeclared.(client),
      undeclared.(read(@server_edges)),
      resid,
      without
    )

    w = read(without)
    File.rm(without)

    IO.puts("\n  the SAME edges with no declared check population:")
    IO.puts("    bucket 2: #{w["buckets"]["bucket_2"]["result"]}")

    verdict(
      "without a declared universe bucket 2 is NOT REPORTED, never zero",
      w["buckets"]["bucket_2"]["declared"] == false
    )

    halt_unless(w["buckets"]["bucket_2"]["declared"] == false)

    # And the counter-mutation: declaring the checks but dropping the edges that
    # cover them grows bucket 2 rather than shrinking the universe. This is the
    # C1a defect restated — under the old derived universe, dropping an edge
    # made the universe smaller and bucket 2 stayed at zero.
    fewer = tmp("composition-fewer-edges")

    # The target has to be a DECLARED check every one of whose edge-bearing
    # members also edges elsewhere — otherwise dropping its edges drops a member
    # out of the population and G15a refuses the mutated file before bucket 2
    # is ever computed. Chosen by that property rather than hard-coded, so a
    # later ticket's edges cannot silently re-aim it (the Access.at(20) lesson).
    edges_per_member = Enum.frequencies_by(a["cells"], & &1["member"]["register_key"])

    # AND EVERY CELL ON IT MUST BE IN THE CLIENT FILE, because the mutation edits
    # only the client file. MES-121 measured this limb missing the hard way: the
    # criterion above selected a check the client file and the none_determinable
    # file BOTH address, dropping the client's edges left the other file's, and
    # bucket 2 did not move — a false RED on a correct tree. The comment two
    # paragraphs up warns about exactly this ("a later ticket's edges cannot
    # silently re-aim it") and the guard against it was one conjunct short.
    client_members =
      MapSet.new(
        Enum.map(
          client["edges"] ++ client["declared_unmatched"],
          & &1["member"]["register_key"]
        )
      )

    dropped_tag =
      Enum.find(Enum.sort(a["population"]["declared_checks"]), fn tag ->
        cells = Enum.filter(a["cells"], &(&1["tag"] == tag))

        cells != [] and
          Enum.all?(cells, &MapSet.member?(client_members, &1["member"]["register_key"])) and
          Enum.all?(cells, fn c ->
            Map.fetch!(edges_per_member, c["member"]["register_key"]) >
              Enum.count(cells, &(&1["member"]["register_key"] == c["member"]["register_key"]))
          end)
      end)

    verdict(
      "a droppable declared check exists — every member of it edges elsewhere too",
      dropped_tag != nil
    )

    halt_unless(dropped_tag != nil)
    IO.puts("            target: #{dropped_tag}")

    run_two_to(
      update_in(client, ["edges"], fn es -> Enum.reject(es, &(&1["tag"] == dropped_tag)) end)
      |> recount(),
      resid,
      fewer
    )

    f = read(fewer)
    File.rm(fewer)

    IO.puts("\n  dropping every edge on ONE declared check:")
    IO.puts("    bucket 2: #{b2["count"]} -> #{f["buckets"]["bucket_2"]["count"]}")

    verdict(
      "a declared check losing its edges GROWS bucket 2 — the universe does not shrink with it",
      f["buckets"]["bucket_2"]["count"] == b2["count"] + 1
    )

    halt_unless(f["buckets"]["bucket_2"]["count"] == b2["count"] + 1)

    IO.puts("""

      C1a's bucket 2 could not have been anything but zero: its universe was the set of
      tags its own edges carried, so the complement was taken inside the set it was taken
      from. The check above is the difference — the same edges, one declaration apart.
    """)
  end

  # The counts block is the file's statement about itself and G15b checks it,
  # so a mutation that changes the rows has to restate them or it is caught by
  # the wrong guard.
  defp recount(doc) do
    members =
      Enum.uniq(
        Enum.map(doc["edges"], & &1["member"]["register_key"]) ++
          Enum.map(doc["declared_unmatched"], & &1["member"]["register_key"])
      )

    update_in(doc, ["the_population_this_file_declares"], fn d ->
      %{
        d
        | "members" => length(members),
          "members_with_edges" =>
            doc["edges"] |> Enum.map(& &1["member"]["register_key"]) |> Enum.uniq() |> length(),
          "members_declared_unmatched" => length(doc["declared_unmatched"]),
          "checks_addressed" => doc["edges"] |> Enum.map(& &1["tag"]) |> Enum.uniq() |> length()
      }
    end)
  end

  defp mutate_axis(axes, key, fun) do
    update_in(axes, ["checks"], fn cs ->
      Enum.map(cs, fn c -> if c["key"] == key, do: fun.(c), else: c end)
    end)
  end

  defp run_axes(axes) do
    path = write_tmp("c1-axes", axes)

    try do
      run_crosswalk(tmp("axes-mutated"), c1_axes: path)
    after
      File.rm(path)
    end
  end

  defp run_two(client, resid), do: run_two_to(client, resid, tmp("two-mutated"))

  # NAMED `two` FOR THE TWO MUTABLE FILES, and it now writes THREE: the server
  # file rides along unmutated, exactly as the residual one does. Before MES-105
  # wired it in, the bucket-2 mutation below built over 54 declared checks while
  # its baseline came from the committed artefact's 84 — so "bucket 2: 30 -> 15"
  # read as a catastrophic mutation when what had happened was that the control
  # stopped building the crosswalk it was measuring. A control that silently
  # builds a SMALLER artefact than the committed one is the quiet failure this
  # whole file is written against.
  defp run_two_to(client, resid, out),
    do: run_three_to(client, read(@server_edges), resid, out)

  # All three files as DOCUMENTS, for the mutations that have to reach more than
  # one of them — bucket 2's universe is the union of what the files declare, so
  # a property about its ABSENCE cannot be produced by editing one file.
  defp run_three_to(client, server, resid, out) do
    paths =
      Enum.map([{"client", client}, {"server", server}, {"resid", resid}], fn {stem, doc} ->
        write_tmp(stem, doc)
      end)

    try do
      run_crosswalk(out, edges: paths)
    after
      Enum.each(paths, &File.rm/1)
    end
  end

  # --- plumbing -------------------------------------------------------------

  defp run_locator(out) do
    Mix.Task.rerun("conformance.locator", [
      "--harness",
      @harness,
      "--denominator",
      @denominator,
      "--axes",
      @a3_axes,
      "-o",
      out
    ])
  end

  defp run_crosswalk(out, overrides \\ []) do
    edges =
      case Keyword.get(overrides, :edges) do
        nil -> @all_edges
        one when is_binary(one) -> [one]
        many when is_list(many) -> many
      end

    Mix.Task.rerun(
      "conformance.crosswalk",
      Enum.flat_map(edges, &["--edges", &1]) ++
        [
          "--manifest",
          @manifest,
          "--denominator",
          @denominator,
          "--register",
          Keyword.get(overrides, :register, @register),
          "--attribution",
          Keyword.get(overrides, :attribution, @attribution),
          "--a3-axes",
          @a3_axes,
          "--c1-axes",
          Keyword.get(overrides, :c1_axes, @c1_axes),
          "--emitting-sites",
          Keyword.get(overrides, :sites, @sites),
          "--harness",
          @harness,
          "-o",
          out
        ]
    )
  end

  # The mutated CLIENT file plus the untouched SERVER and residual ones — the
  # real three-file shape the committed artefact is built from.
  defp build_edges(doc, overrides \\ []) do
    path = write_tmp("edges", doc)
    out = tmp("mutated")

    try do
      run_crosswalk(out, Keyword.merge([edges: [path, @server_edges, @edges]], overrides))
    after
      File.rm(path)
      File.rm(out)
    end
  end

  # The server-file analogue of `build_edges/1`. A separate function rather
  # than a parameter because the two are used side by side and a positional
  # boolean at the call site would be the kind of thing a reader has to
  # decode; the mutated file takes the server slot and the other two are the
  # committed ones.
  defp build_server_edges(doc) do
    path = write_tmp("server-edges", doc)
    out = tmp("mutated-server")

    try do
      run_crosswalk(out, edges: [@client_edges, path, @edges])
    after
      File.rm(path)
      File.rm(out)
    end
  end

  # The residual/none_determinable file's analogue of `build_edges/1`, for the
  # same reason `build_server_edges/1` is its own function: the three are used
  # beside each other and a positional index at the call site would be something
  # a reader has to decode.
  defp build_base_edges(doc) do
    path = write_tmp("base-edges", doc)
    out = tmp("mutated-base")

    try do
      run_crosswalk(out, edges: [@client_edges, @server_edges, path])
    after
      File.rm(path)
      File.rm(out)
    end
  end

  defp put_first(doc, edge), do: update_in(doc, ["edges"], fn [_ | t] -> [edge | t] end)

  defp replace(doc, old, new),
    do: update_in(doc, ["edges"], fn es -> Enum.map(es, &if(&1 == old, do: new, else: &1)) end)

  # `refuses/3` takes the FRAGMENT the refusal must contain. "It raised" is not
  # "the planted defect was caught": a mutation can trip an unrelated guard, or
  # a typo in the control itself, and a bare rescue reads both as success.
  defp refuses(label, expect, fun) do
    fun.()
    IO.puts("  DID NOT REFUSE  #{label}")
    System.halt(1)
  rescue
    e ->
      msg = Exception.message(e)

      if String.contains?(msg, expect) do
        IO.puts("  refused  #{label}\n           #{first_line(msg)}")
      else
        IO.puts("  WRONG GUARD  #{label}")
        IO.puts("           expected the refusal to name: #{inspect(expect)}")
        IO.puts("           got: #{first_line(msg)}")
        System.halt(1)
      end
  end

  defp shows_failure(label, {:error, detail}) do
    IO.puts("  #{label}\n           control failed, as it must: #{first_line(inspect(detail))}")
  end

  defp shows_failure(label, {:ok, n}) do
    IO.puts(
      "  #{label}\n           DID NOT FAIL — the control returned {:ok, #{n}} over a mutated artefact."
    )

    System.halt(1)
  end

  # --- absence: the two ZEROS C1b-ii's bucket-1 records rest on ---------------
  #
  # MES-108. Two `declared_unmatched` records assert that a search over A1's
  # manifest returned NOTHING, and a zero is the one result that looks identical
  # whether the search ran or not. So each gets both halves (A6):
  #
  #   POSITIVE CONTROL  the same predicate machinery over the same 175 rows
  #                     returns a non-zero for terms known to be present, so the
  #                     sweep demonstrably REACHED the population.
  #   MUTATION          the predicate itself is replaced by one that MUST match,
  #                     and is required to go non-zero. Without this, a sweep
  #                     that silently read an empty row set would pass the
  #                     positive control too — `Enum.filter` over `[]` is `[]`
  #                     for every predicate, including the ones that "work".
  #
  # The mutation is the limb that matters and it is the easy one to leave out:
  # a positive control run on DIFFERENT terms shares the row set but not the
  # predicate path, so it cannot distinguish "this term is absent" from "this
  # matcher cannot fire".

  # THE SEARCHED TEXT IS A1's SIX-FIELD KEY, joined with " | " — leg, scenario,
  # check_id, name, description, discriminator. Not a four-field subset: the
  # registry's `population.fields` says six, and MES-109 measured the two apart
  # the hard way. `(?i)capabilit` returns 12 over the six and 11 over the four,
  # so a pattern calibrated on one field set and re-run over the other silently
  # changes its own population — which is why the control compares the RECORDED
  # control figures against the measured ones rather than only checking they are
  # non-zero. That comparison is what caught it.
  #
  # The separator is load-bearing too: several registry patterns use
  # `[^|]{0,40}` to mean "within this row's own field", and that only means
  # anything if the fields are actually delimited.
  @searched_fields ~w(leg scenario check_id name description discriminator)

  defp absence do
    header("ABSENCE — every registered search re-run over its own named population")

    # MES-109 (C1b-iii) rewrote this from a HAND-LISTED PAIR to a sweep over the
    # registry itself. The old form named two patterns in the control and drove
    # them; a third record added to an edges file would have been outside it
    # without anyone noticing, which is the self-declaring-population defect.
    # The universe is now the `absence_searches` block of every edges file
    # given, and the id resolution in both directions is the generator's (G23c),
    # so an entry the control does not reach is an entry no row names.
    rows = manifest_rows()
    halt_unless(length(rows) == 175)

    entries =
      Enum.flat_map(@all_edges, fn path ->
        Enum.map(read(path)["absence_searches"] || [], &{path, &1})
      end)

    IO.puts("  #{length(entries)} registered searches across #{length(@all_edges)} edges files")

    IO.puts("  manifest population: #{@manifest} — #{length(rows)} check rows\n")

    halt_unless(entries != [])

    for {path, e} <- entries do
      {population_label, hits, total} = run_search(e, rows)

      IO.puts("  #{e["id"]}  #{e["kind"]}  — #{population_label}")
      IO.puts("    #{e["pattern"]} -> #{hits}")

      verdict("#{e["id"]}: THE ZERO, re-measured here and not read off the file", hits == 0)
      halt_unless(hits == 0)

      verdict(
        "#{e["id"]}: and the file RECORDS that zero — a registry entry is a search that found none",
        e["hits"] == 0
      )

      halt_unless(e["hits"] == 0)

      # POSITIVE CONTROL — the entry's OWN controls, re-run here. The entry
      # names them, so a search whose controls were chosen to be vacuous is
      # visible in the file rather than hidden in this script.
      pcs =
        for c <- e["positive_controls"], do: {c["term"], elem(run_pattern(e, c["term"], rows), 0)}

      IO.puts(
        "    positive control, same population same machinery: " <>
          Enum.map_join(pcs, ", ", fn {t, n} -> "#{t} -> #{n}" end)
      )

      verdict(
        "#{e["id"]}: the sweep REACHED the population — the zero is the content's, not the sweep's",
        pcs != [] and Enum.all?(pcs, fn {_t, n} -> n > 0 end)
      )

      halt_unless(pcs != [] and Enum.all?(pcs, fn {_t, n} -> n > 0 end))

      # AND the file's recorded control figures must be the ones measured here.
      # A positive control whose number was typed rather than measured is the
      # same defect one level down.
      recorded = Enum.map(e["positive_controls"], &{&1["term"], &1["hits"]})

      verdict(
        "#{e["id"]}: the recorded control figures ARE the measured ones",
        recorded == pcs
      )

      halt_unless(recorded == pcs)

      # MUTATION — a predicate that cannot fail to match.
      {_l, all, _t} = run_search(%{e | "pattern" => "(?s)."}, rows)

      IO.puts("    mutation, a predicate that must match everything: (?s). -> #{all}")

      verdict(
        "#{e["id"]}: the matcher CAN fire, over the whole population (#{total})",
        all == total
      )

      halt_unless(all == total)

      verdict("#{e["id"]}: names a near miss", is_binary(e["near_miss"]) and e["near_miss"] != "")
      halt_unless(is_binary(e["near_miss"]) and e["near_miss"] != "")

      # The LIST form's D4 guard, on every entry that uses it.
      restrict_values!(path, e)

      IO.puts("    (#{path})\n")
    end

    restrict_values_mutation(entries, rows)

    # THE KINDS, counted rather than named. There were two when this was written
    # and MES-105 added three more; a control that asserted "exactly two" would
    # have gone red on a correct file, and one that asserted "at least two"
    # would stop noticing a kind that quietly vanished. So the histogram is
    # PRINTED, and what is asserted is that no kind is the only kind — which is
    # the property the original pair was really about.
    kinds = entries |> Enum.frequencies_by(fn {_p, e} -> e["kind"] end) |> Enum.sort()

    IO.puts("  `oc:none` reason slugs in use, and how many searches each has:")
    for {k, n} <- kinds, do: IO.puts("    #{String.pad_trailing(k, 30)} #{n}")

    verdict(
      "every registered search's kind is EXERCISED and none is the only one — the slugs are " <>
        "kept apart by use and not only by convention (#{length(kinds)} kinds over " <>
        "#{length(entries)} searches)",
      length(kinds) > 1 and Enum.all?(kinds, fn {_k, n} -> n > 0 end)
    )

    halt_unless(length(kinds) > 1)

    # AND every kind a ROW uses is a kind some ENTRY declares, in both
    # directions. G23d compares them per row; this is the set comparison, which
    # catches a slug that has no search behind it at all.
    row_kinds =
      @all_edges
      |> Enum.flat_map(fn path ->
        read(path)["declared_unmatched"]
        |> Enum.map(&(&1["tag"] |> String.split("/") |> Enum.at(1)))
      end)
      |> Enum.uniq()
      |> Enum.sort()

    entry_kinds = kinds |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    verdict(
      "the slugs the ROWS use and the kinds the ENTRIES declare are the same set: " <>
        "#{inspect(row_kinds)}",
      row_kinds == entry_kinds
    )

    halt_unless(row_kinds == entry_kinds)

    near_miss_census()
  end

  # A registry entry names its own population, and there are two kinds. A
  # `no-oc-scenario` search runs over A1's 175 manifest rows; a
  # `no-oc-fixture-case` search runs over a BYTE SPAN of the pinned harness
  # build, because the question is what a fixture contains and the fixture is
  # code. Both go through one function so a kind the control does not handle is
  # a crash rather than a silent skip.
  defp run_search(e, rows), do: run_pattern_labelled(e, e["pattern"], rows)

  defp run_pattern(e, pattern, rows) do
    {_l, n, t} = run_pattern_labelled(e, pattern, rows)
    {n, t}
  end

  defp run_pattern_labelled(e, pattern, rows) do
    re = Regex.compile!(pattern)

    case e["population"] do
      %{"kind" => "manifest_rows"} = p ->
        pop = restrict(e, rows)

        # THE ENTRY'S OWN ROW COUNT, CHECKED. It is a figure in a committed file
        # and nothing re-derived it before MES-105; an entry claiming to sweep
        # 119 rows while sweeping 175 would get a zero that was easier than the
        # one it claimed, and the difference is invisible in the output.
        if length(pop) != p["rows"] do
          IO.puts("  #{e["id"]}: RECORDS #{p["rows"]} rows, this run restricts to #{length(pop)}")
          System.halt(1)
        end

        {"#{length(pop)} manifest rows#{restrict_label(p["restrict"])}", length(sweep(pop, re)),
         length(pop)}

      %{"kind" => "harness_bytes", "byte_span" => [from, to]} ->
        text = harness_bytes(from, to)
        # `byte_size`, not `String.length`. `Regex.compile!/1` without the `u`
        # modifier matches in BYTE mode, so the `(?s).` mutation returns one hit
        # per BYTE and a grapheme count would be 6 short over this span's
        # non-ASCII (measured: 5104 graphemes, 5110 bytes). Comparing the
        # mutation against the wrong unit would have made the one limb that
        # proves the matcher can fire fail on a correct search.
        {"harness bytes [#{from},#{to}]", length(Regex.scan(re, text)), byte_size(text)}

      other ->
        IO.puts("  UNKNOWN POPULATION KIND in #{e["id"]}: #{inspect(other)}")
        System.halt(1)
    end
  end

  # `restrict` — the SUB-POPULATION an entry declares, applied here rather than
  # recognised from a label. MES-105 (C1c-i) introduced it because the server
  # leg needs three kinds of zero and they are not interchangeable:
  # `no-oc-scenario` means no such check ANYWHERE and sweeps all 175;
  # `no-oc-server-check` means none on OUR leg and sweeps the 119 server rows,
  # because the client-leg counterparts it names in its near miss would
  # otherwise come back as hits; `no-oc-check-in-this-scenario` means none among
  # the checks the file DECLARES and sweeps those. Sweeping all 175 for the last
  # two would return their own counterparts and the entry would have to explain
  # away a zero it could not get.
  #
  # It is a {field, value} pair and not a name, so a control cannot be written
  # that agrees with a label while restricting to something else, and an entry
  # naming a field the rows do not carry restricts to NOTHING — which then fails
  # the row-count check above rather than passing with an easy zero.
  #
  # MES-115 (C1c-ii) adds the LIST form, `{field, values}`. It exists because the
  # server file's declared check population stopped being one scenario: C1c-ii
  # declares fifteen (`server-stateless` plus the fourteen MRTR ones), and a
  # `no-oc-check-in-this-scenario` zero has to be swept over the population its
  # own row's claim quantifies over. A single `{field, value}` cannot name that
  # set, and the alternative — leaving SRV02 and SRV07 measured over 30 of 66 —
  # is a zero that is easier than the claim it carries.
  #
  # AND IT IS NOT A SECOND COPY OF THE SCENARIO LIST (D4). `restrict_values!/2`
  # below requires the `values` set to EQUAL the file's own check-selector
  # scenario set, read from the file the entry lives in. So the list cannot
  # drift from the declaration it is supposed to track: widen the selector
  # without widening the search and the control halts; widen the search without
  # widening the selector and it halts too.
  # THE MUTATION for the list form, and it has to show BOTH failure directions —
  # a guard that only ever fires one way is half a guard. Nothing is written to
  # disk: the entry and the file are mutated IN MEMORY (S8-14), so a seat death
  # mid-run cannot leave the tree changed.
  #
  # It also carries its own POSITIVE limb. Without one, a run in which NO entry
  # used the list form would print two green mutation lines about a predicate
  # that never ran (S9-15's vacuum), so the number of list-form entries is
  # asserted to be non-zero first.
  defp restrict_values_mutation(entries, rows) do
    users =
      Enum.filter(entries, fn {_p, e} ->
        match?(%{"field" => "scenario", "values" => _}, get_in(e, ["population", "restrict"]))
      end)

    verdict(
      "the LIST restrict form is USED — #{length(users)} entries, so the D4 guard above ran " <>
        "over something (without this a run with none would print greens for a predicate that " <>
        "never fired)",
      users != []
    )

    halt_unless(users != [])

    {path, e} = hd(users)
    vs = get_in(e, ["population", "restrict", "values"])

    # (a) the list DROPS a scenario the selector declares.
    short = put_in(e, ["population", "restrict", "values"], tl(vs))
    dropped = restrict_values_fires?(path, short)

    # (b) the list ADDS one the selector does not declare.
    long = put_in(e, ["population", "restrict", "values"], ["not-a-scenario" | vs])
    added = restrict_values_fires?(path, long)

    # (c) and the unmutated entry does NOT fire — the control's positive limb.
    clean = restrict_values_fires?(path, e)

    IO.puts(
      "    mutation on #{e["id"]}: drop a value -> #{fired(dropped)}, " <>
        "add one -> #{fired(added)}, unmutated -> #{fired(clean)}"
    )

    verdict(
      "the D4 guard fires BOTH ways and is quiet on the real entry — a list that has drifted " <>
        "from the selector is caught whichever direction it drifted",
      dropped and added and not clean
    )

    halt_unless(dropped and added and not clean)

    # AND the mutation has to MOVE the population it sweeps, or the guard could
    # be right for a reason that has nothing to do with the rows.
    n_clean = length(restrict(e, rows))
    n_short = length(restrict(short, rows))

    verdict(
      "and the dropped value really does shrink the swept population (#{n_clean} -> #{n_short})",
      n_short < n_clean
    )

    halt_unless(n_short < n_clean)
  end

  defp fired(true), do: "FIRED"
  defp fired(false), do: "quiet"

  # `restrict_values!/2` halts, which is what it is for; to OBSERVE it we need
  # it to return instead. The predicate is re-expressed here rather than the
  # guard being weakened to return a boolean: a guard that can be asked "would
  # you fire?" is a guard with two code paths, and the control would then attest
  # the one nothing depends on.
  defp restrict_values_fires?(path, e) do
    declared =
      read(path)
      |> get_in(["the_check_population_this_file_declares", "selector", "any_of"])
      |> Kernel.||([])
      |> Enum.filter(&(&1["field"] == "scenario" and &1["test"] == "equals"))
      |> Enum.map(& &1["value"])
      |> Enum.sort()

    vs = get_in(e, ["population", "restrict", "values"])
    not (Enum.sort(vs) == declared and declared != [])
  end

  defp restrict(e, rows) do
    case get_in(e, ["population", "restrict"]) do
      nil ->
        rows

      %{"field" => f, "value" => v} ->
        Enum.filter(rows, &(Map.get(&1, f) == v))

      %{"field" => f, "values" => vs} when is_list(vs) ->
        Enum.filter(rows, &(Map.get(&1, f) in vs))

      other ->
        halt_with("#{e["id"]}: unknown population restrict #{inspect(other)}")
    end
  end

  defp restrict_label(nil), do: ""
  defp restrict_label(%{"field" => f, "value" => v}), do: " where #{f} = #{v}"

  defp restrict_label(%{"field" => f, "values" => vs}),
    do: " where #{f} in {#{length(vs)} values}"

  # THE D4 GUARD ON THE LIST FORM. A `values` list is a population declaration,
  # and this file already holds one: the check selector's `any_of`. Two copies
  # of one fact is the defect D4 names, so the copies are required to be the
  # SAME SET rather than merely to look alike — read out of the same document,
  # compared as sets, in both directions.
  #
  # Scoped to the entries that USE the list form. An entry with no `restrict`,
  # or with the scalar form, declares no scenario set and there is nothing to
  # compare it against; saying so is the alternative to a vacuous pass.
  defp restrict_values!(path, e) do
    case get_in(e, ["population", "restrict"]) do
      %{"field" => "scenario", "values" => vs} ->
        declared =
          read(path)
          |> get_in(["the_check_population_this_file_declares", "selector", "any_of"])
          |> Kernel.||([])
          |> Enum.filter(&(&1["field"] == "scenario" and &1["test"] == "equals"))
          |> Enum.map(& &1["value"])
          |> Enum.sort()

        same = Enum.sort(vs) == declared and declared != []

        verdict(
          "#{e["id"]}: the `values` list IS the file's own check-selector scenario set — " <>
            "#{length(vs)} values, compared as a set in both directions (D4)",
          same
        )

        halt_unless(same)

      _ ->
        :ok
    end
  end

  defp halt_with(msg) do
    IO.puts("  " <> msg)
    System.halt(1)
  end

  defp harness_bytes(from, to) do
    require_harness!()
    {:ok, h} = Locator.load(@harness)
    Locator.bytes(h, {from, to})
  end

  # The near miss C1b-ii records against the CG2 zero, MEASURED rather than
  # quoted — and it is the figure cg-reconciliation.md §2 states as "seven".
  #
  # ONE FACT, READ ONCE. The two censuses' `expected` blocks are the SAME
  # frozen set and that is asserted here rather than assumed: reading the
  # figure out of both and printing two agreeing lines would look like two
  # measurements corroborating each other, when it is one datum shown twice.
  # The agreement is worth pinning, but as an identity, not as corroboration.
  defp near_miss_census do
    client_expected = read("docs/conformance/client-2026-07-28.json")["expected"]
    server_expected = read("docs/conformance/server-2026-07-28.json")["expected"]

    verdict(
      "the two censuses carry the SAME frozen `expected` block — so this is one fact, not two",
      client_expected == server_expected
    )

    halt_unless(client_expected == server_expected)

    ns = client_expected["not_scored"]
    ext = Enum.filter(ns, &(&1["reason"] == "extension"))
    on_client = Enum.filter(ns, &(&1["leg"] == "client"))
    ext_on_client = Enum.filter(on_client, &(&1["reason"] == "extension"))

    IO.puts(
      "  near miss: #{length(ns)} not_scored entries, #{length(ext)} carry `extension` " <>
        "(#{length(on_client)} entries sit on the client leg, #{length(ext_on_client)} of them `extension`)"
    )

    verdict(
      "the `extension` count is 16, NOT the 7 cg-reconciliation.md §2 states",
      length(ext) == 16
    )

    halt_unless(length(ext) == 16)

    # WHERE THE 7 CAME FROM — named, because a wrong figure with no account of
    # its origin gets re-derived the same way by the next reader.
    verdict(
      "7 is the CLIENT LEG's not_scored ENTRY count, and only 6 of those 7 carry `extension`",
      length(on_client) == 7 and length(ext_on_client) == 6
    )

    halt_unless(length(on_client) == 7 and length(ext_on_client) == 6)

    IO.puts("""

      Every zero stands, and every one is now a zero with a reach shown and a matcher
      shown able to fire. The near-miss figure does NOT stand as written elsewhere:
      cg-reconciliation.md §2 says `"reason": "extension"` sits on "seven" not_scored
      scenarios, and it sits on SIXTEEN — 6 on the client leg (`auth/*`) and 10 on the
      server leg (`tasks-*`). Seven is the client leg's not_scored ENTRY count, of which
      only 6 carry that reason; the seventh is `added-after-release`. The censuses have
      not moved since MES-57 (3e487f8), so this is not drift and re-measuring will not
      fix it. The ZEROS the CG2 records rest on are untouched — what was wrong is the
      near miss named beside them, which is why this control measures the near miss too.
      Reported as a finding against a change-controlled document, not edited from here.

      WHAT THIS CONTROL DOES NOT ESTABLISH. That a search was well-chosen. It re-runs
      the pattern each entry names over the population that entry names, and requires
      a zero, a reached population and a matcher that can fire. Whether the population
      was the right place to look, and whether a given member's claim is really what
      the search looked for, are judgements — the second is written out per row in
      `why_this_search_is_this_claims_search` so a reader can disagree with it, and no
      control here can reach either.
    """)
  end

  defp manifest_rows do
    for s <- read(@manifest)["scenarios"], c <- s["checks"] || [] do
      [leg, scenario, check_id, name, description, discriminator] = c["key"]

      Map.merge(c, %{
        "leg" => leg,
        "scenario" => scenario,
        "check_id" => check_id,
        "name" => name,
        "description" => description,
        "discriminator" => discriminator || ""
      })
    end
  end

  defp sweep(rows, pattern) do
    Enum.filter(rows, &Regex.match?(pattern, row_text(&1)))
  end

  defp row_text(r), do: @searched_fields |> Enum.map_join(" | ", &(r[&1] || ""))

  # --- totality: the client leg is CLOSED, and the closure can go red -------
  #
  # MES-109 (C1b-iii). Two guards land here and neither is worth anything
  # without the other's failure mode being visible, so this mode is built round
  # ONE measurement: the CG9 separation. It is what says G22b is not entailed by
  # G15a — the X7 shape — and it is run on the same mutated input, in the same
  # run, as the unmutated build.
  #
  # WHAT THIS MODE CANNOT SHOW, and it is stated here rather than discovered:
  # G22b does NOT fire on a dropped row. G15a gets there first, because a
  # dropped row shrinks the file's members below its own selector's denotation.
  # That is not a weakness — it is the division of labour — but "G22b refuses a
  # missing member" would be a false description of it, so the control drives
  # the dropped-row case too and ASSERTS WHICH GUARD FIRES. G22b's unique reach
  # is exactly one shape: a B2b row on the declared leg that the file's
  # union-shaped selector does not denote. That is what CG9 is.
  defp totality do
    header("TOTALITY — the client leg closed by refusal, and each refusal shown firing")

    require_harness!()
    client = read(@client_edges)
    src = read(@attribution)

    out = tmp("totality-positive")
    {os_out, status} = os_crosswalk(out, [])
    a = read(out)
    File.rm(out)

    # EVERY asserted leg, not the first one. Until MES-117 exactly one file
    # declared a leg and `Enum.find/2` was indistinguishable from "the leg";
    # with the server leg closed there are two, and a control that kept
    # finding the first would have run the whole mode over the client leg
    # again while printing greens a reader would take for the server's.
    legs =
      a["population"]["files"]
      |> Enum.map(& &1["leg_totality"])
      |> Enum.filter(& &1["declared"])
      |> Map.new(&{&1["leg"], &1})

    lt = Map.fetch!(legs, "client")

    IO.puts("  POSITIVE  the unmutated build succeeds at the OS exit status: #{status}")

    Enum.each(legs, fn {leg, l} ->
      IO.puts(
        "            #{leg} leg total at #{l["members"]} members, " <>
          "#{length(l["slices"])} slices, #{l["cover_not_partition"]["in_more_than_one_slice"]} in two"
      )
    end)

    verdict("the unmutated build exits 0", status == 0)
    halt_unless(status == 0)
    halt_unless(String.contains?(os_out, "CROSSWALK"))

    verdict(
      "and it asserts a leg at all — a run asserting none would pass every case below vacuously",
      lt["declared"] == true and lt["members"] > 0
    )

    halt_unless(lt["declared"] == true and lt["members"] > 0)

    # --- THE CG9 SEPARATION -------------------------------------------------
    #
    # A new B2b row on the client leg carrying a `cg` no limb of the file's
    # union-shaped selector names. G15a asks "is the population what MY
    # selector denotes?" and the answer is still yes. G22b asks "is my selector
    # the leg?" and the answer is now no. One input, two questions, two
    # verdicts — which is the whole argument for not simplifying the top-level
    # selector to a bare `leg equals client`.
    cg9 = %{
      "key" => "MCP.CG9ProbeTest/test a client member B2b knows about and no limb denotes",
      "leg" => "client",
      "leg_reason" => "a CG9 probe planted by crosswalk_controls.exs totality",
      "cg" => "CG9",
      "cg_basis" => "planted",
      "tokens" => [],
      "contradicts_oc" => nil
    }

    mutated = update_in(src, ["rows"], &(&1 ++ [cg9]))

    member_sel = client["the_population_this_file_declares"]["selector"]
    {:ok, still} = Crosswalk.select(member_sel, mutated)
    file_members = lt["members"]

    IO.puts("\n  CG9  a client row carrying a `cg` no limb of the union names:")

    IO.puts(
      "       G15a — the file's OWN selector over the mutated anchor: " <>
        "#{length(still)} denoted vs #{file_members} rows in the file"
    )

    verdict(
      "G15a is GREEN on the mutation — #{file_members} against #{file_members}, set-equal both ways",
      length(still) == file_members
    )

    halt_unless(length(still) == file_members)

    {:ok, leg_only} =
      Crosswalk.select(
        %{
          "source" => @attribution,
          "rows_at" => "rows",
          "key_field" => "key",
          "all_of" => [%{"field" => "leg", "test" => "equals", "value" => "client"}]
        },
        mutated
      )

    IO.puts(
      "       G22b — `leg equals client` over the same mutated anchor: " <>
        "#{length(leg_only)} denoted vs #{file_members} rows in the file"
    )

    verdict(
      "G22b's question has a DIFFERENT answer on the same input — #{length(leg_only)} against #{file_members}",
      length(leg_only) == file_members + 1
    )

    halt_unless(length(leg_only) == file_members + 1)

    # And the generator itself, at the OS exit status, on that same input.
    #
    # THE ANCHOR IS SUBSTITUTED BY RETARGETING, NOT BY EDITING THE REPO.
    # `selected!/4` refuses a run whose `--attribution` is not the path the
    # selector NAMES — that is G15's own anti-substitution limb and it fires
    # before anything here could — so the mutated anchor is written to a temp
    # file and every `source` in a temp COPY of the edges file is retargeted at
    # it. Nothing under the repo is written, which is deliberate: a seat that
    # died mid-run would otherwise leave a mutated register behind (S8-14).
    # The only semantic difference between this pair and the committed one is
    # the single planted row.
    attr_path = write_tmp("attribution-cg9", mutated)
    edges_path = write_tmp("edges-cg9", retarget(client, attr_path))

    try do
      os_refuses(
        "G22b  a client member B2b has and no edges file carries",
        ["G22b", "is NOT total over it", cg9["key"]],
        fn out ->
          os_crosswalk(out, attribution: attr_path, edges: [edges_path, @server_edges, @edges])
        end
      )
    after
      File.rm(attr_path)
      File.rm(edges_path)
    end

    verdict(
      "SO G22b IS NOT ENTAILED BY G15a — one input, G15a green and G22b red, measured in this run",
      length(still) == file_members and length(leg_only) != file_members
    )

    halt_unless(length(still) == file_members and length(leg_only) != file_members)

    # --- THE SERVER-LEG SEPARATION (MES-117, C1c-iv-a) ----------------------
    #
    # The same argument as CG9, on the other leg's selector VOCABULARY, and it
    # has to be re-made rather than inherited: the client's union is over `cg`
    # values and `is_null`, the server's is over 21 module-name PREFIXES, and a
    # mutation that separates one shape says nothing about the other. The
    # server's separating row is a B2b row on the server leg whose key is in a
    # TWENTY-SECOND module — no `starts_with` leaf denotes it, so G15a compares
    # 145 against 145 and passes while G22b compares 146 against 145 and
    # refuses, naming it.
    #
    # THIS MUTATION IS ALSO THE STANDING ARGUMENT FOR THE PREFIX PREDICATE over
    # an enumeration of `key equals` leaves, and the file says so: a new test
    # in an EXISTING declared module is caught by G15a, and a new MODULE only
    # by G22b. Neither alone reaches both, which is why both are kept.
    srv = read(@server_edges)
    srv_lt = Map.fetch!(legs, "server")

    m22 = %{
      "key" =>
        "MCP.TwentySecondModuleProbeTest/test a server member B2b knows about and no prefix denotes",
      "leg" => "server",
      "leg_reason" => "a 22nd-module probe planted by crosswalk_controls.exs totality",
      "cg" => nil,
      "cg_basis" => "planted",
      "tokens" => [],
      "contradicts_oc" => nil
    }

    srv_mutated = update_in(src, ["rows"], &(&1 ++ [m22]))
    srv_sel = srv["the_population_this_file_declares"]["selector"]
    {:ok, srv_still} = Crosswalk.select(srv_sel, srv_mutated)
    srv_members = srv_lt["members"]

    IO.puts("\n  22ND MODULE  a server row in a module no `starts_with` leaf names:")

    IO.puts(
      "       G15a — the file's OWN selector over the mutated anchor: " <>
        "#{length(srv_still)} denoted vs #{srv_members} rows in the file"
    )

    verdict(
      "G15a is GREEN on the mutation — #{srv_members} against #{srv_members}, set-equal both ways",
      length(srv_still) == srv_members
    )

    halt_unless(length(srv_still) == srv_members)

    {:ok, srv_leg_only} =
      Crosswalk.select(
        %{
          "source" => @attribution,
          "rows_at" => "rows",
          "key_field" => "key",
          "all_of" => [%{"field" => "leg", "test" => "equals", "value" => "server"}]
        },
        srv_mutated
      )

    IO.puts(
      "       G22b — `leg equals server` over the same mutated anchor: " <>
        "#{length(srv_leg_only)} denoted vs #{srv_members} rows in the file"
    )

    verdict(
      "G22b's question has a DIFFERENT answer on the same input — " <>
        "#{length(srv_leg_only)} against #{srv_members}",
      length(srv_leg_only) == srv_members + 1
    )

    halt_unless(length(srv_leg_only) == srv_members + 1)

    # ALL THREE FILES ARE RETARGETED, not just the mutated one — and the CG9
    # case above gets away with retargeting one only by an ORDERING ACCIDENT
    # worth naming. `selected!/4` refuses a run whose `--attribution` is not
    # the path the file NAMES, and it is applied per file in the order given.
    # CG9 mutates the CLIENT file, which is first, so its G22b raises before
    # the un-retargeted server file is ever validated. Plant on the SERVER leg
    # and the client file is reached first, its selector still names the
    # committed anchor, and the run dies on the substitution guard instead —
    # which is what this control measured on its first run. Retargeting all
    # three makes the probe independent of file order.
    srv_attr_path = write_tmp("attribution-m22", srv_mutated)
    srv_edges_path = write_tmp("edges-m22", retarget(srv, srv_attr_path))
    cli_edges_path = write_tmp("client-edges-m22", retarget(client, srv_attr_path))
    base_edges_path = write_tmp("base-edges-m22", retarget(read(@edges), srv_attr_path))

    try do
      os_refuses(
        "G22b  a SERVER member B2b has and no edges file carries",
        ["G22b", "is NOT total over it", m22["key"]],
        fn out ->
          os_crosswalk(out,
            attribution: srv_attr_path,
            edges: [cli_edges_path, srv_edges_path, base_edges_path]
          )
        end
      )
    after
      Enum.each([srv_attr_path, srv_edges_path, cli_edges_path, base_edges_path], &File.rm/1)
    end

    verdict(
      "SO G22b IS NOT ENTAILED BY G15a ON THE SERVER LEG EITHER — one input, G15a green and " <>
        "G22b red, measured in this run over the PREFIX vocabulary and not the client's `cg` one",
      length(srv_still) == srv_members and length(srv_leg_only) != srv_members
    )

    halt_unless(length(srv_still) == srv_members and length(srv_leg_only) != srv_members)

    # The COVER limb on the server file, and it is NOT the client's limb run
    # twice: the server cover's overlap is 2 where the client's is 18, and its
    # entries are cut by module prefix rather than by `cg`. Dropping C1c-iv-a's
    # entry leaves its 34 members denoted by no declared slice.
    refuses(
      "G22a  the SERVER cover with C1c-iv-a's slice dropped — 34 members under no declared rule",
      "G22a — the UNION of",
      fn ->
        build_server_edges(
          update_in(srv, ["the_sub_populations_this_file_records", "entries"], fn es ->
            Enum.reject(es, &String.contains?(&1["ticket"], "C1c-iv-a"))
          end)
        )
      end
    )

    refuses(
      "G22  the SERVER leg declared with its sub-populations removed — half a claim is refused",
      "half-declares a leg totality",
      fn -> build_server_edges(Map.delete(srv, "the_sub_populations_this_file_records")) end
    )

    # --- the cover ----------------------------------------------------------
    refuses(
      "G22a  a slice dropped from the cover, leaving members no declared rule reaches",
      "G22a — the UNION of",
      fn ->
        build_edges(
          update_in(client, ["the_sub_populations_this_file_records", "entries"], fn es ->
            Enum.reject(es, &String.contains?(&1["ticket"], "C1b-iii"))
          end)
        )
      end
    )

    refuses(
      "G22  the leg declared with the sub-populations removed — half a claim is refused",
      "half-declares a leg totality",
      fn -> build_edges(Map.delete(client, "the_sub_populations_this_file_records")) end
    )

    # --- and the case G22b does NOT catch, named rather than implied --------
    dropped = update_in(client, ["declared_unmatched"], &Enum.drop(&1, -1))

    refuses(
      "G15a  a member ROW dropped — and it is G15a that fires, NOT G22b",
      "G15a — the population",
      fn -> build_edges(recount(dropped)) end
    )

    IO.puts(
      "           G22b never sees it: a dropped row shrinks the file below its own selector's\n" <>
        "           denotation, so the earlier guard answers first. G22b's unique reach is the\n" <>
        "           CG9 shape above — a row on the leg that the union does not denote."
    )

    # --- THE NONE_DETERMINABLE SEPARATION (MES-121, C1c-iv-b) ---------------
    #
    # The third population, and the argument has to be re-made on ITS selector
    # vocabulary for the same reason the server's did: the client's union is over
    # `cg` values, the server's over 21 module prefixes, and this one over a
    # `none_of[client, server]` leg conjunct AND 9 module prefixes. The leg
    # conjunct here is in its COMPLEMENT form, which is what keeps this file's
    # selector and G22b's fresh one apart — under a bare `none_of[client,
    # server]` G22b's denotation would be a SUBSET of this selector's for every
    # input and G22b could only fail where G15a already had. That is the X7 shape,
    # and the module conjunct is what this control shows to be load-bearing.
    #
    # THE SEPARATING ROW is a B2b row on the none_determinable leg whose key is in
    # a TENTH module: no `starts_with` leaf denotes it, so G15a compares 29
    # against 29 and passes while G22b compares 30 against 29 and refuses.
    nd = read(@edges)
    nd_lt = Map.fetch!(legs, "none_determinable")

    m10 = %{
      "key" =>
        "MCP.TenthModuleProbeTest/test a none_determinable member B2b knows about and no prefix denotes",
      "leg" => "none_determinable",
      "leg_reason" => "a 10th-module probe planted by crosswalk_controls.exs totality",
      "cg" => nil,
      "cg_basis" => "planted",
      "tokens" => [],
      "contradicts_oc" => nil
    }

    nd_mutated = update_in(src, ["rows"], &(&1 ++ [m10]))
    nd_sel = nd["the_population_this_file_declares"]["selector"]
    {:ok, nd_still} = Crosswalk.select(nd_sel, nd_mutated)
    nd_members = nd_lt["members"]

    IO.puts("\n  10TH MODULE  a none_determinable row in a module no `starts_with` leaf names:")

    IO.puts(
      "       G15a — the file's OWN selector over the mutated anchor: " <>
        "#{length(nd_still)} denoted vs #{nd_members} rows in the file"
    )

    verdict(
      "G15a is GREEN on the mutation — #{nd_members} against #{nd_members}, set-equal both ways",
      length(nd_still) == nd_members
    )

    halt_unless(length(nd_still) == nd_members)

    {:ok, nd_leg_only} =
      Crosswalk.select(
        %{
          "source" => @attribution,
          "rows_at" => "rows",
          "key_field" => "key",
          "all_of" => [
            %{"field" => "leg", "test" => "equals", "value" => "none_determinable"}
          ]
        },
        nd_mutated
      )

    IO.puts(
      "       G22b — `leg equals none_determinable` over the same mutated anchor: " <>
        "#{length(nd_leg_only)} denoted vs #{nd_members} rows in the file"
    )

    verdict(
      "G22b's question has a DIFFERENT answer on the same input — " <>
        "#{length(nd_leg_only)} against #{nd_members}",
      length(nd_leg_only) == nd_members + 1
    )

    halt_unless(length(nd_leg_only) == nd_members + 1)

    nd_attr_path = write_tmp("attribution-m10", nd_mutated)
    nd_edges_path = write_tmp("edges-m10", retarget(nd, nd_attr_path))
    nd_cli_path = write_tmp("client-edges-m10", retarget(client, nd_attr_path))
    nd_srv_path = write_tmp("server-edges-m10", retarget(srv, nd_attr_path))

    try do
      os_refuses(
        "G22b  a NONE_DETERMINABLE member B2b has and no edges file carries",
        ["G22b", "is NOT total over it", m10["key"]],
        fn out ->
          os_crosswalk(out,
            attribution: nd_attr_path,
            edges: [nd_cli_path, nd_srv_path, nd_edges_path]
          )
        end
      )
    after
      Enum.each([nd_attr_path, nd_edges_path, nd_cli_path, nd_srv_path], &File.rm/1)
    end

    verdict(
      "SO G22b IS NOT ENTAILED BY G15a ON THE NONE_DETERMINABLE POPULATION EITHER — one input, " <>
        "G15a green and G22b red, measured in this run over the COMPLEMENT-leg-plus-prefix " <>
        "vocabulary and not the client's `cg` one or the server's plain-leg one",
      length(nd_still) == nd_members and length(nd_leg_only) != nd_members
    )

    halt_unless(length(nd_still) == nd_members and length(nd_leg_only) != nd_members)

    # AND THE CONJUNCT THAT MAKES IT POSSIBLE, MEASURED RATHER THAN ASSERTED. The
    # file states that a bare `none_of[client, server]` would make G22b entailed.
    # That is checked here by BUILDING the bare selector and comparing its
    # denotation against G22b's own on the SAME mutated anchor: if the two agree
    # on an input that separates the committed pair, the committed conjunct is
    # what does the separating. A claim that a constraint is load-bearing is only
    # worth something with the loosened form measured beside it.
    {:ok, bare} =
      Crosswalk.select(
        %{
          "source" => @attribution,
          "rows_at" => "rows",
          "key_field" => "key",
          "all_of" => [
            %{
              "none_of" => [
                %{"field" => "leg", "test" => "equals", "value" => "client"},
                %{"field" => "leg", "test" => "equals", "value" => "server"}
              ]
            }
          ]
        },
        nd_mutated
      )

    IO.puts(
      "       the BARE `none_of[client, server]` form on the same input: " <>
        "#{length(bare)} denoted, which is G22b's #{length(nd_leg_only)} and NOT the file's " <>
        "#{nd_members}"
    )

    verdict(
      "the MODULE conjunct is what separates them: without it G15a would denote " <>
        "#{length(bare)} — the same as G22b — so the mutation above could not tell the two " <>
        "guards apart and G22b would be the X7 shape",
      length(bare) == length(nd_leg_only) and length(bare) != nd_members
    )

    halt_unless(length(bare) == length(nd_leg_only) and length(bare) != nd_members)

    # The COVER limb on the none_determinable file. Its overlap is ONE where the
    # client's is 18 and the server's 2, and its entries are cut by ticket:
    # dropping C1c-iv-b's leaves 28 members under no declared rule.
    refuses(
      "G22a  the NONE_DETERMINABLE cover with C1c-iv-b's slice dropped — 28 members under no declared rule",
      "G22a — the UNION of",
      fn ->
        build_base_edges(
          update_in(nd, ["the_sub_populations_this_file_records", "entries"], fn es ->
            Enum.reject(es, &String.contains?(&1["ticket"], "C1c-iv-b"))
          end)
        )
      end
    )

    refuses(
      "G22  the NONE_DETERMINABLE population declared with its sub-populations removed",
      "half-declares a leg totality",
      fn -> build_base_edges(Map.delete(nd, "the_sub_populations_this_file_records")) end
    )

    # --- THE `NOT ASSERTED` BRANCH, WHICH REAL DATA NO LONGER REACHES -------
    #
    # MES-121. `leg_totality!/5` has a `{nil, nil}` clause that reports NOT
    # ASSERTED and lets the build succeed, and until this ticket the committed
    # `crosswalk-edges.json` exercised it. All three files now declare a leg, so
    # the branch has no real input and the unit over the committed artefact that
    # used to cover it could only be made green by asserting something else. It is
    # driven here instead: BOTH fields stripped from a copy of one file, the build
    # required to SUCCEED, and its report for that file required to say NOT
    # ASSERTED. The positive direction matters as much as the refusals around it —
    # a generator that refused a file for declaring no leg would break every slice
    # before the last one.
    stripped =
      nd
      |> Map.delete("leg")
      |> Map.delete("leg_note")
      |> Map.delete("the_sub_populations_this_file_records")

    stripped_path = write_tmp("base-edges-noleg", stripped)
    stripped_out = tmp("noleg")

    {noleg_text, noleg_status} =
      try do
        os_crosswalk(stripped_out, edges: [@client_edges, @server_edges, stripped_path])
      after
        File.rm(stripped_path)
      end

    IO.puts("\n  NOT ASSERTED  `leg` and its sub-populations stripped from a copy of #{@edges}:")
    IO.puts("                the build exits #{noleg_status}")

    verdict(
      "the build SUCCEEDS — declaring no leg is an honest state and not an error",
      noleg_status == 0 and String.contains?(noleg_text, "CROSSWALK")
    )

    halt_unless(noleg_status == 0)

    stripped_report =
      stripped_out
      |> read()
      |> get_in(["population", "files"])
      |> Enum.find(&(&1["path"] == stripped_path))

    File.rm(stripped_out)

    IO.puts(
      "                and reports: #{String.slice(stripped_report["leg_totality"]["result"], 0, 78)}..."
    )

    verdict(
      "and the file's own report says NOT ASSERTED rather than reporting a pass — the branch " <>
        "the committed artefact stopped exercising at this ticket",
      stripped_report["leg_totality"]["declared"] == false and
        stripped_report["leg_totality"]["result"] =~ "NOT ASSERTED"
    )

    halt_unless(stripped_report["leg_totality"]["declared"] == false)

    # AND the whole-crosswalk totality is UNAFFECTED by it, which is the property
    # that says G24 and G22b are asking different questions: a file may decline to
    # claim a leg and still have every one of its members homed.
    verdict(
      "G24 is still GREEN on that build — declining to claim a LEG does not un-home a " <>
        "member, so the two guards really are asking different questions",
      String.contains?(noleg_text, "whole crosswalk   TOTAL")
    )

    halt_unless(String.contains?(noleg_text, "whole crosswalk   TOTAL"))

    # --- G23, the absence-search guard --------------------------------------
    with_search =
      Enum.find_index(client["declared_unmatched"], & &1["the_search_that_found_none"])

    refuses(
      "G23a  a bucket-1 row with its search removed — leg-wide, no exception list",
      "G23a —",
      fn ->
        build_edges(
          update_in(client, ["declared_unmatched"], fn rows ->
            List.update_at(rows, with_search, &Map.delete(&1, "the_search_that_found_none"))
          end)
        )
      end
    )

    registered = Enum.find_index(client["declared_unmatched"], & &1["search_id"])

    refuses(
      "G23b  a `search_id` that resolves to no registry entry",
      "search_id_resolves_to_nothing",
      fn ->
        build_edges(
          update_in(client, ["declared_unmatched"], fn rows ->
            List.update_at(rows, registered, &Map.put(&1, "search_id", "S99"))
          end)
        )
      end
    )

    refuses(
      "G23b  a registry entry recording a NON-zero — an entry IS a search that found none",
      "entry_does_not_record_zero",
      fn ->
        build_edges(
          update_in(client, ["absence_searches"], fn [e | rest] -> [%{e | "hits" => 1} | rest] end)
        )
      end
    )

    refuses(
      "G23b  a registry entry with its near miss removed — a bare zero is a grep",
      "entry_names_no_near_miss",
      fn ->
        build_edges(
          update_in(client, ["absence_searches"], fn [e | rest] ->
            [Map.delete(e, "near_miss") | rest]
          end)
        )
      end
    )

    refuses(
      "G23b  a registry entry with no positive control — a zero whose sweep was never shown to run",
      "entry_has_no_positive_control",
      fn ->
        build_edges(
          update_in(client, ["absence_searches"], fn [e | rest] ->
            [%{e | "positive_controls" => []} | rest]
          end)
        )
      end
    )

    refuses(
      "G23d  an entry whose KIND is not the reason slug its row's own tag carries",
      "entry_kind_is_not_the_rows_reason_slug",
      fn ->
        build_edges(
          update_in(client, ["absence_searches"], fn [e | rest] ->
            [%{e | "kind" => "no-oc-fixture-case"} | rest]
          end)
        )
      end
    )

    refuses(
      "G23b  a row whose prose COPY of the near miss has drifted from its entry (D4)",
      "row_copy_has_drifted_from_the_entry",
      fn ->
        build_edges(
          update_in(client, ["declared_unmatched"], fn rows ->
            List.update_at(
              rows,
              registered,
              &Map.put(&1, "the_near_miss_that_is_not_a_counterpart", "a different near miss")
            )
          end)
        )
      end
    )

    refuses(
      "G23c  a registry entry no row names — a measurement in search of a claim",
      "G23c —",
      fn ->
        orphan = client["absence_searches"] |> hd() |> Map.put("id", "S00")

        build_edges(update_in(client, ["absence_searches"], &(&1 ++ [orphan])))
      end
    )

    # --- and the tree is as it was ------------------------------------------
    after_out = tmp("totality-after")
    {_o, after_status} = os_crosswalk(after_out, [])
    same = File.read!(after_out) == File.read!(@crosswalk_out)
    File.rm(after_out)

    verdict("after every mutation the unmutated build still exits 0", after_status == 0)
    halt_unless(after_status == 0)

    verdict(
      "and reproduces the COMMITTED artefact byte for byte — nothing on disk was mutated",
      same
    )

    halt_unless(same)

    IO.puts("""

      The client leg is closed by a refusal rather than by a sentence. Every ET-CC
      member B2b puts on it carries a row, and a member that does not REFUSES THE
      BUILD — checked against B2b afresh, by set, in both directions.

      THE CG9 CASE IS THE LOAD-BEARING ONE. Had the top-level selector been
      simplified to a bare `leg equals client` once the four slices happened to
      cover the leg, G22b would ask G15a's question in G15a's words and could never
      fire on anything: the X7 shape, a guard as empty as one nobody calls. The
      measurement above is what rules that out, and it is a measurement rather than
      an argument — one anchor, two selectors, two answers, in this run.

      WHAT A GREEN HERE IS NOT. Evidence that any adjudication is right. A leg every
      member of which was adjudicated wrongly passes G22b exactly as firmly, and the
      A3 §6 state-4 guard over this population stays entailed by G15a and unable to
      fire (X7). What is new is that the population it cannot fire over is provably
      the whole leg and not a slice somebody chose.
    """)
  end

  # Point every selector in `doc` that names the committed attribution register
  # at `path` instead. Recursive over the whole document rather than over the
  # two blocks that happen to carry one today: the sub-population cover holds
  # one selector per entry, and a new entry whose source this missed would be
  # refused by G15's anti-substitution limb rather than silently retargeted —
  # but the failure would read as a defect in the guard under test.
  defp retarget(%{} = m, path) do
    m
    |> Enum.map(fn
      {"source", @attribution} -> {"source", path}
      {k, v} -> {k, retarget(v, path)}
    end)
    |> Map.new()
  end

  defp retarget(l, path) when is_list(l), do: Enum.map(l, &retarget(&1, path))
  defp retarget(other, _path), do: other

  defp os_crosswalk(out, overrides) do
    edges =
      Enum.flat_map(Keyword.get(overrides, :edges, @all_edges), &["--edges", &1])

    System.cmd(
      "mix",
      ["conformance.crosswalk"] ++
        edges ++
        [
          "--manifest",
          @manifest,
          "--denominator",
          @denominator,
          "--register",
          Keyword.get(overrides, :register, @register),
          "--attribution",
          Keyword.get(overrides, :attribution, @attribution),
          "--a3-axes",
          @a3_axes,
          "--c1-axes",
          @c1_axes,
          "--emitting-sites",
          @sites,
          "--harness",
          @harness,
          "-o",
          out
        ],
      stderr_to_stdout: true
    )
  end

  # The OS-level twin of `refuses/3`. An in-VM rescue shows the message; only a
  # child process shows that the GENERATOR ITSELF exits non-zero, which is what
  # a caller in a shell would see. Both limbs are required: a non-zero status
  # with the wrong message is a mutation that tripped some other guard.
  defp os_refuses(label, expected, fun) do
    out = tmp("os-refuse")
    {text, status} = fun.(out)
    File.rm(out)

    if status == 0 do
      IO.puts("  DID NOT REFUSE  #{label} — exited 0")
      System.halt(1)
    end

    case Enum.reject(expected, &String.contains?(text, &1)) do
      [] ->
        IO.puts("  refused  #{label}  (OS exit #{status})")

      missing ->
        IO.puts("  WRONG GUARD  #{label}")
        IO.puts("           expected the message to carry: #{inspect(missing)}")
        System.halt(1)
    end
  end

  # --- citations: every evidence quote, lifted live and compared ------------
  #
  # MES-108. Ruling 7 says an address is not evidence, the bytes at it are. CR-3
  # then caught two quotes in C1b-i that were not the bytes at their address (a
  # dropped module prefix), and the general byte-at-address guard is MES-112 and
  # is not built. So until it is, this runs the comparison MECHANICALLY rather
  # than leaving it to a seat's eye.
  #
  # TWO SIDES, TWO ANCHORS, and a quote must be verbatim at an address the
  # evidence ITSELF names — not merely present somewhere:
  #
  #   ET side  against the cited `file.exs:N` / `:N-M` span in the repo.
  #   OC side  against the live harness build, restricted to the byte spans the
  #            axis row FOR THIS EDGE'S TAG addresses. Not "somewhere in 800KB":
  #            a quote that is only findable by searching the whole build is a
  #            quote with no address, which is the thing ruling 7 forbids.
  #
  # A BARE `:N` CONTINUATION IS A FAILURE, not a lookup. `:262` after a full
  # citation earlier in the same string has no syntactic referent — S9's
  # bare-continuation finding — and resolving it against the nearest preceding
  # file name is guessing. Two of C1b-ii's own drafts carried one; both were
  # rewritten in full rather than resolved by proximity.
  #
  # WHAT IT DOES NOT COVER, stated rather than implied. It compares after
  # collapsing runs of whitespace, so it accepts a quote the formatter has
  # line-wrapped at a different point than the author did; that is deliberate
  # (the alternative reddens on `mix format`) and it means the check is on the
  # BYTES modulo layout, not on the layout. It only looks at backtick-delimited
  # spans containing `=`, `(`, `[`, `!==` or `===` — a prose phrase in backticks
  # is not treated as a quote, so an inaccurate paraphrase passes. And it says
  # nothing about whether the quote SUPPORTS the verdict it is filed under.

  @quote_re ~r/`((?:[^`]|`[^`]*`(?=[^`]*`))+?)`(?!`)/
  @cite_re ~r/([a-z0-9_]+\.exs?):(\d+)(?:-(\d+))?/
  @bare_cite_re ~r/(?<![\w.])(?<!\.exs)(?<!\.ex):(\d+)\b/

  defp citations do
    header("CITATIONS — every evidence quote lifted live and compared by == (ruling 7)")

    require_harness!()
    client = read(@client_edges)
    axes = read(@c1_axes)["checks"] ++ read(@a3_axes)["checks"]
    build = File.read!(@harness)

    records =
      client["edges"] ++ client["declared_unmatched"] ++ client["claims_without_an_edge"]

    mine = Enum.filter(records, &authored_here?/1)

    IO.puts(
      "  #{length(records)} records in #{Path.basename(@client_edges)}, " <>
        "#{length(mine)} authored by C1b-ii or C1b-iii\n"
    )

    halt_unless(mine != [])

    {et, oc, problems} = audit(mine, axes, build)

    IO.puts("  ET side  #{et} quotes verbatim at their cited test-file line spans")
    IO.puts("  OC side  #{oc} quotes verbatim inside the axis row's own addressed harness spans")

    verdict(
      "all #{et + oc} quotes C1b-ii and C1b-iii authored are verbatim at an address the evidence names",
      problems == []
    )

    for p <- problems, do: IO.puts("    #{inspect(p)}")
    halt_unless(problems == [])

    # POSITIVE CONTROL. `problems == []` is also what an audit that read nothing
    # returns, so the sweep is shown to have reached the quotes: every one of
    # MES-108's edges must have contributed at least one, and the total must be
    # the number counted independently by walking the regex over the same rows.
    counted =
      mine
      |> Enum.map(&length(source_quotes(&1["evidence"] || "")))
      |> Enum.sum()

    IO.puts("\n  POSITIVE  #{counted} source-shaped quotes found by an independent count")

    verdict(
      "the audit compared every quote the records carry — #{et + oc} of #{counted}",
      et + oc == counted and counted > 0
    )

    halt_unless(et + oc == counted and counted > 0)

    # MUTATION 1 — a quote that is not the bytes at its address. This is CR-3's
    # exact defect, planted: the module prefix dropped from a real assertion.
    mutated =
      Enum.map(mine, fn r ->
        Map.update(r, "evidence", nil, fn ev ->
          String.replace(ev, "HeaderMirror.decode_value(header)", "decode_value(header)")
        end)
      end)

    {_, _, caught} = audit(mutated, axes, build)

    IO.puts("\n  MUTATION  a module prefix dropped from one quote (CR-3's own defect):")
    for p <- caught, do: IO.puts("    #{inspect(p)}")

    verdict("the dropped prefix is CAUGHT, and named", caught != [])
    halt_unless(caught != [])

    # MUTATION 2 — the address moved by one line, the bytes untouched. A check
    # that only asked "is this text anywhere in the file" would pass this, and
    # it is the drift line citations actually suffer (a commit inserting a line
    # above them). This is why the comparison is against the CITED SPAN.
    shifted =
      Enum.map(mine, fn r ->
        Map.update(
          r,
          "evidence",
          nil,
          &String.replace(&1, "routing_headers_test.exs:244", "routing_headers_test.exs:245")
        )
      end)

    {_, _, drifted} = audit(shifted, axes, build)

    IO.puts("\n  MUTATION  one citation moved by a single line, the bytes unchanged:")
    for p <- drifted, do: IO.puts("    #{inspect(p)}")

    verdict(
      "an off-by-one ADDRESS is caught even though the bytes are still in the file",
      drifted != []
    )

    halt_unless(drifted != [])

    # MUTATION 3 — a bare `:N` continuation, which is not a wrong address but an
    # unresolvable one. It must be a failure and not a silent skip.
    bared =
      Enum.map(mine, fn r ->
        Map.update(
          r,
          "evidence",
          nil,
          &String.replace(&1, "and routing_headers_test.exs:223 asserts", "and :223 asserts")
        )
      end)

    {_, _, unresolvable} = audit(bared, axes, build)

    IO.puts("\n  MUTATION  a citation reduced to a bare `:N` with no file:")
    for p <- unresolvable, do: IO.puts("    #{inspect(p)}")

    verdict("a bare continuation is a FAILURE, not a lookup by proximity", unresolvable != [])
    halt_unless(unresolvable != [])

    IO.puts("""

      WHAT THIS IS AND IS NOT. It is the mechanical half of ruling 7, run at this seat
      over the rows THIS TICKET authored — MES-108 ran it before committing, and it
      caught two defects in its own drafts (a harness quote checked against a test file,
      and two bare `:N` continuations) which were fixed rather than argued. MES-109 ran
      it and it caught two more, both in its own five new edges: a COMPOSED quote —
      `Protocol.encode(Request.new(1, "tools/list", %{"cursor" => "abc"}))`, which reads
      exactly like source and appears nowhere in the file, because the call and the
      argument are on two different lines — and a nested-backtick span that made the
      quote regex report a fragment neither the author nor the file ever wrote. Both are
      ruling 7 defects that a careful read would have passed: the first is a plausible
      paraphrase of two real lines, and that is the kind a human eye is worst at.

      It is NOT MES-112, AND MES-112 HAS SINCE LANDED. MES-112 is G30, the guard INSIDE
      the generator, over every row of every edges file, where a bad citation cannot be
      committed at all — `MCP.Conformance.CitationVerbatim`, with its own controls in
      `conformance/controls/citation_verbatim_controls.exs`.

      WHAT THIS PARAGRAPH USED TO SAY, and why it no longer does. It reported that over
      the inherited C1a and C1b-i rows this same audit found 18 quotes it could not
      place — 8 stale addresses, 5 ellipsis paraphrases, 3 prose descriptions quoted as
      if source, 2 bare continuations — and that re-addressing them was not MES-108's to
      do, so they were REPORTED and left. MES-112 fixed all 18 (8 re-addressed, 2 bares
      written out in full, 2 re-lifted, 6 de-quoted; the classification moved because
      G30 separates an elision from a wrong address, and because one `prose` case turned
      out to be real bytes OUTSIDE the row's addressed spans). So the number is now zero
      and the sentence is kept as history rather than as a live count.

      THIS MODE STILL SCOPES ITSELF TO MES-108'S AND MES-109'S ROWS, and that is no
      longer a way of not going red on other people's work — G30 now quantifies over
      every row, so nothing is left unadjudicated by scope. What it remains is a SECOND,
      INDEPENDENT implementation of the same comparison over the rows those tickets
      authored: written before G30 and not sharing its code, so it corroborates rather
      than restates. If the two ever disagree, one of them is wrong and that is worth
      knowing.
    """)
  end

  # WHO WROTE THIS ROW, and MES-109 had to change how the question is asked.
  #
  # C1b-ii answered it by GUESSING from the tag, and the guess held only
  # because its rows happened to carry tags no earlier ticket used. C1b-iii's
  # do not: its `a non-32022 error is never retried` edge carries the SAME
  # `ClientRetrySupportedVersion` tag as four inherited C1a rows, so no tag
  # predicate can separate the row this ticket wrote from the rows it did not —
  # and a predicate that pulled the inherited ones in would red the audit over
  # work it is not adjudicating, while one that left them out would silently
  # drop the new row. So C1b-iii's records carry `authored_by`, written by the
  # author, and the tag heuristic stays only for C1b-ii's rows, which predate
  # the field.
  defp authored_here?(r), do: mes_108_row?(r) or mes_109_row?(r)

  defp mes_109_row?(r), do: String.contains?(r["authored_by"] || "", "MES-109")

  defp mes_108_row?(r) do
    tag = r["tag"] || ""

    (String.contains?(tag, "http-standard-headers") or
       String.contains?(tag, "json-schema-ref-no-deref") or
       String.contains?(tag, "/CG2-") or String.contains?(tag, "/CG1-") or
       String.contains?(r["owner"] || "", "C1b-ii")) and not mes_109_row?(r)
  end

  defp audit(records, axes, build) do
    Enum.reduce(records, {0, 0, []}, fn r, {et, oc, bad} ->
      ev = r["evidence"] || ""
      label = String.slice(r["claim"] || r["tag"] || "?", 0, 50)

      bare =
        for [_, n] <- Regex.scan(@bare_cite_re, ev),
            do: {:bare_citation_has_no_file, label, ":" <> n}

      et_window = cited_window(ev)
      oc_window = axis_window(r["tag"], axes, build)

      {e, o, q_bad} =
        Enum.reduce(source_quotes(ev), {0, 0, []}, fn q, {e, o, acc} ->
          sq = squash(q)

          cond do
            String.contains?(et_window, sq) -> {e + 1, o, acc}
            String.contains?(oc_window, sq) -> {e, o + 1, acc}
            true -> {e, o, [{:not_verbatim_at_any_cited_address, label, q} | acc]}
          end
        end)

      {et + e, oc + o, bad ++ bare ++ Enum.reverse(q_bad)}
    end)
  end

  defp source_quotes(ev) do
    for [_, q] <- Regex.scan(@quote_re, ev),
        Regex.match?(~r/[=(\[]|!==|===/, q),
        do: q
  end

  defp cited_window(ev) do
    for [_, file, from, to] <- Regex.scan(@cite_re, ev, capture: :all) |> pad_captures() do
      case find_source(file) do
        nil ->
          ""

        path ->
          lines = path |> File.read!() |> String.split("\n")
          a = String.to_integer(from)
          b = if to == "", do: a, else: String.to_integer(to)
          lines |> Enum.slice((a - 1)..(b - 1)//1) |> Enum.join("\n") |> squash()
      end
    end
    |> Enum.join(" || ")
  end

  defp pad_captures(scans),
    do: Enum.map(scans, fn c -> c ++ List.duplicate("", 4 - length(c)) end)

  defp find_source(basename) do
    ["test", "lib", "conformance"]
    |> Enum.flat_map(&Path.wildcard(Path.join([&1, "**", basename])))
    |> List.first()
  end

  defp axis_window(nil, _axes, _build), do: ""

  defp axis_window(tag, axes, build) do
    name = tag |> String.split("/") |> List.last()

    for c <- axes, Enum.at(c["key"], 3) == name, reduce: "" do
      acc ->
        spans =
          [c["emitting_byte_span"], get_in(c, ["emitting_site", "dist_byte_span"])] ++
            Enum.map(c["context_excerpts"] || [], & &1["byte_span"])

        bytes =
          spans
          |> Enum.reject(&is_nil/1)
          |> Enum.map_join(" || ", fn [a, b] -> binary_part(build, a, b - a) end)

        acc <> " || " <> bytes <> " || " <> (c["evaluator_excerpt"] || "")
    end
    |> squash()
  end

  defp squash(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()

  # --- statements: G21, the population figures this generator's own prose states
  #
  # CR-5 on MES-108. `trust_status` shipped `48-member / 29-declared-check` into
  # the committed artefact over a 68/39 population, and `crosswalk_test.exs`
  # asserted that literal against itself, so nothing went red. It is CR-1 on
  # MES-104 recurring one ticket later in the one file CR-1's remedy did not
  # reach: the projector's `:population_statement` guards the twelve VIEWS, and
  # the generator's own statements were guarded by nobody.
  #
  # THE MUTATIONS ARE APPLIED TO THE MECHANISM, not to an input file, for the
  # reason `pins` gives: no input can produce the state. A stale literal is a
  # disagreement between prose the generator authors and figures the generator
  # derives, and both sides are in the module. Nothing on disk is touched — the
  # module is recompiled in this VM and restored in an `after`, so a death
  # mid-run cannot leave the shared clone mutated (S8-14).

  @crosswalk_src "conformance/lib/mix/tasks/conformance.crosswalk.ex"
  @crosswalk_lib "conformance/lib/mcp/conformance/crosswalk.ex"

  defp statements do
    header("G21 — every population figure this generator's own prose states, against the tree")

    require_harness!()

    a = read(@crosswalk_out)

    inputs =
      Crosswalk.string_set(
        Enum.map(
          [
            @client_edges,
            @server_edges,
            @edges,
            @c1_axes,
            @a3_axes,
            @manifest,
            @denominator,
            @register,
            @attribution,
            @sites
          ],
          &read/1
        )
      )

    authored = Crosswalk.authored_statements(a, inputs)

    all_claims =
      Enum.filter(Crosswalk.strings_at(a), &(Crosswalk.population_claims(elem(&1, 1)) != []))

    data = length(all_claims) - length(authored)

    IO.puts("  claim-bearing strings in the committed artefact: #{length(all_claims)}")
    IO.puts("    AUTHORED by the generator (in no input document):  #{length(authored)}")
    IO.puts("    carried through from an input document:            #{data}")

    for {path, _t, claims} <- Enum.take(Enum.sort(authored), 20) do
      IO.puts("      #{String.pad_trailing(path, 46)} #{inspect(Enum.map(claims, &elem(&1, 1)))}")
    end

    # POSITIVE CONTROL for the scan's REACH. A scan that read nothing reports the
    # same clean zero as a scan that found nothing wrong, and the statement CR-5
    # was raised about is the one it must be able to see.
    verdict(
      "the scan reaches `trust_status` — the statement CR-5 was raised about",
      Enum.any?(authored, fn {p, _t, _c} -> p == "trust_status" end)
    )

    halt_unless(Enum.any?(authored, fn {p, _t, _c} -> p == "trust_status" end))

    # POSITIVE CONTROL for the EXCLUSION, the other direction. The data rows do
    # carry population figures — `175 manifest checks` in the bucket-1 records'
    # own searches — so "0 stale figures" is not an artefact of a scan that
    # excluded everything. Both directions, or neither means anything.
    verdict(
      "and claim-bearing DATA strings exist and are excluded as their file's claim",
      data > 0
    )

    halt_unless(data > 0)

    IO.puts(
      "\n  the guard's report as committed:\n    #{squash(a["population_statement_guard"])}"
    )

    verdict(
      "the report makes no population claim of its own — it is not part of what it attests",
      Crosswalk.population_claims(a["population_statement_guard"]) == []
    )

    # POSITIVE CONTROL: the unmutated generator emits, so a refusal below is the
    # mutation's doing and not a broken build.
    out = tmp("statements-positive")
    run_crosswalk(out)
    IO.puts("\n  POSITIVE  the unmutated generator emits (#{byte_size(File.read!(out))} bytes)")
    File.rm(out)

    task_src = File.read!(@crosswalk_src)
    lib_src = File.read!(@crosswalk_lib)

    # MUTATION 1 — CR-5's DEFECT, PLANTED. The interpolated pair goes back to the
    # literal the committed artefact actually shipped. This is the one that must
    # go red at C1b-iii and C1c instead of shipping a third time.
    mutate!(
      task_src,
      @crosswalk_src,
      ~S|"#{f.declared_members}-member / #{f.declared_checks}-declared-check slice and no " <>|,
      ~S|"48-member / 29-declared-check slice and no " <>|,
      "1  the stale literal CR-5 found, put back into trust_status",
      "are not figures"
    )

    # MUTATION 2 — a figure the run DOES hold, in the WRONG PLACE. The member
    # count becomes the check count: 39 is a figure this crosswalk holds, so the
    # against-the-tree limb cannot see it, and only the phrase pin can. Without
    # this, limb 3 would be decoration.
    mutate!(
      task_src,
      @crosswalk_src,
      ~S|"#{f.declared_members}-member / #{f.declared_checks}-declared-check slice and no " <>|,
      ~S|"#{f.declared_checks}-member / #{f.declared_checks}-declared-check slice and no " <>|,
      "2  a HELD figure interpolated into the wrong slot (39-member, not 68)",
      "do not state the figure this run holds"
    )

    # MUTATION 3 — the scan itself made blind. A regex edit that stops matching
    # leaves every limb green over an artefact nobody read, which is precisely
    # the shape a guard cannot be allowed to fail in. L1 is fail-closed on it.
    mutate!(
      lib_src,
      @crosswalk_lib,
      ~S|@population_claim ~r/(?<![\w-])(\d+)|,
      ~S|@population_claim ~r/zzzz(?<![\w-])(\d+)|,
      "3  the claim regex stops matching — the scan reads an EMPTY population",
      "found NOTHING to read"
    )

    IO.puts("""

      WHAT THESE DO NOT SHOW. That every figure is interpolated: a literal that coincides
      with some OTHER held figure passes limb 2 until the population next moves — and
      `addressed_not_declared` was 14 here, so a stale `14 checks` would have. That is the
      residual, and it is bounded by when it fires (the next move of the population, which
      is when the recurrence lands anyway) rather than argued away. Nor do they reach prose
      the generator does not EMIT: the moduledoc and a branch not taken are outside the
      universe by construction, because the universe is the artefact's own bytes.
    """)
  end

  # Apply a single-line edit to `path`'s source in-VM, require the generator to
  # refuse naming `expect`, and restore. A mutation that does not mutate is a
  # green that means nothing, so a no-op replacement halts rather than passes.
  defp mutate!(src, path, from, to, label, expect) do
    mutated = String.replace(src, from, to)

    if mutated == src do
      IO.puts("  MUTATION COULD NOT BE APPLIED — the line the control edits has moved:")
      IO.puts("    #{inspect(from)}")
      System.halt(1)
    end

    out = tmp("statements-mutated")

    try do
      recompile!(mutated, path)
      refuses("MUTATION #{label}", expect, fn -> run_crosswalk(out) end)

      verdict(
        "         and nothing was written — the guard runs before the file",
        not File.exists?(out)
      )

      halt_unless(not File.exists?(out))
    after
      recompile!(src, path)
      File.rm(out)
    end

    back = tmp("statements-restored")
    run_crosswalk(back)
    verdict("         restored — the same run emits again", File.exists?(back))
    halt_unless(File.exists?(back))
    File.rm(back)
  end

  # --- wsv_tally: the tally that replaced a count in a field NAME (MES-116) ---
  #
  # `oc-axes-c1.json` carried `why_fourteen_rows_share_one_site` on each of
  # C1c-ii's fourteen `WireSchemaValid` rows. The name and the body both held a
  # count, both were TRUE AT THEIR OWN COMMIT, and C1c-iii's nineteen further
  # rows falsified both. The field is now count-free and the tally lives in one
  # place, `the_leg_wide_wire_schema_valid_tally_and_how_it_is_checked`.
  #
  # A tally in a hand-authored JSON is the same defect one level along unless
  # something re-derives it, so this mode does. RECORDED == MEASURED, and not
  # merely `recorded > 0`: a non-zero assertion passes over any wrong number,
  # which is exactly how the figure it replaced survived a whole slice.
  #
  # The two figures come from DIFFERENT artefacts on purpose — one from this
  # file's own rows, one from A1's manifest — because the gap between them is
  # the claim ("one row still undecomposed, and it is C1c-iv's"). A single
  # `N decomposed` would be satisfied by a file that had decomposed the wrong N.
  defp wsv_tally do
    header("WSV TALLY — the leg-wide WireSchemaValid figures, re-derived (MES-116)")

    axes = read(@c1_axes)
    manifest = read(@manifest)

    {agrees?, rows} = wsv_tally_agreement(axes, manifest)

    [{_, _, measured_rows}, {_, _, measured_manifest}, _] = rows

    IO.puts("    rows at #{inspect(@wsv_site)} in #{@c1_axes}:  #{measured_rows}")
    IO.puts("    WireSchemaValid rows in A1's manifest:      #{measured_manifest}")

    for {field, recorded, measured} <- rows do
      verdict(
        "RECORDED == MEASURED — #{field}: recorded #{inspect(recorded)}, measured #{measured}",
        wsv_figure_agrees?(recorded, measured)
      )
    end

    halt_unless(agrees?)

    # THE MUTATIONS RE-DRIVE `wsv_tally_agreement/2` OVER A MUTATED DOCUMENT AND
    # REQUIRE IT TO RETURN FALSE. They used to compare the mutated value against
    # the measurement inline, which reduces to `n + 1 != n` — true for every
    # possible state of the artefacts, so the mutation passed over the very
    # defect it is named for and a WEAKENED comparison sailed through it
    # (measured by CODE_REVIEWER on MES-116, two probes, both exit 0).
    #
    # The comparison now lives in ONE named place, `wsv_figure_agrees?/2`, and
    # the mutations call the same code path the positive control does. Weaken
    # that one function to the `recorded > 0` form the comment below rejects and
    # BOTH mutations go red, because the mutated document then still "agrees".
    #
    # In memory, nothing on disk (S8-14): a seat death mid-run cannot leave the
    # shared clone carrying a wrong tally.

    # (1) THE RECORDED SIDE MOVES and the artefacts do not.
    mutated = put_in(axes, [@wsv_tally_key, "rows_decomposed_at_the_one_site"], measured_rows + 1)
    {mutated_agrees?, _} = wsv_tally_agreement(mutated, manifest)

    verdict(
      "MUTATION — recorded tally #{measured_rows + 1} against a measured #{measured_rows}: " <>
        "the comparison RE-DRIVEN over the mutated document returns FALSE",
      mutated_agrees? == false
    )

    halt_unless(mutated_agrees? == false)

    # (2) THE MEASURED SIDE MOVES and the recorded tally does not — precisely
    # what MES-116's nineteen rows did to C1c-ii's field, so it is the case this
    # mode exists for.
    extra = %{
      "emitting_byte_span" => @wsv_site,
      "key" => ["server", "fixture", "x", "WireSchemaValid", "", ""]
    }

    grown = Map.update!(axes, "checks", &[extra | &1])
    {grown_agrees?, grown_rows} = wsv_tally_agreement(grown, manifest)
    [{_, grown_recorded, grown_measured}, _, _] = grown_rows

    verdict(
      "MUTATION — one more row at the site (#{grown_recorded} recorded vs #{grown_measured} " <>
        "measured): the comparison RE-DRIVEN over the grown document returns FALSE",
      grown_agrees? == false
    )

    halt_unless(grown_agrees? == false)
  end

  # THE COMPARISON, lifted out of the loop and NAMED so that a mutation can
  # re-drive it and so that weakening it is a change in ONE place. Both sides
  # are read out of the documents it is handed, so a mutation of EITHER side
  # changes its answer — which is what makes the mutations falsifiable.
  defp wsv_tally_agreement(axes, manifest) do
    tally = axes[@wsv_tally_key]

    measured_rows = axes["checks"] |> Enum.count(&(&1["emitting_byte_span"] == @wsv_site))

    measured_manifest =
      manifest["scenarios"]
      |> Enum.flat_map(& &1["checks"])
      |> Enum.count(&(&1["name"] == "WireSchemaValid"))

    rows = [
      {"rows_decomposed_at_the_one_site", tally["rows_decomposed_at_the_one_site"],
       measured_rows},
      {"in_denominator_wire_schema_valid_rows_in_A1s_manifest",
       tally["in_denominator_wire_schema_valid_rows_in_A1s_manifest"], measured_manifest},
      {"remaining_undecomposed", tally["remaining_undecomposed"],
       measured_manifest - measured_rows}
    ]

    {Enum.all?(rows, fn {_field, recorded, measured} ->
       wsv_figure_agrees?(recorded, measured)
     end), rows}
  end

  # RECORDED == MEASURED, and not merely `recorded > 0`: a non-zero assertion
  # passes over any wrong number, which is exactly how the figure this tally
  # replaced survived a whole slice. Weakening this one function is the probe.
  defp wsv_figure_agrees?(recorded, measured), do: recorded == measured

  defp verdict(label, true), do: IO.puts("  ok    #{label}")
  defp verdict(label, false), do: IO.puts("  FAIL  #{label}")

  defp halt_unless(true), do: :ok
  defp halt_unless(false), do: System.halt(1)

  defp require_harness! do
    if File.exists?(@harness) do
      :ok
    else
      IO.puts("""
        HARNESS ABSENT at #{@harness}.
        These controls cannot run, and that is reported rather than skipped: an unrun
        control and a null result are the same artefact (MES-56).
      """)

      System.halt(1)
    end
  end

  defp tmp(stem),
    do: Path.join(System.tmp_dir!(), "mes97-#{stem}-#{System.unique_integer([:positive])}.json")

  defp write_tmp(stem, doc) do
    path = tmp(stem)
    File.write!(path, Jason.encode!(doc))
    path
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp md5(bin), do: :crypto.hash(:md5, bin) |> Base.encode16(case: :lower)
  defp first_line(msg), do: msg |> String.split("\n") |> hd()
  defp header(t), do: IO.puts("\n== #{t} ==\n")
end

CrosswalkControls.run(System.argv())

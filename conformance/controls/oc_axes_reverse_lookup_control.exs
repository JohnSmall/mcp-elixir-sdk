#!/usr/bin/env elixir
# MES-76 (F1) CONTROL — the reverse lookup, RUN against the real harness build.
#
#     mix run conformance/controls/oc_axes_reverse_lookup_control.exs recut
#     mix run conformance/controls/oc_axes_reverse_lookup_control.exs locate
#     mix run conformance/controls/oc_axes_reverse_lookup_control.exs all
#
# ## Why this is a control and not an ExUnit test
#
# It needs the harness build at `/tmp/confalpha/package/dist/index.js`, which is
# a /tmp artefact and absent on most trees. A test requiring it would be red for
# reasons that say nothing about the tree; a test SKIPPING it when absent would
# be the worse failure, because "checked, and fine" and "never asked" would
# print identically — which is the very defect F3 is about. So the suite asserts
# what the ARTEFACT carries, and this control asserts that what it carries is
# TRUE OF THE BUILD.
#
# It is also the answer to the standing "do not build a mix task" ruling: the
# input is a /tmp build, so this is a control a reader runs when they have that
# build, not a gate that pretends to run everywhere.
#
# ## What each subcommand establishes
#
#   * `recut`  — step 0 of `reverse_lookup_procedure`. Cut every row out of the
#                dist by BOTH recorded span kinds and compare byte-for-byte with
#                the committed `evaluator_excerpt`. 13 rows x 2 spans = 26
#                comparisons. This is what makes "the reverse lookup for a known
#                row is a constant-time cut" a measurement rather than a claim.
#
#   * `locate` — step 1, the hard hop. For every row, grep the dist for what the
#                row's own `locator.grep_for` says to grep, and check the hit
#                count against `locator.check_id_occurrences`. Then walk the
#                three form-specific second hops and show each ARRIVING at the
#                emitting site.
#
# ## The build is identified, not assumed
#
# Both subcommands refuse unless the file's sha256 equals the artefact's
# recorded `harness_dist_sha256`. A reverse lookup verified against a lookalike
# build would be a green that means nothing — A1 residual R3, one level down.
defmodule OCAxesReverseLookupControl do
  @axes_path "docs/conformance/oc-axes-2026-07-28.json"
  @template_prefix "sep-2575-http-server-method-not-found-404-"
  @constant_binding "Za=`sep-2106-no-network-ref-deref`"
  @constant_site_ref "id:Za"

  def run(["recut"]), do: with_build(&recut/2)
  def run(["locate"]), do: with_build(&locate/2)

  def run(["all"]) do
    with_build(&recut/2)
    with_build(&locate/2)
  end

  def run(_) do
    IO.puts("usage: recut | locate | all")
    System.halt(2)
  end

  # --- the build, identified by sha before anything is measured ---

  defp with_build(fun) do
    axes = @axes_path |> File.read!() |> Jason.decode!()
    path = axes["provenance"]["read_from"]
    expected = axes["provenance"]["harness_dist_sha256"]

    unless File.exists?(path) do
      IO.puts("""

      CONTROL DID NOT FIRE (not a result)
        the harness build is absent at #{path}
        this control needs it; the ExUnit suite deliberately does not.
      """)

      System.halt(2)
    end

    raw = File.read!(path)
    actual = :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)

    if actual != expected do
      IO.puts("""

      CONTROL REFUSES (not a result)
        #{path}
        sha256 recorded #{expected}
        sha256 on disk  #{actual}
        These axes are a READING OF A PREDICATE AT ONE BUILD. Verifying them
        against a different build would be a green that means nothing.
      """)

      System.halt(1)
    end

    fun.(axes, raw)
  end

  # --- recut: step 0, both span kinds, byte-for-byte ---

  defp recut(axes, raw) do
    header("RECUT — every row cut from the dist by BOTH recorded spans")
    text = raw

    results =
      Enum.map(axes["checks"], fn check ->
        site = check["emitting_site"]
        excerpt = check["evaluator_excerpt"]
        [b_start, b_end] = site["dist_byte_span"]
        [c_start, c_end] = site["dist_char_span"]

        by_byte = binary_part(raw, b_start, b_end - b_start) == excerpt
        by_char = String.slice(text, c_start, c_end - c_start) == excerpt

        {Enum.at(check["key"], 2), Enum.at(check["key"], 5), by_byte, by_char}
      end)

    for {check_id, discriminator, by_byte, by_char} <- results do
      IO.puts(
        "  #{mark(by_byte)} byte  #{mark(by_char)} char   " <>
          check_id <> if(discriminator == "", do: "", else: "##{discriminator}")
      )
    end

    ok = Enum.count(results, fn {_, _, b, c} -> b and c end)
    total = length(results)

    comparisons =
      Enum.count(results, fn {_, _, b, _} -> b end) +
        Enum.count(results, fn {_, _, _, c} -> c end)

    IO.puts("""

      rows re-cut identical on BOTH spans   #{ok} / #{total}
      individual comparisons passing        #{comparisons} / #{total * 2}
    """)

    if ok != total, do: System.halt(1)
  end

  # --- locate: step 1 and the three second hops ---

  defp locate(axes, raw) do
    header("LOCATE — grep what the locator SAYS to grep, then walk the second hop")

    failures =
      Enum.flat_map(axes["checks"], fn check ->
        check_id = Enum.at(check["key"], 2)
        site = check["emitting_site"]
        locator = site["locator"]

        id_hits = count(raw, check_id)
        grep_hits = count(raw, locator["grep_for"])

        recorded_ok = id_hits == locator["check_id_occurrences"]
        {hop_ok, hop_note} = second_hop(site["form"], raw, check_id, grep_hits)

        IO.puts(
          "  #{mark(recorded_ok and hop_ok)} #{String.pad_trailing(site["form"], 9)} " <>
            "id_hits=#{id_hits} (recorded #{locator["check_id_occurrences"]})  " <>
            "grep_for_hits=#{grep_hits}  #{check_id}"
        )

        IO.puts("        #{hop_note}")

        if recorded_ok and hop_ok, do: [], else: [check_id]
      end)

    IO.puts("""

      rows whose locator did NOT reproduce   #{length(failures)} / #{length(axes["checks"])}
    """)

    if failures != [], do: System.halt(1)
  end

  # The three cases of `reverse_lookup_procedure.cases`, each shown ARRIVING.
  defp second_hop("template", raw, _check_id, grep_hits) do
    prefix_hits = count(raw, @template_prefix)

    {grep_hits == 1 and prefix_hits == 1,
     "0 hits on the id; the literal prefix #{inspect(@template_prefix)} hits #{prefix_hits}x " <>
       "and lands on the ${t} loop"}
  end

  defp second_hop("constant", raw, _check_id, _grep_hits) do
    binding? = String.contains?(raw, @constant_binding)
    site? = String.contains?(raw, @constant_site_ref)

    {binding? and site?,
     "the single hit is the BINDING #{inspect(@constant_binding)}; the bound name reaches the " <>
       "site via #{inspect(@constant_site_ref)} (present: #{site?})"}
  end

  defp second_hop("literal", raw, check_id, grep_hits) when grep_hits == 2 do
    own? = String.contains?(raw, "`" <> check_id <> "`")
    as_prefix? = String.contains?(raw, check_id <> "-${")

    {own? and as_prefix?,
     "2 hits: own literal id (backtick-delimited: #{own?}) and the same id as a TEMPLATE " <>
       "PREFIX (#{check_id}-${: #{as_prefix?})"}
  end

  defp second_hop("literal", raw, check_id, _grep_hits) do
    own? = String.contains?(raw, "a(`" <> check_id <> "`")

    {own?, "1 hit, in the first argument position of an a( call: #{own?}"}
  end

  defp count(haystack, needle) do
    haystack |> String.split(needle) |> length() |> Kernel.-(1)
  end

  defp mark(true), do: "ok  "
  defp mark(false), do: "FAIL"

  defp header(title) do
    IO.puts("\n== #{title} ==\n")
  end
end

OCAxesReverseLookupControl.run(System.argv())

#!/usr/bin/env elixir
# MES-94 — GUARD 29's TWO CONTROLS, committed.
#
#     mix run conformance/controls/etcc_citation_controls.exs positive
#     mix run conformance/controls/etcc_citation_controls.exs mutation
#     mix run conformance/controls/etcc_citation_controls.exs limb-b
#     mix run conformance/controls/etcc_citation_controls.exs all
#
# ## Why three, and why none of them alone is evidence
#
# Guard 29 is a 0-or-1 scan: it reports the citations it could not resolve. Two
# different things make such a scan green, and only one of them is good news.
#
#   * **POSITIVE** — the extractor really reaches the population. An extractor
#     that found nothing would satisfy *"every cited key is a key the register
#     carries"* for free, on every document, for ever. This control runs the real
#     extractor over the real committed `etcc-register.md` and prints what it
#     found, so the denominator is on the record rather than assumed.
#
#   * **MUTATION** — limb A's predicate can fire. A guard that only ever passes is
#     not evidence (S8-3). This control perturbs **one character** of one real row
#     key and requires guard 29 to refuse, naming it — and then re-runs the
#     unmutated document to show the guard discriminates rather than refusing
#     everything.
#
#   * **LIMB-B** — limb B's predicate can fire, and it is a SEPARATE predicate. The
#     mutation above only ever reddens limb A, so it says nothing about the ratchet.
#     The limb B first delivered on MES-94 keyed its allow-list on citation TEXT, so
#     a live `:353` written anywhere passed because `:353` is grandfathered in §6 —
#     CODE_REVIEWER falsified it before it merged. This control reproduces that
#     probe, in both of its shapes: a permitted token in a section that does not
#     permit it, and a DUPLICATE of a permitted token inside the section that does.
#     Both must be refused, and the unmutated document must pass in the same run.
#
# ## The mutation is made on a COPY, and the real tree is never written to
#
# `check!/1` takes a root, so the whole control runs against a throwaway root
# holding just the two files it reads. Nothing restores anything, because nothing
# was changed: a mid-run death cannot leave `docs/` mutated (S8-14).

defmodule ETCCCitationControls do
  alias MCP.Conformance.Citations

  @named "MCP.ClientTest/test lifecycle times out a pending request"
  @duplicated ":353"

  def main(["positive"]), do: positive() |> finish()
  def main(["mutation"]), do: mutation() |> finish()
  def main(["limb-b"]), do: limb_b() |> finish()

  def main(["all"]) do
    # Each is run — `and` would short-circuit and hide a later failure behind an
    # earlier one, which is the opposite of what a control run is for.
    [positive(), mutation(), limb_b()] |> Enum.all?() |> finish()
  end

  def main(_), do: halt("usage: positive | mutation | limb-b | all")

  # --- POSITIVE ------------------------------------------------------------
  defp positive do
    section("POSITIVE CONTROL — the extractor reaches the population")

    doc = Citations.read_document()
    keys = Citations.keys(doc)
    occurrences = doc |> Citations.code_spans() |> Enum.count(&(&1.text in keys))
    register = Citations.register_keys()
    lines = Citations.line_citations(doc)
    permitted = Citations.permitted_line_citations()

    IO.puts("  distinct row keys cited in the prose : #{length(keys)}")
    IO.puts("  occurrences of those keys            : #{occurrences}")
    IO.puts("  keys in etcc-register.json           : #{MapSet.size(register)}")
    IO.puts("  line-shaped citations still present  : #{length(lines)}")

    IO.puts("\n  where the line-shaped ones stand, counted not asserted:")

    lines
    |> Enum.group_by(& &1.section)
    |> Enum.sort()
    |> Enum.each(fn {section, found} ->
      classes =
        found
        |> Enum.map(fn c -> elem(Map.fetch!(permitted, {c.section, c.text}), 0) end)
        |> Enum.frequencies()
        |> Enum.sort()
        |> Enum.map_join(", ", fn {class, n} -> "#{n} #{inspect(class)}" end)

      IO.puts("    #{String.pad_trailing(section, 5)} #{length(found)}  (#{classes})")
    end)

    IO.puts("\n  a key named by hand, and found by the extractor:")
    IO.puts("    #{@named}")

    checks = [
      {"the extractor found keys at all", length(keys) > 50},
      {"the hand-named key is among them", @named in keys},
      {"every cited key is carried by the register",
       Enum.all?(keys, &MapSet.member?(register, &1))},
      {"the document is not key-free by accident", occurrences > 100},
      {"every line-shaped citation is permitted WHERE IT STANDS",
       Enum.all?(lines, &Map.has_key?(permitted, {&1.section, &1.text}))}
    ]

    report(checks)
  end

  # --- MUTATION ------------------------------------------------------------
  defp mutation do
    section("MUTATION — one character, and guard 29 must refuse")

    doc = Citations.read_document()
    true = String.contains?(doc, @named)

    mutated =
      String.replace(doc, @named, String.replace(@named, "times out", "times ouT"), global: false)

    true = mutated != doc

    unmutated_verdict = in_root(doc, &Citations.check!/1)
    mutated_verdict = in_root(mutated, fn root -> safe(fn -> Citations.check!(root) end) end)

    IO.puts("  mutation: `times out` -> `times ouT`, in ONE occurrence of")
    IO.puts("            #{@named}")

    {refused?, message} =
      case mutated_verdict do
        {:raised, msg} -> {true, msg}
        {:ok, _} -> {false, "(guard 29 returned a PASS over the mutated document)"}
      end

    IO.puts("\n  guard 29 over the MUTATED document:")
    IO.puts(indent(message))

    checks = [
      {"the mutated document is REFUSED", refused?},
      {"the refusal names the perturbed key",
       refused? and String.contains?(message, "times ouT")},
      {"the refusal is limb A, not limb B", refused? and String.contains?(message, "LIMB A")},
      {"the UNMUTATED document still PASSES (it discriminates)", unmutated_verdict.ok?}
    ]

    report(checks)
  end

  # --- LIMB B --------------------------------------------------------------
  defp limb_b do
    section("LIMB B MUTATION — a duplicate permitted token must be refused")

    doc = Citations.read_document()

    # (i) CODE_REVIEWER's probe verbatim: a LIVE citation using a grandfathered
    #     string, appended to the document. `:353` is permitted in §6; the end of
    #     the document is §11, which permits nothing.
    appended = doc <> "\n\nThe unit is cited live at `#{@duplicated}` here.\n"

    # (ii) the PM's named case: a DUPLICATE inside the very section that permits
    #      it. `:353` is permitted three times in §6; this makes four. The insert
    #      goes immediately after §6's own heading, so it moves with the document
    #      instead of being pinned to a line number.
    duplicated =
      insert_after_section_6(doc, "A live citation at `#{@duplicated}`, inserted in §6.")

    true = appended != doc and duplicated != doc

    unmutated = in_root(doc, &Citations.check!/1)
    {appended?, appended_msg} = refused?(appended)
    {duplicated?, duplicated_msg} = refused?(duplicated)

    IO.puts("  the token reused in both probes: #{@duplicated}, permitted 3 times in §6")

    IO.puts("\n  (i) the SAME token written live in another section:")
    IO.puts(indent(appended_msg))
    IO.puts("\n  (ii) a FOURTH occurrence inside §6, which permits three:")
    IO.puts(indent(duplicated_msg))

    checks = [
      {"(i) the same permitted token in another section is REFUSED", appended?},
      {"(i) the refusal is limb B, and says UNLISTED",
       appended? and String.contains?(appended_msg, "LIMB B") and
         String.contains?(appended_msg, "UNLISTED")},
      {"(ii) a duplicate inside the permitting section is REFUSED", duplicated?},
      {"(ii) the refusal names both counts",
       duplicated? and String.contains?(duplicated_msg, "OVER-COUNT, 4 written") and
         String.contains?(duplicated_msg, "3 permitted")},
      {"the UNMUTATED document still PASSES (it discriminates)", unmutated.ok?},
      {"and it passes with no stale permission left behind", unmutated.stale_permissions == []}
    ]

    report(checks)
  end

  defp refused?(document) do
    case in_root(document, fn root -> safe(fn -> Citations.check!(root) end) end) do
      {:raised, message} -> {true, message}
      {:ok, _} -> {false, "(guard 29 returned a PASS over the mutated document)"}
    end
  end

  defp insert_after_section_6(document, inserted) do
    lines = String.split(document, "\n")
    at = Enum.find_index(lines, &String.starts_with?(&1, "## §6 "))
    true = at != nil

    {before, rest} = Enum.split(lines, at + 1)
    Enum.join(before ++ ["", inserted] ++ rest, "\n")
  end

  # --- plumbing ------------------------------------------------------------
  defp in_root(document, fun) do
    root = Path.join(System.tmp_dir!(), "mes94_citations_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "docs/conformance"))
    File.write!(Path.join(root, "docs/conformance/etcc-register.md"), document)

    File.cp!(
      "docs/conformance/etcc-register.json",
      Path.join(root, "docs/conformance/etcc-register.json")
    )

    try do
      fun.(root)
    after
      File.rm_rf!(root)
    end
  end

  defp safe(fun) do
    {:ok, fun.()}
  rescue
    e in RuntimeError -> {:raised, Exception.message(e)}
  end

  defp report(checks) do
    IO.puts("")

    Enum.each(checks, fn {label, ok?} ->
      IO.puts("  #{if ok?, do: "ok  ", else: "FAIL"}  #{label}")
    end)

    Enum.all?(checks, &elem(&1, 1))
  end

  defp indent(text), do: text |> String.split("\n") |> Enum.map_join("\n", &("    " <> &1))

  defp section(title) do
    IO.puts("\n" <> String.duplicate("=", 78))
    IO.puts(title)
    IO.puts(String.duplicate("=", 78))
  end

  defp finish(true), do: IO.puts("\nALL CONTROLS PASSED\n")
  defp finish(false), do: halt("CONTROLS FAILED")

  defp halt(message) do
    IO.puts("\n" <> message)
    System.halt(1)
  end
end

ETCCCitationControls.main(System.argv())

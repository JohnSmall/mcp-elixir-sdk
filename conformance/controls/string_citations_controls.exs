# Controls for G33, the string-citation guard (MES-192).
#
#     MIX_ENV=test mix run conformance/controls/string_citations_controls.exs all
#
# One mode, `all` (MES-192 ruling 32779 A3). It runs four limbs, in order, in
# one VM:
#
#   P   positive      the REAL tree audits clean, and the planted universe of
#                     `MCP.Conformance.StringCitationControls` audits clean
#                     before any plant.
#   K   planted       every control (C1-C17 with their letters) holds: it
#                     produces its refusal KIND, and the line names G33; or,
#                     for C17a-b (expect: moved), --resolve re-addresses the
#                     window without that refusal and the result audits clean;
#                     for C19a-b (expect: clean), the planted universe audits
#                     clean.
#   R   reverted      for each control, the guard is recompiled IN MEMORY with
#                     that control's limb (a clause of `limb/2`) answering [],
#                     or, for C17a-c and C19a-d, the identity or association
#                     predicate replaced by its stub (the pre-fix whole match;
#                     or never), and the
#                     control must then FAIL. The unplanted universe must stay clean under
#                     the same recompiled guard, so a red here is the limb's
#                     absence and not a broken build. A control with several
#                     reverts (C27a) is run under each; a revert that names
#                     matrix cells must fail every one of them.
#   B   restored      the compiled .beam is reloaded; its md5 must equal the one
#                     recorded before P, every control holds again, and the
#                     guard's source sha256 is unchanged.
#
# NOTHING IS WRITTEN. The plants live in memory; the guard's source is read and
# compiled from a string, never written (a killed VM leaves at most a mutated
# module in a VM that no longer exists, S8-14). Run `git status --porcelain`
# after it all the same.
#
# Exit 0 only if every limb holds; 1 otherwise, naming the control and limb.

defmodule StringCitationsControls do
  alias MCP.Conformance.StringCitationControls, as: C
  alias MCP.Conformance.StringCitations, as: S

  @src "conformance/lib/mcp/conformance/string_citations.ex"

  def main(["all"]) do
    source = File.read!(@src)
    src_sha = sha(source)
    md5 = S.module_info(:md5)

    header("P — positive: the real tree, and the unplanted universe")
    %{defects: real, report: r} = S.audit(S.load())

    IO.puts(
      "  real tree: #{r["occurrences"]} occurrence(s), #{r["byte_checked"]} byte-checked, #{length(real)} defect(s)"
    )

    check(real == [], "P: the real tree audits with #{length(real)} defect(s)")
    check(C.positive() == [], "P: the unplanted universe is not clean")

    header("K — planted: each control is refused with its kind, naming G33")
    for c <- C.controls(), do: line(c, C.holds?(c), expected(c))

    header("R — reverted: each control's limb neutralised in memory; the control must FAIL")

    for c <- C.controls(), r <- C.reverts(c) do
      mutate(source, r)
      clean = C.positive() == []
      {held, failed} = C.verdict(c)
      missed = Map.get(r, :cells, []) -- failed

      line(
        c,
        not held and clean and missed == [],
        "#{neutralised(r)} off: #{if held, do: "STILL holds", else: "fails"}; unplanted #{if clean, do: "clean", else: "NOT clean"}" <>
          cells_note(r, failed, missed)
      )
    end

    header("B — restored: the compiled .beam reloaded")
    :code.purge(S)
    {:module, S} = :code.load_file(S)
    check(S.module_info(:md5) == md5, "B: the reloaded md5 differs from P's")
    check(Enum.all?(C.controls(), &C.holds?/1), "B: a control no longer holds after the reload")
    check(sha(File.read!(@src)) == src_sha, "B: #{@src} changed during the run")
    IO.puts("  md5 #{Base.encode16(md5, case: :lower)} (unchanged)")
    IO.puts("  #{@src} sha256 #{src_sha} (unchanged)")

    finish()
  end

  def main(_) do
    IO.puts(
      :stderr,
      "usage: MIX_ENV=test mix run conformance/controls/string_citations_controls.exs all"
    )

    System.halt(64)
  end

  # The control's limb answers [] before any real clause can match; a control
  # that names a `stub` instead gets that clause ahead of the real one (the
  # F3 identity predicate, MES-192 correction round 1).
  defp mutate(source, %{stub: {anchor, clause}}), do: compile_with(source, anchor, clause)

  defp mutate(source, %{limb: limb}),
    do: compile_with(source, "  defp limb(", "  defp limb(#{inspect(limb)}, _ctx), do: []\n\n")

  defp compile_with(source, anchor, clause) do
    mutated = String.replace(source, anchor, clause <> anchor, global: false)
    if mutated == source, do: fail("R: no `#{String.trim(anchor)}` clause to neutralise")
    {_, _diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(mutated, @src) end)
  end

  defp expected(%{expect: :moved, kind: k}), do: "re-addressed, no #{k} refusal, clean after"
  defp expected(%{expect: :clean, kind: k}), do: "audits clean, no #{k}"
  defp expected(%{mode: :meta}), do: "every refusal kind names a fix"
  defp expected(%{mode: :entry_points, kind: k}), do: "#{k} from audit, --repin and --resolve"
  defp expected(%{mode: :runtime_kinds}), do: "runtime kinds declared, each with a fix"

  defp expected(%{mode: :type_matrix}),
    do:
      "#{length(C.cells())} cells (#{length(C.matrix_fields())} fields) x 3 entry points, each refused, none raised"

  defp expected(%{mode: :field_list}),
    do: "#{length(C.matrix_fields())} fields read from the guard's schema declaration"

  defp expected(%{kind: k}), do: "refused #{k}"

  # A revert that names cells: the matrix cells it failed, and any it should
  # have failed and did not.
  defp cells_note(%{cells: want}, failed, []),
    do: "; cells failed #{inspect(Enum.filter(failed, &(&1 in want)))} of #{length(failed)}"

  defp cells_note(%{cells: _}, _failed, missed), do: "; cells NOT failed #{inspect(missed)}"
  defp cells_note(_r, _failed, _missed), do: ""

  defp neutralised(%{stub: {anchor, _}}), do: String.trim(anchor) <> "...)"
  defp neutralised(%{limb: limb}), do: "limb #{limb}"

  defp line(c, ok, what) do
    IO.puts(
      "  #{if ok, do: "ok  ", else: "FAIL"} #{String.pad_trailing(c.id, 5)} #{String.pad_trailing(c.what, 58)} #{what}"
    )

    unless ok, do: Process.put(:failed, [c.id | Process.get(:failed, [])])
  end

  defp check(true, _why), do: :ok
  defp check(false, why), do: fail(why)

  defp fail(why), do: Process.put(:failed, [why | Process.get(:failed, [])])

  defp header(t), do: IO.puts("\n" <> t)

  defp finish do
    case Process.get(:failed, []) do
      [] ->
        IO.puts("\nG33 CONTROLS: all limbs hold (P, K, R, B).")

      failed ->
        IO.puts("\nG33 CONTROLS FAILED: #{inspect(Enum.reverse(failed))}")
        System.halt(1)
    end
  end

  defp sha(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
end

StringCitationsControls.main(System.argv())

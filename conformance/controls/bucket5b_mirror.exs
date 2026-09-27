# The Confluence bucket-5b page (278036481) as a MIRROR of the D5 records
# (MES-146, the closing D5b slice; plan 30137 item 7, ratified 30138 Q8).
#
#     mix run conformance/controls/bucket5b_mirror.exs blocks "<synced from>"
#     mix run conformance/controls/bucket5b_mirror.exs text "<synced from>"
#
# `blocks` prints the page body as the wrapper's typed content blocks (JSON),
# the `content` argument of confluence_update_page. `text` prints the same
# body flattened to one line per block and per table row, so a reader can
# regenerate it and diff it against the page's read-back text (census by
# reproduction). "<synced from>" is printed verbatim in the banner, e.g.
# "branch MES-146 at b15e375" or, at the merge gate, "main at <merge sha>".
#
# Everything on the page is derived from the records the directory walk finds
# (no hand-held record list). The page is an index: tag, member, disposition,
# discounts and null outcomes per row, plus the whole-view summary. Rationale
# and limbs are not copied; each record is named by its repository path, and
# the repository record wins. The gate-5 unit "the bucket-5b view, whole
# (MES-146)" holds the summary's figures.

defmodule Bucket5bMirror do
  alias MCP.Conformance.Adjudications, as: A

  @walk "docs/conformance/adjudications"
  @v5b "docs/conformance/buckets/bucket-5b-2026-07-28.json"
  @page "https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/278036481"

  def main(["blocks", synced]), do: synced |> blocks() |> Jason.encode!() |> IO.puts()

  def main(["text", synced]),
    do: synced |> blocks() |> Enum.flat_map(&text/1) |> Enum.each(&IO.puts/1)

  def main(_) do
    IO.puts(:stderr, ~s|usage: mix run #{__ENV__.file} blocks\|text "<synced from>"|)
    System.halt(2)
  end

  # {path, record, section} for every section on the bucket-5b view, in walk order.
  def sections do
    for path <- Path.wildcard(Path.join(@walk, "*.json")) |> Enum.sort(),
        rec = path |> File.read!() |> Jason.decode!(),
        s <- rec["sections"],
        s["view"] == @v5b,
        do: {path, rec, s}
  end

  def blocks(synced) do
    secs = sections()
    rows = for {_, rec, s} <- secs, r <- s["rows"], do: {rec["ticket"], r}
    closer = for {_, rec, %{"closure" => "closed"}} <- secs, do: rec["ticket"]
    grains = for t <- A.discount_types(), g <- A.discount_grains(), do: "#{t}/#{g}"

    [
      panel("note", [
        p([
          b("MIRROR. "),
          t("The normative records are the repository files listed under "),
          b("Records"),
          t(" below. This page is generated from them by "),
          c("conformance/controls/bucket5b_mirror.exs"),
          t(". Where the page and a record differ, the record wins.")
        ]),
        p([b("Synced from: "), c(synced), t(".")]),
        p([
          t(
            "Bucket 5b is CLOSED by #{Enum.join(closer, ", ")}: every one of the view's " <>
              "#{length(rows)} rows is adjudicated by exactly one D5 record row (guard G32)."
          )
        ])
      ]),
      panel("warning", [
        p([
          b("A green here is evidence that two instruments agree, NOT evidence of correctness."),
          t(
            " Every row of this bucket is green in both suites: our ET-CC member passes and " <>
              "the official harness's check passes. That says the two instruments agree on " <>
              "this SDK. It does not say that either would go red if the behaviour broke; " <>
              "that is the question the disposition answers, row by row."
          )
        ])
      ]),
      h(2, "The D5 question"),
      p([
        t(
          "Which of these greens would go red if the behaviour broke? The OC side is " <>
            "recomputed by G32 from the committed null censuses (a do-nothing client); the " <>
            "ET side is measured by scratch lib/ mutation, with the real harness run on " <>
            "each limb. Each row gets exactly one disposition, a function of that evidence:"
        )
      ]),
      ul([
        [b("discriminating"), t(": both sides can go red.")],
        [
          b("vacuous_oc"),
          t(": a do-nothing client passes or skips the OC check; the ET member can go red.")
        ],
        [
          b("vacuous_et"),
          t(
            ": the OC check can go red, but a measured mutation that breaks the behaviour " <>
              "leaves our member green."
          )
        ],
        [b("vacuous_both"), t(": neither side goes red on the evidence.")],
        [b("not_established"), t(": the evidence does not settle it; the row says why.")]
      ]),
      p([
        t(
          "Discounts are an attribute, not a disposition, and the two types are kept " <>
            "separate: a null discount (a committed null census passes or skips the check " <>
            "or its scenario) and a drive-policy discount (the adapter kept driving after " <>
            "a failure). Null outcomes are claimed only where the census counts entail them."
        )
      ]),
      h(2, "Whole-view summary"),
      p([
        t(
          "Counted from the records, not from close-outs; the gate-5 unit " <>
            "\"the bucket-5b view, whole (MES-146)\" holds the same figures."
        )
      ]),
      count_table(rows, "disposition", A.d5_dispositions(), &(&1["disposition"] == &2)),
      count_table(
        rows,
        "discount (rows carrying it)",
        grains,
        fn r, k -> Enum.any?(r["discounts"], &("#{&1["type"]}/#{&1["grain"]}" == k)) end
      ),
      count_table(
        rows,
        "null outcome (rows with it in any census)",
        A.null_outcomes(),
        fn r, k -> Enum.any?(r["oc_null"], &(&1["outcome"] == k)) end
      ),
      h(2, "Records")
    ] ++
      Enum.flat_map(secs, fn {path, rec, s} ->
        [
          h(
            3,
            "#{rec["ticket"]}: #{Path.basename(s["view"], "-2026-07-28.json")} " <>
              "(#{length(s["rows"])} rows, #{s["closure"]}#{owner(s)})"
          ),
          p([c(path)]),
          p([t(s["slice"]["statement"])]),
          row_table(s["rows"])
        ]
      end) ++
      [p([t("Page: "), t(@page)])]
  end

  defp owner(%{"closure" => "open", "owner" => o}), do: ", owner #{o}"
  defp owner(_), do: ""

  defp count_table(rows, label, keys, pred) do
    tickets = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    count = fn rs, k -> rs |> Enum.count(fn {_, r} -> pred.(r, k) end) |> Integer.to_string() end

    body =
      for tk <- tickets do
        rs = Enum.filter(rows, &(elem(&1, 0) == tk))
        [tk | Enum.map(keys, &count.(rs, &1))] ++ [Integer.to_string(length(rs))]
      end

    total = ["all" | Enum.map(keys, &count.(rows, &1))] ++ [Integer.to_string(length(rows))]
    table(["#{label}: record" | keys] ++ ["rows"], body ++ [total])
  end

  defp row_table(rows) do
    body =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {r, i} ->
        [
          Integer.to_string(i),
          r["tag"],
          r["member"],
          r["disposition"],
          discounts(r["discounts"]),
          nulls(r["oc_null"])
        ]
      end)

    table(["#", "tag", "member", "disposition", "discounts", "null outcomes"], body)
  end

  defp discounts([]), do: "-"
  defp discounts(ds), do: Enum.map_join(ds, ", ", &"#{&1["type"]}/#{&1["grain"]}")

  defp nulls(ns),
    do:
      Enum.map_join(ns, ", ", fn n ->
        "#{n["census"] |> Path.basename(".json") |> String.replace("client-2026-07-28-", "")} #{n["outcome"]}"
      end)

  # --- typed blocks -----------------------------------------------------------

  defp t(s), do: %{"t" => "text", "text" => s}
  defp b(s), do: %{"t" => "text", "text" => s, "marks" => ["strong"]}
  defp c(s), do: %{"t" => "text", "text" => s, "marks" => ["code"]}
  defp p(inl), do: %{"t" => "p", "c" => inl}
  defp h(l, s), do: %{"t" => "h", "level" => l, "c" => [t(s)]}
  defp panel(v, bs), do: %{"t" => "panel", "variant" => v, "c" => bs}
  defp ul(items), do: %{"t" => "ul", "c" => Enum.map(items, &%{"t" => "li", "c" => [p(&1)]})}

  defp table(head, body) do
    cell = fn hdr, s -> %{"header" => hdr, "c" => [p([t(s)])]} end

    %{
      "t" => "table",
      "rows" => [
        Enum.map(head, &cell.(true, &1))
        | Enum.map(body, fn r -> Enum.map(r, &cell.(false, &1)) end)
      ]
    }
  end

  # --- flattened text, one line per block and per table row ------------------

  def text(%{"t" => "table", "rows" => rows}),
    do: Enum.map(rows, fn r -> Enum.map_join(r, " | ", &cells/1) end)

  def text(%{"t" => t, "c" => bs}) when t in ["panel", "ul"], do: Enum.flat_map(bs, &text/1)
  def text(%{"t" => "li", "c" => bs}), do: Enum.flat_map(bs, &text/1)
  def text(%{"c" => inl}), do: [Enum.map_join(inl, "", & &1["text"])]

  defp cells(%{"c" => bs}), do: Enum.map_join(bs, " ", &(&1 |> text() |> Enum.join(" ")))
end

Bucket5bMirror.main(System.argv())

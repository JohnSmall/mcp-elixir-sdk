# The Confluence bucket-1 page (277741649) as a MIRROR of the D1 records
# (MES-143, the closing D1 slice; plan 29990 item 8, ratified 29991 Q5).
#
#     mix run conformance/controls/bucket1_mirror.exs blocks "<synced from>"
#     mix run conformance/controls/bucket1_mirror.exs text "<synced from>"
#
# `blocks` prints the page body as the wrapper's typed content blocks (JSON),
# the `content` argument of confluence_update_page. `text` prints the same
# body flattened to one line per block and per table row, so a reader can
# regenerate it and diff it against the page's read-back text (census by
# reproduction). "<synced from>" is printed verbatim in the banner, e.g.
# "branch MES-143 at cef293f" or, at the merge gate, "main at <merge sha>".
#
# Everything on the page is derived from the records the directory walk finds
# (no hand-held record list). The page is an index: tag, member, verdict and
# route per row, plus the whole-view summary. Rationale is not copied; each
# record is named by its repository path, and the repository record wins.

defmodule Bucket1Mirror do
  @walk "docs/conformance/adjudications"
  @v1 "docs/conformance/buckets/bucket-1-2026-07-28.json"
  @vcu "docs/conformance/buckets/claim-unmatched-2026-07-28.json"
  @verdicts ~w(genuine_extra_coverage redundant not_a_conformance_claim wrong_against_spec)
  @page "https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/277741649"

  # MES-154's re-verdict set (PM 29984; Q4 of 29990), the same 4 the gate-5
  # whole-view unit holds by key.
  @mes154 [
    "oc:none/no-oc-fixture-case/routing-header-decoded-before-comparison",
    "oc:none/no-oc-scenario/MES-115-retry-identity-re-resolved",
    "oc:none/no-oc-server-check/SEP-2106-server-never-dereferences-a-network-ref",
    "oc:none/no-oc-scenario/MES-117-default-caching-policy-values"
  ]

  def main(["blocks", synced]), do: synced |> blocks() |> Jason.encode!() |> IO.puts()

  def main(["text", synced]),
    do: synced |> blocks() |> Enum.flat_map(&text/1) |> Enum.each(&IO.puts/1)

  def main(_) do
    IO.puts(:stderr, ~s|usage: mix run #{__ENV__.file} blocks\|text "<synced from>"|)
    System.halt(2)
  end

  # {path, record, section} for every section on the two D1 views, in walk order.
  def sections do
    for path <- Path.wildcard(Path.join(@walk, "*.json")) |> Enum.sort(),
        rec = path |> File.read!() |> Jason.decode!(),
        s <- rec["sections"],
        s["view"] in [@v1, @vcu],
        do: {path, rec, s}
  end

  def blocks(synced) do
    secs = sections()
    b1 = for {_, rec, %{"view" => @v1} = s} <- secs, r <- s["rows"], do: {rec["ticket"], r}
    cu = for {_, rec, %{"view" => @vcu} = s} <- secs, r <- s["rows"], do: {rec["ticket"], r}
    closer = for {_, rec, %{"view" => @v1, "closure" => "closed"}} <- secs, do: rec["ticket"]

    [
      panel("note", [
        p([
          b("MIRROR. "),
          t("The normative records are the repository files listed under "),
          b("Records"),
          t(" below. This page is generated from them by "),
          c("conformance/controls/bucket1_mirror.exs"),
          t(". Where the page and a record differ, the record wins.")
        ]),
        p([b("Synced from: "), c(synced), t(".")]),
        p([
          t(
            "Bucket 1 is CLOSED by #{Enum.join(closer, ", ")}: every one of the view's " <>
              "#{length(b1)} rows is adjudicated by exactly one D1 record row (guard G32)."
          )
        ])
      ]),
      h(2, "The D1 question"),
      p([
        t(
          "ET-CC members with no matching in-scope OC check under A3's match relation. " <>
            "Each member gets exactly one verdict:"
        )
      ]),
      ul([
        [
          b("genuine_extra_coverage"),
          t(": keep it; the record states what it protects that OC cannot.")
        ],
        [
          b("redundant"),
          t(
            ": OC covers the same ground and the match rule did not see it. " <>
              "Routed to A3 (MES-152), not fixed here."
          )
        ],
        [
          b("not_a_conformance_claim"),
          t(
            ": a conforming SDK could fail the unit (N5, 29708). " <>
              "Routed to A2 (MES-153)."
          )
        ],
        [
          b("wrong_against_spec"),
          t(": asserts something the specification forbids or contradicts.")
        ]
      ]),
      h(2, "Whole-view summary"),
      p([
        t(
          "Counted from the records, not from close-outs; the gate-5 unit " <>
            "\"the bucket-1 view, whole (MES-143)\" holds the same figures."
        )
      ]),
      count_table(b1, "bucket 1"),
      count_table(cu, "claim-unmatched"),
      h(2, "Routing"),
      p([
        t(
          "Every redundant row is routed to A3 (owner MES-152) and every not_a_conformance_claim " <>
            "row to A2 (owner MES-153); each row's owner_record names the PM's routing comment and item."
        )
      ]),
      routing_table(b1 ++ cu),
      h(2, "For the register: the wrong_against_spec rows"),
      ul(
        for {tk, r} <- b1 ++ cu,
            r["disposition"] == "wrong_against_spec",
            do: [t("#{tk}: "), c(r["tag"])]
      ),
      h(2, "Pending re-verdict: MES-154"),
      p([t("Counted above under their CURRENT verdicts (PM 29984, Q4).")]),
      ul(
        for {tk, r} <- b1 ++ cu,
            r["tag"] in @mes154,
            do: [t("#{tk}: "), c(r["tag"]), t(" (#{view_name(r, b1)}, #{r["disposition"]})")]
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
          row_table(s["rows"])
        ]
      end) ++
      [p([t("Page: "), t(@page)])]
  end

  defp owner(%{"closure" => "open", "owner" => o}), do: ", owner #{o}"
  defp owner(_), do: ""

  defp view_name(r, b1),
    do: if(Enum.any?(b1, fn {_, x} -> x == r end), do: "bucket 1", else: "claim-unmatched")

  defp count_table(rows, label) do
    tickets = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    count = fn rs, v -> Enum.count(rs, fn {_, r} -> r["disposition"] == v end) end

    body =
      for tk <- tickets do
        rs = Enum.filter(rows, &(elem(&1, 0) == tk))

        [tk | Enum.map(@verdicts, &Integer.to_string(count.(rs, &1)))] ++
          [Integer.to_string(length(rs))]
      end

    total =
      ["all" | Enum.map(@verdicts, &Integer.to_string(count.(rows, &1)))] ++
        [Integer.to_string(length(rows))]

    table(["#{label}: record" | @verdicts] ++ ["rows"], body ++ [total])
  end

  defp routing_table(rows) do
    body =
      rows
      |> Enum.filter(fn {_, r} -> Map.has_key?(r, "routed_to") end)
      |> Enum.group_by(fn {tk, r} ->
        [_, comment | _] = String.split(r["routed_to"]["owner_record"], [" comment ", ", item "])
        {tk, r["routed_to"]["to"], r["routed_to"]["owner"], comment}
      end)
      |> Enum.sort()
      |> Enum.map(fn {{tk, to, o, comment}, rs} ->
        [tk, to, o, "#{o} comment #{comment}", Integer.to_string(length(rs))]
      end)

    table(["record", "route", "owner", "routing comment", "rows"], body)
  end

  defp row_table(rows) do
    body =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {r, i} ->
        route = if rt = r["routed_to"], do: "#{rt["to"]}: #{rt["owner_record"]}", else: "-"
        [Integer.to_string(i), r["tag"], member(r), r["disposition"], route]
      end)

    table(["#", "tag", "member", "verdict", "route (owner_record)"], body)
  end

  defp member(%{"member" => m}) when is_binary(m), do: m
  defp member(%{"member" => %{"register_key" => k}}), do: k
  defp member(_), do: "-"

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

Bucket1Mirror.main(System.argv())

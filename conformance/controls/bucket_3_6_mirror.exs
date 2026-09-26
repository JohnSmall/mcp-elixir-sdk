# The Confluence bucket-3 (277774465) and bucket-6 (277741669) pages as
# MIRRORS of the record that closes those views (MES-144; plan 30054 C4,
# ratified 30055). Follows bucket1_mirror.exs.
#
#     mix run conformance/controls/bucket_3_6_mirror.exs blocks 3|6 "<synced from>"
#     mix run conformance/controls/bucket_3_6_mirror.exs text 3|6 "<synced from>"
#
# `blocks` prints the page body as the wrapper's typed content blocks (JSON),
# the `content` argument of confluence_update_page. `text` prints the same
# body flattened to one line per block and per table row, so a reader can
# regenerate it and diff it against the page's read-back text. "<synced from>"
# is printed verbatim in the banner, e.g. "branch MES-144 at 1a2b3c4" or, at
# the merge gate, "main at <merge sha>".
#
# The record is found by the directory walk (the one closed section binding
# the view), not named here. Every figure on the page is read from that record
# or from the view; none is written in this file.

defmodule Bucket36Mirror do
  @walk "docs/conformance/adjudications"
  @views %{
    "3" => "docs/conformance/buckets/bucket-3-2026-07-28.json",
    "6" => "docs/conformance/buckets/bucket-6-2026-07-28.json"
  }
  @pages %{
    "3" => "https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/277774465",
    "6" => "https://vidhya-trading.atlassian.net/wiki/spaces/ElixirMCPS/pages/277741669"
  }

  def main([mode, n, synced]) when mode in ~w(blocks text) and is_map_key(@views, n) do
    bs = blocks(n, synced)

    case mode do
      "blocks" -> bs |> Jason.encode!() |> IO.puts()
      "text" -> bs |> Enum.flat_map(&text/1) |> Enum.each(&IO.puts/1)
    end
  end

  def main(_) do
    IO.puts(:stderr, ~s|usage: mix run #{__ENV__.file} blocks\|text 3\|6 "<synced from>"|)
    System.halt(2)
  end

  # {path, record, section}: the ONE closed section binding the view.
  def closing(view) do
    found =
      for path <- Path.wildcard(Path.join(@walk, "*.json")) |> Enum.sort(),
          rec = path |> File.read!() |> Jason.decode!(),
          s <- rec["sections"],
          s["view"] == view and s["closure"] == "closed",
          do: {path, rec, s}

    case found do
      [one] -> one
      other -> raise "expected one closed section on #{view}, found #{length(other)}"
    end
  end

  def blocks(n, synced) do
    view_path = @views[n]
    view = view_path |> File.read!() |> Jason.decode!()
    {path, rec, s} = closing(view_path)
    m = rec["mechanism"]
    run = m["criterion_run"]
    j = m["joined_to_the_crosswalk"]
    e = rec["excluded_tests"]
    f = rec["fill_conditions"]
    q = rec["question"]["bucket_" <> n]

    [
      panel("note", [
        p([
          b("MIRROR. "),
          t("The normative record is "),
          c(path),
          t(". This page is generated from it by "),
          c("conformance/controls/bucket_3_6_mirror.exs"),
          t(". Where the page and the record differ, the record wins.")
        ]),
        p([b("Synced from: "), c(synced), t(".")]),
        p([
          t(
            "Bucket #{n} is CLOSED by #{rec["ticket"]} over an empty view: the section has no rows and " <>
              "echoes the view's count, emptiness_reason and universe, which guard G32 holds for equality. " <>
              "A re-projection that gains a row, or whose premise moves, is refused."
          )
        ])
      ]),
      h(2, "What belongs here"),
      p([b(view["title"] <> ". "), t(f["bucket_" <> n])]),
      h(2, "The question, and the answer"),
      p([b("Asked: "), c(view["predicate"])]),
      p([
        b("Answer: "),
        t(
          "#{q["result"]} rows (the view's count: #{s["emptiness"]["count"]}), over a universe of "
        ),
        t("#{view["universe"]["count"]} #{view["universe"]["name"]} (#{view["universe"]["of"]}).")
      ]),
      p([b("Premise, as the view states it: "), t(view["emptiness_reason"]["measured"])]),
      p([b("Commands: "), t(q["command"])]),
      p([
        t("Checked, and zero, not never asked: " <> view["emptiness_reason"]["result"])
      ]),
      h(2, "The mechanism of the emptiness"),
      p([t(m["statement"])]),
      table(["measure", "value"], [
        ["gate 5 (#{m["gate_5"]["command"]})", m["gate_5"]["result"]],
        ["excluded in that run", Integer.to_string(m["gate_5"]["excluded"])],
        ["node on PATH", m["gate_5"]["node_on_path"]],
        [
          "ET-CC run (#{run["command"]})",
          "selected #{run["selected"]} of the register's #{run["expected_from_register"]}; " <>
            "missing #{run["missing"]}, stray #{run["stray"]}; #{fmt(run["by_status"])}"
        ],
        ["red ET-CC members", Integer.to_string(length(run["red_members"]))],
        [
          "joined to the crosswalk",
          "#{j["cells"]} cells over #{j["distinct_members"]} members; " <>
            "members outside ET-CC: #{length(j["members_outside_etcc"])}"
        ],
        ["red cells (member did not pass)", Integer.to_string(length(j["red_cells"]))]
      ]),
      p([t(m["gate_5"]["why_node_matters"])]),
      p([b("The stored et verdict. "), t(m["stored_et_verdict"]["what_it_is"])]),
      table(
        ["edges file", "edges", "et_verdict"],
        for {file, v} <- Enum.sort(m["stored_et_verdict"]["edges_by_file"]) do
          [file, Integer.to_string(v["edges"]), fmt(v["by_et_verdict"])]
        end
      ),
      p([
        b("Live check: "),
        c("mix run conformance/controls/bucket_3_6_controls.exs all"),
        t(
          " re-runs the ET-CC members at any tip and refuses if a member, a cell or a stored verdict disagrees with this record."
        )
      ]),
      h(2, "Excluded tests"),
      p([
        b("Does an excluded test count as red here? "),
        t(if(e["counts_as_red_here"], do: "Yes. ", else: "No. ") <> e["why"])
      ]),
      p([
        t(
          "Register rows under test/conformance/: #{e["register_rows_under_test_conformance"]} of #{e["register_rows"]}. " <>
            "Search: "
        ),
        c(e["search"]["command"]),
        t(", #{length(e["search"]["hits"])} hits:")
      ]),
      table(["at", "what"], for(h <- e["search"]["hits"], do: [h["at"], h["what"]])),
      h(2, "What would fill it"),
      p([b("On main: "), t(f["on_main"])]),
      p([b("Superseded: "), t(f["superseded_stub_sentence"])]),
      table(
        ["ticket", "what", "how rows move"],
        for(
          x <- f["what_moves_rows_when_remediation_lands"],
          do: [x["ticket"], x["what"], x["moves"]]
        )
      )
    ] ++
      mes152(hd(f["what_moves_rows_when_remediation_lands"])) ++
      asymmetry(n, rec) ++
      [
        h(2, "Standing constraint"),
        p([
          b("Do not make a test red to populate this bucket."),
          t(" Epic ruling 3; no lib/ change.")
        ]),
        p([t("Page: "), t(@pages[n])])
      ]
  end

  # CR 30063 B1: the MES-152 landing by shape, and the routed counterparts
  # tallied by it. The per-item lists stay in the record; the page counts them.
  defp mes152(%{"ticket" => "MES-152"} = x) do
    c = x["classification"]

    tally = fn rows ->
      for r <- rows, do: [r["verdict"], r["check_status"], Integer.to_string(r["count"])]
    end

    members = fn rows -> Enum.map_join(rows, "; ", &"#{&1["member"]} (#{&1["token"]})") end

    [
      h(3, "MES-152: landing by shape"),
      table(
        ["OC check", "edge shape", "lands"],
        for(r <- x["landing_by_shape"], do: [r["oc"], r["shape"], r["lands"]])
      ),
      p([b("Population: "), t(c["population"])]),
      p([b("Rule: "), t(c["rule"])]),
      p([
        t(
          "Primary counterparts: #{length(c["primary"])} (by record: #{fmt(c["primary_by_record"])})."
        )
      ]),
      table(["verdict", "check status", "count"], tally.(c["primary_by_verdict_and_status"])),
      p([
        t(
          "Contradicting a red check, by check: #{fmt(c["primary_contradicting_a_red_check_by_check"])}. "
        ),
        b("Agreeing with a red check: "),
        t(members.(c["primary_agreeing_with_a_red_check"]))
      ]),
      p([t("Secondary counterparts (oc_counterpart.also): #{length(c["also"])}.")]),
      table(["verdict", "check status", "count"], tally.(c["also_by_verdict_and_status"])),
      p([
        b("Secondary, agreeing with a red check: "),
        t(members.(c["also_agreeing_with_a_red_check"]))
      ]),
      p([t(c["note"])])
    ]
  end

  defp asymmetry("3", _), do: []

  defp asymmetry("6", rec) do
    a = rec["asymmetry_bucket_6"]
    d = a["d1_contradicting_units"]

    [
      h(2, "The asymmetry"),
      p([b("Predicate: "), t(a["predicate"] <> ". "), t(a["inherited_figure"])]),
      p([t("By leg: #{fmt(a["by_leg"])}. By scenario: #{fmt(a["by_scenario"])}.")]),
      table(
        ["OC check (FAILURE)", "ET edges (bucket, et)"],
        for tag <- a["failure_checks"] do
          case Enum.find(a["with_an_et_edge"], &(&1["tag"] == tag)) do
            nil ->
              [tag, "none: bucket 2a"]

            w ->
              [
                tag,
                Enum.map_join(w["edges"], "; ", &"#{&1["member"]} (#{&1["bucket"]}, #{&1["et"]})")
              ]
          end
        end
      ),
      p([
        b("Corresponding ET reds: #{length(a["et_red_counterparts"])}. "),
        t(d["what"])
      ]),
      table(
        ["record", "ticket", "slice members", "red under M9", "M9h", "M9f"],
        for r <- d["per_record"] do
          [
            r["record"],
            r["ticket"],
            Integer.to_string(r["slice_members"]),
            Integer.to_string(length(r["M9_reddened"])),
            r |> Map.get("M9h_slice_members_red", "-") |> to_string(),
            r |> Map.get("M9f_slice_members_red", "-") |> to_string()
          ]
        end
      ),
      p([t("M9 union: #{length(d["M9_union"])} bucket-1 members. " <> d["note"])]),
      p([
        t("Dispositions: #{fmt(d["disposition_split"]["by_disposition"])}; not redundant: "),
        t(
          Enum.map_join(
            d["disposition_split"]["not_redundant"],
            "; ",
            &"#{&1["tag"]} (#{&1["disposition"]})"
          )
        ),
        t(
          ". Rows saying \"only through the construction\" in terms: #{length(d["construction_wording"]["tags"])}. "
        ),
        t(d["construction_wording"]["what"])
      ]),
      p([b("The census negative. "), t(a["census_negative"]["what"])]),
      table(
        ["leg", "census scored FAILURE", "at"],
        for {leg, x} <- Enum.sort(a["census_negative"]["census_scored_failure"]) do
          [leg, Integer.to_string(x["value"]), "#{x["file"]} #{x["at"]}"]
        end
      ),
      p([
        t(
          "Client failures by classification: #{fmt(a["census_negative"]["client_failures_by_classification"])}, " <>
            "over #{length(a["census_negative"]["client_failing_scenarios_out_of_scope_adr_003"])} scenarios. "
        ),
        t(a["census_negative"]["reading"])
      ]),
      p([b("What it implies. "), t(a["what_it_implies"])])
    ]
  end

  defp fmt(map), do: map |> Enum.sort() |> Enum.map_join(", ", fn {k, v} -> "#{k} #{v}" end)

  # --- typed blocks -----------------------------------------------------------

  defp t(s), do: %{"t" => "text", "text" => s}
  defp b(s), do: %{"t" => "text", "text" => s, "marks" => ["strong"]}
  defp c(s), do: %{"t" => "text", "text" => s, "marks" => ["code"]}
  defp p(inl), do: %{"t" => "p", "c" => inl}
  defp h(l, s), do: %{"t" => "h", "level" => l, "c" => [t(s)]}
  defp panel(v, bs), do: %{"t" => "panel", "variant" => v, "c" => bs}

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

  def text(%{"t" => "panel", "c" => bs}), do: Enum.flat_map(bs, &text/1)
  def text(%{"c" => inl}), do: [Enum.map_join(inl, "", & &1["text"])]

  defp cells(%{"c" => bs}), do: Enum.map_join(bs, " ", &(&1 |> text() |> Enum.join(" ")))
end

Bucket36Mirror.main(System.argv())

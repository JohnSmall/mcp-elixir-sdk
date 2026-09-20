defmodule MCP.Conformance.BucketProjectionTest do
  @moduledoc """
  Units for C2's projection logic (MES-98).

  The parts that need a **mutated tree** — the no-op control, the five
  movements, the guard mutations — live in
  `conformance/controls/bucket_projection_controls.exs`, because a file under
  `test/` that rewrites authored artefacts and re-runs whole builds would move
  the unit population MES-88's boundary sweep measures. What is here is what
  gate 5 can hold: the functions that decide which view a row lands in, every
  guard's own refusal, and the committed views' agreement with the committed
  crosswalk.

  ## The fixture is synthetic, and that is the point

  A unit that reads only the committed crosswalk can exercise the buckets that
  are *populated on this slice* — 1, 4a, 4b, 5b and the escalated view — and
  nothing else. Buckets 2a, 2b, 3, 5a and 6 are empty there, so a green suite
  over the real artefact would say nothing about them. The fixture below puts a
  row in **every** view so each predicate is exercised, and the committed
  artefact is then checked separately.
  """
  use ExUnit.Case, async: true

  alias MCP.Conformance.BucketProjection

  @rev "2026-07-28"

  defp cell(opts) do
    leg = Keyword.get(opts, :leg, "client")
    id = Keyword.fetch!(opts, :id)

    %{
      "member" => %{
        "module" => "MCP.#{id}Test",
        "test" => "test #{id}",
        "register_key" => "MCP.#{id}Test/test #{id}"
      },
      "claim" => "claim #{id}",
      "tag" => "oc:#{leg}/scenario-#{id}/check-#{id}/Check#{id}",
      "oc_key" => [leg, "scenario-#{id}", "check-#{id}", "Check#{id}", "d", ""],
      "verdicts" => %{"oc" => "green", "et" => Keyword.get(opts, :et, "green")},
      "shape" => "full",
      "bucket" => Keyword.get(opts, :bucket),
      "bucket_attributes" => [],
      "escalation" => Keyword.get(opts, :escalation),
      "evidence" => "e",
      "note" => nil
    }
  end

  defp unmatched(id) do
    %{
      "member" => %{
        "module" => "MCP.#{id}Test",
        "test" => "test #{id}",
        "register_key" => "MCP.#{id}Test/test #{id}"
      },
      "tag" => "oc:none/no-oc-scenario/#{id}"
    }
  end

  # One row in every view: 3, 4a, 4b, 5a, 5b, 6, escalated, bucket 1, 2a, 2b.
  defp fixture(overrides \\ %{}) do
    cells = [
      cell(id: "A", bucket: "3", et: "red"),
      cell(id: "B", bucket: "4a", leg: "server"),
      cell(id: "C", bucket: "4b", leg: "server"),
      cell(id: "D", bucket: "5", leg: "server"),
      cell(id: "E", bucket: "5"),
      cell(id: "F", bucket: "6", et: "red"),
      cell(id: "G", bucket: nil, escalation: "no_axis_contact — every axis silent")
    ]

    members = Enum.map(cells, &get_in(&1, ["member", "register_key"])) ++ ["MCP.HTest/test H"]

    checks =
      Enum.map(cells, & &1["tag"]) ++
        ["oc:server/scenario-I/check-I/CheckI", "oc:client/scenario-J/check-J/CheckJ"]

    Map.merge(
      %{
        "cells" => cells,
        "population" => %{"members" => Enum.sort(members), "checks" => Enum.sort(checks)},
        "declared_unmatched" => [unmatched("H")]
      },
      overrides
    )
  end

  defp bucket_zero do
    %{
      "checks" => [
        %{"key" => ["client", "s", "c", "Zero1", "d", ""], "matchable" => false},
        %{"key" => ["client", "s", "c", "Zero2", "d", ""], "matchable" => false},
        %{"key" => ["client", "s", "c", "In", "d", ""], "matchable" => true}
      ]
    }
  end

  defp project(doc \\ nil) do
    {:ok, files} = BucketProjection.project(doc || fixture(), bucket_zero(), %{"t" => "test"})
    files
  end

  defp view(files, id), do: Map.fetch!(files, "bucket-#{id}-#{@rev}.json")
  defp roll_up(files), do: Map.fetch!(files, "roll-up-#{@rev}.json")

  defp ids(view),
    do: Enum.map(view["rows"], &(&1["tag"] || get_in(&1, ["member", "register_key"])))

  describe "the ten bucket ids and their specs" do
    test "there are ten, in page order" do
      assert BucketProjection.bucket_ids() == ~w(0 1 2a 2b 3 4a 4b 5a 5b 6)
    end

    test "every bucket carries a predicate, and only bucket 0 is a citation" do
      for id <- BucketProjection.bucket_ids() do
        spec = BucketProjection.spec(id)
        assert is_binary(spec.predicate) and spec.predicate != ""
        assert spec.derivation == if(id == "0", do: "citation", else: "projection")
      end
    end

    test "spec/1 refuses a bucket that does not exist" do
      assert_raise ArgumentError, ~r/no such bucket: 7/, fn -> BucketProjection.spec("7") end
    end
  end

  describe "each view is a filter on a stored field" do
    setup do: %{files: project()}

    test "the stored bucket decides 3, 4a, 4b and 6", %{files: files} do
      assert ids(view(files, "3")) == ["oc:client/scenario-A/check-A/CheckA"]
      assert ids(view(files, "4a")) == ["oc:server/scenario-B/check-B/CheckB"]
      assert ids(view(files, "4b")) == ["oc:server/scenario-C/check-C/CheckC"]
      assert ids(view(files, "6")) == ["oc:client/scenario-F/check-F/CheckF"]
    end

    test "bucket 5 splits on the stored oc_key leg, not on anything recomputed", %{files: files} do
      assert ids(view(files, "5a")) == ["oc:server/scenario-D/check-D/CheckD"]
      assert ids(view(files, "5b")) == ["oc:client/scenario-E/check-E/CheckE"]
    end

    test "bucket 2 splits on the token's own leg segment", %{files: files} do
      assert ids(view(files, "2a")) == ["oc:server/scenario-I/check-I/CheckI"]
      assert ids(view(files, "2b")) == ["oc:client/scenario-J/check-J/CheckJ"]
    end

    test "bucket 1 is the declared members with no edge", %{files: files} do
      rows = view(files, "1")["rows"]
      assert Enum.map(rows, &get_in(&1, ["member", "register_key"])) == ["MCP.HTest/test H"]
    end

    test "bucket 0 cites A5's unmatchable checks and says it is a citation", %{files: files} do
      v = view(files, "0")

      assert v["derivation"] == "citation"
      assert Enum.map(v["rows"], &Enum.at(&1["key"], 3)) == ["Zero1", "Zero2"]
      assert v["what_this_is"] =~ "CITATION, not a projection"
    end

    test "the escalated rows are an eleventh view, outside the ten", %{files: files} do
      escalated = Map.fetch!(files, "escalated-#{@rev}.json")

      assert escalated["bucket"] == nil
      assert ids(escalated) == ["oc:client/scenario-G/check-G/CheckG"]
      assert escalated["what_this_is"] =~ "an escalation is NOT a bucket"

      refute Enum.any?(BucketProjection.bucket_ids(), fn id ->
               ids(view(files, id)) == ids(escalated)
             end)
    end

    test "every view carries the population banner and its predicate verbatim", %{files: files} do
      for {_name, doc} <- files do
        assert doc["population_banner"] == BucketProjection.banner()
      end

      for id <- BucketProjection.bucket_ids() do
        assert view(files, id)["predicate"] == BucketProjection.spec(id).predicate
      end
    end
  end

  describe "a stored bucket that disagrees with f(verdicts, shape) is DEFERRED to, not corrected" do
    test "a 4a row whose shape says 4b stays in 4a" do
      doc =
        fixture(%{
          "cells" =>
            Enum.map(fixture()["cells"], fn c ->
              if c["bucket"] == "4a", do: Map.put(c, "shape", "partial"), else: c
            end)
        })

      files = project(doc)

      assert ids(view(files, "4a")) == ["oc:server/scenario-B/check-B/CheckB"]
      assert ids(view(files, "4b")) == ["oc:server/scenario-C/check-C/CheckC"]

      assert roll_up(files)["what_a_green_run_here_establishes"] =~
               "NOT that the crosswalk is internally consistent"
    end
  end

  describe "emptiness is data-driven and carries its reason" do
    test "a populated view carries no emptiness_reason" do
      assert view(project(), "5b")["emptiness_reason"] == nil
    end

    test "an empty view says which of the three reasons applies, and measures it" do
      doc = fixture(%{"cells" => Enum.reject(fixture()["cells"], &(&1["bucket"] == "3"))})
      doc = put_in(doc, ["declared_unmatched"], [unmatched("H"), unmatched("A")])

      reason = view(project(doc), "3")["emptiness_reason"]

      assert reason["code"] == "by_construction"
      assert reason["result"] =~ "CHECKED, AND ZERO"
      assert reason["measured"] =~ "cells whose stored et verdict is `red`:"
    end

    test "5a's emptiness is by_slice and refuses to read as a structural fact" do
      doc =
        fixture(%{
          "cells" =>
            Enum.reject(
              fixture()["cells"],
              &(&1["oc_key"] == ["server", "scenario-D", "check-D", "CheckD", "d", ""])
            )
        })

      doc = put_in(doc, ["declared_unmatched"], [unmatched("H"), unmatched("D")])

      reason = view(project(doc), "5a")["emptiness_reason"]

      assert reason["code"] == "by_slice"
      assert reason["what_would_fill_it"] =~ "NOT A STRUCTURAL FACT"
      assert reason["what_would_fill_it"] =~ "MES-105"
    end
  end

  describe "the roll-up's three universes" do
    setup do: %{roll_up: roll_up(project())}

    test "there are three derived equations plus the cited bucket-0 one", %{roll_up: r} do
      assert Enum.map(r["equations"], & &1["universe"]) ==
               ~w(edges declared_members declared_checks oc_checks_175)

      assert Enum.all?(r["equations"], & &1["holds"])
    end

    test "the edge equation carries the escalated rows as their own term", %{roll_up: r} do
      edges = Enum.find(r["equations"], &(&1["universe"] == "edges"))

      assert Enum.map(edges["terms"], & &1["term"]) == ~w(3 4a 4b 5a 5b 6 escalated)
      assert edges["total"] == 7
    end

    test "the partition is reported by set comparison in both directions", %{roll_up: r} do
      for universe <- ~w(edges declared_members declared_checks) do
        assert r["partition"][universe]["equal"]
        assert r["partition"][universe]["missing"] == []
        assert r["partition"][universe]["extra"] == []
      end
    end

    test "cross-universe pairwise disjointness is reported as proving nothing", %{roll_up: r} do
      p = r["partition"]["pairwise_disjoint"]

      assert p["pairs_compared"] == 55
      assert p["within_universe_pairs"] + p["cross_universe_pairs"] == 55
      assert p["overlapping"] == []
      assert p["what_the_cross_universe_pairs_establish"] =~ "NOTHING"
    end

    test "E2 is named as the owner of the proof, and its result is not claimed", %{roll_up: r} do
      assert r["partition"]["who_proves_it"] =~ "E2"
      assert r["what_this_is"] =~ "It does not prove the partition"
    end
  end

  describe "the guards, each refusing and naming itself" do
    test "vacuum — a crosswalk with no cells" do
      doc =
        fixture(%{
          "cells" => [],
          "declared_unmatched" => Enum.map(~w(A B C D E F G H), &unmatched/1)
        })

      assert {:error, {:vacuum, message}} = BucketProjection.project(doc, bucket_zero(), %{})
      assert message =~ "VACUUM"
    end

    test "leg — a cell whose oc_key leg is not server or client" do
      doc =
        fixture(%{
          "cells" =>
            Enum.map(fixture()["cells"], &put_in(&1, ["oc_key", Access.at(0)], "gateway"))
        })

      assert {:error, {:leg, message}} = BucketProjection.project(doc, bucket_zero(), %{})
      assert message =~ "LEG GUARD"
    end

    test "leg — a declared check whose token leg is not server or client" do
      doc = update_in(fixture(), ["population", "checks"], &["oc:gateway/s/c/C" | &1])

      assert {:error, {:leg, message}} = BucketProjection.project(doc, bucket_zero(), %{})
      assert message =~ "declared checks carry a leg outside"
    end

    test "edge_partition — a cell whose stored bucket names no view" do
      doc = put_in(fixture(), ["cells", Access.at(0), "bucket"], "7")

      assert {:error, {:edge_partition, message}} =
               BucketProjection.project(doc, bucket_zero(), %{})

      assert message =~ "cells that reach no view (1)"
    end

    test "member_partition — a cell naming a member outside the declared population" do
      doc =
        put_in(fixture(), ["cells", Access.at(0), "member", "register_key"], "MCP.XTest/test X")

      assert {:error, {:member_partition, message}} =
               BucketProjection.project(doc, bucket_zero(), %{})

      assert message =~ "outside the declared population (1)"
    end

    test "member_partition — a bucket-1 member with no declared_unmatched record" do
      doc = Map.put(fixture(), "declared_unmatched", [])

      assert {:error, {:member_partition, message}} =
               BucketProjection.project(doc, bucket_zero(), %{})

      assert message =~ "no declared_unmatched record (1)"
    end

    test "check_partition — a cell tagging a check outside the declared population" do
      doc = put_in(fixture(), ["cells", Access.at(0), "tag"], "oc:client/s/c/Nope")

      assert {:error, {:check_partition, message}} =
               BucketProjection.project(doc, bucket_zero(), %{})

      assert message =~ "outside the declared population (1)"
    end

    test "the guard list is what the controls enumerate" do
      assert BucketProjection.guards() ==
               [:vacuum, :leg, :edge_partition, :member_partition, :check_partition]
    end

    test "an unmutated fixture passes every guard — the negative control" do
      assert {:ok, _} = BucketProjection.project(fixture(), bucket_zero(), %{})
    end
  end

  describe "the committed views against the committed crosswalk" do
    setup do
      crosswalk = read!("docs/conformance/crosswalk-2026-07-28.json")
      zero = read!("docs/conformance/bucket-0-2026-07-28.json")
      {:ok, files} = BucketProjection.project(crosswalk, zero, %{})

      %{files: files, crosswalk: crosswalk}
    end

    test "every committed cell appears in exactly one view", %{files: files, crosswalk: c} do
      placed =
        ~w(3 4a 4b 5a 5b 6)
        |> Enum.flat_map(&view(files, &1)["rows"])
        |> Kernel.++(Map.fetch!(files, "escalated-#{@rev}.json")["rows"])
        |> Enum.map(&{&1["member"]["register_key"], &1["claim"], &1["tag"]})

      cells = Enum.map(c["cells"], &{&1["member"]["register_key"], &1["claim"], &1["tag"]})

      assert Enum.sort(placed) == Enum.sort(cells)
      assert length(placed) == length(Enum.uniq(placed))
    end

    test "the escalated view holds exactly the crosswalk's escalations", %{
      files: files,
      crosswalk: c
    } do
      assert Map.fetch!(files, "escalated-#{@rev}.json")["count"] == c["escalations"]["count"]
    end

    test "each view's rows are the crosswalk's records verbatim", %{files: files, crosswalk: c} do
      by_key = Map.new(c["cells"], &{{&1["member"]["register_key"], &1["claim"], &1["tag"]}, &1})

      for id <- ~w(3 4a 4b 5a 5b 6), row <- view(files, id)["rows"] do
        assert row ==
                 Map.fetch!(by_key, {row["member"]["register_key"], row["claim"], row["tag"]})
      end
    end

    test "the five empty views each carry a reason, and three distinct codes are used", %{
      files: files
    } do
      empty =
        BucketProjection.bucket_ids()
        |> Enum.filter(&(view(files, &1)["count"] == 0))
        |> Map.new(&{&1, view(files, &1)["emptiness_reason"]["code"]})

      assert empty == %{
               "2a" => "by_adjudication",
               "2b" => "by_adjudication",
               "3" => "by_construction",
               "5a" => "by_slice",
               "6" => "by_construction"
             }
    end

    test "the residual naming E2 derives its witness rather than restating it", %{files: files} do
      text =
        roll_up(files)["residuals"]
        |> Enum.find(&(&1["id"] == "C2-R2"))
        |> Map.fetch!("text")

      assert text =~ "StreamableHTTPStatelessTest"
      assert text =~ "E2"
    end
  end

  defp read!(path), do: path |> File.read!() |> Jason.decode!()
end

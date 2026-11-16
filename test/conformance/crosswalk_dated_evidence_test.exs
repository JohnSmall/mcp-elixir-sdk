defmodule MCP.Conformance.CrosswalkDatedEvidenceTest do
  @moduledoc """
  Units for G30's DATED limb (MES-234): `Crosswalk.dated_defects/3`, the
  dated ET windows of `Crosswalk.citation_windows/2`, and the committed pinned
  set against the committed edges files.

  The decision logic is driven through a STUB resolver, so no test here needs a
  particular commit graph; one test runs the real git resolver over the
  committed inputs, which is the state the generator itself checks. The
  mutated-tree controls (a planted quote, a wrong sha, an orphan commit, the
  tip, a dropped prefix) live in `conformance/controls/crosswalk_dated_controls.exs`.
  """
  use ExUnit.Case, async: true

  alias MCP.Conformance.{CitationVerbatim, Crosswalk}

  @sha String.duplicate("a", 40)
  @short String.slice(@sha, 0, 7)

  # A resolver over one fake commit holding one file, `test/f.exs`.
  defp resolver(overrides \\ %{}) do
    Map.merge(
      %{
        resolve: fn
          @sha -> {:ok, @sha}
          _ -> :error
        end,
        ancestor?: fn sha -> sha == @sha end,
        file_at: fn
          @sha, "f.exs" -> {:ok, "test/f.exs"}
          _, _ -> :error
        end,
        show: fn @sha, "test/f.exs" -> {:ok, "line one\nx = 1\nline three\n"} end
      },
      overrides
    )
  end

  defp dated(key, extra \\ %{}) do
    Map.merge(
      %{
        "__file" => "e.json",
        "member" => %{"register_key" => key},
        "claim" => "c",
        "tag" => "t",
        "evidence" => "At #{@short}, f.exs:2 — `x = 1`.",
        "evidence_at" => %{"commit" => @sha, "owner" => "MES-193"}
      },
      extra
    )
  end

  defp pin(key, extra \\ %{}) do
    Map.merge(
      %{
        "file" => "e.json",
        "register_key" => key,
        "claim" => "c",
        "tag" => "t",
        "commit" => @sha,
        "owner" => "MES-193"
      },
      extra
    )
  end

  defp pins(keys, ceiling \\ 8), do: %{"ceiling" => ceiling, "records" => Enum.map(keys, &pin/1)}

  defp kinds(defects), do: defects |> Enum.map(& &1["kind"]) |> Enum.sort()

  describe "dated_defects/3 — every way out of the pinned set is a refusal by name" do
    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a pinned, owned, named record under the ceiling at an ancestor commit passes" do
      assert Crosswalk.dated_defects([dated("k1")], pins(["k1"]), resolver()) == []
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "an undated record is outside the limb entirely" do
      undated = Map.delete(dated("k1"), "evidence_at")
      assert Crosswalk.dated_defects([undated], pins([]), resolver()) == []
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a record past the ceiling is refused as over the ceiling AND as not pinned" do
      keys = for i <- 1..8, do: "k#{i}"
      records = Enum.map(keys, &dated/1) ++ [dated("k9")]

      assert kinds(Crosswalk.dated_defects(records, pins(keys), resolver())) ==
               ["dated_not_pinned", "dated_over_ceiling"]
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a record with no owner, or an owner that is not a ticket key, is refused" do
      for at <- [%{"commit" => @sha}, %{"commit" => @sha, "owner" => "someone"}] do
        record = dated("k1", %{"evidence_at" => at})
        pinned = pins(["k1"]) |> put_in(["records", Access.at(0), "owner"], at["owner"])

        assert "dated_without_owner" in kinds(
                 Crosswalk.dated_defects([record], pinned, resolver())
               )
      end
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a record pinned at another owner is not pinned" do
      pinned = %{"ceiling" => 8, "records" => [pin("k1", %{"owner" => "MES-195"})]}

      assert kinds(Crosswalk.dated_defects([dated("k1")], pinned, resolver())) ==
               ["dated_not_pinned"]
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a pin no dated record uses is refused, so the set can only shrink with its records" do
      assert kinds(Crosswalk.dated_defects([dated("k1")], pins(["k1", "k2"]), resolver())) ==
               ["dated_pin_unused"]
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a ceiling above the compiled one, or not an integer, is refused as raised" do
      assert Crosswalk.dated_ceiling() == 8

      for c <- [9, -1, "8", nil] do
        assert kinds(Crosswalk.dated_defects([dated("k1")], pins(["k1"], c), resolver())) ==
                 ["dated_ceiling_raised"]
      end
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "more pins than the data file's own ceiling is over the ceiling" do
      assert "dated_over_ceiling" in kinds(
               Crosswalk.dated_defects([dated("k1")], pins(["k1", "k2"], 1), resolver())
             )
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a short, a non-hex, or an unknown full sha is unresolved" do
      for c <- [@short, String.duplicate("z", 40), String.duplicate("b", 40)] do
        record = dated("k1", %{"evidence_at" => %{"commit" => c, "owner" => "MES-193"}})
        pinned = %{"ceiling" => 8, "records" => [pin("k1", %{"commit" => c})]}

        assert kinds(Crosswalk.dated_defects([record], pinned, resolver())) ==
                 ["dated_commit_unresolved"]
      end
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a commit that is not an ancestor of HEAD is refused" do
      r = resolver(%{ancestor?: fn _ -> false end})

      assert kinds(Crosswalk.dated_defects([dated("k1")], pins(["k1"]), r)) ==
               ["dated_commit_not_ancestor"]
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a cited file absent at the commit is refused" do
      record = dated("k1", %{"evidence" => "At #{@short}, g.exs:2 — `x = 1`."})

      assert kinds(Crosswalk.dated_defects([record], pins(["k1"]), resolver())) ==
               ["dated_file_absent"]
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a leaf that does not name the commit is refused" do
      record = dated("k1", %{"evidence" => "f.exs:2 — `x = 1`."})

      assert kinds(Crosswalk.dated_defects([record], pins(["k1"]), resolver())) ==
               ["dated_leaf_unnamed"]
    end
  end

  describe "citation_windows/2 — a dated record is read at its commit and never at the tip" do
    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a quote present at the commit is placed in an et@<short> window" do
      ctx = %{axes: [], resolver: resolver()}
      result = CitationVerbatim.audit([dated("k1")], &Crosswalk.citation_windows(&1, ctx))

      assert result["defects"] == []
      assert result["matched_in"] == %{"et@#{@short}:f.exs:2-2" => 1}
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a planted non-verbatim quote at a dated address is not placed" do
      ctx = %{axes: [], resolver: resolver()}
      record = dated("k1", %{"evidence" => "At #{@short}, f.exs:2 — `x = 2`."})
      result = CitationVerbatim.audit([record], &Crosswalk.citation_windows(&1, ctx))

      assert Enum.map(result["defects"], & &1["kind"]) == ["not_verbatim_at_any_cited_address"]
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "a malformed evidence_at gives no window at all, so nothing falls back to the tip" do
      ctx = %{axes: [], resolver: resolver()}
      record = dated("k1", %{"evidence_at" => "#{@sha}"})

      assert Crosswalk.citation_windows(record, ctx).narrow == []
    end
  end

  describe "the committed pinned set against the committed edges files" do
    @tag oc: :none
    @tag oc_reason: "instrument unit (crosswalk G30 dated limb, MES-234); no OC counterpart"
    test "every dated record is pinned and passes with the real git resolver" do
      pins = Crosswalk.dated_pins_path() |> File.read!() |> Jason.decode!()

      records =
        for path <- Path.wildcard("conformance/data/crosswalk-edges*.json"),
            {_key, value} <- path |> File.read!() |> Jason.decode!(),
            is_list(value),
            value != [],
            Enum.all?(value, &is_map/1),
            record <- value,
            do: Map.put(record, "__file", Path.basename(path))

      dated = Enum.filter(records, &Map.has_key?(&1, "evidence_at"))

      assert pins["ceiling"] == Crosswalk.dated_ceiling()
      assert length(pins["records"]) == length(dated)
      assert Enum.all?(dated, &(&1["evidence_at"]["owner"] == "MES-193"))
      assert Crosswalk.dated_defects(records, pins) == []
    end
  end
end

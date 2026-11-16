defmodule MCP.Conformance.PinnedRegisterTest do
  @moduledoc """
  `MCP.Conformance.PinnedRegister`: the one pin the dated consumers of the ET-CC
  register read (MES-231, PM `35457`). It reads a git object, it checks the
  object's md5, and it refuses rather than fall through to the live file.
  """
  use ExUnit.Case, async: true

  alias MCP.Conformance.PinnedRegister

  @refusal ~r/REFUSING to read the pinned ET-CC register b5b0fbc:docs\/conformance\/etcc-register\.json/

  describe "the pin" do
    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "is one commit, one path and one md5, and the object hashes to it" do
      assert PinnedRegister.commit() == "b5b0fbc7321b6ddba79b1a52c2d656947227fb00"
      assert PinnedRegister.path() == "docs/conformance/etcc-register.json"
      assert PinnedRegister.md5() == "0bf1ff3b7e1ba35375f7efd9b4e369e9"

      bytes = PinnedRegister.read!()
      assert :crypto.hash(:md5, bytes) |> Base.encode16(case: :lower) == PinnedRegister.md5()
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "is the register its dated consumers were measured over: 579 rows, 281 ET-CC" do
      r = PinnedRegister.decode!()
      assert length(r["rows"]) == 579
      assert Enum.count(r["rows"], &(&1["label"] == "ET-CC")) == 281
      assert r["totals"]["by_label"]["ET-CC"] == 281
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "read_for!/1 serves the pin for the register's path and a planted copy as planted" do
      assert PinnedRegister.read_for!(PinnedRegister.path()) == PinnedRegister.decode!()

      planted = %{"rows" => [%{"key" => "M/test planted", "label" => "ET-CC"}]}

      path =
        Path.join(System.tmp_dir!(), "pinned-register-planted-#{System.unique_integer()}.json")

      File.write!(path, Jason.encode!(planted))

      try do
        assert PinnedRegister.read_for!(path) == planted
      after
        File.rm(path)
      end
    end
  end

  describe "fail-closed: a refusal naming the pin, never the live file" do
    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "an object not in the repository (a shallow clone) is refused" do
      e =
        assert_raise RuntimeError, fn ->
          PinnedRegister.read!(commit: String.duplicate("0", 40))
        end

      assert e.message =~ @refusal
      assert e.message =~ "exited"
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "no git to run is refused" do
      e =
        assert_raise RuntimeError, fn ->
          PinnedRegister.read!(git: "/nonexistent/mes231/git")
        end

      assert e.message =~ @refusal
      assert e.message =~ "git could not be run"
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "bytes that do not hash to the pin's md5 are refused" do
      e =
        assert_raise RuntimeError, fn ->
          PinnedRegister.read!(md5: String.duplicate("f", 32))
        end

      assert e.message =~ @refusal
      assert e.message =~ "not ffffffffffffffffffffffffffffffff"
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "decode!/1 with an override refuses too, rather than serve the cached pin" do
      _warm = PinnedRegister.decode!()

      assert_raise RuntimeError, @refusal, fn ->
        PinnedRegister.decode!(commit: String.duplicate("0", 40))
      end
    end
  end

  # Each pinned consumer goes red here if it reads the live register: the live
  # file is the rebuilt one (MES-231 H2), so the two member sets differ, and the
  # first test asserts that they do, or the other two would discriminate nothing.
  describe "the pinned consumers read the pin, not the live register" do
    setup do
      etcc = fn r ->
        for row <- r["rows"], row["label"] == "ET-CC", into: MapSet.new(), do: row["key"]
      end

      live = "docs/conformance/etcc-register.json" |> File.read!() |> Jason.decode!()
      %{etcc: etcc, live: etcc.(live), pinned: etcc.(PinnedRegister.decode!())}
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "the live register's members are not the pinned ones, so the controls below can fail",
         c do
      assert MapSet.size(c.pinned) == 281
      assert MapSet.size(c.live) == 479
      assert MapSet.subset?(c.pinned, c.live)
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "B2b: ETCCAttribution.build/1 joins the pinned members (MES-243 removes the pin)", c do
      built = MapSet.new(MCP.Conformance.ETCCAttribution.build()["rows"], & &1["key"])
      assert MapSet.equal?(built, c.pinned)
      refute MapSet.equal?(built, c.live)
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "crosswalk: --register at the register's path reads the pin (MES-244 removes it)", c do
      read = Mix.Tasks.Conformance.Crosswalk.register!("docs/conformance/etcc-register.json")
      assert read == PinnedRegister.decode!()
      refute MapSet.equal?(c.etcc.(read), c.live)
    end

    @tag oc: :none
    @tag oc_reason: "instrument unit (pinned ET-CC register reader, MES-231); no OC counterpart"
    test "D3+D6: bucket_3_6_controls.exs holds its run to the pinned members (MES-244)", c do
      # The control is a script that runs itself, so only its module is compiled
      # here, from its own source, and the call below is the control's own code.
      {:__block__, _, forms} =
        "conformance/controls/bucket_3_6_controls.exs" |> File.read!() |> Code.string_to_quoted!()

      [module] = Enum.filter(forms, &match?({:defmodule, _, _}, &1))
      {{:module, control, _, _}, _} = Code.eval_quoted(module)

      members = control |> apply(:etcc_members, []) |> MapSet.new()
      assert MapSet.equal?(members, c.pinned)
      refute MapSet.equal?(members, c.live)

      # And the dated record the control holds the run to is over that same set.
      record =
        "docs/conformance/adjudications/adjudication-D3-D6-2026-07-28.json"
        |> File.read!()
        |> Jason.decode!()

      recorded = MapSet.new(record["mechanism"]["criterion_run"]["statuses"], & &1["member"])
      assert MapSet.equal?(recorded, members)
    end
  end
end

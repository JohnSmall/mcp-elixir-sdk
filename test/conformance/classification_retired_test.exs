defmodule MCP.Conformance.ClassificationRetiredTest do
  @moduledoc """
  MES-232 (PM ruling 34937). A dated committed census may carry a block for an
  id that has since left the classification table. That block is still
  CHECKED, against its frozen entry in `Classification.retired/0`, byte for
  byte (`MCP.Test.ClassificationBlocks.judge/2`, which `ClassificationTest`
  applies to the committed censuses). These controls show that the retired set
  narrows nothing else, and that it is not a live classification.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.Classification
  alias MCP.Test.ClassificationBlocks

  @tag oc: :none
  @tag oc_reason:
         "a control on the committed-census guard's judgement, not on SDK behaviour; no OC check exercises it"
  test "control: a block for an unknown id that is NOT retired is still unknown" do
    block = %{"class" => "pending", "why" => "anything", "owner" => "anyone"}
    blocks = [{"synthetic.json", "no-such-scenario-mes232", block}]

    assert ClassificationBlocks.judge(blocks, Classification.retired()) ==
             {[{"synthetic.json", "no-such-scenario-mes232"}], []}
  end

  @tag oc: :none
  @tag oc_reason:
         "a control on the committed-census guard's judgement, not on SDK behaviour; no OC check exercises it"
  test "control: a retired id's block with its why altered by one byte is drift" do
    retired = Classification.retired()

    for id <- Map.keys(retired) do
      exact = ClassificationBlocks.expected(id, retired)
      altered = Map.update!(exact, "why", &(&1 <> "."))

      assert ClassificationBlocks.judge([{"synthetic.json", id, exact}], retired) == {[], []}

      assert ClassificationBlocks.judge([{"synthetic.json", id, altered}], retired) ==
               {[], [{"synthetic.json", id}]}
    end

    assert map_size(retired) > 0
  end

  @tag oc: :none
  @tag oc_reason:
         "a unit of the census classification table itself, not of SDK behaviour; no OC check exercises it"
  test "a retired entry is not a live classification" do
    retired = Classification.retired()
    assert map_size(retired) > 0

    for {id, entry} <- retired do
      assert Classification.fetch(id) == nil
      refute Map.has_key?(Classification.table(), id)
      assert %{ticket: "MES-" <> _, class: class, why: why, owner: owner} = entry
      assert class in Classification.classes()
      assert is_binary(why) and why != "" and is_binary(owner) and owner != ""
    end
  end
end

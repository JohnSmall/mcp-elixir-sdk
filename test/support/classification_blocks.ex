defmodule MCP.Test.ClassificationBlocks do
  @moduledoc """
  MES-232 (PM ruling 34937). Judges committed census classification blocks
  against `MCP.Conformance.Classification`: the live table first, then the
  frozen `Classification.retired/0` entries.

  A block is expected to equal the live entry for its id, or failing that the
  retired entry, byte for byte. An id that is neither live nor retired is
  `unknown`; any difference from the expected entry is `drift`. A pure function,
  so `ClassificationTest` judges the committed censuses with it and
  `ClassificationRetiredTest` feeds it synthetic blocks as controls.
  """

  alias MCP.Conformance.Classification

  @type block_ref :: {String.t(), String.t(), map()}

  @spec judge([block_ref()], %{String.t() => map()}) ::
          {[{String.t(), String.t()}], [{String.t(), String.t()}]}
  def judge(blocks, retired) do
    # No assignment clauses inside these comprehensions: one acts as a FILTER,
    # which is how a block for an unknown id once removed its own row (MES-63).
    unknown =
      for {b, id, _} <- blocks,
          Classification.fetch(id) == nil,
          not Map.has_key?(retired, id),
          do: {b, id}

    drift =
      for {b, id, block} <- blocks,
          expected(id, retired) != nil,
          block != expected(id, retired),
          do: {b, id}

    {unknown, drift}
  end

  @doc "The block a committed census should carry for `id`, or nil if it is neither live nor retired."
  @spec expected(String.t(), %{String.t() => map()}) :: map() | nil
  def expected(id, retired) do
    case Classification.fetch(id) do
      nil -> as_block(Map.get(retired, id))
      entry -> as_block(entry)
    end
  end

  defp as_block(nil), do: nil

  defp as_block(entry),
    do: %{"class" => to_string(entry.class), "why" => entry.why, "owner" => entry.owner}
end

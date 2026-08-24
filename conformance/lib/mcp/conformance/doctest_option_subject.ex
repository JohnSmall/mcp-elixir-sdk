defmodule MCP.Conformance.DoctestOptionSubject do
  @moduledoc """
  MES-84 (B4) probe subject. Three functions carrying **five** doctest examples,
  so that `doctest`'s option handling can be measured rather than asserted (AC4).

  Nothing in `lib/` uses this and nothing in `test/` doctests it. It is driven
  only by the three fixtures in `conformance/controls/etcc_doctest_*_fixture.exs`,
  which live outside `test_paths` and so are never reached by `mix test`. The
  example counts below are the whole point of the module, and are what the three
  fixtures select over:

    * `a/1`  — examples 1 and 2
    * `b?/1` — examples 3 and 4 **in a full run**
    * `c/1`  — example 5 **in a full run**

  `b?/1` is a predicate on purpose. An identifier pattern written as `\\w+` does
  not match the `?`, and that is exactly how a doctest census under-counted 9
  against an artefact's 13 at this ticket's dispatch. A probe whose own subject
  cannot expose that would be measuring the easy case.
  """

  @doc """
  The identity, with two examples.

      iex> MCP.Conformance.DoctestOptionSubject.a(1)
      1

      iex> MCP.Conformance.DoctestOptionSubject.a(3)
      3
  """
  @spec a(term()) :: term()
  def a(x), do: x

  @doc """
  A predicate, with two examples — and a `?` in its name.

      iex> MCP.Conformance.DoctestOptionSubject.b?(1)
      true

      iex> MCP.Conformance.DoctestOptionSubject.b?(0)
      false
  """
  @spec b?(number()) :: boolean()
  def b?(x), do: x > 0

  @doc """
  A third function, with one example, so the renumbering is visible past the
  selected range as well as inside it.

      iex> MCP.Conformance.DoctestOptionSubject.c(:only)
      :only
  """
  @spec c(term()) :: term()
  def c(x), do: x
end

defmodule MCP.Conformance.ETCCTags do
  @moduledoc """
  MES-84 (B4). Make the ET-CC member set **selectable by the suite**, derived
  from B2a's register rather than maintained beside it.

  ## The direction of derivation, and why it is the whole ticket

  **The tag is derived from the register; the register is never derived from the
  tag.** A hand-applied `:etcc` would be a second, independently-maintained
  record of membership, and the two would drift the first time anyone added a
  test — the S5-31 two-`totals` hazard, except that here a drifted tag makes
  `mix test.etcc` run the wrong set while looking authoritative.

  So this module owns exactly one thing: given
  `docs/conformance/etcc-register.json`, say which mechanism marks each member
  and which keys the resulting selection must contain. `Mix.Tasks.Conformance.EtccTags`
  applies and checks the source side, `Mix.Tasks.Test.Etcc` runs the selection and
  adjudicates it, and `conformance/controls/etcc_tags_controls.exs` is the evidence
  that both fail red when they should. Three consumers, one derivation.

  ## The mechanism rule, as an antecedent rather than a list of rows

  Ruled by the PM at MES-84 comment `26108` and restated here as the rule
  `mechanism/2` implements, because a list of six declarations would go stale the
  moment a seventh appeared:

  > A tag may be applied to a construct only where **every runtime unit that
  > construct generates is a member**. Otherwise it goes on the individual units;
  > and where the construct cannot express that — a `doctest` directive — the
  > member is selected by exact name instead.

  One `describe`, `for` or `doctest` construct produces N runtime units and a
  source `@tag` reaches all N (S6-6). Grouping the register by `{file, line}` is
  therefore the only grouping that answers "what can a tag reach", and it is what
  `declarations/1` computes. The three outcomes:

    * `:tag` — every unit at this declaration is a member and the units are
      `test`s. `@tag :etcc` immediately above the declaration.
    * `:directive` — every unit is a member and the units are `doctest`s.
      `doctest Mod, tags: [:etcc]`, which reaches every example of every
      function-arity the directive generates.
    * `:name` — the declaration mixes members with non-members and the units are
      `doctest`s. The tag cannot express it, so those members are selected by
      exact test name. See "the declined split" below.

  A `test` declaration that mixes members with non-members has **no** mechanism —
  a `@tag` would over-tag and no smaller marker exists. `plan/1` puts those in
  `:escalations` and every consumer refuses while it is non-empty, rather than
  choosing a direction to be wrong in. Measured at `128dee4`: it is empty.

  ## The declined split, and what it costs

  `test/mcp/protocol/extensions_test.exs:35` is the one mixed declaration in the
  tree: 9 doctests, of which 2 are members. `doctest Mod, only: [from_meta: 1],
  tags: [:etcc]` would tag exactly those 2 — but `only:`/`except:` **renumber the
  example index**, and that index is inside the row key
  (`docs/conformance/etcc-row-key.md` §1), which is the authored join key of
  `conformance/data/etcc-decisions.json`. Splitting would re-key 9 entries of a
  merged deliverable and force a rebuild of the register, the attribution and the
  rows artefact.

  **PM ruling (`26115`, re-dispatched at `26117`): do not split.** Those 2 members
  are selected by exact name and carry no marker in the source — so a reader of
  `extensions_test.exs` sees nothing on them. That cost is recorded as S7-33. The
  condition attached to the ruling is that the 2 keys are **first-class in the
  guard**: they are in `expected_keys/1` like any other member, so if the name
  filter ever stops selecting them the adjudication goes red naming them. There is
  no unguarded special case.

  ## Name selection is exact only because the names are unique

  A bare `--only 'test:<name>'` filter matches on the test name alone, across
  every module. That is exact in this tree because all of the artefact's names are
  distinct — measured, zero collisions — and that is a **property of the tree, not
  a guarantee of the mechanism**. `name_collisions/1` is therefore computed and
  asserted empty by the consumers, so a future collision goes red instead of
  silently widening the selection.

  ## The knob, and the one thing it does beyond naming a tag

  `MCP_ETCC_TAG` (default `:etcc`) changes **which tag is selected on**, so the
  refusal path can be demonstrated without mutating 265 source lines (PM `26116`,
  E4). It cannot change, relax or bypass the register-side expectation: that comes
  from `expected_keys/1` and from nothing else.

  It has one consequence worth stating plainly, because it is a design decision
  and not a side effect. A name proxy exists to **stand in for a tag ExUnit cannot
  place**. When the selected tag is not the tag the source was marked with, there
  is no tag to stand in for, so `Mix.Tasks.Test.Etcc` drops the proxies — a proxy
  applied to a tag nobody applied would be inventing membership. This is what
  makes a genuinely zero-selecting run reachable end to end (AC3), and it is why
  the partial-selection case is demonstrated by a one-line source mutation instead.
  """

  @register "docs/conformance/etcc-register.json"
  @member_label "ET-CC"
  @default_tag :etcc
  @tag_env "MCP_ETCC_TAG"

  @typedoc "A source declaration, grouped by `{file, line}`, with the units it generates."
  @type declaration :: %{
          file: String.t(),
          line: pos_integer(),
          test_type: String.t(),
          units: [map()],
          members: [map()],
          mechanism: :tag | :directive | :name | :escalate | :none
        }

  # ---------------------------------------------------------------------------
  # Paths and configuration
  # ---------------------------------------------------------------------------

  @doc "Paths, so the task, the control and the runner cannot drift apart."
  @spec paths() :: %{register: String.t()}
  def paths, do: %{register: @register}

  @doc "The label a register row carries when it is a member."
  @spec member_label() :: String.t()
  def member_label, do: @member_label

  @doc "The tag the source is marked with, and the default selection tag."
  @spec default_tag() :: atom()
  def default_tag, do: @default_tag

  @doc "Name of the environment variable that overrides the SELECTION tag only."
  @spec tag_env_var() :: String.t()
  def tag_env_var, do: @tag_env

  @doc """
  The tag this run selects on: `MCP_ETCC_TAG` if set and non-empty, else `:etcc`.

  `String.to_atom/1` is safe here and only here: the value comes from the
  operator's own environment, not from a request, and ExUnit's filter API takes
  an atom. It is not called on any register or artefact content.
  """
  @spec selection_tag() :: atom()
  def selection_tag do
    case System.get_env(@tag_env) do
      nil -> @default_tag
      "" -> @default_tag
      name -> String.to_atom(name)
    end
  end

  @doc "The literal a source `@tag` line carries."
  @spec tag_line_body() :: String.t()
  def tag_line_body, do: "@tag :#{@default_tag}"

  # ---------------------------------------------------------------------------
  # Reading
  # ---------------------------------------------------------------------------

  @doc "Read the register. Raises if it is absent — a missing register is not an empty one."
  @spec read_register!(String.t()) :: map()
  def read_register!(path \\ @register) do
    unless File.exists?(path) do
      raise "no register at #{path}. The member set is DERIVED from it, so its absence " <>
              "is a refusal and not an empty selection."
    end

    path |> File.read!() |> Jason.decode!()
  end

  @doc "The register's in-scope rows, in register order."
  @spec rows(map()) :: [map()]
  def rows(register), do: Map.fetch!(register, "rows")

  @doc "The member rows — the `ET-CC` subset of `rows/1`."
  @spec members(map()) :: [map()]
  def members(register), do: Enum.filter(rows(register), &(&1["label"] == @member_label))

  @doc "The member key set. THE register-side expectation, and its only source."
  @spec expected_keys(map()) :: MapSet.t()
  def expected_keys(register), do: MapSet.new(members(register), & &1["key"])

  # ---------------------------------------------------------------------------
  # The derivation
  # ---------------------------------------------------------------------------

  @doc """
  Group the register's rows by `{file, line}` — one entry per source declaration.

  This is the grouping a source `@tag` can actually address, which is why the
  register's 579 runtime units collapse to 539 declarations here.
  """
  @spec declarations(map()) :: [declaration()]
  def declarations(register) do
    register
    |> rows()
    |> Enum.group_by(&{&1["file"], &1["line"]})
    |> Enum.map(fn {{file, line}, units} ->
      members = Enum.filter(units, &(&1["label"] == @member_label))

      %{
        file: file,
        line: line,
        test_type: unit_type!(file, line, units),
        units: Enum.sort_by(units, & &1["key"]),
        members: Enum.sort_by(members, & &1["key"]),
        mechanism: mechanism(units, members)
      }
    end)
    |> Enum.sort_by(&{&1.file, &1.line})
  end

  @doc """
  The mechanism rule, and the only place it is decided.

  Reads as the PM's antecedent reads: all-members lets the construct carry the
  mark, a mixture does not, and a `doctest` directive falls back to name
  selection because it has no smaller marker.
  """
  @spec mechanism([map()], [map()]) :: :tag | :directive | :name | :escalate | :none
  def mechanism(_units, []), do: :none

  def mechanism(units, members) do
    doctest? = hd(units)["test_type"] == "doctest"

    cond do
      length(members) == length(units) and doctest? -> :directive
      length(members) == length(units) -> :tag
      doctest? -> :name
      true -> :escalate
    end
  end

  @doc """
  The whole derivation: which declarations get which mechanism, and what the
  resulting selection must contain.

  `expected_keys` is read off the register's labels and NOT off the mechanisms,
  so a member whose mechanism was mis-derived goes missing from the selection and
  is caught, rather than quietly dropping out of the expectation as well.
  """
  @spec plan(map()) :: map()
  def plan(register) do
    declarations = declarations(register)
    by = Enum.group_by(declarations, & &1.mechanism)

    %{
      expected_keys: expected_keys(register),
      expected_count: register |> members() |> length(),
      tag_points: Map.get(by, :tag, []),
      directive_points: Map.get(by, :directive, []),
      name_points: Map.get(by, :name, []),
      escalations: Map.get(by, :escalate, []),
      declarations: declarations
    }
  end

  @doc """
  The keys a `--only 'test:<name>'` filter must carry, with the name to filter on.

  Flattened out of `:name_points` so a consumer never has to re-walk the grouping,
  and sorted so the argv a run was launched with is reproducible.
  """
  @spec name_proxies(map()) :: [%{key: String.t(), name: String.t(), file: String.t()}]
  def name_proxies(plan) do
    plan.name_points
    |> Enum.flat_map(fn d ->
      Enum.map(d.members, &%{key: &1["key"], name: &1["name"], file: &1["file"]})
    end)
    |> Enum.sort_by(& &1.key)
  end

  @doc """
  Keys the `:tag` and `:directive` mechanisms are expected to mark in source.

  `expected_keys/1` minus the name proxies — i.e. what a source-side check can
  see. Kept separate so that "the source does not mark these 2" is a stated
  residual rather than a silent gap in the source check.
  """
  @spec source_marked_keys(map()) :: MapSet.t()
  def source_marked_keys(plan) do
    (plan.tag_points ++ plan.directive_points)
    |> Enum.flat_map(fn d -> Enum.map(d.members, & &1["key"]) end)
    |> MapSet.new()
  end

  @doc """
  Test names appearing on more than one row, with their count.

  Empty in this tree, and asserted rather than assumed: exact-name selection is
  only exact while it is empty.
  """
  @spec name_collisions(map()) :: [%{name: String.t(), rows: pos_integer()}]
  def name_collisions(register) do
    register
    |> rows()
    |> Enum.frequencies_by(& &1["name"])
    |> Enum.filter(fn {_name, n} -> n > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {name, n} -> %{name: name, rows: n} end)
  end

  # ---------------------------------------------------------------------------
  # The comparison — both directions, one function
  # ---------------------------------------------------------------------------

  @doc """
  The set difference, **both ways**.

  HAZARD 3: a guard checking only "every tagged test is in the register" passes
  while half the register is untagged, and one checking only the converse passes
  when a stray tag is added. So there is one function, it returns both sides, and
  every consumer refuses on either being non-empty. `missing` is expected-and-not-
  selected; `stray` is selected-and-not-expected.
  """
  @spec diff(Enumerable.t(), Enumerable.t()) :: %{missing: [String.t()], stray: [String.t()]}
  def diff(expected, actual) do
    expected = MapSet.new(expected)
    actual = MapSet.new(actual)

    %{
      missing: expected |> MapSet.difference(actual) |> Enum.sort(),
      stray: actual |> MapSet.difference(expected) |> Enum.sort()
    }
  end

  @doc """
  Adjudicate a selection against the register's member set.

  One comparison, not two mechanisms that can disagree: AC1's both-directions
  assertion and AC3's vacuous-run refusal are the same equality, and zero
  selected is simply one instance of it (along with 280 and 282).

  `cause` names zero separately not because it is checked separately, but because
  a run that evaluated **nothing** is the failure mode most likely to be read as
  success, and the message should say so in those words.
  """
  @spec adjudicate(MapSet.t(), Enumerable.t()) :: map()
  def adjudicate(expected, selected) do
    expected = MapSet.new(expected)
    selected = MapSet.new(selected)
    d = diff(expected, selected)
    ok? = d.missing == [] and d.stray == []

    %{
      ok: ok?,
      expected: MapSet.size(expected),
      selected: MapSet.size(selected),
      missing: d.missing,
      stray: d.stray,
      cause: cause(ok?, MapSet.size(selected), MapSet.size(expected), d)
    }
  end

  defp cause(true, _selected, _expected, _d), do: nil

  defp cause(false, 0, expected, _d) do
    "ZERO tests were selected. A run that evaluated nothing is not a pass — " <>
      "the register names #{expected} member(s) and every one of them is missing."
  end

  defp cause(false, selected, expected, d) do
    "the selected set is not the register's member set: #{selected} selected " <>
      "against #{expected} expected — #{length(d.missing)} missing, #{length(d.stray)} stray. " <>
      "No exit status can separate a partial selection from a complete one, which is " <>
      "why the KEY SET is adjudicated and not the status."
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  # A declaration whose units disagree about their type is not a thing this tree
  # can produce, so it is raised on rather than resolved: silently taking the
  # first would pick a mechanism for the other kind.
  defp unit_type!(file, line, units) do
    case units |> Enum.map(& &1["test_type"]) |> Enum.uniq() do
      [one] ->
        one

      many ->
        raise "#{file}:#{line} generates units of more than one test_type " <>
                "(#{Enum.join(many, ", ")}). A mechanism is chosen per declaration, so a " <>
                "declaration that is two kinds at once has no answer."
    end
  end
end

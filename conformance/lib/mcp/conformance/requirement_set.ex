defmodule MCP.Conformance.RequirementSet do
  @moduledoc """
  The **denominator**: which scenarios a revision requires, parsed from the two
  places the harness states it, and cross-checked against each other.

  ## The defect this answers

  MES-51 made a run's figures *attributable*. It did not make them *complete*.
  Nothing compared the scenarios that RAN against the scenarios that SHOULD have
  run, and the manifest could not: under `--requirements` it records the frozen
  set's identity — path, md5, sha256, revision — but never its **contents**. A
  scored scenario that silently did not run is therefore invisible, and the
  harness exits 0 having skipped it. That is S5-5's shape (a count naming
  something it does not count) one level up: a rate over a denominator nobody
  checked.

  ## Two derivations, so the parser can be falsified rather than trusted

  The frozen set is available twice over, and both are captured into the run
  directory by `MCP.Conformance.Runner`:

    * `requirements.yaml` — a byte copy of the harness's own frozen file, the
      one whose md5 the manifest already pins. This is the **source**.
    * `expected.txt` — verbatim stdout of `conformance list --requirements REV`.
      This is the **harness's own rendering** of that source.

  `parse/2` reads both and refuses if they disagree. A hand-rolled YAML reader
  that quietly mis-parses is exactly the kind of instrument this sprint exists
  to distrust, so it is never the only witness: if my reading of the file and
  the harness's reading of the same file differ, the run refuses rather than
  proceeding on mine.

  The cross-check is not free of assumptions and the bound is worth stating: the
  two derivations share a common cause. Both describe the file at
  `requirements/REV.yaml` inside the installed harness, so a **corrupted install
  is agreed upon by both** and passes here. What the manifest's `md5`/`sha256`
  of that same file, and `harness.dist_sha256`, are for.

  ## Why the YAML is parsed by hand

  The grammar this file needs is a fixed, three-key shape written by one
  generator: two flat lists of scalars and a list of uniform records with an
  optional folded `note`. Adding a YAML dependency to a published SDK's
  `mix.exs` to read it would be a permanent runtime cost for a development-only
  tool. The parser is deliberately narrow and **fails loudly on anything it does
  not recognise** rather than skipping it — a skipped line here is a scenario
  missing from a denominator.
  """

  @legs ~w(server client)

  @typedoc """
  The frozen requirement set.

    * `:scored` — scenario ids that count toward conformance, by leg.
    * `:not_scored` — run and reported but never scored, each with the
      **harness's own** reason (`extension`, `pending`, `added-after-release`).
      The reason is quoted, never inferred: three of the six classification
      buckets MES-56 must report come from here rather than from judgement.
  """
  @type t :: %{
          scored: %{String.t() => [String.t()]},
          not_scored: [%{scenario: String.t(), leg: String.t(), reason: String.t()}]
        }

  @doc "Filename of the captured `list --requirements` output at the run root."
  @spec expected_filename() :: String.t()
  def expected_filename, do: "expected.txt"

  @doc "Filename of the byte copy of the frozen requirement set at the run root."
  @spec requirements_copy_filename() :: String.t()
  def requirements_copy_filename, do: "requirements.yaml"

  @doc """
  Parse both derivations and cross-check them.

  Returns `{:ok, t()}` when they agree, or `{:error, reason}` when either will
  not parse or when they describe different sets. The error is a sentence, not a
  code: its only consumer is a refusal message.
  """
  @spec parse(String.t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(yaml_body, expected_body) do
    with {:ok, from_yaml} <- parse_yaml(yaml_body),
         {:ok, from_console} <- parse_expected(expected_body),
         :ok <- agree(from_yaml, from_console) do
      {:ok, from_yaml}
    end
  end

  @doc """
  Scenario ids this leg is expected to RUN: the scored ones plus the not-scored
  ones filed under that leg.

  A not-scored scenario still runs, so a run that omitted one is incomplete even
  though the omission cannot change a rate. It is reported and never refuses.
  """
  @spec expected_to_run(t(), String.t()) :: %{scored: [String.t()], not_scored: [String.t()]}
  def expected_to_run(set, leg) do
    %{
      scored: Map.get(set.scored, leg, []),
      not_scored: set.not_scored |> Enum.filter(&(&1.leg == leg)) |> Enum.map(& &1.scenario)
    }
  end

  @doc """
  Diff what was expected against what ran, for one leg.

  Returns `%{missing_scored:, missing_not_scored:, unexpected:}`, each a sorted
  list of scenario ids and each **named** rather than counted (A2d): a count
  tells a reader that something is wrong and not which thing, and this project
  has already published one figure that was wrong by a factor of four while its
  count looked plausible.
  """
  @spec diff(t(), String.t(), [String.t()]) :: %{
          missing_scored: [String.t()],
          missing_not_scored: [String.t()],
          unexpected: [String.t()]
        }
  def diff(set, leg, ran) do
    %{scored: scored, not_scored: not_scored} = expected_to_run(set, leg)
    ran_set = MapSet.new(ran)

    %{
      missing_scored: Enum.sort(Enum.reject(scored, &MapSet.member?(ran_set, &1))),
      missing_not_scored: Enum.sort(Enum.reject(not_scored, &MapSet.member?(ran_set, &1))),
      unexpected: Enum.sort(ran -- (scored ++ not_scored))
    }
  end

  @doc "The harness's own reason for a not-scored scenario, or `nil` if it is scored."
  @spec harness_reason(t(), String.t()) :: String.t() | nil
  def harness_reason(set, scenario) do
    Enum.find_value(set.not_scored, fn e -> if e.scenario == scenario, do: e.reason end)
  end

  # --- the frozen yaml -------------------------------------------------------

  defp parse_yaml(body) do
    body
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{section: nil, scored: %{}, not_scored: []}}, &yaml_line/2)
    |> case do
      {:error, _} = err -> err
      {:ok, acc} -> finish_yaml(acc)
    end
  end

  defp yaml_line({raw, lineno}, {:ok, acc}) do
    line = String.replace(raw, ~r/\s+$/, "")

    cond do
      blank_or_comment?(line) -> {:cont, {:ok, acc}}
      section = top_level_key(line) -> {:cont, {:ok, %{acc | section: section}}}
      acc.section in @legs -> scalar_entry(line, lineno, acc)
      acc.section == "not_scored" -> record_entry(line, lineno, acc)
      true -> {:halt, {:error, "line #{lineno}: #{inspect(line)} sits under no known key"}}
    end
  end

  # Every per-line helper returns `{:ok, acc}` or `{:error, why}`; this is the
  # one place that decides which of those continues the fold and which stops it.
  defp halt_on_error({:ok, _} = ok), do: {:cont, ok}
  defp halt_on_error({:error, _} = err), do: {:halt, err}

  defp blank_or_comment?(line),
    do: String.trim(line) == "" or String.starts_with?(String.trim(line), "#")

  defp top_level_key(line) do
    case Regex.run(~r/^([a-z_]+):$/, line) do
      [_, key] when key in ["server", "client", "not_scored"] -> key
      _ -> nil
    end
  end

  defp scalar_entry(line, lineno, acc) do
    case Regex.run(~r/^  - (\S+)$/, line) do
      [_, id] ->
        {:cont, {:ok, %{acc | scored: Map.update(acc.scored, acc.section, [id], &(&1 ++ [id]))}}}

      _ ->
        {:halt, {:error, "line #{lineno}: #{inspect(line)} is not a scenario id under a leg key"}}
    end
  end

  # The `note:` values are folded blocks (`>-`) whose continuations are indented
  # further than the key. They are prose for humans and carry nothing this tool
  # judges, so they are consumed and discarded — but only where a note is open,
  # so an unrecognised line elsewhere still fails rather than being absorbed.
  defp record_entry(line, lineno, acc) do
    scenario = Regex.run(~r/^  - scenario: (\S+)$/, line)
    field = Regex.run(~r/^    (leg|reason): (\S+)$/, line)

    cond do
      is_list(scenario) ->
        entry = %{scenario: Enum.at(scenario, 1), leg: nil, reason: nil}
        {:cont, {:ok, %{acc | not_scored: acc.not_scored ++ [entry]}}}

      is_list(field) ->
        # `{:cont, {:error, _}}` would hand the next line an accumulator no
        # clause matches, turning a parse error into a FunctionClauseError two
        # lines later. Every error path halts.
        halt_on_error(put_field(acc, Enum.at(field, 1), Enum.at(field, 2), lineno))

      Regex.match?(~r/^    note: >-$/, line) ->
        {:cont, {:ok, acc}}

      Regex.match?(~r/^      \S/, line) ->
        {:cont, {:ok, acc}}

      true ->
        {:halt, {:error, "line #{lineno}: #{inspect(line)} is not a not_scored field"}}
    end
  end

  defp put_field(%{not_scored: []}, key, _value, lineno),
    do: {:error, "line #{lineno}: #{key}: appears before any `- scenario:`"}

  defp put_field(acc, key, value, _lineno) do
    {init, [last]} = Enum.split(acc.not_scored, -1)
    {:ok, %{acc | not_scored: init ++ [Map.put(last, String.to_existing_atom(key), value)]}}
  end

  defp finish_yaml(acc) do
    incomplete = Enum.filter(acc.not_scored, &(is_nil(&1.leg) or is_nil(&1.reason)))
    bad_leg = Enum.filter(acc.not_scored, &(not is_nil(&1.leg) and &1.leg not in @legs))
    missing_legs = Enum.reject(@legs, &Map.has_key?(acc.scored, &1))

    cond do
      missing_legs != [] ->
        {:error, "the frozen set has no #{Enum.join(missing_legs, " and no ")} key"}

      incomplete != [] ->
        {:error,
         "not_scored entries missing leg or reason: " <>
           inspect(Enum.map(incomplete, & &1.scenario))}

      bad_leg != [] ->
        {:error, "not_scored entries name an unknown leg: " <> inspect(bad_leg)}

      true ->
        with :ok <- unambiguous(acc, "the frozen set"),
             do: {:ok, %{scored: acc.scored, not_scored: acc.not_scored}}
    end
  end

  # MES-56 correction round 2. Every denominator this module hands out is a
  # LIST, and every membership test taken against it is a SET — `diff/3` builds
  # a MapSet of what ran, `MCP.Conformance.Census` builds a MapSet of the scored
  # ids, and `agree/2` below compares the two derivations as MapSets on the
  # explicit grounds that their ORDER differs. Multiplicity survives none of
  # those conversions and survives every one of the counts: with `resources-list`
  # listed twice under `server:`, an accepted run reported
  # `expected_counts.scored = 2` for a set of one scenario, with `absentees.scored
  # = []` — the AC2 denominator asserting that nothing was missing from a total
  # it had inflated itself, and the yaml-vs-listing cross-check blind to it
  # because both sides became sets first.
  #
  # So uniqueness is established HERE, once, where the list is built, rather
  # than defended at each of the places that later convert it. Both derivations
  # are checked: a duplicate in the harness's own listing makes the denominator
  # exactly as ambiguous as a duplicate in ours.
  #
  # Scoped per leg deliberately. A scenario id scored on BOTH legs is not
  # checked and must not be: `scored` is keyed by leg and every reader takes
  # `Map.get(scored, leg)`, so cross-leg repetition is well-defined. Refusing it
  # would be a bound this module cannot justify — measured on the real
  # 2026-07-28 set, which has no cross-leg id today, so the rule would be
  # untested as well as unwarranted.
  defp unambiguous(acc, what) do
    repeated_scored =
      for leg <- @legs,
          {id, n} <- Enum.frequencies(Map.get(acc.scored, leg, [])),
          n > 1,
          do: "#{leg}: #{inspect(id)} x#{n}"

    repeated_not_scored =
      for {id, n} <- Enum.frequencies(Enum.map(acc.not_scored, & &1.scenario)),
          n > 1,
          do: "#{inspect(id)} x#{n}"

    both =
      for leg <- @legs,
          e <- acc.not_scored,
          e.leg == leg,
          e.scenario in Map.get(acc.scored, leg, []),
          uniq: true,
          do: "#{leg}: #{inspect(e.scenario)}"

    cond do
      repeated_scored != [] ->
        {:error,
         "#{what} lists a scored scenario more than once (#{Enum.join(Enum.sort(repeated_scored), ", ")}). " <>
           "Every reader takes membership against a set and every count takes it against the " <>
           "list, so a repeat inflates the denominator while the absentee diff stays empty"}

      repeated_not_scored != [] ->
        {:error,
         "#{what} lists a not-scored scenario more than once " <>
           "(#{Enum.join(Enum.sort(repeated_not_scored), ", ")}). `harness_reason/2` returns the " <>
           "FIRST match, so a repeat with a second reason would pick one silently"}

      both != [] ->
        {:error,
         "#{what} lists #{Enum.join(Enum.sort(both), ", ")} as BOTH scored and not-scored for " <>
           "one leg, so it is counted in both denominators and no reader can say which it is"}

      true ->
        :ok
    end
  end

  # --- the harness's own rendering -------------------------------------------

  defp parse_expected(body) do
    body
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce_while(
      {:ok, %{mode: :preamble, scored: %{}, not_scored: [], reason: nil}},
      &expected_line/2
    )
    |> case do
      {:error, _} = err -> err
      {:ok, acc} -> finish_expected(acc)
    end
  end

  defp expected_line({raw, lineno}, {:ok, acc}) do
    line = String.replace(raw, ~r/\s+$/, "")

    cond do
      String.trim(line) == "" -> {:cont, {:ok, acc}}
      new = expected_heading(line) -> {:cont, {:ok, Map.merge(acc, new)}}
      acc.mode in @legs -> halt_on_error(expected_scored(line, lineno, acc))
      acc.mode == :not_scored -> halt_on_error(expected_not_scored(line, lineno, acc))
      acc.mode == :preamble -> {:cont, {:ok, acc}}
      true -> {:halt, {:error, "line #{lineno}: #{inspect(line)} is outside every section"}}
    end
  end

  defp expected_heading(line) do
    cond do
      Regex.match?(~r/^Server scenarios /, line) -> %{mode: "server"}
      Regex.match?(~r/^Client scenarios /, line) -> %{mode: "client"}
      Regex.match?(~r/^Run and reported, but never scored:$/, line) -> %{mode: :not_scored}
      true -> reason_heading(line)
    end
  end

  defp reason_heading(line) do
    case Regex.run(~r/^  ([a-z-]+) \(\d+\):$/, line) do
      [_, reason] -> %{mode: :not_scored, reason: reason}
      _ -> nil
    end
  end

  defp expected_scored(line, lineno, acc) do
    case Regex.run(~r/^  - (\S+)$/, line) do
      [_, id] -> {:ok, %{acc | scored: Map.update(acc.scored, acc.mode, [id], &(&1 ++ [id]))}}
      _ -> {:error, "line #{lineno}: #{inspect(line)} is not a scenario id"}
    end
  end

  defp expected_not_scored(line, lineno, acc) do
    case Regex.run(~r/^    - (\S+) \[(server|client)\]$/, line) do
      [_, id, leg] when not is_nil(acc.reason) ->
        entry = %{scenario: id, leg: leg, reason: acc.reason}
        {:ok, %{acc | not_scored: acc.not_scored ++ [entry]}}

      [_, _, _] ->
        {:error, "line #{lineno}: a not-scored scenario appears under no reason heading"}

      _ ->
        {:error, "line #{lineno}: #{inspect(line)} is not a not-scored scenario"}
    end
  end

  defp finish_expected(%{scored: scored} = acc) do
    case Enum.reject(@legs, &Map.has_key?(scored, &1)) do
      [] ->
        with :ok <- unambiguous(acc, "the harness's own listing"),
             do: {:ok, %{scored: scored, not_scored: acc.not_scored}}

      missing ->
        {:error, "the harness listing has no #{Enum.join(missing, " and no ")} section"}
    end
  end

  # --- the cross-check -------------------------------------------------------

  # Sets, not lists: the yaml groups not-scored entries by scenario and the
  # listing groups them by reason, so the two agree on content and differ on
  # order by construction. Comparing order would refuse every healthy run.
  #
  # The bound that costs, stated rather than left to be rediscovered: a MapSet
  # discards MULTIPLICITY as well as order, so this cross-check cannot see a
  # scenario listed twice on either side. It does not need to — `unambiguous/2`
  # has already refused both derivations before this runs — but the reason it
  # does not need to is a fact about a different function, which is exactly the
  # kind of dependency that goes stale unnamed.
  defp agree(yaml, console) do
    leg_faults =
      Enum.flat_map(@legs, fn leg ->
        a = MapSet.new(Map.get(yaml.scored, leg, []))
        b = MapSet.new(Map.get(console.scored, leg, []))

        if MapSet.equal?(a, b) do
          []
        else
          ["#{leg}: yaml-only #{inspect(sorted(a, b))}, listing-only #{inspect(sorted(b, a))}"]
        end
      end)

    ns_a = MapSet.new(yaml.not_scored)
    ns_b = MapSet.new(console.not_scored)

    ns_faults =
      if MapSet.equal?(ns_a, ns_b),
        do: [],
        else: [
          "not_scored: yaml-only #{inspect(sorted(ns_a, ns_b))}, " <>
            "listing-only #{inspect(sorted(ns_b, ns_a))}"
        ]

    case leg_faults ++ ns_faults do
      [] ->
        :ok

      faults ->
        {:error,
         "the frozen requirement set and the harness's own listing of it disagree, so " <>
           "neither may be used as a denominator: " <> Enum.join(faults, "; ")}
    end
  end

  defp sorted(a, b), do: a |> MapSet.difference(b) |> Enum.sort()
end

defmodule MCP.Conformance.Crosswalk do
  @moduledoc """
  The ET-CC × OC crosswalk: the single matrix the ten buckets are **projections
  of**. C1a (MES-97) builds the instrument and runs it over one declared
  population; C2 renders it, C3 falsifies it, D adjudicates its cells.

  A3 (`docs/conformance/match-relation.md`) owns the **form** — the token, the
  edge record, `bucket = f(verdict pair, edge shape)` — and `MatchKey` is its
  executable half. This module owns the **join**, and it derives every field
  A3 calls derived rather than accepting it from storage.

  ## What is derived and what is read

  | field | where it comes from |
  | --- | --- |
  | `oc_key` | `MatchKey.resolve/2` of the edge's tag against A1's manifest |
  | `tag` | re-`encode/1`d from that key and required to equal the stored one |
  | `shape` | `MatchKey.shape_from_axes/1` |
  | `bucket` | `MatchKey.bucket/1` |
  | OC verdict | A1's committed per-check `status` at the accepted run |
  | ET verdict | the edge record |
  | axes | the edge record, checked against the check's axis decomposition |

  Nothing in `crosswalk-edges.json` may carry a key, a shape or a bucket.
  `validate_edge/1` then re-derives the lot on the way back out, which is what
  a reader checks a round-tripped edge with before counting it.

  ## The declared population, and why the artefact cannot be total without one

  A3 §6's four-state guard **fails** state 4 — an ET-CC member carrying neither
  token kind — by design, so that silence cannot encode a decision. 211 of the
  281 ET-CC members carry neither. A crosswalk declared total over all 281 is
  therefore not a partial artefact, it is a **failing** one by A3's own ratified
  rule.

  So the artefact declares a `population`, the state-4 guard runs **over that
  population**, and buckets 1 and 2 — which are complements, and a complement is
  meaningless without a universe — are **refused outside it**. Everything else
  is `not_yet_adjudicated`: a third state, distinct from bucket 1 (*we looked,
  there is no counterpart*) and from state 4 (*nobody has looked*).

  ## Why that makes the totality AC bite (S9-15)

  MES-97's AC3 read: *every one of the 173 appears exactly once as a match
  target; every ET-CC member appears; the unmatched sets are enumerated*. A
  crosswalk with **zero edges** satisfies it perfectly — all 173 fall into
  bucket 2, all 281 into bucket 1, every set enumerated, the arithmetic exact.
  An AC a wrong artefact satisfies is not an AC (ruling 8).

  The strengthening, PM-approved as D3: emptiness is exactly what the state-4
  guard fires on, because a member with no token is a member the guard fails.
  `check_population/2` is that guard and `project/2` refuses a bucket-1 or
  bucket-2 projection whose universe it was not given.

  ## The escalations — three, where A3 has two

  A3 §3 escalates `(red, green, :full)` and `(green, green, :contradicting)`.
  This module adds a third and does **not** invent a bucket for it:

      every axis silent  ->  {:escalate, :no_axis_contact}

  A3 §2 rules that covering zero of one axis *"is no match, not a partial
  one"*. Generalised to N axes that is this case exactly, and A3 §3's table has
  no row for it — left alone, `shape_from_axes/1` returns `:partial` and bucket
  5 swallows a claim that never touched the check's predicate. Escalating is
  A3 §7's own mechanism for what the rule does not decide, and unlike a new
  bucket it costs nothing if the PM rules the other way.

  ## What a green run of this module does NOT establish

  That an edge's axis verdicts are *correct* — whether our claim really agrees
  with that conjunct is the semantic-sameness residual (A3 §7 item 1) and no
  code here can decide it. What it establishes is that every stored edge
  resolves, re-derives, names axes that exist, and buckets to the cell the
  ratified table sends it to. C3 (MES-99) is what makes the output trustworthy;
  until it lands, six bucket reports derived from this are assertions
  (ruling 5).
  """

  alias MCP.Conformance.MatchKey

  @typedoc "A joined crosswalk cell."
  @type cell :: map()

  @doc """
  Map a harness run status to the `:green` / `:red` pair `MatchKey.bucket/1`
  takes, plus the attributes the mapping must not launder.

  `WARNING -> :green`, carrying `warning: true` — PM-ratified as D2 on measured
  grounds rather than chosen: WARNING is **leg-dependent** (the client-leg
  reducer fails it; `requirements_exit` and the server-leg reducer ignore it),
  and both in-denominator WARNING checks are on the **server** leg, where the
  reducer that would disagree does not apply. The residual is a stated bound: a
  future **client-leg** WARNING needs its own ruling and this function must not
  be extended to cover one silently.

  It fires on **zero** rows of C1a's population — both WARNING checks are
  outside it — so it is implemented and unit-tested here rather than
  demonstrated on live data. Stated, because a rule with no live instance reads
  as exercised when it is not.
  """
  @spec oc_verdict(String.t()) :: {:ok, :green | :red, keyword()} | {:error, term()}
  def oc_verdict("SUCCESS"), do: {:ok, :green, []}
  def oc_verdict("FAILURE"), do: {:ok, :red, []}
  def oc_verdict("WARNING"), do: {:ok, :green, warning: true}
  def oc_verdict(other), do: {:error, {:unmappable_status, other}}

  @doc """
  Every axis of every check in one decomposition artefact, keyed by A1's
  six-field key. Takes A3's file and C1's and **refuses an overlap**: one fact,
  one home, asserted rather than conventional (D4).
  """
  @spec axis_index([map()]) :: {:ok, %{optional([String.t()]) => [String.t()]}} | {:error, term()}
  def axis_index(artefacts) do
    indexes = Enum.map(artefacts, &one_index/1)

    keys = Enum.map(indexes, &MapSet.new(Map.keys(&1)))

    overlap =
      keys
      |> Enum.with_index()
      |> Enum.flat_map(fn {set, i} ->
        keys |> Enum.drop(i + 1) |> Enum.flat_map(&MapSet.to_list(MapSet.intersection(set, &1)))
      end)

    if overlap == [] do
      {:ok, Enum.reduce(indexes, %{}, &Map.merge/2)}
    else
      {:error, {:axis_artefacts_overlap, Enum.uniq(overlap)}}
    end
  end

  defp one_index(%{"checks" => checks}) do
    Map.new(checks, fn c -> {c["key"], Enum.map(c["axes"], & &1["axis"])} end)
  end

  @doc """
  Build one crosswalk cell from a stored edge.

  `rows` are A1's six-field keys, `statuses` maps a key to its committed run
  status, `axes` is `axis_index/1`'s result.
  """
  @spec cell(map(), [MatchKey.oc_key()], map(), map()) :: {:ok, cell()} | {:error, term()}
  def cell(edge, rows, statuses, axes) do
    with {:ok, oc_key} <- resolve_tag(edge["tag"], rows),
         {:ok, status} <- fetch_status(statuses, oc_key),
         {:ok, oc, attrs} <- oc_verdict(status),
         {:ok, et} <- et_verdict(edge["et_verdict"]),
         :ok <- axes_exist(edge, oc_key, axes),
         {:ok, built} <- build_edge(edge, oc_key, oc, et),
         :ok <- MatchKey.validate_edge(built),
         :ok <- tag_round_trips(edge["tag"], built.tag) do
      {:ok, decorate(built, edge, status, attrs)}
    end
  end

  defp resolve_tag(nil, _rows), do: {:error, :edge_has_no_tag}

  defp resolve_tag(tag, rows) do
    case MatchKey.guard_state(tag, rows) do
      {:matched, key} -> {:ok, key}
      {:declared_unmatched, info} -> {:error, {:oc_none_tag_on_an_edge, info}}
      {:error, reason} -> {:error, {:tag_does_not_resolve, tag, reason}}
    end
  end

  defp fetch_status(statuses, key) do
    case Map.fetch(statuses, key) do
      {:ok, status} -> {:ok, status}
      :error -> {:error, {:no_committed_status_for, key}}
    end
  end

  defp et_verdict("green"), do: {:ok, :green}
  defp et_verdict("red"), do: {:ok, :red}
  defp et_verdict(other), do: {:error, {:bad_et_verdict, other}}

  # A verdict recorded against an axis nobody extracted is a verdict about
  # nothing, and it is the easiest thing in this artefact to get wrong: an axis
  # NAME is free text in the edge file and a typo would otherwise sail through
  # into a shape and a bucket.
  defp axes_exist(edge, oc_key, axes) do
    case Map.fetch(axes, oc_key) do
      :error ->
        {:error, {:check_has_no_axis_decomposition, oc_key}}

      {:ok, known} ->
        named = Enum.map(edge["axes"], & &1["axis"])
        unknown = named -- known

        cond do
          unknown != [] -> {:error, {:axis_not_in_decomposition, unknown, known}}
          length(Enum.uniq(named)) != length(named) -> {:error, {:axis_named_twice, named}}
          MapSet.new(named) != MapSet.new(known) -> {:error, {:axes_not_total, known -- named}}
          true -> :ok
        end
    end
  end

  defp build_edge(edge, oc_key, oc, et) do
    MatchKey.new_edge(%{
      member: %{module: edge["member"]["module"], test: edge["member"]["test"]},
      claim: edge["claim"],
      oc_key: oc_key,
      verdicts: %{oc: oc, et: et},
      axes:
        Enum.map(
          edge["axes"],
          &%{axis: &1["axis"], verdict: String.to_existing_atom(&1["verdict"])}
        )
    })
  end

  defp tag_round_trips(stored, derived) when stored == derived, do: :ok

  defp tag_round_trips(stored, derived),
    do: {:error, {:tag_is_not_what_the_key_encodes, stored, derived}}

  defp decorate(built, edge, status, attrs) do
    {bucket, bucket_attrs, escalation} = assign(built)

    %{
      "member" => %{
        "module" => built.member.module,
        "test" => built.member.test,
        "register_key" => edge["member"]["register_key"]
      },
      "claim" => built.claim,
      "tag" => built.tag,
      "oc_key" => built.oc_key,
      "verdicts" => %{
        "oc" => Atom.to_string(built.verdicts.oc),
        "et" => Atom.to_string(built.verdicts.et),
        "oc_status_at_accepted_run" => status,
        "oc_warning" => Keyword.get(attrs, :warning, false)
      },
      "axes" =>
        Enum.map(built.axes, &%{"axis" => &1.axis, "verdict" => Atom.to_string(&1.verdict)}),
      "shape" => Atom.to_string(built.shape),
      "bucket" => bucket,
      "bucket_attributes" => Enum.map(bucket_attrs, &Atom.to_string/1),
      "escalation" => escalation,
      "evidence" => edge["evidence"],
      "note" => edge["note"]
    }
  end

  @doc """
  `bucket = f(verdict pair, edge shape)`, with the all-silent case intercepted
  **before** `MatchKey.bucket/1` sees it.

  Returns `{bucket_or_nil, attributes, escalation_or_nil}`.
  """
  @spec assign(MatchKey.edge()) :: {String.t() | nil, [atom()], String.t() | nil}
  def assign(%{axes: axes} = edge) do
    if Enum.all?(axes, &(&1.verdict == :silent)) do
      {nil, [],
       "no_axis_contact — every axis of this check is silent. A3 §2 rules that covering zero " <>
         "of one axis is no match, not a partial one; generalised to #{length(axes)} axes that " <>
         "is this edge. §3's table has no row for it, so it escalates rather than being bucketed."}
    else
      case MatchKey.bucket(edge) do
        {:ok, bucket, attrs} -> {bucket, attrs, nil}
        {:escalate, reason} -> {nil, [], "#{inspect(reason)} — match-relation.md §3"}
      end
    end
  end

  @doc """
  The A3 §6 state-4 guard, run over a **declared** population.

  `members` are the population's register keys; `tagged` are the keys that carry
  a token of either kind. Returns `:ok` or the untagged members, which is the
  guard firing.

  This is the limb that makes an empty crosswalk fail rather than pass: a
  population with no tagged members is a population that is entirely state 4.
  """
  @spec check_population([String.t()], [String.t()]) ::
          :ok | {:error, {:state_4_members, [String.t()]}}
  def check_population(members, tagged) do
    case Enum.reject(members, &(&1 in tagged)) do
      [] -> :ok
      untagged -> {:error, {:state_4_members, untagged}}
    end
  end

  @doc """
  Buckets 1 and 2 over a declared universe — and **refused** without one.

  Both are complements over the edge set, and a complement is not a fact about
  the world without a universe to take it in. Asking for bucket 1 over "all 281
  ET-CC members" when only 21 were adjudicated would report 260 members as
  *"we looked and there is no counterpart"*, which is false of every one of
  them.
  """
  @spec project(:bucket_1 | :bucket_2, map()) :: {:ok, [term()]} | {:error, term()}
  def project(_which, %{population: nil}), do: {:error, :no_declared_population}
  def project(_which, %{population: []}), do: {:error, :empty_population}

  def project(:bucket_1, %{population: members, with_edges: with_edges}) do
    {:ok, Enum.reject(members, &(&1 in with_edges))}
  end

  def project(:bucket_2, %{population: checks, with_edges: with_edges}) do
    {:ok, Enum.reject(checks, &(&1 in with_edges))}
  end

  @doc """
  Totality by **set comparison**, never by arithmetic.

  Two counts agreeing is not two sets agreeing: 21 members matched and 21
  members in the population reconcile perfectly when one of each is the wrong
  one. Returns the two directions separately, because *missing* and *extra* are
  different defects with different remedies.
  """
  @spec set_compare(Enumerable.t(), Enumerable.t()) :: %{
          missing: [term()],
          extra: [term()],
          equal: boolean()
        }
  def set_compare(expected, actual) do
    e = MapSet.new(expected)
    a = MapSet.new(actual)

    %{
      missing: e |> MapSet.difference(a) |> MapSet.to_list() |> Enum.sort(),
      extra: a |> MapSet.difference(e) |> MapSet.to_list() |> Enum.sort(),
      equal: MapSet.equal?(e, a)
    }
  end

  @doc """
  The keying control, both directions, **measured** rather than asserted.

  Returns how many rows each projection loses — *rows lost* is A1's measure and
  §5's, so the two keyings are compared in the unit those documents already
  use. The obvious-field keyings must lose rows and the six-field key must lose
  none; a control that only ever ran the second direction would pass over a
  crosswalk keyed on `id`.
  """
  @spec keying_control([[String.t()]]) :: map()
  def keying_control(rows) do
    total = length(rows)

    lost = fn project ->
      total - (rows |> Enum.map(project) |> Enum.uniq() |> length())
    end

    %{
      "rows" => total,
      "by_check_id_alone" => lost.(&Enum.at(&1, 2)),
      "by_name_alone" => lost.(&Enum.at(&1, 3)),
      "by_description_alone" => lost.(&Enum.at(&1, 4)),
      "by_check_id_and_name" => lost.(&[Enum.at(&1, 2), Enum.at(&1, 3)]),
      "by_the_token_five" => lost.(&(Enum.take(&1, 4) ++ [Enum.at(&1, 5)])),
      "by_a1s_six_field_key" => lost.(& &1)
    }
  end

  @doc """
  **G14** — the rows of an edge file that share a `(register_key, claim, tag)`
  triple, which is the join's own key.

  C1a tests this on the committed **output** (`crosswalk_controls.exs keying`).
  A check on the artefact is not a refusal on the generator's path, and the
  distinction is exactly S9-15's: measured on MES-99, an edge duplicated
  verbatim built **cleanly**, taking the edge count 23 → 24 and bucket 5 from
  15 → 16. Every downstream reconciliation still held, because a duplicate
  shrinks nothing and contradicts nothing — it just counts a match twice.

  Returns the offending triples, so the caller names them rather than reporting
  a count.
  """
  @spec duplicate_edge_keys([map()]) :: [{String.t(), String.t(), String.t()}]
  def duplicate_edge_keys(edges) do
    triples = Enum.map(edges, &{&1["member"]["register_key"], &1["claim"], &1["tag"]})

    (triples -- Enum.uniq(triples)) |> Enum.uniq() |> Enum.sort()
  end

  @doc """
  **G15a** — evaluate a population `selector` against the artefact it names.

  The selector is the executable half of the edges file's prose `rule`. It must
  denote its population from a source **outside the file under validation**:
  C1a derived the population by unioning the edges' and declared-unmatched
  members' keys, so a dropped row did not violate the universe, it *shrank*
  it, and the artefact stayed internally perfect while being about less than it
  claimed. Measured on MES-99: dropping one edge and dropping one
  declared-unmatched member each built cleanly, 21 members → 20.

  Fail-closed in every direction a selector can be wrong: an unknown `test`, an
  absent `rows_at`, a `key_field` a row does not carry, and a source whose keys
  are not unique (a duplicate would silently merge two rows into one member and
  hide the drop it was brought in to catch).

  Supported tests are `non_empty_list` and `not_null` — deliberately two, and
  deliberately named rather than a general expression language: a selector rich
  enough to compute is a selector rich enough to lie.
  """
  @spec select(map(), map()) :: {:ok, [String.t()]} | {:error, term()}
  def select(%{"rows_at" => rows_at, "key_field" => key_field, "any_of" => [_ | _] = tests}, src) do
    with {:ok, preds} <- predicates(tests),
         {:ok, rows} <- rows_at(src, rows_at),
         {:ok, keys} <- keys_of(rows, key_field, preds) do
      case (keys -- Enum.uniq(keys)) |> Enum.uniq() do
        [] -> {:ok, Enum.sort(keys)}
        dupes -> {:error, {:selector_source_has_duplicate_keys, dupes}}
      end
    end
  end

  def select(other, _src), do: {:error, {:malformed_selector, other}}

  defp rows_at(src, rows_at) do
    case Map.get(src, rows_at) do
      rows when is_list(rows) -> {:ok, rows}
      _ -> {:error, {:selector_names_no_such_rows, rows_at}}
    end
  end

  defp keys_of(rows, key_field, preds) do
    keys =
      rows
      |> Enum.filter(fn row -> Enum.any?(preds, & &1.(row)) end)
      |> Enum.map(&Map.get(&1, key_field))

    if Enum.any?(keys, &(not is_binary(&1))),
      do: {:error, {:selector_key_field_is_not_a_string, key_field}},
      else: {:ok, keys}
  end

  defp predicates(tests) do
    Enum.reduce_while(tests, {:ok, []}, fn t, {:ok, acc} ->
      case predicate(t) do
        {:ok, f} -> {:cont, {:ok, [f | acc]}}
        {:error, r} -> {:halt, {:error, r}}
      end
    end)
  end

  defp predicate(%{"field" => f, "test" => "non_empty_list"}),
    do: {:ok, fn row -> is_list(Map.get(row, f)) and Map.get(row, f) != [] end}

  defp predicate(%{"field" => f, "test" => "not_null"}),
    do: {:ok, fn row -> Map.get(row, f) != nil end}

  defp predicate(other), do: {:error, {:unknown_selector_test, other}}

  @doc """
  **G15b** — the four counts the edges file declares about itself, against the
  four the generator derives.

  C1a read `the_population_this_file_declares` for its `rule` string alone and
  never checked a single one of its numbers against the derivation. Returns one
  row per disagreeing field; `[]` is agreement.

  This is a **weaker** check than G15a's set comparison and is kept beside it
  rather than instead of it: counts agreeing is not sets agreeing (a dropped
  row and an added one cancel), and sets agreeing is not the file's own
  arithmetic being honest (`members_with_edges` is not a set this module
  otherwise derives). Neither subsumes the other.
  """
  @spec declaration_mismatches(map(), map()) :: [map()]
  def declaration_mismatches(declared, derived) do
    ~w(members members_with_edges members_declared_unmatched checks_addressed)
    |> Enum.flat_map(fn field ->
      d = Map.get(declared, field)
      a = Map.get(derived, field)

      if d == a, do: [], else: [%{"field" => field, "declared" => d, "derived" => a}]
    end)
  end

  @doc """
  **G16** — two independently generated artefacts' per-check verdicts, compared
  as sets of keys **and** per key.

  A1's manifest and A5's bucket-0 artefact carry the same 175 six-field keys
  and each carries its own `status`, written by different generators at
  different tickets. Agreement between them is a **consistency** pin in exactly
  ruling 9's sense: it witnesses that nobody edited one without regenerating
  the other. It does **not** witness that either is right — both descend from
  the same accepted harness run, so a wrong run is wrong in both.

  Stated because the name would otherwise imply the stronger claim.
  """
  @spec status_agreement(map(), map()) :: map()
  def status_agreement(left, right) do
    keys = set_compare(Map.keys(left), Map.keys(right))

    shared = left |> Map.keys() |> Enum.filter(&Map.has_key?(right, &1)) |> Enum.sort()

    disagreements =
      shared
      |> Enum.filter(&(Map.fetch!(left, &1) != Map.fetch!(right, &1)))
      |> Enum.map(
        &%{"key" => &1, "left" => Map.fetch!(left, &1), "right" => Map.fetch!(right, &1)}
      )

    %{
      "compared" => length(shared),
      "key_sets" => %{"equal" => keys.equal, "missing" => keys.missing, "extra" => keys.extra},
      "disagreements" => disagreements,
      "agrees" => keys.equal and disagreements == [],
      "what_this_is" =>
        "A CONSISTENCY pin, not a correctness one (ruling 9). Both artefacts descend from the " <>
          "same accepted harness run: agreement witnesses that nobody edited one without " <>
          "regenerating the other, and a wrong run would be wrong in both."
    }
  end
end

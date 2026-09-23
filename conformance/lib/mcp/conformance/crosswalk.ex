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

  alias MCP.Conformance.CitationVerbatim
  alias MCP.Conformance.MatchKey

  @combinators ~w(any_of all_of none_of)

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

        # `Enum.uniq(named) -- known`, NOT `named -- known`. List subtraction
        # removes one occurrence per element, so a DUPLICATED axis always left a
        # residue and tripped `:axis_not_in_decomposition` first — which made
        # the `:axis_named_twice` clause below unreachable for every input, and
        # made the refusal name the wrong defect. Measured on MES-104 by a
        # control that asserts WHICH guard fires rather than that one did:
        # duplicating the first axis of the first edge reported
        # `{:axis_not_in_decomposition, ["retry_carries_the_request_state"], ...}`
        # over an axis that is plainly in the decomposition.
        unknown = Enum.uniq(named) -- known

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
  the world without a universe to take it in. A WORKED EXAMPLE, from C1a's
  slice and not a statement of the current population: had bucket 1 been taken
  over all 281 ET-CC members when only the 21 C1a adjudicated were in scope, it
  would have reported the other 260 as *"we looked and there is no
  counterpart"*, which was false of every one of them.
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

  ## The selector language — named, non-computing, and fail-closed

  Leaf **tests**: `non_empty_list`, `not_null`, `is_null`, `equals` (which
  takes a `value`). **Combinators**: `any_of`, `all_of`, `none_of`, each taking
  a non-empty list of nodes, and each node is itself a leaf or a combinator, so
  they nest.

  Deliberately named rather than a general expression language: a selector rich
  enough to compute is a selector rich enough to lie. It is fail-closed on an
  unknown `test`, on a node carrying more than one combinator, on an **empty**
  combinator list (a vacuous `all_of` is true of every row and a vacuous
  `any_of` is true of none — both are lies waiting to happen), on an absent
  `rows_at`, on a `key_field` a row does not carry, and on a source whose keys
  are not unique.

  `is_null` was **not** implemented until C1b-iii, on the stated ground that a
  selector test nothing calls is a guard on a dead path (S9-15). C1b-iii's own
  population — *the client members carrying no CG* — is the caller, so it
  arrives with the population that needs it and not before.

  It is `has_key?(row, f) and get(row, f) == nil`, **not** `get(row, f) == nil`,
  and the difference is the whole of its fail-closed behaviour. Under the
  weaker reading an **absent** field and a **null** one are the same thing, so
  a B2b schema change that dropped `cg` entirely would make the leaf denote
  **every row** and silently re-declare the population as all 281 — the
  artefact would still reconcile, over a universe nobody chose. Under the
  reading implemented here an absent field denotes **nothing**, the denotation
  collapses to the empty set, and G15a goes red naming every member of the file
  as `extra`. Measured at this tip: all 281 attribution rows carry the `cg`
  key, so the two readings are **indistinguishable on live data** and only a
  unit separates them. Both limbs are unit-tested, and the absent-field case is
  the one that would have been left out. It is the same refusal the `equals`
  leaf's own comment already makes, made positively.
  """
  @spec select(map(), map()) :: {:ok, [String.t()]} | {:error, term()}
  def select(%{"rows_at" => rows_at, "key_field" => key_field} = selector, src) do
    with {:ok, pred} <- root_predicate(selector),
         {:ok, rows} <- rows_at(src, rows_at),
         {:ok, keys} <- keys_of(rows, key_field, pred) do
      case (keys -- Enum.uniq(keys)) |> Enum.uniq() do
        [] -> {:ok, Enum.sort(keys)}
        dupes -> {:error, {:selector_source_has_duplicate_keys, dupes}}
      end
    end
  end

  def select(other, _src), do: {:error, {:malformed_selector, other}}

  @doc "The combinator names `select/2` accepts, in one place so a control can enumerate them."
  @spec combinators() :: [String.t()]
  def combinators, do: @combinators

  # The ROOT must be a combinator, and exactly one: a selector naming two would
  # otherwise be read as whichever clause matched first, which is a silent
  # choice between two different populations.
  defp root_predicate(selector) do
    case Enum.filter(@combinators, &Map.has_key?(selector, &1)) do
      [one] -> combinator(one, Map.fetch!(selector, one))
      [] -> {:error, {:selector_root_names_no_combinator, @combinators}}
      many -> {:error, {:selector_root_names_several_combinators, many}}
    end
  end

  defp rows_at(src, rows_at) do
    case Map.get(src, rows_at) do
      rows when is_list(rows) -> {:ok, rows}
      _ -> {:error, {:selector_names_no_such_rows, rows_at}}
    end
  end

  defp keys_of(rows, key_field, pred) do
    keys =
      rows
      |> Enum.filter(pred)
      |> Enum.map(&Map.get(&1, key_field))

    if Enum.any?(keys, &(not is_binary(&1))),
      do: {:error, {:selector_key_field_is_not_a_string, key_field}},
      else: {:ok, keys}
  end

  defp combinator(_name, []), do: {:error, :selector_combinator_is_empty}

  defp combinator(name, nodes) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn n, {:ok, acc} ->
      case predicate(n) do
        {:ok, f} -> {:cont, {:ok, [f | acc]}}
        {:error, r} -> {:halt, {:error, r}}
      end
    end)
    |> case do
      {:ok, preds} -> {:ok, apply_combinator(name, Enum.reverse(preds))}
      {:error, r} -> {:error, r}
    end
  end

  defp combinator(_name, other), do: {:error, {:selector_combinator_is_not_a_list, other}}

  defp apply_combinator("any_of", preds), do: fn row -> Enum.any?(preds, & &1.(row)) end
  defp apply_combinator("all_of", preds), do: fn row -> Enum.all?(preds, & &1.(row)) end
  defp apply_combinator("none_of", preds), do: fn row -> not Enum.any?(preds, & &1.(row)) end

  # A node is a combinator or a leaf, and the "exactly one combinator" rule
  # applies at every depth rather than only at the root.
  defp predicate(node) when is_map(node) do
    case Enum.filter(@combinators, &Map.has_key?(node, &1)) do
      [] -> leaf(node)
      [one] -> combinator(one, Map.fetch!(node, one))
      many -> {:error, {:selector_node_names_several_combinators, many}}
    end
  end

  defp predicate(other), do: {:error, {:selector_node_is_not_a_map, other}}

  defp leaf(%{"field" => f, "test" => "non_empty_list"}),
    do: {:ok, fn row -> is_list(Map.get(row, f)) and Map.get(row, f) != [] end}

  defp leaf(%{"field" => f, "test" => "not_null"}),
    do: {:ok, fn row -> Map.get(row, f) != nil end}

  # `has_key?` AND `== nil`, never `== nil` alone. An ABSENT field denotes
  # NOTHING here, and that is the fail-closed direction: a source that stopped
  # carrying the field would otherwise denote every row and re-declare the
  # population silently, whereas denoting nothing collapses the selector's
  # result to the empty set and G15a reds naming every member as `extra`.
  defp leaf(%{"field" => f, "test" => "is_null"}),
    do: {:ok, fn row -> Map.has_key?(row, f) and Map.get(row, f) == nil end}

  # `equals` compares to a STRING and refuses anything else. A test that could
  # compare to a list or a map would be comparing structures the anchor's
  # schema is free to change under it, and `nil == nil` would make an absent
  # field indistinguishable from a null one.
  defp leaf(%{"field" => f, "test" => "equals", "value" => v}) when is_binary(v),
    do: {:ok, fn row -> Map.get(row, f) == v end}

  defp leaf(other), do: {:error, {:unknown_selector_test, other}}

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

  # --- G21: the population statements this generator AUTHORS -----------------
  #
  # CR-1 on MES-104 found C1a's population written as hard-coded text in the
  # PROJECTOR and fixed it there, interpolating every figure and adding
  # `:population_statement`. The CROSSWALK GENERATOR's own statements got no
  # such guard, and one ticket later `trust_status` still read `48-member /
  # 29-declared-check` over a 68/39 population while the twelve views it is
  # projected into interpolated the right pair — CR-5 on MES-108, the same
  # defect in the one file the remedy did not reach.
  #
  # The three functions below are that guard's decision logic, here rather than
  # in the task so gate 5 covers them.
  #
  # THE UNIVERSE IS EXTERNAL, and that is the part that matters. A guard whose
  # population is a list the guarded module declares cannot see a statement
  # nobody added to the list. So the scan runs over the EMITTED ARTEFACT — every
  # string it actually ships — and a string is the generator's OWN iff it does
  # not occur in any input document. Prose copied out of an edges file is that
  # file's claim, checked by G15; prose the generator composed is this guard's.

  # The lookbehind is not decoration: without it `MES-108 moved the check
  # population` reads as a claim of 108 checks, and the guard would refuse its
  # own explanation of why it exists. Digits that continue an identifier are not
  # a figure; digits that begin a word are.
  @population_claim ~r/(?<![\w-])(\d+)[\s-](?:[A-Za-z][\w-]*[\s-]){0,2}?(?:members?|checks?)\b/

  @doc """
  Every `{path, string}` in a decoded JSON document, the path dotted and list
  indices bracketed.

  Public because it is how both the artefact and the inputs are enumerated, and
  a control that had to re-implement the walk would be attesting its own walk.
  """
  @spec strings_at(term()) :: [{String.t(), String.t()}]
  def strings_at(doc), do: doc |> collect([], []) |> Enum.sort()

  defp collect(node, path, acc) do
    case node do
      %{} = m ->
        Enum.reduce(m, acc, fn {k, v}, a -> collect(v, [to_string(k) | path], a) end)

      l when is_list(l) ->
        l
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {v, i}, a -> collect(v, ["[#{i}]" | path], a) end)

      s when is_binary(s) ->
        [{path |> Enum.reverse() |> Enum.join("."), s} | acc]

      _ ->
        acc
    end
  end

  @doc "Every distinct string appearing anywhere in `docs` — the authorship anchor."
  @spec string_set([term()]) :: MapSet.t(String.t())
  def string_set(docs) do
    docs
    |> Enum.flat_map(fn doc -> Enum.map(strings_at(doc), fn {_p, s} -> s end) end)
    |> MapSet.new()
  end

  @doc """
  **G30's windows for an edges-file record** — the ET line spans its `evidence`
  cites, and the OC byte spans the axis row for its `tag` addresses.

  This is the crosswalk-SPECIFIC half of the citation-verbatim guard.
  `MCP.Conformance.CitationVerbatim` owns the predicate and knows nothing about
  edges files or axis rows; this knows nothing about verbatim-ness. MES-113
  reuses the predicate over the attribution surface by writing its own window
  builder, not by generalising this one.

  `ctx` carries the axis check rows and, when `--harness` was given, the harness
  `build` and its squashed form (squashed ONCE, not per record — it is 800KB).
  With no build, an OC span cannot be read: the reason goes in `:unavailable`
  and the predicate turns an unplaced quote into a refusal that says "I could
  not tell" rather than into a pass.

  EACH SPAN IS ITS OWN WINDOW. A quote cannot be contiguous across two of them,
  which is what stops a citation borrowing bytes from a span it also names but
  that the quote does not sit in.

  `:broad` is the same sources with their addresses thrown away — the whole
  file, the whole build. The generator never asks for it; it exists so a control
  can drop the WINDOWING limb and measure what that limb is worth.
  """
  @spec citation_windows(map(), map()) ::
          CitationVerbatim.windows()
  def citation_windows(record, ctx) do
    citation_windows(record, ctx.axes, Map.get(ctx, :build), Map.get(ctx, :squashed_build))
  end

  defp citation_windows(record, axes, build, squashed_build) do
    evidence = record["evidence"] || ""
    et = et_windows(evidence)
    rows = axis_rows(record["tag"], axes)

    %{
      narrow: et.narrow ++ oc_windows(rows, build),
      broad: et.broad ++ oc_broad(rows, squashed_build),
      unavailable: oc_unavailable(rows, build)
    }
  end

  defp et_windows(evidence) do
    spans = CitationVerbatim.cited_line_spans(evidence)

    resolved =
      for {file, from, to} <- spans, path = find_source(file), reduce: {[], %{}} do
        {narrow, files} ->
          source = Map.get_lazy(files, path, fn -> File.read!(path) end)

          {[
             {"et:#{file}:#{from}-#{to}", CitationVerbatim.line_window(source, from, to)}
             | narrow
           ], Map.put(files, path, source)}
      end

    {narrow, files} = resolved

    %{
      narrow: Enum.reverse(narrow),
      broad:
        Enum.map(files, fn {path, src} ->
          {"et-file:#{path}", CitationVerbatim.squash(src)}
        end)
    }
  end

  defp find_source(basename) do
    ["test", "lib", "conformance"]
    |> Enum.flat_map(&Path.wildcard(Path.join([&1, "**", basename])))
    |> List.first()
  end

  defp axis_rows(nil, _axes), do: []

  defp axis_rows(tag, axes) do
    name = tag |> String.split("/") |> List.last()
    Enum.filter(axes, &(Enum.at(&1["key"], 3) == name))
  end

  defp oc_windows(_rows, nil), do: []

  defp oc_windows(rows, build) do
    for row <- rows, window <- oc_row_windows(row, build), do: window
  end

  defp oc_row_windows(row, build) do
    id = Enum.at(row["key"], 3)

    spans =
      [row["emitting_byte_span"], get_in(row, ["emitting_site", "dist_byte_span"])] ++
        Enum.map(row["context_excerpts"] || [], & &1["byte_span"])

    byte_windows =
      for [a, b] <- Enum.reject(spans, &is_nil/1),
          do: {"oc:#{id}:#{a}-#{b}", CitationVerbatim.squash(binary_part(build, a, b - a))}

    case row["evaluator_excerpt"] do
      nil ->
        byte_windows

      x ->
        byte_windows ++
          [{"oc:#{id}:evaluator_excerpt", CitationVerbatim.squash(x)}]
    end
  end

  defp oc_broad([], _squashed), do: []
  defp oc_broad(_rows, nil), do: []
  defp oc_broad(_rows, squashed), do: [{"oc-build", squashed}]

  defp oc_unavailable([], _build), do: []
  defp oc_unavailable(_rows, build) when is_binary(build), do: []

  defp oc_unavailable(_rows, nil),
    do: ["--harness was not given, so this row's OC byte spans could not be read"]

  @doc """
  Every population figure `text` states, as `{figure, the phrase it sits in}`.

  A figure is DIGITS followed, within two words, by `member(s)` or `check(s)`.

  WHAT IT CANNOT SEE, stated rather than implied, because a guard that hides its
  blind spots is worse than one that has none: a figure spelled as a word
  (`C1b-i found five`), and a figure stated without its noun (`the member
  population is 48 across two edges files`, `never all 281`). Both occur in this
  generator's prose. They are handled by interpolating them anyway, not by the
  scan — so the scan is the backstop for what is added NEXT, and the
  interpolation is what makes today's text right.
  """
  @spec population_claims(String.t()) :: [{integer(), String.t()}]
  def population_claims(text) do
    @population_claim
    |> Regex.scan(text)
    |> Enum.map(fn [whole, n | _] -> {String.to_integer(n), whole} end)
  end

  @doc "The regex, so a control can show the scan's reach without restating it."
  @spec population_claim_regex() :: Regex.t()
  def population_claim_regex, do: @population_claim

  @doc """
  Every claim-bearing string the `artefact` ships that the generator AUTHORED —
  i.e. that is not one of `input_strings`.

  Returns `{path, text, claims}`.
  """
  @spec authored_statements(term(), MapSet.t(String.t())) ::
          [{String.t(), String.t(), [{integer(), String.t()}]}]
  def authored_statements(artefact, input_strings) do
    for {path, text} <- strings_at(artefact),
        not MapSet.member?(input_strings, text),
        claims = population_claims(text),
        claims != [],
        do: {path, text, claims}
  end

  @doc """
  Every figure an authored statement states that is **not** one the crosswalk
  holds.

  `held` is the set of the run's own derived figures. This is the limb that goes
  RED AGAINST THE TREE: a literal that was right when it was written stops being
  a figure the crosswalk holds the moment the population moves, which is exactly
  CR-5's recurrence and exactly when it must fail.

  What it does **not** establish: that a figure IS interpolated. A literal that
  coincides with some other held figure survives until the population moves —
  `addressed_not_declared` was 14 here, so a stale `14 checks` would have passed
  this limb on the day it was measured. The phrase pin below is what catches a
  held-but-wrong figure in a statement whose wording is load-bearing.
  """
  @spec unheld_figures([{String.t(), String.t(), [{integer(), String.t()}]}], MapSet.t(integer())) ::
          [{String.t(), integer(), String.t()}]
  def unheld_figures(statements, held) do
    for {path, _text, claims} <- statements,
        {figure, phrase} <- claims,
        not MapSet.member?(held, figure),
        do: {path, figure, phrase}
  end

  @doc """
  **G23** — what an `absence_searches` registry entry must hold to stand behind
  a bucket-1 row, returned as the list of ways this one does not.

  `tag` is the row's own `oc:none/<reason>/<native-id>` token; the entry's
  `kind` must equal that reason slug. A4 defines two — `no-oc-scenario` (the
  suite has no such check anywhere) and `no-oc-fixture-case` (the scenario
  exists and is matched, but its fixture holds no case exercising the
  constraint) — and citing a fixture-case search from a scenario-slug row is
  the one way the two quietly merge. Keeping them apart is the whole reason
  there are two.

  The rest is what makes a recorded zero a MEASUREMENT rather than a silence:
  `hits: 0` (an entry is by definition a search that found none), a population
  to have looked in, a runnable `pattern`, the `subject` searched for, at least
  one positive control so the sweep can be shown to have reached the
  population, and the near miss — because a zero with the near miss named is a
  search and a bare zero is a grep a later reader will re-run, find the word,
  and mistrust.

  Here rather than in the task so gate 5 covers it, the same reason G21's three
  functions are.
  """
  @spec absence_entry_problems(String.t() | nil, String.t(), map()) :: [tuple()]
  def absence_entry_problems(tag, id, entry), do: absence_entry_problems(tag, id, entry, %{})

  @doc """
  As `absence_entry_problems/3`, plus the ONE-FACT-ONE-HOME check between the
  entry and the `row` that names it.

  A bucket-1 row carries the search's subject and its near miss in prose,
  because that prose is what a reviewer reads and sending them to a registry
  id to find it would be worse. But a copy is a second home (D4), and two
  copies can disagree with nothing noticing — MES-109 edited three near misses
  after measuring them and had to edit each in two places. So where the row
  carries a copy it is required to be the entry's, character for character.
  A row carrying neither field is unaffected; this is not a demand that every
  row copy them.
  """
  @spec absence_entry_problems(String.t() | nil, String.t(), map(), map()) :: [tuple()]
  def absence_entry_problems(tag, id, entry, row) do
    copies =
      for {row_field, entry_field} <- [
            {"the_search_that_found_none", "subject"},
            {"the_near_miss_that_is_not_a_counterpart", "near_miss"}
          ],
          copy = Map.get(row, row_field),
          is_binary(copy),
          copy != Map.get(entry, entry_field),
          do: {:row_copy_has_drifted_from_the_entry, id, row_field}

    base_entry_problems(tag, id, entry) ++ copies
  end

  defp base_entry_problems(tag, id, entry) do
    slug =
      case String.split(tag || "", "/") do
        ["oc:none", reason | _] -> reason
        _ -> nil
      end

    [
      {entry["hits"] == 0, {:entry_does_not_record_zero, id, entry["hits"]}},
      {is_map(entry["population"]), {:entry_names_no_population, id}},
      {non_empty?(entry["pattern"]), {:entry_has_no_pattern, id}},
      {non_empty?(entry["subject"]), {:entry_has_no_subject, id}},
      {non_empty?(entry["near_miss"]), {:entry_names_no_near_miss, id}},
      {entry["positive_controls"] not in [nil, []], {:entry_has_no_positive_control, id}},
      {entry["kind"] == slug, {:entry_kind_is_not_the_rows_reason_slug, id, entry["kind"], slug}}
    ]
    |> Enum.reject(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp non_empty?(v), do: is_binary(v) and v != ""

  @doc """
  Every `{path, phrase}` in `required` whose phrase is absent from the statement
  at that path in `artefact`.

  The phrases are built by the CALLER from the run's figures, independently of
  the templates that produced the text, so the two have to be edited together —
  a consistency pin (ruling 9), not a proof that either wording is right. It
  catches the interpolation of the WRONG held figure, which `unheld_figures/2`
  cannot see.
  """
  @spec missing_phrases(term(), [{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def missing_phrases(artefact, required) do
    at = Map.new(strings_at(artefact))

    # `Enum.filter` and not a comprehension: `for ..., text = Map.get(at, path)`
    # reads as a binding and behaves as a TRUTHINESS FILTER, so an ABSENT
    # statement — the fail-closed case this exists for — was silently dropped
    # instead of reported. Caught by the unit that drives the absent case, which
    # is the argument for writing that unit at all.
    Enum.filter(required, fn {path, phrase} ->
      case Map.get(at, path) do
        nil -> true
        text -> not String.contains?(text, phrase)
      end
    end)
  end
end

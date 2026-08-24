defmodule MCP.Conformance.MatchKey do
  @moduledoc """
  The **form** of the ET-CC × OC match relation, ratified on MES-68 (A3):
  the token that names an OC check from an ExUnit test name, the four-state
  guard over that token, the edge record C1 will populate, and the bucket
  function that reads an edge.

  This module **emits no edges**. A3 defines the form; C1 records the edges;
  B4 tags membership only (PM amendment 2). Two tickets owning one artefact is
  the MES-24 two-censuses defect, and when they disagree nothing detects it.

  The prose companion — axis model, worked cases, residuals — is
  `docs/conformance/match-relation.md`. It is the file, not this moduledoc,
  that C1 is meant to read.

  ## What the token is, and what it deliberately is not

      oc:<leg>/<scenario>/<check_id>/<name>[#<discriminator>]
      oc:none/<reason-slug>/<native-id>

  The first form carries **five** of A1's six key fields. The sixth is
  `description`, a sentence, and it cannot live in a test name. So the claim
  this module makes is that a token is **reversible THROUGH A1's manifest, not
  lexically**: `encode/1` is an injection into the frozen 175 and `decode/1`
  plus `resolve/2` is its inverse, a lookup. Anything stronger would be a
  property the artefact does not have.

  Neither field of the pair `{check_id, name}` works alone, and each fails on a
  different leg — which is why either alone reads as adequate to someone
  looking at one leg. Measured over all 175 rows at `891300b`, counting **rows
  lost** (rows that disappear when the projection is deduplicated), not rows
  involved:

      (leg, scenario, name, discriminator)        2 rows lost  (RequestMetaInvalid x3)
      check_id alone, client leg                 29 rows lost  in 7 groups
      check_id alone, server leg                 35 rows lost  in 2 groups
      (scenario, check_id, name, discriminator)   0 rows lost  <- what the token carries

  ## The `oc:none` form exists so that silence cannot encode a decision

  A bucket-1 member — ET-CC with no OC counterpart — has no OC key to be named
  by. If it were simply left untagged, *"nobody has adjudicated this yet"* and
  *"we looked and there is no counterpart"* would be the same state, and a
  register in which those are indistinguishable cannot report bucket 1 at all.
  `none` is safe to reserve as a leg because the leg vocabulary is
  measured-exhaustive at `{"server", "client"}` over all 175 rows.

  `guard_state/2` therefore separates four states **lexically, before any
  lookup**, so that a stale key and a declared non-match fail differently and
  for stated reasons rather than both arriving as "not found".

  ## The native-id slot names a CLAIM, not a requirement heading (MES-77)

  A3 first said A4's `CG` numbers land in the `<native-id>` slot as they stand.
  That is a two-way split over a three-way space, and it inherits the
  assumption §1 rejects — that a CG is a unit of matching. A requirement
  heading can be **matched and bucket-1 at the same time**: CG7 corresponds to
  29 OC checks *and* carries 3 constraint families the suite's fixture never
  exercises. A slot holding `CG7` names all three at once, so a register keyed
  on it cannot tell them apart.

  So the slot carries `<origin-id>-<claim-slug>` — `native_id/2` builds it,
  `none/3` composes the whole token, and `declared_claim_index/1` is the
  register-assembly check that refuses one id naming two claims. `none/2`
  keeps its open contract: it cannot know the caller's taxonomy, and some
  taxonomies are already claim-level.

  A requirement with **no ET-CC member at all** is a third thing again, and it
  is out of this module's domain by rule rather than by omission — see
  `docs/conformance/match-relation.md` §6.

  ## What a green run of this module does NOT establish

  It establishes that a token addresses at most one row of the **committed**
  manifest. It says nothing about whether the test so named asserts the same
  required behaviour as the check — that is the semantic-sameness residual,
  which escalates to the PM per case, and no code here can decide it.
  """

  @typedoc "A1's six-field check key, in `key_fields/0` order."
  @type oc_key :: [String.t()]

  @typedoc "A decoded token."
  @type decoded ::
          %{
            kind: :oc,
            leg: String.t(),
            scenario: String.t(),
            check_id: String.t(),
            name: String.t(),
            discriminator: String.t()
          }
          | %{kind: :none, reason: String.t(), native_id: String.t()}

  @typedoc "One axis of an OC check's predicate, and how the ET claim stands to it."
  @type axis :: %{axis: String.t(), verdict: :agrees | :contradicts | :silent}

  @typedoc "A match edge. `member` is MES-67's ET-CC member; `claim` is the atom of matching."
  @type edge :: %{
          member: %{module: String.t(), test: String.t()},
          claim: String.t(),
          oc_key: oc_key(),
          tag: String.t(),
          verdicts: %{oc: :green | :red, et: :green | :red},
          axes: [axis()],
          shape: :full | :partial | :contradicting
        }

  # A1's key, in the order the manifest writes it.
  @key_fields ~w(leg scenario check_id name description discriminator)

  # The five a test name can carry. `description` is the omission and it is the
  # whole reason reversibility is claimed through A1 rather than lexically.
  @carried_fields ~w(leg scenario check_id name discriminator)

  # Measured over all 175 rows of the frozen manifest: every carried field draws
  # only on this charset — no slash, hash, whitespace or bracket — so the token
  # parses unambiguously. `encode/1` REFUSES rather than emitting an ambiguous
  # token if a future harness breaks it (A1 residual R3).
  @carried_charset ~r/\A[A-Za-z0-9_-]*\z/

  # The leg vocabulary, measured-exhaustive over the same 175 rows. This is what
  # makes `none` safe to reserve.
  @legs ~w(server client)

  @axis_verdicts [:agrees, :contradicts, :silent]
  @run_verdicts [:green, :red]

  # The edge-shape vocabulary, in `shape_from_axes/1`'s own precedence order.
  # It exists as an attribute so `bucket/1`'s domain can be READ rather than
  # restated — see `edge_shapes/0`.
  @edge_shapes [:contradicting, :partial, :full]

  @doc "A1's six key fields, in manifest order."
  @spec key_fields() :: [String.t()]
  def key_fields, do: @key_fields

  @doc "The five fields a token carries. `description` is not among them, by necessity."
  @spec carried_fields() :: [String.t()]
  def carried_fields, do: @carried_fields

  @doc "The measured-exhaustive leg vocabulary. `none` is reserved against it."
  @spec legs() :: [String.t()]
  def legs, do: @legs

  @doc """
  The run-verdict vocabulary — one component of `bucket/1`'s domain.

  Exposed so a test can enumerate that domain instead of restating it
  (MES-76). A hand-written `[:green, :red]` in a test is a literal that can
  drift from this module without anything noticing; a read cannot.
  """
  @spec run_verdicts() :: [atom()]
  def run_verdicts, do: @run_verdicts

  @doc """
  The edge-shape vocabulary, in `shape_from_axes/1`'s precedence order — the
  other component of `bucket/1`'s domain. Exposed for the same reason as
  `run_verdicts/0`.
  """
  @spec edge_shapes() :: [atom()]
  def edge_shapes, do: @edge_shapes

  @doc """
  Encode an A1 key as a token.

  Takes the six-field key as a list (manifest order) or a map keyed by the field
  names. Returns `{:error, {:charset, field}}` rather than an ambiguous token if
  any carried field steps outside `#{inspect(Regex.source(@carried_charset))}`,
  and `{:error, {:empty, field}}` if a field that must be non-empty is blank.
  `discriminator` is the one carried field allowed to be empty — 172 of the 175
  rows have no discriminator.
  """
  @spec encode(oc_key() | map()) :: {:ok, String.t()} | {:error, term()}
  def encode(key) when is_list(key) and length(key) == 6 do
    @key_fields |> Enum.zip(key) |> Map.new() |> encode()
  end

  def encode(%{} = key) do
    with {:ok, fields} <- fetch_carried(key),
         :ok <- check_charset(fields),
         :ok <- check_non_empty(fields),
         :ok <- check_leg(fields["leg"]) do
      {:ok, render(fields)}
    end
  end

  def encode(other), do: {:error, {:not_a_key, other}}

  @doc "Encode, or raise. For call sites where a refusal is a defect in the caller."
  @spec encode!(oc_key() | map()) :: String.t()
  def encode!(key) do
    case encode(key) do
      {:ok, token} -> token
      {:error, reason} -> raise ArgumentError, "cannot encode #{inspect(key)}: #{inspect(reason)}"
    end
  end

  @doc """
  Build the reserved token for an ET-CC member that has no OC counterpart.

  `reason` is a slug saying *why* there is no counterpart; `native_id` is the
  member's own identifier in whatever private taxonomy already names it.

  **`native_id` must name a claim, not a requirement heading** (MES-77) — but
  that is NOT enforced here, and the omission is deliberate. This arity cannot
  know the caller's taxonomy: a unit-level id like `T-CG1a` is already
  claim-level and has no heading part to suffix, so refusing an unsuffixed id
  here would produce false refusals rather than safety. The enforcement points
  are `native_id/2` at build time and `declared_claim_index/1` at register
  assembly. `none/3` is the sanctioned builder.
  """
  @spec none(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def none(reason, native_id) do
    fields = %{"reason" => reason, "native_id" => native_id}

    with :ok <- check_charset(fields),
         :ok <- check_non_empty(fields) do
      {:ok, "oc:none/#{reason}/#{native_id}"}
    end
  end

  @doc """
  Build the reserved token from its three parts — the sanctioned builder
  (MES-77). Composes `native_id/2`, so a heading-only native id cannot be
  produced through this call.
  """
  @spec none(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def none(reason, origin_id, claim_slug) do
    with {:ok, native_id} <- native_id(origin_id, claim_slug) do
      none(reason, native_id)
    end
  end

  @doc """
  Compose a **claim-level** native id: the scope that names the claim, and the
  claim within it.

      native_id("CG7", "annotated-number-excluded")
      #=> {:ok, "CG7-annotated-number-excluded"}

  `origin_id` is whatever private taxonomy already names the scope — a `CG`
  number where one exists, a ticket key where none does. Both parts must be
  non-empty and stay inside the measured carried charset, so a `/` or `#` is
  **refused** rather than emitted as a token `decode/1` would mis-split.

  **The result is deliberately NOT lexically decomposable back into its two
  parts.** Reserving the first `-` as a separator would require origin ids to
  contain none, which holds for `CG1`-`CG7` and fails for every Jira key — and
  a bucket-1 claim belonging to no CG has a ticket key as its natural origin.
  Rollup from a native id to its origin is therefore a lookup in D1's register,
  not a parse, exactly the stance §5 already takes on `description`. Stating
  the weaker property is the point: claiming a decomposability that would break
  within the sprint would be worse than not claiming it.
  """
  @spec native_id(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def native_id(origin_id, claim_slug) do
    fields = %{"origin_id" => origin_id, "claim_slug" => claim_slug}

    with :ok <- check_charset(fields),
         :ok <- check_non_empty(fields) do
      {:ok, "#{origin_id}-#{claim_slug}"}
    end
  end

  @doc """
  Index declared bucket-1 rows by native id, refusing the one thing the slot
  exists to prevent: **one native id naming two different claims** (MES-77,
  gap (a)). This is what a register builder calls before counting.

  Takes `[{native_id, claim}]` — `claim` being the field an edge record already
  carries — and returns `{:ok, %{native_id => claim}}`.

  **Repeats of one id with the SAME claim are legal, and that is not a
  leniency.** A claim can be asserted by several members: CG7's three
  constraint families are discharged by nine ET-CC units, so **nine members
  legitimately share three native ids**. A rule of the form "no two members
  share an id" would reject correct data — the same category error this
  mechanism exists to fix, one level down. The enforceable converse is what
  this checks, and it returns
  `{:error, {:native_id_names_two_claims, id, claims}}`.

  The offender reported is the lexically first, so a refusal is reproducible
  rather than dependent on map ordering.
  """
  @spec declared_claim_index([{String.t(), String.t()}]) :: {:ok, map()} | {:error, term()}
  def declared_claim_index(rows) when is_list(rows) do
    with :ok <- check_rows(rows) do
      grouped =
        Enum.reduce(rows, %{}, fn {native_id, claim}, acc ->
          Map.update(acc, native_id, [claim], &[claim | &1])
        end)

      conflicts =
        grouped
        |> Enum.map(fn {id, claims} -> {id, claims |> Enum.uniq() |> Enum.sort()} end)
        |> Enum.filter(fn {_id, claims} -> length(claims) > 1 end)
        |> Enum.sort_by(fn {id, _claims} -> id end)

      case conflicts do
        [] -> {:ok, Map.new(grouped, fn {id, [claim | _]} -> {id, claim} end)}
        [{id, claims} | _] -> {:error, {:native_id_names_two_claims, id, claims}}
      end
    end
  end

  def declared_claim_index(other), do: {:error, {:not_a_row_list, other}}

  @doc """
  Decode a token into its parts. Purely lexical: it performs no lookup, so a
  well-formed token for a check that does not exist decodes cleanly and is
  refused later, by `resolve/2`. Keeping the two steps apart is what lets
  `guard_state/2` tell a typo from a declared non-match.

  ## The trailing `#` is refused, because the token must be injective (MES-76)

  `render/1` emits the `#` form **only** for a non-empty discriminator, so
  `"…/Name#"` is unreachable from `encode/1`. Before MES-76 it nonetheless
  decoded, and to a map **byte-identical** to the one `"…/Name"` produces:
  two token strings, one decoded value, and only one of the two emittable.
  That is a failure of injectivity, not a cosmetic second spelling, and it is
  what makes it a defect — a relation that silently accepts a string its own
  encoder cannot produce has no basis for saying which of the two is the key.

  `validate_edge/1` already caught it on a *stored* edge, as
  `:derived_field_mismatch`. `guard_state/2` did not, and that is the path
  Sprint 7's drift guard travels: measured at `18df3a6` against the real 175
  manifest rows, `guard_state("oc:server/caching/…/ToolsListCachingHints#",
  rows)` returned `{:matched, key}` — the same `{:matched, key}` as the
  well-formed token. It is now `{:error, {:malformed, :empty_discriminator}}`.

  Refusing it costs nothing, and that is measured rather than assumed: all 175
  legitimate tokens still round-trip.
  """
  @spec decode(String.t()) :: {:ok, decoded()} | {:error, term()}
  def decode("oc:" <> body) when byte_size(body) > 0 do
    case String.split(body, "/") do
      ["none", reason, native_id] ->
        decode_none(reason, native_id)

      [leg, scenario, check_id, tail] ->
        decode_oc(leg, scenario, check_id, tail)

      segments ->
        {:error, {:bad_segment_count, length(segments)}}
    end
  end

  def decode(token) when is_binary(token), do: {:error, :missing_prefix}
  def decode(other), do: {:error, {:not_a_token, other}}

  @doc """
  Resolve a decoded `:oc` token against A1's manifest rows.

  This is the half of reversibility the token cannot carry itself. `rows` is a
  list of six-field keys — `rows_from_manifest/1` extracts them from the decoded
  JSON.

  Returns `{:error, :ambiguous}` if more than one row answers to the token.
  That cannot happen on the frozen 175 and the test proves it; it is here
  because a relation whose failure mode is *silently returning the wrong row*
  is worse than one that refuses.
  """
  @spec resolve(map() | String.t(), [oc_key()]) :: {:ok, oc_key()} | {:error, term()}
  def resolve(token, rows) when is_binary(token) do
    with {:ok, decoded} <- decode(token), do: resolve(decoded, rows)
  end

  def resolve(%{kind: :none}, _rows), do: {:error, :not_an_oc_key}

  def resolve(%{kind: :oc} = decoded, rows) when is_list(rows) do
    case Enum.filter(rows, &row_matches?(&1, decoded)) do
      [row] -> {:ok, row}
      [] -> {:error, :unresolved}
      many -> {:error, {:ambiguous, length(many)}}
    end
  end

  @doc "Pull the six-field keys out of A1's decoded manifest."
  @spec rows_from_manifest(map()) :: [oc_key()]
  def rows_from_manifest(%{"scenarios" => scenarios}) do
    Enum.flat_map(scenarios, fn scenario ->
      Enum.map(scenario["checks"], & &1["key"])
    end)
  end

  @doc """
  The four-state guard, decided **lexically before any lookup**.

  `tag` is the `oc:`-token carried by an ET-CC member, or `nil` when the member
  carries none.

  | returns | means |
  | --- | --- |
  | `{:matched, key}` | state 1 — an OC token that resolves |
  | `{:error, {:unresolved, decoded}}` | state 2 — a typo, or a key gone stale against a harness bump. **FAILS.** |
  | `{:declared_unmatched, info}` | state 3 — a declared bucket-1 member |
  | `{:error, :untagged}` | state 4 — nobody has adjudicated this member. **FAILS.** |

  State 4 failing is the part with a cost: the Sprint 7 drift guard blocks on
  any ET-CC member nobody has adjudicated. That is the cost of not letting
  silence encode a decision, and it was ratified with the cost named.
  """
  @spec guard_state(String.t() | nil, [oc_key()]) ::
          {:matched, oc_key()} | {:declared_unmatched, map()} | {:error, term()}
  def guard_state(nil, _rows), do: {:error, :untagged}

  def guard_state(tag, rows) when is_binary(tag) do
    case decode(tag) do
      {:ok, %{kind: :none} = info} ->
        {:declared_unmatched, info}

      {:ok, %{kind: :oc} = decoded} ->
        case resolve(decoded, rows) do
          {:ok, key} -> {:matched, key}
          {:error, reason} -> {:error, {reason, decoded}}
        end

      {:error, reason} ->
        {:error, {:malformed, reason}}
    end
  end

  @doc """
  The edge shape, from the per-axis verdicts, in **stated precedence**:
  contradicts beats silent.

      any axis contradicts  -> :contradicting
      else any axis silent  -> :partial
      else                  -> :full

  The precedence is what makes buckets 4a and 4b exclusive *by construction*
  rather than by adjudication. Without it the `:83` `initialize` edge — which
  contradicts on the code axis **and** is silent on the status axis — could be
  filed either way depending on which axis an implementation happened to test
  first, and the epic's own worked 4a example would land in 4b.
  """
  @spec shape_from_axes([axis()]) :: {:ok, :full | :partial | :contradicting} | {:error, term()}
  def shape_from_axes([]), do: {:error, :no_axes}

  def shape_from_axes(axes) when is_list(axes) do
    verdicts = Enum.map(axes, & &1.verdict)

    cond do
      Enum.any?(verdicts, &(&1 not in @axis_verdicts)) -> {:error, :bad_axis_verdict}
      :contradicts in verdicts -> {:ok, :contradicting}
      :silent in verdicts -> {:ok, :partial}
      true -> {:ok, :full}
    end
  end

  @doc """
  Build a match edge. The edge is the unit of the relation: one **claim** within
  one ET-CC member, against one OC check.

  A member carrying several claims contributes several edges, and edges are
  never collapsed — that is what keeps the three verdicts of the `:83` case
  from merging into one.

  `shape` is derived here rather than accepted from the caller, so an edge
  cannot carry a shape its own axes contradict.
  """
  @spec new_edge(map()) :: {:ok, edge()} | {:error, term()}
  def new_edge(%{member: member, claim: claim, oc_key: oc_key, verdicts: verdicts, axes: axes}) do
    with :ok <- check_member(member),
         :ok <- check_claim(claim),
         :ok <- check_verdicts(verdicts),
         {:ok, tag} <- encode(oc_key),
         {:ok, shape} <- shape_from_axes(axes) do
      {:ok,
       %{
         member: member,
         claim: claim,
         oc_key: oc_key,
         tag: tag,
         verdicts: verdicts,
         axes: axes,
         shape: shape
       }}
    end
  end

  def new_edge(other), do: {:error, {:missing_fields, other}}

  @doc """
  Re-validate an edge that has been round-tripped through storage. C1 writes
  edges as data; this is what a reader checks them with before counting them.
  """
  @spec validate_edge(map()) :: :ok | {:error, term()}
  def validate_edge(%{shape: shape, axes: axes, oc_key: oc_key, tag: tag} = edge) do
    with :ok <- check_member(Map.get(edge, :member)),
         :ok <- check_claim(Map.get(edge, :claim)),
         :ok <- check_verdicts(Map.get(edge, :verdicts)),
         {:ok, ^shape} <- shape_from_axes(axes),
         {:ok, ^tag} <- encode(oc_key) do
      :ok
    else
      {:ok, other} -> {:error, {:derived_field_mismatch, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_edge(other), do: {:error, {:missing_fields, other}}

  @doc """
  `bucket = f(verdict pair, edge shape)` — MES-65's bucket for one edge.

  The verdict pair alone cannot decide it: **4a and 4b share the pair**
  (red OC / green ET-CC), differing only in mechanism — contradiction versus
  incompleteness — and the shape is what witnesses the difference.

  Returns `{:ok, bucket, attributes}`, or `{:escalate, reason}` for the one
  combination that should not be able to occur.

  | pair (oc, et) | shape | bucket |
  | --- | --- | --- |
  | red, green | `:contradicting` | `"4a"` |
  | red, green | `:partial` | `"4b"` |
  | red, green | `:full` | **escalates** — `:divergent_despite_agreement`, no bucket |
  | green, green | `:partial` | `"5"` + `:partial` (the vacuity sub-count) |
  | green, green | `:contradicting` | **escalates** — see below |
  | green, green | `:full` | `"5"` |
  | green, red | any | `"3"` |
  | red, red | any | `"6"` |

  Buckets 0, 1 and 2 are not decidable from an edge and are not returned here:
  bucket 1 is an ET-CC member with **no** edge, bucket 2 an OC check with no
  edge, and bucket 0 is A5's out-of-denominator set. All three are complements
  over the whole edge set, which is C1's to compute.

  **The two escalations, and why they are escalations rather than buckets.**

  `{:red, :green}` with a `:full` edge says our claim agrees with the check on
  every axis, our test passes, and the harness still fails the SDK. Nothing is
  contradicted and nothing is silent, so the test cannot be exercising the
  behaviour the check exercises — that is a coverage defect of a different kind
  and it is D4b's to disposition, but it is flagged rather than counted
  silently. This case was implicit in the ratified table and is made explicit
  here.

  `{:green, :green}` with a `:contradicting` edge is stronger: our claim
  contradicts the check on some axis, yet both passed. Against one build that
  is impossible, so the input is wrong — mismatched provenance, or a
  mis-recorded axis — and bucketing it would launder a data defect into a
  finding.
  """
  @spec bucket(edge() | map()) :: {:ok, String.t(), [atom()]} | {:escalate, term()}
  def bucket(%{verdicts: %{oc: oc, et: et}, shape: shape}), do: bucket(oc, et, shape)
  def bucket(other), do: {:escalate, {:not_an_edge, other}}

  defp bucket(:red, :green, :contradicting), do: {:ok, "4a", []}
  defp bucket(:red, :green, :partial), do: {:ok, "4b", []}
  defp bucket(:red, :green, :full), do: {:escalate, :divergent_despite_agreement}
  defp bucket(:green, :green, :contradicting), do: {:escalate, :inconsistent_verdict_pair}
  defp bucket(:green, :green, :partial), do: {:ok, "5", [:partial]}
  defp bucket(:green, :green, :full), do: {:ok, "5", []}
  defp bucket(:green, :red, _shape), do: {:ok, "3", []}
  defp bucket(:red, :red, _shape), do: {:ok, "6", []}
  defp bucket(oc, et, shape), do: {:escalate, {:undecidable, oc, et, shape}}

  # --- internals ---

  defp decode_none(reason, native_id) do
    fields = %{"reason" => reason, "native_id" => native_id}

    with :ok <- check_charset(fields),
         :ok <- check_non_empty(fields) do
      {:ok, %{kind: :none, reason: reason, native_id: native_id}}
    end
  end

  defp decode_oc(leg, scenario, check_id, tail) do
    {name, discriminator} =
      case String.split(tail, "#") do
        [name] -> {name, ""}
        [name, ""] -> {name, :empty}
        [name, discriminator] -> {name, discriminator}
        _many -> {tail, nil}
      end

    fields = %{
      "leg" => leg,
      "scenario" => scenario,
      "check_id" => check_id,
      "name" => name,
      "discriminator" => discriminator
    }

    with :ok <- check_discriminator(discriminator),
         :ok <- check_charset(fields),
         :ok <- check_non_empty(fields),
         :ok <- check_leg(leg) do
      {:ok,
       %{
         kind: :oc,
         leg: leg,
         scenario: scenario,
         check_id: check_id,
         name: name,
         discriminator: discriminator
       }}
    end
  end

  # Two sentinels, both standing for "the split produced something no token
  # should carry", refused before any other check so the reason is the lexical
  # one rather than a downstream charset complaint.
  defp check_discriminator(nil), do: {:error, :multiple_discriminators}
  defp check_discriminator(:empty), do: {:error, :empty_discriminator}
  defp check_discriminator(_), do: :ok

  defp fetch_carried(key) do
    missing = Enum.reject(@carried_fields, &Map.has_key?(key, &1))

    if missing == [],
      do: {:ok, Map.take(key, @carried_fields)},
      else: {:error, {:missing_fields, missing}}
  end

  defp check_charset(fields) do
    Enum.find_value(fields, :ok, fn {field, value} ->
      cond do
        not is_binary(value) -> {:error, {:not_a_string, field}}
        Regex.match?(@carried_charset, value) -> nil
        true -> {:error, {:charset, field}}
      end
    end)
  end

  # `discriminator` is the one field allowed to be empty: 172 of the 175 rows
  # carry no discriminator at all, so an empty one is the common case, not a
  # defect.
  defp check_non_empty(fields) do
    Enum.find_value(fields, :ok, fn {field, value} ->
      if field != "discriminator" and value == "", do: {:error, {:empty, field}}
    end)
  end

  defp check_rows(rows) do
    Enum.find_value(rows, :ok, fn
      {id, claim} when is_binary(id) and is_binary(claim) and id != "" and claim != "" -> nil
      other -> {:error, {:bad_row, other}}
    end)
  end

  defp check_leg(leg) when leg in @legs, do: :ok
  defp check_leg(leg), do: {:error, {:unknown_leg, leg}}

  defp check_member(%{module: module, test: test})
       when is_binary(module) and is_binary(test) and module != "" and test != "",
       do: :ok

  defp check_member(other), do: {:error, {:bad_member, other}}

  defp check_claim(claim) when is_binary(claim) and claim != "", do: :ok
  defp check_claim(other), do: {:error, {:bad_claim, other}}

  defp check_verdicts(%{oc: oc, et: et}) when oc in @run_verdicts and et in @run_verdicts, do: :ok
  defp check_verdicts(other), do: {:error, {:bad_verdicts, other}}

  defp render(fields) do
    base =
      "oc:#{fields["leg"]}/#{fields["scenario"]}/#{fields["check_id"]}/#{fields["name"]}"

    case fields["discriminator"] do
      "" -> base
      discriminator -> base <> "#" <> discriminator
    end
  end

  defp row_matches?(row, decoded) when is_list(row) and length(row) == 6 do
    fields = @key_fields |> Enum.zip(row) |> Map.new()

    fields["leg"] == decoded.leg and fields["scenario"] == decoded.scenario and
      fields["check_id"] == decoded.check_id and fields["name"] == decoded.name and
      fields["discriminator"] == decoded.discriminator
  end

  defp row_matches?(_row, _decoded), do: false
end

defmodule MCP.Conformance.Locator do
  @moduledoc """
  `check_id -> emitting site -> excerpt` over the harness `dist/index.js`, as a
  re-runnable artefact rather than a procedure a reader executes by hand.

  MES-76 recorded the procedure (`oc-axes-2026-07-28.json`
  `provenance.reverse_lookup_procedure`) and A3 hand-cut **13** rows with it.
  C1 (MES-97) makes it mechanical over **all 173** in-denominator rows, because
  C1b/C1c will need a site for every check they adjudicate and a hand traversal
  per check does not scale to 173.

  ## The resolution ladder — five rungs, each naming what it establishes

  A check id is not always at the site that emits it, and MES-76 already named
  three ways that happens. Two more turned up when the procedure was run over
  the whole denominator rather than over 13 hand-picked rows. Each rung is
  tried in order and the first that hits wins; the row records which one did,
  because the rungs do **not** establish the same thing.

  | rung | what the grep found | what it pins |
  | --- | --- | --- |
  | `id_literal_pair` | the id literal, adjacent to **this row's own `name`** | the **row** |
  | `id_literal_site` | the id literal at an emitting position, next to a *computed* name | the **check**, not the row |
  | `id_bound_variable` | the id inside an initialiser bound to a variable, consumed at an emitting site | the check |
  | `id_table_value` | the id as a value in a lookup table, consumed at an emitting site | the **row** via the table ENTRY *when the entry's key is this row's own name suffix*; the **loop** when it is a sibling's — see below |
  | `id_template_prefix` | nothing — the id is built at runtime; its longest literal prefix heads a template at an emitting site | the **loop**, not the row |

  `id_bound_variable` generalises MES-76's CONSTANT case: the binding need not
  be a bare literal. `sep-2243-client-encode-values` is bound by a **ternary**
  (``c=s?`…base64-unsafe`:r===`number`…?`…encode-values`:`…mirrors…` ``), and a
  rule reading only ``X=`id` `` misses it. `id_table_value` is a case MES-76
  does not name at all: ten `http-invalid-tool-headers` rows take their id from
  an object literal (`Ua`) consumed by `Object.entries`.

  ## What `id_table_value` pins is NOT a property of the rung (MES-97 CR finding)

  The rung's site is a **loop** — `for(let[e,t]of Object.entries(Ua))` — and the
  name it emits is computed (`` `ClientRejectsInvalidTool_${e}` ``). So the site
  is the same 1162 bytes for every row the table carries, and **nothing at the
  site distinguishes one row from another**. The row-level link, where there is
  one, lives at a *second and different* address: the table entry
  `` key:`check-id` `` inside `Ua`'s definition.

  Hence `pin_level/2` takes the rung **and its metadata**, not the rung alone:

    * `row_key_matches == true` — the entry that resolved is keyed by this row's
      own name suffix, so the entry pins the **row**. The entry's span *and its
      bytes* are recorded in `rung_detail.table_entry`, because a row-level claim
      whose bytes do not show the row is an address without evidence (ruling 7).
    * `row_key_matches == false` — the id was reached through a **sibling's**
      key, and no address in hand names this row. What is pinned is the table,
      and therefore the **loop** that consumes it. This is a real resolution and
      is recorded as one; it is simply coarser than the row.

  Six of the ten `id_table_value` rows are in the second class. They were
  recorded as row-level until CR measured that their committed bytes do not
  contain their own case suffix.

  ## Why the emitting-position test insists on the enclosing delimiter

  An id literal followed by `` ,` `` looks like a call argument and is not
  always one: `Ha=[…]` is an **array** of five check ids, each of them followed
  by `` ,` ``. Reading those as emitting sites resolved
  `sep-2243-client-encode-values` to its membership list rather than to the
  code that emits it — a grep that fails *toward* its conclusion. So an
  occurrence counts as a call argument only when `enclosing/2` reports its
  nearest unclosed delimiter is `(`.

  The same hazard, one rung down: the `id_template_prefix` search drops trailing
  `-`-segments until the prefix hits, and **without a structural test it hits on
  `sep`** — inside the harness's own `sep-${e}-todo` scaffolding, ~70 KB from
  any check. Ten rows resolved that way before the emitting-position test was
  added to the prefix rung too. A prefix that is not at an emitting site is not
  a resolution.

  ## The excerpt rule, in stated precedence

  From the site, walk outward through enclosing scopes and take the first of:

      1. a `getChecks(){` method body
      2. a `callee(...)` call
      3. a `{id:…}` check object literal

  Precedence, **not** innermost-first, and the order is not arbitrary: a check
  object literal is *produced* by the construct around it, so where there is a
  producer the producer is the emitting construct. A3 cut `sep-2106` at the
  `getChecks()` method and the twelve `a(`-form rows at the call; only this
  ordering reproduces both from one rule.

  ## What makes a green run of this module mean something

  `positive_control/1` re-derives all **13** of A3's hand-cut rows from the
  ladder and the excerpt rule and requires every one to come back
  **byte-identical** to the committed `evaluator_excerpt`. It is the only
  population where a hand answer and a mechanical answer both exist, so it is
  the only place the mechanism can be checked against something other than
  itself. `mix conformance.locator` runs it **before** emitting anything and
  refuses on a single mismatch.

  It does **not** establish that the site is the place the check's **verdict**
  is decided. `sep-2575-client-retry-supported-version` is emitted with a
  hard-coded `` status:`WARNING` `` and its real predicate lives ~200 bytes
  later, at a `this.checks.find(…)` mutation site that carries no id literal in
  an emitting position. The locator finds the emitter; where the two differ,
  the axes artefact records the mutation site separately. Recorded as S9-16.
  """

  @ladder [
    :id_literal_pair,
    :id_literal_site,
    :id_bound_variable,
    :id_table_value,
    :id_template_prefix
  ]

  @typedoc "Which rung of the ladder resolved a row."
  @type rung ::
          :id_literal_pair
          | :id_literal_site
          | :id_bound_variable
          | :id_table_value
          | :id_template_prefix
          | :unresolved

  @typedoc "A scanned harness: the bytes, the bracket index, and the multibyte map."
  @opaque harness :: %{
            bin: binary(),
            brackets: [{non_neg_integer(), byte()}],
            conts: [non_neg_integer()]
          }

  @doc "The ladder's rungs, in the order they are tried."
  @spec ladder() :: [rung()]
  def ladder, do: @ladder

  @typedoc """
  How finely a resolution addresses the manifest row it was run for.

  `:row` — an address exists that names *this row*. `:check` — the address is
  the check's, and rows sharing the check share it. `:loop` — the address emits
  this row **and its siblings**, and nothing at it tells them apart. `:none` —
  nothing was resolved.
  """
  @type pin_level :: :row | :check | :loop | :none

  @doc """
  What a resolution actually pins — a function of the rung **and its metadata**.

  Rung alone is not enough, and that is the MES-97 CR finding rather than a
  design flourish: `id_table_value` pins the row when the table entry that
  resolved is keyed by this row's own name suffix, and only the loop when it is
  a sibling's key. See the moduledoc section on that rung.

      iex> MCP.Conformance.Locator.pin_level(:id_literal_pair, %{})
      :row
      iex> MCP.Conformance.Locator.pin_level(:id_table_value, %{"row_key_matches" => true})
      :row
      iex> MCP.Conformance.Locator.pin_level(:id_table_value, %{"row_key_matches" => false})
      :loop
  """
  @spec pin_level(rung(), map()) :: pin_level()
  def pin_level(:id_literal_pair, _meta), do: :row
  def pin_level(:id_literal_site, _meta), do: :check
  def pin_level(:id_bound_variable, _meta), do: :check
  def pin_level(:id_table_value, %{"row_key_matches" => true}), do: :row
  def pin_level(:id_table_value, _meta), do: :loop
  def pin_level(:id_template_prefix, _meta), do: :loop
  def pin_level(:unresolved, _meta), do: :none

  @doc """
  Read and index a harness build. Everything else in this module takes the
  result, so the 810 KB scan happens once per run rather than once per row.
  """
  @spec load(Path.t()) :: {:ok, harness()} | {:error, term()}
  def load(path) do
    case File.read(path) do
      {:ok, bin} -> {:ok, index(bin)}
      {:error, reason} -> {:error, {:unreadable, path, reason}}
    end
  end

  @doc "Index an already-read harness."
  @spec index(binary()) :: harness()
  def index(bin) when is_binary(bin) do
    %{bin: bin, brackets: scan(bin, 0, []), conts: continuations(bin, 0, [])}
  end

  @doc """
  How many times `needle` occurs in the build.

  Public because the occurrence count is one of the three measurements the
  locator artefact keeps apart (S9-14) and a caller must be able to take it
  without reaching inside the opaque handle.
  """
  @spec count(harness(), binary()) :: non_neg_integer()
  def count(%{bin: bin}, needle), do: length(:binary.matches(bin, needle))

  @doc """
  How many times the check id occurs **as a whole template literal** — the
  `occurs at all` predicate, and NOT the `reaches the emitting site` one. The
  two differ on 22 of the 173 rows and conflating them is S9-14.
  """
  @spec occurrence_count(harness(), String.t()) :: non_neg_integer()
  def occurrence_count(h, check_id), do: count(h, "`" <> check_id <> "`")

  @doc "sha256 of the indexed build, lower-case hex — what a row's provenance pins."
  @spec sha256(harness()) :: String.t()
  def sha256(%{bin: bin}), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)

  @doc """
  Resolve one manifest row to its emitting site(s).

  `check_id` and `name` are A1's third and fourth key fields. Both are needed:
  the id alone cannot tell rung 1 from rung 2, and rung 2 is the rung that says
  *"this site is the check's, but it is not this row's"*.
  """
  @spec resolve(harness(), String.t(), String.t()) ::
          {rung(), [non_neg_integer()], map()}
  def resolve(h, check_id, name) do
    occ = occurrences(h, check_id)

    cond do
      (hits = pair_sites(h, occ, check_id, name)) != [] -> {:id_literal_pair, hits, %{}}
      (hits = emitting_sites(h, occ, check_id)) != [] -> {:id_literal_site, hits, %{}}
      true -> resolve_indirect(h, occ, check_id, name)
    end
  end

  defp resolve_indirect(h, occ, check_id, name) do
    Enum.find_value(
      [
        fn -> bound_variable(h, occ) end,
        fn -> table_value(h, occ, check_id, name) end,
        fn -> template_prefix(h, check_id) end
      ],
      {:unresolved, [], %{}},
      fn rung -> with :miss <- rung.(), do: nil end
    )
  end

  @doc """
  The excerpt rule: the byte span of the emitting construct around `site`.

  Returns `{start, stop}` as a **byte** half-open range into the build, or
  `:none` when no enclosing construct answers to any of the three forms.
  """
  @spec excerpt(harness(), non_neg_integer()) :: {non_neg_integer(), non_neg_integer()} | :none
  def excerpt(h, site) do
    chain = enclosing_chain(h, site, 8)

    get_checks(h, chain) || call_form(h, chain) || object_literal(h, chain) || :none
  end

  @doc "The bytes at a span — the evidence an address is only a pointer to (ruling 7)."
  @spec bytes(harness(), {non_neg_integer(), non_neg_integer()}) :: binary()
  def bytes(%{bin: bin}, {from, to}), do: binary_part(bin, from, to - from)

  @doc """
  Convert a byte offset to a character offset.

  A3 records both, and they differ: the build is 809_888 bytes and 809_555
  characters, so a byte span quoted as a character span is wrong by up to 333
  and lands mid-token.
  """
  @spec char_offset(harness(), non_neg_integer()) :: non_neg_integer()
  def char_offset(%{conts: conts}, byte_pos) do
    byte_pos - Enum.count(conts, &(&1 < byte_pos))
  end

  @doc """
  The positive control: re-derive A3's 13 hand-cut rows mechanically and compare
  the **bytes**, not the spans alone.

  Returns `{:ok, 13}` or `{:error, mismatches}`. A control that can only pass is
  not a control, so the failure carries the row and what it produced.
  """
  @spec positive_control(harness(), map()) :: {:ok, non_neg_integer()} | {:error, [map()]}
  def positive_control(h, axes_artefact) do
    rows = Map.fetch!(axes_artefact, "checks")

    mismatches =
      Enum.flat_map(rows, fn row ->
        [_leg, _scenario, check_id, name, _desc, _disc] = row["key"]

        {from, to} =
          {hd(row["emitting_site"]["dist_byte_span"]),
           List.last(row["emitting_site"]["dist_byte_span"])}

        expected = row["evaluator_excerpt"]

        {rung, sites, _meta} = resolve(h, check_id, name)
        spans = sites |> Enum.map(&excerpt(h, &1)) |> Enum.reject(&(&1 == :none)) |> Enum.uniq()

        if {from, to} in spans and bytes(h, {from, to}) == expected do
          []
        else
          [
            %{
              check_id: check_id,
              name: name,
              rung: rung,
              a3_span: {from, to},
              derived_spans: spans
            }
          ]
        end
      end)

    if mismatches == [], do: {:ok, length(rows)}, else: {:error, mismatches}
  end

  # --- the ladder ---

  defp occurrences(%{bin: bin}, check_id) do
    lit = "`" <> check_id <> "`"
    find_all(bin, lit, 0, [])
  end

  defp find_all(bin, needle, from, acc) do
    case :binary.match(bin, needle, scope: {from, byte_size(bin) - from}) do
      :nomatch -> Enum.reverse(acc)
      {at, len} -> find_all(bin, needle, at + len, [at | acc])
    end
  end

  # Rung 1: the id literal sitting next to THIS ROW's own name.
  defp pair_sites(h, occ, check_id, name) do
    Enum.filter(occ, fn p ->
      emitting_at?(h, p, byte_size(check_id)) and
        (after?(h, p, check_id, ",`" <> name <> "`") or
           after?(h, p, check_id, ",name:`" <> name <> "`"))
    end)
  end

  # Rung 2: the id literal at an emitting position, whatever name is there.
  defp emitting_sites(h, occ, check_id) do
    Enum.filter(occ, &emitting_at?(h, &1, byte_size(check_id)))
  end

  defp after?(%{bin: bin}, p, check_id, suffix) do
    at = p + byte_size(check_id) + 2

    :binary.match(bin, suffix, scope: {at, min(byte_size(suffix), byte_size(bin) - at)}) ==
      {at, byte_size(suffix)}
  end

  # An occurrence is EMITTING when it is an `id:` property followed by `,name:`,
  # or a call argument. "Call argument" insists on the enclosing delimiter being
  # `(` — see the moduledoc: an array of check ids passes the lexical test and
  # is not a call.
  defp emitting_at?(h, p, id_len) do
    stop = p + id_len + 2

    cond do
      ends_with?(h, p, "id:") and starts_with?(h, stop, ",name:") -> true
      starts_with?(h, stop, ",`") -> match?({_, ?(}, enclosing(h, p))
      true -> false
    end
  end

  defp ends_with?(%{bin: bin}, at, s) do
    n = byte_size(s)
    at >= n and binary_part(bin, at - n, n) == s
  end

  defp starts_with?(%{bin: bin}, at, s) do
    n = byte_size(s)
    at + n <= byte_size(bin) and binary_part(bin, at, n) == s
  end

  # Rung 3: the id is inside an initialiser bound to a variable at depth 0, and
  # that variable is consumed at an emitting site.
  defp bound_variable(h, occ) do
    Enum.find_value(occ, :miss, fn p ->
      with {:ok, var} <- binding_name(h, p),
           [_ | _] = hits <- consumers(h, var) do
        {:id_bound_variable, hits, %{"binding" => var}}
      else
        _ -> nil
      end
    end)
  end

  defp binding_name(%{bin: bin} = h, p) do
    scan_back_for_eq(bin, p - 1, 0, max(p - 400, 0))
    |> case do
      nil -> :error
      eq -> ident_before(h, eq)
    end
  end

  defp scan_back_for_eq(_bin, i, _depth, floor) when i <= floor, do: nil

  defp scan_back_for_eq(bin, i, depth, floor) do
    case :binary.at(bin, i) do
      c when c in ~c")}]" ->
        scan_back_for_eq(bin, i - 1, depth + 1, floor)

      c when c in ~c"({[" ->
        if depth == 0, do: nil, else: scan_back_for_eq(bin, i - 1, depth - 1, floor)

      ?; when depth == 0 ->
        nil

      ?= when depth == 0 ->
        if plain_assignment?(bin, i), do: i, else: scan_back_for_eq(bin, i - 1, depth, floor)

      _ ->
        scan_back_for_eq(bin, i - 1, depth, floor)
    end
  end

  defp plain_assignment?(bin, i) do
    :binary.at(bin, i - 1) not in ~c"=!<>" and :binary.at(bin, i + 1) != ?=
  end

  defp ident_before(%{bin: bin}, eq) do
    from = max(eq - 60, 0)
    window = binary_part(bin, from, eq - from)

    case Regex.run(~r/([A-Za-z_$][A-Za-z0-9_$]*)$/, window) do
      [_, var] -> {:ok, var}
      _ -> :error
    end
  end

  defp consumers(%{bin: bin}, var) do
    props = Regex.scan(~r/id:#{Regex.escape(var)}(?![A-Za-z0-9_$]),name:/, bin, return: :index)
    args = Regex.scan(~r/\(#{Regex.escape(var)}(?![A-Za-z0-9_$]),`/, bin, return: :index)

    (Enum.map(props, fn [{at, _} | _] -> at end) ++ Enum.map(args, fn [{at, _} | _] -> at + 1 end))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Rung 4: the id is a value in an object literal bound to a variable, and the
  # table is consumed at an emitting site. The consuming site is a LOOP over the
  # whole table; the row-level link, where there is one, is the table ENTRY, and
  # that is a second address. Both are recorded — see `pin_level/2`.
  defp table_value(h, occ, check_id, name) do
    Enum.find_value(occ, :miss, fn p ->
      with {:ok, key} <- property_key(h, p),
           {:ok, table, def_at} <- enclosing_table(h, p),
           [_ | _] = hits <- table_consumers(h, table, def_at) do
        span = entry_span(p, key, check_id)

        {:id_table_value, hits,
         %{
           "table" => table,
           "table_key" => key,
           "row_key_matches" => String.ends_with?(name, key),
           "table_entry" => %{
             "byte_span" => Tuple.to_list(span),
             "char_span" => [char_offset(h, elem(span, 0)), char_offset(h, elem(span, 1))],
             "bytes" => bytes(h, span),
             "note" =>
               "The entry is NOT the emitting site — it is the second address this rung " <>
                 "rests on. A row-level pin is a claim about THIS span's bytes; the site's " <>
                 "bytes are the loop's and name no row (ruling 7)."
           }
         }}
      else
        _ -> nil
      end
    end)
  end

  # `key:`check-id`` — from the first byte of the key to the closing backtick.
  defp entry_span(p, key, check_id),
    do: {p - byte_size(key) - 1, p + byte_size(check_id) + 2}

  defp property_key(%{bin: bin}, p) do
    from = max(p - 60, 0)
    window = binary_part(bin, from, p - from)

    case Regex.run(~r/([A-Za-z_$][A-Za-z0-9_$]*):$/, window) do
      [_, key] -> {:ok, key}
      _ -> :error
    end
  end

  defp enclosing_table(%{bin: bin} = h, p) do
    case enclosing(h, p) do
      {at, ?{} ->
        from = max(at - 60, 0)
        window = binary_part(bin, from, at - from)

        case Regex.run(~r/([A-Za-z_$][A-Za-z0-9_$]*)=$/, window) do
          [_, var] -> {:ok, var, at}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp table_consumers(%{bin: bin}, table, def_at) do
    ~r/(?<![A-Za-z0-9_$])#{Regex.escape(table)}(?![A-Za-z0-9_$])/
    |> Regex.scan(bin, return: :index)
    |> Enum.flat_map(fn [{at, len} | _] -> consumer_after(bin, at, len, def_at) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A use of the table that is not its own definition, followed closely by an
  # `id:<var>,name:` emission. The window is what bounds "closely": the value is
  # destructured out of the table and pushed in the same loop body.
  defp consumer_after(_bin, at, _len, def_at) when abs(at - def_at) < 10, do: []

  defp consumer_after(bin, at, len, _def_at) do
    window = binary_part(bin, at + len, min(600, byte_size(bin) - at - len))

    case Regex.run(~r/id:[A-Za-z_$][A-Za-z0-9_$]*,name:/, window, return: :index) do
      [{off, _}] -> [at + len + off]
      _ -> []
    end
  end

  # Rung 5: the id does not occur. Drop trailing `-`-segments until a prefix
  # heads a template AT AN EMITTING POSITION — the structural test is what stops
  # the search resolving on the bare prefix `sep`.
  defp template_prefix(h, check_id) do
    parts = String.split(check_id, "-")

    1..(length(parts) - 1)//1
    |> Enum.reverse()
    |> Enum.find_value(:miss, fn n ->
      prefix = parts |> Enum.take(n) |> Enum.join("-")

      case template_heads(h, prefix) do
        [] -> nil
        hits -> {:id_template_prefix, hits, %{"literal_prefix" => prefix}}
      end
    end)
  end

  defp template_heads(%{bin: bin} = h, prefix) do
    bin
    |> find_all("`" <> prefix <> "-${", 0, [])
    |> Enum.filter(fn at -> emitting_at?(h, at, template_body_len(bin, at)) end)
  end

  # The literal's body length, honouring `${…}` nesting, so `emitting_at?/3` can
  # find the character after the closing backtick.
  defp template_body_len(bin, at), do: template_body_len(bin, at + 1, 0, 0)

  defp template_body_len(bin, i, depth, n) when i < byte_size(bin) do
    case {:binary.at(bin, i), depth} do
      {?`, 0} ->
        n

      {?$, _} ->
        if :binary.at(bin, i + 1) == ?{,
          do: template_body_len(bin, i + 2, depth + 1, n + 2),
          else: template_body_len(bin, i + 1, depth, n + 1)

      {?}, d} when d > 0 ->
        template_body_len(bin, i + 1, depth - 1, n + 1)

      _ ->
        template_body_len(bin, i + 1, depth, n + 1)
    end
  end

  defp template_body_len(_bin, _i, _depth, n), do: n

  # --- the excerpt rule ---

  defp enclosing_chain(h, site, limit), do: enclosing_chain(h, site, limit, [])

  defp enclosing_chain(_h, _site, 0, acc), do: Enum.reverse(acc)

  defp enclosing_chain(h, site, limit, acc) do
    case enclosing(h, site) do
      nil ->
        Enum.reverse(acc)

      {at, kind} ->
        acc = if close = match_forward(h, at), do: [{at, kind, close} | acc], else: acc
        enclosing_chain(h, at, limit - 1, acc)
    end
  end

  defp get_checks(h, chain) do
    Enum.find_value(chain, fn
      {at, ?{, close} ->
        if ends_with?(h, at, "getChecks()"), do: {at - byte_size("getChecks()"), close + 1}

      _ ->
        nil
    end)
  end

  defp call_form(h, chain) do
    Enum.find_value(chain, fn
      {at, ?(, close} ->
        case callee_before(h, at) do
          {:ok, callee} -> {at - byte_size(callee), close + 1}
          :error -> nil
        end

      _ ->
        nil
    end)
  end

  defp object_literal(h, chain) do
    Enum.find_value(chain, fn
      {at, ?{, close} -> if starts_with?(h, at + 1, "id:"), do: {at, close + 1}
      _ -> nil
    end)
  end

  defp callee_before(%{bin: bin}, at) do
    from = max(at - 120, 0)
    window = binary_part(bin, from, at - from)

    case Regex.run(~r/([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)$/, window) do
      [_, callee] -> {:ok, callee}
      _ -> :error
    end
  end

  # --- the bracket index ---

  @doc """
  The nearest unclosed `(`, `{` or `[` at or before `pos`, as `{position, byte}`.

  Public because `emitting_at?/3`'s call-argument test rests on it and a test
  that cannot ask the question cannot check the answer.
  """
  @spec enclosing(harness(), non_neg_integer()) :: {non_neg_integer(), byte()} | nil
  def enclosing(%{brackets: brackets}, pos) do
    brackets
    |> Enum.take_while(fn {at, _} -> at < pos end)
    |> Enum.reverse()
    |> walk_out(%{?( => 0, ?{ => 0, ?[ => 0})
  end

  defp walk_out([], _depth), do: nil

  defp walk_out([{at, c} | rest], depth) do
    case closer_of(c) do
      {:close, open} ->
        walk_out(rest, Map.update!(depth, open, &(&1 + 1)))

      {:open, ^c} ->
        if depth[c] == 0, do: {at, c}, else: walk_out(rest, Map.update!(depth, c, &(&1 - 1)))
    end
  end

  defp closer_of(?)), do: {:close, ?(}
  defp closer_of(?}), do: {:close, ?{}
  defp closer_of(?]), do: {:close, ?[}
  defp closer_of(c), do: {:open, c}

  @doc "The matching close bracket for the opener at `at`, or nil."
  @spec match_forward(harness(), non_neg_integer()) :: non_neg_integer() | nil
  def match_forward(%{bin: bin, brackets: brackets}, at) do
    open = :binary.at(bin, at)
    want = matching(open)

    brackets
    |> Enum.drop_while(fn {p, _} -> p <= at end)
    |> forward(open, want, 0)
  end

  defp forward([], _open, _want, _d), do: nil

  defp forward([{at, c} | rest], open, want, d) do
    cond do
      c == open -> forward(rest, open, want, d + 1)
      c == want and d == 0 -> at
      c == want -> forward(rest, open, want, d - 1)
      true -> forward(rest, open, want, d)
    end
  end

  defp matching(?(), do: ?)
  defp matching(?{), do: ?}
  defp matching(?[), do: ?]

  # --- the scanner ---
  #
  # Bracket positions OUTSIDE string, template and comment contexts. Byte-wise,
  # because the build is 810 KB and every span this module emits is a byte span.

  defp scan(bin, i, acc) when i >= byte_size(bin), do: Enum.reverse(acc)

  defp scan(bin, i, acc) do
    case :binary.at(bin, i) do
      c when c in [?", ?'] -> scan(bin, skip_quoted(bin, i + 1, c), acc)
      ?` -> scan(bin, skip_template(bin, i + 1, 0), acc)
      c when c in ~c"({[)}]" -> scan(bin, i + 1, [{i, c} | acc])
      _ -> scan(bin, i + 1, acc)
    end
  end

  defp skip_quoted(bin, i, _q) when i >= byte_size(bin), do: i

  defp skip_quoted(bin, i, q) do
    case :binary.at(bin, i) do
      ?\\ -> skip_quoted(bin, i + 2, q)
      ^q -> i + 1
      _ -> skip_quoted(bin, i + 1, q)
    end
  end

  defp skip_template(bin, i, _d) when i >= byte_size(bin), do: i

  defp skip_template(bin, i, depth) do
    case {:binary.at(bin, i), depth} do
      {?\\, _} ->
        skip_template(bin, i + 2, depth)

      {?$, _} ->
        if :binary.at(bin, i + 1) == ?{,
          do: skip_template(bin, i + 2, depth + 1),
          else: skip_template(bin, i + 1, depth)

      {?}, d} when d > 0 ->
        skip_template(bin, i + 1, depth - 1)

      {?`, 0} ->
        i + 1

      _ ->
        skip_template(bin, i + 1, depth)
    end
  end

  defp continuations(bin, i, acc) when i >= byte_size(bin), do: Enum.reverse(acc)

  defp continuations(bin, i, acc) do
    case :binary.at(bin, i) do
      c when c >= 0x80 and c < 0xC0 -> continuations(bin, i + 1, [i | acc])
      _ -> continuations(bin, i + 1, acc)
    end
  end
end

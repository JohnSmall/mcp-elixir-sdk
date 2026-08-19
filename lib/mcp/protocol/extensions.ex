defmodule MCP.Protocol.Extensions do
  @moduledoc """
  The MCP extensions **negotiation surface** (SEP-2133) — and no extension.

  This SDK supports **zero extensions**. This module exists so that a
  conformant server and client handle an `extensions` map correctly while
  supporting none of them, and so a consumer can declare support for an
  extension it has implemented itself.

  ## The surface, in full

  Two optional map fields, one on each capabilities object — there is no
  negotiation message, no handshake, no RPC and no registry:

      // schema.ts:785 (ClientCapabilities), schema.ts:882 (ServerCapabilities)
      extensions?: { [key: string]: JSONObject };

  `JSONObject = { [key: string]: JSONValue }` (schema.ts:12). Keys are
  extension identifiers, values are per-extension settings objects; an empty
  settings object means "supported, with no settings".

  ## Where each side declares — SEP-2133 mapped onto the stateless core

  SEP-2133 predates SEP-2575 and describes negotiation over the `initialize`
  handshake, which no longer exists at `2026-07-28`. The **envelope** moved;
  the map's own shape and naming rules did not. The mapping is stated upstream
  and is not this SDK's invention:

    * **Client → server, per request.** `_meta["io.modelcontextprotocol/clientCapabilities"]`
      — schema.ts:91-98 (`RequestMetaObject`), which also states *"Capabilities
      are declared per-request rather than once at initialization"* and
      *"Servers MUST NOT infer capabilities from prior requests"*. Also
      `docs/extensions/overview.mdx:120`.
    * **Server → client, once.** The `server/discover` result's `capabilities`
      — schema.ts:678-687 (`DiscoverResult`), `docs/extensions/overview.mdx:152`.

  The two therefore have **different lifetimes**, and this module keeps them
  apart by shape rather than by convention. A server's set is launch-static
  (`MCP.Server.Config.build/2`'s `:extensions` option, frozen at `init/1`); a
  client's is read out of *that request's* `_meta` via `from_meta/1`, whose
  argument is the request's own metadata and which caches nothing between
  requests.

  All citations are to the published-final `2026-07-28` schema at commit
  `5f5440bb26a62e2cf3440b92da5a667efa03b267`, `schema/2026-07-28/schema.ts`,
  and to the spec pages at the same pin.

  ## Supporting zero extensions is a behaviour, not an absence

  `docs/specification/2026-07-28/basic/versioning.mdx:121-124` puts the
  graceful-degradation obligation on **the supporting party**:

  > If one party supports an extension but the other does not, the supporting
  > party MUST either revert to core protocol behavior or reject the request
  > with an appropriate error.

  We support zero, so we are always the **non-supporting** party and the
  obligation is the peer's. **A peer offering extensions we do not support is
  not an error condition**: such a request is serviced normally and its
  declaration is neither rejected, rewritten nor logged as a fault. Rejecting
  it would be over-building against the spec, not under-building.

  Extensions are also **disabled by default and require explicit opt-in**
  (`seps/2133-extensions.md:99`). Here that is structural rather than a default
  value someone can forget: `MCP.Server.Config.detect_capabilities/2` never
  sets the field, and the capability encoders drop `nil`, so `extensions` is
  **absent** from the wire unless a consumer declares something. Absent is not
  the same claim as `{}`: `"extensions": {}` says "I do extensions, none of
  them", and we make no claim at all.

  ## Validation: enforced outbound, deliberately not enforced inbound

    * **Outbound** (`normalise/2`, used on our own declarations) — identifiers
      that fail `valid_identifier?/1` are dropped, as are settings values that
      would not encode as a JSON object, and an empty result becomes `nil`
      (absent). This is the only point at which the SDK could help a consumer
      emit a key that violates a MUST. Dropping rather than raising follows
      `MCP.Protocol.Messages.Subscriptions`' unknown-key posture: a
      declaration that cannot be honoured, dropped, leaves a wire that tells
      the truth.

      **Nothing a consumer puts in a declaration may fail later than the call
      that normalises it.** Both seams — `MCP.Server.Config.build/2` and
      `MCP.Client.start_link/1` — run at *launch*, on config the consumer owns,
      in a process the consumer is starting; a value that survived to request
      time and raised there (an unencodable settings value raising out of
      `Jason` on *every* `server/discover`, forever) would be a launch-time
      mistake reported at an unrelated place, at an unrelated time, to someone
      who cannot fix it. So everything is checked here, and anything dropped is
      named in a `Logger.warning` — the drop keeps the wire truthful, the
      warning supplies the diagnosability that dropping alone loses. This is
      the one respect in which the `Subscriptions` precedent does **not**
      transfer: a *peer's* malformed key has no channel back to whoever made
      it, and a *consumer's* does.
    * **Inbound** (`from_meta/1`, reading a peer's declarations) — **not
      validated and never an error**. A shape guard only: a non-object yields
      `%{}`, so a handler is never handed a crash. A key we would consider
      malformed still reaches the handler verbatim, because silently rewriting
      a peer's claim is the opposite of reporting what it actually said.

  ## Reserved prefixes are classified, never blocked

  `reserved_prefix?/1` reports the schema's reservation (schema.ts:45) and the
  SDK itself does **not** act on it, in either direction. Declaring support for
  an *official* extension is exactly a reserved-prefix identifier —
  `io.modelcontextprotocol/tasks` is the schema's own `ServerCapabilities`
  example — and on the wire that is indistinguishable from inventing a private
  extension under a reserved prefix. The reservation governs who may **define**
  an identifier, not who may declare support for one, so blocking would break
  the common legitimate case and warning would fire on it every time. The
  predicate ships for consumers who want to make their own judgement — which is
  why its two undecided corners are stated on it rather than left to be
  discovered: it is **case-sensitive**, and a **single-label** prefix is not
  reserved. See `reserved_prefix?/1`.

  ## Supported extensions

  **None.** `seps/2133-extensions.md:99` asks SDK documentation to list the
  extensions it supports; the list is empty, and stating that is the point.
  """

  require Logger

  alias MCP.Protocol.Meta

  # schema.ts:43 -- "Labels MUST start with a letter and end with a letter or
  # digit. Interior characters may be letters, digits, or hyphens (`-`)."
  @label "[A-Za-z](?:[A-Za-z0-9-]*[A-Za-z0-9])?"

  # schema.ts:42 -- "a series of _labels_ separated by dots (`.`), followed by a
  # slash (`/`)". The trailing slash is the separator and is not part of what
  # this pattern matches.
  #
  # ANCHORED WITH \A .. \z, NEVER ^ .. $ (MES-16 round 1, R-1). In PCRE `$`
  # also matches immediately before a final newline, so `^...$` accepted a
  # prefix or a name ending in `\n` -- a MUST-violating identifier that
  # `normalise/1` then put on the wire. `\z` matches only at the true end of
  # the string. Both patterns below are whole-string predicates, so both use it.
  @prefix_regex ~r/\A#{@label}(?:\.#{@label})*\z/

  # schema.ts:48-49 -- "Unless empty, MUST start and end with an alphanumeric
  # character ([a-z0-9A-Z]). Interior characters may be alphanumeric, hyphens
  # (`-`), underscores (`_`), or dots (`.`)." The empty alternative is the
  # schema's own "unless empty" case and is deliberately preserved; it applies
  # to the NAME SEGMENT of a key, never to a key that is empty in its entirety
  # (see `valid_meta_key?/1`).
  @name_regex ~r/\A(?:|[A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9])\z/

  # schema.ts:45 -- "Any prefix where the second label is `modelcontextprotocol`
  # or `mcp` is reserved for MCP use."
  @reserved_second_labels ["modelcontextprotocol", "mcp"]

  # How many dropped identifiers the warning names PER REASON before it says
  # how many more there were. See `warn_dropped/2`.
  @max_named_per_reason 10

  @typedoc """
  A validated outbound declaration: identifier → settings object.
  """
  @type declaration :: %{optional(String.t()) => map()}

  @typedoc """
  A peer's declaration as received. Values are **whatever the peer sent** —
  retained verbatim and not narrowed to objects, because inbound data is not
  validated here (see the moduledoc).
  """
  @type received :: %{optional(String.t()) => term()}

  @doc """
  Whether `key` is a valid `_meta` key (schema.ts:39-49).

  The general rule, in which the **prefix is optional**. Extension identifiers
  need the stricter `valid_identifier?/1`, which is this rule plus a mandatory
  prefix.

  This is the primitive on purpose: the same rule governs every `_meta` key,
  and a second bespoke pattern elsewhere in this SDK would be a second
  opportunity to get it wrong. Wiring it into general `_meta` handling would
  change behaviour on paths this module does not own and is left to a later
  ticket.
  """
  @spec valid_meta_key?(term()) :: boolean()
  def valid_meta_key?(key) when is_binary(key) do
    case String.split(key, "/") do
      # The empty string is not a key -- OUR narrowing, not the schema's
      # (MES-16 round 2, R-12). Read literally, schema.ts:39-49 makes the
      # prefix optional and schema.ts:48's "unless empty" permits an empty
      # name, and that reading licenses `""` exactly as it licenses
      # `"com.example/"`. We refuse it anyway because there is nothing there to
      # name anything, so it cannot identify anything. `"com.example/"` -- an
      # empty NAME after a real prefix -- IS the schema's own "unless empty"
      # case and stays valid; the two corners look alike and only one of them
      # is the schema's.
      [""] -> false
      [name] -> valid_name?(name)
      [prefix, name] -> valid_prefix?(prefix) and valid_name?(name)
      _too_many_slashes -> false
    end
  end

  def valid_meta_key?(_key), do: false

  @doc """
  Whether `key` is a valid **extension identifier**.

  `valid_meta_key?/1` **and** a prefix is present — schema.ts:779-780
  (client) and schema.ts:876-877 (server), *"Keys MUST follow the `_meta` key
  naming rules, with a mandatory prefix"*, reinforced by
  `basic/versioning.mdx:86-87`. The mandatory prefix is the one place an
  extension identifier is stricter than a `_meta` key generally.

  ## Examples

      iex> MCP.Protocol.Extensions.valid_identifier?("io.modelcontextprotocol/tasks")
      true

      iex> MCP.Protocol.Extensions.valid_identifier?("tasks")
      false

  """
  @spec valid_identifier?(term()) :: boolean()
  def valid_identifier?(key) when is_binary(key),
    do: String.contains?(key, "/") and valid_meta_key?(key)

  def valid_identifier?(_key), do: false

  @doc """
  Whether `key`'s prefix is reserved for MCP use — its **second** label is
  `modelcontextprotocol` or `mcp` (schema.ts:45).

  Accepts either a full identifier (`"io.modelcontextprotocol/tasks"`) or a
  bare prefix (`"io.modelcontextprotocol/"`). A key with no prefix is not
  reserved.

  Two corners the schema does not settle, decided here and stated so a consumer
  making its own judgement knows which answer it is getting:

    * **A single-label prefix is not reserved** — `"mcp/thing"` and
      `"modelcontextprotocol/thing"` are both `false`. schema.ts:45 is written
      about the **second** label, and a rule about a label that is not there
      does not fire.
    * **The comparison is case-sensitive** — `"io.ModelContextProtocol/tasks"`
      is `false`. schema.ts:45 is silent on case; reverse-DNS labels are
      conventionally case-insensitive, so the other reading is available and a
      consumer wanting it must fold the case itself. Nothing in this SDK acts
      on the predicate, so this decides only what a consumer is told, never
      what goes on the wire.

  **Informational only.** Nothing in this SDK acts on the result — see the
  moduledoc for why blocking a reserved prefix would break the common
  legitimate case.

  ## Examples

      iex> MCP.Protocol.Extensions.reserved_prefix?("io.modelcontextprotocol/tasks")
      true

      iex> MCP.Protocol.Extensions.reserved_prefix?("com.example.mcp/thing")
      false

  """
  @spec reserved_prefix?(term()) :: boolean()
  def reserved_prefix?(key) when is_binary(key) do
    case String.split(key, "/") do
      [prefix, _name] ->
        case String.split(prefix, ".") do
          [_first, second | _rest] -> second in @reserved_second_labels
          _fewer_than_two_labels -> false
        end

      _no_prefix_or_too_many_slashes ->
        false
    end
  end

  def reserved_prefix?(_key), do: false

  @doc """
  Normalises an **outbound** extensions declaration.

  Keeps an entry only when both halves are fit for the wire:

    * the identifier satisfies `valid_identifier?/1` (schema.ts:39-49 plus the
      mandatory prefix), and
    * the settings value is a map whose `Jason.encode/1` output **begins with
      `{`** (schema.ts:12). The check is on the encoding, not on the Elixir
      type, and two different things fail it: a value the encoder cannot encode
      at all (a map holding a tuple, a pid, or a struct with no
      `Jason.Encoder`), and a value it encodes to something that is not an
      object — `%Date{}`, `%Time{}`, `%DateTime{}` and `%NaiveDateTime{}` all
      encode to a JSON *string*, with no custom encoder involved. A struct that
      *derives* `Jason.Encoder` encodes to `{…}` and is kept.

  Everything else is **dropped and named in a `Logger.warning`**, including an
  `:extensions` value that is not a map at all (a struct, a string, `nil`).
  Nothing here raises and nothing is deferred: this call is the last place a
  bad declaration can be reported to the consumer who wrote it, so it is the
  place it is reported. Raising instead would turn a typo in one identifier
  into a server that will not start.

  Returns `nil` when nothing survives — including for an input of `%{}`. `nil`
  is what the capability encoders drop, so an empty declaration is **absent**
  from the wire rather than present-and-empty.

  Reserved prefixes are **not** dropped: declaring support for
  `io.modelcontextprotocol/tasks` is the ordinary legitimate case.

  ## Options

    * `:source` — a string naming the seam for the warning, so the reader is
      told which option they got wrong. Defaults to this function's own name.

  ## Examples

      iex> MCP.Protocol.Extensions.normalise(%{"io.modelcontextprotocol/tasks" => %{}})
      %{"io.modelcontextprotocol/tasks" => %{}}

      iex> MCP.Protocol.Extensions.normalise(%{"tasks" => %{}})
      nil

      iex> MCP.Protocol.Extensions.normalise(%{})
      nil

  """
  @spec normalise(term(), keyword()) :: declaration() | nil
  def normalise(declared, opts \\ [])

  def normalise(declared, opts) when is_map(declared) and not is_struct(declared) do
    {kept, dropped} =
      Enum.reduce(declared, {%{}, []}, fn {key, settings}, {kept, dropped} ->
        cond do
          not valid_identifier?(key) ->
            {kept,
             [
               {key, "not a valid extension identifier (schema.ts:39-49, prefix mandatory)"}
               | dropped
             ]}

          not json_object?(settings) ->
            {kept, [{key, "settings are not a JSON object (schema.ts:12)"} | dropped]}

          true ->
            {Map.put(kept, key, settings), dropped}
        end
      end)

    warn_dropped(dropped, opts)

    if map_size(kept) > 0, do: kept
  end

  def normalise(nil, _opts), do: nil

  # A struct, a string, a number: not a declaration. Matched here rather than
  # left to the comprehension above, because iterating a struct raises
  # `Protocol.UndefinedError` (no `Enumerable`) — the exact deferred-failure
  # class this function exists to close.
  def normalise(declared, opts) do
    Logger.warning(
      "MCP extensions (SEP-2133) — #{source(opts)}: the declaration is not an object " <>
        "(#{inspect(declared, limit: 5, printable_limit: 120)}); NOTHING is advertised."
    )

    nil
  end

  @doc """
  Reads the **peer's** declared extensions out of a raw per-request `_meta` map.

  Server-side, pass `ctx.meta` (`MCP.Server.ToolContext`) — the client's
  declaration for *this* request, per schema.ts:91-98. Returns `%{}` when
  absent or malformed, so a handler never has to guard the shape:

      if Map.has_key?(Extensions.from_meta(ctx.meta), "io.modelcontextprotocol/tasks") do
        # ... extension-aware behaviour ...
      else
        # ... core behaviour ...
      end

  That check is how a server discharges `seps/2133-extensions.md:174` —
  *"servers SHOULD check client capabilities before offering
  extension-specific features"*. **This SDK ships no extension, so nothing in
  it calls this function; it is here for handler authors.**

  Contents are **not validated** and reach the caller verbatim (see the
  moduledoc). Nothing is cached: the answer is a function of the `_meta` you
  pass, which is why schema.ts:96 (*"Servers MUST NOT infer capabilities from
  prior requests"*) holds by shape here rather than by discipline.

  **The empty/absent distinction this module insists on outbound is collapsed
  here, deliberately.** A peer that sent `"extensions": {}` ("I do extensions,
  none of them") and a peer that omitted the key ("no claim") both read as
  `%{}`, and so does a malformed one. Outbound the difference is a claim we
  make and must not make carelessly; inbound, since we support zero extensions,
  every one of those peers is a peer whose extensions we do not support — the
  three are operationally identical and distinguishing them would be
  complexity with no consumer. If you need the raw distinction, it is still in
  the `_meta` you passed in.

  > #### These are declarations, never identity {: .warning}
  >
  > Extension declarations are **client-composed and self-asserted**. They say
  > what the peer *supports*; they never say who the peer *is*, and they
  > **MUST NOT** gate access to anything. Caller identity comes from
  > `ctx.identity` alone, which the authenticated transport pipeline supplies —
  > never from the message body. This is the schema's own stance on
  > self-reported peer data, not a house rule: schema.ts:85-88 says of
  > `clientInfo` that it is *"not verified by the protocol"* and that servers
  > *"SHOULD NOT rely on it for security decisions"*.

  ## Examples

      iex> meta = %{"io.modelcontextprotocol/clientCapabilities" =>
      ...>   %{"extensions" => %{"io.modelcontextprotocol/tasks" => %{}}}}
      iex> MCP.Protocol.Extensions.from_meta(meta)
      %{"io.modelcontextprotocol/tasks" => %{}}

      iex> MCP.Protocol.Extensions.from_meta(nil)
      %{}

  """
  @spec from_meta(map() | nil) :: received()
  def from_meta(meta) when is_map(meta) do
    with capabilities when is_map(capabilities) <-
           Map.get(meta, Meta.client_capabilities_key()),
         extensions when is_map(extensions) <- Map.get(capabilities, "extensions") do
      extensions
    else
      _absent_or_not_an_object -> %{}
    end
  end

  def from_meta(_meta), do: %{}

  defp valid_prefix?(prefix), do: Regex.match?(@prefix_regex, prefix)
  defp valid_name?(name), do: Regex.match?(@name_regex, name)

  # "Is it an object?" answered by the encoder that will actually have to do
  # it, and asked about the ENCODING rather than about the Elixir type. Both
  # halves matter, and the second is MES-16 round 2 (R-7): "is a map" and
  # "encodes without error" are each necessary and together still not
  # sufficient, because a struct's encoder may emit something that is not an
  # object. It takes no custom `Jason.Encoder` to reach one —
  # `Jason.encode(~D[2026-08-19])` is `{:ok, "\"2026-08-19\""}`, a JSON STRING,
  # and `%Time{}`, `%DateTime{}` and `%NaiveDateTime{}` behave the same. So the
  # check is the encoding's first byte: `{` and nothing else. schema.ts:785 and
  # :882 require `{ [key: string]: JSONObject }`, and schema.ts:12 defines
  # `JSONObject` as `{ [key: string]: JSONValue }`; a JSON string is not one.
  #
  # `Jason.encode/1` RETURNS `{:error, %Protocol.UndefinedError{}}` rather than
  # raising for tuples, pids and structs with no encoder, nested and top-level
  # alike, so this predicate is total on any term and needs no `rescue`.
  defp json_object?(settings) when is_map(settings) do
    match?({:ok, "{" <> _rest}, Jason.encode(settings))
  end

  defp json_object?(_settings), do: false

  defp warn_dropped([], _opts), do: :ok

  # Grouped by reason and capped, because the enumeration is unbounded in the
  # number of declarations the consumer wrote: 500 bad ones produced a single
  # 42,004-byte log line, most of it the same reason string repeated verbatim
  # (MES-16 round 2, R-10). The cap SAYS how many it elided — a truncated list
  # that does not admit it truncated is the silent-drop class this ticket has
  # spent two rounds closing, wearing a different hat.
  #
  # Sorted, not reversed: the reduce that built this list ran over a MAP, whose
  # iteration order is arbitrary, so there was never a declaration order to
  # restore and the `Enum.reverse/1` that used to be here implied one (R-11).
  # Sorting costs the same and makes the line stable enough to diff and grep.
  defp warn_dropped(dropped, opts) do
    detail =
      dropped
      |> Enum.group_by(fn {_key, why} -> why end, fn {key, _why} -> key end)
      |> Enum.sort_by(fn {why, _keys} -> why end)
      |> Enum.map_join("; ", fn {why, keys} -> "#{why}: #{named(keys)}" end)

    Logger.warning(
      "MCP extensions (SEP-2133) — #{source(opts)}: #{length(dropped)} declaration(s) DROPPED " <>
        "and NOT advertised — #{detail}"
    )
  end

  defp named(keys) do
    sorted = Enum.sort(keys)
    shown = Enum.take(sorted, @max_named_per_reason)
    listed = Enum.map_join(shown, ", ", &inspect(&1, printable_limit: 120))

    case length(sorted) - length(shown) do
      0 -> listed
      elided -> "#{listed} (+#{elided} more, not listed)"
    end
  end

  defp source(opts), do: Keyword.get(opts, :source, "MCP.Protocol.Extensions.normalise/2")
end

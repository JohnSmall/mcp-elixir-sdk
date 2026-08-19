defmodule MCP.Protocol.ExtensionsTest do
  @moduledoc """
  MES-16 — `MCP.Protocol.Extensions`: identifier validation, the reserved-prefix
  classifier, outbound normalisation, and the inbound read.

  **A7 — every test in this file is a positive control, not a caught
  regression.** "extension" occurred zero times in `lib/`, `test/` and
  `conformance/` before this ticket, so no test here can fail at a pre-fix SHA:
  there is no pre-fix behaviour to regress from. The assertions that would
  otherwise pass trivially were demonstrated red against deliberately-wrong
  fixtures before the module existed; that run is recorded on MES-16.

  Every rule asserted below is cited to the published-final `2026-07-28` schema
  at commit `5f5440bb26a62e2cf3440b92da5a667efa03b267`,
  `schema/2026-07-28/schema.ts` — never to the ticket brief.
  """
  use ExUnit.Case, async: true

  # The drop-and-warn posture (R-2/R-3) means the tests that exercise a bad
  # declaration legitimately log; captured so a green run stays readable, and
  # the log is still printed for any test that fails.
  @moduletag :capture_log

  import ExUnit.CaptureLog

  alias MCP.Protocol.Extensions

  doctest MCP.Protocol.Extensions

  describe "valid_identifier?/1 — the mandatory prefix (T13)" do
    # schema.ts:779-780 (client) / :876-877 (server): "Keys MUST follow the
    # `_meta` key naming rules, with a mandatory prefix." The mandatory prefix
    # is the single point at which an extension identifier is stricter than a
    # `_meta` key generally, which is why the two predicates are separate.
    test "a prefix is required, where `_meta` keys generally make it optional" do
      assert Extensions.valid_meta_key?("tasks")
      refute Extensions.valid_identifier?("tasks")

      assert Extensions.valid_meta_key?("io.modelcontextprotocol/tasks")
      assert Extensions.valid_identifier?("io.modelcontextprotocol/tasks")
    end

    # schema.ts:43 — labels start with a letter, end with a letter or digit,
    # interior may be letters, digits or hyphens.
    test "label rules" do
      assert Extensions.valid_identifier?("com.example/thing")
      assert Extensions.valid_identifier?("a/thing")
      assert Extensions.valid_identifier?("com.ex-ample.v2/thing")

      refute Extensions.valid_identifier?("1com.example/thing")
      refute Extensions.valid_identifier?("com-.example/thing")
      refute Extensions.valid_identifier?("-com.example/thing")
      refute Extensions.valid_identifier?(".com/thing")
      refute Extensions.valid_identifier?("com./thing")
      refute Extensions.valid_identifier?("com..example/thing")
      refute Extensions.valid_identifier?("com_example/thing")

      # R-1 (round 1). `\n` is not a letter, digit or hyphen, so a label ending
      # in one violates :43 — but PCRE's `$` matches immediately BEFORE a final
      # newline, so the original `^…$` anchoring accepted it and `normalise/1`
      # put it on the wire. Fixed by `\A … \z`. The `\r` case is the control
      # that shows what the pattern was already doing correctly: `$` has no such
      # exemption for a carriage return, so only `\n` ever slipped through, and
      # a fix that merely widened the character class would not explain that.
      refute Extensions.valid_identifier?("com.example\n/thing")
      refute Extensions.valid_meta_key?("com.example\n/thing")
      refute Extensions.valid_identifier?("com.example\r/thing")
    end

    # schema.ts:48-49 — the name starts and ends alphanumeric; interior may be
    # alphanumeric, hyphens, underscores or dots.
    test "name rules" do
      assert Extensions.valid_identifier?("com.example/a-b_c.d2")
      assert Extensions.valid_identifier?("com.example/x")

      refute Extensions.valid_identifier?("com.example/-thing")
      refute Extensions.valid_identifier?("com.example/thing-")
      refute Extensions.valid_identifier?("com.example/_thing")
      refute Extensions.valid_identifier?("com.example/thing.")
      refute Extensions.valid_identifier?("com.example/th ing")

      # R-1 again, on the name segment: :48-49 requires the name to END
      # alphanumeric, and `\n` is not. Three shapes because the hole was in the
      # shared anchoring, not in one pattern: a name ending in `\n`, a name that
      # is ONLY `\n` (which the "unless empty" alternative made especially easy
      # to miss), and the same key with a `\r` control.
      refute Extensions.valid_identifier?("com.example/thing\n")
      refute Extensions.valid_identifier?("com.example/\n")
      refute Extensions.valid_meta_key?("thing\n")
      refute Extensions.valid_identifier?("com.example/thing\r")
    end

    # schema.ts:48 says the name rule applies "unless empty" — so an empty name
    # is permitted, and a bare prefix is a valid key. Pinned deliberately rather
    # than left to chance: it is a corner a stricter reading would reject, and
    # only the schema decides which reading ships.
    test "an empty name is permitted (schema.ts:48, 'unless empty')" do
      assert Extensions.valid_identifier?("com.example/")
      assert Extensions.valid_identifier?("io.modelcontextprotocol/")
    end

    # The corner immediately next door, and the opposite answer. :48's "unless
    # empty" licenses an empty NAME after a prefix; the empty STRING has no
    # prefix and no name, and is not a key. Asserted beside the test above
    # rather than apart from it, because the two look alike and only one of
    # them is the schema's exception.
    test "the empty string is not a key, though an empty name after a prefix is" do
      refute Extensions.valid_meta_key?("")
      refute Extensions.valid_identifier?("")
      assert Extensions.valid_meta_key?("com.example/")
    end

    test "a key may carry at most one slash" do
      refute Extensions.valid_identifier?("com.example/a/b")
      refute Extensions.valid_meta_key?("com.example/a/b")
    end

    test "non-binary input is not a key" do
      for input <- [nil, :tasks, 42, %{}, ["com.example/x"]] do
        refute Extensions.valid_identifier?(input)
        refute Extensions.valid_meta_key?(input)
      end
    end
  end

  describe "reserved_prefix?/1 — the schema's own worked examples (T13)" do
    # schema.ts:45 enumerates exactly these five. Using the schema's examples
    # rather than invented ones means the test agrees with the normative text by
    # construction and not by our paraphrase of it.
    test "the four reserved examples" do
      assert Extensions.reserved_prefix?("io.modelcontextprotocol/")
      assert Extensions.reserved_prefix?("dev.mcp/")
      assert Extensions.reserved_prefix?("org.modelcontextprotocol.api/")
      assert Extensions.reserved_prefix?("com.mcp.tools/")
    end

    test "the one NOT reserved — second label is `example`, not `mcp`" do
      refute Extensions.reserved_prefix?("com.example.mcp/")
    end

    test "classifies a full identifier as well as a bare prefix" do
      assert Extensions.reserved_prefix?("io.modelcontextprotocol/tasks")
      refute Extensions.reserved_prefix?("com.example.mcp/thing")
    end

    # The rule at :45 is written about the SECOND label. A prefix with only one
    # label has no second label, so the rule does not fire — stated here so the
    # reading is pinned rather than inferred from an absent test.
    test "a single-label prefix is not reserved (the rule names the second label)" do
      refute Extensions.reserved_prefix?("mcp/thing")
      refute Extensions.reserved_prefix?("modelcontextprotocol/thing")
    end

    test "a key with no prefix is not reserved" do
      refute Extensions.reserved_prefix?("tasks")
      refute Extensions.reserved_prefix?(nil)
    end

    # schema.ts:45 is silent on case and reverse-DNS labels are conventionally
    # case-insensitive, so this could reasonably go either way. It goes the
    # case-sensitive way, and that is now written on `reserved_prefix?/1`
    # rather than left for a consumer to discover — pinned here so the doc
    # cannot drift away from the behaviour it describes. The SDK never acts on
    # the predicate, so nothing on the wire depends on this.
    test "the comparison is case-sensitive (a stated decision, not an accident)" do
      refute Extensions.reserved_prefix?("io.ModelContextProtocol/tasks")
      refute Extensions.reserved_prefix?("dev.MCP/tasks")
      assert Extensions.reserved_prefix?("io.modelcontextprotocol/tasks")
    end
  end

  describe "normalise/1 — outbound validation (T2, T14)" do
    test "keeps valid identifiers with object settings" do
      declared = %{
        "io.modelcontextprotocol/tasks" => %{},
        "com.example/thing" => %{"mode" => "fast"}
      }

      assert Extensions.normalise(declared) == declared
    end

    test "drops identifiers that violate the naming rules" do
      declared = %{
        "com.example/kept" => %{},
        "no-prefix" => %{},
        "1bad.prefix/x" => %{},
        "com.example/-bad" => %{}
      }

      assert Extensions.normalise(declared) == %{"com.example/kept" => %{}}
    end

    test "drops settings values that are not objects" do
      declared = %{
        "com.example/kept" => %{},
        "com.example/number" => 1,
        "com.example/string" => "yes",
        "com.example/null" => nil
      }

      assert Extensions.normalise(declared) == %{"com.example/kept" => %{}}
    end

    # R-2 (round 1). "Object" cannot mean `is_map/1`: a map holding a tuple, a
    # pid or a struct with no `Jason.Encoder` is map-shaped and still cannot be
    # encoded. Before the fix each of these was KEPT, and the failure surfaced
    # at the first `server/discover` as a raise out of Jason — every request,
    # forever, arbitrarily far from the launch config that caused it. The
    # question the predicate now asks is the one that actually matters: can the
    # encoder that will have to do this do it?
    test "drops settings that are map-shaped but not encodable as a JSON object" do
      declared = %{
        "com.example/kept" => %{"n" => 1},
        "com.example/tuple" => %{"t" => {1, 2}},
        "com.example/pid" => %{"p" => self()},
        "com.example/struct-value" => %{"s" => %URI{}}
      }

      assert capture_log(fn ->
               assert Extensions.normalise(declared) == %{"com.example/kept" => %{"n" => 1}}
             end) =~ "DROPPED"
    end

    # R-7 (round 2), and the case the suite could not see. The predicate asked
    # `is_map/1` and "does it encode?" and called the answer "is it a JSON
    # object?". Those two come apart on any struct whose encoder emits a
    # non-object, and reaching one takes no custom `Jason.Encoder` at all:
    # `Jason.encode(~D[2026-08-19])` is `{:ok, "\"2026-08-19\""}`, a JSON
    # STRING. Every value below was KEPT and advertised — the server seam put
    # `{"com.example/date":"2026-08-19"}` on the wire, against schema.ts:785
    # and :882, which require `{ [key: string]: JSONObject }` (:12).
    #
    # The whole suite stayed green with the fixed predicate applied, so nothing
    # that already existed discriminated the fixed predicate from the broken
    # one; the test above covers only the UNencodable side. This is that
    # discrimination, and it is R-1's shape a third time — the suite had been
    # written from the failure mode we had already named.
    test "drops settings that encode, but not to a JSON object" do
      declared = %{
        "com.example/kept" => %{"n" => 1},
        "com.example/date" => ~D[2026-08-19],
        "com.example/time" => ~T[10:30:00],
        "com.example/naive" => ~N[2026-08-19 10:30:00],
        "com.example/datetime" => DateTime.from_naive!(~N[2026-08-19 10:30:00], "Etc/UTC")
      }

      log =
        capture_log(fn ->
          assert Extensions.normalise(declared) == %{"com.example/kept" => %{"n" => 1}}
        end)

      assert log =~ "4 declaration(s) DROPPED"
      assert log =~ "settings are not a JSON object"
    end

    # The control for the test above, and the reason the fix checks the
    # ENCODING rather than banning structs: a struct that derives
    # `Jason.Encoder` really does encode to `{…}`, so it really is a JSON
    # object and it is kept. Without this, "drop non-objects" would be
    # satisfied by "drop every struct" — a rule about Elixir types rather than
    # about JSON, and a silent drop of a legitimate declaration.
    test "keeps a struct whose ENCODING is a JSON object" do
      settings = %MCP.Protocol.Types.Implementation{name: "x", version: "1"}
      declared = %{"com.example/derived-struct" => settings}

      assert match?({:ok, "{" <> _rest}, Jason.encode(settings))
      assert capture_log(fn -> assert Extensions.normalise(declared) == declared end) == ""
    end

    # The whole `:extensions` value, not an entry in it. A struct is a map, so
    # it passed `is_map/1` and then raised `Protocol.UndefinedError` out of the
    # comprehension — a launch-time crash from a launch-time typo, which is the
    # one outcome the drop-and-warn posture exists to rule out. Nothing a
    # consumer can pass here raises.
    test "a non-object :extensions value is dropped whole, never raised on" do
      # `%Implementation{}` derives `Jason.Encoder`, so this is not about
      # encodability: a struct is not a declaration whatever it encodes to, and
      # it is the shape that used to raise.
      for declared <- [%MCP.Protocol.Types.Implementation{}, %URI{}, "not a map", 42, [a: 1]] do
        assert capture_log(fn -> assert Extensions.normalise(declared) == nil end) =~
                 "not an object"
      end

      # `nil` is the DEFAULT, not a mistake: it is what a consumer who declared
      # nothing has. It must be silent, or every server that never touched the
      # option warns at every launch.
      assert capture_log(fn -> assert Extensions.normalise(nil) == nil end) == ""
    end

    # Dropping alone leaves a server that silently never advertises an
    # extension it does implement, with nothing anywhere saying why. The
    # warning names the identifier and the reason, and the seam, so the reader
    # is told which option they got wrong.
    test "the warning names each dropped identifier, its reason, and the seam" do
      log =
        capture_log(fn ->
          Extensions.normalise(
            %{"no-prefix" => %{}, "com.example/bad-settings" => %{"t" => {1, 2}}},
            source: "MY.Seam"
          )
        end)

      assert log =~ "MY.Seam"
      assert log =~ "2 declaration(s) DROPPED"
      assert log =~ ~s("no-prefix")
      assert log =~ "not a valid extension identifier"
      assert log =~ ~s("com.example/bad-settings")
      assert log =~ "settings are not a JSON object"
    end

    # R-10 (round 2). The enumeration is unbounded in the number of
    # declarations the consumer wrote — 500 bad ones made a single 42,004-byte
    # log line, most of it the same reason string repeated verbatim. It is the
    # operator's own launch config, read once, so this is legibility rather
    # than an attack surface; the part that is not merely cosmetic is that a
    # cap must SAY what it hid, or the line is a silent drop of its own.
    test "a large drop is grouped by reason and capped, and the line says how many it elided" do
      declared = Map.new(1..500, fn n -> {"bad-#{n}", %{}} end)

      log = capture_log(fn -> assert Extensions.normalise(declared) == nil end)

      assert log =~ "500 declaration(s) DROPPED"
      assert log =~ "(+490 more, not listed)"
      # One reason, stated once, not 500 times.
      assert length(String.split(log, "not a valid extension identifier")) == 2
      assert byte_size(log) < 2_000
    end

    # R-11 (round 2). The reduce behind the warning runs over a MAP, whose
    # iteration order is arbitrary — the reviewer's 1..500 run came out
    # starting at "bad-127" — so the `Enum.reverse/1` that used to be here was
    # restoring an order that never existed. Sorted instead, which is an order
    # the code can actually promise.
    test "the named identifiers are in a deterministic order" do
      declared = Map.new(["c.example/x", "a.example/x", "b.example/x"], &{&1, {:not, :json}})

      log = capture_log(fn -> assert Extensions.normalise(declared) == nil end)

      assert log =~ ~s("a.example/x", "b.example/x", "c.example/x")
    end

    # The silence half. A warning that fires on a correct declaration would be
    # trained away within a week, and then the noisy one nobody reads is the
    # only diagnostic left for the case that matters.
    test "a wholly valid declaration warns about nothing" do
      log =
        capture_log(fn ->
          assert Extensions.normalise(%{"io.modelcontextprotocol/tasks" => %{}}) != nil
        end)

      assert log == ""
    end

    # T2's unit half: empty and all-dropped both become nil, which is what the
    # capability encoders drop. `{}` on the wire would claim "I do extensions,
    # none of them"; nil makes no claim at all.
    test "an empty or fully-dropped declaration becomes nil, not %{}" do
      assert Extensions.normalise(%{}) == nil
      assert Extensions.normalise(%{"no-prefix" => %{}}) == nil
      assert Extensions.normalise(nil) == nil
      assert Extensions.normalise("not a map") == nil
    end

    # T14: pins the D-4 adjudication as behaviour rather than prose. Declaring
    # support for an official extension IS a reserved-prefix identifier — the
    # schema's own ServerCapabilities example is `io.modelcontextprotocol/tasks`
    # — so a block here would break the common legitimate case.
    test "a reserved-prefix declaration is NOT blocked" do
      declared = %{"io.modelcontextprotocol/tasks" => %{}}

      assert Extensions.reserved_prefix?("io.modelcontextprotocol/tasks")
      assert Extensions.normalise(declared) == declared
    end
  end

  describe "from_meta/1 — the inbound read (T12)" do
    @key "io.modelcontextprotocol/clientCapabilities"

    test "reads the peer's declared extensions" do
      meta = %{@key => %{"extensions" => %{"io.modelcontextprotocol/tasks" => %{}}}}
      assert Extensions.from_meta(meta) == %{"io.modelcontextprotocol/tasks" => %{}}
    end

    test "returns %{} for nil, an absent key, or an absent extensions field" do
      assert Extensions.from_meta(nil) == %{}
      assert Extensions.from_meta(%{}) == %{}
      assert Extensions.from_meta(%{@key => %{}}) == %{}
      assert Extensions.from_meta(%{"other" => "thing"}) == %{}
    end

    # R-4 (round 1). Outbound this module is emphatic that `{}` and absent are
    # DIFFERENT claims — `{}` says "I do extensions, none of them" and absent
    # makes no claim — and inbound it collapses them. That is deliberate: we
    # support zero, so a peer claiming none and a peer claiming nothing are the
    # same peer to us. It was only ever asserted for the omission half, which
    # left the collapse looking like an oversight rather than a decision; both
    # halves are pinned here, and the reasoning is now on `from_meta/1`.
    test "a peer's `{}` and an omitted key collapse to the same %{} (deliberately)" do
      assert Extensions.from_meta(%{@key => %{"extensions" => %{}}}) == %{}
      assert Extensions.from_meta(%{@key => %{}}) == %{}
    end

    # The shape guard, and the whole of it: a handler is never handed a crash.
    test "returns %{} when the shape is wrong rather than raising" do
      assert Extensions.from_meta(%{@key => "not an object"}) == %{}
      assert Extensions.from_meta(%{@key => %{"extensions" => "not an object"}}) == %{}
      assert Extensions.from_meta(%{@key => %{"extensions" => nil}}) == %{}
      assert Extensions.from_meta("not a map") == %{}
    end

    # Inbound is deliberately NOT validated (D-4). A key we would refuse to emit
    # still reaches the handler verbatim, because silently rewriting a peer's
    # claim would misreport what the peer actually said. This asserts the
    # difference between the two directions directly, so the split cannot decay
    # into "validate everywhere" without a test going red.
    test "does NOT validate: a malformed identifier reaches the caller verbatim" do
      malformed = %{"no-prefix" => %{}, "com.example/-bad" => %{"x" => 1}}
      meta = %{@key => %{"extensions" => malformed}}

      assert Extensions.from_meta(meta) == malformed
      refute Extensions.valid_identifier?("no-prefix")
      assert Extensions.normalise(malformed) == nil
    end

    # schema.ts:96 — "Servers MUST NOT infer capabilities from prior requests."
    # Held by shape here: the answer is a function of the argument, so there is
    # no state in which a previous request's declaration could survive.
    test "caches nothing between calls" do
      declared = %{@key => %{"extensions" => %{"com.example/thing" => %{}}}}

      assert Extensions.from_meta(declared) == %{"com.example/thing" => %{}}
      assert Extensions.from_meta(%{}) == %{}
      assert Extensions.from_meta(nil) == %{}
    end
  end
end

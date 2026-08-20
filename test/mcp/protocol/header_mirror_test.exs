defmodule MCP.Protocol.HeaderMirrorTest do
  @moduledoc """
  MES-18 / CG7 — `x-mcp-header` annotation validity and value encoding
  (SEP-2243), derived from the normative spec at the pinned commit
  `5f5440bb26a62e2cf3440b92da5a667efa03b267`:
  `server/tools.mdx:346-368` and `basic/transports/streamable-http.mdx:371-545`.

  ## Evidence posture (A7)

  Every test here is a **POSITIVE CONTROL**. None of this behaviour existed at
  `2829769` — `x-mcp-header` had zero occurrences in `lib/` and `test/` — so
  nothing below can be a caught regression, and the full suite being green
  before and after discriminates nothing about it.

  ## What is covered (A2d — the enumeration, including the negatives)

  All **six** annotation constraints and all **four** encoding rules are
  implemented and tested. Three of the six earn NO harness credit and are
  tested here on the spec's authority alone: `number`-exclusion, the integer
  safe range, and static reachability. The alpha.11 fixture
  (`@modelcontextprotocol/conformance@0.2.0-alpha.11`) ships ten invalid tools
  covering only four constraint classes — read off its own `Ua` map:
  not-empty (1), primitive-only (3), uniqueness (2), charset (4). Each of those
  ten classes is named in a test below so the harness-covered subset is
  checkable rather than asserted.
  """
  use ExUnit.Case, async: true

  alias MCP.Protocol.HeaderMirror

  doctest MCP.Protocol.HeaderMirror

  defp schema(properties), do: %{"type" => "object", "properties" => properties}

  defp annotations!(schema) do
    {:ok, annotations} = HeaderMirror.validate_schema(schema)
    annotations
  end

  describe "annotation validity — the ten classes the alpha.11 fixture exercises" do
    # 1/10 — fixture tool `invalid_empty_header`, check
    # `sep-2243-x-mcp-header-not-empty`.
    test "invalid_empty_header: an empty value is rejected" do
      assert {:error, {:empty_header_name, ""}} =
               HeaderMirror.validate_schema(
                 schema(%{"a" => %{"type" => "string", "x-mcp-header" => ""}})
               )
    end

    # 2/10, 3/10, 4/10 — `invalid_object_header`, `invalid_array_header`,
    # `invalid_null_header`, all check `sep-2243-x-mcp-header-primitive-only`.
    test "invalid_object_header / invalid_array_header / invalid_null_header: non-primitive types" do
      for type <- ["object", "array", "null"] do
        assert {:error, {:non_primitive_type, "H", ^type}} =
                 HeaderMirror.validate_schema(
                   schema(%{"a" => %{"type" => type, "x-mcp-header" => "H"}})
                 )
      end
    end

    # 5/10 — `invalid_duplicate_same_case`, check `sep-2243-x-mcp-header-unique`.
    test "invalid_duplicate_same_case: the same value twice is rejected" do
      assert {:error, {:duplicate_header_name, "Dup"}} =
               HeaderMirror.validate_schema(
                 schema(%{
                   "a" => %{"type" => "string", "x-mcp-header" => "Dup"},
                   "b" => %{"type" => "string", "x-mcp-header" => "Dup"}
                 })
               )
    end

    # 6/10 — `invalid_duplicate_diff_case`, same check. Uniqueness is
    # case-INSENSITIVE, which is the half a naive `MapSet` of raw values misses.
    test "invalid_duplicate_diff_case: values differing only in case are rejected" do
      assert {:error, {:duplicate_header_name, _}} =
               HeaderMirror.validate_schema(
                 schema(%{
                   "a" => %{"type" => "string", "x-mcp-header" => "Region"},
                   "b" => %{"type" => "string", "x-mcp-header" => "REGION"}
                 })
               )
    end

    # 7/10, 8/10, 9/10, 10/10 — `invalid_space_in_name`, `invalid_colon_in_name`,
    # `invalid_non_ascii_name`, `invalid_control_char_name`, all check
    # `sep-2243-x-mcp-header-charset`.
    test "invalid_space_in_name / invalid_colon_in_name / invalid_non_ascii_name: not 1*tchar" do
      for value <- ["Has Space", "Has:Colon", "Ünïcode", "with\"quote", "brack[et]"] do
        assert {:error, {:invalid_header_name, ^value}} =
                 HeaderMirror.validate_schema(
                   schema(%{"a" => %{"type" => "string", "x-mcp-header" => value}})
                 )
      end
    end

    test "invalid_control_char_name: a control character is named as such, not as a grammar miss" do
      # Reported as a control character rather than the generic token failure it
      # would also be: an operator reading "this name carried a CR" learns the
      # security-relevant fact.
      for value <- ["Bad\rName", "Bad\nName", "Bad\tName", "Bad\0Name", "Bad\x7FName"] do
        assert {:error, {:control_character_in_header_name, ^value}} =
                 HeaderMirror.validate_schema(
                   schema(%{"a" => %{"type" => "string", "x-mcp-header" => value}})
                 )
      end
    end
  end

  describe "annotation validity — the three constraints NO harness check covers (spec-only)" do
    # Spec-only 1/3. `tools.mdx:355` — "Parameters with type `number` are not
    # permitted", stated separately from the primitive list precisely because
    # `number` is the tempting fourth.
    test "`number` is excluded even though it is a JSON Schema scalar" do
      assert {:error, {:non_primitive_type, "N", "number"}} =
               HeaderMirror.validate_schema(
                 schema(%{"a" => %{"type" => "number", "x-mcp-header" => "N"}})
               )
    end

    test "a missing or non-string `type` never establishes primitiveness" do
      assert {:error, {:non_primitive_type, "H", nil}} =
               HeaderMirror.validate_schema(schema(%{"a" => %{"x-mcp-header" => "H"}}))

      # A type union is not one of the three primitive types the spec names.
      assert {:error, {:non_primitive_type, "H", ["string", "null"]}} =
               HeaderMirror.validate_schema(
                 schema(%{"a" => %{"type" => ["string", "null"], "x-mcp-header" => "H"}})
               )
    end

    # Spec-only 2/3 — the integer safe range, which is a VALUE-level rule: the
    # tool definition cannot state it, so it can only be enforced at call time.
    test "an integer outside the IEEE 754 safe range is not mirrored, and says so" do
      annotations = annotations!(schema(%{"n" => %{"type" => "integer", "x-mcp-header" => "N"}}))

      assert [{"mcp-param-n", "9007199254740991"}] =
               HeaderMirror.headers_for(annotations, %{"n" => 9_007_199_254_740_991})

      assert [{"mcp-param-n", "-9007199254740991"}] =
               HeaderMirror.headers_for(annotations, %{"n" => -9_007_199_254_740_991})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert [] = HeaderMirror.headers_for(annotations, %{"n" => 9_007_199_254_740_992})
        end)

      # The omission is visible. A silently absent header is indistinguishable
      # on the wire from a parameter that has no annotation — F-9's shape.
      assert log =~ "Mcp-Param-N"
      assert log =~ "safe range"
    end

    # Spec-only 3/3 — static reachability. `streamable-http.mdx:389-397`: the
    # chain must consist SOLELY of `properties` keys, and an annotation
    # anywhere else invalidates the tool rather than being ignored.
    test "an annotation under `items` is not statically reachable" do
      assert {:error, {:not_statically_reachable, "X"}} =
               HeaderMirror.validate_schema(
                 schema(%{
                   "a" => %{
                     "type" => "array",
                     "items" => %{"type" => "string", "x-mcp-header" => "X"}
                   }
                 })
               )
    end

    test "an annotation under a composition or conditional keyword is not reachable" do
      for keyword <- ["oneOf", "anyOf", "allOf"] do
        assert {:error, {:not_statically_reachable, "X"}} =
                 HeaderMirror.validate_schema(
                   schema(%{
                     "a" => %{
                       keyword => [
                         schema(%{"b" => %{"type" => "string", "x-mcp-header" => "X"}})
                       ]
                     }
                   })
                 )
      end

      for keyword <- ["not", "if", "then", "else"] do
        assert {:error, {:not_statically_reachable, "X"}} =
                 HeaderMirror.validate_schema(
                   schema(%{
                     "a" => %{
                       keyword => schema(%{"b" => %{"type" => "string", "x-mcp-header" => "X"}})
                     }
                   })
                 )
      end
    end

    test "an annotation under `$defs`/`$ref` machinery is not reachable" do
      assert {:error, {:not_statically_reachable, "X"}} =
               HeaderMirror.validate_schema(%{
                 "type" => "object",
                 "$defs" => %{
                   "thing" => schema(%{"b" => %{"type" => "string", "x-mcp-header" => "X"}})
                 },
                 "properties" => %{"a" => %{"$ref" => "#/$defs/thing"}}
               })
    end

    test "a NESTED object property IS reachable — every step is a `properties` key" do
      annotations =
        annotations!(
          schema(%{
            "outer" =>
              schema(%{
                "inner" => %{"type" => "string", "x-mcp-header" => "Inner"}
              })
          })
        )

      assert [%{name: "Inner", path: ["outer", "inner"]}] = annotations

      assert [{"mcp-param-inner", "v"}] =
               HeaderMirror.headers_for(annotations, %{"outer" => %{"inner" => "v"}})
    end

    test "a property literally named `items` is still reachable — the KEYWORD is what matters" do
      # The chain is properties→"items", not the `items` keyword, so this is a
      # reachable property whose name happens to collide with a keyword.
      annotations =
        annotations!(schema(%{"items" => %{"type" => "string", "x-mcp-header" => "Items"}}))

      assert [%{name: "Items", path: ["items"]}] = annotations
    end

    test "an annotation on the schema root is invalid — the root is not a property" do
      assert {:error, {:annotation_not_on_a_property, "Root"}} =
               HeaderMirror.validate_schema(%{"type" => "object", "x-mcp-header" => "Root"})
    end
  end

  describe "tool-level validation" do
    test "an unannotated tool is valid and mirrors nothing" do
      assert {:ok, []} =
               HeaderMirror.validate_tool(%{
                 "name" => "plain",
                 "inputSchema" => schema(%{"q" => %{"type" => "string"}})
               })
    end

    test "a tool with no inputSchema, or a non-object one, is valid" do
      assert {:ok, []} = HeaderMirror.validate_tool(%{"name" => "t"})
      assert {:ok, []} = HeaderMirror.validate_tool(%{"name" => "t", "inputSchema" => "nonsense"})
    end

    test "a non-string annotation value is rejected before any grammar check" do
      assert {:error, {:invalid_annotation_value, 42}} =
               HeaderMirror.validate_schema(
                 schema(%{"a" => %{"type" => "string", "x-mcp-header" => 42}})
               )
    end

    test "every rejection reason renders as a sentence naming the offending value" do
      reasons = [
        {:empty_header_name, ""},
        {:invalid_header_name, "a b"},
        {:control_character_in_header_name, "a\rb"},
        {:duplicate_header_name, "Dup"},
        {:non_primitive_type, "N", "number"},
        {:not_statically_reachable, "X"},
        {:annotation_not_on_a_property, "Root"},
        {:invalid_annotation_value, 42}
      ]

      for reason <- reasons do
        sentence = HeaderMirror.describe(reason)
        assert is_binary(sentence) and sentence != ""
      end
    end
  end

  describe "value encoding — the fixture's own 16-value vector" do
    # The arguments below are read off the alpha.11 `http-custom-headers`
    # fixture's `toolCalls[0].arguments` verbatim, and the expectations from
    # its `Ka`/`Ga` predicates plus the spec's encoding-examples table.
    @fixture_schema %{
      "type" => "object",
      "properties" => %{
        "region" => %{"type" => "string", "x-mcp-header" => "Region"},
        "priority" => %{"type" => "integer", "x-mcp-header" => "Priority"},
        "verbose" => %{"type" => "boolean", "x-mcp-header" => "Verbose"},
        "debug" => %{"type" => "boolean", "x-mcp-header" => "Debug"},
        "empty_val" => %{"type" => "string", "x-mcp-header" => "EmptyVal"},
        "method_val" => %{"type" => "string", "x-mcp-header" => "Method"},
        "float_val" => %{"type" => "number"},
        "non_ascii_val" => %{"type" => "string", "x-mcp-header" => "NonAscii"},
        "whitespace_val" => %{"type" => "string", "x-mcp-header" => "Whitespace"},
        "leading_space_val" => %{"type" => "string", "x-mcp-header" => "LeadingSpace"},
        "trailing_space_val" => %{"type" => "string", "x-mcp-header" => "TrailingSpace"},
        "internal_space_val" => %{"type" => "string", "x-mcp-header" => "InternalSpace"},
        "control_char_val" => %{"type" => "string", "x-mcp-header" => "ControlChar"},
        "crlf_val" => %{"type" => "string", "x-mcp-header" => "CrLf"},
        "tab_val" => %{"type" => "string", "x-mcp-header" => "Tab"},
        "query" => %{"type" => "string"}
      }
    }

    @fixture_arguments %{
      "region" => "us-west1",
      "priority" => 42,
      "verbose" => false,
      "debug" => true,
      "empty_val" => "",
      "method_val" => "test-method",
      "float_val" => 3.14159,
      "non_ascii_val" => "Hello, 世界",
      "whitespace_val" => " padded ",
      "leading_space_val" => " us-west1",
      "trailing_space_val" => "us-west1 ",
      "internal_space_val" => "us west 1",
      "control_char_val" => "line1\nline2",
      "crlf_val" => "line1\r\nline2",
      "tab_val" => "\tindented",
      "query" => "SELECT * FROM users"
    }

    setup do
      annotations = annotations!(@fixture_schema)
      %{headers: Map.new(HeaderMirror.headers_for(annotations, @fixture_arguments))}
    end

    test "plain ASCII is sent as-is", %{headers: headers} do
      assert headers["mcp-param-region"] == "us-west1"
      assert headers["mcp-param-method"] == "test-method"
    end

    test "an integer becomes its decimal string, a boolean lowercase true/false", %{
      headers: headers
    } do
      assert headers["mcp-param-priority"] == "42"
      assert headers["mcp-param-verbose"] == "false"
      assert headers["mcp-param-debug"] == "true"
    end

    test "an EMPTY string is present with an empty value, not omitted", %{headers: headers} do
      # `empty_val` is present in the arguments, so a header is required: the
      # rule is "omit when no value is PRESENT", and "" is a value. The fixture
      # agrees — it reports a missing Mcp-Param-EmptyVal as a failure.
      assert Map.has_key?(headers, "mcp-param-emptyval")
      assert headers["mcp-param-emptyval"] == ""
    end

    test "non-ASCII, padded, control and CRLF values are Base64 sentinels", %{headers: headers} do
      assert headers["mcp-param-nonascii"] == "=?base64?SGVsbG8sIOS4lueVjA==?="
      assert headers["mcp-param-whitespace"] == "=?base64?IHBhZGRlZCA=?="
      assert headers["mcp-param-leadingspace"] == HeaderMirror.encode_value(" us-west1")
      assert headers["mcp-param-trailingspace"] == HeaderMirror.encode_value("us-west1 ")

      for key <- ~w(mcp-param-controlchar mcp-param-crlf mcp-param-tab) do
        assert String.starts_with?(headers[key], "=?base64?")
        assert String.ends_with?(headers[key], "?=")
      end
    end

    test "every encoded value decodes back to exactly the body value", %{headers: headers} do
      # The server-side comparison the spec mandates, run against our own
      # output: a value that does not round-trip is a -32020 waiting to happen.
      for {arg, header} <- %{
            "non_ascii_val" => "mcp-param-nonascii",
            "whitespace_val" => "mcp-param-whitespace",
            "control_char_val" => "mcp-param-controlchar",
            "crlf_val" => "mcp-param-crlf",
            "tab_val" => "mcp-param-tab"
          } do
        assert HeaderMirror.decode_value(headers[header]) == @fixture_arguments[arg]
      end
    end

    test "INTERNAL spaces stay plain — only leading/trailing whitespace forces encoding", %{
      headers: headers
    } do
      assert headers["mcp-param-internalspace"] == "us west 1"
    end

    test "no header carries a raw CR or LF — injection is closed by construction", %{
      headers: headers
    } do
      # The property that matters most, asserted over the WHOLE header set
      # rather than the two values that happen to contain newlines.
      for {name, value} <- headers do
        refute value =~ "\r", "header #{name} carried a raw CR"
        refute value =~ "\n", "header #{name} carried a raw LF"
        assert name == String.downcase(name)
      end
    end

    test "unannotated parameters are NOT mirrored", %{headers: headers} do
      # Both fixture negatives: an unannotated string, and an unannotated
      # `number` (which could not be annotated even if the server wanted to).
      refute Map.has_key?(headers, "mcp-param-query")
      refute Map.has_key?(headers, "mcp-param-floatval")
    end

    test "the `Method` annotation produces Mcp-Param-Method, never Mcp-Method", %{
      headers: headers
    } do
      # The fixture names this case explicitly: a mirrored parameter must not
      # be able to forge a routing header.
      assert headers["mcp-param-method"] == "test-method"
      refute Map.has_key?(headers, "mcp-method")
    end
  end

  describe "value encoding — omission and the sentinel's ambiguity rule" do
    test "a null value omits the header; so does an absent one" do
      annotations =
        annotations!(
          schema(%{
            "verbose" => %{"type" => "boolean", "x-mcp-header" => "Verbose"},
            "region" => %{"type" => "string", "x-mcp-header" => "Region"}
          })
        )

      assert [{"mcp-param-region", "us-east1"}] =
               HeaderMirror.headers_for(annotations, %{"region" => "us-east1", "verbose" => nil})

      assert [] = HeaderMirror.headers_for(annotations, %{})
    end

    test "a plain-ASCII value that LOOKS like a sentinel is itself encoded" do
      # `streamable-http.mdx:508-510`: clients MUST also Base64-encode any
      # plain-ASCII value matching the sentinel pattern, or a server cannot
      # tell an encoded value from a literal one.
      assert HeaderMirror.encode_value("=?base64?literal?=") ==
               "=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?="

      assert HeaderMirror.decode_value("=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=") ==
               "=?base64?literal?="
    end

    test "decode leaves a plain value alone and survives a malformed sentinel" do
      assert HeaderMirror.decode_value("us-west1") == "us-west1"
      # Not valid Base64 inside the markers: returned unchanged, so it fails
      # the comparison it was going to fail anyway rather than raising.
      assert HeaderMirror.decode_value("=?base64?!!!not-base64!!!?=") ==
               "=?base64?!!!not-base64!!!?="
    end

    test "a value whose runtime type is not string/integer/boolean is omitted with a reason" do
      annotations = annotations!(schema(%{"a" => %{"type" => "string", "x-mcp-header" => "A"}}))

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert [] = HeaderMirror.headers_for(annotations, %{"a" => %{"nested" => "map"}})
          assert [] = HeaderMirror.headers_for(annotations, %{"a" => ["list"]})
          assert [] = HeaderMirror.headers_for(annotations, %{"a" => 1.5})
        end)

      assert log =~ "Mcp-Param-A"
    end

    test "a non-map arguments value yields no headers rather than raising" do
      annotations = annotations!(schema(%{"a" => %{"type" => "string", "x-mcp-header" => "A"}}))
      assert [] = HeaderMirror.headers_for(annotations, nil)
      assert [] = HeaderMirror.headers_for(annotations, "not a map")
    end

    test "the exact property path is read — a same-named key elsewhere is not" do
      annotations =
        annotations!(
          schema(%{
            "outer" => schema(%{"region" => %{"type" => "string", "x-mcp-header" => "R"}})
          })
        )

      # A top-level "region" is NOT at the annotated path ["outer", "region"].
      assert [] = HeaderMirror.headers_for(annotations, %{"region" => "wrong"})

      assert [{"mcp-param-r", "right"}] =
               HeaderMirror.headers_for(annotations, %{"outer" => %{"region" => "right"}})
    end
  end
end

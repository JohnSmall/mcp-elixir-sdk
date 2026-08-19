defmodule MCP.Protocol.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias MCP.Protocol.Capabilities.{ClientCapabilities, ServerCapabilities}

  describe "ServerCapabilities" do
    test "from_map/1 parses full capabilities" do
      map = %{
        "tools" => %{"listChanged" => true},
        "resources" => %{"subscribe" => true, "listChanged" => true},
        "prompts" => %{"listChanged" => true},
        "logging" => %{},
        "completions" => %{}
      }

      caps = ServerCapabilities.from_map(map)

      assert caps.tools.list_changed == true
      assert caps.resources.subscribe == true
      assert caps.resources.list_changed == true
      assert caps.prompts.list_changed == true
      assert %MCP.Protocol.Capabilities.LoggingCapabilities{} = caps.logging
      assert %MCP.Protocol.Capabilities.CompletionCapabilities{} = caps.completions
    end

    test "from_map/1 handles missing capabilities" do
      caps = ServerCapabilities.from_map(%{})

      assert caps.tools == nil
      assert caps.resources == nil
      assert caps.prompts == nil
      assert caps.logging == nil
      assert caps.completions == nil
    end

    test "from_map/1 handles experimental capabilities" do
      map = %{"experimental" => %{"custom" => %{"enabled" => true}}}
      caps = ServerCapabilities.from_map(map)
      assert caps.experimental == %{"custom" => %{"enabled" => true}}
    end

    test "round-trips through JSON" do
      map = %{
        "tools" => %{"listChanged" => true},
        "resources" => %{"subscribe" => true}
      }

      caps = ServerCapabilities.from_map(map)
      json = Jason.encode!(caps)
      decoded = Jason.decode!(json)

      assert decoded["tools"]["listChanged"] == true
      assert decoded["resources"]["subscribe"] == true
      refute Map.has_key?(decoded, "prompts")
      refute Map.has_key?(decoded, "logging")
    end
  end

  describe "ClientCapabilities" do
    test "from_map/1 parses full capabilities" do
      map = %{
        "roots" => %{"listChanged" => true},
        "sampling" => %{},
        "elicitation" => %{"form" => %{}, "url" => %{}}
      }

      caps = ClientCapabilities.from_map(map)

      assert caps.roots.list_changed == true
      assert %MCP.Protocol.Capabilities.SamplingCapabilities{} = caps.sampling
      assert caps.elicitation.form == %{}
      assert caps.elicitation.url == %{}
    end

    test "from_map/1 handles empty map" do
      caps = ClientCapabilities.from_map(%{})

      assert caps.roots == nil
      assert caps.sampling == nil
      assert caps.elicitation == nil
    end

    test "round-trips through JSON" do
      map = %{
        "roots" => %{"listChanged" => true},
        "sampling" => %{}
      }

      caps = ClientCapabilities.from_map(map)
      json = Jason.encode!(caps)
      decoded = Jason.decode!(json)

      assert decoded["roots"]["listChanged"] == true
      assert decoded["sampling"] == %{}
      refute Map.has_key?(decoded, "elicitation")
    end
  end

  # MES-16 — `extensions` (SEP-2133) and `experimental` are DIFFERENT fields and
  # must stay different on the wire. schema.ts:720/:797 declare `experimental`
  # ("Experimental, non-standard capabilities", free-form); schema.ts:785/:882
  # declare `extensions` (SEP-2133 identifiers, mandatory prefix). Reusing the
  # already-present-but-unused `experimental` field would have looked like
  # tidiness and been wrong.
  #
  # A7: positive controls, not caught regressions — `extensions` did not exist
  # in this codebase before MES-16, so no assertion here can fail at a pre-fix
  # SHA. Each asserts the value lands under its own key AND refutes its
  # appearance under the other, which is what makes the pair discriminating
  # rather than merely present.
  describe "extensions vs experimental — the 2x2 (T6-T9)" do
    @extensions %{"io.modelcontextprotocol/tasks" => %{}}
    @experimental %{"custom" => %{"enabled" => true}}

    test "T6 — ServerCapabilities encode keeps the two apart" do
      decoded =
        %ServerCapabilities{extensions: @extensions}
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["extensions"] == @extensions
      refute Map.has_key?(decoded, "experimental")

      decoded =
        %ServerCapabilities{experimental: @experimental}
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["experimental"] == @experimental
      refute Map.has_key?(decoded, "extensions")
    end

    test "T7 — ServerCapabilities decode keeps the two apart" do
      caps = ServerCapabilities.from_map(%{"extensions" => @extensions})
      assert caps.extensions == @extensions
      assert caps.experimental == nil

      caps = ServerCapabilities.from_map(%{"experimental" => @experimental})
      assert caps.experimental == @experimental
      assert caps.extensions == nil
    end

    test "T8 — ClientCapabilities encode keeps the two apart" do
      decoded =
        %ClientCapabilities{extensions: @extensions}
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["extensions"] == @extensions
      refute Map.has_key?(decoded, "experimental")

      decoded =
        %ClientCapabilities{experimental: @experimental}
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["experimental"] == @experimental
      refute Map.has_key?(decoded, "extensions")
    end

    test "T9 — ClientCapabilities decode keeps the two apart" do
      caps = ClientCapabilities.from_map(%{"extensions" => @extensions})
      assert caps.extensions == @extensions
      assert caps.experimental == nil

      caps = ClientCapabilities.from_map(%{"experimental" => @experimental})
      assert caps.experimental == @experimental
      assert caps.extensions == nil
    end

    test "both may be carried at once, each under its own key" do
      decoded =
        %ServerCapabilities{extensions: @extensions, experimental: @experimental}
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["extensions"] == @extensions
      assert decoded["experimental"] == @experimental
    end

    test "neither is emitted when unset" do
      decoded = %ServerCapabilities{} |> Jason.encode!() |> Jason.decode!()
      refute Map.has_key?(decoded, "extensions")
      refute Map.has_key?(decoded, "experimental")

      decoded = %ClientCapabilities{} |> Jason.encode!() |> Jason.decode!()
      refute Map.has_key?(decoded, "extensions")
      refute Map.has_key?(decoded, "experimental")
    end
  end
end

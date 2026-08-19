defmodule MCP.Server.CapabilityHonestyTest do
  @moduledoc """
  MES-15 C3 — a capability is a claim, and `main` was making three it could not
  keep.

  Before this fix `Config.detect_capabilities/1` set `listChanged: true` for
  tools, resources and prompts whenever the corresponding list callback
  existed. Since Sprint 3 deleted the standing GET stream there has been **no
  mechanism in `lib/` by which any `list_changed` notification could reach any
  client** — the only occurrences of `list_changed` outside these capability
  structs are the method-name constants. So the advertisement was false on
  `main`, independently of `subscriptions/listen`.

  These are **regression** tests in A7's strict sense, not positive controls:
  the first two assertions fail against the pre-fix `detect_capabilities/1`,
  which returns `listChanged: true` for a handler that can deliver nothing.
  """
  use ExUnit.Case, async: true

  alias MCP.Protocol.Capabilities.ServerCapabilities
  alias MCP.Server.Config
  alias MCP.Test.{CapabilityProbeHandler, StatelessHandler}

  describe "a listChanged claim needs a channel to honour it on" do
    test "a handler with list callbacks but no handle_listen/3 advertises no listChanged" do
      # THE C3 REGRESSION. StatelessHandler implements all three list callbacks
      # and nothing else; on the pre-fix builder this returned listChanged: true
      # three times over.
      caps = Config.detect_capabilities(StatelessHandler, streaming: true)

      assert caps.tools.list_changed == nil
      assert caps.resources.list_changed == nil
      assert caps.prompts.list_changed == nil

      # The capabilities themselves still appear — the server does have tools,
      # resources and prompts. It is only the notification claim that is gone.
      assert caps.tools
      assert caps.resources
      assert caps.prompts
    end

    test "the arity-1 call, unchanged across the fix, is the cross-SHA regression" do
      # `detect_capabilities/1` is callable on BOTH sides of this change (before:
      # the only arity; after: the arity-2 default). Running this exact
      # assertion at the pre-fix SHA fails with a plain assertion error rather
      # than an UndefinedFunctionError, which is what makes it evidence of a
      # caught regression rather than of a signature change.
      caps = Config.detect_capabilities(StatelessHandler)

      assert caps.tools.list_changed == nil
      assert caps.resources.list_changed == nil
      assert caps.prompts.list_changed == nil
    end

    test "absent, not present-and-false: the key never reaches the wire" do
      # `false` would be a different claim ("I support the concept and decline")
      # and is not what a server without the feature has ever sent. Assert the
      # encoded shape, since that is what a client actually reads.
      wire =
        StatelessHandler
        |> Config.detect_capabilities(streaming: true)
        |> Jason.encode!()
        |> Jason.decode!()

      assert wire["tools"] == %{}
      assert wire["prompts"] == %{}
      assert wire["resources"] == %{}
      refute Map.has_key?(wire["tools"], "listChanged")
    end

    test "a handler that CAN deliver earns the advertisement back" do
      caps = Config.detect_capabilities(CapabilityProbeHandler, streaming: true)

      assert caps.tools.list_changed == true
      assert caps.resources.list_changed == true
      assert caps.prompts.list_changed == true
    end

    test "the same handler behind a non-streaming driver advertises nothing" do
      # JSON mode cannot hold a stream, so this deployment has no channel — the
      # handler's ability is irrelevant. This is the half of C3 that survives
      # even once subscriptions/listen exists.
      caps = Config.detect_capabilities(CapabilityProbeHandler, streaming: false)

      assert caps.tools.list_changed == nil
      assert caps.resources.list_changed == nil
      assert caps.prompts.list_changed == nil
    end

    test "streaming defaults to false — omission cannot over-claim" do
      assert Config.detect_capabilities(CapabilityProbeHandler) ==
               Config.detect_capabilities(CapabilityProbeHandler, streaming: false)
    end
  end

  describe "resources.subscribe is declared, never inferred" do
    test "not advertised without an explicit declaration, even when deliverable" do
      # StatelessHandler has resources and (in this call) a streaming driver,
      # but declares nothing and has no handle_listen/3. Per-URI watching is
      # never implied.
      caps = Config.detect_capabilities(StatelessHandler, streaming: true)
      assert caps.resources.subscribe == nil
    end

    test "advertised when the handler declares resourceSubscriptions" do
      caps = Config.detect_capabilities(CapabilityProbeHandler, streaming: true)
      assert caps.resources.subscribe == true
      assert "resourceSubscriptions" in CapabilityProbeHandler.supported_subscriptions()
    end
  end

  describe "the driver's declaration reaches the built config" do
    test "Config.build/2 records :streaming and applies it to capabilities" do
      {:ok, streaming} = Config.build(CapabilityProbeHandler, streaming: true)
      {:ok, json_mode} = Config.build(CapabilityProbeHandler, streaming: false)

      assert streaming.streaming == true
      assert json_mode.streaming == false

      assert %ServerCapabilities{tools: %{list_changed: true}} = streaming.capabilities
      assert %ServerCapabilities{tools: %{list_changed: nil}} = json_mode.capabilities
    end

    test "Config.build/2 defaults :streaming to false" do
      {:ok, config} = Config.build(CapabilityProbeHandler, [])
      assert config.streaming == false
    end
  end
end

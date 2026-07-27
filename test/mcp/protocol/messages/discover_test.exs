defmodule MCP.Protocol.Messages.DiscoverTest do
  use ExUnit.Case, async: true

  alias MCP.Protocol.Capabilities.ServerCapabilities
  alias MCP.Protocol.Messages.Discover
  alias MCP.Protocol.Types.Implementation

  # Wire shape pinned to draft schema 7634684382c3d14cf7e9f14073fe40a2d8ace3fa
  # (DiscoverResult extends CacheableResult): supportedVersions + resultType/
  # ttlMs/cacheScope; serverInfo under _meta["io.modelcontextprotocol/serverInfo"].

  test "to_map/1 produces the schema shape" do
    result = %Discover.Result{
      supported_versions: ["2026-07-28"],
      capabilities: %ServerCapabilities{},
      server_info: %Implementation{name: "mcp_elixir_sdk", version: "2.0.0"},
      instructions: "hello"
    }

    map = Discover.Result.to_map(result)

    assert map["supportedVersions"] == ["2026-07-28"]
    assert map["resultType"] == "complete"
    assert map["ttlMs"] == 0
    assert map["cacheScope"] == "public"
    assert map["instructions"] == "hello"
    assert is_map(map["capabilities"])
    assert map["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "mcp_elixir_sdk"
    # server identity is NOT top-level; supportedVersions replaces protocolVersions
    refute Map.has_key?(map, "serverInfo")
    refute Map.has_key?(map, "protocolVersions")
  end

  test "from_map/1 round-trips the schema shape" do
    map = %{
      "supportedVersions" => ["2026-07-28"],
      "capabilities" => %{},
      "resultType" => "complete",
      "ttlMs" => 0,
      "cacheScope" => "public",
      "_meta" => %{"io.modelcontextprotocol/serverInfo" => %{"name" => "s", "version" => "2.0.0"}}
    }

    result = Discover.Result.from_map(map)
    assert result.supported_versions == ["2026-07-28"]
    assert result.cache_scope == "public"
    assert result.server_info.name == "s"
  end
end

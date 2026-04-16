# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-04-16

### Changed
- **Renamed package** from `mcp_ex` to `mcp_elixir_sdk` (the `mcp_ex` hex name was previously taken by another client-only library). The new name follows the official MCP SDK naming convention (`mcp-go-sdk`, `mcp-python-sdk`, `mcp-ruby-sdk`, `mcp-typescript-sdk`).
- Top-level OTP application module renamed from `McpEx.Application` to `MCPElixirSDK.Application` (internal, not part of the public API).
- Default `client_info`/`server_info` name updated to `mcp_elixir_sdk`.

### Note
Public module names under the `MCP.*` namespace (e.g. `MCP.Client`, `MCP.Server`, `MCP.Server.Handler`, `MCP.Transport.*`) are unchanged, so existing code using these modules continues to work — only the dependency declaration needs updating.

## [1.0.0] - 2026-04-16

### Added
- First stable release (never published to hex — superseded by 1.0.1 due to package rename)
- 100% MCP conformance (Tier 1, 30/30 scenarios, 40/40 checks)
- Full hex package metadata, documentation, and usage rules for AI agents

## [0.2.3] - 2025-02-17

### Changed
- Updated documentation paths after workspace reorganization

## [0.2.2] - 2025-02-11

### Added
- Documented sampling timeout behavior over HTTP transport
- Added link to mcp_ex_examples repo in README

## [0.2.1] - 2025-02-11

### Changed
- Rewrote README with accurate usage examples

## [0.2.0] - 2025-02-09

### Added
- 100% MCP conformance (Tier 1) — 30/30 scenarios, 40/40 checks
- Async tool execution with `handle_call_tool/4` and `ToolContext`
- SSE streaming for intermediate messages during tool execution
- Client features: sampling, roots, elicitation callbacks
- Integration tests covering full client-server workflows

### Changed
- Phase 7 completion: conformance suite integration

## [0.1.0] - 2025-02-08

### Added
- Initial release
- MCP Client GenServer with full protocol API
- MCP Server GenServer with Handler behaviour
- Stdio transport (newline-delimited JSON-RPC)
- Streamable HTTP transport (POST + SSE) with Plug and Bandit
- Core protocol types, JSON-RPC 2.0 messages, capability negotiation
- Initialization handshake and capability auto-detection
- Pagination support for list operations
- Tools, resources, prompts, completions, and logging features

[1.0.1]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.2.3...v1.0.0
[0.2.3]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/JohnSmall/mcp-elixir-sdk/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/JohnSmall/mcp-elixir-sdk/releases/tag/v0.1.0

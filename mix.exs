defmodule MCPElixirSDK.MixProject do
  use Mix.Project

  @version "1.0.2"
  @source_url "https://github.com/JohnSmall/mcp-elixir-sdk"

  def project do
    [
      app: :mcp_elixir_sdk,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]],

      # Hex
      name: "MCP Elixir SDK",
      description: "Official-style Elixir SDK for the Model Context Protocol (MCP) — client and server with stdio and Streamable HTTP transports.",
      source_url: @source_url,
      homepage_url: "https://modelcontextprotocol.io",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MCPElixirSDK.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "MCP Specification" => "https://modelcontextprotocol.io/specification/2025-11-25",
        "Examples" => "https://github.com/JohnSmall/mcp_ex_examples"
      },
      files: ~w(lib usage-rules.md .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "usage-rules.md": [title: "Usage Rules (AI Agents)"],
        "docs/architecture.md": [title: "Architecture"],
        "docs/onboarding.md": [title: "Onboarding"]
      ],
      groups_for_extras: [
        Guides: ["docs/architecture.md", "docs/onboarding.md"],
        Reference: ["CHANGELOG.md", "LICENSE", "usage-rules.md"]
      ],
      groups_for_modules: [
        Client: [MCP.Client],
        Server: [MCP.Server, MCP.Server.Handler, MCP.Server.ToolContext],
        Protocol: [
          MCP.Protocol,
          MCP.Protocol.Error,
          MCP.Protocol.Methods
        ],
        Capabilities: ~r/MCP\.Protocol\.Capabilities\..*/,
        Messages: ~r/MCP\.Protocol\.Messages\..*/,
        Types: ~r/MCP\.Protocol\.Types\..*/,
        Transport: [
          MCP.Transport,
          MCP.Transport.Stdio,
          MCP.Transport.SSE,
          MCP.Transport.StreamableHTTP.Client,
          MCP.Transport.StreamableHTTP.Server,
          MCP.Transport.StreamableHTTP.Plug,
          MCP.Transport.StreamableHTTP.PreStarted
        ]
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["docs/architecture.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},

      # Optional: Streamable HTTP transport
      {:req, "~> 0.5", optional: true},
      {:plug, "~> 1.16", optional: true},
      {:bandit, "~> 1.5", optional: true},

      # Dev/test
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end

defmodule MCP.Conformance.HarnessHost do
  @moduledoc """
  Whether the pinned official conformance harness can be driven from this host,
  stated once for every caller.

  Two callers need the same answer and must not be able to disagree about it:
  `test/test_helper.exs` (through `MCP.Conformance.TestHarness`, which
  delegates here) turns it into a visible EXCLUSION of the
  `:requires_live_harness` units, and gate 7 (`mix conformance.oc_gate`,
  MES-160) turns it into a REFUSAL — the gate is never skipped for want of a
  harness. `test/support/` is compiled in `:test` only, so the predicate lives
  here, where `:dev` can reach it too (MES-160).
  """

  @default_harness_dir "/tmp/conf11"
  @package ["node_modules", "@modelcontextprotocol", "conformance"]
  @revision "2026-07-28"
  @pinned "0.2.0-alpha.11"
  # The pinned build's `dist/index.js`, by content. The version string is a
  # claim the package makes about itself; the sha is what was measured. ONE
  # constant: `MCP.Conformance.BucketZero` cites this build, and gate 7 refuses
  # any other (MES-160 B2).
  @pinned_dist_sha256 "a10085d0cfc9dd9192cc227f0f4dd6f1af9a94f6a0d3e30af08d4a0bcf268aae"

  @doc "The npm install root the runner and the tests default to."
  @spec default_harness_dir() :: String.t()
  def default_harness_dir, do: @default_harness_dir

  @doc "The pinned harness package version."
  @spec pinned_version() :: String.t()
  def pinned_version, do: @pinned

  @doc "The sha256 of the pinned harness build's `dist/index.js`."
  @spec pinned_dist_sha256() :: String.t()
  def pinned_dist_sha256, do: @pinned_dist_sha256

  @doc "The frozen revision the harness is driven at."
  @spec revision() :: String.t()
  def revision, do: @revision

  @doc "The harness package directory under an npm install root."
  @spec install_dir(String.t()) :: String.t()
  def install_dir(harness_dir \\ @default_harness_dir), do: Path.join([harness_dir | @package])

  @doc "The frozen requirement set as shipped inside the harness package."
  @spec requirements_yaml(String.t()) :: String.t()
  def requirements_yaml(harness_dir \\ @default_harness_dir),
    do: Path.join([install_dir(harness_dir), "requirements", "#{@revision}.yaml"])

  @doc "The harness entry point."
  @spec dist(String.t()) :: String.t()
  def dist(harness_dir \\ @default_harness_dir),
    do: Path.join([install_dir(harness_dir), "dist", "index.js"])

  @doc """
  `nil` when the live harness can be driven here, otherwise the reason it
  cannot — one sentence.
  """
  @spec unavailable_reason(String.t()) :: String.t() | nil
  def unavailable_reason(harness_dir \\ @default_harness_dir) do
    cond do
      System.find_executable("node") == nil ->
        "no `node` on PATH (the harness is a Node program; `mix test` cannot drive it here)"

      not File.exists?(dist(harness_dir)) ->
        "no harness at #{dist(harness_dir)} — install it with " <>
          "`npm i --prefix #{harness_dir} @modelcontextprotocol/conformance@#{@pinned}`"

      not File.exists?(requirements_yaml(harness_dir)) ->
        "the harness is installed but carries no #{@revision} requirement set at " <>
          "#{requirements_yaml(harness_dir)} — `latest` has none; the pinned alpha does"

      true ->
        nil
    end
  end
end

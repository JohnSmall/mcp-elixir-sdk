defmodule MCP.Conformance.PinnedRegister do
  @moduledoc """
  The ET-CC register as it stood when its dated consumers were measured: ONE
  named pin, read through a git object, never through a copy (MES-231, PO ruling
  2026-11-15, route DECOUPLE, PM `35457`).

  ## Why a pin exists at all

  MES-231 rebuilds `docs/conformance/etcc-register.json` from MES-230's
  re-capture: 579 rows and 281 ET-CC members become 811 and 479. Four consumers
  were measured over the 281-member set and are not extended to the new
  members on this ticket, so they read the register as of that set:

    * B2b's attribution join (`MCP.Conformance.ETCCAttribution.build/1`, its
      gate-5 test and its controls). Removed by **MES-243**, which authors the
      198 new attributions and re-points the join at the live register.
    * The crosswalk's register input (`mix conformance.crosswalk --register`)
      and G24's gate-5 re-derivation. Removed by **MES-244**.
    * The D2a-ii covered-elsewhere universe and the D3+D6 (MES-144) run record,
      both re-derived from the register in `adjudications_test.exs`. **MES-244**
      also proposes their permanent status.

  Everything else reads the live register.

  ## The pin, and what it refuses

  `commit/0` and `path/0` name the blob; `md5/0` is the md5 of its bytes. The
  reader refuses, naming the pin, when git cannot be run, when the object is
  not in the repository (a shallow clone, say), or when the bytes do not hash to
  `md5/0`. It never falls through to the file at `path/0`: a silent fall-through
  would hand the live register to a consumer that was measured over the pinned
  one, and the consumer would go red for a reason nobody could see, or green
  for one nobody intended.
  """

  # b5b0fbc: main when MES-231 branched (MES-239, 2.0.0-dev.119), the last
  # commit whose committed register is the 579-row, 281-member one.
  @commit "b5b0fbc7321b6ddba79b1a52c2d656947227fb00"
  @path "docs/conformance/etcc-register.json"
  @md5 "0bf1ff3b7e1ba35375f7efd9b4e369e9"

  @doc "The pinned commit, in full."
  def commit, do: @commit

  @doc "The register's path, in the pinned commit and in the tree."
  def path, do: @path

  @doc "The md5 of the pinned blob's bytes."
  def md5, do: @md5

  @doc "The pin as one string, as a refusal or a comment names it."
  def ref, do: "#{String.slice(@commit, 0, 7)}:#{@path} (md5 #{@md5})"

  @doc """
  The pinned register, decoded. Raises, naming the pin, on any failure.

  `opts` exists for the fail-closed controls only: `:commit`, `:md5` and `:git`
  replace the pin's commit, its md5 or the git executable.
  """
  def decode!(opts \\ []) do
    if opts == [] do
      case :persistent_term.get({__MODULE__, :decoded}, nil) do
        nil ->
          decoded = opts |> read!() |> Jason.decode!()
          :persistent_term.put({__MODULE__, :decoded}, decoded)
          decoded

        decoded ->
          decoded
      end
    else
      opts |> read!() |> Jason.decode!()
    end
  end

  @doc "The pinned blob's bytes, md5-checked. Raises, naming the pin."
  def read!(opts \\ []) do
    commit = Keyword.get(opts, :commit, @commit)
    expected = Keyword.get(opts, :md5, @md5)
    git = Keyword.get(opts, :git, "git")
    object = "#{commit}:#{@path}"

    bytes =
      try do
        System.cmd(git, ["cat-file", "blob", object], stderr_to_stdout: true)
      rescue
        e -> refuse!("git could not be run (#{Exception.message(e)})")
      else
        {bytes, 0} ->
          bytes

        {out, status} ->
          refuse!("git cat-file blob #{object} exited #{status}: #{String.trim(out)}")
      end

    actual = :crypto.hash(:md5, bytes) |> Base.encode16(case: :lower)

    unless actual == expected,
      do: refuse!("the object's md5 is #{actual}, not #{expected}")

    bytes
  end

  @doc """
  The register a consumer that takes a PATH should read: the pinned blob when
  `path` is the register's own path, and the file at `path` otherwise. Every
  other path is a control's planted copy, which must be read as planted.
  """
  def read_for!(path) do
    if Path.expand(path) == Path.expand(@path),
      do: decode!(),
      else: path |> File.read!() |> Jason.decode!()
  end

  defp refuse!(why) do
    raise "REFUSING to read the pinned ET-CC register #{ref()}: #{why}. " <>
            "The pinned consumers (MES-243, MES-244) never fall back to the live file."
  end
end

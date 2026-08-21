defmodule MCP.Conformance.Adapters do
  @moduledoc """
  The closed set of adapters a conformance run may be driven by, stated once.

  ## Why this module exists rather than a constant in `MCP.Conformance.Runner`

  Before MES-57 the same enum was spelled three times, in three files, for three
  different purposes:

    * `Runner`'s `@adapters` decided what could be *launched*;
    * `Census.adapter_fragment/1` decided what a beacon `source` had to *name*;
    * `Census.run_block/2` decided, with a bare `== "null"`, whether a run was a
      *control* or a *measurement*.

  Three spellings of one enum is the shape MES-56 was ratified for removing on
  the console side ("one derivation, not two"): adding an adapter meant editing
  three files, and forgetting the third silently reclassified a control as a
  measurement. The client leg adds **five** adapters at once, which turns that
  hazard from theoretical into likely, so the enum is centralised first.

  ## It stays an ENUM, and that is a security property

  `Runner`'s original comment is inherited verbatim in intent: "let the operator
  name a command" would turn a provenance tool into an arbitrary-process
  launcher whose manifest records whatever it was told. Every command line here
  is fixed at compile time, so `invocation.adapter` is a fact about **which of a
  known few things ran**.

  ## Role, and why there are three of them rather than two

    * `:measurement` — the SDK under test, driven by the measurement adapter.
      Its non-passing scenarios must each carry a classification entry
      (`Census.classify/1`).
    * `:control` — a **null implementation**: contains no SDK at all. Any scored
      scenario it passes is a scenario whose checks cannot distinguish this SDK
      from its absence. Joinable with `--control`.
    * `:probe` — the SDK under test driven by a **deliberately altered policy**,
      to establish by measurement whether a pass depends on that policy. The
      strict-connect probe is the one MES-57 needs: it halts the moment
      `MCP.Client.connect/1` errors, where the measurement adapter carries on.

  A probe is neither of the other two and must not be filed as either. It is not
  a control: it is full of SDK, so subtracting it would compute "ours alone
  against ourselves". It is not a measurement: demanding a classification
  rationale for each of its failures would be filing paperwork against a
  variant that exists to fail. `Census` gates on `role/2` for exactly these two
  reasons.
  """

  @typedoc "What a run's adapter makes the run: the SDK, its absence, or a policy variant."
  @type role :: :measurement | :control | :probe

  @typedoc """
  One adapter's fixed description.

  `scope` is `:all` for anything that drives every scenario the harness offers,
  or an explicit list for an adapter that deliberately drives fewer. Only the
  probe uses the second form, and it is declared HERE rather than inside the
  probe because two consumers need it and they must not be able to disagree:

    * the probe itself, which drives exactly this list;
    * `MCP.Conformance.Discounts`, which must read the probe's OTHER rows as
      meaningless rather than as failures. Deriving the drive-policy discount
      over the probe's whole sheet subtracts 6 of 7 in-scope scenarios and
      reports "0 of 7" — a catastrophic-looking headline produced entirely by
      reading a narrow instrument as a wide one. Measured, not hypothesised:
      that is what this module returned before `scope` existed.
  """
  @type entry :: %{
          leg: :server | :client,
          role: role(),
          fragment: String.t(),
          summary: String.t(),
          scope: :all | [String.t()]
        }

  # Keyed by {leg, adapter-name-as-written-into-the-manifest}. The names `sdk`
  # and `null` are shared across legs on purpose: they are the names MES-51 and
  # MES-56 already wrote into committed manifests, and renaming them would
  # orphan every artefact on `main`.
  @entries %{
    {:server, "sdk"} => %{
      leg: :server,
      role: :measurement,
      fragment: "server_adapter.exs",
      summary: "the SDK's own MCP server, under test",
      scope: :all
    },
    {:server, "null"} => %{
      leg: :server,
      role: :control,
      fragment: "null_server.py",
      summary: "answers -32601 to every method; contains no SDK",
      scope: :all
    },
    {:client, "sdk"} => %{
      leg: :client,
      role: :measurement,
      fragment: "client_adapter.exs",
      summary: "the SDK's own MCP client, under test",
      scope: :all
    },
    {:client, "null_exit0"} => %{
      leg: :client,
      role: :control,
      fragment: "null_client_exit0.py",
      summary: "exits 0 without opening a socket; the weakest null",
      scope: :all
    },
    {:client, "null_connect"} => %{
      leg: :client,
      role: :control,
      fragment: "null_client_connect.py",
      summary: "opens a TCP connection to the server URL, sends nothing, exits 0",
      scope: :all
    },
    {:client, "null_request"} => %{
      leg: :client,
      role: :control,
      fragment: "null_client_request.py",
      summary: "POSTs one well-formed JSON-RPC request for a nonexistent method, exits 0",
      scope: :all
    },
    {:client, "strict_connect"} => %{
      leg: :client,
      role: :probe,
      fragment: "strict_connect_adapter.exs",
      summary: "the SDK client, but HALTS the moment connect/1 errors — the drive-policy probe",
      # The ONE scenario the drive-policy claim is about. Narrow on purpose: the
      # probe exists to answer one question, and every other row of its sheet is
      # a category error rather than a result.
      scope: ["request-metadata"]
    }
  }

  # Command lines, kept beside the entries rather than inside them because the
  # server leg's take a port and the client leg's do not. A single `command`
  # field would have to be a format string, and a format string is a small
  # language the operator could be tempted to extend.
  @commands %{
    {:server, "sdk"} => "mix run --no-halt conformance/server_adapter.exs",
    {:server, "null"} => "python3 conformance/controls/null_server.py",
    {:client, "sdk"} => "mix run conformance/client_adapter.exs",
    {:client, "null_exit0"} => "python3 conformance/controls/null_client_exit0.py",
    {:client, "null_connect"} => "python3 conformance/controls/null_client_connect.py",
    {:client, "null_request"} => "python3 conformance/controls/null_client_request.py",
    {:client, "strict_connect"} => "mix run conformance/controls/strict_connect_adapter.exs"
  }

  # The table is a LITERAL, and a literal is where a key goes missing without
  # anything noticing: `scope` was added to six of the seven entries and omitted
  # from the seventh, and the omission surfaced as a `KeyError` at the point of
  # use rather than as a refusal to build. Every entry must carry every field,
  # and every entry must have a command, checked at COMPILE time — this module
  # is a registry, and a registry with a hole in it is worse than no registry
  # because its callers stop checking.
  @required_fields [:leg, :role, :fragment, :summary, :scope]

  @incomplete for {key, entry} <- @entries,
                  missing = @required_fields -- Map.keys(entry),
                  missing != [],
                  do: {key, missing}

  if @incomplete != [] do
    raise "MCP.Conformance.Adapters: incomplete entries #{inspect(@incomplete)}. " <>
            "A registry with a hole in it is worse than no registry: its callers stop " <>
            "checking, and the hole surfaces as a crash at the point of use."
  end

  @commandless Enum.sort(Map.keys(@entries) -- Map.keys(@commands))

  if @commandless != [] do
    raise "MCP.Conformance.Adapters: #{inspect(@commandless)} are declared adapters with no " <>
            "command line, so `--adapter` would accept them and then launch nothing."
  end

  @orphan_commands Enum.sort(Map.keys(@commands) -- Map.keys(@entries))

  if @orphan_commands != [] do
    raise "MCP.Conformance.Adapters: #{inspect(@orphan_commands)} have a command line and no " <>
            "entry, so nothing states their leg, role or beacon fragment."
  end

  # The enum's names as atoms, minted HERE at compile time from the literal
  # table above. `String.to_existing_atom/1` in the Mix task then converts an
  # operator's string safely: the atom exists because this attribute created it,
  # and only for names the registry declares. Minting them lazily from operator
  # input would be the atom-table leak; not minting them at all made
  # `--adapter null_exit0` crash with "not an already existing atom", which is a
  # refusal by accident rather than by design.
  @atoms Map.new(@entries, fn {{_leg, name}, _} -> {name, String.to_atom(name)} end)

  @doc """
  The atom for an adapter name the registry declares, or `nil`.

  The only sanctioned string -> atom conversion for an adapter name.
  """
  @spec atom(String.t()) :: atom() | nil
  def atom(name), do: Map.get(@atoms, name)

  @doc "Every `{leg, name}` this tooling can run, sorted."
  @spec keys() :: [{atom(), String.t()}]
  def keys, do: @entries |> Map.keys() |> Enum.sort()

  @doc "Adapter names admissible for `leg`, sorted."
  @spec names(atom()) :: [String.t()]
  def names(leg) do
    Enum.sort(for {{l, name}, _} <- @entries, l == leg, do: name)
  end

  @doc "The entry for `leg` and `name`, or `nil` if the pair is not in the enum."
  @spec fetch(atom() | String.t(), String.t()) :: entry() | nil
  def fetch(leg, name) when is_binary(leg), do: fetch(leg_atom(leg), name)
  def fetch(leg, name), do: Map.get(@entries, {leg, name})

  @doc """
  The path fragment a run's `beacon.jsonl` must name as the source that started.

  `nil` when the pair is not in the enum — the caller refuses rather than
  guessing, because a run whose adapter this tooling cannot name is a run whose
  role cannot be established.
  """
  @spec fragment(atom() | String.t(), String.t()) :: String.t() | nil
  def fragment(leg, name) do
    case fetch(leg, name) do
      nil -> nil
      entry -> entry.fragment
    end
  end

  @doc """
  The scenarios this adapter drives: `:all`, or an explicit list.

  `nil` when the pair is not in the enum.
  """
  @spec scope(atom() | String.t(), String.t()) :: :all | [String.t()] | nil
  def scope(leg, name) do
    case fetch(leg, name) do
      nil -> nil
      entry -> entry.scope
    end
  end

  @doc "`:measurement`, `:control`, `:probe`, or `nil` if the pair is not in the enum."
  @spec role(atom() | String.t(), String.t()) :: role() | nil
  def role(leg, name) do
    case fetch(leg, name) do
      nil -> nil
      entry -> entry.role
    end
  end

  @doc """
  The fixed command line for `leg`/`name`, with the port appended for the server
  leg only.

  Deliberately cwd-relative, exactly as the runs MES-51 was raised over were
  invoked. An absolute path here would silently repair the wrong-cwd failure
  mode and there would be nothing left for the positive control to catch.
  """
  @spec command(atom(), String.t(), integer()) :: String.t() | nil
  def command(leg, name, port) do
    case Map.get(@commands, {leg, name}) do
      nil -> nil
      base when leg == :server -> "#{base} #{port}"
      base -> base
    end
  end

  defp leg_atom("server"), do: :server
  defp leg_atom("client"), do: :client
  defp leg_atom(_), do: nil
end

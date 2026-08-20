defmodule MCP.Conformance.Argv do
  @moduledoc """
  Reject invalid operator input before any adjudication or run work begins.

  ## The property

  > **No invalid operator input may produce exit 0.**

  This is the third surface of one class, and it is stated here once for the
  whole tool rather than at each call site.

    * **B2** was absence read as satisfaction in the *artefacts* — a missing
      scenario directory counted as a passing one.
    * **The nil audit** was absence read as satisfaction in the *manifest* — an
      absent JSON key compared as satisfied under `==`, `>` and truthiness.
    * **This** is absence read as satisfaction in the *operator's own input* — a
      misspelled pin is silently no pin, so the check that was asked for is
      never run while the tool returns its only success signal.

  `mix conformance.adjudicate` is binding on MES-56 and MES-57 through its exit
  status. A consumer reading only that status cannot see that a switch was
  dropped, however loudly the drop is printed — so the drop must not be
  survivable, not merely visible.

  ## Why `strict:` and not the invalid list

  The obvious mechanism — keep the third element of `OptionParser.parse/2`
  instead of discarding it — is **not sufficient**, and measurement rather than
  reading is what shows it. Under `switches:`, an *unknown* switch is not
  reported as invalid; it is discarded silently, along with the value that
  follows it:

      iex> OptionParser.parse(["/d", "--expect-comit", "0000"], switches: [expect_commit: :string])
      {[], ["/d"], []}

  Empty invalid list, and the misspelling is gone. Only a *known* switch given a
  bad or missing value lands in `invalid`. Of the six invocations that reached
  exit 0 on a good run, that list holds two. `strict:` reports all six, because
  it treats an unrecognised switch as an error rather than as noise:

      iex> OptionParser.parse(["/d", "--expect-comit", "0000"], strict: [expect_commit: :string])
      {[], ["/d"], [{"--expect-comit", nil}]}

  So the mechanism here is `strict:` **plus** the invalid list **plus** a bound
  on positional arguments — the three together, because each alone leaves a hole
  the other two cover.

  ## Exit status, chosen rather than fallen into

  A usage error exits **#{64}** (`EX_USAGE`, sysexits.h), not 1 and not 2.

    * Not **0**, which is the only thing that must hold: 0 means *quotable*.
    * Not **1**. 1 means *this run is inadmissible* — a verdict about the run,
      reached by adjudicating it. A usage error is not a verdict about anything;
      the run was never adjudicated. Sharing a code would make a caller that
      reports "provenance refused" on 1 misreport a typo as a provenance
      failure, and the two want opposite responses: fix the command line versus
      re-run the measurement.
    * Not **2**, which `--diagnose` holds for *reported, no verdict*.

  `64` is conventional rather than invented, so it is not one more local code to
  learn. The bound worth stating: a caller that tests only `rc != 0` sees no
  difference between the four, and that is intended — the safety property is
  that a usage error is not mistaken for success, not that every consumer
  distinguishes it.
  """

  @usage_exit 64

  @doc "The exit status of a usage error. Never 0, 1 or 2 — see the moduledoc."
  @spec usage_exit() :: pos_integer()
  def usage_exit, do: @usage_exit

  @doc """
  Parse `argv` or exit #{@usage_exit}. Returns `{opts, positional}`.

  Options:

    * `:strict` — the switch spec, passed to `OptionParser` as `strict:`
    * `:aliases` — short-form aliases (default `[]`)
    * `:positional` — how many positional arguments are permitted (default `0`)
    * `:usage` — the usage line printed with any rejection
    * `:retired` — a map of `"--flag" => "why it went"`, so a switch removed on
      purpose says so instead of reading as a typo
  """
  @spec parse!(String.t(), [String.t()], keyword()) :: {keyword(), [String.t()]}
  def parse!(task, argv, spec) do
    switches = Keyword.fetch!(spec, :strict)
    aliases = Keyword.get(spec, :aliases, [])
    max_positional = Keyword.get(spec, :positional, 0)
    usage = Keyword.fetch!(spec, :usage)
    retired = Keyword.get(spec, :retired, %{})

    {opts, positional, invalid} =
      OptionParser.parse(argv, strict: switches, aliases: aliases)

    faults =
      Enum.map(invalid, &fault(&1, switches, retired)) ++
        surplus(positional, max_positional)

    if faults == [], do: {opts, positional}, else: reject(task, faults, usage, switches)
  end

  # A known switch and an unknown one fail for different reasons and want
  # different corrections, so they are not collapsed into one message.
  defp fault({switch, value}, switches, retired) do
    cond do
      Map.has_key?(retired, switch) ->
        "#{switch} was removed, not renamed: #{Map.fetch!(retired, switch)}"

      not known?(switch, switches) ->
        "#{switch} is not a switch of this task#{did_you_mean(switch, switches)}"

      is_nil(value) ->
        "#{switch} needs a value and was given none"

      true ->
        "#{switch} was given #{inspect(value)}, which is not a #{type_of(switch, switches)}"
    end
  end

  defp surplus(positional, max) when length(positional) <= max, do: []

  defp surplus(positional, max) do
    extra = positional |> Enum.drop(max) |> Enum.map_join(", ", &inspect/1)

    ["unexpected argument(s) #{extra} — this task takes #{max} positional argument(s)"]
  end

  defp known?(switch, switches), do: switch in switch_names(switches)

  defp switch_names(switches) do
    Enum.map(switches, fn {key, _type} ->
      "--" <> String.replace(Atom.to_string(key), "_", "-")
    end)
  end

  defp type_of(switch, switches) do
    Enum.find_value(switches, "valid value", fn {key, type} ->
      if "--" <> String.replace(Atom.to_string(key), "_", "-") == switch, do: to_string(type)
    end)
  end

  # A misspelling is the case that reached exit 0, so it is the case worth
  # spending a line on: name the switch that was probably meant.
  defp did_you_mean(switch, switches) do
    switch_names(switches)
    |> Enum.filter(&(String.jaro_distance(&1, switch) > 0.85))
    |> case do
      [] -> ""
      near -> " (did you mean #{Enum.join(near, " or ")}?)"
    end
  end

  defp reject(task, faults, usage, switches) do
    Mix.shell().error("""
    USAGE ERROR  mix #{task}

    #{Enum.map_join(faults, "\n", &"  #{&1}")}

      Nothing was adjudicated and nothing was run. This exits #{@usage_exit}, not 0:
      an unrecognised switch is a check you asked for and did not get, and it
      may not return the success signal that lets a figure be quoted.

      usage: #{usage}
      switches: #{Enum.join(switch_names(switches), " ")}
    """)

    exit({:shutdown, @usage_exit})
  end
end

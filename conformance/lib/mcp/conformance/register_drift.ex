defmodule MCP.Conformance.RegisterDrift do
  @moduledoc """
  Gate 9 (MES-241): would a faithful re-capture of the suite change the ET-CC register?

  `docs/conformance/etcc-register.json` is built from the committed rows file
  (`docs/conformance/etcc-exunit-rows.json`), the authored decisions, the boundaries table
  and the live `test/mcp/` sources (`MCP.Conformance.ETCCRegister`). A ticket that adds,
  renames or deletes a `test/mcp/` test, or adds a doctest example in `lib/`, changes the
  suite without changing the committed rows file, and `keysets` and `reproduce` stay green
  on it (measured on the MES-241 plan, comment 35676). This module asks the generator
  itself, so no relevance rule is re-implemented here.

  ## The three steps

    * `reproduce` — build from the committed inputs and compare the bytes with the
      committed register, through `ETCCRegister.encode/1`, the writer's own encoder. A
      build refusal is drift: the refusal is printed.
    * `keysets` — the committed register's rows equal the committed rows file's
      `test/mcp/` keys, and rows plus `out_of_scope` equal the whole file, disjoint. This
      is the `keysets` control the ticket names, kept as a diagnostic. When `reproduce`
      is green it cannot be red, because `build/1` refuses a partition that fails it
      (`check_key_sets!/2`, `check_partition!/3`).
    * `fresh` — build from the FRESH capture, with the same decisions, boundaries and
      sources, and compare its `rows` with the committed register's `rows`, key by key
      and field by field. A build refusal is drift (for example "1 in-scope unit(s) have
      no decision"). `totals` and `provenance` are not compared: the in-scope totals are a
      function of `rows`, and the provenance carries the capture's own md5.
      `out_of_scope` is not compared either. It holds only `test/conformance/` keys, which are
      not in-scope rows, and the end-of-sprint rows-drift sweep owns it
      (`docs/procedure/end-of-sprint.md`, step 6). Test code under `test/conformance/` can
      still change in-scope doctest units (gate-9.md residual 8, MES-248).

  ## Refusals

  The fresh capture is checked by every `MCP.Conformance.RowsDrift` guard (RD1-RD9) on the
  fresh side, before anything is built, and by three provenance guards of this gate's own
  (MES-241 correction round 1, CR findings R1 and R2):

    * RT1 `tip`: the capture's `run.tip` is not the current `git rev-parse HEAD`, or is
      missing. A capture from another commit says nothing about this one.
    * RT2 `worktree`: the CURRENT tree is not clean (`git status --porcelain` is not empty,
      or git cannot answer). RD6 reads the clean state the capture recorded; RT2 reads the
      tree being judged now.
    * RT3 `suite_rc`: the capture carries no integer `run.suite_rc`. Only `capture!/0`
      writes it, and RD7 reads it; a replayed capture without it could hide a suite that
      exited non-zero with every row green.

  A capture that fails any guard is refused and nothing is compared: an incomplete capture
  would read a missing test as a deletion, or miss an added one. A capture that fails RD1 is
  checked for nothing else, as in RowsDrift.

  RT4 `instrument_error` is the fourth refusal: an exception in a build that is NOT an
  expected generator or data refusal (R4). The build's own refusals (`RuntimeError`s
  beginning `REFUSING to write`) and a `File.Error` with reason `:enoent` on a test source
  the build's inputs cite (a test file that moved or went) are drift; anything else means the instrument could not decide, so it is refused (exit 2)
  with the exception in the report, and never reported as drift. `guards/0` lists all of
  them.

  ## Report

  `check/2` returns a map with schema `etcc-register-drift/1` and a `verdict` of `clean`,
  `drift` or `refused`. `exit_status/1` maps it to 0, 1 or 2.
  """

  alias MCP.Conformance.{ETCCRegister, ExUnitRows, RowsDrift}

  @schema "etcc-register-drift/1"
  @steps ~w(reproduce keysets fresh)
  @in_scope "test/mcp/"

  @typedoc "A decoded `etcc-register-drift/1` report."
  @type report :: map()

  @doc "The report's schema identifier."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc "The steps, in report order."
  @spec steps() :: [String.t()]
  def steps, do: @steps

  @own_guards ~w(RT1 RT2 RT3 RT4 RT5)

  @doc "Every refusal this check can make: RowsDrift's RD1-RD9, then RT1-RT4."
  @spec guards() :: [String.t()]
  def guards, do: RowsDrift.guards() ++ @own_guards

  @doc "The files this check never writes: the committed rows file and the register."
  @spec protected() :: [String.t()]
  def protected, do: [RowsDrift.committed_path(), ETCCRegister.paths().register]

  @doc """
  Adjudicate the fresh capture `fresh` (a decoded rows artefact, or `:missing`) against the
  committed register in the current directory.
  """
  @spec check(map() | :missing) :: report()
  def check(fresh) do
    refusals = refusals(fresh)

    base = %{
      "schema" => @schema,
      "refusals" => refusals,
      "fresh_md5" => run_field(fresh, "rows_md5"),
      "fresh_tip" => run_field(fresh, "tip")
    }

    if refusals != [] do
      Map.put(base, "verdict", "refused")
    else
      bytes = File.read!(ETCCRegister.paths().register)
      committed = Jason.decode!(bytes)

      steps = %{
        "reproduce" => reproduce(bytes, committed),
        "keysets" => keysets(committed),
        "fresh" => fresh_build(fresh, committed)
      }

      errors =
        for s <- @steps,
            msg = steps[s]["error"],
            do: %{"guard" => "RT4", "side" => s, "detail" => msg}

      verdict =
        cond do
          errors != [] -> "refused"
          Enum.all?(@steps, &steps[&1]["ok"]) -> "clean"
          true -> "drift"
        end

      %{base | "refusals" => errors} |> Map.merge(steps) |> Map.put("verdict", verdict)
    end
  end

  @doc """
  Every refusal `fresh` earns before anything is compared: RowsDrift's guards on the fresh
  side, then RT1-RT3. After an RD1 refusal nothing else is checked.
  """
  @spec refusals(map() | :missing) :: [map()]
  def refusals(fresh) do
    rows = RowsDrift.refusals("fresh", fresh)

    if Enum.any?(rows, &(&1["guard"] == "RD1")) do
      rows
    else
      rows ++ provenance_refusals(fresh)
    end
  end

  defp provenance_refusals(fresh) do
    [rt1_tip(fresh), rt2_worktree(), rt3_suite_rc(fresh), rt5_doctests(fresh)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {g, detail} -> %{"guard" => g, "side" => "fresh", "detail" => detail} end)
  end

  @doc false
  def rt1_tip(fresh) do
    tip = run_field(fresh, "tip")
    head = git(["rev-parse", "HEAD"])

    if is_binary(tip) and tip != "" and tip == head,
      do: nil,
      else: {"RT1", "the capture's tip #{inspect(tip)} is not HEAD #{inspect(head)}"}
  end

  @doc false
  def rt2_worktree do
    case git(["status", "--porcelain"]) do
      "" ->
        nil

      nil ->
        {"RT2", "git status could not be read, so the tree is not known to be clean"}

      out ->
        {"RT2",
         "the tree being judged is dirty: #{out |> String.split("\n") |> Enum.take(3) |> Enum.join("; ")}"}
    end
  end

  @doc false
  def rt3_suite_rc(fresh) do
    if is_integer(run_field(fresh, "suite_rc")),
      do: nil,
      else:
        {"RT3",
         "the capture carries no suite_rc, so the suite's own exit status is unknown " <>
           "(only a capture made by this gate or rows_drift records it)"}
  end

  @doc """
  RT5 (correction rounds 3 and 4, PM rulings on CR finding R5). It reads the capture, not the
  test source, and checks three things for every in-scope row whose `test_type` is `doctest`.
  The row must name, in its test name (`doctest Mod.fun/arity (n)` or
  `doctest module Mod (n)`) and in ExUnit's own `doctest` tag where present, a module that a
  `defmodule` under `lib/` defines, AND the module as loaded at suite end must have been
  compiled from a file under `lib/` (correction round 4): the capture records each doctested
  module's `module_info(:compile)[:source]`, read inside the test VM when the suite finishes,
  in `run.doctest_sources`, and its real path must lie under this repository's `lib/`. An
  unparseable name, a name and tag that disagree, a name no `lib/` defmodule defines, no
  recorded source, or a source elsewhere is refused, with the module named.

  What this establishes, exactly: the compile source of each doctested module as loaded at
  suite end. It does not establish which definition DocTest expanded its units from; test code
  that swaps a module's definition between doctest expansion and suite end is not detected
  (CR 35837; residual 8 in `docs/procedure/gate-9.md`, hardening ticketed as MES-248).
  Such a swap needs test code. A hook in `test/mcp/`, `test/support/` or
  `test/test_helper.exs` fires gate 9; a hook elsewhere, for example in `test/conformance/`
  (CR 35914), does not. Either way it is a reviewable change under D7, but gate 9 does not
  guarantee to see it. When gate 9 runs, a suite-end source outside `lib/` is refused.
  """
  @spec rt5_doctests(map()) :: {String.t(), String.t()} | nil
  def rt5_doctests(fresh) do
    lib = lib_modules()
    sources = get_in(fresh, ["run", "doctest_sources"])

    offenders =
      for %{"test_type" => "doctest"} = row <- fresh["rows"],
          in_scope?(row),
          verdict = row |> doctest_module() |> in_lib(lib) |> origin(sources),
          not match?({:ok, _}, verdict),
          uniq: true,
          do: describe_offender(row, verdict)

    if offenders == [],
      do: nil,
      else:
        {"RT5",
         "#{length(offenders)} in-scope doctest unit(s) whose module is not defined under lib/: " <>
           Enum.join(offenders, "; ")}
  rescue
    e -> {"RT5", "the doctest premise could not be checked: #{message(e)}"}
  end

  defp describe_offender(row, {:error, why}),
    do: "#{why}: #{inspect(row["name"])} (#{row["file"]})"

  # The name check: a defmodule under lib/ must define the module (kept as an extra check).
  defp in_lib({:ok, mod}, lib) do
    if MapSet.member?(lib, mod),
      do: {:ok, mod},
      else: {:error, "#{mod} is not defined under lib/"}
  end

  defp in_lib(verdict, _), do: verdict

  # The origin check (correction round 4, PM ruling on CR's shadow case): the definition the
  # test VM loaded, as the capture recorded it (run.doctest_sources), must have been compiled
  # from a regular file whose real path is under this repository's lib/. No record, or a
  # source elsewhere, refuses.
  defp origin({:ok, mod}, sources), do: loaded_from_lib(mod, sources)
  defp origin(verdict, _), do: verdict

  @doc false
  def loaded_from_lib(mod, sources) do
    source = if is_map(sources), do: sources[mod]
    lib_root = RowsDrift.real_path(Path.join(File.cwd!(), "lib")) <> "/"

    cond do
      not is_map(sources) ->
        {:error, "the capture records no doctest_sources, so the origin of #{mod} is unknown"}

      not is_binary(source) ->
        {:error, "the capture records no compile source for #{mod}"}

      String.starts_with?(RowsDrift.real_path(source), lib_root) and File.regular?(source) ->
        {:ok, mod}

      true ->
        {:error, "#{mod} was loaded from #{source}, which is not a file under lib/"}
    end
  end

  @doc false
  def doctest_module(%{"name" => name} = row) when is_binary(name) do
    parsed = parse_doctest_name(name)
    tagged = get_in(row, ["tags", "doctest"])

    cond do
      parsed == :error ->
        {:error, "unparseable doctest name"}

      is_binary(tagged) and tagged != parsed ->
        {:error, "name and doctest tag #{inspect(tagged)} disagree"}

      true ->
        {:ok, parsed}
    end
  end

  def doctest_module(_), do: {:error, "no name"}

  @module_name ~r/\A[A-Z]\w*(\.[A-Z]\w*)*\z/

  defp parse_doctest_name("doctest module " <> rest) do
    case Regex.run(~r/\A(\S+) \(\d+\)\z/, rest) do
      [_, mod] -> if Regex.match?(@module_name, mod), do: mod, else: :error
      _ -> :error
    end
  end

  defp parse_doctest_name("doctest " <> rest) do
    case Regex.run(~r/\A(.+)\.[^.\s]+\/\d+ \(\d+\)\z/, rest) do
      [_, mod] -> if Regex.match?(@module_name, mod), do: mod, else: :error
      _ -> :error
    end
  end

  defp parse_doctest_name(_), do: :error

  # The modules a `defmodule` under lib/ defines, read from the AST (nothing is loaded).
  @doc false
  def lib_modules do
    "lib/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn f -> f |> File.read!() |> Code.string_to_quoted!() |> defined([]) end)
    |> MapSet.new(&Enum.join(&1, "."))
  end

  defp defined({:defmodule, _, [{:__aliases__, _, parts}, [do: body]]}, parent) do
    name = parent ++ Enum.map(parts, &Atom.to_string/1)
    [name | defined(body, name)]
  end

  defp defined({_, _, args}, parent) when is_list(args),
    do: Enum.flat_map(args, &defined(&1, parent))

  defp defined(list, parent) when is_list(list), do: Enum.flat_map(list, &defined(&1, parent))
  defp defined({a, b}, parent), do: defined(a, parent) ++ defined(b, parent)
  defp defined(_, _), do: []

  @doc """
  The bytes `--keep` writes: the adjudicated artefact, `run.suite_rc` included, so a
  replay with `--fresh` is judged on the same facts as the live run (R2). Only a capture
  that could not be decoded falls back to the formatter's file as written.
  """
  @spec keep_bytes(map() | :missing, Path.t()) :: binary()
  def keep_bytes(%{} = artefact, _raw_path), do: ExUnitRows.encode(artefact)
  def keep_bytes(_, raw_path), do: File.read!(raw_path)

  @doc "0 for clean, 1 for drift, 2 for refused."
  @spec exit_status(report()) :: 0 | 1 | 2
  def exit_status(%{"verdict" => "clean"}), do: 0
  def exit_status(%{"verdict" => "drift"}), do: 1
  def exit_status(%{"verdict" => "refused"}), do: 2

  # ---------------------------------------------------------------------------
  # The steps
  # ---------------------------------------------------------------------------

  @doc false
  def reproduce(bytes, committed) do
    rebuilt = ETCCRegister.encode(ETCCRegister.build(spec_md5s: spec_md5s(committed)))

    %{
      "ok" => rebuilt == bytes,
      "committed_md5" => md5(bytes),
      "rebuilt_md5" => md5(rebuilt),
      "refused" => nil
    }
  rescue
    e -> reproduce_refused(e, cited_files(committed, ETCCRegister.paths().artefact))
  end

  # A refusal is drift, never clean. Each step has its own function, so a mutant that
  # reads one step's refusal as clean is separable from the other (controls M6a, M6b).
  defp reproduce_refused(e, cited), do: refused_or_error(e, cited)

  # R4: only the generator's own refusals and a missing test file are drift. Any other
  # exception is an instrument error, which `check/1` turns into an RT4 refusal.
  defp refused_or_error(e, cited) do
    if expected_refusal?(e, cited),
      do: %{"ok" => false, "refused" => message(e)},
      else: %{"ok" => false, "refused" => nil, "error" => message(e)}
  end

  @doc """
  Whether exception `e`, raised inside a build, is a statement about the register's inputs
  (drift) rather than a failure of the instrument (RT4). Exactly two forms are drift: one of
  the generator's own refusals (a `RuntimeError` beginning `REFUSING to write`), and a
  `File.Error` with reason `:enoent` on a test source that the failing build's own inputs
  cite (the committed register's rows, or the rows of the artefact that build read: the
  committed rows file for `reproduce`, the fresh capture for `fresh`), which is a test file
  that moved or went (plant P11, where the committed rows file still names the old path). Any other `File.Error` (`:eacces`, `:emfile`, or
  `:enoent` on a path the register does not cite) says nothing about the register, so it is
  not drift (MES-241 correction round 2, CR finding R4).
  """
  @spec expected_refusal?(Exception.t(), MapSet.t(String.t())) :: boolean()
  def expected_refusal?(e, cited) do
    case e do
      %RuntimeError{message: "REFUSING to write" <> _} -> true
      %File.Error{reason: :enoent, path: path} -> MapSet.member?(cited, relative(path))
      _ -> false
    end
  end

  # The test sources the build actually locates: the IN-SCOPE rows (under test/mcp/) of the
  # committed register and of the artefact the failing build read. An out_of_scope row only
  # names a file; the builder never opens it, so it can never make an :enoent drift
  # (correction round 3, CR finding R4).
  defp cited_files(committed, artefact) do
    rows = Map.get(committed, "rows", []) ++ artefact_rows(artefact)

    rows
    |> Enum.filter(&in_scope?/1)
    |> MapSet.new(& &1["file"])
  end

  defp in_scope?(%{"file" => file}) when is_binary(file), do: String.starts_with?(file, @in_scope)
  defp in_scope?(_), do: false

  defp artefact_rows(%{"rows" => rows}) when is_list(rows), do: rows

  defp artefact_rows(path) when is_binary(path) do
    with {:ok, bytes} <- File.read(path), {:ok, %{} = a} <- Jason.decode(bytes) do
      artefact_rows(a)
    else
      _ -> []
    end
  end

  defp artefact_rows(_), do: []

  defp relative(path),
    do: path |> to_string() |> Path.expand() |> Path.relative_to(File.cwd!())

  @doc false
  def keysets(committed) do
    artefact = ETCCRegister.paths().artefact |> File.read!() |> Jason.decode!()
    all = MapSet.new(artefact["rows"], & &1["key"])

    in_scope =
      artefact["rows"]
      |> Enum.filter(&String.starts_with?(&1["file"], @in_scope))
      |> MapSet.new(& &1["key"])

    reg = MapSet.new(committed["rows"], & &1["key"])
    oos = MapSet.new(committed["out_of_scope"], & &1["key"])

    differ =
      for {name, a, b} <- [
            {"register rows == artefact rows under test/mcp/", reg, in_scope},
            {"register + out_of_scope == the whole artefact", MapSet.union(reg, oos), all},
            {"register and out_of_scope are disjoint", MapSet.intersection(reg, oos),
             MapSet.new()}
          ],
          not MapSet.equal?(a, b),
          do: name

    %{"ok" => differ == [], "differ" => differ}
  end

  @doc false
  def fresh_build(fresh, committed) do
    built = ETCCRegister.build(artefact: fresh, spec_md5s: spec_md5s(committed))
    compare_rows(committed["rows"], built["rows"])
  rescue
    e -> fresh_refused(e, cited_files(committed, fresh))
  end

  defp fresh_refused(e, cited), do: refused_or_error(e, cited)

  @doc false
  def compare_rows(committed_rows, fresh_rows) do
    c = Map.new(committed_rows, &{&1["key"], &1})
    f = Map.new(fresh_rows, &{&1["key"], &1})

    only_committed = c |> Map.keys() |> Enum.reject(&Map.has_key?(f, &1)) |> Enum.sort()
    only_fresh = f |> Map.keys() |> Enum.reject(&Map.has_key?(c, &1)) |> Enum.sort()

    changed =
      for {k, row} <- Enum.sort(c),
          other = f[k],
          other != nil,
          fields = changed_fields(row, other),
          fields != [],
          do: %{"key" => k, "fields" => fields}

    %{
      "ok" => only_committed == [] and only_fresh == [] and changed == [],
      "refused" => nil,
      "only_committed" => only_committed,
      "only_fresh" => only_fresh,
      "changed" => changed
    }
  end

  defp changed_fields(a, b) do
    (Map.keys(a) ++ Map.keys(b)) |> Enum.uniq() |> Enum.filter(&(a[&1] != b[&1])) |> Enum.sort()
  end

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  @doc "The human-readable report. The last line is the verdict line."
  @spec render(report()) :: String.t()
  def render(%{"verdict" => "refused"} = r) do
    lines = for x <- r["refusals"], do: "  #{x["guard"]} (#{x["side"]}): #{x["detail"]}"
    guards = r["refusals"] |> Enum.map(& &1["guard"]) |> Enum.uniq() |> Enum.join(", ")

    head =
      if Enum.any?(r["refusals"], &(&1["guard"] == "RT4")),
        do: "REFUSED, the instrument failed, so this is no verdict on the register:",
        else: "REFUSED, nothing was compared:"

    Enum.join(
      [head | lines] ++
        ["register-drift: REFUSED - #{guards} (a refusal is not a clean result)"],
      "\n"
    )
  end

  def render(r) do
    detail = Enum.flat_map(@steps, &step_lines(&1, r[&1]))
    summary = Enum.map_join(@steps, ", ", &"#{&1} #{if r[&1]["ok"], do: "ok", else: "RED"}")

    Enum.join(
      detail ++ ["register-drift: #{String.upcase(r["verdict"])} - #{summary}"],
      "\n"
    )
  end

  defp step_lines(step, %{"refused" => msg}) when is_binary(msg),
    do: ["#{step}: RED, the build refused: #{msg}"]

  defp step_lines("reproduce", s),
    do: [
      "reproduce: #{if s["ok"], do: "ok", else: "RED"}, identical: #{s["ok"]} " <>
        "(committed md5 #{s["committed_md5"]}, rebuilt md5 #{s["rebuilt_md5"]})"
    ]

  defp step_lines("keysets", %{"ok" => true}), do: ["keysets: ok (3 equalities)"]

  defp step_lines("keysets", s),
    do: ["keysets: RED" | Enum.map(s["differ"], &"  DIFFER #{&1}")]

  defp step_lines("fresh", %{"ok" => true}),
    do: ["fresh: ok, the register built from the fresh capture has the committed rows"]

  defp step_lines("fresh", s) do
    ["fresh: RED, the register built from the fresh capture differs from the committed one"] ++
      Enum.map(s["only_committed"], &"  only committed: #{&1}") ++
      Enum.map(s["only_fresh"], &"  only fresh:     #{&1}") ++
      Enum.map(s["changed"], &"  changed:        #{&1["key"]} (#{Enum.join(&1["fields"], ", ")})")
  end

  # ---------------------------------------------------------------------------
  # Plumbing
  # ---------------------------------------------------------------------------

  defp spec_md5s(committed), do: get_in(committed, ["provenance", "spec_files"]) || %{}

  defp git(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp run_field(%{"run" => %{} = run}, k), do: run[k]
  defp run_field(_, _), do: nil

  # The exception's text, for drift and for RT4 alike; any exception other than one of the
  # generator's own refusals is prefixed with its type.
  # The generator's refusals put the offending key on the following lines, so up to three
  # lines are kept.
  defp message(e) do
    text =
      e
      |> Exception.message()
      |> String.split("\n")
      |> Enum.take(3)
      |> Enum.map_join(" ", &String.trim/1)

    if match?(%RuntimeError{message: "REFUSING to write" <> _}, e),
      do: text,
      else: "#{inspect(e.__struct__)}: #{text}"
  end

  defp md5(bin), do: :crypto.hash(:md5, bin) |> Base.encode16(case: :lower)
end

defmodule MCP.Conformance.RowsDrift do
  @moduledoc """
  MES-240. Compare a fresh ExUnit row capture with the committed one, so the test-rows
  file `docs/conformance/etcc-exunit-rows.json` never again ages unseen.

  ## Why

  The committed rows file was captured at `584e115` on 2026-08-24, and by MES-230's size
  survey it had lost about 210 tests and many of its lines before a sweep refused
  (MES-228). A plain `mix test` writes no rows (`MCP.Conformance.ExUnitRows` is off by
  default), so nothing re-captured the file. This module is that comparison, and
  `mix conformance.rows_drift` is its command. It runs at the sprint boundary
  (`docs/procedure/end-of-sprint.md`, step 6), and MES-241 is expected to call it per
  ticket.

  ## The comparison

  Unit keys are compared in both directions. For each shared key, the fields that
  `docs/conformance/etcc-row-key.md` §5 calls a finding regardless of host are compared
  too. Each class below is computed by its own function:

    * `added` — a key the fresh capture has and the committed file does not.
    * `removed` — the reverse. A renamed test is one removed key plus one added key,
      because the key is the unit's identity (§1). A removed and an added key in the same
      file at the same line are paired as `rename_candidates`, for information only.
    * `moved` — a shared key whose `file` differs.
    * `relined` — a shared key whose `line` differs (delimit drift). Every shared key is
      compared, including one that moved file: a move with a new line is reported under
      both `moved` and `relined` (MES-240 F3).
    * `refielded` — a shared key whose `describe`, `test_type` or `tags` differ.
    * `restatus` — a shared key whose `status` or `reason` differ.

  ## Refusals

  A capture that cannot be adjudicated is refused, never compared. **Every guard is
  two-sided**: `refusals/2` runs all nine on the committed artefact and on the fresh one,
  and every refusal found is reported, not just the first. That is how the controls show
  that each plant fails only its own guard, on each side, and a mutant that skips a guard
  on one side only is killed (MES-240 F2). No guard is deliberately one-sided. One limb is
  one-sided by data, not by code: `run.suite_rc` (RD7) is written only by `capture!/0`,
  so a committed file never carries it.

    * RD1 `schema`: `schema` is not `etcc-exunit-rows/1`, or `rows` is not a list.
    * RD2 `md5`: the recorded `run.rows_md5` is not the md5 of the rows as they are,
      for example in a hand-edited file.
    * RD3 `incomplete`: `run.complete` is not true, `run.row_errors` is not empty, or
      the started and finished module counts differ.
    * RD4 `partial`: `run.argv` is anything other than `test` with an optional
      `--seed N`, `run.include` is set, or the run was `--only-test-ids` or
      `--max-failures`.
    * RD5 `host`: `run.exclude` is set. On a host without `node`, `test_helper.exs`
      excludes `:requires_live_harness` with no argv change, which is the §5.1 host
      variation. RD4 does not read `exclude`, so the two guards stay separable.
    * RD6 `dirty`: `run.tree_clean` is not true, or `run.tree_dirty` is not empty.
    * RD7 `red`: a row is `failed` or `invalid`, or the capture's own `mix test` exited
      non-zero (`suite_rc`, live captures only).
    * RD8 `collisions`: `run.key_collisions` is not empty, or two rows share a key.
    * RD9 `consistency`: a row's `key` is not `module <> "/" <> name`, or
      `run.module_cross_check.disagreements` is not empty. `ExUnitRows` derives all three
      together and records the cross-check, so either is a file not written by it as
      recorded. An absent `module_cross_check` is not refused here.

  ## Report

  `check/2` returns a map with schema `etcc-rows-drift/1`, whose `verdict` is `clean`,
  `drift` or `refused`. `exit_status/1` maps that verdict to 0, 1 or 2. The report is
  JSON-encodable as it stands, which is the interface MES-241 is to consume.
  """

  alias MCP.Conformance.ExUnitRows

  @schema "etcc-rows-drift/1"
  @rows_schema "etcc-exunit-rows/1"
  @committed "docs/conformance/etcc-exunit-rows.json"
  @classes ~w(added removed moved relined refielded restatus)
  @guards ~w(RD1 RD2 RD3 RD4 RD5 RD6 RD7 RD8 RD9)
  @red ~w(failed invalid)
  @refields ~w(describe test_type tags)

  @typedoc "A decoded `etcc-exunit-rows/1` artefact."
  @type artefact :: map()
  @typedoc "A decoded `etcc-rows-drift/1` report."
  @type report :: map()

  @doc "The report's schema identifier."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc "The committed rows file's path, relative to the project root."
  @spec committed_path() :: String.t()
  def committed_path, do: @committed

  @doc "The drift classes, in report order."
  @spec classes() :: [String.t()]
  def classes, do: @classes

  @doc "The refusal guards, in check order."
  @spec guards() :: [String.t()]
  def guards, do: @guards

  # ---------------------------------------------------------------------------
  # The verdict
  # ---------------------------------------------------------------------------

  @doc """
  Adjudicate `fresh` against `committed`. Refusals are checked first, on both sides. If
  any refusal fires, the report carries no drift classes, because nothing was compared.
  """
  @spec check(artefact(), artefact()) :: report()
  def check(committed, fresh) do
    refusals = refusals("committed", committed) ++ refusals("fresh", fresh)

    base = %{
      "schema" => @schema,
      "refusals" => refusals,
      "committed_md5" => get_in_run(committed, "rows_md5"),
      "fresh_md5" => get_in_run(fresh, "rows_md5"),
      "fresh_tip" => get_in_run(fresh, "tip"),
      "committed_rows" => row_count(committed),
      "fresh_rows" => row_count(fresh)
    }

    if refusals != [] do
      Map.put(base, "verdict", "refused")
    else
      drift = diff(committed, fresh)
      verdict = if Enum.all?(@classes, &(drift[&1] == [])), do: "clean", else: "drift"
      base |> Map.merge(drift) |> Map.put("verdict", verdict)
    end
  end

  @doc "0 for clean, 1 for drift, 2 for refused."
  @spec exit_status(report()) :: 0 | 1 | 2
  def exit_status(%{"verdict" => "clean"}), do: 0
  def exit_status(%{"verdict" => "drift"}), do: 1
  def exit_status(%{"verdict" => "refused"}), do: 2

  # ---------------------------------------------------------------------------
  # Refusals — one function per guard, so each can be shown firing alone
  # ---------------------------------------------------------------------------

  @doc """
  Every refusal `artefact` earns, as `%{"guard", "side", "detail"}`. An artefact that
  fails RD1 is checked for nothing else, because no other field of it can be trusted.
  """
  @spec refusals(String.t(), term()) :: [map()]
  def refusals(side, artefact) do
    case rd1_schema(artefact) do
      nil ->
        [
          rd2_md5(artefact),
          rd3_incomplete(artefact),
          rd4_partial(artefact),
          rd5_host(artefact),
          rd6_dirty(artefact),
          rd7_red(artefact),
          rd8_collisions(artefact),
          rd9_consistency(artefact)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&tag(&1, side))

      refusal ->
        [tag(refusal, side)]
    end
  end

  defp tag({guard, detail}, side), do: %{"guard" => guard, "side" => side, "detail" => detail}

  @doc false
  def rd1_schema(%{"schema" => @rows_schema, "run" => run, "rows" => rows})
      when is_map(run) and is_list(rows),
      do: nil

  def rd1_schema(%{"schema" => s}) when s != @rows_schema,
    do: {"RD1", "schema #{inspect(s)}, not #{@rows_schema}"}

  def rd1_schema(_), do: {"RD1", "not an #{@rows_schema} artefact (no run map or rows list)"}

  @doc false
  def rd2_md5(%{"run" => run, "rows" => rows}) do
    actual = ExUnitRows.rows_md5(rows)

    if run["rows_md5"] == actual,
      do: nil,
      else: {"RD2", "recorded rows_md5 #{inspect(run["rows_md5"])}, rows hash to #{actual}"}
  end

  @doc false
  def rd3_incomplete(%{"run" => run}) do
    if run["complete"] == true and run["row_errors"] == [] and
         run["modules_started"] == run["modules_finished"],
       do: nil,
       else:
         {"RD3",
          "complete #{inspect(run["complete"])}, row_errors #{inspect(run["row_errors"], limit: 3)}, " <>
            "modules #{inspect(run["modules_started"])} started / " <>
            "#{inspect(run["modules_finished"])} finished"}
  end

  @doc false
  def rd4_partial(%{"run" => run}) do
    faults =
      [
        unless(whole_suite_argv?(run["argv"]), do: "argv #{inspect(run["argv"])}"),
        unless(run["include"] in [[], nil], do: "include #{inspect(run["include"])}"),
        unless(run["only_test_ids"] == nil,
          do: "only_test_ids #{inspect(run["only_test_ids"])}"
        ),
        unless(run["max_failures"] in [":infinity", nil],
          do: "max_failures #{inspect(run["max_failures"])}"
        )
      ]
      |> Enum.reject(&is_nil/1)

    if faults == [], do: nil, else: {"RD4", "not the whole suite: " <> Enum.join(faults, "; ")}
  end

  defp whole_suite_argv?(["test"]), do: true
  defp whole_suite_argv?(["test", "--seed", seed]), do: Regex.match?(~r/\A\d+\z/, seed)
  defp whole_suite_argv?(_), do: false

  @doc false
  def rd5_host(%{"run" => run}) do
    if run["exclude"] in [[], nil],
      do: nil,
      else: {"RD5", "exclude #{inspect(run["exclude"])}: a host-incomplete population (§5.1)"}
  end

  @doc false
  def rd6_dirty(%{"run" => run}) do
    if run["tree_clean"] == true and run["tree_dirty"] in [[], nil],
      do: nil,
      else:
        {"RD6",
         "tree_clean #{inspect(run["tree_clean"])}, tree_dirty #{inspect(run["tree_dirty"])}"}
  end

  @doc false
  def rd7_red(%{"run" => run, "rows" => rows}) do
    red = for r <- rows, r["status"] in @red, do: r["key"]
    rc = run["suite_rc"]

    cond do
      red != [] -> {"RD7", "#{length(red)} red row(s), first #{inspect(hd(red))}"}
      rc not in [0, nil] -> {"RD7", "the capture's mix test exited #{rc}"}
      true -> nil
    end
  end

  @doc false
  def rd8_collisions(%{"run" => run, "rows" => rows}) do
    dupes = ExUnitRows.key_collisions(rows)
    recorded = run["key_collisions"]

    if dupes == [] and recorded in [[], nil],
      do: nil,
      else: {"RD8", "duplicate keys #{inspect(dupes, limit: 3)}, recorded #{inspect(recorded)}"}
  end

  @doc false
  def rd9_consistency(%{"run" => run, "rows" => rows}) do
    bad = for r <- rows, r["key"] != "#{r["module"]}/#{r["name"]}", do: r["key"]

    disagreements =
      case run["module_cross_check"] do
        %{"disagreements" => d} when is_list(d) -> d
        _ -> []
      end

    if bad == [] and disagreements == [],
      do: nil,
      else:
        {"RD9",
         "#{length(bad)} row(s) whose key is not module/name#{first(bad)}, " <>
           "#{length(disagreements)} module_cross_check disagreement(s)"}
  end

  defp first([]), do: ""
  defp first([k | _]), do: " (first #{inspect(k)})"

  # ---------------------------------------------------------------------------
  # Drift — one function per class, so each can be mutated alone
  # ---------------------------------------------------------------------------

  @doc """
  The drift classes between two adjudicable artefacts, plus `rename_candidates`. Every
  list is sorted by key.
  """
  @spec diff(artefact(), artefact()) :: map()
  def diff(committed, fresh) do
    c = index(committed)
    f = index(fresh)
    shared = c |> Map.keys() |> Enum.filter(&Map.has_key?(f, &1)) |> Enum.sort()

    added = added(c, f)
    removed = removed(c, f)

    %{
      "added" => added,
      "removed" => removed,
      "moved" => moved(c, f, shared),
      "relined" => relined(c, f, shared),
      "refielded" => refielded(c, f, shared),
      "restatus" => restatus(c, f, shared),
      "rename_candidates" => rename_candidates(c, f, removed, added)
    }
  end

  defp index(%{"rows" => rows}), do: Map.new(rows, &{&1["key"], &1})

  @doc false
  def added(c, f), do: f |> Map.keys() |> Enum.reject(&Map.has_key?(c, &1)) |> Enum.sort()

  @doc false
  def removed(c, f), do: c |> Map.keys() |> Enum.reject(&Map.has_key?(f, &1)) |> Enum.sort()

  @doc false
  def moved(c, f, shared) do
    for k <- shared,
        c[k]["file"] != f[k]["file"],
        do: %{"key" => k, "from" => c[k]["file"], "to" => f[k]["file"]}
  end

  @doc false
  def relined(c, f, shared) do
    for k <- shared,
        c[k]["line"] != f[k]["line"],
        do: %{"key" => k, "file" => f[k]["file"], "from" => c[k]["line"], "to" => f[k]["line"]}
  end

  @doc false
  def refielded(c, f, shared) do
    for k <- shared,
        field <- @refields,
        c[k][field] != f[k][field],
        do: %{"key" => k, "field" => field, "from" => c[k][field], "to" => f[k][field]}
  end

  @doc false
  def restatus(c, f, shared) do
    for k <- shared,
        {c[k]["status"], c[k]["reason"]} != {f[k]["status"], f[k]["reason"]},
        do: %{"key" => k, "from" => c[k]["status"], "to" => f[k]["status"]}
  end

  defp rename_candidates(c, f, removed, added) do
    for r <- removed,
        a <- added,
        c[r]["file"] == f[a]["file"] and c[r]["line"] == f[a]["line"],
        do: %{"removed" => r, "added" => a, "file" => f[a]["file"], "line" => f[a]["line"]}
  end

  # ---------------------------------------------------------------------------
  # Capture
  # ---------------------------------------------------------------------------

  @doc """
  Capture the suite fresh: `mix test --seed 0` in `MIX_ENV=test`, with `MCP_ETCC_ROWS`
  naming `rows.json` inside a directory this call creates. `File.mkdir!/1` refuses a
  directory that already exists, so the path is private and freshly made, and no
  caller-supplied path is ever written, removed or captured into. Keeping the capture
  elsewhere is the caller's copy, guarded by `same_file?/2` (MES-240 F1). Returns
  `{artefact | :missing, rows_path, output}`. The suite's exit status is recorded in the
  artefact's `run.suite_rc`, which RD7 reads. The transcript is kept as `<rows>.log`.
  """
  @spec capture!() :: {artefact() | :missing, String.t(), String.t()}
  def capture! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "rows-drift-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(dir)
    path = Path.join(dir, "rows.json")

    {out, rc} =
      System.cmd("mix", ["test", "--seed", "0"],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}, {ExUnitRows.env_path_var(), path}]
      )

    File.write!(path <> ".log", out)

    artefact =
      with {:ok, bytes} <- File.read(path),
           {:ok, %{} = a} <- Jason.decode(bytes) do
        update_in(a, ["run"], &if(is_map(&1), do: Map.put(&1, "suite_rc", rc), else: &1))
      else
        _ -> :missing
      end

    {artefact, path, out}
  end

  # ---------------------------------------------------------------------------
  # Never-write: is an output path the protected file, by any name?
  # ---------------------------------------------------------------------------

  @doc """
  True when `a` and `b` name the same file. `Path.expand/1` is lexical: it does not
  resolve a symlink in a parent directory, and an output path written through such an
  alias overwrote a decoy committed file (MES-240 F1). So both paths are resolved with
  `real_path/1`, the way the kernel resolves them. Two paths that both exist are also
  compared by device and inode, which adds one case real paths cannot see, a hard link.
  It never repairs a wrong real path: a correct `real_path/1` is what decides.
  """
  @spec same_file?(Path.t(), Path.t()) :: boolean()
  def same_file?(a, b) do
    real_path(a) == real_path(b) or same_inode?(a, b)
  end

  defp same_inode?(a, b) do
    with {:ok, %File.Stat{inode: i, major_device: d}} <- File.stat(a),
         {:ok, %File.Stat{inode: ^i, major_device: ^d}} <- File.stat(b) do
      true
    else
      _ -> false
    end
  end

  @doc """
  The path the kernel would open, with every symlink resolved. A relative path is taken
  against the current directory. Components are walked left to right and nothing is
  collapsed first: a symlink is resolved (recursively, including the components of its
  target) BEFORE a following `..` is applied, so `a/link/../x` names `x` beside the link's
  target, not `a/x` (MES-240 R1-2). A missing component is kept as written, because an
  output file may not exist yet. More than 40 links raise. Pure Elixir: no `realpath`
  binary is used.
  """
  @spec real_path(Path.t()) :: String.t()
  def real_path(path), do: path |> absolute_parts() |> walk("/", 0)

  # The components of `path`, absolute against the cwd, with `.` and `..` left as written.
  defp absolute_parts(path) do
    abs = if Path.type(path) == :absolute, do: path, else: Path.join(File.cwd!(), path)
    ["/" | parts] = Path.split(abs)
    parts
  end

  defp walk(_, _, depth) when depth > 40, do: raise(ArgumentError, "too many symlinks")
  defp walk([], acc, _), do: acc
  defp walk([seg | rest], acc, depth) when seg in [".", ""], do: walk(rest, acc, depth)
  defp walk([".." | rest], acc, depth), do: walk(rest, Path.dirname(acc), depth)

  defp walk([seg | rest], acc, depth) do
    candidate = Path.join(acc, seg)

    case :file.read_link_all(candidate) do
      {:ok, target} ->
        target = to_string(target)

        case Path.split(target) do
          ["/" | parts] -> walk(parts ++ rest, "/", depth + 1)
          parts -> walk(parts ++ rest, acc, depth + 1)
        end

      {:error, _} ->
        walk(rest, candidate, depth)
    end
  end

  @doc """
  Write `bytes` to the output path `out`, unless `out` names a `protected` file by any
  route. The check is made HERE, at the write itself, and not only when the task starts:
  a link planted while the suite was being captured redirected the report onto a decoy
  committed file (MES-240 R1-1). Then the write goes to a temporary file created
  exclusively in `out`'s real directory and is renamed over the final name. A rename
  replaces a symlink at the final component rather than following it, and the real
  directory was resolved by the same check, so a link planted at either point after the
  check cannot redirect the write. Returns `:ok` or `{:refused, protected_path}`.
  """
  @spec write_output!(Path.t(), iodata(), [Path.t()]) :: :ok | {:refused, Path.t()}
  def write_output!(out, bytes, protected) do
    File.mkdir_p!(Path.dirname(out))

    case Enum.find(protected, &same_file?(out, &1)) do
      nil -> atomic_write!(out, bytes)
      p -> {:refused, p}
    end
  end

  defp atomic_write!(out, bytes) do
    dir = real_path(Path.dirname(out))
    target = Path.join(dir, Path.basename(out))
    tmp = Path.join(dir, ".rows-drift-#{System.unique_integer([:positive])}.tmp")
    File.write!(tmp, bytes, [:exclusive])
    File.rename!(tmp, target)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  @doc "The human-readable report. The last line is the verdict line."
  @spec render(report()) :: String.t()
  def render(%{"verdict" => "refused"} = r) do
    lines =
      for x <- r["refusals"], do: "  #{x["guard"]} (#{x["side"]}): #{x["detail"]}"

    guards = r["refusals"] |> Enum.map(& &1["guard"]) |> Enum.uniq() |> Enum.join(", ")

    Enum.join(
      ["REFUSED, nothing was compared:" | lines] ++
        ["rows-drift: REFUSED - #{guards} (a refusal is not a clean result)"],
      "\n"
    )
  end

  def render(r) do
    detail =
      for class <- @classes ++ ["rename_candidates"], r[class] != [] do
        ["#{class} (#{length(r[class])}):" | Enum.map(r[class], &"  #{entry(&1)}")]
        |> Enum.join("\n")
      end

    counts = Enum.map_join(@classes, ", ", &"#{length(r[&1])} #{&1}")

    md5 =
      if r["committed_md5"] == r["fresh_md5"],
        do: "committed md5 #{r["committed_md5"]} = fresh md5 #{r["fresh_md5"]}",
        else: "committed md5 #{r["committed_md5"]}, fresh md5 #{r["fresh_md5"]}"

    verdict = String.upcase(r["verdict"])

    Enum.join(
      detail ++
        [
          "rows-drift: #{verdict} - #{counts} " <>
            "(#{r["committed_rows"]} committed rows, #{r["fresh_rows"]} fresh; #{md5})"
        ],
      "\n"
    )
  end

  defp entry(k) when is_binary(k), do: k

  defp entry(%{"field" => fld} = e),
    do: "#{e["key"]}: #{fld} #{inspect(e["from"])} -> #{inspect(e["to"])}"

  defp entry(%{"removed" => r, "added" => a} = e),
    do: "#{e["file"]}:#{e["line"]} #{r}  =>  #{a}"

  defp entry(e), do: "#{e["key"]}: #{inspect(e["from"])} -> #{inspect(e["to"])}"

  defp get_in_run(%{"run" => %{} = run}, k), do: run[k]
  defp get_in_run(_, _), do: nil

  defp row_count(%{"rows" => rows}) when is_list(rows), do: length(rows)
  defp row_count(_), do: nil
end

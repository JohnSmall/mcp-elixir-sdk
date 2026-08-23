defmodule MCP.Conformance.ExUnitRows do
  @moduledoc """
  MES-83 (B3). Capture an ExUnit run as **one JSON row per runtime test**.

  ## What this is for

  C1 joins our own verdicts to the official suite's the same way it joins the
  two key sets. Before this module the ET side had no machine-readable result
  artefact at all — the only capture was console text, and console text carries
  a *summary*.

  ## The row key

  The unit and the key constraint are fixed by `docs/conformance/etcc-membership.md`
  §0 (ratified MES-67, landed at `ffc1a2f`). **That file is the authority; this
  module does not restate it.** The key's concrete form — the one MES-81 and
  MES-84 adopt — is `docs/conformance/etcc-row-key.md`, which is the single home
  for it.

  In code: `key/2` renders `{module, name}` as `inspect(module) <> "/" <> name`,
  with `name` verbatim — including the `test `/`doctest ` type prefix and the
  describe prefix ExUnit itself builds at `case.ex:701` and `case.ex:705`
  (`"\#{test_type} \#{describe} \#{name}"`). No normalisation, so B2a can
  reconstruct the key from source by that same rule.

  Uniqueness within a module is ExUnit's, by construction: it raises
  `"..." is already defined in <mod>` at `case.ex:710`. A collision in the
  artefact can therefore only come from *this module's* rendering being lossy,
  which is why `key_collisions/1` is computed and asserted empty rather than
  assumed.

  ## Three properties this module exists to hold

    * **Rows, never a summary** (S6-11). `totals` is *derived* from `rows` by
      `derive_totals/1` and is never maintained alongside them. A histogram
      cannot distinguish 2 from 11, and a projection discards a field
      invisibly — the artefact still looks complete.

    * **Excluded must not look like not-run** (S6-9). An excluded test gets a
      row, carrying ExUnit's own exclusion reason. "The test no longer exists"
      is then a *fourth* thing — absence of the key from `rows` — and is
      distinct from all five statuses precisely because excluded tests get a
      row. See `docs/conformance/etcc-row-key.md` §4 for the consumer's rule.

    * **Runtime tests, not source declarations** (S6-6). Rows come off
      `test_finished` events, so one `describe`/`for`/`doctest` construct
      produces its N runtime rows and a doctest gets a row like any other test.

  ## Discipline — this is an instrument, and it is OFF by default

  Ruled at MES-83's ratification. The formatter is attached only when
  `MCP_ETCC_ROWS` names an output path (`output_path/0`), following
  `MCP.Conformance.Beacon`'s in-tree precedent. Gate 5 runs on every ticket at
  three seats; a defect in an instrument this ticket owns must not be able to
  fail an unrelated ticket's gate. The cost — a plain `mix test` writes no
  artefact, so the committed copy can go stale silently — is bounded by
  `run.tip` being in the file, and **drift detection belongs to MES-84**.

  ## Determinism

  Row *content* does not depend on seed or ordering, and row *order* is
  canonical (sorted by `{module, name}` on write) so a diff is meaningful.
  Duration is deliberately not a field: it would make every run differ and
  destroy the diff. The fields that legitimately move between hosts and runs
  are enumerated in `docs/conformance/etcc-row-key.md` §5 — a diff confined to
  them is expected variation; a diff outside them is a finding.
  """

  use GenServer

  @schema "etcc-exunit-rows/1"
  @env_path "MCP_ETCC_ROWS"

  @statuses ~w(passed failed excluded skipped invalid)

  # Removed from the recorded tag map, with the reason each is removed:
  #
  #   * promoted to their own row field — :file :line :describe :test_type
  #   * ExUnit bookkeeping already keyed on — :module :test :registered
  #     :describe_line
  #   * PRESENT ONLY FOR TESTS THAT RAN — :async :test_group. `prepare_tests/4`
  #     (runner.ex:255-303) merges these four in while evaluating the filter and
  #     stores the merged map only on the to-run branch, so an excluded or
  #     skipped test keeps its original tags. Denying them is what makes the tag
  #     map identical between run states, and so host-independent.
  #
  # A deny-list with a stated reason is the S6-11-safe form of a projection. An
  # allow-list would drop tags nobody thought of, invisibly.
  @denied_tags [
    :async,
    :describe,
    :describe_line,
    :file,
    :line,
    :module,
    :registered,
    :test,
    :test_group,
    :test_type
  ]

  @typedoc "One captured runtime test, as written to the artefact."
  @type row :: %{optional(String.t()) => term()}

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  @doc "Name of the environment variable carrying the artefact's output path."
  @spec env_path_var() :: String.t()
  def env_path_var, do: @env_path

  @doc """
  The artefact path this run should write, or `nil` when capture is off.

  Read by `test/test_helper.exs` to decide whether to attach the formatter at
  all, and by `init/1` to decide whether to write. One function, used twice, so
  the two decisions cannot disagree.
  """
  @spec output_path() :: String.t() | nil
  def output_path do
    case System.get_env(@env_path) do
      nil -> nil
      "" -> nil
      path -> path
    end
  end

  @doc "The artefact's schema identifier."
  @spec schema_version() :: String.t()
  def schema_version, do: @schema

  @doc "The five statuses a row may carry."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Tag keys deliberately not recorded in a row's `tags` map."
  @spec denied_tags() :: [atom()]
  def denied_tags, do: @denied_tags

  # ---------------------------------------------------------------------------
  # The key, and rows
  # ---------------------------------------------------------------------------

  @doc """
  The row key: `inspect(module) <> "/" <> name`.

  A module name cannot contain `/`, so splitting on the FIRST `/` is lossless
  even though a test name may contain one.
  """
  @spec key(module(), atom() | String.t()) :: String.t()
  def key(module, name) when is_atom(name), do: key(module, Atom.to_string(name))
  def key(module, name) when is_binary(name), do: inspect(module) <> "/" <> name

  @doc "Split a key back into `{module, name}`, on the first `/`."
  @spec split_key(String.t()) :: {String.t(), String.t()}
  def split_key(key) when is_binary(key) do
    [module, name] = :binary.split(key, "/")
    {module, name}
  end

  @doc """
  Build one row from a finished `ExUnit.Test`.

  `cwd` relativises `file` so the artefact does not carry the checkout's
  absolute path — a worktree and a clone must produce the same bytes.
  """
  @spec row(ExUnit.Test.t(), String.t()) :: row()
  def row(%ExUnit.Test{} = test, cwd) do
    tags = test.tags
    {status, reason, failure} = classify(test.state)

    %{
      "key" => key(test.module, test.name),
      "module" => inspect(test.module),
      "name" => Atom.to_string(test.name),
      "test_type" => to_string(Map.get(tags, :test_type, :test)),
      "file" => relative_file(Map.get(tags, :file), cwd),
      "line" => Map.get(tags, :line),
      "describe" => Map.get(tags, :describe),
      "tags" => public_tags(tags),
      "status" => status,
      "reason" => reason,
      "failure" => failure
    }
  end

  @doc """
  Map an `t:ExUnit.state/0` onto `{status, reason, failure}`.

  Five states, because ExUnit distinguishes five (`ex_unit.ex:76-81`):
  `nil` is a pass; `{:failed, _}` a failure; `{:excluded, reason}` a filter
  decision; `{:skipped, reason}` an `@tag :skip`; `{:invalid, module}` a test
  that never ran because the module's `setup_all` failed — AC2's "errored", and
  neither a pass nor a failure.
  """
  @spec classify(ExUnit.state()) :: {String.t(), String.t() | nil, list() | nil}
  def classify(nil), do: {"passed", nil, nil}
  def classify({:excluded, reason}), do: {"excluded", to_string(reason), nil}
  def classify({:skipped, reason}), do: {"skipped", to_string(reason), nil}
  def classify({:failed, failures}), do: {"failed", nil, format_failures(failures)}

  def classify({:invalid, %ExUnit.TestModule{} = module}) do
    reason = "setup_all failed in #{inspect(module.name)}"
    {"invalid", reason, module_failure(module.state)}
  end

  # ---------------------------------------------------------------------------
  # Derivation — AC3
  # ---------------------------------------------------------------------------

  @doc """
  Derive the totals block from the rows. The ONLY producer of `totals`.

  `by_status` always carries all five keys, so a consumer joining on it never
  has to tell "zero" from "absent" — the same reason an excluded test gets a
  row.
  """
  @spec derive_totals([row()]) :: map()
  def derive_totals(rows) when is_list(rows) do
    by_status =
      Enum.reduce(rows, Map.new(@statuses, &{&1, 0}), fn row, acc ->
        Map.update(acc, row["status"], 1, &(&1 + 1))
      end)

    by_test_type =
      Enum.reduce(rows, %{}, fn row, acc ->
        Map.update(acc, row["test_type"], 1, &(&1 + 1))
      end)

    %{
      "total" => length(rows),
      "by_status" => by_status,
      "by_test_type" => by_test_type,
      "by_test_type_not_excluded" => not_excluded_by_type(rows)
    }
  end

  @doc """
  Per-type counts over rows that are NOT excluded.

  This is the shape ExUnit's own headline counts in: `update_test_counter/2`
  (`cli_formatter.ex:263-265`) returns the counter unchanged for
  `{:excluded, _reason}` and counts everything else by `test_type`. So this is
  the term `reconcile/2` compares against, and it is why the naive
  `rows == total` identity would be wrong.
  """
  @spec not_excluded_by_type([row()]) :: map()
  def not_excluded_by_type(rows) do
    rows
    |> Enum.reject(&(&1["status"] == "excluded"))
    |> Enum.reduce(%{}, fn row, acc -> Map.update(acc, row["test_type"], 1, &(&1 + 1)) end)
  end

  @doc "Keys appearing on more than one row, with their count. Empty by construction."
  @spec key_collisions([row()]) :: [map()]
  def key_collisions(rows) do
    rows
    |> Enum.frequencies_by(& &1["key"])
    |> Enum.filter(fn {_key, n} -> n > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {key, n} -> %{"key" => key, "rows" => n} end)
  end

  @doc "Canonical row order: `{module, name}`. Applied on write, so a diff is meaningful."
  @spec sort_rows([row()]) :: [row()]
  def sort_rows(rows), do: Enum.sort_by(rows, &{&1["module"], &1["name"]})

  @doc "md5 of the canonical encoding of `rows` — a content handle for MES-84's drift work."
  @spec rows_md5([row()]) :: String.t()
  def rows_md5(rows) do
    :md5 |> :crypto.hash(Jason.encode!(rows)) |> Base.encode16(case: :lower)
  end

  @doc """
  Assemble the artefact. `rows` are sorted and `totals` derived here, nowhere else.
  """
  @spec artefact([row()], map()) :: map()
  def artefact(rows, run) when is_list(rows) and is_map(run) do
    sorted = sort_rows(rows)

    %{
      "schema" => @schema,
      "run" => Map.merge(run, %{"rows_md5" => rows_md5(sorted)}),
      "totals" => derive_totals(sorted),
      "rows" => sorted
    }
  end

  @doc """
  Serialise the artefact, pretty, with the trailing newline the other artefacts carry.

  The four top-level members are written in reading order — `schema`, `run`,
  `totals`, `rows` — rather than in map order, so the header of a ~1000-row
  file is at the top where a reader diffing it is standing. Everything below
  that is plain maps, whose key order Erlang fixes for a given key set, so the
  bytes are still deterministic.
  """
  @spec encode(map()) :: String.t()
  def encode(artefact) do
    ordered =
      Jason.OrderedObject.new([
        {"schema", artefact["schema"]},
        {"run", artefact["run"]},
        {"totals", artefact["totals"]},
        {"rows", artefact["rows"]}
      ])

    Jason.encode!(ordered, pretty: true) <> "\n"
  end

  # ---------------------------------------------------------------------------
  # Reconciliation against ExUnit's own summary — AC1
  # ---------------------------------------------------------------------------

  @summary_re ~r/^(?<types>(?:\d+ \w+, )*)(?<failures>\d+) failures?(?:, (?<invalid>\d+) invalid)?(?:, (?<skipped>\d+) skipped)?(?: \((?<excluded>\d+) excluded\))?$/

  @doc """
  Find and parse ExUnit's own summary line out of a captured run's `output`.

  Grammar read off `print_summary/2` (`cli_formatter.ex:340-373`) rather than
  remembered: sorted per-type counts, then failures, then optional invalid,
  skipped and excluded terms.
  """
  @spec parse_summary(String.t()) :: {:ok, map()} | :error
  def parse_summary(output) when is_binary(output) do
    output
    |> strip_ansi()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reverse()
    |> Enum.find_value(:error, fn line ->
      case Regex.named_captures(@summary_re, line) do
        nil -> nil
        caps -> {:ok, summary_from(caps, line)}
      end
    end)
  end

  @doc """
  Check the artefact's totals against ExUnit's own summary line.

  **What this checks, and what it cannot.** Both numbers are computed from the
  SAME broadcast — `event_manager.ex:87-93` casts every event to every
  formatter — so this is *not* a check that the suite was fully discovered. A
  test that never reached the event manager (a module that failed to load,
  `--only-test-ids`, a `--max-failures` cut-off) is invisible to both sides and
  cancels. What it checks is the projection from events to rows, which is where
  S6-11's hazard actually lives.

  A mismatch is therefore *this module's* defect in both directions: fewer rows
  than ExUnit counted means a row was lost on write or two runtime tests
  rendered onto one key (`key_collisions/1` separates those); more rows means
  double-counting or the excluded rule mis-modelled. The one direction not
  attributable here — ExUnit's own summary miscounting — needs the second
  witness, which is `module_finished` (see `cross_check/2`).
  """
  @spec reconcile(String.t(), map()) :: map()
  def reconcile(output, totals) do
    case parse_summary(output) do
      :error ->
        %{"ok" => false, "error" => "no summary line found", "checks" => []}

      {:ok, summary} ->
        checks = summary_checks(summary, totals)

        %{
          "ok" => Enum.all?(checks, & &1["ok"]),
          "summary_line" => summary["line"],
          "checks" => checks
        }
    end
  end

  defp summary_checks(summary, totals) do
    by_type = totals["by_test_type_not_excluded"] || %{}

    type_checks =
      by_type
      |> Map.keys()
      |> Kernel.++(Map.keys(summary["by_type"]))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn type ->
        check("type:#{type}", Map.get(summary["by_type"], type, 0), Map.get(by_type, type, 0))
      end)

    type_checks ++
      [
        check("excluded", summary["excluded"], totals["by_status"]["excluded"]),
        check("skipped", summary["skipped"], totals["by_status"]["skipped"]),
        check("invalid", summary["invalid"], totals["by_status"]["invalid"]),
        check("failures", summary["failures"], totals["by_status"]["failed"])
      ]
  end

  # Fold a summary word back onto the test_type it counts — ExUnit prints the
  # singular at one and the plural otherwise (`pluralize/3`, cli_formatter.ex).
  # An unrecognised word is left AS THE WORD rather than guessed at, so it lands
  # on a type no row carries and surfaces as a DISAGREEing check. Folding it
  # onto something it is not would hide a whole category.
  defp to_test_type(word) do
    Enum.find(~w(test doctest property), word, &(&1 == word or ExUnit.plural_rule(&1) == word))
  end

  defp check(name, expected, actual) do
    %{"name" => name, "exunit" => expected, "rows" => actual, "ok" => expected == actual}
  end

  defp summary_from(caps, line) do
    by_word =
      ~r/(\d+) (\w+), /
      |> Regex.scan(caps["types"])
      |> Map.new(fn [_, n, word] -> {word, String.to_integer(n)} end)

    by_type =
      Enum.reduce(by_word, %{}, fn {word, n}, acc ->
        Map.update(acc, to_test_type(word), n, &(&1 + n))
      end)

    %{
      "line" => line,
      "by_word" => by_word,
      "by_type" => by_type,
      "failures" => to_int(caps["failures"]),
      "invalid" => to_int(caps["invalid"]),
      "skipped" => to_int(caps["skipped"]),
      "excluded" => to_int(caps["excluded"])
    }
  end

  defp to_int(""), do: 0
  defp to_int(nil), do: 0
  defp to_int(s), do: String.to_integer(s)

  defp strip_ansi(s), do: String.replace(s, ~r/\e\[[0-9;]*m/, "")

  # ---------------------------------------------------------------------------
  # The second witness — module_finished
  # ---------------------------------------------------------------------------

  @doc """
  Compare the keys seen on `test_finished` against the module's OWN test list.

  `module_finished` carries `%{test_module | tests: Enum.reverse(finished_tests,
  pending_tests)}` (`runner.ex:275`), assembled by a different code path from
  the counters. Its membership is **run tests plus invalid tests, and nothing
  else**: excluded and skipped tests are emitted earlier at `runner.ex:243-249`
  and are not joined back in, and `pending_tests` is `invalid_tests`
  (`runner.ex:255-265`), not the skipped ones. That membership is established by
  the control run, not taken from this comment.

  So the comparison is against event rows whose status is `passed`, `failed` or
  `invalid`. A disagreement catches a dropped `test_finished`, which the
  headline reconciliation cannot.
  """
  @spec cross_check(map(), map()) :: [map()]
  def cross_check(module_keys, event_keys) do
    module_keys
    |> Map.keys()
    |> Kernel.++(Map.keys(event_keys))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn module ->
      from_module = Map.get(module_keys, module, MapSet.new())
      from_events = Map.get(event_keys, module, MapSet.new())

      disagreement(module, MapSet.difference(from_module, from_events), "missing_from_events") ++
        disagreement(
          module,
          MapSet.difference(from_events, from_module),
          "missing_from_module_list"
        )
    end)
  end

  defp disagreement(module, diff, direction) do
    if MapSet.size(diff) == 0 do
      []
    else
      [%{"module" => module, "direction" => direction, "keys" => Enum.sort(MapSet.to_list(diff))}]
    end
  end

  # ---------------------------------------------------------------------------
  # Formatter
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       path: output_path(),
       cwd: File.cwd!(),
       opts: opts,
       rows: [],
       module_keys: %{},
       event_keys: %{},
       modules_started: 0,
       modules_finished: 0,
       max_failures_reached: false
     }}
  end

  @impl GenServer
  def handle_cast({:module_started, _module}, state) do
    {:noreply, %{state | modules_started: state.modules_started + 1}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    row = row(test, state.cwd)
    module = row["module"]

    event_keys =
      if row["status"] in ["passed", "failed", "invalid"] do
        Map.update(
          state.event_keys,
          module,
          MapSet.new([row["key"]]),
          &MapSet.put(&1, row["key"])
        )
      else
        state.event_keys
      end

    {:noreply, %{state | rows: [row | state.rows], event_keys: event_keys}}
  end

  def handle_cast({:module_finished, %ExUnit.TestModule{} = test_module}, state) do
    module = inspect(test_module.name)
    keys = MapSet.new(test_module.tests, &key(&1.module, &1.name))

    {:noreply,
     %{
       state
       | modules_finished: state.modules_finished + 1,
         module_keys: Map.update(state.module_keys, module, keys, &MapSet.union(&1, keys))
     }}
  end

  def handle_cast(:max_failures_reached, state) do
    {:noreply, %{state | max_failures_reached: true}}
  end

  def handle_cast({:suite_finished, _times}, state) do
    write(state)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp write(%{path: nil}), do: :noop

  defp write(state) do
    artefact = artefact(state.rows, run_block(state))
    File.mkdir_p!(Path.dirname(state.path))
    File.write!(state.path, encode(artefact))
    IO.puts(:stderr, "[etcc-rows] wrote #{state.path} (#{length(state.rows)} rows)")
    :ok
  rescue
    error ->
      # Never take the suite down: this is an instrument, and a run it perturbs
      # is a run it has falsified. The control checks the file exists and is
      # fresh, so a failure here is caught there rather than swallowed.
      IO.puts(:stderr, "[etcc-rows] FAILED to write #{state.path}: #{Exception.message(error)}")
      :error
  end

  defp run_block(state) do
    disagreements = cross_check(state.module_keys, state.event_keys)
    dirty = dirty_paths(state)

    %{
      "tip" => git("rev-parse", ["HEAD"]),
      "tree_clean" => dirty == [],
      "tree_dirty" => dirty,
      "seed" => state.opts[:seed],
      "exclude" => inspect_list(state.opts[:exclude]),
      "include" => inspect_list(state.opts[:include]),
      "only_test_ids" => if(state.opts[:only_test_ids], do: "set", else: nil),
      "max_failures" => inspect(state.opts[:max_failures]),
      "argv" => System.argv(),
      "elixir" => System.version(),
      "otp" => System.otp_release(),
      "complete" =>
        not state.max_failures_reached and state.modules_started == state.modules_finished,
      "modules_started" => state.modules_started,
      "modules_finished" => state.modules_finished,
      "key_collisions" => key_collisions(state.rows),
      "module_cross_check" => %{
        "modules" => map_size(state.module_keys),
        "compared" => state.module_keys |> Map.values() |> Enum.map(&MapSet.size/1) |> Enum.sum(),
        "disagreements" => disagreements
      }
    }
  end

  # The tree's state as a LIST, not just a boolean — "clean, and here is the
  # empty list" and "clean, take my word for it" print differently.
  #
  # The artefact's own path is excluded: it is the file being written, so it is
  # dirty by construction during the run that writes it, and counting it would
  # make `tree_clean` permanently false and therefore useless.
  defp dirty_paths(state) do
    own = state.path && Path.relative_to(Path.expand(state.path), state.cwd)

    case git("status", ["--porcelain"]) do
      nil ->
        []

      "" ->
        []

      out ->
        out
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(own && String.ends_with?(&1, " " <> own)))
        |> Enum.sort()
    end
  end

  defp git(command, args) do
    case System.cmd("git", [command | args], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp inspect_list(nil), do: []
  defp inspect_list(list), do: Enum.map(list, &inspect/1)

  # ---------------------------------------------------------------------------
  # Row helpers
  # ---------------------------------------------------------------------------

  defp relative_file(nil, _cwd), do: nil
  defp relative_file(file, cwd), do: Path.relative_to(file, cwd)

  defp public_tags(tags) do
    tags
    |> Map.drop(@denied_tags)
    |> Map.new(fn {k, v} -> {to_string(k), jsonable(v)} end)
  end

  defp jsonable(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: v
  defp jsonable(v) when is_atom(v), do: inspect(v)
  defp jsonable(v) when is_list(v), do: Enum.map(v, &jsonable/1)
  defp jsonable(%_{} = v), do: inspect(v)

  defp jsonable(v) when is_map(v),
    do: Map.new(v, fn {k, val} -> {to_string(k), jsonable(val)} end)

  defp jsonable(v), do: inspect(v)

  # Failure detail: enough to identify the failure, and nothing that moves per
  # run. `at` is the first stack frame inside the checkout, relativised.
  defp format_failures(failures) when is_list(failures) do
    Enum.map(failures, fn {kind, reason, stacktrace} ->
      %{
        "kind" => to_string(kind),
        "exception" => exception_name(kind, reason),
        "message" => failure_message(kind, reason),
        "at" => first_frame(stacktrace)
      }
    end)
  end

  defp format_failures(_), do: nil

  defp module_failure({:failed, failures}), do: format_failures(failures)
  defp module_failure(_), do: nil

  defp exception_name(:error, %{__struct__: struct}), do: inspect(struct)
  defp exception_name(kind, _reason), do: to_string(kind)

  defp failure_message(:error, %{__struct__: _} = exception), do: Exception.message(exception)
  defp failure_message(_kind, reason), do: inspect(reason)

  defp first_frame(stacktrace) when is_list(stacktrace) do
    Enum.find_value(stacktrace, fn
      {_m, _f, _a, info} ->
        with file when is_list(file) <- info[:file],
             line when is_integer(line) <- info[:line] do
          Path.relative_to(List.to_string(file), File.cwd!()) <> ":" <> Integer.to_string(line)
        else
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp first_frame(_), do: nil
end

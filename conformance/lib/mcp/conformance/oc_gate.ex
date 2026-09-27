defmodule MCP.Conformance.OcGate do
  @moduledoc """
  Gate 7 (MES-160, PO ruling 2026-09-27): **no test merges green while the
  official-conformance (OC) check it corresponds to is red.**

  `MCP.Conformance.OcGateDeclarations` supplies the population — the branch's
  new and changed tests, plus, when the branch changes `lib/`, every test
  already carrying `@tag oc:` check tokens — and what each declares. This
  module measures the named checks **live** and judges.

  ## The measurement is live, and the verdict is read off the checks

  For each leg a token names, the leg is run whole through the canonical
  `mix conformance.run` path (`MCP.Conformance.Runner`, `--requirements
  2026-07-28`) against the tree under review, and the run must pass
  `MCP.Conformance.Census.build/2` — the adjudicator's provenance judgement,
  pinned to the branch tip and to the pinned harness build's `dist/index.js`
  sha256 (`MCP.Conformance.HarnessHost.pinned_dist_sha256/0`), plus the census
  corroborations — before any figure is read from it. The committed census is never consulted: it can be stale.

  Each scenario's `checks.json` is keyed by `MCP.Conformance.InScope.key_checks/3`
  (the ratified discriminator rule), and each token is resolved by
  `MCP.Conformance.MatchKey.guard_state/2`. A token passes only when it
  resolves to exactly one row **and** that row's status is `"SUCCESS"`.
  `WARNING` and `SKIPPED` are refused like `FAILURE` (Q1): a check that cannot
  be SUCCESS cannot vouch for a test. The harness exit code is never read — it
  is 1 on both legs of a healthy tree.

  ## Fail-closed

  No `node`, no harness, a run the adjudicator refuses, a scenario that threw
  or was never run: each is a refusal of every token that needed it, never a
  skip. `judge/2` returns one verdict per declaration; a declaration with any
  refused token is refused.
  """

  alias MCP.Conformance.{Census, HarnessHost, InScope, MatchKey, Runner}
  alias MCP.Conformance.OcGateDeclarations, as: Decls

  @typedoc "What one leg's live measurement produced."
  @type measurement ::
          {:ok, %{rows: [map()], threw: %{String.t() => String.t()}, run_dir: String.t() | nil}}
          | {:error, atom(), String.t()}

  @typedoc "One declaration's verdict."
  @type verdict :: %{
          decl: map(),
          outcome: :pass | :none | :refuse,
          class: atom() | nil,
          detail: String.t(),
          checks: [
            %{token: String.t(), status: String.t() | nil, outcome: atom(), detail: String.t()}
          ]
        }

  # --- judging (pure) --------------------------------------------------------

  @doc "The legs a population's check tokens name, sorted."
  @spec legs([map()]) :: [String.t()]
  def legs(decls) do
    decls
    |> Enum.flat_map(fn d ->
      case Decls.classify(d) do
        {:tokens, ts} -> Enum.map(ts, &token_leg/1)
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp token_leg(t) do
    {:ok, %{leg: leg}} = MatchKey.decode(t)
    leg
  end

  @doc """
  Judge each declaration against the per-leg measurements (a map from leg to
  `t:measurement/0`). Pure: everything live happened before this call.
  """
  @spec judge([map()], %{String.t() => measurement()}) :: [verdict()]
  def judge(decls, measurements), do: Enum.map(decls, &judge_one(&1, measurements))

  defp judge_one(decl, measurements) do
    case Decls.classify(decl) do
      {:refuse, class, detail} ->
        %{decl: decl, outcome: :refuse, class: class, detail: detail, checks: []}

      {:none, reason} ->
        %{decl: decl, outcome: :none, class: nil, detail: "oc: none — #{reason}", checks: []}

      {:tokens, tokens} ->
        checks = Enum.map(tokens, &check(&1, measurements))

        case Enum.find(checks, &(&1.outcome != :pass)) do
          nil ->
            %{decl: decl, outcome: :pass, class: nil, detail: "", checks: checks}

          first ->
            %{
              decl: decl,
              outcome: :refuse,
              class: first.outcome,
              detail: first.detail,
              checks: checks
            }
        end
    end
  end

  defp check(token, measurements) do
    {:ok, decoded} = MatchKey.decode(token)

    case Map.get(measurements, decoded.leg) do
      nil ->
        refused(token, :not_measured, "the #{decoded.leg} leg was not measured")

      {:error, class, detail} ->
        refused(token, class, detail)

      {:ok, %{rows: rows, threw: threw}} ->
        from_rows(token, decoded, rows, threw)
    end
  end

  defp from_rows(token, decoded, rows, threw) do
    in_run? = Enum.any?(rows, &(Enum.at(&1["key"], 1) == decoded.scenario))

    case {Map.fetch(threw, decoded.scenario), in_run?} do
      {{:ok, msg}, _} ->
        refused(token, :not_observed, "scenario #{decoded.scenario} threw: #{msg}")

      {:error, false} ->
        refused(token, :not_observed, "scenario #{decoded.scenario} is not in the live run")

      {:error, true} ->
        resolve(token, decoded, rows)
    end
  end

  defp resolve(token, decoded, rows) do
    case MatchKey.guard_state(token, Enum.map(rows, & &1["key"])) do
      {:matched, key} ->
        %{"status" => status} = Enum.find(rows, &(&1["key"] == key))

        if status == "SUCCESS",
          do: %{token: token, status: status, outcome: :pass, detail: ""},
          else: %{
            token: token,
            status: status,
            outcome: :not_success,
            detail: "#{token} is #{status} in the live run"
          }

      {:error, {reason, _}} ->
        unresolved(token, decoded, rows, reason)
    end
  end

  # MatchKey resolves the discriminator EXACTLY, so a bare token on a tied check
  # (HttpServerMetaInvalid400 x3, told apart only by details.fieldIssue) finds
  # no row at all. That is reported as what it is — ambiguous — with the
  # discriminators that would resolve it, rather than as a typo.
  defp unresolved(token, decoded, rows, reason) do
    siblings = Enum.filter(rows, &same_check?(&1, decoded))
    discs = Enum.map_join(siblings, ", ", &"##{&1["discriminator"]}")

    cond do
      siblings != [] and (decoded.discriminator == "" or match?({:ambiguous, _}, reason)) ->
        refused(
          token,
          :ambiguous,
          "#{token} matches #{length(siblings)} rows; add one of #{discs}"
        )

      siblings != [] ->
        refused(
          token,
          :unresolved,
          "#{token}: no row carries that discriminator; rows are #{discs}"
        )

      true ->
        refused(
          token,
          :unresolved,
          "#{token} names no check in the live run (#{inspect(reason)})"
        )
    end
  end

  defp same_check?(row, d) do
    [_leg, scenario, id, name | _] = row["key"]
    {scenario, id, name} == {d.scenario, d.check_id, d.name}
  end

  defp refused(token, class, detail),
    do: %{token: token, status: nil, outcome: class, detail: detail}

  # --- measuring (live) ------------------------------------------------------

  @doc """
  Measure one leg live against the tree at `tip`. Options: `:harness_dir`,
  `:out_root` (default `/tmp/mes-oc-gate`), `:label`.
  """
  @spec measure(String.t(), String.t(), keyword()) :: measurement()
  def measure(leg, tip, opts \\ []) do
    harness_dir = Keyword.get(opts, :harness_dir, HarnessHost.default_harness_dir())

    case HarnessHost.unavailable_reason(harness_dir) do
      nil -> run_leg(leg, tip, harness_dir, opts)
      reason -> {:error, :harness_unavailable, reason}
    end
  end

  defp run_leg(leg, tip, harness_dir, opts) do
    stamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(~r/[^0-9TZ]/, "")
    label = Keyword.get(opts, :label, "gate")
    out = Path.join(Keyword.get(opts, :out_root, "/tmp/mes-oc-gate"), "#{label}-#{leg}-#{stamp}")

    case run_runner(leg, harness_dir, out) do
      {:ok, run_dir} -> accept(leg, run_dir, tip)
      {:error, detail} -> {:error, :run_not_accepted, "the #{leg} leg did not run: #{detail}"}
    end
  end

  defp run_runner(leg, harness_dir, out) do
    guard_runner(fn ->
      Runner.run(leg: String.to_existing_atom(leg), harness_dir: harness_dir, out_dir: out)
    end)
  end

  @doc false
  # A runner that raises, exits or throws — or returns anything but
  # `{:ok, _, run_dir}`, which is a MatchError here — is a refusal like any
  # other, so the task keeps its one-final-line contract (MES-160 N1, N5). An
  # exit SIGNAL from a linked process is not an `exit/1` in this process and is
  # not caught here: it takes the task down, and the status stays nonzero.
  @spec guard_runner((-> term())) :: {:ok, String.t()} | {:error, String.t()}
  def guard_runner(run) do
    {:ok, _manifest, run_dir} = run.()
    {:ok, run_dir}
  rescue
    e -> {:error, Exception.message(e)}
  catch
    kind, reason when kind in [:exit, :throw] -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp accept(leg, run_dir, tip) do
    # Pinned to the tip AND to the pinned harness build: a run by any other
    # dist is refused by the adjudicator as HARNESS_MISMATCH (MES-160 B2).
    case Census.build(run_dir,
           expect_commit: tip,
           expect_harness_dist_sha256: HarnessHost.pinned_dist_sha256()
         ) do
      {:ok, census} -> {:ok, rows(leg, run_dir, census)}
      {:refused, code, detail} -> {:error, :run_not_accepted, "#{run_dir}: #{code}: #{detail}"}
    end
  end

  @doc false
  # Every scenario's keyed rows, and the scenarios that threw (no checks.json).
  @spec rows(String.t(), String.t(), map()) :: map()
  def rows(leg, run_dir, census) do
    {thrown, read} = Enum.split_with(census["scenarios"], &(&1["checks_source"] != "artefacts"))

    rows =
      Enum.flat_map(read, fn s ->
        checks = run_dir |> Path.join(s["artefact_dir"]) |> Path.join("checks.json")
        InScope.key_checks(leg, s["id"], checks |> File.read!() |> Jason.decode!())
      end)

    %{
      rows: rows,
      threw: Map.new(thrown, &{&1["id"], to_string(&1["threw"])}),
      run_dir: run_dir
    }
  end
end

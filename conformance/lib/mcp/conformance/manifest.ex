defmodule MCP.Conformance.Manifest do
  @moduledoc """
  The run-level provenance record, and the adjudication that decides whether a
  run may be quoted.

  ## The defect this answers

  The conformance harness's saved `-o` artefacts contain no run-level metadata
  of any kind: a scenario directory holds `checks.json`, `stdout.txt` and
  `stderr.txt`, and the run root holds nothing at all. Every figure this project
  has published — 35/37, 33/37, 29/37, 8/32, 7/32, 6/7, 6/37, 2/32, into docs,
  into ADR-003 and into a consumer-facing claim draft — is tied to the tree that
  produced it by an operator having written it down. Four incidents reduce to
  that one missing field.

  ## Shape

  `build/1` is pure: it turns a collected map into the nested record written as
  `manifest.json` at the run root. `judge/3` is pure: it turns a manifest plus
  what the run directory looks like *now* into `:ok` or a refusal. Everything
  that touches the world lives in `MCP.Conformance.Provenance` — the one call
  this module makes into it, `covers_root?/2`, is a path predicate that reads
  nothing.

  ## What `judge/3` guarantees about missing inputs

  Its first check is `check_complete/3`, and the property it establishes is the
  one every later comparison depends on: **no comparison in `judge/3` can be
  reached with an operand that is absent or, if judged, null.** Every field in
  `@field_dispositions` must be present; every field the table marks as consumed
  by a refusal condition must also be non-null. Otherwise `MANIFEST_INCOMPLETE`.

  This is a class fix, not three instance fixes. A manifest is decoded JSON, so
  an absent key arrives as `nil`, and `nil` reads as *satisfied* under `==`, `>`
  and truthiness alike. Measured before the check existed: 47 of the 54 fields a
  manifest carries could be deleted outright and `judge/3` still returned `:ok`.
  A control that passes when it cannot see is precisely the failure this ticket
  was opened about — a null run and an unrun check producing identical
  artefacts — reproduced inside the tool built to detect it.

  ## Refusal, not warning (R4)

  `judge/3` returns `{:refused, code, detail}`. The Mix task exits non-zero and
  prints no census. A warning is a gate that can be ignored while continuing to
  look like one.

  ## What an accepted manifest does NOT establish (R5)

  An accepted manifest makes a figure **attributable**, not **correct**. It ties
  a number to a tree; it says nothing about whether the number is a good
  measurement of conformance. See `MCP.Conformance.Manifest.residual/0` for the
  enumerated bound.
  """

  alias MCP.Conformance.Provenance

  @schema_version 1

  # The refusal conditions `read/1` decides, ahead of the ten `checks/0` tests.
  @read_codes [:MANIFEST_ABSENT, :MANIFEST_UNREADABLE]

  @doc "Schema version this build writes and is willing to read."
  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  @doc "Filename of the manifest at the run root."
  @spec filename() :: String.t()
  def filename, do: "manifest.json"

  @doc "Filename of the captured run-level console output at the run root."
  @spec console_filename() :: String.t()
  def console_filename, do: "console.txt"

  @doc "Filename of the beacon journal at the run root."
  @spec beacon_filename() :: String.t()
  def beacon_filename, do: "beacon.jsonl"

  # C5: every field is either consumed by a refusal condition or explicitly
  # labelled provenance-only. A field nobody reads is decoration, and this table
  # is what keeps that honest — `manifest_test.exs` asserts that every field a
  # built manifest actually carries appears here, so an unlabelled field added
  # later fails gate 5 rather than sliding in.
  @field_dispositions %{
    "schema_version" => :MANIFEST_UNREADABLE,
    "leg" => :provenance_only,
    "git.commit_sha_start" => :COMMIT_MISMATCH,
    "git.commit_sha_end" => :COMMIT_MOVED_MID_RUN,
    "git.branch_start" => :provenance_only,
    "git.branch_end" => :provenance_only,
    "git.worktree_root" => :DIRTY_EXCLUSION_COVERS_ROOT,
    "git.dirty_start" => :WORKTREE_DIRTY,
    "git.dirty_end" => :WORKTREE_DIRTY,
    "git.dirty_digest_start" => :provenance_only,
    "git.dirty_digest_end" => :provenance_only,
    "git.dirty_entries_start" => :provenance_only,
    "git.dirty_entries_end" => :provenance_only,
    # `dirty_entries` is truncated to 50; the count is what makes the truncation
    # visible rather than silent (A2d).
    "git.dirty_entry_count_start" => :provenance_only,
    "git.dirty_entry_count_end" => :provenance_only,
    "git.dirty_excluded_paths" => :DIRTY_EXCLUSION_COVERS_ROOT,
    "git.dirty_exclusions_rejected" => :DIRTY_EXCLUSION_COVERS_ROOT,
    "harness.install_dir" => :provenance_only,
    "harness.dist_path" => :provenance_only,
    "harness.dist_sha256" => :HARNESS_MISMATCH,
    "harness.version_declared" => :provenance_only,
    "harness.version_reported" => :provenance_only,
    "harness.node_version" => :provenance_only,
    "requirements.revision" => :provenance_only,
    "requirements.path" => :provenance_only,
    "requirements.exists" => :provenance_only,
    "requirements.md5" => :HARNESS_MISMATCH,
    "requirements.sha256" => :provenance_only,
    "invocation.argv" => :provenance_only,
    "invocation.cwd" => :CWD_NOT_PROJECT_ROOT,
    "invocation.project_root" => :CWD_NOT_PROJECT_ROOT,
    "invocation.cwd_is_project_root" => :CWD_NOT_PROJECT_ROOT,
    "invocation.adapter_command" => :provenance_only,
    "invocation.out_dir" => :provenance_only,
    "invocation.compiled_before_run" => :provenance_only,
    "timing.started_at" => :provenance_only,
    "timing.ended_at" => :provenance_only,
    "timing.utc_offset" => :provenance_only,
    "timing.duration_ms" => :provenance_only,
    "toolchain.elixir" => :provenance_only,
    "toolchain.otp" => :provenance_only,
    "toolchain.mix_env" => :provenance_only,
    "beacon.token" => :provenance_only,
    "beacon.preflight_ok" => :BEACON_PREFLIGHT_FAILED,
    "beacon.preflight_detail" => :provenance_only,
    "beacon.adapter_count" => :ADAPTER_NEVER_STARTED,
    "beacon.preflight_count" => :provenance_only,
    "beacon.foreign_lines" => :ARTEFACTS_INCONSISTENT,
    "beacon.unparseable_lines" => :ARTEFACTS_INCONSISTENT,
    "beacon.adapter_sources" => :provenance_only,
    # The harness exits non-zero whenever any scenario fails, which is the
    # NORMAL state of a run of this SDK. Making it a refusal condition would
    # refuse every real run — C3's failure mode by another route — so it is
    # recorded and not judged. Deliberate.
    "result.harness_exit_code" => :provenance_only,
    "result.console_sha256" => :ARTEFACTS_INCONSISTENT,
    "result.console_bytes" => :provenance_only,
    "result.scenario_dir_count" => :ARTEFACTS_INCONSISTENT,
    "result.scenario_dirs" => :ARTEFACTS_INCONSISTENT
  }

  @doc """
  Field-by-field disposition: the refusal condition that consumes each field, or
  `:provenance_only` when nothing judges it (C5).
  """
  @spec field_dispositions() :: %{String.t() => atom()}
  def field_dispositions, do: @field_dispositions

  @doc "The refusal conditions `read/1` decides, ahead of the ones `judge/3` does."
  @spec read_codes() :: [atom()]
  def read_codes, do: @read_codes

  @doc """
  Every refusal condition the adjudicator can raise, in the order it tests them:
  `read_codes/0` first, then `judged_codes/0`.
  """
  @spec refusal_codes() :: [atom()]
  def refusal_codes do
    [
      :MANIFEST_ABSENT,
      :MANIFEST_UNREADABLE,
      :MANIFEST_INCOMPLETE,
      :CWD_NOT_PROJECT_ROOT,
      :COMMIT_MISMATCH,
      :COMMIT_MOVED_MID_RUN,
      :DIRTY_EXCLUSION_COVERS_ROOT,
      :WORKTREE_DIRTY,
      :BEACON_PREFLIGHT_FAILED,
      :ADAPTER_NEVER_STARTED,
      :HARNESS_MISMATCH,
      :ARTEFACTS_INCONSISTENT
    ]
  end

  @doc """
  What an accepted manifest does not establish (R5, AC5). Enumerated rather than
  summarised: claiming a bound that does not hold is the error this sprint
  exists to avoid.
  """
  @spec residual() :: [String.t()]
  def residual do
    [
      "A checkout that moves away and returns before the run ends is invisible: " <>
        "commit_sha_start and commit_sha_end agree and the middle is unobserved. " <>
        "Three seats share one clone, so this is not hypothetical.",
      "Attribution is run-level, never per-scenario. The manifest cannot say which " <>
        "tree any individual checks.json was measured against.",
      "It binds SOURCE, not the BEAMS that ran. The runner compiles before launching " <>
        "the adapter and records that it did; the residual after that is dependency " <>
        "beams, which it does not bind.",
      "The beacon proves our adapter started with this run's token. It does not prove " <>
        "every scenario used it — only that at least one did, plus a count to compare.",
      "Timestamps inherit the container clock. A wrong clock yields wrong stamps and " <>
        "nothing here detects that.",
      "Most important: an accepted manifest makes a figure ATTRIBUTABLE, not CORRECT. " <>
        "It ties a number to a tree. Whether the number is a good measurement of " <>
        "conformance is decided by the adapters' own fidelity — MES-56/57's problem, " <>
        "not this tooling's."
    ]
  end

  @doc "Build the nested manifest record from a collected map."
  @spec build(map()) :: map()
  def build(c) do
    %{
      "schema_version" => @schema_version,
      "leg" => c.leg,
      "git" => %{
        "commit_sha_start" => c.git_start["commit_sha"],
        "commit_sha_end" => c.git_end["commit_sha"],
        "branch_start" => c.git_start["branch"],
        "branch_end" => c.git_end["branch"],
        "worktree_root" => c.git_start["worktree_root"],
        "dirty_start" => c.git_start["dirty"],
        "dirty_end" => c.git_end["dirty"],
        "dirty_digest_start" => c.git_start["dirty_digest"],
        "dirty_digest_end" => c.git_end["dirty_digest"],
        "dirty_entries_start" => c.git_start["dirty_entries"],
        "dirty_entries_end" => c.git_end["dirty_entries"],
        "dirty_entry_count_start" => c.git_start["dirty_entry_count"],
        "dirty_entry_count_end" => c.git_end["dirty_entry_count"],
        "dirty_excluded_paths" => c.git_start["dirty_excluded_paths"],
        "dirty_exclusions_rejected" => c.git_start["dirty_exclusions_rejected"]
      },
      "harness" => c.harness,
      "requirements" => c.requirements,
      "invocation" => c.invocation,
      "timing" => c.timing,
      "toolchain" => c.toolchain,
      "beacon" => c.beacon,
      "result" => c.result
    }
  end

  @doc "Serialise a manifest to pretty JSON."
  @spec encode(map()) :: String.t()
  def encode(manifest), do: Jason.encode!(manifest, pretty: true)

  @doc """
  Read the manifest at the root of `run_dir`.

  Returns `{:refused, :MANIFEST_ABSENT, _}` for a run directory with no
  manifest — which is every run this project has ever produced, and the point.
  """
  @spec read(String.t()) :: {:ok, map()} | {:refused, atom(), String.t()}
  def read(run_dir) do
    path = Path.join(run_dir, filename())

    with {:read, {:ok, body}} <- {:read, File.read(path)},
         {:decode, {:ok, m}} <- {:decode, Jason.decode(body)},
         {:schema, %{"schema_version" => @schema_version}} <- {:schema, m} do
      {:ok, m}
    else
      {:read, {:error, reason}} ->
        {:refused, :MANIFEST_ABSENT,
         "no #{filename()} at #{path} (#{:file.format_error(reason)})"}

      {:decode, {:error, _}} ->
        {:refused, :MANIFEST_UNREADABLE, "#{path} is not valid JSON"}

      {:schema, %{"schema_version" => v}} ->
        {:refused, :MANIFEST_UNREADABLE,
         "schema_version #{inspect(v)} is not #{@schema_version}, which this build reads"}

      {:schema, _} ->
        {:refused, :MANIFEST_UNREADABLE, "manifest carries no schema_version"}
    end
  end

  @doc """
  Judge a manifest. Pure.

  `observed` describes the run directory as it stands now (`:scenario_dirs`,
  `:console_sha256`). `expect` carries what the caller requires:
  `:commit` (the tree under review), and optionally `:requirements_md5` and
  `:harness_dist_sha256`.

  Checks run in the order `checks/0` lists and the first refusal halts, so the
  code returned is the *earliest* thing wrong with the run rather than an
  arbitrary one. `check_complete/3` leads deliberately: until the record is
  known to be whole there is nothing the later comparisons could honestly say.
  """
  @spec judge(map(), map(), map()) :: :ok | {:refused, atom(), String.t()}
  def judge(m, observed, expect) do
    Enum.reduce_while(checks(), :ok, fn {_code, check}, _acc ->
      case check.(m, observed, expect) do
        :ok -> {:cont, :ok}
        refusal -> {:halt, refusal}
      end
    end)
  end

  @doc """
  Diagnose a run: every refusal condition's status, none of them halting.

  `judge/3` halts at the first refusal, which is right for a verdict and wrong
  for an operator trying to see what a run's problems *are*. This reports all
  twelve conditions in the order they are tested, each `:ok`,
  `{:refused, detail}` or `{:not_evaluated, why}`.

  It takes the *result* of `read/1` rather than a manifest, so the two
  read-stage conditions are reported alongside the ten judged ones rather than
  being invisible in the mode whose whole purpose is visibility.

  **This is a diagnosis, not a verdict, and no caller may treat it as one.**
  A returned list carrying no refusal is not acceptance: `judge/3` is the only
  function that accepts, and `mix conformance.adjudicate --diagnose` — the only
  caller of this one — exits non-zero unconditionally.

  `check_complete/3` refusing collapses everything below it to
  `:not_evaluated` rather than running it anyway. That is not caution: past
  `check_complete/3`, no comparison can receive an operand that is absent or
  null, and running the later checks without it would report exactly the kind of
  pass-when-it-cannot-see that this ticket exists to remove.
  """
  @spec diagnose(map() | {:refused, atom(), String.t()}, map(), map()) ::
          [{atom(), :ok | {:refused, String.t()} | {:not_evaluated, String.t()}}]
  def diagnose({:refused, code, detail}, _observed, _expect) do
    halted_at(code, detail, "no manifest could be read, so there was nothing to compare")
  end

  def diagnose(m, observed, expect) do
    [{complete_code, complete} | rest] = checks()

    case complete.(m, observed, expect) do
      {:refused, code, detail} ->
        halted_at(
          code,
          detail,
          "the manifest is incomplete, so this comparison would read an operand that is " <>
            "absent or null — and nil compares as satisfied"
        )

      :ok ->
        read_codes_ok() ++
          [{complete_code, :ok}] ++
          Enum.map(rest, &status_of(&1, m, observed, expect))
    end
  end

  # One condition's status. The pin on `^code` is deliberate: it asserts the
  # pairing in `checks/0` rather than trusting it, so a check wired to the wrong
  # code raises here instead of reporting under a condition it cannot raise.
  defp status_of({code, check}, m, observed, expect) do
    case check.(m, observed, expect) do
      :ok -> {code, :ok}
      {:refused, ^code, detail} -> {code, {:refused, detail}}
    end
  end

  # Every condition before `code` was tested and passed; `code` refused; every
  # condition after it was never reached. Stated per-condition rather than
  # summarised, so the report never implies a check it did not run.
  defp halted_at(code, detail, why_not_evaluated) do
    all = refusal_codes()
    at = Enum.find_index(all, &(&1 == code))

    all
    |> Enum.with_index()
    |> Enum.map(fn
      {^code, _} -> {code, {:refused, detail}}
      {c, i} when i < at -> {c, :ok}
      {c, _} -> {c, {:not_evaluated, why_not_evaluated}}
    end)
  end

  # Reaching `judge/3` at all means `read/1` returned a manifest.
  defp read_codes_ok, do: Enum.map(@read_codes, &{&1, :ok})

  # Each check is paired with the ONE code it can return, so `diagnose/3` can
  # name a condition that did not fire. `manifest_test.exs` pins the pairing
  # both ways: every code here is one `refusal_codes/0` lists, and the codes
  # here plus `read_codes/0` are exactly that list, in that order.
  defp checks do
    [
      {:MANIFEST_INCOMPLETE, &check_complete/3},
      {:CWD_NOT_PROJECT_ROOT, &check_cwd/3},
      {:COMMIT_MISMATCH, &check_commit_match/3},
      {:COMMIT_MOVED_MID_RUN, &check_commit_stable/3},
      {:DIRTY_EXCLUSION_COVERS_ROOT, &check_dirty_exclusions/3},
      {:WORKTREE_DIRTY, &check_clean/3},
      {:BEACON_PREFLIGHT_FAILED, &check_preflight/3},
      {:ADAPTER_NEVER_STARTED, &check_adapter_started/3},
      {:HARNESS_MISMATCH, &check_harness/3},
      {:ARTEFACTS_INCONSISTENT, &check_artefacts/3}
    ]
  end

  @doc "The refusal conditions `judge/3` tests, in the order it tests them."
  @spec judged_codes() :: [atom()]
  def judged_codes, do: Enum.map(checks(), &elem(&1, 0))

  # The class fix. Every comparison below reads its operands out of a decoded
  # JSON map, where an absent key yields `nil` — and `nil` then compares as
  # *satisfied* under `==`, `>` and truthiness. Measured before this check
  # existed: of the 54 fields a manifest carries, 47 could be deleted outright
  # and `judge/3` still returned `:ok` (one, `git.dirty_start`, raised instead).
  # A control that passes when it cannot see is the exact defect this ticket
  # exists to fix, so it is fixed as a class rather than a list of instances.
  #
  # The rule is driven off `@field_dispositions`, which `manifest_test.exs`
  # already pins to what `build/1` actually writes:
  #
  #   * a CONSUMED field (one a refusal condition reads) must be present AND
  #     non-nil — nothing may be judged against an operand that is not there;
  #   * a PROVENANCE-ONLY field must be present, but may be `null` — "we looked
  #     and could not tell" is legitimate provenance, whereas a missing key
  #     means this manifest was not written by this tooling.
  #
  # The guarantee that follows, and the property to hold this to: past
  # `check_complete/3`, no later comparison can receive a missing operand.
  defp check_complete(m, _o, _e) do
    {missing, null} =
      Enum.reduce(@field_dispositions, {[], []}, fn {field, disposition}, {missing, null} ->
        case lookup(m, String.split(field, ".")) do
          :absent -> {[field | missing], null}
          {:ok, nil} when disposition != :provenance_only -> {missing, [field | null]}
          {:ok, _} -> {missing, null}
        end
      end)

    cond do
      missing != [] ->
        refuse(
          :MANIFEST_INCOMPLETE,
          "#{length(missing)} field(s) absent from the manifest: " <>
            "#{inspect(Enum.sort(missing))}. An absent field is read as nil by every " <>
            "comparison below it, and nil compares as satisfied — so a partial manifest " <>
            "would be accepted by checks that never ran."
        )

      null != [] ->
        refuse(
          :MANIFEST_INCOMPLETE,
          "#{length(null)} field(s) are null that a refusal condition judges: " <>
            "#{inspect(Enum.sort(null))}. A null operand cannot be compared, and a " <>
            "comparison that cannot run must not report a pass."
        )

      true ->
        :ok
    end
  end

  # Deliberately distinguishes an absent key from a present `null`; `Map.get/2`
  # cannot, and that conflation is the bug.
  defp lookup(value, []), do: {:ok, value}

  defp lookup(%{} = map, [key | rest]) do
    case Map.fetch(map, key) do
      {:ok, v} -> lookup(v, rest)
      :error -> :absent
    end
  end

  defp lookup(_not_a_map, _path), do: :absent

  # The message renders `cwd_is_project_root` — the field this condition actually
  # judges — and demotes the two strings to context. Rendering them as the
  # comparison made a string-only forgery print two identical paths either side of
  # "is not", which reads as a malfunctioning instrument rather than a refused run.
  defp check_cwd(m, _o, _e) do
    inv = m["invocation"]

    if inv["cwd_is_project_root"] do
      :ok
    else
      refuse(
        :CWD_NOT_PROJECT_ROOT,
        "the runner recorded invocation.cwd_is_project_root = " <>
          "#{inspect(inv["cwd_is_project_root"])}: this run did not start from the project " <>
          "root. Recorded paths, as context and not as the field judged: cwd " <>
          "#{inspect(inv["cwd"])}, project_root #{inspect(inv["project_root"])}"
      )
    end
  end

  defp check_commit_match(m, _o, e) do
    expected = Map.get(e, :commit)
    actual = m["git"]["commit_sha_start"]

    cond do
      is_nil(expected) -> :ok
      expected == actual -> :ok
      true -> refuse(:COMMIT_MISMATCH, "run measured #{actual}; tree under review is #{expected}")
    end
  end

  defp check_commit_stable(m, _o, _e) do
    g = m["git"]

    if g["commit_sha_start"] == g["commit_sha_end"] do
      :ok
    else
      refuse(
        :COMMIT_MOVED_MID_RUN,
        "HEAD moved during the run: #{g["commit_sha_start"]} -> #{g["commit_sha_end"]}"
      )
    end
  end

  # B1. `dirty_excluded_paths` narrows the dirty computation so that a run whose
  # artefacts land inside the repository does not dirty the tree it measures
  # (C3). An exclusion that equals or contains the worktree root does not narrow
  # it — it switches it off, and `WORKTREE_DIRTY` then passes over a tree with
  # uncommitted edits. Judged from the manifest rather than trusted from the
  # writer, so a hand-written manifest cannot assert its way past it.
  defp check_dirty_exclusions(m, _o, _e) do
    g = m["git"]
    root = g["worktree_root"]
    covering = Enum.filter(g["dirty_excluded_paths"], &Provenance.covers_root?(&1, root))
    rejected = g["dirty_exclusions_rejected"]

    cond do
      covering != [] ->
        refuse(
          :DIRTY_EXCLUSION_COVERS_ROOT,
          "#{inspect(covering)} was excluded from the dirty computation and equals or " <>
            "contains the worktree root #{inspect(root)}: the exclusion does not narrow " <>
            "WORKTREE_DIRTY, it disables it, so `dirty` here means nothing was looked at"
        )

      rejected != [] ->
        refuse(
          :DIRTY_EXCLUSION_COVERS_ROOT,
          "the run asked to exclude #{inspect(rejected)} from the dirty computation, " <>
            "which equals or contains the worktree root #{inspect(root)}. The exclusion " <>
            "was refused when the run was recorded, so the run measured a tree it was " <>
            "simultaneously writing into"
        )

      true ->
        :ok
    end
  end

  # `dirty_start`/`dirty_end` are booleans by the time they reach here
  # (`check_complete/3` refuses a null), but the test is written to treat
  # anything that is not literally `false` as dirty rather than relying on
  # truthiness. `or` on a nil operand raises BadBooleanError, which is how this
  # comparison behaved before the class audit: a crash, not a refusal.
  defp check_clean(m, _o, _e) do
    g = m["git"]

    if g["dirty_start"] != false or g["dirty_end"] != false do
      refuse(
        :WORKTREE_DIRTY,
        "worktree dirty (start: #{g["dirty_start"]}, end: #{g["dirty_end"]}); " <>
          "a figure from a dirty tree is tied to a commit plus unrecorded edits, " <>
          "entries: #{inspect(Enum.take(g["dirty_entries_end"] || [], 5))}"
      )
    else
      :ok
    end
  end

  defp check_preflight(m, _o, _e) do
    if m["beacon"]["preflight_ok"] do
      :ok
    else
      refuse(
        :BEACON_PREFLIGHT_FAILED,
        "the beacon could not be shown to work before the adapter launched, so a " <>
          "later count of zero would not mean the adapter never started: " <>
          inspect(m["beacon"]["preflight_detail"])
      )
    end
  end

  defp check_adapter_started(m, _o, _e) do
    b = m["beacon"]
    r = m["result"]

    if b["adapter_count"] == 0 and r["scenario_dir_count"] > 0 do
      refuse(
        :ADAPTER_NEVER_STARTED,
        "#{r["scenario_dir_count"]} scenario directories but 0 adapter beacons: this run " <>
          "is indistinguishable from having no implementation at all (the MES-49 null-client " <>
          "signature)"
      )
    else
      :ok
    end
  end

  defp check_harness(m, _o, e) do
    cond do
      mismatch?(e, :requirements_md5, m["requirements"]["md5"]) ->
        refuse(
          :HARNESS_MISMATCH,
          "requirement-set md5 #{m["requirements"]["md5"]} is not the expected " <>
            "#{Map.get(e, :requirements_md5)}"
        )

      mismatch?(e, :harness_dist_sha256, m["harness"]["dist_sha256"]) ->
        refuse(
          :HARNESS_MISMATCH,
          "harness dist sha256 #{m["harness"]["dist_sha256"]} is not the expected " <>
            "#{Map.get(e, :harness_dist_sha256)}"
        )

      true ->
        :ok
    end
  end

  defp mismatch?(expect, key, actual) do
    case Map.get(expect, key) do
      nil -> false
      wanted -> wanted != actual
    end
  end

  defp check_artefacts(m, o, _e) do
    r = m["result"]
    b = m["beacon"]
    seen = Enum.sort(Map.get(o, :scenario_dirs, []))
    recorded = Enum.sort(r["scenario_dirs"])
    console = Map.get(o, :console_sha256)

    cond do
      r["scenario_dir_count"] == 0 ->
        refuse(:ARTEFACTS_INCONSISTENT, "the run recorded no scenario directories")

      # A2d inside the tool that exists to enforce A2d. The count and the
      # enumeration behind it were never reconciled, so a manifest claiming 999
      # scenario directories over a list of one was accepted — and the
      # acceptance block printed the 999.
      r["scenario_dir_count"] != length(recorded) ->
        refuse(
          :ARTEFACTS_INCONSISTENT,
          "the run recorded scenario_dir_count #{r["scenario_dir_count"]} but enumerated " <>
            "#{length(recorded)} scenario director(ies): a count that its own list does not " <>
            "support is not a count"
        )

      b["foreign_lines"] > 0 ->
        refuse(
          :ARTEFACTS_INCONSISTENT,
          "#{b["foreign_lines"]} beacon line(s) carry another run's token: this directory " <>
            "was reused (the MES-24 stale-artefact defect)"
        )

      # Contamination refused and truncation did not. A beacon line that will
      # not parse is a line whose token could not be read, so every count taken
      # over that file — `adapter_count` above all — is taken over fewer lines
      # than the file holds. ADAPTER_NEVER_STARTED cannot be trusted against a
      # journal that is partly unreadable.
      b["unparseable_lines"] > 0 ->
        refuse(
          :ARTEFACTS_INCONSISTENT,
          "#{b["unparseable_lines"]} beacon line(s) could not be parsed, so their token " <>
            "was never read: adapter_count #{b["adapter_count"]} is a count over an " <>
            "incomplete journal (truncated or interleaved write)"
        )

      seen != recorded ->
        refuse(
          :ARTEFACTS_INCONSISTENT,
          "scenario directories on disk differ from those the run recorded: " <>
            "#{inspect(only(recorded, seen))} recorded-but-absent, " <>
            "#{inspect(only(seen, recorded))} present-but-unrecorded"
        )

      # `console_sha256` is nil when the file is absent or unreadable. Skipping
      # the comparison on a nil observation meant a run with NO console.txt was
      # accepted — while the acceptance block printed the stored hash for a file
      # that did not exist. The output asserted something false, which is worse
      # than failing to check.
      is_nil(console) ->
        refuse(
          :ARTEFACTS_INCONSISTENT,
          "no readable #{console_filename()} in the run directory, yet the manifest records " <>
            "#{r["console_sha256"]} (#{r["console_bytes"]} bytes). The scored/not-scored " <>
            "split lives only in that file, so the denominator cannot be reconstructed"
        )

      console != r["console_sha256"] ->
        refuse(
          :ARTEFACTS_INCONSISTENT,
          "#{console_filename()} hashes #{console}; the run recorded " <>
            "#{r["console_sha256"]} — the census would be reported over output that is not " <>
            "this run's"
        )

      true ->
        :ok
    end
  end

  defp only(a, b), do: Enum.take(a -- b, 5)

  defp refuse(code, detail), do: {:refused, code, detail}
end

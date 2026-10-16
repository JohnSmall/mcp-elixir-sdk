defmodule MCP.Conformance.StringCitationControls do
  @moduledoc """
  The controls for **guard 33** (`MCP.Conformance.StringCitations`), as one
  implementation that `test/conformance/string_citations_test.exs` (gate 5) and
  `conformance/controls/string_citations_controls.exs` (`--reverted`) both
  drive.

  Every control plants one defect into a small synthetic universe held in
  memory, nothing on disk: two artefacts, four sources (two of them sharing the
  basename `client.ex`), the commits an `at` row may name, and a ledger that
  audits clean before the plant. Each control names the refusal KIND it must
  produce and the LIMB of `StringCitations.audit/1` that produces it, so the
  `--reverted` run can neutralise exactly that limb and show the control fail.

  `run/1` returns the defects the planted universe audits to; `holds?/1` is the
  control's verdict: the expected kind is among them and its rendered line
  starts with `G33`.
  """

  alias MCP.Conformance.StringCitations, as: S

  @json "docs/conformance/fixture.json"
  @md "docs/conformance/report-2026-07-28.md"
  @g32_record "docs/conformance/adjudications/adjudication-D1-nd-CU-2026-07-28.json"
  @holder_test "test/conformance/adjudications_test.exs"

  @a_ex Enum.join(
          [
            "defmodule A do",
            "  def one, do: 1",
            "  def two, do: 2",
            "  def three, do: 3",
            "end",
            ""
          ],
          "\n"
        )

  @a_test Enum.join(
            [
              "defmodule ATest do",
              "  test \"two\" do",
              "    assert A.two() == 2",
              "  end",
              "end",
              ""
            ],
            "\n"
          )

  @x_client "defmodule X.Client do\n  def connect, do: :x\nend\n"
  @y_client "defmodule Y.Client do\n  def request, do: :y\nend\n"

  @old "1111111111111111111111111111111111111111"
  @unrelated "2222222222222222222222222222222222222222"

  @doc "The fixture's tip sources."
  def sources do
    %{
      "lib/a.ex" => @a_ex,
      "test/a_test.exs" => @a_test,
      "lib/x/client.ex" => @x_client,
      "lib/y/client.ex" => @y_client
    }
  end

  @doc "The fixture's JSON artefact, with three citations."
  def json(evidence \\ default_evidence()) do
    rows =
      evidence
      |> Enum.map_join(",\n", fn {tag, text} ->
        ~s(    {"tag": #{Jason.encode!(tag)}, "evidence": #{Jason.encode!(text)}})
      end)

    "{\n  \"rows\": [\n" <> rows <> "\n  ]\n}\n"
  end

  @doc false
  def default_evidence do
    [
      {"r1", "see lib/a.ex:3 for two/0"},
      {"r2", "the test a_test.exs:2-3 asserts it"},
      {"r3", "connect/0 at client.ex:2"}
    ]
  end

  @doc "The fixture's Markdown artefact: one dated citation, anchored at `@old`."
  def md, do: "# Report\n\n## §1 Findings\n\nAt the time `lib/a.ex:4` held three/0.\n"

  @doc """
  The planted universe's inputs, from a map of overrides: `:docs`, `:tip`,
  `:at` (`{sha, path} => bytes`) and `:ledger` (bytes).
  """
  def inputs(over \\ %{}) do
    tip = Map.get(over, :tip, sources())
    at = Map.get(over, :at, %{{@old, "lib/a.ex"} => @a_ex, {@unrelated, "lib/a.ex"} => "x\n"})
    docs = Map.get(over, :docs, %{@json => json(), @md => md()})

    base = %{
      files: docs |> Map.keys() |> Enum.sort(),
      sources: tip |> Map.keys() |> Enum.sort(),
      docs: Map.new(docs, fn {k, v} -> {k, {:ok, v}} end),
      read: fn
        {:tip, p} -> Map.fetch(tip, p) |> or_enoent()
        {:at, sha, p} -> Map.fetch(at, {sha, p}) |> or_enoent()
      end,
      # The production predicate's contract: a 40-hex string first (it raises
      # on anything else, as `StringCitations.ancestor_fun/1` does), then
      # ancestry, here the fixture's two commits.
      ancestor?: &(Regex.match?(~r/\A[0-9a-f]{40}\z/, &1) and &1 in [@old, @unrelated])
    }

    # The ledger is pinned over the UNPLANTED universe, so a plant in the tip
    # or the artefacts is a change against it.
    clean = fn -> if over == %{}, do: ledger(base), else: ledger(inputs(%{})) end

    base
    |> Map.put(:ledger, {:ok, Map.get_lazy(over, :ledger, clean)})
  end

  # An empty ledger in the canonical form (the schema refuses anything less).
  defp empty_ledger, do: S.encode_ledger(%{windows: %{}, rows: []})

  defp or_enoent({:ok, v}), do: {:ok, v}
  defp or_enoent(:error), do: {:error, :enoent}

  @doc """
  The clean ledger of `base`: `--repin` pins the two unambiguous citations; the
  doubled-basename one is added as `--repin` cannot (with its target and
  `target_by: evidence`), and the Markdown one as an `at` publication row.
  """
  def ledger(base) do
    {l, _} = S.repin(Map.put(base, :ledger, {:ok, empty_ledger()}))
    S.encode_ledger(add_rows(l, base))
  end

  defp add_rows(l, base) do
    {:ok, a} = base.read.({:at, @old, "lib/a.ex"})
    {:ok, x} = base.read.({:tip, "lib/x/client.ex"})
    {:ok, sa} = S.window_sha(a, 4, 4)
    {:ok, sx} = S.window_sha(x, 2, 2)

    rows =
      Enum.reject(l.rows, &row?(&1, "lib/a.ex:4")) ++
        [
          %{
            "art" => @json,
            "at_path" => "rows[r3].evidence",
            "cite" => "client.ex:2",
            "nth" => 1,
            "state" => "pin",
            "target" => "lib/x/client.ex",
            "target_by" => "evidence"
          },
          %{
            "art" => @md,
            "at_path" => "## §1 Findings",
            "cite" => "lib/a.ex:4",
            "nth" => 1,
            "state" => "at",
            "class" => "publication",
            "at" => @old,
            "target" => "lib/a.ex"
          }
        ]

    windows =
      l.windows
      |> Map.delete("lib/a.ex:4-4")
      |> Map.merge(%{"lib/x/client.ex:2-2" => sx, "lib/a.ex:4-4@#{@old}" => sa})

    %{l | rows: rows, windows: windows}
  end

  @doc "The clean ledger, decoded, for a plant that edits rows."
  def decoded(base \\ inputs()) do
    {:ok, bin} = base.ledger
    {:ok, l} = S.decode_ledger(bin)
    l
  end

  defp with_rows(fun) do
    l = decoded()
    S.encode_ledger(%{l | rows: Enum.map(l.rows, fun)})
  end

  defp row?(r, cite), do: r["cite"] == cite

  defp insert_line(src, at, line),
    do: src |> String.split("\n") |> List.insert_at(at - 1, line) |> Enum.join("\n")

  @doc """
  Every control: `%{id, what, limb, kind, inputs}`. `limb` is the clause of
  `StringCitations.limb/2` that produces `kind`.
  """
  def controls do
    [
      %{
        id: "C1",
        what: "moved, path form",
        limb: :window,
        kind: :window_drift,
        inputs: fn ->
          inputs(%{tip: %{sources() | "lib/a.ex" => insert_line(@a_ex, 2, "  @moduledoc false")}})
        end
      },
      %{
        id: "C2",
        what: "moved, basename form",
        limb: :window,
        kind: :window_drift,
        inputs: fn ->
          inputs(%{
            tip: %{sources() | "test/a_test.exs" => insert_line(@a_test, 2, "  use ExUnit.Case")}
          })
        end
      },
      %{
        id: "C3",
        what: "changed",
        limb: :window,
        kind: :window_drift,
        inputs: fn ->
          inputs(%{
            tip: %{
              sources()
              | "lib/a.ex" => String.replace(@a_ex, "def two, do: 2", "def two, do: :two")
            }
          })
        end
      },
      %{
        id: "C4",
        what: "ambiguous",
        limb: :window,
        kind: :window_drift,
        inputs: fn ->
          src =
            @a_ex |> insert_line(2, "  @moduledoc false") |> insert_line(6, "  def two, do: 2")

          inputs(%{tip: %{sources() | "lib/a.ex" => src}})
        end
      },
      %{
        id: "C5",
        what: "doubled basename, target swapped",
        limb: :window,
        kind: :window_drift,
        inputs: fn ->
          l = decoded()

          rows =
            Enum.map(
              l.rows,
              &if(row?(&1, "client.ex:2"), do: %{&1 | "target" => "lib/y/client.ex"}, else: &1)
            )

          {sx, windows} = Map.pop(l.windows, "lib/x/client.ex:2-2")

          inputs(%{
            ledger:
              S.encode_ledger(%{
                l
                | rows: rows,
                  windows: Map.put(windows, "lib/y/client.ex:2-2", sx)
              })
          })
        end
      },
      %{
        id: "C5a",
        what: "doubled basename, a new plain basename row",
        limb: :resolution,
        kind: :doubled_basename,
        inputs: fn ->
          inputs(%{
            ledger:
              with_rows(&if(row?(&1, "client.ex:2"), do: Map.delete(&1, "target_by"), else: &1))
          })
        end
      },
      %{
        id: "C5b",
        what: "doubled basename, order-resolved rows beyond the ceiling",
        limb: :ceilings,
        kind: :stale_over_ceiling,
        inputs: fn -> order_beyond_ceiling() end
      },
      %{
        id: "C5c",
        what: "doubled basename, concatenated typo",
        limb: :resolution,
        kind: :unresolved,
        inputs: fn ->
          ev = [
            {"r1", "see lib/a.ex:3 for two/0"},
            {"r2", "the test a_test.exsa_test.exs:2-3 asserts it"},
            {"r3", "connect/0 at client.ex:2"}
          ]

          inputs(%{
            docs: %{@json => json(ev), @md => md()},
            ledger:
              with_rows(
                &if(row?(&1, "a_test.exs:2-3"),
                  do: %{&1 | "cite" => "a_test.exsa_test.exs:2-3"},
                  else: &1
                )
              )
          })
        end
      },
      %{
        id: "C6",
        what: "a cite added to an artefact",
        limb: :universe,
        kind: :unledgered,
        inputs: fn ->
          ev = default_evidence() ++ [{"r4", "and lib/a.ex:2 for one/0"}]
          inputs(%{docs: %{@json => json(ev), @md => md()}, ledger: S.encode_ledger(decoded())})
        end
      },
      %{
        id: "C7",
        what: "a cite removed from an artefact",
        limb: :universe,
        kind: :ledger_orphan,
        inputs: fn ->
          ev = [
            {"r1", "see two/0"},
            {"r2", "the test a_test.exs:2-3 asserts it"},
            {"r3", "connect/0 at client.ex:2"}
          ]

          inputs(%{docs: %{@json => json(ev), @md => md()}, ledger: S.encode_ledger(decoded())})
        end
      },
      %{
        id: "C8",
        what: "a ledger row with no cite",
        limb: :universe,
        kind: :ledger_orphan,
        inputs: fn ->
          l = decoded()

          extra = %{
            "art" => @json,
            "at_path" => "rows[r1].evidence",
            "cite" => "lib/a.ex:2",
            "nth" => 1,
            "state" => "held",
            "class" => "g32_bytes"
          }

          inputs(%{ledger: S.encode_ledger(%{l | rows: l.rows ++ [extra]})})
        end
      },
      %{
        id: "C9",
        what: "a reader that drops a cite",
        limb: :parity,
        kind: :structured_parity,
        seam: &drop_r1/2,
        inputs: fn ->
          inputs()
        end
      },
      %{
        id: "C10",
        what: "a held label on an arbitrary cite",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn -> inputs(%{ledger: held_on_r1()}) end
      },
      %{
        id: "C11a",
        what: "an at row naming no ancestor",
        limb: :anchors,
        kind: :anchor_invalid,
        inputs: fn ->
          inputs(%{ledger: retarget_at("3333333333333333333333333333333333333333")})
        end
      },
      %{
        id: "C11b",
        what: "an at row whose commit lacks the bytes",
        limb: :anchors,
        kind: :at_drift,
        inputs: fn -> inputs(%{ledger: retarget_at(@unrelated)}) end
      },
      %{
        id: "C12a",
        what: "a stale row over its owner's ceiling",
        limb: :ceilings,
        kind: :stale_over_ceiling,
        inputs: fn -> inputs(%{ledger: stale_on_r1("MES-999")}) end
      },
      %{
        id: "C12b",
        what: "a stale row with no owning ticket",
        limb: :rows,
        kind: :bad_row,
        inputs: fn -> inputs(%{ledger: stale_on_r1("none")}) end
      },
      %{
        id: "C13a",
        what: "grammar: :0 and a reversed range",
        limb: :shape,
        kind: :bad_range,
        inputs: fn -> grammar(["lib/a.ex:0", "lib/a.ex:4-3"]) end
      },
      %{
        id: "C13b",
        what: "grammar: a column and an ordinal",
        limb: :shape,
        kind: :bad_shape,
        inputs: fn -> grammar(["lib/a.ex:3:4", "lib/a.ex:3rd"]) end
      },
      %{
        id: "C14",
        what: "the ledger not in canonical form",
        limb: :ledger,
        kind: :ledger_not_canonical,
        inputs: fn ->
          {:ok, bin} = inputs().ledger
          inputs(%{ledger: String.replace(bin, "\n", "\n ", global: false)})
        end
      },
      # --- MES-192 correction round 1 (32825): F1, F2, F3 ---------------------
      %{
        id: "C15",
        what: "F1: the leaf names the other doubled file, the row is pinned by order",
        limb: :resolution,
        kind: :target_contradicted,
        inputs: fn ->
          ev = [
            {"r1", "see lib/a.ex:3 for two/0"},
            {"r2", "the test a_test.exs:2-3 asserts it"},
            {"r3", "client.ex:2 is lib/y/client.ex, request/0"}
          ]

          ledger =
            with_rows(
              &if(row?(&1, "client.ex:2"), do: Map.put(&1, "target_by", "order"), else: &1)
            )

          inputs(%{docs: %{@json => json(ev), @md => md()}, ledger: ledger})
        end
      },
      %{
        id: "C16a",
        what: "F2: held g32_bytes outside G32's records",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          universe(
            %{"conformance/data/fixture-g32.json" => g32_like()},
            [{"conformance/data/fixture-g32.json", "quote.bytes", "g32_bytes"}]
          )
        end
      },
      %{
        id: "C16b",
        what: "F2: held g32_anchor_entry outside G32's records",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          universe(
            %{"conformance/data/fixture-g32.json" => g32_like()},
            [
              {"conformance/data/fixture-g32.json", "holder.prose_anchors[#0].cite",
               "g32_anchor_entry"}
            ]
          )
        end
      },
      %{
        id: "C16c",
        what: "F2: held g32_prose_anchor outside G32's records",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          universe(
            %{"conformance/data/fixture-g32.json" => g32_like()},
            [{"conformance/data/fixture-g32.json", "holder.note", "g32_prose_anchor"}]
          )
        end
      },
      %{
        id: "C16d",
        what: "F2: held attribution_citations in an artefact the holder does not read",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          ev = [
            {"r1", "the assert a_test.exs:2 holds"},
            {"r2", "the test a_test.exs:2-3 asserts it"},
            {"r3", "connect/0 at client.ex:2"}
          ]

          universe(
            %{@json => json(ev), attribution_md() => attribution_doc("§2.4")},
            [{@json, "rows[r1].evidence", "attribution_citations"}]
          )
        end
      },
      %{
        id: "C16e",
        what: "F2: held attribution_citations in a section the holder does not audit",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          universe(
            %{attribution_md() => attribution_doc("§2.3")},
            [{attribution_md(), "## §2.3 Class", "attribution_citations"}]
          )
        end
      },
      %{
        id: "C16f",
        what: "F2: held g5_asserts_read on a list no holder test enumerates (R1: no such class)",
        limb: :rows,
        kind: :bad_row,
        inputs: fn ->
          doc = ~s|{"asserts_read": ["test/a_test.exs:3 \u2014 assert A.two() == 2"]}\n|

          universe(
            %{@g32_record => doc},
            [{@g32_record, "asserts_read[#0]", "g5_asserts_read"}],
            Map.put(sources(), @holder_test, holder_source())
          )
        end
      },
      %{
        id: "C16g",
        what: "F2: held g29 in a section G29 does not permit",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          universe(
            %{register_md() => "# Register\n\n## §9 Other\n\nquoted `client.ex:868` here\n"},
            [{register_md(), "## §9 Other", "g29"}]
          )
        end
      },
      %{
        id: "C16h",
        what: "F2: held g29 in an artefact G29 does not read",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn -> universe(%{}, [{@json, "rows[r1].evidence", "g29"}]) end
      },
      %{
        id: "C17a",
        what: "F3: a cite in a root field named module moves (no record)",
        mode: :resolve,
        expect: :moved,
        stub: {"  defp in_identity?(", broad_identity()},
        kind: :in_record_identity,
        inputs: fn -> moved_universe(~s({"module": "see lib/a.ex:3"}\n)) end
      },
      %{
        id: "C17b",
        what: "F3: a cite in module beside a key moves (key is the identity)",
        mode: :resolve,
        expect: :moved,
        stub: {"  defp in_identity?(", broad_identity()},
        kind: :in_record_identity,
        inputs: fn ->
          moved_universe(~s({"rows": [{"key": "k1", "module": "see lib/a.ex:3"}]}\n))
        end
      },
      %{
        id: "C17c",
        what: "F3: a cite that IS a record's identity is refused",
        mode: :resolve,
        expect: :refused,
        stub: {"  defp in_identity?(", "  defp in_identity?(_o), do: false\n\n"},
        kind: :in_record_identity,
        inputs: fn -> moved_universe(~s({"rows": [{"module": "lib/a.ex:3"}]}\n)) end
      },
      # --- MES-192 correction round 2 (32833, 32835): R1 and R2 ---------------
      %{
        id: "C18a",
        what: "R1: held g5_asserts_read on a holder-enumerated row is no longer a class",
        limb: :rows,
        kind: :bad_row,
        inputs: fn -> g5_universe(holder_source()) end
      },
      %{
        id: "C18b",
        what: "R1: held g5_asserts_read under a holder loop filtered to no rows",
        limb: :rows,
        kind: :bad_row,
        inputs: fn ->
          g5_universe(
            String.replace(
              holder_source(),
              ~s|for s <- record["sections"], r <- s["rows"] do|,
              ~s|for s <- record["sections"], r <- s["rows"], false do|
            )
          )
        end
      },
      %{
        id: "C18c",
        what: "R1: an et_test_at row whose et_test file is not the cited file",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn -> anchored_universe("test/a_test.exs") end
      },
      %{
        id: "C19a",
        what: "R2: two correct cites in separate sentences pass",
        expect: :clean,
        stub: {"  defp associated(", whole_leaf()},
        kind: :target_contradicted,
        inputs: fn ->
          r3_universe("connect/0 at client.ex:2. The request/0 consumer is lib/y/client.ex:2.")
        end
      },
      %{
        id: "C19b",
        what: "R2: an unrelated other-client path in another sentence passes",
        expect: :clean,
        stub: {"  defp associated(", whole_leaf()},
        kind: :target_contradicted,
        inputs: fn ->
          r3_universe("connect/0 at client.ex:2. Unrelated: lib/y/client.ex holds request/0.")
        end
      },
      %{
        id: "C19c",
        what: "R2: both doubled files associated with the cite is ambiguous",
        stub: {"  defp associated(", "  defp associated(_o, _cands), do: []\n\n"},
        kind: :target_ambiguous,
        inputs: fn -> r3_universe("client.ex:2 is lib/y/client.ex or lib/x/client.ex") end
      },
      %{
        id: "C19d",
        what: "R2: the :851 form still refuses a wrong pin",
        stub: {"  defp associated(", "  defp associated(_o, _cands), do: []\n\n"},
        kind: :target_contradicted,
        inputs: fn -> r3_universe("`client.ex:2` is `lib/y/client.ex`; see connect/0") end
      },
      # --- MES-192 correction round 3 (32842): S1-S4 ---------------------------
      %{
        id: "C20a",
        what: "S1: a pin row whose window hash is null, its source drifted",
        limb: :rows,
        kind: :bad_window,
        inputs: fn ->
          moved = %{sources() | "lib/a.ex" => insert_line(@a_ex, 2, "  @moduledoc false")}
          inputs(%{tip: moved, ledger: with_window("lib/a.ex:3-3", nil)})
        end
      },
      %{
        id: "C20b",
        what: "S1: an at row whose window hash is null, its commit's bytes drifted",
        limb: :rows,
        kind: :bad_window,
        inputs: fn ->
          inputs(%{
            at: %{{@old, "lib/a.ex"} => "x\ny\nz\nw\n"},
            ledger: with_window("lib/a.ex:4-4@#{@old}", nil)
          })
        end
      },
      %{
        id: "C20c",
        what: "S1: a window hash that is not lowercase 64-hex",
        limb: :rows,
        kind: :bad_window,
        inputs: fn ->
          l = decoded()
          inputs(%{ledger: with_window("lib/a.ex:3-3", String.upcase(l.windows["lib/a.ex:3-3"]))})
        end
      },
      %{
        id: "C21a",
        what: "S2: a scalar named live_units outside the sweep's records",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          sweep_universe([{"cr_note.live_units", "snapshot", "sweep_measurement"}])
        end
      },
      %{
        id: "C21b",
        what: "S2: a lookalike nested live_units list outside the sweep's records",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          sweep_universe([{"elsewhere.live_units[#0]", "snapshot", "sweep_measurement"}])
        end
      },
      %{
        id: "C21c",
        what: "S2: another field of a sweep record",
        limb: :states,
        kind: :state_unwarranted,
        inputs: fn ->
          sweep_universe([{"boundaries[b1].note", "snapshot", "sweep_measurement"}])
        end
      },
      %{
        id: "C21d",
        what: "S2: the sweep's own live_units and live_column_excluded_units stay snapshot",
        expect: :clean,
        stub: {"  defp sweep_list_element?(", "  defp sweep_list_element?(_o), do: false\n\n"},
        kind: :state_unwarranted,
        inputs: fn ->
          sweep_universe([
            {"boundaries[b1].live_units[#0]", "snapshot", "sweep_measurement"},
            {"live_column_excluded_units[#0]", "snapshot", "sweep_measurement"}
          ])
        end
      },
      %{
        id: "C22a",
        what: "S3: a backup file named after the other client is not its path",
        expect: :clean,
        stub: {"  defp mentions(", prefix_mentions()},
        kind: :target_contradicted,
        inputs: fn -> r3_universe("client.ex:2 documents the backup lib/y/client.ex.bak") end
      },
      %{
        id: "C22b",
        what: "S3: an uppercase-extension cite stands between the cite and the path",
        expect: :clean,
        stub: {"  defp other_cites(", lowercase_cites()},
        kind: :target_contradicted,
        inputs: fn -> r3_universe("client.ex:2 before schema.JSON:5 in lib/y/client.ex") end
      },
      %{
        id: "C22c",
        what: "S3: a digit-extension cite stands between the cite and the path",
        expect: :clean,
        stub: {"  defp other_cites(", lowercase_cites()},
        kind: :target_contradicted,
        inputs: fn -> r3_universe("client.ex:2 before schema.json5:5 in lib/y/client.ex") end
      },
      %{
        id: "C23",
        what: "S4: every refusal kind the guard can emit names a fix",
        mode: :meta,
        stub: {"  def fix(", "  def fix(_kind), do: \"\"\n\n"},
        kind: :fix_missing,
        inputs: fn -> inputs() end
      },
      # --- MES-192 correction round 4 (32966): T1-T3 ---------------------------
      %{
        id: "C24a",
        what: "T1: at: null is bad_row from audit, --repin and --resolve, never a raise",
        mode: :entry_points,
        stub: {"  defp schema_split(", whole_rows_split()},
        kind: :bad_row,
        row: fn -> at_row(nil) end,
        inputs: fn -> inputs(%{ledger: with_at(nil)}) end
      },
      %{
        id: "C24b",
        what: "T1: at: 1 is bad_row from audit, --repin and --resolve, never a raise",
        mode: :entry_points,
        stub: {"  defp schema_split(", whole_rows_split()},
        kind: :bad_row,
        row: fn -> at_row(1) end,
        inputs: fn -> inputs(%{ledger: with_at(1)}) end
      },
      %{
        id: "C25a",
        what: "T2: relabelling cites external beyond its ceiling",
        limb: :ceilings,
        kind: :stale_over_ceiling,
        inputs: fn ->
          gone = Enum.map_join(1..6, ", ", &"lib/gone.ex:#{&1}")
          ev = default_evidence() ++ [{"r6", "removed: " <> gone}]
          universe(%{@json => json(ev)}, [{@json, "rows[r6].evidence", %{"state" => "external"}}])
        end
      },
      %{
        id: "C25b",
        what: "T2: relabelling cites not_a_cite beyond its ceiling",
        limb: :ceilings,
        kind: :stale_over_ceiling,
        inputs: fn ->
          ev = default_evidence() ++ [{"r7", "fixtures: lib/a.ex:98 and lib/a.ex:99"}]
          fields = %{"state" => "not_a_cite", "class" => "fixture", "target" => "lib/a.ex"}
          universe(%{@json => json(ev)}, [{@json, "rows[r7].evidence", fields}])
        end
      },
      %{
        id: "C26",
        what: "T3: the runtime shape kinds are declared, and each names a fix",
        mode: :runtime_kinds,
        stub: {"  def fix(", "  def fix(:bad_shape), do: \"\"\n\n"},
        kind: :fix_missing,
        inputs: fn -> inputs() end
      },
      # --- MES-192 correction round 5 (32983): U1 ------------------------------
      %{
        id: "C27a",
        what: "U1: every JSON type in every field of every row state, every entry point",
        mode: :type_matrix,
        # Each revert must fail the matrix, and a revert naming `cells` must
        # fail every one of those `state.field` cells (MES-192 32993, V1).
        stubs: [
          %{stub: {"  defp schema_split(", whole_rows_split()}},
          %{
            stub: {"  defp full_sha?(", "  defp full_sha?(\"\"), do: true\n\n"},
            cells: ["at.at"]
          },
          %{
            stub: {"  defp field_problem(\"target\", r),", maps_only_target()},
            cells: ["pin.target", "at.target", "not_a_cite.target"]
          }
        ],
        kind: :bad_row,
        inputs: fn -> inputs() end
      },
      %{
        id: "C27b",
        what: "U1: a refused row whose cite is an object is described, not raised on",
        mode: :entry_points,
        stub: {"  defp shown(", interpolated_shown()},
        kind: :bad_row,
        row: fn -> r1_row(%{"cite" => %{"a" => 1}}) end,
        inputs: fn -> inputs(%{ledger: with_r1(%{"cite" => %{"a" => 1}})}) end
      },
      %{
        id: "C28",
        what: "U1: the matrix's field list is the schema's, and not empty",
        mode: :field_list,
        stub: {"  defp state_fields_check(", "  defp state_fields_check(_r), do: nil\n\n"},
        kind: :field_list_short,
        inputs: fn -> inputs() end
      }
    ]
  end

  # The pre-U1 split: every row flows on past the schema; the refused ones are
  # still listed.
  defp whole_rows_split do
    ~S"""
      defp schema_split(rows),
        do: {rows, for(r <- rows, why <- [row_problem(r)], why != nil, do: {r, why})}

    """
  end

  # The pre-U1 renderer: string interpolation, which raises on a map.
  defp interpolated_shown do
    ~S"""
      defp shown(v), do: "#{v}"

    """
  end

  # CR's mutant 2 (32992): a target is refused only when it is an object.
  defp maps_only_target do
    ~S"""
      defp field_problem("target", r), do: if(is_map(r["target"]), do: "target is a path")

    """
  end

  defp with_r1(fields) do
    l = decoded()
    rows = Enum.map(l.rows, &if(row?(&1, "lib/a.ex:3"), do: Map.merge(&1, fields), else: &1))
    S.encode_ledger(%{l | rows: rows})
  end

  defp r1_row(fields),
    do: decoded().rows |> Enum.find(&row?(&1, "lib/a.ex:3")) |> Map.merge(fields)

  defp at_row(value),
    do: decoded().rows |> Enum.find(&(&1["state"] == "at")) |> Map.put("at", value)

  # --- a refusal's own cause (MES-192 32993, V1) -------------------------------
  #
  # A control holds on the refusal of what it planted, never on another
  # refusal of the same kind: a bad_row carries the planted row's art and key,
  # and the schema's own verdict on that row as its detail; a
  # ledger_unreadable is the document-shape refusal of the planted occurrence
  # entry.

  # The guard's renderer contract (32983): a binary as it is, anything else as
  # inspect/2 shows it.
  defp shown(v) when is_binary(v), do: v
  defp shown(v), do: inspect(v, limit: 8, printable_limit: 120)

  @doc "Whether `d` is the schema's refusal of `row` itself."
  def refuses_row?(d, row) do
    why = S.row_problem(row)

    why != nil and d.kind == :bad_row and d.detail == why and d.art == shown(row["art"]) and
      d.key == "#{shown(row["at_path"])} `#{shown(row["cite"])}`##{shown(row["nth"])}"
  end

  @doc "Whether `d` is the document-shape refusal of the occurrence entry `row` is written in."
  def refuses_entry?(d, row) do
    entry = %{
      "art" => row["art"],
      "at_path" => row["at_path"],
      "cites" => [Map.drop(row, ["art", "at_path"])]
    }

    d.kind == :ledger_unreadable and String.starts_with?(d.detail, "an occurrence entry is not") and
      String.ends_with?(d.detail, ": " <> shown(entry))
  end

  defp own_refusal?(d, :bad_row, row), do: refuses_row?(d, row)
  defp own_refusal?(d, :ledger_unreadable, row), do: refuses_entry?(d, row)

  # --- the type matrix (C27a, C28) ---------------------------------------------

  # One value of every JSON type, none of which any row field takes: an integer
  # is 0 (nth counts from 1), a string is empty. `:absent` removes the field.
  @json_types [nil, true, 0, 1.5, "", ["x"], %{}, %{"a" => 1}, :absent]
  @schema_attrs [:base_fields, :state_fields, :row_fields, :classes]

  @doc """
  The ledger row schema as the guard DECLARES it: its `@base_fields`,
  `@state_fields`, `@row_fields` and `@classes`, read from its quoted source as
  `guard_kinds/0` reads its kinds. Never a hand list: a field added to the
  schema is planted by C27a without an edit here, and C28 fails if what is
  read is empty or narrower than the schema the guard enforces.
  """
  def row_schema do
    {:ok, ast} =
      S.__info__(:compile)[:source] |> to_string() |> File.read!() |> Code.string_to_quoted()

    {_, read} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [value]}]} = n, acc when name in @schema_attrs ->
          {n, Map.put(acc, name, elem(Code.eval_quoted(value), 0))}

        n, acc ->
          {n, acc}
      end)

    Map.merge(%{base_fields: [], state_fields: %{}, row_fields: [], classes: %{}}, read)
  end

  @doc """
  Every cell's `{state, field, expected kind}`: each field of each row state.
  A base field the encoder does not write into a row (`art`, `at_path`) lives
  on the occurrence entry, so a plant there is the document's shape
  (`ledger_unreadable`); every other is the row's (`bad_row`).
  """
  def matrix_fields(schema \\ row_schema()) do
    entry = schema.base_fields -- schema.row_fields

    for {state, {req, opt}} <- Enum.sort(schema.state_fields),
        f <- schema.base_fields ++ req ++ opt,
        do: {state, f, if(f in entry, do: :ledger_unreadable, else: :bad_row), f not in opt}
  end

  @doc """
  Every cell `{state, field, expected kind, value}`: each JSON value in each
  field; `:absent` only where the field is required (an optional field may be
  absent).
  """
  def cells(schema \\ row_schema()) do
    for {state, field, kind, required} <- matrix_fields(schema),
        v <- @json_types,
        required or v != :absent,
        do: {state, field, kind, v}
  end

  # A schema-valid row of `state` on r1's occurrence, with every field the
  # state takes; a field with no value here is left nil, so the prototype is
  # refused and C28 names it.
  defp prototype(state, schema) do
    {req, opt} = schema.state_fields[state]

    values = %{
      "target" => "lib/a.ex",
      "target_by" => "evidence",
      "at" => @old,
      "owner" => "MES-193",
      "reason" => "planted",
      "class" => schema.classes |> Map.get(state, []) |> List.first()
    }

    Map.merge(
      %{
        "art" => @json,
        "at_path" => "rows[r1].evidence",
        "cite" => "lib/a.ex:3",
        "nth" => 1,
        "state" => state
      },
      Map.new(req ++ opt, &{&1, Map.get(values, &1)})
    )
  end

  defp plant(row, field, :absent), do: Map.delete(row, field)
  defp plant(row, field, value), do: Map.put(row, field, value)

  # The cells that fail: a raise, a missing refusal of the expected kind, a
  # kind with no fix, or a refusal that cannot be rendered.
  defp matrix_failures do
    schema = row_schema()
    l = decoded()
    others = Enum.reject(l.rows, &row?(&1, "lib/a.ex:3"))

    schema
    |> cells()
    |> Task.async_stream(
      fn {state, field, kind, v} ->
        row = state |> prototype(schema) |> plant(field, v)
        i = inputs(%{ledger: S.encode_ledger(%{l | rows: [row | others]})})
        {state, field, kind, v, cell_problems(i, kind, row)}
      end,
      timeout: :infinity,
      ordered: true
    )
    |> Enum.flat_map(fn {:ok, {state, field, _kind, v, problems}} ->
      for p <- problems,
          do: %{
            kind: :cell_failed,
            art: nil,
            key: "#{state}.#{field} = #{inspect(v)}",
            detail: p
          }
    end)
  end

  defp cell_problems(i, kind, row) do
    for {name, call} <- [
          audit: fn -> S.audit(i).defects end,
          repin: fn -> S.repin(i) end,
          resolve: fn -> S.resolve(i, &base_read/1) end
        ],
        p <- entry_problems(name, entry_defects(name, call), kind, row),
        do: p
  end

  defp entry_problems(name, defects, kind, row) do
    rendered = Enum.map(defects, &render_defect/1)

    cond do
      Enum.any?(defects, &(&1.kind == :raised)) ->
        ["#{name} raised: " <> Enum.find(defects, &(&1.kind == :raised)).detail]

      not Enum.any?(defects, &own_refusal?(&1, kind, row)) ->
        [
          "#{name}: no #{kind} of the planted row among " <>
            inspect(Enum.map(defects, &{&1.kind, &1.detail}), limit: 4)
        ]

      S.fix(kind) == "" ->
        ["#{name}: #{kind} names no fix"]

      :error in rendered ->
        ["#{name}: a refusal cannot be rendered"]

      true ->
        []
    end
  end

  defp render_defect(d) do
    S.format_defect(d)
  rescue
    _ -> :error
  end

  # C28: the field list is not empty, covers every field the encoder writes,
  # each state's prototype passes the guard's schema, the schema refuses it
  # without each required field, and refuses a field outside the list (so the
  # list is every field the schema admits).
  defp field_list_problems do
    schema = row_schema()
    cells = matrix_fields(schema)
    listed = cells |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    ([
       cells == [] && "the field list read is empty",
       not MapSet.subset?(MapSet.new(schema.base_fields ++ schema.row_fields), listed) &&
         "the field list omits a field the encoder writes",
       map_size(schema.state_fields) == 0 && "no row state is declared"
     ] ++
       Enum.flat_map(schema.state_fields, fn {state, {req, _opt}} ->
         row = prototype(state, schema)

         [
           S.row_problem(row) != nil &&
             "the #{state} prototype is refused: #{S.row_problem(row)}",
           S.row_problem(Map.put(row, "zz_unlisted", "x")) == nil &&
             "a #{state} row admits a field outside the list"
         ] ++
           for f <- schema.base_fields ++ req,
               do:
                 S.row_problem(Map.delete(row, f)) == nil &&
                   "a #{state} row without #{f} is admitted"
       end))
    |> Enum.filter(&is_binary/1)
  end

  defp with_at(value) do
    l = decoded()
    rows = Enum.map(l.rows, &if(&1["state"] == "at", do: %{&1 | "at" => value}, else: &1))
    S.encode_ledger(%{l | rows: rows})
  end

  # The pre-S3 mention: a candidate path followed by a dot (lib/y/client.ex.bak).
  defp prefix_mentions do
    ~S"""
      defp mentions(text, path) do
        ~r/(?<![\w.\/-])#{Regex.escape(path)}(?![\w\/-]|:\d)/u
        |> Regex.scan(text, return: :index)
        |> Enum.map(fn [{s, l}] -> {s, s + l} end)
      end

    """
  end

  # The pre-S3 separator: lowercase alphabetic extensions only.
  defp lowercase_cites do
    ~S"""
      defp other_cites(text, at) do
        for [{s, l}] <-
              Regex.scan(
                ~r/(?<![\w.\/-])(?:[\w.-]+\/)*[\w.-]+\.[a-z]+:\d+(?:[-–]\d+)?|(?<![\w.:\/-]):\d+/u,
                text,
                return: :index
              ),
            s != at,
            do: {s, s + l}
      end

    """
  end

  defp with_window(key, value) do
    l = decoded()
    S.encode_ledger(%{l | windows: Map.put(l.windows, key, value)})
  end

  # A boundaries table shaped like BoundarySweep's, with a lookalike scalar, a
  # lookalike nested list and another field of a record, each citing lib/a.ex.
  defp sweep_universe(plants) do
    path = MCP.Conformance.BoundarySweep.paths().boundaries

    doc =
      Jason.encode!(%{
        "boundaries" => [
          %{"id" => "b1", "live_units" => ["lib/a.ex:3 (A)"], "note" => "see lib/a.ex:2"}
        ],
        "live_column_excluded_units" => ["lib/a.ex:2 (A)"],
        "cr_note" => %{"live_units" => "lib/a.ex:2"},
        "elsewhere" => %{"live_units" => ["lib/a.ex:2"]}
      }) <> "\n"

    universe(%{path => doc}, for({p, st, c} <- plants, do: {path, p, st, c}))
  end

  @doc """
  Every refusal kind the guard can emit: the kinds it declares (`kinds/0`, when
  it has one) and every literal kind in its source passed to `d/3`/`d/4`,
  returned as `{:refuse, kind, _}` or `{:error, {kind, _}}` (read from its
  quoted source, so a new literal kind cannot escape the count).
  """
  def guard_kinds do
    {:ok, ast} =
      S.__info__(:compile)[:source] |> to_string() |> File.read!() |> Code.string_to_quoted()

    {_, found} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:d, _, [k | _]} = n, acc when is_atom(k) -> {n, MapSet.put(acc, k)}
        {:{}, _, [:refuse, k, _]} = n, acc when is_atom(k) -> {n, MapSet.put(acc, k)}
        {:error, {k, _}} = n, acc when is_atom(k) -> {n, MapSet.put(acc, k)}
        n, acc -> {n, acc}
      end)

    declared = if function_exported?(S, :kinds, 0), do: apply(S, :kinds, []), else: []
    found |> MapSet.union(MapSet.new(declared ++ runtime_kinds())) |> Enum.sort()
  end

  @doc """
  The kinds the guard builds at runtime (`d(o.shape, ...)`), as it declares
  them in the one attribute its emitter reads (`runtime_kinds/0`); none if it
  declares none.
  """
  def runtime_kinds,
    do: if(function_exported?(S, :runtime_kinds, 0), do: apply(S, :runtime_kinds, []), else: [])

  @doc "The kinds whose rendered refusal has no fix instruction."
  def kinds_without_fix do
    for k <- guard_kinds(),
        line = S.format_defect(%{kind: k, art: nil, key: nil, detail: "x"}),
        String.ends_with?(line, "[fix: ]"),
        do: k
  end

  # The pre-R2 association: any candidate path written anywhere in the leaf.
  defp whole_leaf do
    ~S"""
      defp associated(o, cands),
        do: Enum.filter(cands, &Regex.match?(~r/(?<![\w.\/-])#{Regex.escape(&1)}(?![\w\/-])/, o.leaf))

    """
  end

  # The default universe with r3's leaf replaced; r3's client.ex:2 stays pinned to
  # lib/x/client.ex by evidence, and any other cite is pinned by --repin.
  defp r3_universe(text) do
    ev = [
      {"r1", "see lib/a.ex:3 for two/0"},
      {"r2", "the test a_test.exs:2-3 asserts it"},
      {"r3", text}
    ]

    universe(%{@json => json(ev)}, [])
  end

  # A D1-shaped record whose one row's asserts_read head is labelled
  # held:g5_asserts_read, with `holder` as the holder test's source.
  defp g5_universe(holder) do
    doc =
      ~s|{"sections": [{"rows": [{"tag": "t1", "asserts_read": | <>
        ~s|["test/a_test.exs:3 \u2014 assert A.two() == 2"]}]}]}\n|

    universe(
      %{@g32_record => doc},
      [{@g32_record, "sections[#0].rows[t1].asserts_read[#0]", "g5_asserts_read"}],
      Map.put(sources(), @holder_test, holder)
    )
  end

  # A row whose et_test is anchored at @old on `et_file`, with a reading citing
  # lib/a.ex:3 recorded as an et_test_at row at @old.
  defp anchored_universe(et_file) do
    doc =
      Jason.encode!(%{
        "rows" => [
          %{
            "tag" => "t1",
            "et_test" => %{"file" => et_file, "lines" => [1, 1], "at" => @old},
            "reading" => "see lib/a.ex:3"
          }
        ]
      }) <> "\n"

    i = universe(%{"docs/conformance/fixture-anchored.json" => doc}, [])
    l = decoded(i)
    {:ok, src} = i.read.({:at, @old, "lib/a.ex"})
    {:ok, sha} = S.window_sha(src, 3, 3)

    rows =
      Enum.map(l.rows, fn
        %{"art" => "docs/conformance/fixture-anchored.json"} = r ->
          r
          |> Map.drop(["target_by"])
          |> Map.merge(%{
            "state" => "at",
            "class" => "et_test_at",
            "at" => @old,
            "target" => "lib/a.ex"
          })

        r ->
          r
      end)

    windows = Map.put(l.windows, "lib/a.ex:3-3@#{@old}", sha)
    %{i | ledger: {:ok, S.encode_ledger(%{l | rows: rows, windows: windows})}}
  end

  # The pre-fix predicate: any identity-named key anywhere on the path.
  defp broad_identity do
    "  defp in_identity?(o),\n    do: Enum.any?(o.segs, &match?({:key, k} when k in " <>
      "~w(key id member claim tag module ticket slice definition register_key), &1))\n\n"
  end

  @doc "The attribution prose's path, as its holder names it."
  def attribution_md, do: MCP.Conformance.ETCCAttribution.paths().prose

  @doc "G29's document."
  def register_md, do: "docs/conformance/etcc-register.md"

  defp attribution_doc(section),
    do: "# Attribution\n## #{section} Class\nmember `a_test.exs:2`\n"

  defp g32_like do
    Jason.encode!(%{
      "quote" => %{"file" => "lib/a.ex", "lines" => [3, 3], "bytes" => "quoting lib/a.ex:3 here"},
      "holder" => %{
        "note" => "see lib/a.ex:3",
        "prose_anchors" => [
          %{"field" => "note", "cite" => "lib/a.ex:3", "file" => "lib/a.ex", "lines" => [3, 3]}
        ]
      }
    }) <> "\n"
  end

  # A synthetic holder: one test that reads every row's asserts_read heads of
  # the fixture's D1 record, in the shape adjudications_test.exs uses.
  defp holder_source do
    ~S'''
    defmodule FixtureAdjudicationsTest do
      @d1 "docs/conformance/adjudications/adjudication-D1-nd-CU-2026-07-28.json"

      test "every assert a row says it read is an assert at that line", %{inputs: inputs} do
        {:ok, record} = inputs.records[@d1]

        for s <- record["sections"], r <- s["rows"] do
          for entry <- r["asserts_read"],
              [_, file, line, text] <- [Regex.run(~r/\A(test\/[^:]+):(\d+) — (.*)\z/s, entry)] do
            at = {file, line}
            assert at == text
          end
        end
      end
    end
    '''
  end

  # The default universe plus `extra` artefacts, its ledger pinned by --repin
  # over all of them; then every occurrence at each planted {art, at_path} is
  # given a held row of the planted class, whatever --repin made of it.
  defp universe(extra, plants, tip \\ sources()) do
    docs = Map.merge(%{@json => json(), @md => md()}, extra)
    i0 = inputs(%{docs: docs, tip: tip, ledger: empty_ledger()})
    {l, _} = S.repin(i0)
    l = add_rows(l, i0)

    held =
      for plant <- plants,
          {art, p, fields} = with_state(plant),
          o <- S.context(i0).occs,
          o.art == art and o.at_path == p,
          do: Map.merge(%{"art" => art, "at_path" => p, "cite" => o.cite, "nth" => o.nth}, fields)

    keys = MapSet.new(held, &key/1)
    rows = Enum.reject(l.rows, &MapSet.member?(keys, key(&1))) ++ held
    inputs(%{docs: docs, tip: tip, ledger: S.encode_ledger(%{l | rows: rows})})
  end

  defp key(r), do: {r["art"], r["at_path"], r["cite"], r["nth"]}

  defp with_state({art, p, %{} = fields}), do: {art, p, fields}
  defp with_state({art, p, class}), do: {art, p, %{"state" => "held", "class" => class}}
  defp with_state({art, p, state, class}), do: {art, p, %{"state" => state, "class" => class}}

  # An extra artefact pinned over the unplanted tip, then lib/a.ex's line 3
  # moved to 4: a moved window for --resolve.
  defp moved_universe(doc) do
    clean = universe(%{"docs/conformance/fixture-identity.json" => doc}, [])
    moved = %{sources() | "lib/a.ex" => insert_line(@a_ex, 2, "  @moduledoc false")}
    %{clean | read: read_over(moved), sources: moved |> Map.keys() |> Enum.sort()}
  end

  defp read_over(tip) do
    fn
      {:tip, p} -> Map.fetch(tip, p) |> or_enoent()
      {:at, sha, p} -> Map.fetch(%{{@old, "lib/a.ex"} => @a_ex}, {sha, p}) |> or_enoent()
    end
  end

  defp order_beyond_ceiling do
    {_, n} = Enum.find(S.ceilings(), fn {k, _} -> k == {"order", "MES-196"} end)
    text = "connect/0 at " <> Enum.map_join(1..(n + 1), ", ", fn _ -> "client.ex:2" end)

    ev = [
      {"r1", "see lib/a.ex:3 for two/0"},
      {"r2", "the test a_test.exs:2-3 asserts it"},
      {"r3", text}
    ]

    l = decoded()

    rows =
      Enum.reject(l.rows, &row?(&1, "client.ex:2")) ++
        for k <- 1..(n + 1) do
          %{
            "art" => @json,
            "at_path" => "rows[r3].evidence",
            "cite" => "client.ex:2",
            "nth" => k,
            "state" => "pin",
            "target" => "lib/x/client.ex",
            "target_by" => "order"
          }
        end

    inputs(%{docs: %{@json => json(ev), @md => md()}, ledger: S.encode_ledger(%{l | rows: rows})})
  end

  defp held_on_r1 do
    l = decoded()

    rows =
      Enum.map(
        l.rows,
        &if(row?(&1, "lib/a.ex:3"),
          do: %{
            "art" => &1["art"],
            "at_path" => &1["at_path"],
            "cite" => &1["cite"],
            "nth" => 1,
            "state" => "held",
            "class" => "g32_prose_anchor"
          },
          else: &1
        )
      )

    S.encode_ledger(%{l | rows: rows, windows: Map.delete(l.windows, "lib/a.ex:3-3")})
  end

  defp stale_on_r1(owner) do
    l = decoded()

    rows =
      Enum.map(
        l.rows,
        &if(row?(&1, "lib/a.ex:3"),
          do: %{
            "art" => &1["art"],
            "at_path" => &1["at_path"],
            "cite" => &1["cite"],
            "nth" => 1,
            "state" => "stale",
            "owner" => owner,
            "reason" => "planted"
          },
          else: &1
        )
      )

    S.encode_ledger(%{l | rows: rows, windows: Map.delete(l.windows, "lib/a.ex:3-3")})
  end

  defp retarget_at(sha) do
    l = decoded()
    rows = Enum.map(l.rows, &if(&1["state"] == "at", do: %{&1 | "at" => sha}, else: &1))
    {w, windows} = Map.pop(l.windows, "lib/a.ex:4-4@#{@old}")
    S.encode_ledger(%{l | rows: rows, windows: Map.put(windows, "lib/a.ex:4-4@#{sha}", w)})
  end

  defp grammar(cites) do
    ev = default_evidence() ++ [{"r9", "bad: " <> Enum.join(cites, " and ")}]
    inputs(%{docs: %{@json => json(ev), @md => md()}, ledger: S.encode_ledger(decoded())})
  end

  @doc "The control with `id`."
  def control(id), do: Enum.find(controls(), &(&1.id == id))

  @doc """
  The defects the control's planted universe audits to; for a `:resolve`
  control, the refusals of `--resolve` (from the unplanted sources) followed by
  the audit of its result.
  """
  def run(%{mode: :resolve, inputs: f}) do
    i = f.()
    r = S.resolve(i, &base_read/1)
    r.refused ++ S.audit(applied(i, r)).defects
  end

  def run(%{mode: :meta}),
    do:
      for(
        k <- kinds_without_fix(),
        do: %{kind: :fix_missing, art: nil, key: "#{k}", detail: "no fix"}
      )

  def run(%{mode: :entry_points, inputs: f}) do
    i = f.()

    for {name, call} <- [
          audit: fn -> S.audit(i).defects end,
          repin: fn -> S.repin(i) end,
          resolve: fn -> S.resolve(i, &base_read/1) end
        ],
        d <- entry_defects(name, call) do
      d
    end
  end

  def run(%{mode: :runtime_kinds}),
    do:
      for(
        k <- [:runtime_kinds_declared | runtime_kinds()],
        not runtime_ok?(k),
        do: %{kind: :fix_missing, art: nil, key: "#{k}", detail: "not declared, or no fix"}
      )

  def run(%{mode: :type_matrix}), do: matrix_failures()

  def run(%{mode: :field_list}),
    do:
      for(
        why <- field_list_problems(),
        do: %{kind: :field_list_short, art: nil, key: nil, detail: why}
      )

  def run(%{seam: seam, inputs: f}), do: S.control_audit(f.(), seam).defects
  def run(%{inputs: f}), do: S.audit(f.()).defects

  # C9's stand-in reader: it drops one citation the raw scan still finds.
  defp drop_r1(_file, structured), do: Enum.reject(structured, &(&1.cite == "lib/a.ex:3"))

  defp entry_defects(name, call) do
    case call.() do
      {:error, defects} -> Enum.map(defects, &Map.put(&1, :entry, name))
      defects when is_list(defects) -> Enum.map(defects, &Map.put(&1, :entry, name))
      _accepted -> []
    end
  rescue
    e -> [%{kind: :raised, entry: name, art: nil, key: nil, detail: Exception.message(e)}]
  end

  defp runtime_ok?(:runtime_kinds_declared), do: runtime_kinds() != []
  defp runtime_ok?(k), do: S.fix(k) != "" and k in guard_kinds()

  @doc false
  def base_read(path), do: Map.fetch(sources(), path) |> or_enoent()

  @doc false
  def applied(i, r) do
    docs = Map.merge(i.docs, Map.new(r.docs, fn {k, v} -> {k, {:ok, v}} end))
    %{i | docs: docs, ledger: {:ok, S.encode_ledger(r.ledger)}}
  end

  @doc """
  The control holds: its kind is refused and the refusal names G33; for an
  `expect: :moved` control, the window moved, nothing of its kind was refused,
  and the result audits clean.
  """
  def holds?(%{expect: :clean, inputs: f}), do: S.audit(f.()).defects == []
  def holds?(%{mode: :meta}), do: guard_kinds() != [] and kinds_without_fix() == []

  # Every entry point refuses the row: audit lists it, --repin and --resolve
  # return {:error, defects}; a raise is not a refusal.
  # Every entry point refuses the planted row itself (V1): audit lists it,
  # --repin and --resolve return {:error, defects}; a raise is not a refusal.
  def holds?(%{mode: :entry_points, kind: k, row: row} = c) do
    by_entry = c |> run() |> Enum.group_by(& &1.entry)
    planted = row.()

    Enum.all?(~w(audit repin resolve)a, fn e ->
      Enum.any?(Map.get(by_entry, e, []), &own_refusal?(&1, k, planted))
    end)
  end

  def holds?(%{mode: :runtime_kinds} = c), do: run(c) == []
  def holds?(%{mode: :type_matrix} = c), do: matrix_fields() != [] and run(c) == []
  def holds?(%{mode: :field_list} = c), do: run(c) == []

  def holds?(%{expect: :moved, inputs: f} = c) do
    i = f.()
    r = S.resolve(i, &base_read/1)

    r.moved != [] and not Enum.any?(r.refused, &(&1.kind == c.kind)) and
      S.audit(applied(i, r)).defects == []
  end

  def holds?(c) do
    Enum.any?(run(c), fn d ->
      d.kind == c.kind and String.starts_with?(S.format_defect(d), S.guard() <> " ")
    end)
  end

  @doc """
  The reverts of a control for the `--reverted` limb: its `stubs`, its one
  `stub`, or its `limb`. A revert may name `cells`, the `state.field` cells
  of the type matrix it must fail.
  """
  def reverts(%{stubs: stubs}), do: stubs
  def reverts(%{stub: stub}), do: [%{stub: stub}]
  def reverts(%{limb: limb}), do: [%{limb: limb}]

  @doc """
  `{holds, failed}`: the control's verdict, and for the type matrix the
  `state.field` cells that failed (one run of the matrix for both).
  """
  def verdict(%{mode: :type_matrix} = c) do
    failures = run(c)

    failed =
      failures
      |> Enum.map(fn f -> f.key |> String.split(" = ", parts: 2) |> hd() end)
      |> Enum.uniq()

    {matrix_fields() != [] and failures == [], failed}
  end

  def verdict(c), do: {holds?(c), []}

  @doc "The positive control: the unplanted universe audits clean."
  def positive, do: S.audit(inputs()).defects
end

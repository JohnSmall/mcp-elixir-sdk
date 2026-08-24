defmodule MCP.Conformance.MatchKeyTest do
  @moduledoc """
  MES-68 (A3), AC2/AC3/AC4 — the mechanical proof that the naming convention is
  reversible, that it can return **NO**, and that the two awkward cardinalities
  are expressible without collapsing.

  ## What a green run here rules out, stated as construction rather than promise

  The positive half is cheap and would be green under a broken relation too: any
  encoder that concatenates fields round-trips. **The negative half is the
  evidence.** Five constructions are asserted to refuse, each one a wrong answer
  the relation could plausibly have given:

  1. a one-character mutation of a real token — the stale-key case;
  2. a real `name` under the wrong `check_id` — the `RequestMetaInvalid` case,
     and the exact failure the contributed page's `oc:<Name>#<disc>` token
     would have committed;
  3. a real `check_id` with a discriminator belonging to a sibling row;
  4. an `oc:none` token, which must NOT resolve as a key;
  5. a token whose five fields are each individually real but jointly unattested.

  A relation that cannot return NO is the F2 defect — an acceptance criterion
  satisfied by four wrong runs. So NO is what most of this file asserts.

  ## What it does NOT establish

  Everything here is measured against the **committed** manifest. It says
  nothing about whether a matched test asserts the same required behaviour as
  the check it names; that is the semantic-sameness residual and it escalates
  per case. It also says nothing about the axis decomposition being a correct
  reading of the harness — the axes are committed as data
  (`docs/conformance/oc-axes-2026-07-28.json`) with the build's sha alongside,
  and this file checks their internal consistency only.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.MatchKey

  @manifest_path "docs/conformance/in-scope-2026-07-28.json"
  @axes_path "docs/conformance/oc-axes-2026-07-28.json"

  setup_all do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()
    axes = @axes_path |> File.read!() |> Jason.decode!()
    {:ok, manifest: manifest, rows: MatchKey.rows_from_manifest(manifest), axes: axes}
  end

  describe "AC2 — reversibility, on both legs and both discriminator sources" do
    test "every one of the 175 rows encodes, and resolves back to itself", %{rows: rows} do
      assert length(rows) == 175

      for row <- rows do
        token = MatchKey.encode!(row)
        assert {:ok, ^row} = MatchKey.resolve(token, rows)
      end
    end

    test "both legs are exercised, so a server-only pass cannot read as total", %{rows: rows} do
      legs = rows |> Enum.map(&hd/1) |> Enum.frequencies()
      assert %{"server" => 119, "client" => 56} = legs
    end

    test "a differentiator-dependent key round-trips, and its siblings stay distinct", %{
      rows: rows
    } do
      # A1 rule 2 (`details.fieldIssue`) separated exactly these three rows. They
      # share id, name AND description, so this is the case the convention has to
      # survive: it is the only one where the discriminator carries the key.
      siblings =
        Enum.filter(rows, fn [_leg, _scen, id, _n, _d, _disc] ->
          id == "sep-2575-http-server-meta-invalid-400"
        end)

      assert length(siblings) == 3

      tokens = Enum.map(siblings, &MatchKey.encode!/1)
      assert length(Enum.uniq(tokens)) == 3

      assert ("oc:server/server-stateless/sep-2575-http-server-meta-invalid-400/" <>
                "HttpServerMetaInvalid400#missing-protocol-version") in tokens

      for {row, token} <- Enum.zip(siblings, tokens) do
        assert {:ok, ^row} = MatchKey.resolve(token, rows)
      end
    end

    test "the ordinal rule has no members today, so rule 2 is the only one under test", %{
      manifest: manifest
    } do
      # Stated rather than assumed: the page's worked example said these rows
      # "keep their #1/#2/#3" and they have no ordinals at all.
      assert %{"unique" => 172, "field_issue" => 3, "ordinal" => 0} =
               manifest["check_key"]["rows_by_discriminator_source"]
    end

    test "encode refuses rather than emitting an ambiguous token (A1 residual R3)" do
      base = ["server", "server-stateless", "sep-x", "NameX", "a sentence", ""]

      for {field, bad} <- [{1, "server/stateless"}, {2, "sep#x"}, {3, "Name X"}] do
        row = List.replace_at(base, field, bad)
        assert {:error, {:charset, _}} = MatchKey.encode(row)
      end

      assert {:error, {:unknown_leg, "none"}} =
               MatchKey.encode(["none", "s", "i", "N", "d", ""])
    end
  end

  describe "AC2 — the relation returns NO, which is the half that carries the evidence" do
    test "a one-character mutation resolves to nothing, never to a neighbour", %{rows: rows} do
      for row <- rows do
        token = MatchKey.encode!(row)
        mutated = String.replace(token, "-", "_", global: false)

        if mutated != token do
          assert {:error, :unresolved} = MatchKey.resolve(mutated, rows),
                 "mutation of #{token} resolved to a row"
        end
      end
    end

    test "a real name under the wrong check_id is refused — the page's token would not have been",
         %{rows: rows} do
      # Three `server-stateless` rows share name AND discriminator (empty) and are
      # separated only by check_id. A token keyed on name alone addresses all three.
      requests =
        Enum.filter(rows, fn [_l, _s, _id, name, _d, _disc] -> name == "RequestMetaInvalid" end)

      assert length(requests) >= 2

      [[_l, scenario, id_a, name, _d, _disc] | _] = requests

      [_l, _s, id_b, ^name, _d2, _disc2] =
        Enum.find(requests, fn [_, _, id, _, _, _] -> id != id_a end)

      refute id_a == id_b

      crossed = "oc:server/#{scenario}/#{id_a}/#{name}#not-a-real-discriminator"
      assert {:error, :unresolved} = MatchKey.resolve(crossed, rows)
    end

    test "a real check_id with a sibling's discriminator is refused", %{rows: rows} do
      token =
        "oc:server/server-stateless/sep-2575-request-meta-invalid-missing-meta/" <>
          "RequestMetaInvalid#missing-protocol-version"

      assert {:error, :unresolved} = MatchKey.resolve(token, rows)
    end

    test "an oc:none token decodes but must not resolve as a key", %{rows: rows} do
      # Claim-level native id per MES-77 — the module's own tests must not go on
      # illustrating the heading-only form §6 now forbids.
      {:ok, token} = MatchKey.none("no-oc-counterpart", "CG4", "network-ref-not-dereferenced")

      assert {:ok,
              %{
                kind: :none,
                reason: "no-oc-counterpart",
                native_id: "CG4-network-ref-not-dereferenced"
              }} = MatchKey.decode(token)

      assert {:error, :not_an_oc_key} = MatchKey.resolve(token, rows)
    end

    test "fields individually real but jointly unattested resolve to nothing", %{rows: rows} do
      # Every field below appears in the manifest; the combination does not.
      token =
        "oc:client/server-stateless/sep-2575-http-server-method-not-found-404-ping/" <>
          "HttpServerMethodNotFound404ping"

      assert {:error, :unresolved} = MatchKey.resolve(token, rows)
    end

    test "malformed tokens are refused by shape, before any lookup" do
      assert {:error, :missing_prefix} = MatchKey.decode("server/scenario/id/Name")
      assert {:error, {:bad_segment_count, 3}} = MatchKey.decode("oc:server/scenario/id")
      assert {:error, {:bad_segment_count, 5}} = MatchKey.decode("oc:a/b/c/d/e")
      assert {:error, :multiple_discriminators} = MatchKey.decode("oc:server/s/i/N#a#b")
      assert {:error, {:unknown_leg, "sever"}} = MatchKey.decode("oc:sever/s/i/N")
      assert {:error, {:not_a_token, :nope}} = MatchKey.decode(:nope)
    end
  end

  describe "the four-state guard — silence must not encode a decision" do
    test "state 1: an oc token that resolves is a matched edge", %{rows: rows} do
      token = rows |> hd() |> MatchKey.encode!()
      assert {:matched, key} = MatchKey.guard_state(token, rows)
      assert key == hd(rows)
    end

    test "state 2: an oc token that does not resolve FAILS, naming the decoded parts", %{
      rows: rows
    } do
      assert {:error, {:unresolved, %{kind: :oc, check_id: "sep-typo"}}} =
               MatchKey.guard_state("oc:server/server-stateless/sep-typo/Name", rows)
    end

    test "state 3: a declared non-match is a distinct, non-failing state", %{rows: rows} do
      {:ok, token} = MatchKey.none("no-oc-counterpart", "CG4", "network-ref-not-dereferenced")

      assert {:declared_unmatched, %{native_id: "CG4-network-ref-not-dereferenced"}} =
               MatchKey.guard_state(token, rows)
    end

    test "state 4: an untagged member FAILS — the cost, ratified with the cost named", %{
      rows: rows
    } do
      assert {:error, :untagged} = MatchKey.guard_state(nil, rows)
    end

    test "states 2 and 4 fail DIFFERENTLY, which is the whole point", %{rows: rows} do
      {:error, stale} = MatchKey.guard_state("oc:server/s/sep-typo/Name", rows)
      {:error, untagged} = MatchKey.guard_state(nil, rows)
      refute stale == untagged
    end
  end

  describe "AC3 — CG4 ↔ json-schema-ref-no-deref is expressible as exactly ONE edge" do
    setup %{rows: rows} do
      {:ok, key} =
        MatchKey.resolve(
          "oc:client/json-schema-ref-no-deref/sep-2106-no-network-ref-deref/NoNetworkRefDereference",
          rows
        )

      {:ok, key: key}
    end

    test "the claim-bearing member contributes one edge; the control contributes none", %{
      key: key
    } do
      # Two ET tests, one OC check. The `:133` control is ET-CTRL under MES-67's
      # criterion — it asserts the canary counter, not the SDK — so it is not an
      # ET-CC member and cannot contribute an edge. "2 tests, 1 check" resolves
      # to "1 claim, 1 control, 1 edge".
      members = [
        %{
          member: %{
            module: "MCP.ClientConformanceTest",
            test:
              "listing and calling a tool whose inputSchema $refs a network URI never fetches it"
          },
          claim: "the client does not dereference a network-URI $ref",
          oc_key: key,
          verdicts: %{oc: :green, et: :green},
          axes: [%{axis: "canary_not_fetched", verdict: :agrees}]
        }
      ]

      edges =
        Enum.map(members, fn attrs ->
          {:ok, edge} = MatchKey.new_edge(attrs)
          edge
        end)

      assert length(edges) == 1
      assert [%{shape: :full}] = edges
      assert {:ok, "5", []} = edges |> hd() |> MatchKey.bucket()
    end
  end

  describe "AC4 — the :83 one-to-three case, with three verdicts PRESERVED" do
    setup %{rows: rows} do
      member = %{
        module: "MCP.Transport.StreamableHTTPStatelessTest",
        test: "initialize is gone → -32022; ping/logging.setLevel → -32601"
      }

      claims = [
        {"initialize → -32022", "sep-2575-http-server-method-not-found-404-initialize",
         [
           %{axis: "jsonrpc_error_code", verdict: :contradicts},
           %{axis: "http_status", verdict: :silent}
         ]},
        {"ping → -32601", "sep-2575-http-server-method-not-found-404-ping",
         [
           %{axis: "jsonrpc_error_code", verdict: :agrees},
           %{axis: "http_status", verdict: :silent}
         ]},
        {"logging/setLevel → -32601",
         "sep-2575-http-server-method-not-found-404-logging-setlevel",
         [
           %{axis: "jsonrpc_error_code", verdict: :agrees},
           %{axis: "http_status", verdict: :silent}
         ]}
      ]

      build = fn {claim, check_id, axes} ->
        {:ok, key} =
          MatchKey.resolve("oc:server/server-stateless/#{check_id}/#{name_of(check_id)}", rows)

        {:ok, edge} =
          MatchKey.new_edge(%{
            member: member,
            claim: claim,
            oc_key: key,
            verdicts: %{oc: :red, et: :green},
            axes: axes
          })

        edge
      end

      {:ok, claims: claims, build: build}
    end

    test "one member yields three edges, none of them collapsible", %{
      claims: claims,
      build: build
    } do
      edges = Enum.map(claims, build)

      assert length(edges) == 3
      assert length(Enum.uniq_by(edges, & &1.tag)) == 3
      assert length(Enum.uniq_by(edges, & &1.claim)) == 3

      # The load-bearing assertion: a future implementation that keys edges on
      # the MEMBER rather than on the claim collapses these three to one, and
      # this line is what fails when it does.
      assert length(Enum.uniq(edges)) == 3
    end

    test "the three shapes and buckets differ — 4a for initialize, 4b for the other two", %{
      claims: claims,
      build: build
    } do
      [init, ping, logging] = Enum.map(claims, build)

      assert init.shape == :contradicting
      assert ping.shape == :partial
      assert logging.shape == :partial

      assert {:ok, "4a", []} = MatchKey.bucket(init)
      assert {:ok, "4b", []} = MatchKey.bucket(ping)
      assert {:ok, "4b", []} = MatchKey.bucket(logging)
    end

    test "order-freeness: the same three edges in reverse yield the same buckets", %{
      claims: claims,
      build: build
    } do
      forward = claims |> Enum.map(build) |> Enum.map(&{&1.claim, MatchKey.bucket(&1)})

      reverse =
        claims |> Enum.reverse() |> Enum.map(build) |> Enum.map(&{&1.claim, MatchKey.bucket(&1)})

      assert Enum.sort(forward) == Enum.sort(reverse)
    end
  end

  describe "the bucket function — f(verdict pair, edge shape), with precedence" do
    test "contradicts beats silent, so 4a and 4b are exclusive by construction" do
      both = [
        %{axis: "jsonrpc_error_code", verdict: :contradicts},
        %{axis: "http_status", verdict: :silent}
      ]

      assert {:ok, :contradicting} = MatchKey.shape_from_axes(both)
      assert {:ok, :contradicting} = MatchKey.shape_from_axes(Enum.reverse(both))
    end

    test "a partial edge over a GREEN check is bucket 5, not 4b" do
      # This is the case that falsifies the contributed page's "partial => 4b".
      # It is invisible on the R2 class because those 12 checks are OC-red anyway.
      edge = %{
        verdicts: %{oc: :green, et: :green},
        shape: :partial
      }

      assert {:ok, "5", [:partial]} = MatchKey.bucket(edge)
    end

    test "the verdict pair ALONE cannot decide, because 4a and 4b share it" do
      pair = %{oc: :red, et: :green}

      assert {:ok, "4a", []} = MatchKey.bucket(%{verdicts: pair, shape: :contradicting})
      assert {:ok, "4b", []} = MatchKey.bucket(%{verdicts: pair, shape: :partial})
    end

    test "the pair alone DOES decide 3 and 6, whatever the shape" do
      for shape <- [:full, :partial, :contradicting] do
        assert {:ok, "3", []} =
                 MatchKey.bucket(%{verdicts: %{oc: :green, et: :red}, shape: shape})

        assert {:ok, "6", []} = MatchKey.bucket(%{verdicts: %{oc: :red, et: :red}, shape: shape})
      end
    end

    test "the two escalations are escalations, not buckets" do
      assert {:escalate, :divergent_despite_agreement} =
               MatchKey.bucket(%{verdicts: %{oc: :red, et: :green}, shape: :full})

      assert {:escalate, :inconsistent_verdict_pair} =
               MatchKey.bucket(%{verdicts: %{oc: :green, et: :green}, shape: :contradicting})
    end

    test "an edge with no axes has no shape, so it cannot be bucketed by accident" do
      assert {:error, :no_axes} = MatchKey.shape_from_axes([])

      assert {:error, :bad_axis_verdict} =
               MatchKey.shape_from_axes([%{axis: "x", verdict: :maybe}])
    end
  end

  describe "the edge record — what C1 stores, and what a reader can check" do
    test "shape is DERIVED, so a stored edge cannot lie about its own axes", %{rows: rows} do
      {:ok, edge} = MatchKey.new_edge(valid_edge_attrs(rows))
      assert :ok = MatchKey.validate_edge(edge)

      assert {:error, {:derived_field_mismatch, :partial}} =
               MatchKey.validate_edge(%{edge | shape: :full})
    end

    test "a tampered tag is caught against the key it claims to encode", %{rows: rows} do
      {:ok, edge} = MatchKey.new_edge(valid_edge_attrs(rows))

      assert {:error, {:derived_field_mismatch, _}} =
               MatchKey.validate_edge(%{edge | tag: "oc:server/s/i/N"})
    end

    test "the member is MES-67's unit — module AND test name, never the name alone", %{rows: rows} do
      attrs = valid_edge_attrs(rows)

      assert {:error, {:bad_member, _}} =
               MatchKey.new_edge(%{attrs | member: %{test: "round-trips through JSON"}})

      assert {:error, {:bad_member, _}} =
               MatchKey.new_edge(%{attrs | member: %{module: "M", test: ""}})
    end

    test "an edge without a claim is refused — the claim is the atom of matching", %{rows: rows} do
      attrs = valid_edge_attrs(rows)
      assert {:error, {:bad_claim, _}} = MatchKey.new_edge(%{attrs | claim: ""})
    end

    test "verdicts outside the vocabulary are refused", %{rows: rows} do
      attrs = valid_edge_attrs(rows)

      assert {:error, {:bad_verdicts, _}} =
               MatchKey.new_edge(%{attrs | verdicts: %{oc: :amber, et: :green}})
    end
  end

  describe "the committed axis data — axes come from the PREDICATE, never the description" do
    test "every axis row names a key that resolves in A1's manifest", %{axes: axes, rows: rows} do
      assert axes["checks"] != []

      for check <- axes["checks"] do
        token = MatchKey.encode!(check["key"])

        assert {:ok, _row} = MatchKey.resolve(token, rows),
               "axis row #{token} does not resolve in the manifest"
      end
    end

    test "every axis expression appears verbatim in the excerpt it was read from", %{axes: axes} do
      for check <- axes["checks"], axis <- check["axes"] do
        assert String.contains?(check["evaluator_excerpt"], axis["expr"]),
               "#{axis["expr"]} is not a substring of the excerpt for #{check["key"]}"
      end
    end

    test "the trap case is recorded as ONE axis, though its description names two", %{axes: axes} do
      trap =
        Enum.find(axes["checks"], fn c ->
          Enum.at(c["key"], 2) == "sep-2575-http-server-unsupported-version-400"
        end)

      # description: "MUST respond with 400 Bad Request AND an
      # UnsupportedProtocolVersionError listing its supported versions"
      # predicate:   S.status === 400
      assert String.contains?(Enum.at(trap["key"], 4), "UnsupportedProtocolVersionError")
      assert length(trap["axes"]) == 1
      assert hd(trap["axes"])["expr"] == "S.status===400"
    end

    test "the 7/5 split is what the committed axes say, and it is marked provisional", %{
      axes: axes
    } do
      status_bearing = Enum.filter(axes["checks"], & &1["carries_http_status_in_error_message"])
      assert length(status_bearing) == 12

      by_axis_count = Enum.frequencies_by(status_bearing, &length(&1["axes"]))
      assert %{2 => 7, 1 => 5} == by_axis_count

      assert axes["provisional_pending"] =~ "B2a"
    end

    test "provenance names the build the axes were read from", %{axes: axes, manifest: manifest} do
      sha = axes["provenance"]["harness_dist_sha256"]
      assert sha == manifest["provenance"]["server"]["harness_dist_sha256"]
      assert sha == manifest["provenance"]["client"]["harness_dist_sha256"]
    end
  end

  describe "MES-76 F1 — the artefact can be reached the way a consumer travels" do
    test "the authoring procedure is kept, renamed, and says what it presupposes", %{axes: axes} do
      # The old procedure is not wrong; it is the wrong DIRECTION, and it records
      # how the rows were actually cut. Deleting it would trade one gap for
      # another, so it is renamed and labelled rather than removed.
      provenance = axes["provenance"]

      refute Map.has_key?(provenance, "extraction_procedure")
      assert is_list(provenance["authoring_procedure"])

      preamble = hd(provenance["authoring_procedure"])
      assert preamble =~ "axis -> site"
      assert preamble =~ "presupposes"
      assert preamble =~ "reverse_lookup_procedure"

      # the original four steps survive the rename
      assert length(provenance["authoring_procedure"]) == 5
      assert Enum.any?(provenance["authoring_procedure"], &(&1 =~ "Locate the axis expression"))
    end

    test "the reverse-lookup procedure runs check_id -> site and names all three forms", %{
      axes: axes
    } do
      reverse = axes["provenance"]["reverse_lookup_procedure"]

      assert reverse["direction"] =~ "check_id -> emitting site"

      # The clause that matters most: a consumer meeting an empty grep is
      # exactly where the fallback to reading the check's `description` happens,
      # and that is the one move MES-68 exists to forbid.
      empty_grep = reverse["cases"]["0_occurrences_TEMPLATE"]
      assert empty_grep =~ "THE GREP RETURNED NOTHING"
      assert empty_grep =~ "must NOT fall back"
      assert empty_grep =~ "description"

      assert MapSet.new(Map.keys(reverse["cases"])) ==
               MapSet.new([
                 "0_occurrences_TEMPLATE",
                 "1_occurrence_LITERAL_or_CONSTANT",
                 "2_occurrences_LITERAL_PLUS_PREFIX"
               ])
    end

    test "every row carries a locator, and its occurrence count agrees with its form", %{
      axes: axes
    } do
      # The taxonomy was already honest — `form` and `id_source` carried this
      # distinction before MES-76. What was missing is the locator that consumes
      # it. This asserts the two cannot drift apart.
      by_form =
        for check <- axes["checks"] do
          locator = check["emitting_site"]["locator"]
          form = check["emitting_site"]["form"]

          assert is_integer(locator["check_id_occurrences"])
          assert locator["grep_for"] != ""
          assert locator["disambiguate"] != ""

          case form do
            "template" ->
              # 0 occurrences, so grep_for MUST be something other than the id
              assert locator["check_id_occurrences"] == 0
              refute locator["grep_for"] == Enum.at(check["key"], 2)
              assert String.starts_with?(Enum.at(check["key"], 2), locator["grep_for"])

            _ ->
              assert locator["check_id_occurrences"] > 0
          end

          form
        end

      # 7 literal, 5 template, 1 constant = 13, enumerated rather than counted.
      assert Enum.frequencies(by_form) == %{"literal" => 7, "template" => 5, "constant" => 1}
    end

    test "the 6 of 13 a check_id grep cannot reach are exactly the 5 templates + the constant", %{
      axes: axes
    } do
      # F1's central figure, stated as a set rather than a count.
      unreachable =
        for check <- axes["checks"],
            check["emitting_site"]["locator"]["check_id_occurrences"] == 0 or
              check["emitting_site"]["form"] == "constant",
            into: MapSet.new(),
            do: Enum.at(check["key"], 2)

      assert unreachable ==
               MapSet.new([
                 "sep-2575-http-server-method-not-found-404-initialize",
                 "sep-2575-http-server-method-not-found-404-ping",
                 "sep-2575-http-server-method-not-found-404-logging-setlevel",
                 "sep-2575-http-server-method-not-found-404-resources-subscribe",
                 "sep-2575-http-server-method-not-found-404-resources-unsubscribe",
                 "sep-2106-no-network-ref-deref"
               ])

      assert MapSet.size(unreachable) == 6
    end

    test "the two-hit row is flagged, and its disambiguator names both hits", %{axes: axes} do
      two_hit =
        Enum.filter(
          axes["checks"],
          &(&1["emitting_site"]["locator"]["check_id_occurrences"] == 2)
        )

      assert length(two_hit) == 1
      row = hd(two_hit)
      assert Enum.at(row["key"], 2) == "sep-2575-http-server-method-not-found-404"

      # It is a prefix of the template ids, which is WHY it has two hits.
      disambiguate = row["emitting_site"]["locator"]["disambiguate"]
      assert disambiguate =~ "PREFIX"
      assert disambiguate =~ "closing backtick"

      template_ids =
        for c <- axes["checks"],
            c["emitting_site"]["form"] == "template",
            do: Enum.at(c["key"], 2)

      assert length(template_ids) == 5

      for id <- template_ids do
        assert String.starts_with?(id, Enum.at(row["key"], 2))
      end
    end

    test "the three rows sharing ONE emitting site say so", %{axes: axes} do
      # Finding the site does not finish the job of identifying the row: three
      # manifest rows are separated by `discriminator`, not by position in the
      # dist. A consumer who stops at the site would read three rows as one.
      shared =
        Enum.filter(axes["checks"], fn c ->
          Enum.at(c["key"], 2) == "sep-2575-http-server-meta-invalid-400"
        end)

      assert length(shared) == 3

      assert MapSet.new(shared, &Enum.at(&1["key"], 5)) ==
               MapSet.new([
                 "missing-meta",
                 "missing-protocol-version",
                 "missing-client-capabilities"
               ])

      # one site: identical spans, and the locator warns about it
      assert shared
             |> Enum.map(& &1["emitting_site"]["dist_byte_span"])
             |> Enum.uniq()
             |> length() ==
               1

      for row <- shared do
        assert row["emitting_site"]["locator"]["disambiguate"] =~
                 "THREE manifest rows share this ONE site"
      end
    end

    test "step 0 is the recorded span, and every row still carries both span kinds", %{axes: axes} do
      # The claim the procedure rests on: for a row already in this file the
      # traversal is skipped entirely. The spans' agreement with the excerpt is
      # measured against the real build in
      # conformance/controls/oc_axes_reverse_lookup_control.exs (that needs the
      # /tmp harness build, which this suite must not require). Here we assert
      # the artefact carries what that control needs.
      assert axes["provenance"]["reverse_lookup_procedure"]["step_0_if_the_row_is_already_here"] =~
               "SKIP THE TRAVERSAL ENTIRELY"

      for check <- axes["checks"] do
        assert [b_start, b_end] = check["emitting_site"]["dist_byte_span"]
        assert [c_start, c_end] = check["emitting_site"]["dist_char_span"]
        assert b_end > b_start
        assert c_end > c_start
        # the excerpt's own length ties the two: same characters, same count
        assert c_end - c_start == String.length(check["evaluator_excerpt"])
        assert b_end - b_start == byte_size(check["evaluator_excerpt"])
      end
    end
  end

  describe "MES-76 F2 — axis polarity is AUTHORED, total, and checked against the rows" do
    test "every axis carries a polarity drawn from the two-value vocabulary", %{axes: axes} do
      # Totality proved by SET COMPARISON over the axes, not by a pattern that
      # matched most of them. F2 exists because an operator-keyed classifier
      # returned 5/14/1-undecidable here — it could not see the one row that
      # uses neither `===` nor `!==`.
      all_axes = Enum.flat_map(axes["checks"], & &1["axes"])
      assert length(all_axes) == 20

      with_polarity = Enum.filter(all_axes, &Map.has_key?(&1, "polarity"))
      assert length(with_polarity) == length(all_axes)

      assert MapSet.new(all_axes, & &1["polarity"]) ==
               MapSet.new(["pass_when_true", "fail_when_true"])

      for axis <- all_axes do
        assert is_binary(axis["polarity_reading"]) and axis["polarity_reading"] != "",
               "#{axis["axis"]} carries a polarity with no stated reading"
      end
    end

    test "the stated totals are RECOMPUTED from the rows, not asserted alongside them", %{
      axes: axes
    } do
      # A total written next to the data it describes can drift from it. This
      # recomputes and compares, so the artefact's own summary cannot lie.
      counted =
        axes["checks"]
        |> Enum.flat_map(& &1["axes"])
        |> Enum.frequencies_by(& &1["polarity"])

      totals = axes["polarity_totals"]

      assert counted["pass_when_true"] == totals["pass_when_true"]
      assert counted["fail_when_true"] == totals["fail_when_true"]
      assert counted["pass_when_true"] + counted["fail_when_true"] == totals["total_axes"]
      assert totals["total_axes"] == 20
      assert %{"pass_when_true" => 5, "fail_when_true" => 15} == counted
    end

    test "the row an operator-keyed derivation CANNOT classify is polarised anyway", %{axes: axes} do
      # The specific row that makes authorship necessary rather than tidy. If a
      # future edit ever derives polarity from the operator, this is the
      # assertion that catches it.
      canary =
        axes["checks"]
        |> Enum.flat_map(& &1["axes"])
        |> Enum.find(&(&1["axis"] == "canary_not_fetched"))

      assert canary["expr"] == "this.canaryRequests.length>0"
      refute String.contains?(canary["expr"], "===")
      refute String.contains?(canary["expr"], "!==")
      assert canary["polarity"] == "fail_when_true"
      assert axes["polarity_rule"] =~ "AUTHORED, NOT DERIVED"
    end
  end

  describe "MES-76 F3 — preconditions are checkable, and `[]` is not a legal value" do
    test "no check records an empty precondition list", %{axes: axes} do
      # The sentinel rule, enforced. Before MES-76, 5 of 13 recorded `[]` while
      # having guards of exactly the shape the other 8 did record — so `[]` read
      # as "checked, and none" when it meant "not recorded". This project's rule
      # is that those two must not print identically; this is that rule one
      # field down, inside the artefact built to enforce it.
      empty = Enum.filter(axes["checks"], &(&1["preconditions"] == []))

      assert empty == [],
             "rows recording []: #{inspect(Enum.map(empty, &Enum.at(&1["key"], 2)))}"

      assert length(axes["checks"]) == 13
      assert axes["preconditions_rule"] =~ "NOT A LEGAL VALUE"
    end

    test "every guard and on_failure is a VERBATIM substring of its own row's excerpt", %{
      axes: axes
    } do
      # This is what the object form buys, and the reason Q1 was worth its cost:
      # the same discipline `expr` already keeps. Prose would have been
      # unverifiable, and F3 is a finding about a field that understates what it
      # records — repairing it with something uncheckable would reproduce the
      # defect one level up.
      counted =
        for check <- axes["checks"], precondition <- check["preconditions"] do
          check_id = Enum.at(check["key"], 2)

          assert String.contains?(check["evaluator_excerpt"], precondition["guard"]),
                 "#{check_id}: guard #{inspect(precondition["guard"])} is not in its excerpt"

          assert String.contains?(check["evaluator_excerpt"], precondition["on_failure"]),
                 "#{check_id}: on_failure #{inspect(precondition["on_failure"])} is not in its excerpt"

          assert is_binary(precondition["reads"]) and precondition["reads"] != ""
          precondition["kind"]
        end

      # 8 converted from the prose form + 6 added by MES-76 = 14, enumerated
      # rather than counted: 12 rows with one, and missing-capability with two.
      assert length(counted) == 14
      assert Enum.frequencies(counted) == %{"network" => 12, "semantic" => 2}
    end

    test "the sixth row's TWO guards are both recorded, and they are different kinds", %{
      axes: axes
    } do
      # `missing-capability-http-400` was not among the five `[]` rows: it
      # recorded its semantic guard and omitted its network one. A different
      # omission from an empty list, and collapsing the two would lose that.
      row =
        Enum.find(axes["checks"], fn c ->
          Enum.at(c["key"], 2) == "sep-2575-missing-capability-http-400"
        end)

      assert length(row["preconditions"]) == 2
      assert MapSet.new(row["preconditions"], & &1["kind"]) == MapSet.new(["network", "semantic"])

      assert Enum.any?(row["preconditions"], &(&1["guard"] == "()=>O?"))
      assert Enum.any?(row["preconditions"], &(&1["guard"] == "()=>O?A?"))
    end

    test "the five rows that recorded [] now each carry their guard", %{axes: axes} do
      # Enumerated, not counted (epic ruling 4 / A2d) — F3 is in this ticket
      # precisely because a count and an enumeration disagreed.
      five = [
        {"sep-2575-http-server-meta-invalid-400", "missing-meta"},
        {"sep-2575-http-server-meta-invalid-400", "missing-protocol-version"},
        {"sep-2575-http-server-meta-invalid-400", "missing-client-capabilities"},
        {"sep-2575-http-server-unsupported-version-400", ""},
        {"sep-2575-http-server-header-mismatch-400", ""}
      ]

      for {check_id, discriminator} <- five do
        row =
          Enum.find(axes["checks"], fn c ->
            Enum.at(c["key"], 2) == check_id and Enum.at(c["key"], 5) == discriminator
          end)

        assert row, "#{check_id}##{discriminator} is not in the artefact"
        assert row["preconditions"] != []
        assert hd(row["preconditions"])["kind"] == "network"
      end

      assert length(five) == 5
    end

    test "the schema version records that the shape changed", %{axes: axes} do
      # A consumer written against version 1 must be able to tell.
      assert axes["axes_schema_version"] == 2
    end
  end

  describe "MES-77 — the native-id slot names a CLAIM, not a requirement heading" do
    # A4's real seven (cg-reconciliation.md §5), not synthesised pairs: two
    # invented claims would demonstrate the arithmetic of deduplication and
    # nothing about this tree.
    @a4_claims [
      {"CG2", "inbound-parse"},
      {"CG2", "absent-yields-nil"},
      {"CG2", "unknown-not-a-fault"},
      {"CG2", "outbound-meta"},
      {"CG7", "annotated-number-excluded"},
      {"CG7", "integer-safe-range"},
      {"CG7", "static-reachability"}
    ]

    test "native_id/2 composes the two parts" do
      assert {:ok, "CG7-annotated-number-excluded"} =
               MatchKey.native_id("CG7", "annotated-number-excluded")
    end

    test "an origin id containing a hyphen is fine — a Jira key is a legal origin" do
      # MES-82 will meet bucket-1 claims belonging to NO CG, whose natural
      # origin is the owning ticket. A separator rule reserving the first `-`
      # would forbid exactly those.
      assert {:ok, "MES-38-listen-stream-consumed"} =
               MatchKey.native_id("MES-38", "listen-stream-consumed")
    end

    test "native_id/2 REFUSES rather than emitting a token decode/1 would mis-split" do
      assert {:error, {:empty, "claim_slug"}} = MatchKey.native_id("CG7", "")
      assert {:error, {:empty, "origin_id"}} = MatchKey.native_id("", "a-claim")
      assert {:error, {:not_a_string, "claim_slug"}} = MatchKey.native_id("CG7", nil)
      assert {:error, {:charset, "claim_slug"}} = MatchKey.native_id("CG7", "a/b")
      assert {:error, {:charset, "claim_slug"}} = MatchKey.native_id("CG7", "a#b")
      assert {:error, {:charset, "claim_slug"}} = MatchKey.native_id("CG7", "a b")
      assert {:error, {:charset, "origin_id"}} = MatchKey.native_id("CG/7", "a-claim")
    end

    test "none/3 composes native_id/2, and propagates its refusal" do
      assert {:ok, "oc:none/no-oc-fixture-case/CG7-integer-safe-range"} =
               MatchKey.none("no-oc-fixture-case", "CG7", "integer-safe-range")

      assert {:error, {:charset, "claim_slug"}} =
               MatchKey.none("no-oc-fixture-case", "CG7", "a/b")
    end

    test "none/2 keeps its open contract — it cannot know the caller's taxonomy" do
      # A unit-level id is ALREADY claim-level and has no heading part to
      # suffix. Refusing it here would be a false refusal, not safety.
      assert {:ok, "oc:none/no-oc-scenario/T-CG1a"} = MatchKey.none("no-oc-scenario", "T-CG1a")
    end

    test "none/2 accepts a HYPHEN-FREE origin id — the open contract is not a separator rule" do
      # CR-M8: `none/2` made to reject a heading-only id survived gate 5,
      # because the re-point left `T-CG1a` as the sole witness and it happens
      # to contain a hyphen. A bare `CG4` has none, so it pins the contract
      # ruling (3) preserved against the natural over-strict implementation.
      assert {:ok, "oc:none/no-oc-counterpart/CG4"} = MatchKey.none("no-oc-counterpart", "CG4")
    end

    test "the new form round-trips: builder -> decode/1 -> the same native id" do
      for {origin_id, claim_slug} <- @a4_claims do
        {:ok, expected} = MatchKey.native_id(origin_id, claim_slug)
        {:ok, token} = MatchKey.none("no-oc-scenario", origin_id, claim_slug)

        assert {:ok, %{kind: :none, reason: "no-oc-scenario", native_id: ^expected}} =
                 MatchKey.decode(token)
      end
    end

    test "and still guards to state 3 — the scheme change must not move the guard", %{rows: rows} do
      for {origin_id, claim_slug} <- @a4_claims do
        {:ok, token} = MatchKey.none("no-oc-scenario", origin_id, claim_slug)
        assert {:declared_unmatched, %{kind: :none}} = MatchKey.guard_state(token, rows)
      end
    end

    test "THE OLD SCHEME FAILS: a bare CG number names all of that CG's claims" do
      # The demonstration AC4 asks for, held here so gate 5 carries it. Under
      # §6 as first ratified, all three CG7 claims carried native id "CG7".
      rows =
        for {origin_id, claim_slug} <- @a4_claims, origin_id == "CG7", do: {origin_id, claim_slug}

      assert {:error, {:native_id_names_two_claims, "CG7", claims}} =
               MatchKey.declared_claim_index(rows)

      assert claims == [
               "annotated-number-excluded",
               "integer-safe-range",
               "static-reachability"
             ]
    end

    test "the new scheme is accepted, one entry per claim" do
      rows =
        for {origin_id, claim_slug} <- @a4_claims do
          {:ok, id} = MatchKey.native_id(origin_id, claim_slug)
          {id, claim_slug}
        end

      assert {:ok, index} = MatchKey.declared_claim_index(rows)
      assert map_size(index) == 7
      assert index["CG7-integer-safe-range"] == "integer-safe-range"
    end

    test "REPEATS OF ONE ID WITH THE SAME CLAIM ARE LEGAL, and that is not a leniency" do
      # CG7's three constraint families are discharged by NINE ET-CC units
      # (header_mirror_test.exs:113,120,134,157,169,195,207,224,233), so nine
      # members legitimately share three native ids. A "no two members share an
      # id" rule would reject correct data.
      rows =
        List.duplicate({"CG7-static-reachability", "static-reachability"}, 6) ++
          List.duplicate({"CG7-annotated-number-excluded", "annotated-number-excluded"}, 2) ++
          [{"CG7-integer-safe-range", "integer-safe-range"}]

      assert length(rows) == 9
      assert {:ok, index} = MatchKey.declared_claim_index(rows)
      assert map_size(index) == 3
    end

    test "the offender reported is the lexically first, so a refusal is reproducible" do
      rows = [
        {"ZZ", "one"},
        {"ZZ", "two"},
        {"AA", "one"},
        {"AA", "two"}
      ]

      assert {:error, {:native_id_names_two_claims, "AA", ["one", "two"]}} =
               MatchKey.declared_claim_index(rows)
    end

    test "malformed rows are refused by shape, before any grouping" do
      assert {:error, {:bad_row, :nope}} = MatchKey.declared_claim_index([:nope])
      assert {:error, {:bad_row, {"id", ""}}} = MatchKey.declared_claim_index([{"id", ""}])
      assert {:error, {:bad_row, {"", "claim"}}} = MatchKey.declared_claim_index([{"", "claim"}])
      assert {:error, {:not_a_row_list, :nope}} = MatchKey.declared_claim_index(:nope)
    end

    test "an empty register is legal — no rows is not a collision" do
      assert {:ok, index} = MatchKey.declared_claim_index([])
      assert index == %{}
    end
  end

  describe "MES-76 — bucket/1 is EXHAUSTIVE over its domain, and the domain is READ" do
    # MES-68's contribution was finding an implicit case in a total-looking
    # table: {:red, :green, :full} fell through to :undecidable in a table that
    # read as complete. Five hand-written examples covered all 12 combinations
    # between them, but nothing asserted that 12 WAS the count — so the same
    # defect could recur and the suite would still be green.
    #
    # The domain therefore comes from the module (`run_verdicts/0`,
    # `edge_shapes/0`) rather than from a literal in this file. A literal 2x2x3
    # asserting its own completeness would be a total-looking table with an
    # implicit case, which is the exact shape under repair.

    test "the domain is 2 x 2 x 3, and the accessors are the real vocabularies" do
      # An accessor that merely DECLARES a vocabulary could be wrong in the same
      # way the bucket table was. So: assert the sizes, then prove below that
      # each value is genuinely reachable through the module's own functions.
      assert length(MatchKey.run_verdicts()) == 2
      assert length(MatchKey.edge_shapes()) == 3
      assert MapSet.new(MatchKey.run_verdicts()) == MapSet.new([:green, :red])
      assert MapSet.new(MatchKey.edge_shapes()) == MapSet.new([:contradicting, :partial, :full])
    end

    test "every shape in edge_shapes/0 is producible by shape_from_axes/1, and nothing else is" do
      # Ties `edge_shapes/0` to the function that actually derives a shape, so
      # the accessor cannot drift into naming a shape the module never yields.
      # Enumerated over the full axis-verdict product up to arity 2 rather than
      # over chosen examples.
      verdicts = [:agrees, :contradicts, :silent]

      produced =
        for a <- verdicts, b <- verdicts, into: MapSet.new() do
          axes = [%{axis: "a", verdict: a}, %{axis: "b", verdict: b}]
          {:ok, shape} = MatchKey.shape_from_axes(axes)
          shape
        end

      assert produced == MapSet.new(MatchKey.edge_shapes())
    end

    test "every verdict in run_verdicts/0 is accepted by new_edge/1, and nothing else is", %{
      rows: rows
    } do
      # The converse tie for the other accessor: the pair vocabulary bucket/1
      # ranges over is the pair vocabulary an edge can actually carry.
      attrs = valid_edge_attrs(rows)

      for oc <- MatchKey.run_verdicts(), et <- MatchKey.run_verdicts() do
        assert {:ok, edge} = MatchKey.new_edge(%{attrs | verdicts: %{oc: oc, et: et}})
        assert edge.verdicts == %{oc: oc, et: et}
      end

      # and a verdict outside the vocabulary is refused, so "accepted" above is
      # a discriminating result rather than a function that accepts anything.
      assert {:error, {:bad_verdicts, _}} =
               MatchKey.new_edge(%{attrs | verdicts: %{oc: :amber, et: :green}})
    end

    test "all 12 cells are decided: a bucket, or one of the TWO NAMED escalations" do
      # The assertion the suite was missing. Nothing may reach :undecidable —
      # that clause is the fall-through, and a cell landing there means the
      # table has an implicit case again.
      cells =
        for oc <- MatchKey.run_verdicts(),
            et <- MatchKey.run_verdicts(),
            shape <- MatchKey.edge_shapes() do
          {{oc, et, shape}, MatchKey.bucket(%{verdicts: %{oc: oc, et: et}, shape: shape})}
        end

      # 2 x 2 x 3, and the count is derived from the accessors, not written here.
      assert length(cells) ==
               length(MatchKey.run_verdicts()) * length(MatchKey.run_verdicts()) *
                 length(MatchKey.edge_shapes())

      assert length(cells) == 12

      for {domain_point, result} <- cells do
        case result do
          {:ok, bucket, attrs} when is_binary(bucket) and is_list(attrs) ->
            :ok

          {:escalate, reason}
          when reason in [:divergent_despite_agreement, :inconsistent_verdict_pair] ->
            :ok

          other ->
            flunk("#{inspect(domain_point)} is undecided: #{inspect(other)}")
        end
      end
    end

    test "the 12 cells are compared as a SET against the domain, so none can be skipped" do
      # A `for` comprehension that silently produced 11 cells would pass the
      # loop above. This is the check that it did not: the keys of the result
      # are exactly the domain product.
      domain =
        for oc <- MatchKey.run_verdicts(),
            et <- MatchKey.run_verdicts(),
            shape <- MatchKey.edge_shapes(),
            into: MapSet.new(),
            do: {oc, et, shape}

      covered =
        for oc <- MatchKey.run_verdicts(),
            et <- MatchKey.run_verdicts(),
            shape <- MatchKey.edge_shapes(),
            match?({:ok, _, _}, MatchKey.bucket(%{verdicts: %{oc: oc, et: et}, shape: shape})) or
              match?(
                {:escalate, _},
                MatchKey.bucket(%{verdicts: %{oc: oc, et: et}, shape: shape})
              ),
            into: MapSet.new(),
            do: {oc, et, shape}

      assert MapSet.size(domain) == 12
      assert covered == domain
      assert MapSet.difference(domain, covered) == MapSet.new()
    end

    test "the two named escalations land on exactly the cells they are named for" do
      # Exhaustiveness alone would be satisfied by a table that escalated
      # everywhere. This pins WHICH cells escalate, so the previous test cannot
      # be passed by a degenerate implementation.
      escalating =
        for oc <- MatchKey.run_verdicts(),
            et <- MatchKey.run_verdicts(),
            shape <- MatchKey.edge_shapes(),
            {:escalate, reason} <-
              [MatchKey.bucket(%{verdicts: %{oc: oc, et: et}, shape: shape})],
            into: %{},
            do: {{oc, et, shape}, reason}

      assert escalating == %{
               {:red, :green, :full} => :divergent_despite_agreement,
               {:green, :green, :contradicting} => :inconsistent_verdict_pair
             }
    end

    test ":undecidable is still reachable — from OUTSIDE the domain, which is its job" do
      # The fall-through clause is not dead code and this ticket does not remove
      # it. It is what catches a value that is not in the vocabulary at all. If
      # it were unreachable the exhaustiveness claim above would be vacuous.
      assert {:escalate, {:undecidable, :amber, :green, :full}} =
               MatchKey.bucket(%{verdicts: %{oc: :amber, et: :green}, shape: :full})

      assert {:escalate, {:undecidable, :green, :green, :sideways}} =
               MatchKey.bucket(%{verdicts: %{oc: :green, et: :green}, shape: :sideways})

      assert {:escalate, {:not_an_edge, :nope}} = MatchKey.bucket(:nope)
    end
  end

  describe "MES-76 F4 — the token is INJECTIVE: one string per decoded value" do
    # The defect this closes was not "a second spelling exists". It was that two
    # DIFFERENT token strings decoded to a BYTE-IDENTICAL map while `render/1`
    # could emit only one of them — so the relation accepted a key its own
    # encoder cannot produce and had no basis for saying which string was the
    # key. `validate_edge/1` caught it on a stored edge (`:derived_field_mismatch`);
    # `guard_state/2` did not, and `guard_state/2` is the path Sprint 7's drift
    # guard travels.
    #
    # Measured at 18df3a6 BEFORE the fix, against these same 175 rows:
    #   decode("oc:server/caching/…/ToolsListCachingHints#")
    #     == decode("oc:server/caching/…/ToolsListCachingHints")   -> true
    #   guard_state(that token, rows) -> {:matched, key}           -> the drift guard's blind spot

    test "no token in the manifest admits a second, '#'-suffixed spelling", %{rows: rows} do
      # The injectivity claim stated over the whole domain, not one example: for
      # every one of the 175, the emitted string decodes and the one other string
      # that could decode to the same value is REFUSED.
      #
      # The refusal reason is not uniform, and enumerating the partition is the
      # point rather than a detail — appending `#` to a row that ALREADY carries
      # a discriminator produces a three-segment split, which was refused before
      # MES-76 too. So the fix moves 172 of 175 from accepted to refused, and the
      # remaining 3 were never the defect. A test asserting one reason for all
      # 175 would be false; asserting "refused, somehow" would hide which 172
      # actually moved.
      refusals =
        for row <- rows do
          token = MatchKey.encode!(row)

          assert {:ok, decoded} = MatchKey.decode(token)
          # the refusal is not collateral damage: the well-formed token is
          # untouched, discriminator and all.
          assert decoded.discriminator == Enum.at(row, 5)

          case MatchKey.decode(token <> "#") do
            {:error, reason} -> reason
            {:ok, _} -> flunk("#{token}# still decodes — the token is not injective")
          end
        end

      assert Enum.frequencies(refusals) == %{
               empty_discriminator: 172,
               multiple_discriminators: 3
             }

      assert length(refusals) == 175
    end

    test "guard_state/2 refuses it against the REAL manifest rows", %{rows: rows} do
      token =
        MatchKey.encode!(Enum.find(rows, fn row -> Enum.at(row, 5) == "" end))

      # state 1 for the emittable spelling ...
      assert {:matched, _key} = MatchKey.guard_state(token, rows)

      # ... and a stated refusal for the one that is unreachable from encode/1.
      # This is the assertion that would have been RED before the fix: it
      # returned {:matched, key}, indistinguishable from the line above.
      assert {:error, {:malformed, :empty_discriminator}} =
               MatchKey.guard_state(token <> "#", rows)
    end

    test "refusing it costs nothing — all 175 still round-trip", %{rows: rows} do
      # The fix is only free if no legitimate token was collateral. Asserted over
      # the full 175 rather than sampled, and as a SET comparison so a silently
      # dropped row cannot pass.
      resolved =
        for row <- rows, into: MapSet.new() do
          token = MatchKey.encode!(row)
          {:ok, back} = MatchKey.resolve(token, rows)
          back
        end

      assert MapSet.size(resolved) == 175
      assert resolved == MapSet.new(rows)
    end

    test "the 3 rows that DO carry a discriminator are unaffected", %{rows: rows} do
      # The refused sentinel is an EXPLICITLY EMPTY discriminator. A real one
      # must still decode, or the fix would have closed the defect by removing
      # the feature. These are the RequestMetaInvalid siblings.
      with_discriminator = Enum.filter(rows, fn row -> Enum.at(row, 5) != "" end)
      assert length(with_discriminator) == 3

      for row <- with_discriminator do
        token = MatchKey.encode!(row)
        assert String.contains?(token, "#")
        assert {:ok, decoded} = MatchKey.decode(token)
        assert decoded.discriminator == Enum.at(row, 5)
        assert {:matched, ^row} = MatchKey.guard_state(token, rows)
      end
    end

    test "the two split sentinels fail differently, and neither is silent" do
      # `:empty_discriminator` and `:multiple_discriminators` are distinct
      # refusals for distinct malformations. Collapsing them would reintroduce
      # the F4 shape one level up: two causes, one answer.
      base = "oc:server/caching/sep-2549-tools-list-caching-hints/ToolsListCachingHints"

      assert {:error, :empty_discriminator} = MatchKey.decode(base <> "#")
      assert {:error, :multiple_discriminators} = MatchKey.decode(base <> "#a#b")
      assert {:error, :multiple_discriminators} = MatchKey.decode(base <> "##")
      assert {:ok, _} = MatchKey.decode(base <> "#a")
    end
  end

  defp valid_edge_attrs(rows) do
    {:ok, key} =
      MatchKey.resolve(
        "oc:server/server-stateless/sep-2575-http-server-method-not-found-404-ping/" <>
          "HttpServerMethodNotFound404ping",
        rows
      )

    %{
      member: %{
        module: "MCP.Transport.StreamableHTTPStatelessTest",
        test: "initialize is gone → -32022; ping/logging.setLevel → -32601"
      },
      claim: "ping → -32601",
      oc_key: key,
      verdicts: %{oc: :red, et: :green},
      axes: [
        %{axis: "jsonrpc_error_code", verdict: :agrees},
        %{axis: "http_status", verdict: :silent}
      ]
    }
  end

  defp name_of("sep-2575-http-server-method-not-found-404-initialize"),
    do: "HttpServerMethodNotFound404initialize"

  defp name_of("sep-2575-http-server-method-not-found-404-ping"),
    do: "HttpServerMethodNotFound404ping"

  defp name_of("sep-2575-http-server-method-not-found-404-logging-setlevel"),
    do: "HttpServerMethodNotFound404loggingsetLevel"
end

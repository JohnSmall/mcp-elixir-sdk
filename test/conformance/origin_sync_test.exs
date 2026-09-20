defmodule MCP.Conformance.OriginSyncTest do
  @moduledoc """
  The decision half of `mix origin.sync`, unit by unit.

  > **No observation that fails to establish the published state may produce a
  > green verdict.**

  `MCP.Conformance.OriginSync.observe/1` is I/O and is exercised end-to-end, on
  real git fixtures, by `conformance/controls/origin_sync_controls.exs`.
  `decide/1` is a pure function of the readings, so every failure mode — including
  the three that need a remote in a state a fixture is clumsy to build — is
  reachable here directly, and cheaply.

  The pairing matters as much as the reds: `in_sync/0` is the green control every
  red case is a single-field mutation of. A decision function that returned
  `ok?: false` unconditionally would satisfy every red assertion below and fail
  only that one.
  """

  use ExUnit.Case, async: true

  alias MCP.Conformance.OriginSync

  doctest MCP.Conformance.OriginSync

  @main String.duplicate("a", 40)
  @tagged String.duplicate("b", 40)
  @tag_object String.duplicate("c", 40)
  @tag_name "2.0.0-dev.33"

  # The green control. Shaped like the real repository measured on 2026-09-20:
  # the tag peels to main~1, not to the tip.
  defp in_sync do
    %{
      repo: "/nowhere",
      remote: "origin",
      version: @tag_name,
      tag: @tag_name,
      local_main: {:ok, @main},
      live: {:ok, %{"refs/heads/main" => @main, "refs/tags/#{@tag_name}" => @tag_object}},
      local_tag: {:ok, %{object: @tag_object, annotated?: true, peels_to: @tagged}},
      ancestry: :ancestor_or_equal,
      distance: "0 (identical)"
    }
  end

  defp status(verdict, id) do
    Enum.find(verdict.conjuncts, &(&1.id == id)).status
  end

  defp statuses(observation) do
    verdict = OriginSync.decide(observation)
    {verdict.ok?, Map.new(verdict.conjuncts, &{&1.id, &1.status})}
  end

  describe "the green control" do
    test "an in-sync observation is green on all five conjuncts" do
      assert {true, all} = statuses(in_sync())

      assert all == %{c1: :green, c2: :green, c3: :green, c4: :green, c5: :green}
    end

    test "every conjunct states the claim it is about" do
      for c <- OriginSync.decide(in_sync()).conjuncts do
        assert is_binary(c.claim) and c.claim != ""
        assert c.lines != []
      end
    end
  end

  describe "C2 — the live main" do
    test "red when origin's main is a different commit" do
      obs = %{in_sync() | live: {:ok, %{"refs/heads/main" => @tagged}}}

      assert {false, %{c2: :red}} = statuses(obs)
    end

    test "red when origin has no refs/heads/main at all" do
      # ls-remote exits 0 and prints nothing for a ref the remote does not have,
      # measured 2026-09-20. Absence must therefore be read off the OUTPUT, and it
      # must be a failure rather than a silent pass.
      obs = %{in_sync() | live: {:ok, %{"refs/tags/#{@tag_name}" => @tag_object}}}

      assert {false, %{c2: :red}} = statuses(obs)
    end

    test "the report names both shas and the distance" do
      obs = %{
        in_sync()
        | live: {:ok, %{"refs/heads/main" => @tagged}},
          distance: "local main is 3 ahead, 0 behind origin"
      }

      lines = Enum.find(OriginSync.decide(obs).conjuncts, &(&1.id == :c2)).lines

      assert Enum.any?(lines, &String.contains?(&1, OriginSync.short(@main)))
      assert Enum.any?(lines, &String.contains?(&1, OriginSync.short(@tagged)))
      assert Enum.any?(lines, &String.contains?(&1, "3 ahead"))
    end
  end

  describe "C3 — the local tag" do
    test "red when the version's tag does not exist locally" do
      obs = %{in_sync() | local_tag: {:error, "unknown revision"}}

      assert {false, %{c3: :red}} = statuses(obs)
    end

    test "red when the tag exists but is lightweight rather than annotated" do
      obs = %{
        in_sync()
        | local_tag: {:ok, %{object: @tagged, annotated?: false, peels_to: @tagged}}
      }

      assert {false, %{c3: :red}} = statuses(obs)
    end

    test "the expected tag name is derived from the version, with no leading v" do
      assert OriginSync.tag_for("2.0.0-dev.33") == "2.0.0-dev.33"
      assert OriginSync.tag_for("2.0.0") == "2.0.0"
    end
  end

  describe "C4 — the tag on origin" do
    test "red when origin does not carry the tag — the S7-47 lapse" do
      # Exactly what a bare `git push origin main` leaves behind: main arrives,
      # the tag does not.
      obs = %{in_sync() | live: {:ok, %{"refs/heads/main" => @main}}}

      assert {false, %{c2: :green, c4: :red}} = statuses(obs)
    end

    test "red when the tag name is on origin as a different object" do
      obs = %{
        in_sync()
        | live: {:ok, %{"refs/heads/main" => @main, "refs/tags/#{@tag_name}" => @main}}
      }

      assert {false, %{c4: :red}} = statuses(obs)
    end
  end

  describe "C5 — where the tag sits" do
    test "green when the tag peels to a commit main contains, tip or not" do
      assert status(OriginSync.decide(in_sync()), :c5) == :green
    end

    test "red when the tag peels to a commit that is not an ancestor of main" do
      obs = %{in_sync() | ancestry: :not_ancestor}

      assert {false, %{c5: :red}} = statuses(obs)
    end

    test "undetermined when ancestry could not be established" do
      obs = %{in_sync() | ancestry: {:error, "bad object"}}

      assert {false, %{c5: :undetermined}} = statuses(obs)
    end
  end

  describe "fail-closed" do
    test "an unreachable origin is red, and what depends on it is undetermined" do
      obs = %{in_sync() | live: {:error, "Could not read from remote repository"}}

      assert {false, all} = statuses(obs)
      assert all.c1 == :red
      assert all.c2 == :undetermined
      assert all.c4 == :undetermined
    end

    test "undetermined is not a pass — a verdict with no red at all is still not ok" do
      # The distinguishing case: nothing is :red, so a decision rule written as
      # "ok unless something is red" would return green over a remote nobody read.
      obs = %{
        in_sync()
        | live: {:error, "timeout"},
          ancestry: {:error, "not attempted"}
      }

      verdict = OriginSync.decide(obs)

      refute verdict.ok?
      refute Enum.any?(verdict.conjuncts, &(&1.status == :red and &1.id in [:c2, :c4]))
      assert Enum.any?(verdict.conjuncts, &(&1.status == :undetermined))
    end

    test "an unreadable local main is undetermined, not green" do
      obs = %{in_sync() | local_main: {:error, "no refs/heads/main"}}

      assert {false, %{c2: :undetermined}} = statuses(obs)
    end

    test "every undetermined conjunct says so in its own lines" do
      obs = %{in_sync() | live: {:error, "timeout"}}

      for c <- OriginSync.decide(obs).conjuncts, c.status == :undetermined do
        assert Enum.any?(c.lines, &String.contains?(&1, "not a pass"))
      end
    end
  end

  describe "parse_ls_remote/1 — decisions come off the output, never the status" do
    test "an empty answer is an empty map, not an error" do
      # `git ls-remote origin refs/tags/does-not-exist` exits 0 and prints nothing.
      assert OriginSync.parse_ls_remote("") == %{}
      assert OriginSync.parse_ls_remote("\n\n") == %{}
    end

    test "reads every tab-separated row and trims" do
      out = "#{@main}\trefs/heads/main\n#{@tag_object}\trefs/tags/#{@tag_name}\n"

      assert OriginSync.parse_ls_remote(out) == %{
               "refs/heads/main" => @main,
               "refs/tags/#{@tag_name}" => @tag_object
             }
    end

    test "a line with no tab is dropped rather than half-read" do
      assert OriginSync.parse_ls_remote("warning: something\n#{@main}\trefs/heads/main\n") ==
               %{"refs/heads/main" => @main}
    end
  end
end

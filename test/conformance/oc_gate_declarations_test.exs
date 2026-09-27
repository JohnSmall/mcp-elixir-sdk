defmodule MCP.Conformance.OcGateDeclarationsTest do
  # Gate 7's declaration reader (MES-160). Every test here is its own gate-7
  # declaration: none of them asserts behaviour an OC check measures.
  use ExUnit.Case, async: true

  alias MCP.Conformance.OcGateDeclarations, as: D

  @base ~S'''
  defmodule FxTest do
    use ExUnit.Case

    @tag oc: :none
    @tag oc_reason: "fixture"
    test "alpha" do
      assert 1 + 1 == 2
    end

    describe "grp" do
      test "beta", %{x: x} do
        assert x == :ok
      end
    end
  end
  '''

  defp parse!(src, file \\ "test/fx_test.exs") do
    {:ok, decls} = D.parse(src, file)
    decls
  end

  defp changes(base, tip) do
    {:ok, changed} = D.diff_sources(base, tip, "test/fx_test.exs")
    Map.new(changed, &{&1.id, &1.change})
  end

  defp causes(base, tip) do
    {:ok, changed} = D.diff_sources(base, tip, "test/fx_test.exs")
    Map.new(changed, &{&1.id, {&1.change, &1.cause}})
  end

  describe "new and changed" do
    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "an identical file has nothing new or changed" do
      assert changes(@base, @base) == %{}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "moving a test across a context statement is a change of that test: position (B3)" do
      moved = ~S'''
      defmodule FxTest do
        use ExUnit.Case

        describe "grp" do
          test "beta", %{x: x} do
            assert x == :ok
          end
        end

        @tag oc: :none
        @tag oc_reason: "fixture"
        test "alpha" do
          assert 1 + 1 == 2
        end
      end
      '''

      # alpha crossed the `describe` statement; beta's block did not move.
      assert causes(@base, moved) == %{"alpha" => {:changed, :position}}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "swapping two tests with no context statement between them is not a change" do
      base = """
      defmodule FxTest do
        use ExUnit.Case
        @x 1
        test "a", do: assert(@x)
        @tag :t
        test "b", do: assert(@x)
      end
      """

      swapped = """
      defmodule FxTest do
        use ExUnit.Case
        @x 1
        @tag :t
        test "b", do: assert(@x)
        test "a", do: assert(@x)
      end
      """

      assert causes(base, swapped) == %{}
    end

    # PO (MES-160 CR 30255): the file context is [@x 1, @x 2] on both sides and
    # no byte of any statement moved, yet alpha now reads @x = 2.
    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a move across a module-attribute redefinition is changed: position (PO)" do
      base = """
      defmodule FxTest do
        use ExUnit.Case
        @x 1
        test "alpha", do: assert(@x > 0)
        @x 2
        test "beta", do: assert(@x > 0)
      end
      """

      moved = """
      defmodule FxTest do
        use ExUnit.Case
        @x 1
        @x 2
        test "alpha", do: assert(@x > 0)
        test "beta", do: assert(@x > 0)
      end
      """

      {:ok, b} = D.parse_file(base, "test/fx_test.exs")
      {:ok, t} = D.parse_file(moved, "test/fx_test.exs")
      assert b.context == t.context
      assert causes(base, moved) == %{"alpha" => {:changed, :position}}

      # Nested: the slot is per block, and the block path carries the enclosing
      # statement's own slot.
      nest = &"defmodule FxTest do\n  use ExUnit.Case\n  describe \"d\" do\n#{&1}\n  end\nend\n"
      nb = nest.("    @x 1\n    test \"a\", do: assert(@x)\n    @x 2")
      nt = nest.("    @x 1\n    @x 2\n    test \"a\", do: assert(@x)")
      assert causes(nb, nt) == %{"d / a" => {:changed, :position}}
    end

    # PP with the slot in the fingerprint: an added or deleted test sits between
    # context statements and still moves no OTHER test.
    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "adding or deleting a test between context statements moves no other slot (PP)" do
      base = """
      defmodule FxTest do
        use ExUnit.Case
        @x 1
        test "a", do: assert(@x)
        @x 2
        test "b", do: assert(@x)
      end
      """

      added = String.replace(base, "  @x 2\n", "  @tag :t\n  test \"new\", do: :ok\n  @x 2\n")
      assert added != base
      assert causes(base, added) == %{"new" => {:new, nil}}

      deleted = String.replace(base, "  test \"a\", do: assert(@x)\n", "")
      assert deleted != base
      assert causes(base, deleted) == %{}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "reindenting and re-wrapping is not a change" do
      reindented = String.replace(@base, "assert 1 + 1 == 2", "assert(\n        1 + 1 ==\n 2)")
      assert reindented != @base
      assert changes(@base, reindented) == %{}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a one-token body edit is a change" do
      edited = String.replace(@base, "1 + 1 == 2", "1 + 2 == 2")
      assert changes(@base, edited) == %{"alpha" => :changed}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a context-pattern edit is a change" do
      edited = String.replace(@base, "%{x: x}", "%{x: x, y: _}")
      assert changes(@base, edited) == %{"grp / beta" => :changed}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a rename is new" do
      renamed = String.replace(@base, ~s(test "alpha"), ~s(test "alpha2"))
      assert changes(@base, renamed) == %{"alpha2" => :new}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a tag edit alone is a change of that test only (PJ)" do
      retagged = String.replace(@base, ~s(oc_reason: "fixture"), ~s(oc_reason: "other"))
      assert causes(@base, retagged) == %{"alpha" => {:changed, :tags}}

      redeclared = String.replace(@base, "@tag oc: :none", ~s(@tag oc: "oc:client/s/C/N"))
      assert causes(@base, redeclared) == %{"alpha" => {:changed, :tags}}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a file absent at the base makes every test new" do
      assert {:ok, changed} = D.diff_sources(nil, @base, "test/fx_test.exs")
      assert Enum.map(changed, & &1.change) == [:new, :new]
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "adding or deleting a test changes no OTHER test: the context excludes test calls" do
      added =
        String.replace(
          @base,
          ~s(  describe "grp" do),
          ~s(  @tag :x\n  test "new", do: :ok\n\n  describe "grp" do)
        )

      assert causes(@base, added) == %{"new" => {:new, nil}}

      alpha =
        ~s(@tag oc: :none\n  @tag oc_reason: "fixture"\n  test "alpha" do\n    assert 1 + 1 == 2\n  end)

      deleted = String.replace(@base, alpha, "")
      assert deleted != @base
      assert causes(@base, deleted) == %{}

      # A deleted test's tags left behind are context: they now pend onto the next statement.
      orphaned = String.replace(@base, ~s(test "alpha" do\n    assert 1 + 1 == 2\n  end), "")
      assert causes(@base, orphaned) == %{"grp / beta" => {:changed, :file}}
    end

    # MES-160 correction round 1 (PB/PC/PD, ruled conservative): anything in the
    # file outside the test calls and their tags makes every test in it changed.
    @file_level [
      {"a module attribute (PB)", "use ExUnit.Case\n", "use ExUnit.Case\n  @value 2\n"},
      {"a defp helper (PC)", "use ExUnit.Case\n", "use ExUnit.Case\n  defp h, do: 1\n"},
      {"setup (PD)", "use ExUnit.Case\n", "use ExUnit.Case\n  setup do\n    :ok\n  end\n"},
      {"describe-level code", ~s(describe "grp" do\n), ~s(describe "grp" do\n    @x 1\n)}
    ]

    for {what, from, to} <- @file_level do
      @tag oc: :none
      @tag oc_reason: "reader unit; no OC counterpart"
      test "an edit to #{what} alone makes every test in the file changed: file" do
        edited = String.replace(@base, unquote(from), unquote(to))
        assert edited != @base

        assert causes(@base, edited) ==
                 %{"alpha" => {:changed, :file}, "grp / beta" => {:changed, :file}}
      end
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a for-generated test gaining an iteration is changed: file (B1, PE and PA shapes)" do
      pe = ~S'''
      defmodule FxTest do
        use ExUnit.Case
        for m <- [:a] do
          test "gen #{m}", do: assert(m)
        end
      end
      '''

      assert causes(pe, String.replace(pe, "[:a]", "[:a, :b]")) ==
               %{~S("gen #{m}") => {:changed, :file}}

      # The real manifest_test.exs shape: the generator reads a module attribute.
      pa = ~S'''
      defmodule FxTest do
        use ExUnit.Case
        @pairs [{1, :one}]
        for {code, name} <- @pairs do
          test "pair #{code}", do: assert({unquote(code), unquote(name)})
        end
      end
      '''

      assert causes(pa, String.replace(pa, "[{1, :one}]", "[{1, :one}, {2, :two}]")) ==
               %{~S("pair #{code}") => {:changed, :file}}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a @tag pending before a for is file context, not a test's tag" do
      src = ~S'''
      defmodule FxTest do
        use ExUnit.Case
        @tag :a
        for i <- [1] do
          test "t#{i}", do: :ok
        end
      end
      '''

      assert causes(src, String.replace(src, "@tag :a", "@tag :b")) ==
               %{~S("t#{i}") => {:changed, :file}}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a repeated identity is numbered, so the second copy is its own declaration" do
      src = ~S'''
      defmodule FxTest do
        use ExUnit.Case
        for i <- [1] do
          test "t#{i}", do: :ok
        end
        for i <- [2] do
          test "t#{i}", do: :ok
        end
      end
      '''

      assert Enum.map(parse!(src), & &1.id) == [~S("t#{i}"), ~S("t#{i}" #2)]
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "unparseable source is an error, not an empty declaration list" do
      assert {:error, {:parse, _}} = D.parse("defmodule X do test \"a\" do", "test/x_test.exs")
    end
  end

  describe "classification" do
    defp classify(tags) do
      src = """
      defmodule FxTest do
        use ExUnit.Case
      #{tags}
        test "subject", do: :ok
      end
      """

      [decl] = parse!(src)
      D.classify(decl)
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "an untagged test is refused as untagged" do
      assert {:refuse, :untagged, _} = classify("")
      assert {:refuse, :untagged, _} = classify("@tag :etcc")
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "oc: :none needs a one-line, non-empty oc_reason" do
      assert {:refuse, :none_without_reason, _} = classify("@tag oc: :none")
      assert {:refuse, :none_without_reason, _} = classify(~s(@tag oc: :none, oc_reason: "  "))
      assert {:refuse, :none_without_reason, _} = classify(~s(@tag oc: :none, oc_reason: "a\\nb"))
      assert {:refuse, :none_without_reason, _} = classify(~s(@tag oc: :none, oc_reason: :why))
      assert {:none, "why not"} = classify(~s(@tag oc: :none\n@tag oc_reason: "why not"))
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a check token, a token list, and the oc:none token (Q2)" do
      t = "oc:client/http-custom-headers/C1/Name"
      assert {:tokens, [^t]} = classify(~s(@tag oc: "#{t}"))
      assert {:tokens, [^t, ^t]} = classify(~s(@tag oc: ["#{t}", "#{t}"]))
      assert {:none, "no-counterpart"} = classify(~s(@tag oc: "oc:none/no-counterpart/CG1-x"))
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "malformed declarations are refused as malformed" do
      assert {:refuse, :malformed, _} = classify(~s(@tag oc: "client/x/y/z"))
      assert {:refuse, :malformed, _} = classify(~s(@tag oc: "oc:client/x/y/z#"))
      assert {:refuse, :malformed, _} = classify(~s(@tag oc: []))
      assert {:refuse, :malformed, _} = classify(~s(@tag oc: ["oc:none/a/b"]))
      assert {:refuse, :malformed, _} = classify(~S(@tag oc: "oc:client/#{s}/C/N"))
      assert {:refuse, :malformed, _} = classify(~s(@tag oc: @token))
      assert {:refuse, :malformed, _} = classify(~s(@tag oc: :other))
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "@moduletag and @describetag oc: are refused as suite-level" do
      assert {:refuse, :suite_level_tag, _} = classify(~s(@moduletag oc: :none))

      assert {:refuse, :suite_level_tag, _} =
               classify(~s(@describetag oc_reason: "x"\n@tag oc: :none, oc_reason: "y"))
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "tags accumulate since the previous test, and the last oc wins" do
      src = ~S'''
      defmodule FxTest do
        use ExUnit.Case
        @tag oc: "oc:client/s/C/N"
        test "first", do: :ok
        test "second", do: :ok
        @tag oc: :none
        @tag :etcc
        @tag oc: "oc:server/s/C/N", oc_reason: "kept"
        test "third", do: :ok
      end
      '''

      assert [first, second, third] = parse!(src)
      assert first.oc == {:literal, "oc:client/s/C/N"}
      assert second.oc == {:absent}
      assert third.oc == {:literal, "oc:server/s/C/N"}
      assert third.oc_reason == {:literal, "kept"}
    end
  end

  describe "agreement with ExUnit's own runtime tags" do
    @fixture ~S'''
    defmodule MCP.Conformance.OcGateDeclarationsTest.Fixture do
      use ExUnit.Case, register: false

      @tag oc: "oc:client/s/C/N"
      test "a", do: :ok

      test "b", do: :ok

      describe "d" do
        @tag oc: :none
        @tag oc_reason: "r"
        test "c", do: :ok

        @tag :other
        @tag oc: ["oc:client/s/C/N", "oc:server/s/C/N"]
        test "e", do: :ok

        @tag oc: "earlier", oc_reason: "kept"
        @tag oc: "later"
        test "h", do: :ok
      end

      @tag oc: "outside"
      for i <- [1, 2] do
        test "f#{i}", do: :ok
      end

      for i <- [1, 2] do
        @tag oc: "inside"
        test "g#{i}", do: :ok
      end
    end
    '''

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "the reader never claims a tag ExUnit does not apply, and agrees on literal names" do
      [{mod, _}] = Code.compile_string(@fixture)
      runtime = Map.new(mod.__ex_unit__().tests, &{Atom.to_string(&1.name), &1.tags})
      decls = parse!(@fixture)

      reader_value = fn
        {:literal, v} -> v
        {:absent} -> nil
      end

      # Literal-named declarations: the reader and ExUnit agree both ways.
      for d <- decls, not String.starts_with?(d.name, "\"") do
        full = Enum.join(["test", d.describe, d.name] |> Enum.reject(&is_nil/1), " ")
        tags = Map.fetch!(runtime, full)
        assert reader_value.(d.oc) == tags[:oc], "oc disagrees on #{full}"
        assert reader_value.(d.oc_reason) == tags[:oc_reason], "oc_reason disagrees on #{full}"
      end

      # Generated tests: a tag inside the block agrees on every iteration ...
      g = Enum.find(decls, &(&1.name == ~S("g#{i}")))
      assert g.oc == {:literal, "inside"}
      assert runtime["test g1"][:oc] == "inside" and runtime["test g2"][:oc] == "inside"

      # ... and a tag before the block is the stated disagreement, in the
      # refusing direction only: ExUnit tags the first iteration, the reader none.
      f = Enum.find(decls, &(&1.name == ~S("f#{i}")))
      assert f.oc == {:absent}
      assert runtime["test f1"][:oc] == "outside"
      refute Map.has_key?(runtime["test f2"], :oc)
    end
  end

  describe "population over git" do
    setup do
      repo = Path.join(System.tmp_dir!(), "oc-gate-decl-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(repo, "test"))
      File.mkdir_p!(Path.join(repo, "lib"))
      on_exit(fn -> File.rm_rf!(repo) end)
      git!(repo, ["init", "-q", "-b", "main"])
      write!(repo, "test/a_test.exs", @base)
      write!(repo, "lib/a.ex", "defmodule A, do: nil\n")

      write!(repo, "test/old_test.exs", ~S'''
      defmodule OldTest do
        use ExUnit.Case
        @tag oc: "oc:client/s/C/N"
        test "tagged earlier", do: :ok
        test "untagged earlier", do: :ok
      end
      ''')

      commit!(repo, "base")
      git!(repo, ["checkout", "-q", "-b", "K-1"])
      %{repo: repo}
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "only the branch's new and changed tests, from git objects", %{repo: repo} do
      write!(repo, "test/a_test.exs", String.replace(@base, "1 + 1", "2 + 0"))

      write!(
        repo,
        "test/b_test.exs",
        "defmodule BTest do\n use ExUnit.Case\n test \"n\", do: :ok\nend\n"
      )

      commit!(repo, "branch")
      # A working-tree edit after the commit is invisible: git objects are read.
      write!(repo, "test/a_test.exs", "garbage (")

      assert {:ok, pop} = D.population(repo, "main", "K-1")

      assert Enum.map(pop.changed, &{&1.file, &1.id, &1.change}) ==
               [{"test/a_test.exs", "alpha", :changed}, {"test/b_test.exs", "n", :new}]

      assert pop.test_changed and not pop.lib_changed
      assert pop.tagged_elsewhere == []
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a lib/ change adds every unchanged oc-tagged test in the tree (Q5)", %{repo: repo} do
      write!(repo, "lib/a.ex", "defmodule A, do: :changed\n")
      commit!(repo, "lib")

      assert {:ok, pop} = D.population(repo, "main", "K-1")
      assert pop.lib_changed and pop.changed == []
      assert Enum.map(pop.tagged_elsewhere, & &1.id) == ["tagged earlier"]
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a conformance/-only change re-measures them too (N2)", %{repo: repo} do
      File.mkdir_p!(Path.join(repo, "conformance"))
      write!(repo, "conformance/adapter.exs", "# adapter edit\n")
      commit!(repo, "adapter")

      assert {:ok, pop} = D.population(repo, "main", "K-1")
      assert pop.conformance_changed and not pop.lib_changed and not pop.test_changed
      assert Enum.map(pop.tagged_elsewhere, & &1.id) == ["tagged earlier"]
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "a deleted test file declares nothing", %{repo: repo} do
      git!(repo, ["rm", "-q", "test/old_test.exs"])
      commit!(repo, "rm")
      assert {:ok, %{changed: [], test_changed: true}} = D.population(repo, "main", "K-1")
    end

    @tag oc: :none
    @tag oc_reason: "reader unit; no OC counterpart"
    test "an unresolvable ref is an error, never an empty diff", %{repo: repo} do
      assert {:error, {:unresolvable_ref, "K-404"}} = D.population(repo, "main", "K-404")
      assert {:error, {:unresolvable_ref, "nope"}} = D.population(repo, "nope", "K-1")
    end
  end

  defp write!(repo, path, body), do: File.write!(Path.join(repo, path), body)

  defp commit!(repo, msg) do
    git!(repo, ["add", "-A"])

    git!(repo, [
      "-c",
      "user.name=t",
      "-c",
      "user.email=t@t",
      "commit",
      "-q",
      "--no-verify",
      "-m",
      msg
    ])
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    out
  end
end

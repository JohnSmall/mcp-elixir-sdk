defmodule MCP.Conformance.OcGateDeclarations do
  @moduledoc """
  Gate 7's **declaration** half (MES-160): which tests a branch added or
  changed, and what each one declares about its official-conformance (OC)
  counterpart.

  It reads **source**, through the AST, never a running suite. Two blobs of
  each `test/**/*_test.exs` file the branch touched are parsed — the one at the
  merge-base and the one at the branch tip — and their test declarations are
  compared.

  ## Identity, "new" and "changed"

  A declaration's identity is `{file, describe, name}`, with the name rendered
  by `Macro.to_string/1` when it is not a literal (a `for`-generated test's
  name is its interpolation, so its identity is the template, not an
  iteration). When one file repeats an identity, an occurrence ordinal is
  appended, `#2` onwards.

    * **new** — the identity is absent at the merge-base. A renamed test, or a
      test in a renamed file, is new.
    * **changed** — the identity is present at both, and one of four things
      differs once every node's metadata is stripped (so line numbers and
      indentation are never a change, and neither is a move that crosses no
      context statement):
        * `:body` — the test call's arguments after the name (the context
          pattern and the body);
        * `:tags` — the `@tag`s that attach to the test, `oc:` and
          `oc_reason:` among them, so a re-declared test is re-verified live
          (MES-160 PJ);
        * `:file` — **anything in the file outside the test calls and their
          tags**: module attributes, `defp` helpers, `setup`/`setup_all`,
          `describe`-level code, and the head of any `for` that generates
          tests. Any such difference makes **every** test in the file changed
          (MES-160 correction round 1, ruled conservative). It over-refuses by
          design, and it is what makes a `for`-generated test visible: a new
          generator element, or a new row in the `@attribute` a generator
          reads, adds a test ExUnit will register while leaving the template
          identity unchanged — the file context is what moved.
        * `:position` — the test's **slot**: the path of enclosing blocks
          and the number of context statements (anything but a test call and
          its tags) that precede it in its own block. A move across a context
          statement — `@x 1; test a; @x 2` to `@x 1; @x 2; test a` — leaves
          the file context equal but changes what the test reads, so it is a
          change (MES-160 correction round 2, B3). Adding or deleting a test
          moves no other test's slot, because only context statements count.

  ## The tag, read with ExUnit's accumulation semantics

  Every `@tag` since the previous test declaration applies to the next one,
  later keys overriding earlier ones — the rule ExUnit itself applies, and a
  gate-5 unit compiles fixture modules with `register: false` to hold the two
  in agreement. The accepted forms:

      @tag oc: "oc:<leg>/<scenario>/<check_id>/<name>[#<discriminator>]"
      @tag oc: ["oc:…", "oc:…"]          # every named check must be SUCCESS
      @tag oc: :none
      @tag oc_reason: "<one line>"       # required with :none
      @tag oc: "oc:none/<slug>/<native-id>"   # a declared none; the slug is the reason

  **One disagreement with ExUnit, in the refusing direction, and stated.** A
  `@tag` pending when a `for` (or any block containing tests) begins is applied
  by ExUnit to the **first** generated test only. The reader applies it to
  none of them, so every generated test reads as untagged and is refused. The
  fix is the one the refusal implies: put the `@tag` inside the block, where
  ExUnit applies it to every iteration.

  `@moduletag oc:` and `@describetag oc:` are recorded and refused: the
  declaration is per test.

  ## What this module does not see

  Doctests (their content lives in `lib/`); changes under `test/support/` (a
  helper change there does not make its callers "changed"); and anything else
  a test file reads from outside itself — a `for` whose enumerable is computed
  by `lib/` or `test/support/` can gain an iteration with no byte of the file
  moving. These are stated residuals of gate 7, ratified on MES-160 (Q3, Q7).
  """

  alias MCP.Conformance.MatchKey

  @typedoc "One test declaration, as read from source."
  @type decl :: %{
          file: String.t(),
          line: pos_integer() | nil,
          describe: String.t() | nil,
          name: String.t(),
          id: String.t(),
          fingerprint: term(),
          tag_fingerprint: term(),
          position: {[{non_neg_integer(), atom()}], non_neg_integer()},
          oc: {:absent} | {:literal, term()} | {:non_literal, String.t()},
          oc_reason: {:absent} | {:literal, term()} | {:non_literal, String.t()},
          suite_level_oc: [pos_integer()]
        }

  @typedoc "A classified declaration."
  @type classified ::
          {:tokens, [String.t()]}
          | {:none, String.t()}
          | {:refuse, atom(), String.t()}

  @tag_attrs [:moduletag, :describetag]

  # --- parsing ---------------------------------------------------------------

  @doc """
  Parse one file's source into its test declarations, in source order.

  Returns `{:error, {:parse, message}}` rather than an empty list for source
  that does not parse: a file the reader cannot read has not been shown to
  declare nothing.
  """
  @spec parse(String.t(), String.t()) :: {:ok, [decl()]} | {:error, term()}
  def parse(source, file) do
    with {:ok, %{decls: decls}} <- parse_file(source, file), do: {:ok, decls}
  end

  @doc """
  As `parse/2`, and also the file's `context/1`: `{:ok, %{decls: [...],
  context: term}}`.
  """
  @spec parse_file(String.t(), String.t()) ::
          {:ok, %{decls: [decl()], context: term()}} | {:error, term()}
  def parse_file(source, file) do
    case Code.string_to_quoted(source, file: file, columns: false) do
      {:ok, ast} ->
        {decls, _pending, suite} = walk(ast, %{describe: nil, path: [], slot: 0}, [], [])

        decls =
          decls
          |> Enum.reverse()
          |> Enum.map(&Map.merge(&1, %{file: file, suite_level_oc: Enum.sort(suite)}))
          |> number_duplicates()

        {:ok, %{decls: decls, context: context(ast)}}

      {:error, {meta, msg, token}} ->
        {:error, {:parse, "#{file}:#{meta[:line]}: #{inspect(msg)} #{inspect(token)}"}}
    end
  end

  # walk/4 returns {decls_reversed, pending_tags, suite_level_lines}. It is a
  # statement walker: a block is walked in order, so @tag accumulates exactly
  # as ExUnit's module-body evaluation accumulates it.
  #
  # `ctx.slot` counts the context statements before `stmt` in its block, by the
  # rule `ctx_stmts/3` keeps them: a test is not one, a @tag that attaches to a
  # test is not one, and every other statement is — together with any @tags it
  # flushed. So a test's slot moves only when a context statement is crossed.
  defp walk({:__block__, _, stmts}, ctx, pending, suite) do
    {acc, pend, s, _slot, _buffered} =
      Enum.reduce(stmts, {[], pending, suite, 0, 0}, fn stmt, {acc, pend, s, slot, buf} ->
        {d, pend2, s2} = walk(stmt, %{ctx | slot: slot}, pend, s)
        {slot2, buf2} = advance_slot(stmt, slot, buf)
        {d ++ acc, pend2, s2, slot2, buf2}
      end)

    {acc, pend, s}
  end

  defp walk({:@, _, [{:tag, _, [arg]}]}, _ctx, pending, suite) do
    {[], pending ++ [arg], suite}
  end

  defp walk({:@, meta, [{attr, _, [arg]}]}, _ctx, pending, suite) when attr in @tag_attrs do
    if names_oc?(arg), do: {[], pending, [meta[:line] | suite]}, else: {[], pending, suite}
  end

  defp walk({:describe, _, [name, [do: body]]}, ctx, _pending, suite) do
    {d, _, s} = walk(body, enter(%{ctx | describe: render(name)}, :do), [], suite)
    {d, [], s}
  end

  defp walk({:test, meta, [name | rest]}, ctx, pending, suite) do
    decl = %{
      line: meta[:line],
      describe: ctx.describe,
      name: render(name),
      fingerprint: strip(rest),
      tag_fingerprint: strip(pending),
      position: {ctx.path, ctx.slot},
      oc: tag_value(pending, :oc),
      oc_reason: tag_value(pending, :oc_reason)
    }

    {[decl], [], suite}
  end

  defp walk({:defmodule, _, [_name, [do: body]]}, ctx, _pending, suite) do
    {d, _, s} = walk(body, enter(%{ctx | describe: nil}, :do), [], suite)
    {d, [], s}
  end

  # Any other call carrying a `do` block (`for`, `if`, `Enum.each` …). Tests
  # inside it are walked with NO inherited tag (see the moduledoc's stated
  # disagreement); if it declared tests, the pending tags are consumed — ExUnit
  # hands them to the first generated test — and otherwise they carry on.
  defp walk({_, _, args}, ctx, pending, suite) when is_list(args) do
    blocks = for arg <- args, is_list(arg), {k, body} <- arg, k in [:do, :else], do: {k, body}

    {d, s} =
      Enum.reduce(blocks, {[], suite}, fn {k, body}, {acc, s} ->
        {d, _, s2} = walk(body, enter(ctx, k), [], s)
        {d ++ acc, s2}
      end)

    if d == [], do: {[], pending, s}, else: {d, [], s}
  end

  defp walk(_other, _ctx, pending, suite), do: {[], pending, suite}

  # Into a block of the statement at `ctx.slot`: that statement is a context
  # statement, so its slot is as stable as any test's.
  defp enter(ctx, key), do: %{ctx | path: ctx.path ++ [{ctx.slot, key}], slot: 0}

  defp advance_slot({:@, _, [{:tag, _, [_]}]}, slot, buf), do: {slot, buf + 1}
  defp advance_slot({:test, _, [_ | _]}, slot, _buf), do: {slot, 0}
  defp advance_slot(_stmt, slot, buf), do: {slot + buf + 1, 0}

  defp names_oc?(arg) when is_list(arg), do: Keyword.keyword?(arg) and has_oc_key?(arg)
  defp names_oc?(_), do: false

  defp has_oc_key?(kw), do: Keyword.has_key?(kw, :oc) or Keyword.has_key?(kw, :oc_reason)

  # The LAST pending @tag carrying `key` wins — ExUnit merges tags in order.
  defp tag_value(pending, key) do
    pending
    |> Enum.flat_map(fn
      kw when is_list(kw) -> if Keyword.keyword?(kw), do: Keyword.get_values(kw, key), else: []
      _ -> []
    end)
    |> List.last()
    |> case do
      nil -> {:absent}
      value -> literal(value)
    end
  end

  defp literal(v) when is_binary(v) or is_atom(v), do: {:literal, v}

  defp literal(list) when is_list(list) do
    if Enum.all?(list, &is_binary/1),
      do: {:literal, list},
      else: {:non_literal, Macro.to_string(list)}
  end

  defp literal(other), do: {:non_literal, Macro.to_string(other)}

  defp render(name) when is_binary(name), do: name
  defp render(name), do: Macro.to_string(name)

  @doc false
  # Every node's metadata dropped, so line and column moves compare equal.
  @spec strip(term()) :: term()
  def strip(ast) do
    Macro.prewalk(ast, fn
      {a, meta, b} when is_list(meta) -> {a, [], b}
      other -> other
    end)
  end

  @doc """
  The file's **context**: its AST with every test call, and the `@tag`s that
  attach to one, removed, and all metadata stripped. Two blobs with equal
  context differ only inside test calls and their tags — any other difference
  makes every test in the file `:changed` (cause `:file`).

  A `@tag` attaches to a test when only `@tag`s stand between it and the test
  in the same block, which is ExUnit's accumulation rule. A `@tag` pending when
  a `for` begins is therefore context: ExUnit hands it to the first generated
  test only, and the reader to none (see the moduledoc).
  """
  @spec context(Macro.t()) :: term()
  def context(ast), do: ast |> ctx_body() |> strip()

  defp ctx_body({:__block__, _, stmts}), do: ctx_stmts(stmts, [], [])
  defp ctx_body(stmt), do: ctx_stmts([stmt], [], [])

  # `tags` buffers the @tags seen since the last other statement, in order;
  # `acc` holds the kept statements, reversed.
  defp ctx_stmts([], tags, acc), do: Enum.reverse(acc, tags)

  defp ctx_stmts([{:@, _, [{:tag, _, [_]}]} = t | rest], tags, acc),
    do: ctx_stmts(rest, tags ++ [t], acc)

  defp ctx_stmts([{:test, _, [_ | _]} | rest], _tags, acc), do: ctx_stmts(rest, [], acc)

  defp ctx_stmts([stmt | rest], tags, acc),
    do: ctx_stmts(rest, [], [ctx_node(stmt) | Enum.reverse(tags, acc)])

  # A call's `do`/`else` bodies are themselves statement lists: tests inside a
  # `describe`, a `for` or a nested module are removed the same way, and the
  # call itself — its name, a `for`'s generators and filters — stays.
  defp ctx_node({f, meta, args}) when is_list(args) do
    {f, meta, Enum.map(args, &ctx_arg/1)}
  end

  defp ctx_node(other), do: other

  defp ctx_arg(kw) when is_list(kw) and kw != [] do
    if Keyword.keyword?(kw) and Enum.any?(kw, fn {k, _} -> k in [:do, :else] end) do
      Enum.map(kw, fn
        {k, body} when k in [:do, :else] -> {k, {:__context_block__, ctx_body(body)}}
        pair -> pair
      end)
    else
      kw
    end
  end

  defp ctx_arg(arg), do: arg

  defp number_duplicates(decls) do
    decls
    |> Enum.map_reduce(%{}, fn d, seen ->
      base = if d.describe, do: "#{d.describe} / #{d.name}", else: d.name
      n = Map.get(seen, base, 0) + 1
      id = if n == 1, do: base, else: "#{base} ##{n}"
      {Map.put(d, :id, id), Map.put(seen, base, n)}
    end)
    |> elem(0)
  end

  # --- new / changed ---------------------------------------------------------

  @doc """
  Compare a file at the base with the same file at the tip, each as returned by
  `parse_file/2` (`base` is `nil` when the file is absent at the base). Returns
  the tip's declarations that are `:new` or `:changed`, each with `:change`
  set and, for `:changed`, `:cause` — `:body`, `:tags`, `:file` or
  `:position` (see the moduledoc; the first that applies is reported).
  """
  @spec changed(map() | nil, map()) :: [map()]
  def changed(nil, %{decls: tip}), do: Enum.map(tip, &Map.merge(&1, %{change: :new, cause: nil}))

  def changed(%{decls: base, context: base_ctx}, %{decls: tip, context: tip_ctx}) do
    at_base = Map.new(base, &{&1.id, &1})
    file_moved? = base_ctx != tip_ctx

    for d <- tip,
        {change, cause} = change(Map.fetch(at_base, d.id), d, file_moved?),
        change != :unchanged,
        do: Map.merge(d, %{change: change, cause: cause})
  end

  defp change(:error, _, _), do: {:new, nil}

  defp change({:ok, b}, d, file_moved?) do
    cond do
      b.fingerprint != d.fingerprint -> {:changed, :body}
      b.tag_fingerprint != d.tag_fingerprint -> {:changed, :tags}
      file_moved? -> {:changed, :file}
      b.position != d.position -> {:changed, :position}
      true -> {:unchanged, nil}
    end
  end

  @doc """
  `changed/2` over two sources: the base's (`nil` when absent) and the tip's.
  """
  @spec diff_sources(String.t() | nil, String.t(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  def diff_sources(base_src, tip_src, file) do
    with {:ok, tip} <- parse_file(tip_src, file),
         {:ok, base} <- parse_file_or_nil(base_src, file) do
      {:ok, changed(base, tip)}
    end
  end

  defp parse_file_or_nil(nil, _file), do: {:ok, nil}
  defp parse_file_or_nil(src, file), do: parse_file(src, file)

  # --- classification --------------------------------------------------------

  @doc """
  What a declaration declares, or why it is refused **before any measurement**.

      {:tokens, ["oc:…"]}         — checks to measure
      {:none, reason}             — a declared non-counterpart
      {:refuse, class, detail}    — untagged | none_without_reason | malformed | suite_level_tag
  """
  @spec classify(decl()) :: classified()
  def classify(%{suite_level_oc: [_ | _] = lines}) do
    {:refuse, :suite_level_tag,
     "@moduletag/@describetag oc: at line(s) #{Enum.join(lines, ", ")} — the declaration is per test"}
  end

  def classify(%{oc: {:absent}}),
    do: {:refuse, :untagged, "no @tag oc: — declare the OC check, or oc: :none with oc_reason"}

  def classify(%{oc: {:non_literal, src}}),
    do: {:refuse, :malformed, "@tag oc: must be a literal; got #{src}"}

  def classify(%{oc: {:literal, :none}, oc_reason: reason}) do
    case reason do
      {:literal, r} when is_binary(r) ->
        if String.trim(r) != "" and not String.contains?(r, "\n"),
          do: {:none, r},
          else: {:refuse, :none_without_reason, "oc_reason must be one non-empty line"}

      _ ->
        {:refuse, :none_without_reason, "oc: :none needs @tag oc_reason: \"<one line>\""}
    end
  end

  def classify(%{oc: {:literal, token}}) when is_binary(token) do
    case MatchKey.decode(token) do
      {:ok, %{kind: :none, reason: slug}} -> {:none, slug}
      {:ok, %{kind: :oc}} -> {:tokens, [token]}
      {:error, reason} -> {:refuse, :malformed, "#{inspect(token)}: #{inspect(reason)}"}
    end
  end

  def classify(%{oc: {:literal, [_ | _] = tokens}}) do
    bad =
      Enum.reject(tokens, fn t -> match?({:ok, %{kind: :oc}}, MatchKey.decode(t)) end)

    if bad == [],
      do: {:tokens, tokens},
      else: {:refuse, :malformed, "a list names only oc: check tokens; refused #{inspect(bad)}"}
  end

  def classify(%{oc: {:literal, other}}),
    do: {:refuse, :malformed, "@tag oc: #{inspect(other)} is not a token, a token list or :none"}

  # --- git -------------------------------------------------------------------

  @doc """
  The gate's declaration population for `tip` against `base`, read from git
  objects in `repo` (never the working tree).

  Returns `{:ok, %{changed: [...], tagged_elsewhere: [...], lib_changed: bool,
  conformance_changed: bool, test_changed: bool, merge_base: sha}}`.
  `tagged_elsewhere` holds every unchanged test in the tip's tree carrying
  `@tag oc:` check tokens, and is filled only when the branch changes `lib/`
  (MES-160 Q5) or `conformance/` — an adapter or runner edit can move a live
  check either way (N2, ruled on correction round 1).

  Fails closed on anything git cannot answer: an unresolvable ref is an error,
  never an empty diff.
  """
  @spec population(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def population(repo, base, tip) do
    with {:ok, base_sha} <- rev_parse(repo, base),
         {:ok, tip_sha} <- rev_parse(repo, tip),
         {:ok, mb} <- git(repo, ["merge-base", base_sha, tip_sha]),
         {:ok, names} <- git(repo, ["diff", "--name-only", "#{mb}...#{tip_sha}"]) do
      names = String.split(names, "\n", trim: true)
      test_files = Enum.filter(names, &test_file?/1)
      lib_changed = Enum.any?(names, &String.starts_with?(&1, "lib/"))
      conformance_changed = Enum.any?(names, &String.starts_with?(&1, "conformance/"))
      remeasure = lib_changed or conformance_changed

      with {:ok, changed} <- changed_in(repo, mb, tip_sha, test_files),
           {:ok, elsewhere} <- tagged_elsewhere(repo, tip_sha, remeasure, changed) do
        {:ok,
         %{
           merge_base: mb,
           tip: tip_sha,
           names: names,
           test_changed: Enum.any?(names, &String.starts_with?(&1, "test/")),
           lib_changed: lib_changed,
           conformance_changed: conformance_changed,
           changed: changed,
           tagged_elsewhere: elsewhere
         }}
      end
    end
  end

  defp test_file?(path),
    do: String.starts_with?(path, "test/") and String.ends_with?(path, "_test.exs")

  defp changed_in(repo, mb, tip, files) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, acc} ->
      with {:ok, tip_src} when is_binary(tip_src) <- show(repo, tip, file),
           {:ok, base_src} <- show(repo, mb, file),
           {:ok, changed} <- diff_sources(base_src, tip_src, file) do
        {:cont, {:ok, acc ++ changed}}
      else
        # Deleted on the branch: nothing at the tip to declare.
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  defp tagged_elsewhere(_repo, _tip, false, _changed), do: {:ok, []}

  defp tagged_elsewhere(repo, tip, true, changed) do
    seen = MapSet.new(changed, &{&1.file, &1.id})

    with {:ok, listing} <- git(repo, ["ls-tree", "-r", "--name-only", tip, "--", "test/"]) do
      listing
      |> String.split("\n", trim: true)
      |> Enum.filter(&test_file?/1)
      |> collect(&tagged_in_file(repo, tip, &1, seen))
    end
  end

  # Concatenate each file's `{:ok, list}`, halting on the first error.
  defp collect(files, fun) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, acc} ->
      case fun.(file) do
        {:ok, list} -> {:cont, {:ok, acc ++ list}}
        e -> {:halt, e}
      end
    end)
  end

  defp tagged_in_file(repo, tip, file, seen) do
    with {:ok, src} <- show(repo, tip, file),
         {:ok, decls} <- parse(src, file) do
      tagged =
        for d <- decls,
            not MapSet.member?(seen, {d.file, d.id}),
            match?({:tokens, _}, classify(d)),
            do: Map.merge(d, %{change: :unchanged, cause: nil})

      {:ok, tagged}
    end
  end

  @doc false
  @spec rev_parse(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def rev_parse(repo, ref) do
    case git(repo, ["rev-parse", "--verify", "--quiet", ref <> "^{commit}"]) do
      {:ok, ""} -> {:error, {:unresolvable_ref, ref}}
      {:ok, sha} -> {:ok, sha}
      {:error, _} -> {:error, {:unresolvable_ref, ref}}
    end
  end

  # `{:ok, nil}` when the path is absent at `rev` — the ONE failure mapped to a
  # value, because "absent at the base" is what makes a file's tests new.
  defp show(repo, rev, path) do
    case git(repo, ["cat-file", "-e", "#{rev}:#{path}"]) do
      {:ok, _} -> git_raw(repo, ["show", "#{rev}:#{path}"])
      {:error, _} -> {:ok, nil}
    end
  end

  defp git(repo, args) do
    with {:ok, out} <- git_raw(repo, args), do: {:ok, String.trim(out)}
  end

  defp git_raw(repo, args) do
    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {:git, args, code, String.trim(out)}}
    end
  rescue
    e -> {:error, {:git, args, Exception.message(e)}}
  end
end

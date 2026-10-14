defmodule MCP.Conformance.UnitLocator do
  @moduledoc """
  Finds an ExUnit `test` in its source file by the test's **runtime name**, not by a
  recorded line (MES-176).

  A line number captured from an ExUnit run goes stale the moment anything above the
  test moves, and nothing re-captures it: MES-161's `@tag oc:` inserts moved
  `initialize is removed` in `test/mcp/server/dispatch_test.exs` from :82 to :106 while
  the ExUnit row artefact still says :82. A reader that trusts such a line either dies
  on a line that is no longer a `test` or, worse, reads ANOTHER test's body and reports
  nothing. The name does not drift that way, so this reader goes by the name.

  The name is the one ExUnit registers: `"test "`, then the enclosing `describe` and a
  space when there is one, then the test's own name. A `for`-generated test whose name
  is interpolated is indexed by its **template**: the literal parts must match exactly
  and each interpolation matches one or more characters.

  `locate/2` refuses rather than guesses: a name no declaration matches is `:none`, a
  name two or more match is `{:ambiguous, lines}`, and the caller decides what that
  costs. The end line is the parser's own (`token_metadata`), not an indentation rule.

  `locate_unit/2` also returns the unit's **body**: its `do` block rendered back to
  source from the AST (MES-176 correction round 1, CR F1). A body cut from whole source
  lines between the declaration and its `end` loses every byte that shares either line —
  all of a `do … end` one-liner, all of a `do:` one-liner, and a call written on the
  declaration or the closing line — and a guard that scans nothing there accepts. The
  rendered block is exactly the unit's executable code, whatever its layout, and nothing
  else: not its name, not its context pattern, and not its comments.

  The block is ALL of it (correction round 2, CR F2). `ExUnit.Case.test/3` runs a block
  that is exactly `[do: block]` as `block`, and any other as `try(contents)` — so an
  `after`, `rescue`, `catch` or `else` clause executes too, and is rendered with the rest,
  as the `try` it becomes. Every other shape is UNSCANNABLE, and `locate_unit/2` says so
  with a reason rather than dropping it: a block key `try` does not take, a block with no
  `do`, a bodiless `test/1` (pending), and a last argument that is not a literal keyword
  block. Each `test` call is indexed whatever its shape, so a unit is never "not found"
  merely because its body could not be read.

  A NAME must establish identity too (correction round 3, CR F3). A test or `describe`
  name that is neither a string literal nor a template with literal text — an attribute,
  a variable, a call, or a pure interpolation such as `"\#{x}"` — says nothing about the
  runtime name, so its matcher is a bare wildcard, and a wildcard that is the only match
  is not proof of identity. Such a test is indexed UNSCANNABLE: its wildcard still
  catches every row it could stand for, and each of those rows is refused, alone or
  alongside a literal match. A template that carries literal text is matched as a
  template (the stated residual: a stale row that still fits a template's literal text
  resolves to that template, and is scanned against the template's body — the body every
  instance of it runs).
  """

  @try_keys [:do, :after, :rescue, :catch, :else]

  @typedoc """
  One indexed `test` call: its name matcher, declaration line, last line (the `end`, or
  otherwise the last line its call reaches) and either its rendered block or the reason
  it cannot be scanned.
  """
  @type entry ::
          {Regex.t(), pos_integer(), pos_integer(),
           {:ok, String.t()} | {:unscannable, String.t()}}

  @doc "Indexes every `test` call in `source`, whatever its shape."
  @spec index(String.t(), String.t()) :: [entry()]
  def index(source, file) do
    source
    |> Code.string_to_quoted!(token_metadata: true, file: file)
    |> walk(nil, [])
    |> Enum.reverse()
  end

  @doc """
  The declaration and `end` lines of the one test whose name matches `name`, or `:none`,
  or `{:ambiguous, declaration_lines}`.
  """
  @spec locate([entry()], String.t()) ::
          {:ok, pos_integer(), pos_integer()}
          | {:unscannable, pos_integer(), String.t()}
          | :none
          | {:ambiguous, [pos_integer()]}
  def locate(index, name) do
    case locate_unit(index, name) do
      {:ok, %{line: line, last: last}} -> {:ok, line, last}
      other -> other
    end
  end

  @doc """
  As `locate/2`, with what guard 21 scans: `{:ok, %{line: _, last: _, body: _}}` with the
  rendered block, or `{:unscannable, line, reason}` for a shape whose body cannot be read.
  """
  @spec locate_unit([entry()], String.t()) ::
          {:ok, %{line: pos_integer(), last: pos_integer(), body: String.t()}}
          | {:unscannable, pos_integer(), String.t()}
          | :none
          | {:ambiguous, [pos_integer()]}
  def locate_unit(index, name) do
    case Enum.filter(index, fn {re, _, _, _} -> Regex.match?(re, name) end) do
      [{_, line, last, {:ok, body}}] -> {:ok, %{line: line, last: last, body: body}}
      [{_, line, _, {:unscannable, why}}] -> {:unscannable, line, why}
      [] -> :none
      many -> {:ambiguous, Enum.map(many, &elem(&1, 1))}
    end
  end

  defp walk({:describe, _, [name, [{_do, body}]]}, _describe, acc), do: walk(body, name, acc)

  defp walk({:test, meta, [name | rest]} = call, describe, acc) do
    last = if meta[:end], do: meta[:end][:line], else: last_line(call)

    scan =
      cond do
        describe != nil and not identity?(describe) -> unnamed("describe", describe)
        not identity?(name) -> unnamed("test", name)
        true -> scan(rest)
      end

    [{matcher(describe, name), meta[:line], last, scan} | acc]
  end

  defp walk({_, _, args}, describe, acc) when is_list(args),
    do: Enum.reduce(args, acc, &walk(&1, describe, &2))

  defp walk({left, right}, describe, acc), do: walk(right, describe, walk(left, describe, acc))

  defp walk(list, describe, acc) when is_list(list),
    do: Enum.reduce(list, acc, &walk(&1, describe, &2))

  defp walk(_other, _describe, acc), do: acc

  # A name establishes identity when it is a string literal, or a template with at least
  # one non-empty literal part. Anything else matches as a bare wildcard.
  defp identity?(name) when is_binary(name), do: true

  defp identity?({:<<>>, _, parts}),
    do: Enum.any?(parts, &(is_binary(&1) and &1 != ""))

  defp identity?(_expression), do: false

  defp unnamed(kind, name) do
    {:unscannable,
     "its #{kind} name #{Macro.to_string(name)} is not a string literal or a template " <>
       "with literal text, so the runtime name cannot be established"}
  end

  # What ExUnit.Case.test/3 executes, rendered: the `do` value alone for `[do: _]`, and
  # the whole `try` for any other block of `try` keys. Anything else is unscannable.
  defp scan([]), do: {:unscannable, "it is a bodiless (pending) test/1 — no body to attribute"}

  defp scan(args) do
    block = List.last(args)

    if is_list(block) and block != [] and Keyword.keyword?(block) do
      keys = Keyword.keys(block)

      cond do
        (bad = Enum.uniq(keys -- @try_keys)) != [] ->
          {:unscannable,
           "its block has the key(s) #{inspect(bad)}, outside the " <>
             "do/after/rescue/catch/else that ExUnit's try(contents) takes"}

        :do not in keys ->
          {:unscannable, "its block has no `do`"}

        keys == [:do] ->
          {:ok, Macro.to_string(block[:do])}

        true ->
          {:ok, Macro.to_string({:try, [], [block]})}
      end
    else
      {:unscannable,
       "its last argument is not a literal keyword block (`do: …` / `do … end`), " <>
         "so its body cannot be read"}
    end
  end

  defp last_line(ast) do
    ast
    |> Macro.prewalk(0, fn
      {_, meta, _} = node, max when is_list(meta) ->
        lines = [meta[:line], get_in(meta, [:closing, :line])]
        {node, Enum.max([max | Enum.reject(lines, &is_nil/1)])}

      node, max ->
        {node, max}
    end)
    |> elem(1)
  end

  defp matcher(describe, name) do
    prefix = if describe, do: fragment(describe) <> " ", else: ""
    Regex.compile!("\\Atest " <> prefix <> fragment(name) <> "\\z", "u")
  end

  defp fragment(literal) when is_binary(literal), do: Regex.escape(literal)

  defp fragment({:<<>>, _, parts}),
    do:
      Enum.map_join(parts, fn part -> if is_binary(part), do: Regex.escape(part), else: ".+?" end)

  defp fragment(_expression), do: ".+?"
end

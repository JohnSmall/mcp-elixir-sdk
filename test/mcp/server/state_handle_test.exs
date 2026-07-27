defmodule MCP.Server.StateHandleTest do
  use ExUnit.Case, async: true

  alias MCP.Server.StateHandle

  setup do
    {:ok, store} = StateHandle.start_link()
    %{store: store}
  end

  test "mint returns an opaque handle that resolves back to the value", %{store: store} do
    handle = StateHandle.mint(store, %{"cursor" => 42})
    assert String.starts_with?(handle, "sh_")
    assert StateHandle.fetch(store, handle) == {:ok, %{"cursor" => 42}}
  end

  test "distinct mints get distinct handles; each resolves to its own value", %{store: store} do
    h1 = StateHandle.mint(store, :a)
    h2 = StateHandle.mint(store, :b)
    assert h1 != h2
    assert StateHandle.fetch(store, h1) == {:ok, :a}
    assert StateHandle.fetch(store, h2) == {:ok, :b}
  end

  test "an unminted or non-binary handle does not resolve", %{store: store} do
    assert StateHandle.fetch(store, "sh_nope") == :error
    assert StateHandle.fetch(store, nil) == :error
  end

  test "delete removes a handle", %{store: store} do
    handle = StateHandle.mint(store, :x)
    assert :ok = StateHandle.delete(store, handle)
    assert StateHandle.fetch(store, handle) == :error
  end
end

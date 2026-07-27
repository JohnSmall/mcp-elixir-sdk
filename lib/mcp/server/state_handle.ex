defmodule MCP.Server.StateHandle do
  @moduledoc """
  Server-minted **state handles** for cross-call state in the stateless core
  (SEP-2567).

  With protocol-level sessions removed, a server that needs to carry state
  across tool calls mints an **opaque handle**, stores the associated state
  server-side, and returns the handle to the client. The model passes the handle
  back as an **ordinary tool argument** on a later call; the handler resolves it
  with `fetch/2`.

  ## NOT for identity

  State handles are **model-controlled input** — the model receives a handle and
  passes it back as a tool argument. They MUST NOT be used to carry caller
  **identity**: identity comes from the authenticated transport pipeline and
  rides `MCP.Server.ToolContext.identity`, never a model-passed value (see the
  identity-threading design spec / MC-4). Binding identity to a state handle
  would reintroduce exactly the spoofing surface the seam exists to prevent.

  This store is a minimal `Agent`; a handle is a random, unguessable token. It is
  deliberately independent of any request context.
  """
  use Agent

  @doc """
  Starts a handle store. Pass `:name` to register it.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, Keyword.take(opts, [:name]))
  end

  @doc """
  Mints a fresh opaque handle for `value`, stores it, and returns the handle.
  """
  @spec mint(Agent.agent(), term()) :: String.t()
  def mint(store, value) do
    handle = "sh_" <> UUID.uuid4()
    Agent.update(store, &Map.put(&1, handle, value))
    handle
  end

  @doc """
  Resolves a handle previously minted by this store.

  Returns `{:ok, value}` or `:error` — a handle the store did not mint (or one
  already consumed) does not resolve.
  """
  @spec fetch(Agent.agent(), String.t()) :: {:ok, term()} | :error
  def fetch(store, handle) when is_binary(handle) do
    Agent.get(store, &Map.fetch(&1, handle))
  end

  def fetch(_store, _handle), do: :error

  @doc """
  Deletes a handle (e.g. a one-shot handle consumed on use).
  """
  @spec delete(Agent.agent(), String.t()) :: :ok
  def delete(store, handle) do
    Agent.update(store, &Map.delete(&1, handle))
  end
end

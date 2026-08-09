defmodule MCP.Server.SubscriptionRegistry do
  @moduledoc false

  @spec name(atom() | pid()) :: {:ok, atom()} | {:error, :invalid_registry}
  def name(registry) when is_atom(registry), do: {:ok, registry}

  def name(registry) when is_pid(registry) do
    case Process.info(registry, :registered_name) do
      {:registered_name, name} when is_atom(name) -> {:ok, name}
      _ -> {:error, :invalid_registry}
    end
  end

  def name(_registry), do: {:error, :invalid_registry}
end

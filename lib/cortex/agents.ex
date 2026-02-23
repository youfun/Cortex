defmodule Cortex.Agents do
  @moduledoc """
  Agents context.

  The core runtime agents live under `Cortex.Agents.*` (e.g. `LLMAgent`).
  This lightweight context exists primarily for test fixtures and future
  persistence needs.
  """

  @doc """
  Creates an agent record.

  Currently returns an in-memory map with a generated `:id` to satisfy
  fixture usage. No persistence is performed.
  """
  def create_agent(attrs) when is_map(attrs) do
    {:ok,
     attrs
     |> Map.new()
     |> Map.put_new(:id, Ecto.UUID.generate())}
  end

  def create_agent(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> create_agent()
  end
end

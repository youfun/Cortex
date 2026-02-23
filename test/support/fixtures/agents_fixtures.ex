defmodule Cortex.AgentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Cortex.Agents` context.
  """

  @doc """
  Generate a agent.
  """
  def agent_fixture(attrs \\ %{}) do
    {:ok, agent} =
      attrs
      |> Enum.into(%{
        capabilities: %{},
        driver: "some driver",
        driver_config: %{},
        mode: "some mode",
        name: "some name"
      })
      |> Cortex.Agents.create_agent()

    agent
  end
end

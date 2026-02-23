defmodule Cortex.WorkspacesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Cortex.Workspaces` context.
  """

  @doc """
  Generate a workspace.
  """
  def workspace_fixture(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    {:ok, workspace} =
      attrs
      |> Enum.into(%{
        config: %{},
        name: "some name #{unique_id}",
        path: "some path #{unique_id}",
        status: "some status"
      })
      |> Cortex.Workspaces.create_workspace()

    workspace
  end
end

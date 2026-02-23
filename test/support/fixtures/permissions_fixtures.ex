defmodule Cortex.PermissionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Cortex.Permissions` context.
  """

  @doc """
  Generate a permission_request.
  """
  def permission_request_fixture(attrs \\ %{}) do
    {:ok, permission_request} =
      attrs
      |> Enum.into(%{
        action_module: "some action_module",
        decision: "some decision",
        params: %{},
        status: "some status"
      })
      |> Cortex.Permissions.create_permission_request()

    permission_request
  end
end

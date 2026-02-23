defmodule Cortex.WorkspacesTest do
  use Cortex.DataCase

  alias Cortex.Workspaces

  describe "workspaces" do
    alias Cortex.Workspaces.Workspace

    import Cortex.WorkspacesFixtures

    @invalid_attrs %{name: nil, status: nil, config: nil, path: nil}

    test "list_workspaces/0 returns all workspaces" do
      workspace = workspace_fixture()
      assert Workspaces.list_workspaces() == [workspace]
    end

    test "get_workspace!/1 returns the workspace with given id" do
      workspace = workspace_fixture()
      assert Workspaces.get_workspace!(workspace.id) == workspace
    end

    test "create_workspace/1 with valid data creates a workspace" do
      valid_attrs = %{name: "some name", status: "some status", config: %{}, path: "some path"}

      assert {:ok, %Workspace{} = workspace} = Workspaces.create_workspace(valid_attrs)
      assert workspace.name == "some name"
      assert workspace.status == "some status"
      assert workspace.config == %{}
      assert workspace.path == "some path"
    end

    test "create_workspace/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Workspaces.create_workspace(@invalid_attrs)
    end

    test "update_workspace/2 with valid data updates the workspace" do
      workspace = workspace_fixture()

      update_attrs = %{
        name: "some updated name",
        status: "some updated status",
        config: %{},
        path: "some updated path"
      }

      assert {:ok, %Workspace{} = workspace} =
               Workspaces.update_workspace(workspace, update_attrs)

      assert workspace.name == "some updated name"
      assert workspace.status == "some updated status"
      assert workspace.config == %{}
      assert workspace.path == "some updated path"
    end

    test "update_workspace/2 with invalid data returns error changeset" do
      workspace = workspace_fixture()
      assert {:error, %Ecto.Changeset{}} = Workspaces.update_workspace(workspace, @invalid_attrs)
      assert workspace == Workspaces.get_workspace!(workspace.id)
    end

    test "delete_workspace/1 deletes the workspace" do
      workspace = workspace_fixture()
      assert {:ok, %Workspace{}} = Workspaces.delete_workspace(workspace)
      assert_raise Ecto.NoResultsError, fn -> Workspaces.get_workspace!(workspace.id) end
    end

    test "change_workspace/1 returns a workspace changeset" do
      workspace = workspace_fixture()
      assert %Ecto.Changeset{} = Workspaces.change_workspace(workspace)
    end
  end
end

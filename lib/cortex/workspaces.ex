defmodule Cortex.Workspaces do
  @moduledoc """
  The Workspaces context.
  """

  import Ecto.Query, warn: false
  alias Cortex.Repo

  alias Cortex.Workspaces.Workspace

  @default_workspace_subdir ".cortex/workspace"

  @doc """
  Returns the list of workspaces.

  ## Examples

      iex> list_workspaces()
      [%Workspace{}, ...]

  """
  def list_workspaces do
    Repo.all(Workspace)
  end

  @doc """
  Returns the workspace root directory.

  Defaults to `~/.cortex/workspace` when not configured.
  """
  def workspace_root do
    case Application.get_env(:cortex, :workspace_root) do
      nil -> default_workspace_root()
      "" -> default_workspace_root()
      path when is_binary(path) -> Path.expand(path)
      _ -> default_workspace_root()
    end
  end

  @doc """
  Ensures a workspace exists for the current root directory and returns it.
  """
  def ensure_default_workspace do
    path = ensure_workspace_root!()

    case Repo.get_by(Workspace, path: path) do
      %Workspace{} = ws ->
        ws

      nil ->
        {:ok, ws} =
          create_workspace(%{
            name: Path.basename(path),
            path: path,
            status: "active",
            last_accessed: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        ws
    end
  end

  @doc """
  Ensures the workspace root directory exists and returns its path.
  """
  def ensure_workspace_root! do
    root = workspace_root()
    File.mkdir_p!(root)
    root
  end

  defp default_workspace_root do
    Path.join(System.user_home!(), @default_workspace_subdir)
  end

  @doc """
  Gets a single workspace.

  Raises `Ecto.NoResultsError` if the Workspace does not exist.

  ## Examples

      iex> get_workspace!(123)
      %Workspace{}

      iex> get_workspace!(456)
      ** (Ecto.NoResultsError)

  """
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  @doc """
  Creates a workspace.

  ## Examples

      iex> create_workspace(%{field: value})
      {:ok, %Workspace{}}

      iex> create_workspace(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_workspace(attrs) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a workspace.

  ## Examples

      iex> update_workspace(workspace, %{field: new_value})
      {:ok, %Workspace{}}

      iex> update_workspace(workspace, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a workspace.

  ## Examples

      iex> delete_workspace(workspace)
      {:ok, %Workspace{}}

      iex> delete_workspace(workspace)
      {:error, %Ecto.Changeset{}}

  """
  def delete_workspace(%Workspace{} = workspace) do
    Repo.delete(workspace)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking workspace changes.

  ## Examples

      iex> change_workspace(workspace)
      %Ecto.Changeset{data: %Workspace{}}

  """
  def change_workspace(%Workspace{} = workspace, attrs \\ %{}) do
    Workspace.changeset(workspace, attrs)
  end
end

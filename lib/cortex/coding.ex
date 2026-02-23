defmodule Cortex.Coding do
  @moduledoc """
  The Coding context.

  This context is currently used by `Cortex.Workspaces.SnapshotManager` to
  retrieve and update `FileChange` records.
  """

  import Ecto.Query, warn: false
  alias Cortex.Repo

  alias Cortex.Coding.FileChange

  @doc """
  Gets a single file change.

  Raises `Ecto.NoResultsError` if the FileChange does not exist.
  """
  def get_file_change!(id), do: Repo.get!(FileChange, id)

  @doc """
  Updates a file change.
  """
  def update_file_change(%FileChange{} = file_change, attrs) when is_map(attrs) do
    file_change
    |> FileChange.changeset(attrs)
    |> Repo.update()
  end
end

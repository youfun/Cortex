defmodule Cortex.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :path, :string
      add :config, :map
      add :status, :string

      timestamps(type: :utc_datetime)
    end
  end
end

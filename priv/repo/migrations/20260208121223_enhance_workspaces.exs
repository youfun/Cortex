defmodule Cortex.Repo.Migrations.EnhanceWorkspaces do
  use Ecto.Migration

  def change do
    alter table(:workspaces) do
      add :last_accessed, :utc_datetime
      add :git_branch, :string
      add :language, :string
      add :file_count, :integer
    end

    create index(:workspaces, [:last_accessed])
    create unique_index(:workspaces, [:path])
  end
end

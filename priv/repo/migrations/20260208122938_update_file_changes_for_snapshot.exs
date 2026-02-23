defmodule Cortex.Repo.Migrations.UpdateFileChangesForSnapshot do
  use Ecto.Migration

  def change do
    alter table(:file_changes) do
      # Remove old content fields
      remove :before_content
      remove :after_content

      # Add hash fields
      add :before_hash, :string
      add :after_hash, :string

      # Add backup path
      add :backup_path, :string
    end
  end
end

defmodule Cortex.Repo.Migrations.CreateFileChanges do
  use Ecto.Migration

  def change do
    create table(:file_changes) do
      add :task_id, references(:coding_tasks, on_delete: :delete_all)
      add :file_path, :string
      add :before_content, :text
      add :after_content, :text
      add :diff, :text
      add :status, :string, default: "pending_approval"

      timestamps(type: :utc_datetime)
    end

    create index(:file_changes, [:task_id])
    create index(:file_changes, [:status])
  end
end

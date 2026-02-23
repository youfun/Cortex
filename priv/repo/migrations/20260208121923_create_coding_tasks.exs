defmodule Cortex.Repo.Migrations.CreateCodingTasks do
  use Ecto.Migration

  def change do
    create table(:coding_tasks) do
      add :task_id, :string, null: false
      add :goal, :text, null: false
      add :status, :string, default: "pending"
      add :authorized_paths, {:array, :string}, default: []
      add :plan, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coding_tasks, [:task_id])
    create index(:coding_tasks, [:status])
  end
end

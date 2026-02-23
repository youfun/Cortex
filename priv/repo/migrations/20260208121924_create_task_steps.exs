defmodule Cortex.Repo.Migrations.CreateTaskSteps do
  use Ecto.Migration

  def change do
    create table(:task_steps) do
      add :task_id, references(:coding_tasks, on_delete: :delete_all)
      add :step_type, :string
      add :input, :map
      add :output, :map
      add :tokens_used, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:task_steps, [:task_id])
    create index(:task_steps, [:step_type])
  end
end

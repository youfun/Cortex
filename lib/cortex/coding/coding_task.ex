defmodule Cortex.Coding.CodingTask do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "coding_tasks" do
    field :task_id, :string
    field :goal, :string
    field :status, :string, default: "pending"
    field :authorized_paths, {:array, :string}, default: []
    field :plan, :map

    has_many :file_changes, Cortex.Coding.FileChange, foreign_key: :task_id
    has_many :task_steps, Cortex.Coding.TaskStep, foreign_key: :task_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(coding_task, attrs) do
    coding_task
    |> cast(attrs, [:task_id, :goal, :status, :authorized_paths, :plan])
    |> validate_required([:task_id, :goal])
  end
end

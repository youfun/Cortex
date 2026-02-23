defmodule Cortex.Coding.TaskStep do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "task_steps" do
    field :step_type, :string
    field :input, :map
    field :output, :map
    field :tokens_used, :integer

    belongs_to :coding_task, Cortex.Coding.CodingTask, foreign_key: :task_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task_step, attrs) do
    task_step
    |> cast(attrs, [:task_id, :step_type, :input, :output, :tokens_used])
    |> validate_required([:task_id, :step_type])
  end
end

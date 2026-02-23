defmodule Cortex.Coding.FileChange do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "file_changes" do
    field :file_path, :string
    field :before_hash, :string
    field :after_hash, :string
    field :diff, :string
    field :status, :string, default: "pending_approval"
    field :backup_path, :string

    belongs_to :coding_task, Cortex.Coding.CodingTask, foreign_key: :task_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(file_change, attrs) do
    file_change
    |> cast(attrs, [:file_path, :before_hash, :after_hash, :diff, :status, :backup_path, :task_id])
    |> validate_required([:file_path, :task_id])
    |> validate_inclusion(:status, [
      "pending_approval",
      "approved",
      "rejected",
      "applied",
      "reverted"
    ])
  end
end

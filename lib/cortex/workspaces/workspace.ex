defmodule Cortex.Workspaces.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workspaces" do
    field :name, :string
    field :path, :string
    field :config, :map
    field :status, :string
    field :last_accessed, :utc_datetime
    field :git_branch, :string
    field :language, :string
    field :file_count, :integer

    has_many :conversations, Cortex.Conversations.Conversation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [
      :name,
      :path,
      :config,
      :status,
      :last_accessed,
      :git_branch,
      :language,
      :file_count
    ])
    |> validate_required([:name, :path, :status])
  end
end

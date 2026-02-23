defmodule Cortex.Conversations.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversations" do
    field :current_plan_id, Ecto.UUID
    field :title, :string
    field :context, :map
    field :status, :string, default: "active"

    # New fields for multi-session support
    field :last_used_at, :utc_datetime
    field :is_pinned, :boolean, default: false
    field :kind, :string, default: "chat"
    field :model_config, :map
    field :meta, :map

    # 双轨历史系统字段
    # LLM 对话上下文
    field :llm_context, {:array, :map}, default: []
    field :workspace_id, :binary_id

    has_many :display_messages, Cortex.Conversations.DisplayMessage

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [
      :current_plan_id,
      :title,
      :context,
      :status,
      :last_used_at,
      :is_pinned,
      :kind,
      :model_config,
      :meta,
      :llm_context
    ])
    |> validate_required([:title, :status])
    |> validate_inclusion(:kind, ~w(chat task plan))
    |> validate_inclusion(:status, ~w(active archived completed))
  end
end

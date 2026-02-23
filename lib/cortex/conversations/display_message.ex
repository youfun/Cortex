defmodule Cortex.Conversations.DisplayMessage do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Cortex.Conversations.Conversation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @content_types ~w(text thinking tool_call tool_result image notification error)

  schema "display_messages" do
    belongs_to :conversation, Conversation

    field :message_type, :string
    field :content, :map
    field :content_type, :string
    field :sequence, :integer, default: 0
    field :status, :string, default: "completed"
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def create_changeset(conversation_id, attrs) do
    %DisplayMessage{}
    |> cast(attrs, [:message_type, :content, :content_type, :sequence, :status, :metadata])
    |> put_change(:conversation_id, conversation_id)
    |> common_validations()
  end

  def changeset(%DisplayMessage{} = message, attrs) do
    message
    |> cast(attrs, [:message_type, :content, :content_type, :sequence, :status, :metadata])
    |> common_validations()
  end

  defp common_validations(changeset) do
    changeset
    |> validate_required([:conversation_id, :message_type, :content, :content_type])
    |> validate_inclusion(:content_type, @content_types)
    |> validate_inclusion(:status, ["pending", "executing", "completed", "failed"])
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> validate_content_structure()
    |> foreign_key_constraint(:conversation_id)
  end

  defp validate_content_structure(changeset) do
    content_type = get_field(changeset, :content_type)
    content = get_field(changeset, :content)

    case {content_type, content} do
      {"text", %{"text" => _}} ->
        changeset

      {"thinking", %{"text" => _}} ->
        changeset

      {"tool_call", %{"call_id" => _, "name" => _, "arguments" => _}} ->
        changeset

      {"tool_result", %{"tool_call_id" => _, "name" => _, "content" => _}} ->
        changeset

      {"image", %{"url" => _}} ->
        changeset

      {"image", %{"data" => _, "mime_type" => _}} ->
        changeset

      {"notification", %{"text" => _}} ->
        changeset

      {"error", %{"text" => _}} ->
        changeset

      {nil, _} ->
        changeset

      _ ->
        add_error(changeset, :content, "invalid structure for content_type #{content_type}")
    end
  end

  def to_text(%DisplayMessage{content_type: "text", content: %{"text" => text}}), do: text
  def to_text(%DisplayMessage{content_type: "thinking", content: %{"text" => text}}), do: text

  def to_text(%DisplayMessage{content_type: "notification", content: %{"text" => text}}),
    do: text

  def to_text(%DisplayMessage{content_type: "error", content: %{"text" => text}}), do: text

  def to_text(%DisplayMessage{content_type: "tool_call", content: %{"name" => name}}),
    do: "Tool: #{name}"

  def to_text(%DisplayMessage{content_type: "tool_result", content: %{"content" => c}}), do: c
  def to_text(_), do: ""
end

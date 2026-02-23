defmodule Cortex.Repo.Migrations.ReplaceMessagesWithDisplayMessages do
  use Ecto.Migration

  def change do
    drop_if_exists table(:messages)

    create table(:display_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :message_type, :string, null: false
      add :content, :map, null: false
      add :content_type, :string, null: false
      add :sequence, :integer, default: 0, null: false
      add :status, :string, default: "completed", null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:display_messages, [:conversation_id])
    create index(:display_messages, [:conversation_id, :inserted_at, :sequence])
    create index(:display_messages, [:content_type])

    create index(:display_messages, [:status],
             where: "status IN ('pending', 'executing')",
             name: :display_messages_active_tools_index
           )

    execute(
      """
      CREATE UNIQUE INDEX unique_tool_call_per_conversation
      ON display_messages(conversation_id, json_extract(content, '$.call_id'))
      WHERE content_type = 'tool_call' AND json_extract(content, '$.call_id') IS NOT NULL
      """,
      """
      DROP INDEX IF EXISTS unique_tool_call_per_conversation
      """
    )
  end
end

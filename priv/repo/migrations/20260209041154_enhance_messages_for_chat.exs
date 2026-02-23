defmodule Cortex.Repo.Migrations.EnhanceMessagesForChat do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :content, :text
      add :payload, :map
      add :meta, :map

      add :model_name, :string
      add :prompt_tokens, :integer
      add :completion_tokens, :integer
      add :total_tokens, :integer
      add :cost, :decimal

      add :deleted_at, :utc_datetime
      add :group_id, :binary_id
      add :version, :integer, default: 1
      add :is_active, :boolean, default: true
    end

    create index(:messages, [:conversation_id, :inserted_at])
    create index(:messages, [:conversation_id, :is_active])
  end
end

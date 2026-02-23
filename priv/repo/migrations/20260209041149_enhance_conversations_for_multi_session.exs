defmodule Cortex.Repo.Migrations.EnhanceConversationsForMultiSession do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :last_used_at, :utc_datetime
      add :is_pinned, :boolean, default: false
      add :kind, :string, default: "chat"
      add :model_config, :map
      add :meta, :map
    end

    create index(:conversations, [:workspace_id, :is_pinned, :last_used_at])
  end
end

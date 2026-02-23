defmodule Cortex.Repo.Migrations.RemoveFullHistoryFromConversations do
  use Ecto.Migration

  def up do
    # Drop index first before removing column
    drop_if_exists(index(:conversations, [:full_history]))

    alter table(:conversations) do
      remove :full_history
    end
  end

  def down do
    alter table(:conversations) do
      add :full_history, :text, default: "[]", null: false
    end

    create index(:conversations, [:full_history])
  end
end

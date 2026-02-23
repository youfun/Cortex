defmodule Cortex.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :current_plan_id, :binary_id
      add :title, :string
      add :context, :map
      add :status, :string
      add :workspace_id, references(:workspaces, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:workspace_id])
  end
end

defmodule Cortex.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sender_id, :uuid
      add :sender_type, :string
      add :role, :string
      add :type, :string
      add :conversation_id, references(:conversations, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:conversation_id])
  end
end

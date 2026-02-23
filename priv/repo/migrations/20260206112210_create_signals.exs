defmodule Cortex.Repo.Migrations.CreateSignals do
  use Ecto.Migration

  def change do
    create table(:signals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string
      add :type, :string
      add :data, :map
      add :occurred_at, :utc_datetime
      add :conversation_id, references(:conversations, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:signals, [:conversation_id])
  end
end

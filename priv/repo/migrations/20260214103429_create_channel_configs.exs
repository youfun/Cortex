defmodule Cortex.Repo.Migrations.CreateChannelConfigs do
  use Ecto.Migration

  def change do
    create table(:channel_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :adapter, :string, null: false
      add :name, :string
      add :config, :map
      add :enabled, :boolean, default: true, null: false
      add :status, :string, default: "active"

      timestamps()
    end

    create index(:channel_configs, [:adapter])
    create unique_index(:channel_configs, [:adapter, :name])
  end
end

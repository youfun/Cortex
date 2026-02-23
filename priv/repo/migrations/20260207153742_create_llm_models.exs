defmodule Cortex.Repo.Migrations.CreateLlmModels do
  use Ecto.Migration

  def change do
    create table(:llm_models, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :display_name, :string
      add :provider_drive, :string, null: false
      add :adapter, :string, null: false
      add :api_key, :text
      add :base_url, :text
      add :source, :string, null: false
      add :status, :string, default: "active"
      add :context_window, :integer
      add :capabilities, :map
      add :pricing, :map
      add :architecture, :map
      add :custom_overrides, :map
      add :enabled, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:llm_models, [:name])
    create index(:llm_models, [:enabled])
    create index(:llm_models, [:source])
    create index(:llm_models, [:adapter])
  end
end

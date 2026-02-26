defmodule Cortex.Repo.Migrations.CreateSearchSettings do
  use Ecto.Migration

  def change do
    create table(:search_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :default_provider, :string, default: "tavily"
      add :brave_api_key, :string
      add :tavily_api_key, :string
      add :enable_llm_title_generation, :boolean, default: false

      timestamps()
    end
  end
end

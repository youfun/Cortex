defmodule Cortex.Config.SearchSettings do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cortex.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "search_settings" do
    field :default_provider, :string, default: "tavily"
    field :brave_api_key, :string
    field :tavily_api_key, :string
    field :enable_llm_title_generation, :boolean, default: false
    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:default_provider, :brave_api_key, :tavily_api_key, :enable_llm_title_generation])
    |> validate_inclusion(:default_provider, ["brave", "tavily"])
  end

  def get_settings do
    case :persistent_term.get({__MODULE__, :cached}, nil) do
      nil -> load_from_db()
      cached -> cached
    end
  end

  def update_settings(attrs) do
    # Always load fresh from DB to avoid stale struct issues
    result =
      case Repo.one(from(s in __MODULE__, limit: 1)) do
        nil -> %__MODULE__{}
        s -> s
      end
      |> changeset(attrs)
      |> Repo.insert_or_update()

    case result do
      {:ok, settings} ->
        :persistent_term.put({__MODULE__, :cached}, settings)

        Cortex.SignalHub.emit("config.search.updated", %{
          provider: "config",
          event: "search",
          action: "updated",
          actor: "system",
          origin: %{channel: "config", client: "search_settings", platform: "server"}
        }, source: "/config/search_settings")

        {:ok, settings}

      error ->
        error
    end
  end

  defp load_from_db do
    settings =
      case Repo.one(from(s in __MODULE__, limit: 1)) do
        nil -> %__MODULE__{}
        s -> s
      end

    :persistent_term.put({__MODULE__, :cached}, settings)
    settings
  end
end

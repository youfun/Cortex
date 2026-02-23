defmodule Cortex.Config.LlmModel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "llm_models" do
    field :name, :string
    field :display_name, :string
    field :provider_drive, :string
    field :adapter, :string
    field :api_key, :string
    field :base_url, :string
    field :source, :string
    field :status, :string, default: "active"
    field :context_window, :integer
    field :capabilities, :map
    field :pricing, :map
    field :architecture, :map
    field :custom_overrides, :map
    field :enabled, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(llm_model, attrs) do
    llm_model
    |> cast(attrs, [
      :name,
      :display_name,
      :provider_drive,
      :adapter,
      :api_key,
      :base_url,
      :source,
      :status,
      :context_window,
      :capabilities,
      :pricing,
      :architecture,
      :custom_overrides,
      :enabled
    ])
    |> validate_required([:name, :provider_drive, :adapter, :source])
    |> validate_inclusion(:source, ~w(seed llmdb custom remote_api))
    |> validate_inclusion(:status, ~w(alpha beta active deprecated))
    |> validate_inclusion(
      :adapter,
      ~w(openai anthropic google gemini google_vertex xai groq mistral deepseek ollama lmstudio cloudflare zenmux openrouter kimi)
    )
    |> unique_constraint(:name)
  end
end

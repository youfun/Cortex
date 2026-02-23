defmodule Cortex.Channels.ChannelConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channel_configs" do
    field :adapter, :string
    field :name, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true
    field :status, :string, default: "active"

    timestamps()
  end

  @doc false
  def changeset(channel_config, attrs) do
    channel_config
    |> cast(attrs, [:adapter, :name, :config, :enabled, :status])
    |> validate_required([:adapter, :name])
    |> unique_constraint([:adapter, :name])
  end
end

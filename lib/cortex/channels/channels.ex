defmodule Cortex.Channels do
  @moduledoc """
  The Channels context for managing channel configurations.
  """
  import Ecto.Query, warn: false
  alias Cortex.Repo
  alias Cortex.Channels.ChannelConfig
  alias Cortex.Utils.SafeAtom

  @doc """
  Returns the list of channel_configs.
  """
  def list_channel_configs do
    Repo.all(ChannelConfig)
  end

  @doc """
  Gets a single channel_config.
  """
  def get_channel_config!(id), do: Repo.get!(ChannelConfig, id)

  @doc """
  Gets a channel_config by adapter (and optionally name).
  """
  def get_channel_config_by_adapter(adapter) do
    Repo.one(from c in ChannelConfig, where: c.adapter == ^adapter, limit: 1)
  rescue
    e in [Exqlite.Error, Ecto.QueryError] ->
      require Logger

      Logger.warning(
        "[Channels] DB query failed for adapter #{adapter}: #{Exception.message(e)}"
      )

      nil
  end

  @doc """
  Creates a channel_config.
  """
  def create_channel_config(attrs \\ %{}) do
    %ChannelConfig{}
    |> ChannelConfig.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a channel_config.
  """
  def update_channel_config(%ChannelConfig{} = channel_config, attrs) do
    channel_config
    |> ChannelConfig.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a channel_config.
  """
  def delete_channel_config(%ChannelConfig{} = channel_config) do
    Repo.delete(channel_config)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking channel_config changes.
  """
  def change_channel_config(%ChannelConfig{} = channel_config, attrs \\ %{}) do
    ChannelConfig.changeset(channel_config, attrs)
  end

  @doc """
  Resolved configuration for an adapter.
  Delegates to ConfigLoader which handles DB > JSON > Env priority.
  """
  def get_config(adapter_name) when is_binary(adapter_name) do
    config_map = Cortex.Channels.ConfigLoader.load(adapter_name)

    # Convert keys to atoms for internal consumption
    Map.new(config_map, fn {k, v} ->
      key =
        cond do
          is_atom(k) ->
            k

          is_binary(k) ->
            case SafeAtom.to_existing(k) do
              {:ok, atom} -> atom
              {:error, :not_found} -> k
            end

          true ->
            k
        end

      {key, v}
    end)
  end
end

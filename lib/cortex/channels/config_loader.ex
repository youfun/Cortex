defmodule Cortex.Channels.ConfigLoader do
  @moduledoc """
  Handles loading channel configurations with a 3-layer priority system:
  1. Database (Highest)
  2. JSON File (Middle)
  3. Environment Variables (Lowest)
  """

  alias Cortex.Channels

  @json_config_paths [
    Path.expand("~/.jido/channels.json"),
    Path.join(File.cwd!(), "config/channels.json")
  ]

  @doc """
  Resolves the final configuration for a given adapter.
  """
  def load(adapter) when is_binary(adapter) do
    env_config = load_from_env(adapter)
    json_config = load_from_json(adapter)
    db_config = load_from_db(adapter)

    env_config
    |> Map.merge(json_config)
    |> Map.merge(db_config)
  end

  @doc """
  Loads configuration from Environment Variables (Application.get_env).
  """
  def load_from_env(adapter) do
    case adapter_to_atom(adapter) do
      nil ->
        %{}

      adapter_atom ->
        Application.get_env(:cortex, adapter_atom, [])
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
    end
  end

  @doc """
  Loads configuration from the JSON file.
  Checks standard locations: `~/.jido/channels.json` and `./config/channels.json`.
  """
  def load_from_json(adapter) do
    case find_json_file() do
      nil ->
        %{}

      path ->
        with {:ok, contents} <- File.read(path),
             {:ok, decoded} <- Jason.decode(contents) do
          Map.get(decoded, adapter, %{})
        else
          _ -> %{}
        end
    end
  end

  defp find_json_file do
    Enum.find(@json_config_paths, &File.exists?/1)
  end

  defp adapter_to_atom(adapter) when is_binary(adapter) do
    case adapter do
      "dingtalk" ->
        :dingtalk

      "feishu" ->
        :feishu

      "wecom" ->
        :wecom

      "telegram" ->
        :telegram

      "discord" ->
        :discord

      other ->
        case Cortex.Utils.SafeAtom.to_existing(other) do
          {:ok, atom} -> atom
          {:error, :not_found} -> nil
        end
    end
  end

  defp adapter_to_atom(_), do: nil

  @doc """
  Loads configuration from the Database.
  Only returns config if the channel is enabled.
  """
  def load_from_db(adapter) do
    case Channels.get_channel_config_by_adapter(adapter) do
      %{enabled: true, config: config} when is_map(config) ->
        config

      _ ->
        %{}
    end
  end
end

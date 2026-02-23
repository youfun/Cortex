defmodule Cortex.Channels.Discord.Adapter do
  @moduledoc """
  Adapter for Discord integration.
  """
  @behaviour Cortex.Channel.Adapter

  @impl true
  def channel, do: "discord"

  @impl true
  def enabled? do
    conf = config()
    # Check if enabled in DB/Env and has required bot token
    conf[:bot_token] && conf[:bot_token] != ""
  end

  @impl true
  def config do
    Cortex.Channels.get_config("discord")
  end

  @impl true
  def child_specs do
    if enabled?() do
      # TODO: Add Discord Supervisor/Gateway
      []
    else
      []
    end
  end
end

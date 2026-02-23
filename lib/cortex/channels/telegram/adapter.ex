defmodule Cortex.Channels.Telegram.Adapter do
  @moduledoc """
  Telegram channel adapter metadata and child specs.
  """
  @behaviour Cortex.Channel.Adapter

  @impl true
  def channel, do: "telegram"

  @impl true
  def enabled? do
    token = Application.get_env(:cortex, :telegram, [])[:bot_token]
    is_binary(token) and token != ""
  end

  @impl true
  def child_specs do
    [
      Cortex.Channels.Telegram.Poller,
      Cortex.Channels.Telegram.Dispatcher,
      Cortex.Channels.Telegram.CommandHandler
    ]
  end

  @impl true
  def config do
    Application.get_env(:cortex, :telegram, [])
  end
end

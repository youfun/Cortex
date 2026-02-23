defmodule Cortex.Channels.WeCom.Adapter do
  @moduledoc """
  Adapter for WeCom (Enterprise WeChat) integration.
  """
  @behaviour Cortex.Channel.Adapter

  @impl true
  def channel, do: "wecom"

  @impl true
  def enabled? do
    conf = config()
    # Check if enabled in DB/Env and has required callback credentials
    # For receiving messages (callback), Token and AESKey are minimum
    conf[:token] && conf[:encoding_aes_key]
  end

  @impl true
  def config do
    Cortex.Channels.get_config("wecom")
  end

  @impl true
  def child_specs do
    if enabled?() do
      # TODO: Add WeCom Supervisor/Receiver/Dispatcher
      []
    else
      []
    end
  end
end

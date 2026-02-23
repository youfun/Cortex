defmodule Cortex.Channels.Feishu.Adapter do
  @moduledoc """
  Feishu channel adapter metadata and child specs.
  """
  @behaviour Cortex.Channel.Adapter

  @impl true
  def channel, do: "feishu"

  @impl true
  def enabled? do
    cfg = Application.get_env(:cortex, :feishu, [])
    app_id = cfg[:app_id]
    app_secret = cfg[:app_secret]
    present?(app_id) and present?(app_secret)
  end

  @impl true
  def child_specs do
    [
      Cortex.Channels.Feishu.Receiver,
      Cortex.Channels.Feishu.Dispatcher
    ]
  end

  @impl true
  def config do
    Application.get_env(:cortex, :feishu, [])
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(value), do: not is_nil(value)
end

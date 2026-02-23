defmodule Cortex.Channels.Dingtalk.Adapter do
  @moduledoc """
  Adapter for DingTalk integration.
  """
  alias Cortex.Channels.Dingtalk.Supervisor, as: DingtalkSupervisor

  @behaviour Cortex.Channel.Adapter

  @impl true
  def channel, do: "dingtalk"

  @impl true
  def enabled? do
    conf = config()
    # Check if enabled in DB/Env and has required credentials
    conf[:client_id] && conf[:client_secret]
  end

  @impl true
  def config do
    Cortex.Channels.get_config("dingtalk")
  end

  @impl true
  def child_specs do
    if enabled?() do
      [DingtalkSupervisor]
    else
      []
    end
  end
end

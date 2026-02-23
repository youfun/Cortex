defmodule Cortex.Channels.Dingtalk.Supervisor do
  @moduledoc """
  Supervises DingTalk components (Client, Receiver, Dispatcher).
  """
  use Supervisor

  alias Cortex.Channels.Dingtalk.Client
  alias Cortex.Channels.Dingtalk.Receiver
  alias Cortex.Channels.Dingtalk.Dispatcher

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Client, []},
      {Receiver, []},
      {Dispatcher, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

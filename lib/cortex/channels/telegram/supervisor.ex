defmodule Cortex.Channels.Telegram.Supervisor do
  @moduledoc """
  Telegram 通道管理树。
  """
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # 只有当配置了 Token 时才启动子进程
    token = Application.get_env(:cortex, :telegram, [])[:bot_token]

    children =
      if token && token != "" do
        [
          Cortex.Channels.Telegram.Poller,
          Cortex.Channels.Telegram.Dispatcher,
          Cortex.Channels.Telegram.CommandHandler
        ]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end

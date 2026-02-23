defmodule CortexWeb.Hooks.SignalSubscriber do
  @moduledoc """
  LiveView lifecycle hook, 自动订阅信号总线。

  在 LiveView mount 时订阅相关信号，
  unmount 时自动清理订阅。
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      # 直接订阅 SignalHub（移除 PubSub 中转）
      {:ok, _sub} = Cortex.SignalHub.subscribe("**", target: self())
    end

    {:cont, socket}
  end
end

defmodule Cortex.Channels.Telegram.EchoBridge do
  @moduledoc """
  一个简单的回声桥接器，用于验证 Telegram 通道的信号链路。
  它监听收到的消息，并原样（加前缀）发回。
  """
  use GenServer
  require Logger
  alias Cortex.SignalHub

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # 订阅 Telegram 接收到的文本消息
    SignalHub.subscribe("telegram.message.text")
    Logger.info("[Telegram.EchoBridge] Started and subscribed to telegram.message.text")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %{type: "telegram.message.text", data: data, source: source}}, state) do
    payload = signal_payload(data)

    Logger.debug(
      "[Telegram.EchoBridge] Processing message from #{source}: #{payload[:text] || payload["text"]}"
    )

    # 构造回复信号
    reply_data = %{
      chat_id: payload[:chat_id] || payload["chat_id"],
      text: "🤖 Cortex 收到您的消息：

#{payload[:text] || payload["text"]}",
      parse_mode: "Markdown"
    }

    # 发射发送指令信号
    SignalHub.emit(
      "jido.telegram.cmd.send_message",
      %{
        provider: "telegram",
        event: "command",
        action: "send_message",
        actor: "echo_bridge",
        origin: %{channel: "telegram", client: "echo_bridge", platform: "server"}
      }
      |> Map.merge(reply_data),
      source: "/telegram/echo_bridge"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp signal_payload(data) when is_map(data) do
    payload = Map.get(data, :payload) || Map.get(data, "payload")

    if is_map(payload) and map_size(payload) > 0 do
      payload
    else
      data
    end
  end
end

defmodule Cortex.Channels.Telegram.EchoBridgeTest do
  use ExUnit.Case
  alias Cortex.Channels.Telegram.EchoBridge
  alias Cortex.SignalHub

  # 确保 Application 已启动 (包括 SignalHub)
  setup do
    # 允许 SignalHub 广播到测试进程
    :ok
  end

  test "receives telegram text message and emits send command" do
    # 1. 订阅我们期望 EchoBridge 发出的信号
    SignalHub.subscribe("jido.telegram.cmd.send_message")

    # 2. 启动 EchoBridge (它会自动订阅 telegram.message.text)
    start_supervised!(EchoBridge)

    # 3. 模拟 Poller 发出的入站信号
    {:ok, _} =
      SignalHub.emit(
        "telegram.message.text",
        %{
          provider: "telegram",
          event: "message",
          action: "receive",
          actor: "user",
          origin: %{channel: "telegram", client: "bot", platform: "server"},
          chat_id: 12345,
          text: "Hello Jido",
          message_id: 999,
          from: %{"username" => "tester"}
        },
        source: "/telegram/test_bot"
      )

    # 4. 断言收到回复信号
    assert_receive {:signal,
                    %Jido.Signal{
                      type: "jido.telegram.cmd.send_message",
                      data: data
                    }},
                   2000

    assert data.payload.chat_id == 12345
    assert data.payload.text =~ "Hello Jido"
  end
end

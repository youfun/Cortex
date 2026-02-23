defmodule Cortex.History.SignalRecorderTest do
  use Cortex.ProcessCase, async: false

  alias Cortex.History.SignalRecorder
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  setup do
    # Get the actual history file path
    workspace_root = Workspaces.workspace_root()
    history_file = Path.join(workspace_root, "history.jsonl")

    # 确保测试前文件为空或删除
    File.rm(history_file)

    # 订阅信号 - 在启动 SignalRecorder 之前订阅
    SignalHub.subscribe("test.history")

    # 如果已经在运行，先停止
    case Process.whereis(Cortex.History.SignalRecorder) do
      nil ->
        :ok

      pid ->
        Process.exit(pid, :kill)
        # 等待退出
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          1000 -> :ok
        end
    end

    # 手动启动一个新的，用于测试
    {:ok, pid} = Cortex.History.SignalRecorder.start_link()

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    {:ok, history_file: history_file}
  end

  test "records signals to file after flush", %{history_file: history_file} do
    # 发射信号
    {:ok, signal} =
      SignalHub.emit("test.history", %{
        provider: "test",
        event: "history",
        action: "record",
        actor: "tester",
        origin: %{channel: "test", client: "test", platform: "server"},
        foo: "bar"
      })

    IO.puts("Emitted signal: #{signal.id} type: #{signal.type}")

    # 验证测试进程收到了信号
    assert_receive {:signal, %Jido.Signal{type: "test.history"}}, 1000

    # 等待一会确保信号被接收
    Process.sleep(500)

    # 手动触发刷新（或者等待定时器，但测试中手动触发更好）
    send(Cortex.History.SignalRecorder, :flush)

    # 等待刷新完成
    Process.sleep(100)

    # 检查文件
    assert File.exists?(history_file)
    content = File.read!(history_file)
    assert content != ""

    # 验证内容
    assert String.contains?(content, signal.id)
    assert String.contains?(content, "test.history")
    assert String.contains?(content, "bar")

    # 验证是否为有效 JSON
    decoded = Jason.decode!(String.trim(content))
    assert decoded["id"] == signal.id
    assert decoded["type"] == "test.history"
    assert decoded["data"]["payload"]["foo"] == "bar"
  end
end

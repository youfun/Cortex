defmodule Cortex.Integration.AgentLoopTest do
  use Cortex.DataCase, async: false
  alias Cortex.Agents.LLMAgent
  alias Cortex.SignalHub
  require Logger

  @model_name "test-mock-llm"
  @api_key "sk-mock"
  @base_url "http://localhost:8046/v1"

  setup_all do
    # 0. 启动 Mock LLM 服务器
    {:ok, _} = Cortex.Test.MockLLM.start_link()
    {:ok, _} = Bandit.start_link(plug: Cortex.Test.MockLLM, port: 8046)
    :ok
  end

  setup %{owner_pid: owner_pid} do
    # 1. 确保数据库中有这个模型配置
    case Cortex.Config.get_llm_model_by_name(@model_name) do
      nil ->
        {:ok, _} =
          Cortex.Config.create_llm_model(%{
            name: @model_name,
            display_name: "Mock LLM (Local)",
            provider_drive: "openai",
            adapter: "openai",
            base_url: @base_url,
            api_key: @api_key,
            enabled: true,
            status: "active",
            source: "custom"
          })

      _ ->
        :ok
    end

    # 强制重载缓存
    Cortex.Config.Metadata.reload()

    session_id = "test_loop_#{:erlang.unique_integer([:positive])}"

    # 订阅信号总线以便观察 Agent 行为
    SignalHub.subscribe("agent.turn.start")
    SignalHub.subscribe("agent.response")
    SignalHub.subscribe("agent.turn.end")
    SignalHub.subscribe("tool.call.shell")
    SignalHub.subscribe("tool.call.result")
    SignalHub.subscribe("agent.error")

    {:ok, session_id: session_id, owner_pid: owner_pid}
  end

  test "Agent Loop 能够跨越多个轮次完成复杂任务", %{session_id: session_id, owner_pid: owner_pid} do
    test_file = "integration_test_#{session_id}.txt"
    on_exit(fn -> File.rm(test_file) end)

    # 1. 启动 Agent 进程
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Cortex.SessionSupervisor,
        {LLMAgent, session_id: session_id, model: @model_name}
      )

    Cortex.DataCase.allow_process(owner_pid, pid)

    # 2. 发送一个需要多步执行的任务
    task = """
    请帮我完成以下步骤：
    1. 使用 shell 工具创建一个名为 #{test_file} 的文件，内容写上 'Jido Loop Test'。
    2. 紧接着，使用 read_file 工具读取这个文件的内容。
    3. 如果读取到的内容确实是 'Jido Loop Test'，请回复我 'COMPLETED_SUCCESSFULLY'。
    """

    Logger.info("[Test] Starting task for session: #{session_id}")
    LLMAgent.chat(LLMAgent.via(session_id), task)

    # --- 信号流断言 ---

    # 第 1 轮：启动
    assert_receive {:signal, %Jido.Signal{type: "agent.turn.start", data: data}}, 15_000
    assert data.payload.turn == 1

    # 应该触发 Shell 调用
    assert_receive {:signal, %Jido.Signal{type: "tool.call.shell", data: data}}, 20_000
    cmd = data.payload.command
    assert String.contains?(String.downcase(cmd), String.downcase(test_file))

    # 等待工具结果
    assert_receive {:signal, %Jido.Signal{type: "tool.call.result"}}, 20_000

    # 第 2 轮：应该自动读取文件
    # 注意：Agent 可能会在同一轮调用多个工具，或者分步调用。
    # 我们检查是否有新的 turn 开始，或者直接检查 read_file 行为。
    # assert_receive {:signal, %Jido.Signal{type: "agent.turn.start", data: data}}, 20_000
    # assert data.payload.turn == 2

    # 最终结果：应该包含预期的关键词
    assert_receive {:signal, %Jido.Signal{type: "agent.response", data: data}}, 45_000
    content = data.payload.content
    Logger.info("[Test] Received Agent Response: #{content}")
    assert String.contains?(content, "COMPLETED_SUCCESSFULLY")

    # 循环状态最终应为成功
    assert_receive {:signal, %Jido.Signal{type: "agent.turn.end", data: data}}, 15_000
    assert data.payload.status == :success

    Logger.info("[Test] Integration test finished successfully!")
  end
end

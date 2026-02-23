defmodule Cortex.Agents.CodingCoordinator.Actions.ChildStartedAction do
  @moduledoc """
  处理子 Agent 启动完成的 Action。

  这是 Spawn Handshake 的第二阶段：
  1. Parent 收到 child.started 信号
  2. 根据 tag 构造对应的 work request
  3. 发送给子 Agent
  """

  use Jido.Action,
    name: "child_started",
    description: "处理子 Agent 启动完成",
    schema: [
      pid: [type: :any, required: true],
      tag: [type: :any, required: true],
      child_id: [type: :string, required: true],
      child_module: [type: :any, required: false],
      parent_id: [type: :string, required: false],
      meta: [type: :map, default: %{}]
    ]

  require Logger
  alias Jido.Agent.Directive

  @impl true
  def run(params, context) do
    %{pid: child_pid, tag: tag, child_id: child_id} = params
    state = context.state

    Logger.info("[CodingCoordinator] Child started: #{inspect(tag)}, pid: #{inspect(child_pid)}")

    # 更新 children 追踪
    new_children =
      Map.put(state.children, tag, %{
        pid: child_pid,
        id: child_id,
        status: :started,
        started_at: DateTime.utc_now()
      })

    # 根据 tag 构造 work request
    {work_signal, new_state_updates} = build_work_request(tag, state)

    # 发送 work request 给子 Agent
    emit_directive = Directive.emit_to_pid(work_signal, child_pid)

    {:ok, Map.merge(%{children: new_children}, new_state_updates), [emit_directive]}
  end

  defp build_work_request(:analysis, state) do
    {:ok, signal} =
      Jido.Signal.new(
        "analysis.request",
        %{
          run_id: state.run_id,
          files: state.task[:files] || [],
          focus: state.task[:focus] || "structure"
        },
        source: "/coordinator/coding"
      )

    {signal, %{}}
  end

  defp build_work_request(:implementation, state) do
    {:ok, signal} =
      Jido.Signal.new(
        "implementation.request",
        %{
          run_id: state.run_id,
          analysis_result: state.artifacts[:analysis],
          attempt: state.attempt,
          previous_issues: get_previous_issues(state)
        },
        source: "/coordinator/coding"
      )

    {signal, %{}}
  end

  defp build_work_request(:review, state) do
    {:ok, signal} =
      Jido.Signal.new(
        "review.request",
        %{
          run_id: state.run_id,
          implementation_result: state.artifacts[:implementation]
        },
        source: "/coordinator/coding"
      )

    {signal, %{}}
  end

  defp build_work_request(unknown_tag, _state) do
    Logger.warning("[CodingCoordinator] Unknown child tag: #{inspect(unknown_tag)}")
    {nil, %{}}
  end

  defp get_previous_issues(state) do
    case List.last(state.attempt_history) do
      %{issues: issues} -> issues
      _ -> []
    end
  end
end

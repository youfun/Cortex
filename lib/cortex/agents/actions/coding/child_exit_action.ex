defmodule Cortex.Agents.CodingCoordinator.Actions.ChildExitAction do
  @moduledoc """
  处理子 Agent 崩溃的 Action。

  当子 Agent 异常退出时，记录错误并决定如何处理。
  """

  use Jido.Action,
    name: "child_exit",
    description: "处理子 Agent 崩溃",
    schema: [
      pid: [type: :any, required: true],
      tag: [type: :any, required: true],
      reason: [type: :any, required: true]
    ]

  require Logger

  @impl true
  def run(params, context) do
    %{pid: child_pid, tag: tag, reason: reason} = params
    state = context.state

    Logger.error(
      "[CodingCoordinator] Child agent crashed: #{inspect(tag)}, pid: #{inspect(child_pid)}, reason: #{inspect(reason)}"
    )

    # 更新 children 状态
    new_children =
      Map.update(state.children, tag, %{}, fn child_info ->
        Map.merge(child_info, %{
          status: :crashed,
          crashed_at: DateTime.utc_now(),
          reason: reason
        })
      end)

    # 记录错误
    error_entry = %{
      stage: tag,
      type: :child_crash,
      reason: reason,
      timestamp: DateTime.utc_now()
    }

    # 根据当前阶段决定是否可以恢复
    # 简化版本：直接标记为失败
    # 生产版本可以实现更复杂的恢复策略

    {:ok,
     %{
       children: new_children,
       errors: append_one(state.errors, error_entry),
       phase: :failed,
       status: :child_crashed
     }, []}
  end

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end
end

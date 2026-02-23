defmodule Cortex.Agents.CodingCoordinator.Actions.ImplementationResultAction do
  @moduledoc """
  处理实现结果的 Action。

  收到 ImplementationAgent 的结果后：
  1. 保存实现结果到 artifacts
  2. 进入 reviewing 阶段
  3. Spawn ReviewAgent
  """

  use Jido.Action,
    name: "implementation_result",
    description: "处理实现结果",
    schema: [
      run_id: [type: :string, required: true],
      result: [type: :map, required: true],
      attempt: [type: :integer, required: true],
      status: [type: :atom, required: true]
    ]

  require Logger
  alias Jido.Agent.Directive
  alias Cortex.Agents.Workers.ReviewAgent

  @impl true
  def run(params, context) do
    %{run_id: run_id, result: result, attempt: attempt, status: status} = params
    state = context.state

    Logger.info(
      "[CodingCoordinator] Received implementation result for run_id: #{run_id}, attempt: #{attempt}"
    )

    if status == :success do
      # 保存实现结果
      new_artifacts = Map.put(state.artifacts, :implementation, result)

      # Spawn ReviewAgent
      spawn_directive =
        Directive.spawn_agent(
          ReviewAgent,
          :review,
          opts: %{
            run_id: run_id,
            task: state.task,
            implementation_result: result
          }
        )

      {:ok,
       %{
         phase: :reviewing,
         artifacts: new_artifacts
       }, [spawn_directive]}
    else
      # 实现失败
      Logger.error("[CodingCoordinator] Implementation failed for run_id: #{run_id}")

      {:ok,
       %{
         phase: :failed,
         errors:
           append_one(state.errors, %{
             stage: :implementation,
             attempt: attempt,
             reason: "Implementation failed"
           })
       }, []}
    end
  end

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end
end

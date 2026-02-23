defmodule Cortex.Agents.CodingCoordinator.Actions.AnalysisResultAction do
  @moduledoc """
  处理分析结果的 Action。

  收到 AnalysisAgent 的结果后：
  1. 保存分析结果到 artifacts
  2. 进入 implementing 阶段
  3. Spawn ImplementationAgent
  """

  use Jido.Action,
    name: "analysis_result",
    description: "处理分析结果",
    schema: [
      run_id: [type: :string, required: true],
      result: [type: :map, required: true],
      status: [type: :atom, required: true]
    ]

  require Logger
  alias Jido.Agent.Directive
  alias Cortex.Agents.Workers.ImplementationAgent

  @impl true
  def run(params, context) do
    %{run_id: run_id, result: result, status: status} = params
    state = context.state

    Logger.info("[CodingCoordinator] Received analysis result for run_id: #{run_id}")

    if status == :success do
      # 保存分析结果
      new_artifacts = Map.put(state.artifacts, :analysis, result)

      # Spawn ImplementationAgent
      spawn_directive =
        Directive.spawn_agent(
          ImplementationAgent,
          :implementation,
          opts: %{
            run_id: run_id,
            task: state.task,
            analysis_result: result
          }
        )

      {:ok,
       %{
         phase: :implementing,
         artifacts: new_artifacts
       }, [spawn_directive]}
    else
      # 分析失败
      Logger.error("[CodingCoordinator] Analysis failed for run_id: #{run_id}")

      {:ok,
       %{
         phase: :failed,
         errors: append_one(state.errors, %{stage: :analysis, reason: "Analysis failed"})
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

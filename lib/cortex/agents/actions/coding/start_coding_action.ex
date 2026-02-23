defmodule Cortex.Agents.CodingCoordinator.Actions.StartCodingAction do
  @moduledoc """
  启动编码任务的 Action。

  接收任务描述，生成 run_id，spawn AnalysisAgent 开始分析阶段。
  """

  use Jido.Action,
    name: "start_coding",
    description: "启动编码任务",
    schema: [
      task_description: [type: :string, required: true],
      files: [type: {:list, :string}, default: []],
      focus: [type: :string, default: "full"]
    ]

  require Logger
  alias Jido.Agent.Directive
  alias Cortex.Agents.Workers.AnalysisAgent

  @impl true
  def run(params, context) do
    %{task_description: desc, files: files, focus: focus} = params
    _state = context.state

    # 生成唯一 run_id
    run_id = generate_run_id()

    Logger.info("[CodingCoordinator] Starting coding task: #{run_id}")
    Logger.info("[CodingCoordinator] Task: #{desc}")

    # Spawn AnalysisAgent
    spawn_directive =
      Directive.spawn_agent(
        AnalysisAgent,
        # tag
        :analysis,
        opts: %{
          run_id: run_id,
          task: %{description: desc, files: files, focus: focus}
        }
      )

    # 设置全局超时（10分钟）
    timeout_directive = Directive.schedule(:timer.minutes(10), :task_timeout)

    {:ok,
     %{
       run_id: run_id,
       phase: :analyzing,
       task: %{description: desc, files: files, focus: focus},
       attempt: 1
     }, [spawn_directive, timeout_directive]}
  end

  defp generate_run_id do
    "run_#{System.system_time(:millisecond)}_#{:rand.uniform(9999)}"
  end
end

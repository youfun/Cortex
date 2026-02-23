defmodule Cortex.Agents.Workers.AnalysisAgent do
  @moduledoc """
  代码分析 Worker Agent。

  负责分析代码结构、依赖关系、潜在问题等。
  这是一个叶子节点 Agent，不会再 spawn 子 Agent。
  """

  use Jido.Agent,
    name: "analysis_worker",
    description: "代码分析 Worker，负责分析代码结构和依赖",
    schema: [
      run_id: [type: :string, default: nil, doc: "本次运行的唯一标识"],
      task: [type: :map, default: %{}, doc: "分析任务描述"],
      result: [type: :map, default: nil, doc: "分析结果"],
      status: [
        type: :atom,
        default: :idle,
        doc: "Worker 状态: idle | analyzing | completed | failed"
      ],
      error: [type: :any, default: nil, doc: "错误信息"]
    ]

  require Logger

  @impl true
  def signal_routes(_ctx) do
    [
      {"analysis.request", __MODULE__.Actions.AnalyzeAction}
    ]
  end
end

defmodule Cortex.Agents.Workers.AnalysisAgent.Actions.AnalyzeAction do
  @moduledoc """
  执行代码分析的 Action。
  """

  use Jido.Action,
    name: "analyze",
    description: "执行代码分析任务",
    schema: [
      run_id: [type: :string, required: true],
      files: [type: {:list, :string}, default: []],
      focus: [type: :string, default: "structure"]
    ]

  require Logger
  alias Jido.Agent.Directive

  @impl true
  def run(params, context) do
    %{run_id: run_id, files: files, focus: focus} = params
    _state = context.state

    Logger.info("[AnalysisAgent] Starting analysis for run_id: #{run_id}, focus: #{focus}")

    # 执行分析（这里是简化版本，实际应该调用真实的分析工具）
    result = perform_analysis(files, focus)

    # 发送结果给 parent
    {:ok, result_signal} =
      Jido.Signal.new(
        "analysis.result",
        %{
          run_id: run_id,
          result: result,
          status: :success
        },
        source: "/worker/analysis"
      )

    emit_directive = Directive.emit_to_parent(%{state: context.state}, result_signal)

    {:ok,
     %{
       status: :completed,
       result: result,
       run_id: run_id
     }, Enum.reject([emit_directive], &is_nil/1)}
  end

  defp perform_analysis(files, focus) do
    # 简化的分析逻辑
    %{
      files_analyzed: length(files),
      focus: focus,
      findings: [
        %{type: "info", message: "Analysis completed successfully"},
        %{type: "suggestion", message: "Consider adding more documentation"}
      ],
      timestamp: DateTime.utc_now()
    }
  end
end

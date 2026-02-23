defmodule Cortex.Agents.Workers.ImplementationAgent do
  @moduledoc """
  代码实现 Worker Agent。

  负责根据分析结果生成代码实现。
  """

  use Jido.Agent,
    name: "implementation_worker",
    description: "代码实现 Worker，负责生成代码",
    schema: [
      run_id: [type: :string, default: nil],
      task: [type: :map, default: %{}],
      analysis_result: [type: :map, default: nil, doc: "来自 AnalysisAgent 的分析结果"],
      result: [type: :map, default: nil],
      status: [type: :atom, default: :idle],
      attempt: [type: :integer, default: 1, doc: "当前尝试次数"],
      previous_issues: [type: {:list, :map}, default: [], doc: "上次失败的问题列表"],
      error: [type: :any, default: nil]
    ]

  require Logger

  @impl true
  def signal_routes(_ctx) do
    [
      {"implementation.request", __MODULE__.Actions.ImplementAction}
    ]
  end
end

defmodule Cortex.Agents.Workers.ImplementationAgent.Actions.ImplementAction do
  @moduledoc """
  执行代码实现的 Action。
  """

  use Jido.Action,
    name: "implement",
    description: "执行代码实现任务",
    schema: [
      run_id: [type: :string, required: true],
      analysis_result: [type: :map, required: true],
      attempt: [type: :integer, default: 1],
      previous_issues: [type: {:list, :map}, default: []]
    ]

  require Logger
  alias Jido.Agent.Directive

  @impl true
  def run(params, context) do
    %{run_id: run_id, analysis_result: analysis, attempt: attempt} = params
    _state = context.state

    Logger.info(
      "[ImplementationAgent] Starting implementation for run_id: #{run_id}, attempt: #{attempt}"
    )

    # 执行实现（简化版本）
    result = perform_implementation(analysis, attempt, params[:previous_issues] || [])

    # 发送结果给 parent
    {:ok, result_signal} =
      Jido.Signal.new(
        "implementation.result",
        %{
          run_id: run_id,
          result: result,
          attempt: attempt,
          status: :success
        },
        source: "/worker/implementation"
      )

    emit_directive = Directive.emit_to_parent(%{state: context.state}, result_signal)

    {:ok,
     %{
       status: :completed,
       result: result,
       run_id: run_id,
       attempt: attempt
     }, Enum.reject([emit_directive], &is_nil/1)}
  end

  defp perform_implementation(_analysis, attempt, _previous_issues) do
    # 简化的实现逻辑
    %{
      files_created: 3,
      files_modified: 2,
      attempt: attempt,
      improvements: if(attempt > 1, do: ["Fixed issues from attempt #{attempt - 1}"], else: []),
      code_snippets: [
        %{file: "lib/example.ex", lines_added: 50}
      ],
      timestamp: DateTime.utc_now()
    }
  end
end

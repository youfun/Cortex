defmodule Cortex.Agents.Workers.ReviewAgent do
  @moduledoc """
  代码审查 Worker Agent。

  负责审查实现的代码质量、安全性、最佳实践等。
  """

  use Jido.Agent,
    name: "review_worker",
    description: "代码审查 Worker，负责审查代码质量",
    schema: [
      run_id: [type: :string, default: nil],
      task: [type: :map, default: %{}],
      implementation_result: [type: :map, default: nil],
      result: [type: :map, default: nil],
      status: [type: :atom, default: :idle],
      error: [type: :any, default: nil]
    ]

  require Logger

  @impl true
  def signal_routes(_ctx) do
    [
      {"review.request", __MODULE__.Actions.ReviewAction}
    ]
  end
end

defmodule Cortex.Agents.Workers.ReviewAgent.Actions.ReviewAction do
  @moduledoc """
  执行代码审查的 Action。
  """

  use Jido.Action,
    name: "review",
    description: "执行代码审查任务",
    schema: [
      run_id: [type: :string, required: true],
      implementation_result: [type: :map, required: true]
    ]

  require Logger
  alias Jido.Agent.Directive

  @impl true
  def run(params, context) do
    %{run_id: run_id, implementation_result: impl} = params
    _state = context.state

    Logger.info("[ReviewAgent] Starting review for run_id: #{run_id}")

    # 执行审查（简化版本）
    result = perform_review(impl)

    # 发送结果给 parent
    {:ok, result_signal} =
      Jido.Signal.new(
        "review.result",
        %{
          run_id: run_id,
          result: result,
          passed: result.passed,
          issues: result.issues,
          status: :success
        },
        source: "/worker/review"
      )

    emit_directive = Directive.emit_to_parent(%{state: context.state}, result_signal)

    {:ok,
     %{
       status: :completed,
       result: result,
       run_id: run_id
     }, Enum.reject([emit_directive], &is_nil/1)}
  end

  defp perform_review(_implementation) do
    # 简化的审查逻辑
    # 随机决定是否通过（实际应该有真实的审查逻辑）
    passed = :rand.uniform() > 0.3

    issues =
      if passed do
        []
      else
        [
          %{severity: "warning", message: "Missing error handling in function X"},
          %{severity: "info", message: "Consider adding type specs"}
        ]
      end

    %{
      passed: passed,
      issues: issues,
      quality_score: if(passed, do: 85, else: 65),
      recommendations: [
        "Add more unit tests",
        "Improve documentation"
      ],
      timestamp: DateTime.utc_now()
    }
  end
end

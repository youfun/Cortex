defmodule Cortex.Agents.CodingCoordinator do
  @moduledoc """
  编码任务协调器 Agent。

  负责协调多个 Worker Agent 完成编码任务：
  1. 分析阶段：spawn AnalysisAgent
  2. 实现阶段：spawn ImplementationAgent
  3. 审查阶段：spawn ReviewAgent
  4. 如果审查失败，重试实现（最多 3 次）

  ## 状态机

  :idle → :analyzing → :implementing → :reviewing → :completed
                           ↑                |
                           └── retry ───────┘ (if review fails)
  """

  use Jido.Agent,
    name: "coding_coordinator",
    description: "编码任务协调器，管理分析、实现、审查的完整流程",
    schema: [
      run_id: [type: :string, default: nil, doc: "本次运行的唯一标识"],
      phase: [
        type: :atom,
        default: :idle,
        doc: "当前阶段: idle | analyzing | implementing | reviewing | completed | failed"
      ],
      task: [type: :map, default: %{}, doc: "任务描述"],
      children: [type: :map, default: %{}, doc: "子 Agent 信息 %{tag => %{pid, status}}"],
      artifacts: [
        type: :map,
        default: %{},
        doc: "各阶段产出物 %{analysis: ..., implementation: ..., review: ...}"
      ],
      errors: [type: {:list, :any}, default: [], doc: "错误列表"],
      attempt: [type: :integer, default: 1, doc: "当前实现尝试次数"],
      max_attempts: [type: :integer, default: 3, doc: "最大重试次数"],
      attempt_history: [type: {:list, :map}, default: [], doc: "重试历史记录"]
    ]

  require Logger

  @impl true
  def signal_routes(_ctx) do
    [
      {"coding.task.start", __MODULE__.Actions.StartCodingAction},
      {"jido.agent.child.started", __MODULE__.Actions.ChildStartedAction},
      {"analysis.result", __MODULE__.Actions.AnalysisResultAction},
      {"implementation.result", __MODULE__.Actions.ImplementationResultAction},
      {"review.result", __MODULE__.Actions.ReviewResultAction},
      {"jido.agent.child.exit", __MODULE__.Actions.ChildExitAction}
    ]
  end
end

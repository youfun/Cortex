defmodule Cortex.Tools.Memory.RunMemoryChecks do
  @moduledoc """
  Tool to run memory system background checks.
  Identifies maintenance needs and preconscious surfacing opportunities.
  """
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Memory.BackgroundChecks

  @impl true
  def execute(args, _ctx) do
    # 提取参数，支持字符串键（来自 LLM）和原子键（来自内部调用）
    skip_consolidation =
      Map.get(args, "skip_consolidation") || Map.get(args, :skip_consolidation, false)

    skip_insights = Map.get(args, "skip_insights") || Map.get(args, :skip_insights, false)

    opts = [
      skip_consolidation: skip_consolidation,
      skip_insights: skip_insights
    ]

    result = BackgroundChecks.run(opts)
    {:ok, result}
  end
end

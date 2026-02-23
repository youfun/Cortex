defmodule Cortex.Tools.Memory.DetectInsights do
  @moduledoc """
  Tool to detect and queue memory insights.
  Analyzes memory system statistics and creates proposals for consolidation or key concept reviews.
  """
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Memory.InsightDetector

  @impl true
  def execute(args, _ctx) do
    # 提取参数，支持字符串键和原子键
    node_threshold = Map.get(args, "node_threshold") || Map.get(args, :node_threshold, 100)
    obs_threshold = Map.get(args, "obs_threshold") || Map.get(args, :obs_threshold, 500)

    opts = [
      node_threshold: node_threshold,
      obs_threshold: obs_threshold
    ]

    case InsightDetector.detect_and_queue(opts) do
      {:ok, status} ->
        {:ok, %{status: status}}
    end
  end
end

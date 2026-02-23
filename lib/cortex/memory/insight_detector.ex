defmodule Cortex.Memory.InsightDetector do
  @moduledoc """
  轻量级洞察检测器。
  基于记忆系统的统计数据生成低成本的洞察提议，无需调用 LLM。
  """

  alias Cortex.Memory.Consolidator
  alias Cortex.Memory.Proposal
  alias Cortex.Memory.Store

  @doc """
  检测并排队洞察提议。

  ## 选项

  - `:node_threshold` - 触发洞察的节点数量阈值（默认：100）
  - `:obs_threshold` - 触发洞察的观察项数量阈值（默认：500）

  ## 返回

  `{:ok, :insight_created}` 或 `{:ok, :no_insight}`
  """
  def detect_and_queue(opts \\ []) do
    default_node_threshold =
      :cortex
      |> Application.get_env(:memory, [])
      |> get_in([:thresholds, :node_insight]) || 100

    default_obs_threshold =
      :cortex
      |> Application.get_env(:memory, [])
      |> get_in([:thresholds, :obs_insight]) || 500

    node_threshold = Keyword.get(opts, :node_threshold, default_node_threshold)
    obs_threshold = Keyword.get(opts, :obs_threshold, default_obs_threshold)

    # 1. 检查知识图谱规模
    consolidator_stats = Consolidator.stats()
    node_count = get_in(consolidator_stats, [:graph, :node_count]) || 0

    if node_count > node_threshold do
      content =
        "Knowledge Graph keeps growing (#{node_count} nodes). Structural review recommended."

      # 检查是否已有类似提议以避免刷屏
      unless Proposal.find_similar(content, threshold: 0.9, status: :pending) do
        Proposal.create(content,
          type: :insight,
          confidence: 0.6,
          evidence: ["KG node count: #{node_count} > #{node_threshold}"]
        )
      end
    end

    # 2. 检查存储规模
    store_stats = Store.stats()
    obs_count = Map.get(store_stats, :total, 0)

    if obs_count > obs_threshold do
      content = "Memory Store accumulation high (#{obs_count} items). Deep consolidation advised."

      unless Proposal.find_similar(content, threshold: 0.9, status: :pending) do
        Proposal.create(content,
          type: :insight,
          confidence: 0.7,
          evidence: ["Store total: #{obs_count} > #{obs_threshold}"]
        )
      end
    end

    {:ok, :check_completed}
  end
end

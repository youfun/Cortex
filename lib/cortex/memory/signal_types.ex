defmodule Cortex.Memory.SignalTypes do
  @moduledoc """
  记忆系统信号类型常量定义。

  所有信号遵循 CloudEvents 1.0.2 规范，类型命名遵循 `domain.action.detail` 三段式。

  ## 操作完成通知信号（由 Memory 子系统内部操作完成后发射）

  - `memory.observation.created` - 新观察项已写入
  - `memory.observation.deleted` - 观察项已删除
  - `memory.observation.updated` - 观察项已更新
  - `memory.index.stored` - 向量索引已存储
  - `memory.index.recalled` - 语义检索已完成（仅写操作通知，纯读不发射）
  - `memory.kg.node_added` - 知识图谱节点已新增
  - `memory.kg.edge_added` - 知识图谱边已新增
  - `memory.kg.pruned` - 节点已剪枝
  - `memory.working.saved` - 工作记忆已保存
  - `memory.consolidation.completed` - 整合已完成

  ## 跨组件通信信号（组件间唯一的通信方式）

  - `memory.proposal.created` - 潜意识 → 意识：提交提议
  - `memory.proposal.accepted` - 意识 → 存储：接受提议
  - `memory.proposal.rejected` - 意识 → 存储：拒绝提议
  - `memory.preconscious.surfaced` - 预意识 → 意识：浮现记忆
  - `memory.insight.detected` - 洞察检测 → 意识：发现模式
  """

  # 操作完成通知信号
  @memory_observation_created "memory.observation.created"
  @memory_observation_deleted "memory.observation.deleted"
  @memory_observation_updated "memory.observation.updated"
  @memory_index_stored "memory.index.stored"
  @memory_index_recalled "memory.index.recalled"
  @memory_kg_node_added "memory.kg.node_added"
  @memory_kg_edge_added "memory.kg.edge_added"
  @memory_kg_pruned "memory.kg.pruned"
  @memory_working_saved "memory.working.saved"
  @memory_consolidation_completed "memory.consolidation.completed"

  # 跨组件通信信号
  @memory_proposal_created "memory.proposal.created"
  @memory_proposal_accepted "memory.proposal.accepted"
  @memory_proposal_rejected "memory.proposal.rejected"
  @memory_preconscious_surfaced "memory.preconscious.surfaced"
  @memory_insight_detected "memory.insight.detected"

  # 操作完成通知信号
  def memory_observation_created, do: @memory_observation_created
  def memory_observation_deleted, do: @memory_observation_deleted
  def memory_observation_updated, do: @memory_observation_updated
  def memory_index_stored, do: @memory_index_stored
  def memory_index_recalled, do: @memory_index_recalled
  def memory_kg_node_added, do: @memory_kg_node_added
  def memory_kg_edge_added, do: @memory_kg_edge_added
  def memory_kg_pruned, do: @memory_kg_pruned
  def memory_working_saved, do: @memory_working_saved
  def memory_consolidation_completed, do: @memory_consolidation_completed

  # 跨组件通信信号
  def memory_proposal_created, do: @memory_proposal_created
  def memory_proposal_accepted, do: @memory_proposal_accepted
  def memory_proposal_rejected, do: @memory_proposal_rejected
  def memory_preconscious_surfaced, do: @memory_preconscious_surfaced
  def memory_insight_detected, do: @memory_insight_detected

  @doc """
  返回所有记忆相关的信号类型列表。
  """
  def all_types do
    [
      @memory_observation_created,
      @memory_observation_deleted,
      @memory_observation_updated,
      @memory_index_stored,
      @memory_index_recalled,
      @memory_kg_node_added,
      @memory_kg_edge_added,
      @memory_kg_pruned,
      @memory_working_saved,
      @memory_consolidation_completed,
      @memory_proposal_created,
      @memory_proposal_accepted,
      @memory_proposal_rejected,
      @memory_preconscious_surfaced,
      @memory_insight_detected
    ]
  end

  @doc """
  返回所有操作完成通知信号类型。
  """
  def operation_completed_types do
    [
      @memory_observation_created,
      @memory_observation_deleted,
      @memory_observation_updated,
      @memory_index_stored,
      @memory_index_recalled,
      @memory_kg_node_added,
      @memory_kg_edge_added,
      @memory_kg_pruned,
      @memory_working_saved,
      @memory_consolidation_completed
    ]
  end

  @doc """
  返回所有跨组件通信信号类型。
  """
  def cross_component_types do
    [
      @memory_proposal_created,
      @memory_proposal_accepted,
      @memory_proposal_rejected,
      @memory_preconscious_surfaced,
      @memory_insight_detected
    ]
  end
end

defmodule Cortex.History.DualTrackFilter do
  @moduledoc """
  双轨历史过滤器。

  根据信号类型自动分流：

  ## 审计流 (Full Audit)
  所有信号都记录，UI 可以展示完整历史。

  ## 对话流 (LLM View)
  只保留 LLM 推理所需的关键信号：
  - user.input.*          - 用户输入
  - agent.response        - Agent 响应
  - tool.result.*         - 工具执行结果
  - tool.error.*          - 工具错误
  - skill.loaded          - 新技能可用
  - memory.proposal.*     - 记忆提议 [NEW]
  - memory.preconscious.* - 预意识浮现 [NEW]

  过滤掉的信号（不发送给 LLM）：
  - system.heartbeat      - 心跳
  - tool.stream.*         - 流式输出（已在 result 中汇总）
  - file.changed.*        - 文件变更通知（UI 专用）
  - session.branch.*      - 会话分支操作
  - memory.consolidation.* - 记忆整合（后台操作）
  """

  @llm_visible_types [
    "user.input.",
    "agent.chat.request",
    "agent.response",
    "agent.think",
    "tool.result.",
    "tool.error.",
    "skill.loaded",
    # [NEW] Memory system signals
    "memory.proposal.",
    "memory.preconscious."
  ]

  @doc """
  判断信号是否应该包含在 LLM 上下文中。
  """
  def llm_visible?(%{type: type}) do
    Enum.any?(@llm_visible_types, &String.starts_with?(type, &1))
  end

  @doc """
  从完整信号历史中提取 LLM 可见的子集。
  """
  def filter_for_llm(signals) when is_list(signals) do
    Enum.filter(signals, &llm_visible?/1)
  end

  @doc """
  将信号转换为 LLM 消息格式。
  """
  def signal_to_llm_message(%{type: "user.input." <> _, data: data}) do
    %{role: "user", content: data.content}
  end

  def signal_to_llm_message(%{type: "agent.chat.request", data: data}) do
    %{role: "user", content: data[:content] || data["content"]}
  end

  def signal_to_llm_message(%{type: "agent.response", data: data}) do
    %{role: "assistant", content: data.content}
  end

  def signal_to_llm_message(%{type: "tool.result." <> tool, data: data}) do
    %{role: "tool", tool: tool, content: inspect(data)}
  end

  def signal_to_llm_message(%{type: "tool.error." <> tool, data: data}) do
    %{role: "tool", tool: tool, content: "ERROR: #{inspect(data)}"}
  end

  def signal_to_llm_message(%{type: type, data: data}) do
    %{role: "system", content: "[#{type}] #{inspect(data)}"}
  end
end

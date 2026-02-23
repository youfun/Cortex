defmodule Cortex.Memory.CognitivePrompts do
  @moduledoc """
  认知模式提示词管理模块。
  根据当前的认知任务需求提供不同的 System Prompt 片段。
  """

  @doc """
  获取指定模式的 System Prompt 片段。

  ## 模式

  - `:default` - 平衡模式
  - `:creative` - 发散思维
  - `:analytical` - 逻辑分析
  - `:memory` - 记忆检索增强
  - `:critical` - 批判性思维

  如果不识别模式，默认返回 `:default` 模式内容。
  """
  def prompt_for(mode) do
    case mode do
      :creative ->
        """
        ## COGNITIVE MODE: CREATIVE
        - Think divergently and explore novel connections.
        - Prioritize innovation over convention.
        - Use analogies and metaphors freely.
        """

      :analytical ->
        """
        ## COGNITIVE MODE: ANALYTICAL
        - Think convergently and logically.
        - Break down complex problems into components.
        - Focus on evidence, structure, and clarity.
        """

      :memory ->
        """
        ## COGNITIVE MODE: MEMORY-FOCUSED
        - Actively recall and utilize past context.
        - Prioritize consistency with established facts in Knowledge Graph.
        - Explicitly reference prior decisions or learnings.
        """

      :critical ->
        """
        ## COGNITIVE MODE: CRITICAL
        - Question assumptions and identify potential flaws.
        - Evaluate arguments for validity and soundness.
        - Consider edge cases and potential risks.
        """

      _ ->
        """
        ## COGNITIVE MODE: STANDARD
        - Maintain a balanced perspective.
        - Adapt to the context of the conversation.
        - Be helpful, clear, and direct.
        """
    end
  end

  @doc """
  获取指定模式的推荐模型 ID。

  目前作为占位符，总是返回 nil。
  未来可用于根据任务切换模型（如 o1-preview 用于推理，claude-3-opus 用于写作）。
  """
  def model_for(_mode), do: nil
end

defmodule Cortex.Memory.ContextBuilder do
  @moduledoc """
  LLM 上下文构建器 —— 组装 System Prompt 的记忆部分。

  从工作记忆和观察项中组装 LLM 上下文，遵循 Token 预算限制。

  ## 注入策略

  ```
  System Prompt
  ├── base_prompt()                    # 工具说明 + 指导原则
  ├── memory_section                   # 现有  MEMORY.md (全局偏好)
  ├── [NEW] observation_section        # 最近 + 高优先级观察项
  ├── [NEW] working_memory_section     # 当前关注/好奇/顾虑
  └── skills_section                   # 可用技能列表
  ```

  ## Token 预算分配

  - 系统提示词基础：~2000 tokens
  - 技能部分：~2000 tokens
  - 记忆部分（本模块）：上下文窗口的 15%
  - 预留对话历史：~4000 tokens
  """

  alias Cortex.Memory.Observation
  alias Cortex.Memory.Store
  alias Cortex.Memory.TokenBudget
  alias Cortex.Workspaces

  @default_observation_limit 20
  @default_memory_ratio 0.15

  @doc """
  构建完整的记忆上下文字符串。

  ## 参数

  - `opts` - 可选参数
    - `:workspace_root` - 工作区根目录（默认：workspace_root）
    - `:workspace_id` - 工作区 ID（可选）
    - `:model` - 模型名称（默认："gemini-3-flash"）
    - `:observation_limit` - 观察项数量限制（默认：20）
    - `:include_high_priority_only` - 仅包含高优先级（默认：false）

  ## 返回

  格式化的记忆上下文字符串
  """
  def build_context(opts \\ []) do
    _workspace_root = Keyword.get(opts, :workspace_root, Workspaces.workspace_root())
    _workspace_id = Keyword.get(opts, :workspace_id)
    model = Keyword.get(opts, :model, "gemini-3-flash")
    observation_limit = Keyword.get(opts, :observation_limit, @default_observation_limit)
    high_priority_only = Keyword.get(opts, :include_high_priority_only, false)

    # 优先使用显式传入的预算，否则计算
    memory_budget =
      Keyword.get(opts, :token_budget) ||
        TokenBudget.calculate_memory_budget(model, memory_ratio: @default_memory_ratio)

    # 获取观察项
    observations =
      if high_priority_only do
        Store.load_observations(priority: :high, limit: observation_limit)
      else
        Store.load_observations(limit: observation_limit)
      end

    # 按优先级排序
    sorted_observations = Observation.sort_by_priority(observations)

    # 根据 Token 预算裁剪
    cropped =
      TokenBudget.crop_to_budget(
        sorted_observations,
        memory_budget,
        content_key: :content,
        priority_key: :priority
      )

    # 获取高优先级观察项（以裁剪结果为准）
    high_priority = Observation.high_priority(cropped.selected)

    high_priority_summary = build_high_priority_summary(high_priority)

    # 如果高优先级摘要超出预算，则丢弃摘要，避免挤占主要观察项
    high_priority_summary =
      if high_priority_summary &&
           TokenBudget.estimate_tokens(high_priority_summary) + cropped.total_tokens >
             memory_budget do
        nil
      else
        high_priority_summary
      end

    working_focus = fetch_working_focus()
    working_section = build_working_memory_section(current_focus: working_focus)

    # 构建各个部分
    parts = [
      build_observations_section(cropped.selected),
      high_priority_summary,
      working_section
    ]

    content =
      parts
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    case content do
      "" -> ""
      _ -> "## Observational Memory\n\n" <> content
    end
  end

  @doc """
  构建观察项部分。
  """
  def build_observations_section([]), do: nil

  def build_observations_section(observations) when is_list(observations) do
    lines =
      Enum.map_join(observations, "\n", &format_observation_line/1)

    """
    ### Recent Observations

    #{lines}
    """
    |> String.trim()
  end

  @doc """
  构建高优先级摘要。
  """
  def build_high_priority_summary([]), do: nil

  def build_high_priority_summary(observations) when is_list(observations) do
    high_priority_items = Enum.filter(observations, &(&1.priority == :high))

    if high_priority_items == [] do
      nil
    else
      items =
        Enum.map_join(high_priority_items, "\n", fn item -> "- #{item.content}" end)

      """
      ### High Priority Notes

      #{items}
      """
      |> String.trim()
    end
  end

  @doc """
  构建工作记忆部分（思维、关注、好奇）。

  当前为简化实现，未来可扩展。
  """
  def build_working_memory_section(opts \\ []) do
    # TODO: 集成 WorkingMemory 模块
    current_focus = Keyword.get(opts, :current_focus)

    if current_focus do
      """
      ### Current Focus

      #{current_focus}
      """
    else
      nil
    end
  end

  @doc """
  格式化单个观察项为文本行。
  """
  def format_observation_line(%Observation{} = obs) do
    prefix =
      case obs.priority do
        :high -> "[重要]"
        :medium -> "[一般]"
        :low -> "[备注]"
      end

    "#{prefix} #{obs.content}"
  end

  @doc """
  将记忆上下文附加到现有系统提示词。

  ## 参数

  - `base_prompt` - 基础系统提示词
  - `opts` - 传递给 build_context/1 的选项

  ## 返回

  完整的系统提示词
  """
  def append_to_prompt(base_prompt, opts \\ []) when is_binary(base_prompt) do
    memory_context = build_context(opts)

    if memory_context == "" do
      base_prompt
    else
      base_prompt <> "\n\n" <> memory_context
    end
  end

  @doc """
  检查内存上下文是否适合 Token 预算。

  返回包含以下字段的 Map：
  - `:fits` - 是否符合预算
  - `:estimated_tokens` - 估算的 Token 数
  - `:budget` - 预算上限
  - `:overage` - 超出数量（如符合则为 0）
  """
  def check_budget(opts \\ []) do
    model = Keyword.get(opts, :model, "gemini-3-flash")

    memory_budget =
      TokenBudget.calculate_memory_budget(model, memory_ratio: @default_memory_ratio)

    context = build_context(opts)
    estimated = TokenBudget.estimate_tokens(context)

    %{
      fits: estimated <= memory_budget,
      estimated_tokens: estimated,
      budget: memory_budget,
      overage: max(estimated - memory_budget, 0)
    }
  end

  @doc """
  获取上下文构建统计。
  """
  def stats(opts \\ []) do
    _workspace_root = Keyword.get(opts, :workspace_root, Workspaces.workspace_root())
    model = Keyword.get(opts, :model, "gemini-3-flash")

    memory_budget =
      TokenBudget.calculate_memory_budget(model, memory_ratio: @default_memory_ratio)

    observations = Store.load_observations(limit: 1000)

    %{
      total_observations: length(observations),
      high_priority_count: length(Observation.high_priority(observations)),
      memory_budget: memory_budget,
      memory_budget_formatted: TokenBudget.format_tokens(memory_budget)
    }
  end

  defp fetch_working_focus do
    case Process.whereis(Cortex.Memory.WorkingMemory) do
      nil ->
        nil

      _pid ->
        case Cortex.Memory.WorkingMemory.get_focus() do
          %{content: content} when is_binary(content) -> content
          _ -> nil
        end
    end
  end
end

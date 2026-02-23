defmodule Cortex.Memory.TokenBudget do
  @moduledoc """
  Token 预算管理。

  从 Arbor Memory 的 TokenBudget 移植，用于：
  - 估算文本的 Token 数量 (现在统一使用 Cortex.Agents.TokenCounter)
  - 查询模型的上下文大小限制
  - 在 Prompt 预算控制中裁剪内容

  ## 模型上下文大小（近似值）

  | 模型 | 上下文窗口 |
  |------|-----------|
  | gemini-2.0-flash | 1,048,576 tokens |
  | gemini-2.0-flash-lite | 1,048,576 tokens |
  | gemini-3-flash | 1,048,576 tokens |
  | gemini-3-flash-lite | 1,048,576 tokens |
  | gemini-3-flash-thinking | 32,768 tokens |
  | gemini-2.5-pro | 1,048,576 tokens |
  | claude-opus | 200,000 tokens |
  | claude-sonnet | 200,000 tokens |
  | claude-haiku | 200,000 tokens |
  | gpt-4o | 128,000 tokens |
  | gpt-4o-mini | 128,000 tokens |
  | gpt-4-turbo | 128,000 tokens |
  | gpt-3.5-turbo | 16,384 tokens |
  """

  alias Cortex.Agents.TokenCounter

  # 模型上下文窗口大小（tokens）
  @model_contexts %{
    # Gemini 模型
    "gemini-2.0-flash" => 1_048_576,
    "gemini-2.0-flash-lite" => 1_048_576,
    "gemini-3-flash" => 1_048_576,
    "gemini-3-flash-lite" => 1_048_576,
    "gemini-3-flash-thinking" => 32_768,
    "gemini-2.5-pro" => 1_048_576,

    # Claude 模型
    "claude-opus" => 200_000,
    "claude-opus-4" => 200_000,
    "claude-opus-4-6" => 200_000,
    "claude-sonnet" => 200_000,
    "claude-sonnet-4" => 200_000,
    "claude-sonnet-4-5" => 200_000,
    "claude-haiku" => 200_000,
    "claude-haiku-4" => 200_000,
    "claude-haiku-4-5" => 200_000,

    # GPT 模型
    "gpt-4o" => 128_000,
    "gpt-4o-mini" => 128_000,
    "gpt-4-turbo" => 128_000,
    "gpt-4" => 8_192,
    "gpt-3.5-turbo" => 16_384,

    # 默认
    "default" => 128_000
  }

  @doc """
  估算文本的 Token 数量。

  统一调用 `Cortex.Agents.TokenCounter.estimate_tokens/1` 进行细粒度估算。

  ## 示例

      iex> TokenBudget.estimate_tokens("Hello world")
      4

      iex> TokenBudget.estimate_tokens("你好世界")
      8
  """
  @spec estimate_tokens(String.t() | nil) :: non_neg_integer()
  def estimate_tokens(text), do: TokenCounter.estimate_tokens(text)

  @doc """
  估算列表中所有文本的总 Token 数。
  """
  @spec estimate_tokens_list([String.t()]) :: non_neg_integer()
  def estimate_tokens_list(texts) when is_list(texts) do
    texts
    |> Enum.map(&estimate_tokens/1)
    |> Enum.sum()
  end

  @doc """
  获取模型的上下文窗口大小。

  如果模型名称不在已知列表中，返回默认值。

  ## 示例

      iex> TokenBudget.get_context_size("gemini-3-flash")
      1048576

      iex> TokenBudget.get_context_size("unknown-model")
      128000
  """
  @spec get_context_size(String.t()) :: pos_integer()
  def get_context_size(model_name) when is_binary(model_name) do
    # 尝试精确匹配
    case Map.get(@model_contexts, model_name) do
      nil ->
        # 尝试前缀匹配
        case find_by_prefix(model_name) do
          nil -> Map.get(@model_contexts, "default")
          size -> size
        end

      size ->
        size
    end
  end

  @doc """
  计算可用于记忆的 Token 预算。

  为系统提示词、历史对话等预留空间后，返回可用于记忆内容的 Token 数。

  ## 参数

  - `model_name` - 模型名称
  - `opts` - 可选参数
    - `:reserved_tokens` - 预留 Token 数（默认：4000）
    - `:memory_ratio` - 记忆占用比例（默认：0.15 = 15%）

  ## 示例

      iex> TokenBudget.calculate_memory_budget("gemini-3-flash")
      153286

      iex> TokenBudget.calculate_memory_budget("gpt-4o", reserved_tokens: 8000)
      11200
  """
  @spec calculate_memory_budget(String.t(), keyword()) :: non_neg_integer()
  def calculate_memory_budget(model_name, opts \\ []) do
    context_size = get_context_size(model_name)
    reserved = Keyword.get(opts, :reserved_tokens, 4000)
    memory_ratio = Keyword.get(opts, :memory_ratio, 0.15)

    available = trunc(context_size * memory_ratio) - reserved
    max(available, 0)
  end

  @doc """
  根据 Token 预算裁剪内容列表。

  优先保留优先级高的内容，直到达到预算上限。

  ## 参数

  - `items` - 内容项列表，每项应为包含 `:content` 和可选 `:priority` 的 Map
  - `budget` - Token 预算
  - `opts` - 可选参数
    - `:content_key` - 内容字段名（默认：`:content`）
    - `:priority_key` - 优先级字段名（默认：`:priority`）

  ## 返回

  包含以下字段的 Map：
  - `:selected` - 选中的内容列表
  - `:dropped` - 被裁剪的内容列表
  - `:total_tokens` - 选中内容的总 Token 数

  ## 示例

      items = [
        %{content: "重要内容", priority: :high},
        %{content: "次要内容", priority: :low}
      ]
      TokenBudget.crop_to_budget(items, 10)
  """
  @spec crop_to_budget([map()], non_neg_integer(), keyword()) :: %{
          selected: [map()],
          dropped: [map()],
          total_tokens: non_neg_integer()
        }
  def crop_to_budget(items, budget, opts \\ []) when is_list(items) and budget >= 0 do
    content_key = Keyword.get(opts, :content_key, :content)
    priority_key = Keyword.get(opts, :priority_key, :priority)

    # 按优先级排序
    sorted =
      Enum.sort_by(items, fn item ->
        priority = Map.get(item, priority_key, :medium)
        priority_value(priority)
      end)

    # 累积选择直到预算用完
    {selected, dropped, used_tokens} =
      Enum.reduce(sorted, {[], [], 0}, fn item, {sel, drop, used} ->
        content = Map.get(item, content_key, "")
        tokens = estimate_tokens(content)

        if used + tokens <= budget do
          {[item | sel], drop, used + tokens}
        else
          {sel, [item | drop], used}
        end
      end)

    %{
      selected: Enum.reverse(selected),
      dropped: Enum.reverse(dropped),
      total_tokens: used_tokens
    }
  end

  @doc """
  检查文本是否在 Token 预算内。

  ## 示例

      iex> TokenBudget.within_budget?("短文本", 100)
      true

      iex> TokenBudget.within_budget?(String.duplicate("长", 1000), 10)
      false
  """
  @spec within_budget?(String.t(), non_neg_integer()) :: boolean()
  def within_budget?(text, budget) when is_binary(text) and budget >= 0 do
    estimate_tokens(text) <= budget
  end

  @doc """
  格式化 Token 数为人类可读形式。

  ## 示例

      iex> TokenBudget.format_tokens(1572864)
      "1.6M"

      iex> TokenBudget.format_tokens(15728)
      "15.7K"
  """
  @spec format_tokens(non_neg_integer()) :: String.t()
  def format_tokens(tokens) when tokens >= 1_000_000 do
    "#{Float.round(tokens / 1_000_000, 1)}M"
  end

  def format_tokens(tokens) when tokens >= 1_000 do
    "#{Float.round(tokens / 1_000, 1)}K"
  end

  def format_tokens(tokens), do: to_string(tokens)

  @doc """
  获取所有已知模型的上下文大小。

  返回模型名称到上下文大小的映射 Map。
  """
  @spec list_model_contexts() :: %{String.t() => pos_integer()}
  def list_model_contexts do
    @model_contexts
    |> Map.drop(["default"])
  end

  # 私有函数

  defp find_by_prefix(model_name) do
    found = Enum.find(@model_contexts, fn {key, _} -> String.starts_with?(model_name, key) end)

    case found do
      nil -> nil
      {_, size} -> size
    end
  end

  defp priority_value(:high), do: 0
  defp priority_value(:medium), do: 1
  defp priority_value(:low), do: 2
  defp priority_value(_), do: 1
end

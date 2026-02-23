defmodule Cortex.Agents.TokenCounter do
  @moduledoc """
  Token 计数器模块，从 Gong.Compaction.TokenEstimator 移植。

  用于估算中英文混合文本的 token 数量，无外部依赖。

  ## 估算规则 (Heuristic Rules)

  - **中文字符 (CJK)**: 每个字符 ≈ 2 tokens。
  - **连续英文字母/数字 (ASCII Letters/Digits)**: 视为单词，每个单词 ≈ 1.3 tokens。
  - **其他字符 (空白/标点)**: 计为 1 token (保守估算)。

  该算法旨在提供快速、保守的估算，而非 100% 精确的 Tokenizer 实现。

  ## Telemetry Events

  This module emits the following telemetry events:

  - `[:cortex, :token_counter, :estimate]` - Emitted when tokens are estimated
    - Measurements: `%{count: integer()}`
    - Metadata: `%{text_length: integer(), type: :text | :messages}`
  """

  require Logger

  @doc """
  估算单段文本的 token 数。

  ## 示例

      iex> Cortex.Agents.TokenCounter.estimate_tokens("Hello world")
      3 # "Hello" (1.3) + " " (1) + "world" (1.3) = 3.6 -> round -> 4 (Actually depends on state)
      # Current impl: Hello(word) -> 1.3, Space -> 1.3, world(word) -> 1.3 = 3.9 -> 4

      iex> Cortex.Agents.TokenCounter.estimate_tokens("你好世界")
      8 # 4 chars * 2 = 8
  """
  @spec estimate_tokens(String.t() | nil) :: non_neg_integer()
  def estimate_tokens(nil), do: 0
  def estimate_tokens(""), do: 0

  def estimate_tokens(text) when is_binary(text) do
    result =
      text
      |> String.graphemes()
      |> count_tokens(0, :start)

    # Ensure result is a float before calling Float.ceil
    tokens =
      case result do
        n when is_integer(n) -> n
        n when is_float(n) -> Float.ceil(n) |> trunc()
      end

    # Emit telemetry event
    :telemetry.execute(
      [:cortex, :token_counter, :estimate],
      %{count: tokens},
      %{text_length: String.length(text), type: :text}
    )

    tokens
  end

  # 中文字符每个 2 tokens
  # 连续英文字母序列视为单词，每个单词 1.3 tokens
  defp count_tokens([], acc, :in_word), do: acc + 1.3
  defp count_tokens([], acc, _state), do: acc

  defp count_tokens([char | rest], acc, state) do
    cond do
      cjk?(char) ->
        # 中文字符：每个约 2 tokens；如果之前在英文单词中，先结算
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus + 2, :start)

      ascii_letter?(char) ->
        # 英文字母：积累单词
        count_tokens(rest, acc, :in_word)

      true ->
        # 空白、标点等：如果之前在英文单词中，结算
        bonus = if state == :in_word, do: 1.3, else: 0
        # 即使是非中英文，也给一点权重 (1 token)
        count_tokens(rest, acc + bonus + 1, :start)
    end
  end

  defp cjk?(<<cp::utf8>>) do
    # CJK 统一表意文字范围
    # 中文标点
    (cp >= 0x4E00 and cp <= 0x9FFF) or
      (cp >= 0x3400 and cp <= 0x4DBF) or
      (cp >= 0x20000 and cp <= 0x2A6DF) or
      (cp >= 0x3000 and cp <= 0x303F) or
      (cp >= 0xFF00 and cp <= 0xFFEF)
  end

  defp cjk?(_), do: false

  defp ascii_letter?(<<cp::utf8>>) do
    (cp >= ?a and cp <= ?z) or (cp >= ?A and cp <= ?Z) or
      (cp >= ?0 and cp <= ?9)
  end

  defp ascii_letter?(_), do: false

  @doc "估算消息列表的总 token 数"
  @spec estimate_messages([map()]) :: non_neg_integer()
  def estimate_messages([]), do: 0

  def estimate_messages(messages) when is_list(messages) do
    tokens =
      messages
      |> Enum.reduce(0, fn msg, acc ->
        content = extract_content(msg)
        acc + estimate_tokens(content)
      end)

    # Emit telemetry event
    :telemetry.execute(
      [:cortex, :token_counter, :estimate],
      %{count: tokens},
      %{message_count: length(messages), type: :messages}
    )

    tokens
  end

  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(_), do: ""
end

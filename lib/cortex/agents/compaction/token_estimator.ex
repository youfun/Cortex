defmodule Cortex.Agents.Compaction.TokenEstimator do
  @moduledoc """
  Token 估算模块。

  用于估算中英文混合文本的 token 数量，无外部依赖。
  规则：
  - 中文字符: 1字 ≈ 2 tokens
  - 英文单词: 1 word ≈ 1.3 tokens
  - 空白/标点: 不单独计 token
  """

  @doc "估算单段文本的 token 数"
  @spec estimate(String.t()) :: non_neg_integer()
  def estimate(nil), do: 0
  def estimate(""), do: 0

  def estimate(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> count_tokens(0, :start)
    |> round()
    |> max(0)
  end

  defp count_tokens([], acc, :in_word), do: acc + 1.3
  defp count_tokens([], acc, _state), do: acc

  defp count_tokens([char | rest], acc, state) do
    cond do
      cjk?(char) ->
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus + 2, :start)

      ascii_letter?(char) ->
        count_tokens(rest, acc, :in_word)

      true ->
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus, :start)
    end
  end

  defp cjk?(<<cp::utf8>>) do
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
    messages
    |> Enum.reduce(0, fn msg, acc ->
      content = extract_content(msg)
      acc + estimate(content)
    end)
  end

  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content

  defp extract_content(%{content: content}) when is_list(content) do
    Enum.map_join(content, " ", &part_text/1)
  end

  defp extract_content(%{"content" => content}) when is_list(content) do
    Enum.map_join(content, " ", &part_text/1)
  end

  defp extract_content(_), do: ""

  defp part_text(part) when is_binary(part), do: part

  defp part_text(part) when is_map(part) do
    Map.get(part, :text) || Map.get(part, "text") || Map.get(part, :data) || Map.get(part, "data") ||
      ""
  end

  defp part_text(_), do: ""
end

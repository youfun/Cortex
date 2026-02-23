defmodule Cortex.Agents.SlidingWindow do
  @moduledoc """
  滑动窗口管理模块，从 Gong.Compaction 移植。

  用于管理会话历史的滑动窗口，确保：
  - 系统消息始终保留
  - 最近 N 条非系统消息保留
  - 自动寻找安全边界，防止 tool_call 和 tool_result 配对被拆分
  """

  @default_window_size 20

  @doc """
  分割消息：系统消息始终保留在 recent 中，其余按窗口分割。

  返回 {old_messages, recent_messages}，其中 recent 包含所有系统消息 + 最近 window_size 条非系统消息。
  """
  @spec split([map()], non_neg_integer()) :: {[map()], [map()]}
  def split(messages, window_size \\ @default_window_size) do
    {system_msgs, non_system} =
      Enum.split_with(messages, fn msg ->
        get_role(msg) == "system"
      end)

    if length(non_system) <= window_size do
      {[], system_msgs ++ non_system}
    else
      split_at = length(non_system) - window_size
      # 调整分割点，确保 tool_call/result 配对不被拆分
      safe_split = find_safe_boundary(non_system, split_at)
      {old, recent_non_system} = Enum.split(non_system, safe_split)
      {old, system_msgs ++ recent_non_system}
    end
  end

  @doc """
  寻找安全边界，确保分割点不在 tool_call 和 tool_result 之间。
  """
  @spec find_safe_boundary([map()], non_neg_integer()) :: non_neg_integer()
  def find_safe_boundary(_messages, split_at) when split_at <= 0, do: 0

  def find_safe_boundary(messages, split_at) do
    if split_at >= length(messages) do
      split_at
    else
      first_recent = Enum.at(messages, split_at)

      cond do
        # recent 第一条是 tool result → 向前找到对应的 assistant(tool_calls)
        get_role(first_recent) == "tool" ->
          scan_back_for_tool_call_start(messages, split_at)

        # old 最后一条是 assistant(tool_calls) → 它的 results 在 recent，把它也放进 recent
        split_at > 0 and has_tool_calls?(Enum.at(messages, split_at - 1)) ->
          split_at - 1

        true ->
          split_at
      end
    end
  end

  defp scan_back_for_tool_call_start(_messages, idx) when idx <= 0, do: 0

  defp scan_back_for_tool_call_start(messages, idx) do
    prev = Enum.at(messages, idx - 1)

    cond do
      get_role(prev) == "tool" -> scan_back_for_tool_call_start(messages, idx - 1)
      has_tool_calls?(prev) -> idx - 1
      true -> idx
    end
  end

  defp has_tool_calls?(%{tool_calls: tcs}) when is_list(tcs) and tcs != [], do: true
  defp has_tool_calls?(%{"tool_calls" => tcs}) when is_list(tcs) and tcs != [], do: true
  defp has_tool_calls?(_), do: false

  defp get_role(%{role: role}), do: to_string(role)
  defp get_role(%{"role" => role}), do: to_string(role)
  defp get_role(_), do: nil
end

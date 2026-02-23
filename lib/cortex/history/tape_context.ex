defmodule Cortex.History.TapeContext do
  @moduledoc """
  从 Tape 投影 LLM 消息上下文。
  负责将 Tape Entry 转换为 ReqLLM.Context 可用的消息格式。
  """

  alias Cortex.History.Tape.{Store, Entry}

  @doc """
  从 Tape 恢复 LLM 消息列表。

  ## 参数
  - session_id: 会话 ID
  - opts: 可选参数
    - limit: 限制返回的 Entry 数量
    - from_anchor: 从指定锚点开始恢复

  ## 返回
  ReqLLM.Message 列表
  """
  def to_llm_messages(session_id, opts \\ []) do
    entries =
      if anchor = Keyword.get(opts, :from_anchor) do
        Store.from_last_anchor(session_id, anchor)
      else
        limit = Keyword.get(opts, :limit, 100)
        Store.list_entries(session_id, limit: limit)
      end

    entries
    |> Enum.map(&entry_to_message/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  将单个 Tape Entry 转换为 ReqLLM.Message。
  """
  def entry_to_message(%Entry{kind: :message, payload: payload}) do
    role = Map.get(payload, :role) || Map.get(payload, "role")
    content = Map.get(payload, :content) || Map.get(payload, "content")

    case role do
      "system" -> ReqLLM.Context.system(content)
      "user" -> ReqLLM.Context.user(content)
      "assistant" -> ReqLLM.Context.assistant(content)
      _ -> nil
    end
  end

  def entry_to_message(%Entry{kind: :tool_call, payload: payload}) do
    calls = Map.get(payload, :calls) || Map.get(payload, "calls") || []
    # Normalize + validate tool calls before passing to ReqLLM
    sanitized_calls =
      calls
      |> Enum.map(&normalize_tool_call/1)
      |> Enum.filter(&valid_tool_call?/1)
    
    if Enum.empty?(sanitized_calls) do
      nil
    else
      ReqLLM.Context.assistant("", tool_calls: sanitized_calls)
    end
  end

  def entry_to_message(%Entry{kind: :tool_result, payload: payload}) do
    call_id = Map.get(payload, :call_id) || Map.get(payload, "call_id")
    tool_name = Map.get(payload, :tool_name) || Map.get(payload, "tool_name")
    output = Map.get(payload, :output) || Map.get(payload, "output")

    if call_id do
      output_str = if is_binary(output), do: output, else: inspect(output)
      ReqLLM.Context.tool_result(call_id, tool_name, output_str)
    else
      nil
    end
  end

  def entry_to_message(%Entry{kind: :system}), do: nil
  def entry_to_message(%Entry{kind: :anchor}), do: nil
  def entry_to_message(_), do: nil

  # Normalize tool call structure to match ReqLLM expectations
  defp normalize_tool_call(%{"id" => id, "name" => name, "args" => args} = call)
       when is_binary(id) and is_binary(name) and is_map(args) do
    call
    |> Map.delete("args")
    |> Map.put("arguments", args)
  end

  defp normalize_tool_call(%{id: id, name: name, args: args} = call)
       when is_binary(id) and is_binary(name) and is_map(args) do
    call
    |> Map.delete(:args)
    |> Map.put(:arguments, args)
  end

  defp normalize_tool_call(call), do: call

  # Validate tool call structure
  defp valid_tool_call?(%{"id" => id, "name" => name, "arguments" => args})
       when is_binary(id) and is_binary(name) and is_map(args), do: true
  defp valid_tool_call?(%{id: id, name: name, arguments: args})
       when is_binary(id) and is_binary(name) and is_map(args), do: true
  defp valid_tool_call?(_), do: false
end

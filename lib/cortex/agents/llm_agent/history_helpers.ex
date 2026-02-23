defmodule Cortex.Agents.LLMAgent.HistoryHelpers do
  @moduledoc """
  历史消息清洗和转换辅助函数。

  提供纯函数用于：
  - 清洗和过滤历史消息
  - 转换历史条目为 LLM 消息格式
  - 确保系统提示词存在
  """

  alias Cortex.Agents.Prompts
  alias Cortex.Workspaces

  @standard_roles ["system", "user", "assistant", "tool"]

  @doc """
  清洗历史消息，过滤无效角色并转换为 LLM 消息格式。

  ## 选项
  - `:include_system?` - 是否包含 system 角色消息（默认 true）

  ## 示例
      iex> sanitize_messages([%{role: "user", content: "Hello"}], include_system?: false)
      [%ReqLLM.Message{role: :user, content: "Hello"}]
  """
  def sanitize_messages(history, opts) when is_list(history) and is_list(opts) do
    include_system? = Keyword.get(opts, :include_system?, true)

    history
    |> Enum.filter(&allowed_role?(&1, include_system?))
    |> Enum.map(&entry_to_message/1)
  end

  def sanitize_messages(_history, _opts), do: []

  @doc """
  确保消息列表中包含系统提示词。

  如果列表中没有 system 角色消息，会在开头插入默认的系统提示词。
  """
  def ensure_system_prompt(messages) when is_list(messages) do
    if Enum.any?(messages, &(&1.role == :system)) do
      messages
    else
      system_prompt = Prompts.build_system_prompt(workspace_root: Workspaces.workspace_root())
      [ReqLLM.Context.system(system_prompt) | messages]
    end
  end

  # Private functions

  defp allowed_role?(msg, include_system?) when is_map(msg) do
    role = get_role(msg)
    role in @standard_roles and (include_system? or role != "system")
  end

  defp allowed_role?(_msg, _include_system?), do: false

  defp entry_to_message(msg) when is_map(msg) do
    role = get_role(msg)
    content = get_content(msg)

    case role do
      "system" ->
        ReqLLM.Context.system(content)

      "user" ->
        ReqLLM.Context.user(content)

      "assistant" ->
        case get_tool_calls(msg) do
          nil -> ReqLLM.Context.assistant(content)
          tool_calls -> ReqLLM.Context.assistant(content, tool_calls: tool_calls)
        end

      "tool" ->
        tool_name = Map.get(msg, :name, Map.get(msg, "name", ""))
        call_id = get_tool_call_id(msg) || "unknown_#{:erlang.unique_integer([:positive])}"
        ReqLLM.Context.tool_result(call_id, tool_name, content)

      _ ->
        ReqLLM.Context.user(content)
    end
  end

  defp get_role(msg) when is_map(msg) do
    msg
    |> Map.get(:role, Map.get(msg, "role", ""))
    |> to_string()
  end

  defp get_content(msg) when is_map(msg) do
    msg
    |> Map.get(:content, Map.get(msg, "content", ""))
    |> content_to_string()
  end

  defp content_to_string(nil), do: ""
  defp content_to_string(content) when is_binary(content), do: content

  defp content_to_string(content) when is_list(content) do
    content
    |> Enum.map(&content_part_to_string/1)
    |> Enum.join("")
  end

  defp content_to_string(content), do: inspect(content)

  defp content_part_to_string(%{text: text}) when is_binary(text), do: text
  defp content_part_to_string(%{"text" => text}) when is_binary(text), do: text
  defp content_part_to_string(text) when is_binary(text), do: text
  defp content_part_to_string(other), do: inspect(other)

  defp get_tool_calls(msg) when is_map(msg) do
    Map.get(msg, :tool_calls) || Map.get(msg, "tool_calls")
  end

  defp get_tool_call_id(msg) when is_map(msg) do
    Map.get(msg, :tool_call_id) || Map.get(msg, "tool_call_id")
  end
end

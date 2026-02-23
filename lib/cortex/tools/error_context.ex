defmodule Cortex.Tools.ErrorContext do
  @moduledoc """
  格式化工具错误为结构化的上下文块，供 LLM 理解和处理。
  """

  @doc """
  格式化错误为结构化的 [TOOL_ERROR] 块。

  ## 参数
  - tool_name: 工具名称
  - reason: 错误原因（atom 或 string）
  - opts: 可选参数
    - elapsed_ms: 执行耗时（毫秒）
    - hint: 自定义提示信息

  ## 返回
  格式化的错误字符串，包含分类、原因和建议。
  """
  def format(tool_name, reason, opts \\ []) do
    elapsed_ms = Keyword.get(opts, :elapsed_ms, 0)
    custom_hint = Keyword.get(opts, :hint)

    {category, hint} = categorize_error(reason, tool_name)
    final_hint = custom_hint || hint

    """
    [TOOL_ERROR]
    Tool: #{tool_name}
    Category: #{category}
    Reason: #{format_reason(reason)}
    Elapsed: #{elapsed_ms}ms
    Hint: #{final_hint}
    """
  end

  defp categorize_error(:tool_not_found, tool_name) do
    {"NOT_FOUND", "Tool '#{tool_name}' is not registered. Check available tools with list_tools."}
  end

  defp categorize_error({:permission_denied, _req_id}, _tool_name) do
    {"PERMISSION_DENIED", "This operation requires user approval. Waiting for permission..."}
  end

  defp categorize_error(:timeout, _tool_name) do
    {"TIMEOUT", "Tool execution exceeded time limit. Consider breaking down the task."}
  end

  defp categorize_error({:exit, reason}, _tool_name) do
    {"CRASH", "Tool process crashed: #{inspect(reason)}. This may indicate a bug in the tool."}
  end

  defp categorize_error(:enoent, _tool_name) do
    {"FILE_NOT_FOUND", "File or directory does not exist. Verify the path is correct."}
  end

  defp categorize_error(:eacces, _tool_name) do
    {"ACCESS_DENIED", "Permission denied. Check file/directory permissions."}
  end

  defp categorize_error({:invalid_args, details}, _tool_name) do
    {"INVALID_ARGS", "Invalid arguments: #{inspect(details)}. Check tool documentation."}
  end

  defp categorize_error(reason, _tool_name) when is_binary(reason) do
    {"EXECUTION_ERROR", reason}
  end

  defp categorize_error(reason, _tool_name) do
    {"UNKNOWN_ERROR", "Unexpected error occurred. Raw reason: #{inspect(reason)}"}
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason, limit: :infinity, printable_limit: :infinity)
end

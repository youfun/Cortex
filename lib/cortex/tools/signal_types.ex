defmodule Cortex.Tools.SignalTypes do
  @moduledoc """
  工具系统信号类型常量定义。

  信号类型命名规则：
  - `tool.call.<tool_name>`   - 工具调用请求
  - `tool.result.<tool_name>` - 工具执行结果
  - `tool.error.<tool_name>`  - 工具执行错误
  - `tool.stream.<tool_name>` - 工具流式输出（如 Shell）
  """

  # 工具调用
  def call_read, do: "tool.call.read"
  def call_write, do: "tool.call.write"
  def call_edit, do: "tool.call.edit"
  def call_shell, do: "tool.call.shell"

  # 工具结果
  def result_read, do: "tool.result.read"
  def result_write, do: "tool.result.write"
  def result_edit, do: "tool.result.edit"
  def result_shell, do: "tool.result.shell"

  # 流式输出
  def stream_shell, do: "tool.stream.shell"

  # 错误
  def error(tool_name), do: "tool.error.#{tool_name}"
end

defmodule Cortex.Tools.ShellInterceptor do
  @moduledoc """
  Shell 命令安全拦截器。

  作为信号中间件运行，在 tool.call.shell 信号到达执行层之前进行审查。
  对高危指令发射 permission.request 信号，等待用户授权。
  """

  require Logger

  alias Cortex.SignalCatalog
  alias Cortex.SignalHub

  # 需要审批的命令模式
  @approval_required_patterns [
    {~r/^npm\s+(install|i)(\s|$)/, "Installing npm packages"},
    {~r/^mix\s+deps\.get(\s|$)/, "Fetching Elixir dependencies"},
    {~r/^pip\s+install(\s|$)/, "Installing Python packages"},
    {~r/^git\s+(push|merge|rebase)(\s|$)/, "Git write operation"},
    {~r/^rm\s/, "Deleting files"},
    {~r/^mv\s/, "Moving/renaming files"}
  ]

  @doc """
  检查命令是否需要用户审批。

  返回值：
  - :ok - 可以直接执行
  - {:approval_required, reason} - 需要用户确认
  """
  def check(command) do
    case find_matching_pattern(command) do
      nil ->
        :ok

      pattern_description ->
        SignalHub.emit(
          SignalCatalog.permission_request(),
          %{
            provider: "system",
            event: "permission",
            action: "request",
            actor: "shell_interceptor",
            origin: %{channel: "system", client: "shell_interceptor", platform: "server"},
            command: command,
            reason: pattern_description,
            tool: "shell"
          },
          source: "/security/interceptor"
        )

        {:approval_required, pattern_description}
    end
  end

  defp find_matching_pattern(command) do
    Enum.find_value(@approval_required_patterns, fn {regex, desc} ->
      if Regex.match?(regex, command), do: desc
    end)
  end
end

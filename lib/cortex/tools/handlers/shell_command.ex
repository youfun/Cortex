defmodule Cortex.Tools.Handlers.ShellCommand do
  @moduledoc """
  Shell 工具：运行 CLI 命令。

  基于 Jido.Shell 实现，输出流实时映射为信号。

  安全机制：
  1. 路径沙盒：命令的工作目录被限制在项目根目录内
  2. 指令审查：高危指令（sudo, rm -rf /）被拦截
  3. 超时控制：默认 30 秒超时

  信号流：
  - tool.stream.shell: 实时输出（每行或每 chunk）
  - tool.result.shell: 最终结果（退出码 + 完整输出）
  """

  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Sandbox
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  require Logger

  # 高危命令黑名单
  @dangerous_commands ~w(sudo su passwd shutdown reboot halt poweroff
                          mkfs fdisk dd format)

  # 高危参数模式
  @dangerous_patterns [
    # rm -rf /
    ~r/rm\s+(-rf?|--recursive)\s+\//,
    # 写入磁盘设备
    ~r/>\s*\/dev\/sd/,
    # fork bomb
    ~r/:\(\)\{\s*:\|:\s*&\s*\};:/
  ]

  @default_timeout 30_000

  @impl true
  def execute(args, ctx) do
    case Map.get(args, :command) do
      nil ->
        {:error, "Missing required argument: command"}

      command ->
        timeout = Map.get(args, :timeout, @default_timeout)
        project_root = Map.get(ctx, :project_root, Workspaces.workspace_root())
        session_id = Map.get(ctx, :session_id)
        do_execute(command, timeout, project_root, session_id)
    end
  end

  defp do_execute(command, timeout, project_root, session_id) do
    # 1. 安全检查
    with :ok <- check_command_safety(command, session_id),
         :ok <- Cortex.Tools.ShellInterceptor.check(command) do
      # 2. 发射调用信号
      SignalHub.emit(
        "tool.call.shell",
        %{
          provider: "tool",
          event: "shell",
          action: "call",
          actor: "shell_handler",
          origin: %{
            channel: "tool",
            client: "shell_handler",
            platform: "server",
            session_id: session_id
          },
          command: command,
          timeout: timeout,
          session_id: session_id
        },
        source: "/tool/shell"
      )

      # 3. 执行命令（使用 System.cmd 或未来切换到 Jido.Shell）
      execute_command(command, project_root, timeout, session_id)
    else
      {:approval_required, reason} ->
        {:error, {:approval_required, "User approval required for: #{reason}"}}

      error ->
        error
    end
  end

  defp check_command_safety(command, session_id) do
    cmd_name = command |> String.split() |> List.first() |> String.downcase()

    cond do
      cmd_name in @dangerous_commands ->
        SignalHub.emit(
          "tool.error.shell",
          %{
            provider: "tool",
            event: "shell",
            action: "error",
            actor: "shell_handler",
            origin: %{
              channel: "tool",
              client: "shell_handler",
              platform: "server",
              session_id: session_id
            },
            command: command,
            reason: :dangerous_command
          },
          source: "/tool/shell"
        )

        {:error, {:permission_denied, "Dangerous command blocked: #{cmd_name}"}}

      Enum.any?(@dangerous_patterns, &Regex.match?(&1, command)) ->
        SignalHub.emit(
          "tool.error.shell",
          %{
            provider: "tool",
            event: "shell",
            action: "error",
            actor: "shell_handler",
            origin: %{
              channel: "tool",
              client: "shell_handler",
              platform: "server",
              session_id: session_id
            },
            command: command,
            reason: :dangerous_pattern
          },
          source: "/tool/shell"
        )

        {:error, {:permission_denied, "Dangerous command pattern detected"}}

      true ->
        :ok
    end
  end

  defp execute_command(command, project_root, timeout, session_id) do
    stream_chunk = fn chunk ->
      SignalHub.emit(
        "tool.stream.shell",
        %{
          provider: "tool",
          event: "shell",
          action: "stream",
          actor: "shell_handler",
          origin: %{
            channel: "tool",
            client: "shell_handler",
            platform: "server",
            session_id: session_id
          },
          chunk: chunk,
          session_id: session_id
        },
        source: "/tool/shell"
      )
    end

    case Sandbox.execute(command, workdir: project_root, timeout: timeout, on_chunk: stream_chunk) do
      {:ok, %{stdout: output, exit_code: exit_code}} ->
        SignalHub.emit(
          "tool.result.shell",
          %{
            provider: "tool",
            event: "shell",
            action: "result",
            actor: "shell_handler",
            origin: %{
              channel: "tool",
              client: "shell_handler",
              platform: "server",
              session_id: session_id
            },
            command: command,
            output: output,
            exit_code: exit_code,
            session_id: session_id
          },
          source: "/tool/shell"
        )

        {:ok, "Exit code: #{exit_code}\n#{output}"}

      {:ok, %{stderr: stderr}} when is_binary(stderr) and stderr != "" ->
        {:error, "Command failed: #{stderr}"}

      {:error, :timeout} ->
        {:error, "Command timed out after #{timeout}ms"}

      {:error, reason} ->
        {:error, "Command failed: #{inspect(reason)}"}
    end
  end
end

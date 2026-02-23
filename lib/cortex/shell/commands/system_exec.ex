defmodule Cortex.Shell.Commands.SystemExec do
  @moduledoc """
  Executes system commands on the host OS via Jido Shell.

  Acts as a bridge between the virtual Jido Shell session and the real OS.
  It uses the session's Current Working Directory (CWD) and Environment Variables (ENV).

  ## Usage

      sys <command> [args...]

  ## Examples

      sys git status
      sys mix test
      sys docker ps

  ## Safety

  All commands are passed through `Cortex.Tools.ShellInterceptor` for validation.
  """

  @behaviour Cortex.Shell.Command

  alias Cortex.Tools.ShellInterceptor
  alias Cortex.SignalHub
  alias Cortex.Shell.Error

  require Logger

  @impl true
  def name, do: "sys"

  @impl true
  def summary, do: "Execute a system command on the host OS"

  @impl true
  def schema do
    Zoi.map(%{
      args: Zoi.array(Zoi.string()) |> Zoi.default([])
    })
  end

  @impl true
  def run(_state, %{args: []}, _emit) do
    {:error,
     Error.shell(:invalid_usage, %{message: "No command specified. Usage: sys <cmd> [args...]"})}
  end

  def run(state, %{args: args}, emit) do
    [cmd | cmd_args] = args
    full_command_str = Enum.join(args, " ")

    # 1. Security Check
    case ShellInterceptor.check(full_command_str) do
      :ok ->
        execute_command(cmd, cmd_args, state, emit)

      {:approval_required, reason} ->
        {:error, Error.shell(:permission_denied, %{message: "Approval required: #{reason}"})}
    end
  end

  defp execute_command(cmd, args, state, emit) do
    # Resolve executable path (System.find_executable/1 is useful if cmd is not absolute)
    executable = System.find_executable(cmd)

    if is_nil(executable) do
      {:error, Error.shell(:command_not_found, %{name: cmd})}
    else
      # Prepare Environment
      env = Map.to_list(state.env || %{})

      # Prepare Options
      opts = [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        {:args, args},
        {:cd, state.cwd},
        {:env, env}
      ]

      port = Port.open({:spawn_executable, executable}, opts)

      # Signal Start
      SignalHub.emit(
        "tool.call.shell",
        %{
          provider: "system",
          event: "shell",
          action: "call",
          actor: "system_exec",
          origin: %{channel: "system", client: "system_exec", platform: "server"},
          command: cmd,
          args: args,
          cwd: state.cwd,
          # We might want the real session ID later
          session_id: "jido_shell_hybrid"
        },
        source: "/jido_shell/sys"
      )

      collect_output(port, emit)
    end
  end

  defp collect_output(port, emit) do
    receive do
      {^port, {:data, data}} ->
        # 1. Emit to Shell Session (Standard Jido.Shell behavior)
        emit.({:output, data})

        # 2. Emit to SignalHub (Real-time UI)
        SignalHub.emit(
          "tool.stream.shell",
          %{
            provider: "system",
            event: "shell",
            action: "stream",
            actor: "system_exec",
            origin: %{channel: "system", client: "system_exec", platform: "server"},
            chunk: data
          },
          source: "/jido_shell/sys"
        )

        collect_output(port, emit)

      {^port, {:exit_status, code}} ->
        SignalHub.emit(
          "tool.result.shell",
          %{
            provider: "system",
            event: "shell",
            action: "result",
            actor: "system_exec",
            origin: %{channel: "system", client: "system_exec", platform: "server"},
            exit_code: code
          },
          source: "/jido_shell/sys"
        )

        if code == 0 do
          {:ok, nil}
        else
          # In Jido Shell, non-zero exit can be treated as an error or just output.
          # Returning {:ok, nil} means the command "ran successfully" (even if it returned error code).
          # But for better agent awareness, we might want to return an error structure if critical?
          # For now, standard shell behavior is to return OK and let the user see the exit code via output/signals.
          {:ok, nil}
        end
    end
  end
end

defmodule Cortex.ProcessCase do
  @moduledoc """
  Test case for tests that require supervised processes.

  This module ensures that critical application processes are available
  during tests, either by using already-running processes from the application
  or by starting them on-demand for isolated tests.

  ## Usage

      use Cortex.ProcessCase

  ## Philosophy

  Following Phoenix best practices:
  1. Prefer using processes started by the application (test_helper.exs)
  2. Fall back to starting processes if they're not available
  3. This allows tests to work both in full suite and in isolation
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Cortex.ProcessCase
    end
  end

  setup tags do
    # Ensure required processes are available
    unless tags[:skip_processes] do
      ensure_test_processes()
    end

    :ok
  end

  @doc """
  Ensures that required processes are running.

  If processes are already started by the application, use them.
  Otherwise, start them for this test.
  """
  def ensure_test_processes do
    # SignalHub (signal bus)
    ensure_process_running(
      :cortex_bus,
      {Jido.Signal.Bus, [name: :cortex_bus]},
      "SignalHub"
    )

    # Tools.Registry
    ensure_process_running(
      Cortex.Tools.Registry,
      Cortex.Tools.Registry,
      "Tools.Registry"
    )

    # History.Tape.Store
    ensure_process_running(
      Cortex.History.Tape.Store,
      Cortex.History.Tape.Store,
      "History.Tape.Store"
    )

    # PermissionTracker
    ensure_process_running(
      Cortex.Core.PermissionTracker,
      Cortex.Core.PermissionTracker,
      "PermissionTracker"
    )

    # Memory processes
    ensure_process_running(
      Cortex.Memory.Store,
      Cortex.Memory.Store,
      "Memory.Store"
    )

    ensure_process_running(
      Cortex.Memory.WorkingMemory,
      Cortex.Memory.WorkingMemory,
      "Memory.WorkingMemory"
    )

    ensure_process_running(
      Cortex.Memory.Subconscious,
      Cortex.Memory.Subconscious,
      "Memory.Subconscious"
    )

    ensure_process_running(
      Cortex.Memory.Preconscious,
      Cortex.Memory.Preconscious,
      "Memory.Preconscious"
    )

    ensure_process_running(
      Cortex.Memory.Consolidator,
      Cortex.Memory.Consolidator,
      "Memory.Consolidator"
    )

    ensure_process_running(
      Cortex.Memory.ReflectionProcessor,
      Cortex.Memory.ReflectionProcessor,
      "Memory.ReflectionProcessor"
    )

    # Extensions
    ensure_process_running(
      Cortex.Extensions.HookRegistry,
      Cortex.Extensions.HookRegistry,
      "Extensions.HookRegistry"
    )

    ensure_process_running(
      Cortex.Extensions.Manager,
      Cortex.Extensions.Manager,
      "Extensions.Manager"
    )

    # TTS
    ensure_process_running(
      Cortex.TTS.NodeManager,
      Cortex.TTS.NodeManager,
      "TTS.NodeManager"
    )

    # Registries & supervisors
    ensure_process_running(
      Cortex.Registry,
      {Registry, keys: :unique, name: Cortex.Registry},
      "Registry"
    )

    ensure_process_running(
      Cortex.SessionRegistry,
      {Registry, keys: :unique, name: Cortex.SessionRegistry},
      "SessionRegistry"
    )

    ensure_process_running(
      Cortex.SessionSupervisor,
      {DynamicSupervisor, name: Cortex.SessionSupervisor, strategy: :one_for_one},
      "SessionSupervisor"
    )

    ensure_process_running(
      Cortex.AgentTaskSupervisor,
      {Task.Supervisor, name: Cortex.AgentTaskSupervisor},
      "AgentTaskSupervisor"
    )

    :ok
  end

  defp ensure_process_running(name, child_spec, _description) do
    # Try to start the process if it's not already running
    # If Process.whereis returns a PID, the process is running
    # If it returns nil, we try to start it
    # If start_supervised! fails with "already_started", we ignore it
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        try do
          start_supervised!(child_spec)
          :ok
        rescue
          RuntimeError ->
            # The process might be started but not yet registered
            # Wait a bit and check again
            Process.sleep(10)

            case Process.whereis(name) do
              pid when is_pid(pid) -> :ok
              # Ignore - process might be started under different supervision
              nil -> :ok
            end
        end
    end
  end

  @doc """
  Starts additional processes on demand for specific tests.

  ## Examples

      setup do
        start_additional_processes([
          Cortex.Memory.Store,
          Cortex.Memory.WorkingMemory
        ])
        :ok
      end
  """
  def start_additional_processes(process_specs) when is_list(process_specs) do
    Enum.each(process_specs, fn spec ->
      # Only start if not already running
      name = extract_process_name(spec)

      case name && Process.whereis(name) do
        nil -> start_supervised!(spec)
        _pid -> :ok
      end
    end)

    :ok
  end

  defp extract_process_name({module, opts}) when is_list(opts) do
    Keyword.get(opts, :name, module)
  end

  defp extract_process_name(module) when is_atom(module), do: module
  defp extract_process_name(_), do: nil
end

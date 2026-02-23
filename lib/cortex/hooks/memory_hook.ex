defmodule Cortex.Hooks.MemoryHook do
  @moduledoc """
  Memory integration hook.

  Bridges the Agent lifecycle with the Memory subsystem:
  - on_input: sets WorkingMemory focus from user message
  - before_tool_call: adds curiosity to WorkingMemory
  - on_tool_result: records concerns on tool errors
  - on_agent_end: triggers lightweight memory extraction via Subconscious
  """

  @behaviour Cortex.Agents.Hook

  require Logger

  alias Cortex.Memory.WorkingMemory

  # === on_input: set focus ===

  @impl true
  def on_input(agent_state, message) when is_binary(message) do
    safe_set_focus(message)
    {:continue, message, agent_state}
  end

  def on_input(agent_state, message), do: {:continue, message, agent_state}

  # === before_tool_call: add curiosity ===

  @impl true
  def before_tool_call(agent_state, call_data) do
    tool_name = call_data[:name] || call_data["name"]
    args = call_data[:args] || call_data["args"] || %{}

    curiosity =
      case tool_name do
        "read_file" -> "Reading: #{args["path"] || args[:path]}"
        "read_file_structure" -> "Exploring structure: #{args["path"] || args[:path]}"
        "write_file" -> "Writing: #{args["path"] || args[:path]}"
        "edit_file" -> "Editing: #{args["path"] || args[:path]}"
        "shell" -> "Running: #{truncate(args["command"] || args[:command] || "", 80)}"
        _ -> nil
      end

    if curiosity, do: safe_add_curiosity(curiosity)

    {:ok, call_data, agent_state}
  end

  # === on_tool_result: record concerns on errors ===

  @impl true
  def on_tool_result(agent_state, result_data) do
    output = result_data[:output] || ""

    if error_output?(output) do
      concern = "Tool error: #{truncate(to_string(output), 120)}"
      safe_add_concern(concern)
    end

    {:ok, result_data, agent_state}
  end

  # === on_agent_end: notify for memory extraction ===
  # Note: behaviour defines on_agent_end/2 but HookRunner.run_notify calls with arity 1

  @impl true
  def on_agent_end(agent_state, _data) do
    on_agent_end(agent_state)
  end

  def on_agent_end(agent_state) do
    session_id = agent_state.session_id

    # Clear focus when agent finishes a run — set to empty string (not nil)
    safe_call(fn -> WorkingMemory.set_focus("(idle)") end)

    Logger.debug("[MemoryHook] Agent run ended for #{session_id}")
    :ok
  end

  # Private helpers

  defp safe_set_focus(content) when is_binary(content) and byte_size(content) > 0 do
    preview = truncate(content, 200)
    safe_call(fn -> WorkingMemory.set_focus(preview) end)
  end

  defp safe_set_focus(_), do: :ok

  defp safe_add_curiosity(content) do
    safe_call(fn -> WorkingMemory.add_curiosity(content) end)
  end

  defp safe_add_concern(content) do
    safe_call(fn -> WorkingMemory.add_concern(content) end)
  end

  defp safe_call(fun) do
    case Process.whereis(Cortex.Memory.WorkingMemory) do
      nil -> :ok
      _pid -> try do fun.() rescue _ -> :ok end
    end
  end

  defp error_output?(output) when is_binary(output) do
    String.contains?(output, ["Error:", "error:", "** (", "FAILED", "Permission denied"])
  end

  defp error_output?(_), do: false

  defp truncate(str, max) when is_binary(str) and byte_size(str) > max do
    String.slice(str, 0, max) <> "..."
  end

  defp truncate(str, _max) when is_binary(str), do: str
  defp truncate(_, _), do: ""
end

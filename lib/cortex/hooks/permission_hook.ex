defmodule Cortex.Hooks.PermissionHook do
  @behaviour Cortex.Agents.Hook

  require Logger

  @impl true
  def before_tool_call(agent_state, call_data) do
    # Check if permission is already granted via metadata
    # The flag :_permission_granted will be set by the agent when retrying
    if Map.get(call_data, :_permission_granted) do
      {:ok, call_data, agent_state}
    else
      action = permission_action(call_data)

      if action in [:write, :execute] do
        req_id = Ecto.UUID.generate()

        Logger.info(
          "Permission required for tool #{call_data.name} (action: #{action}) req_id: #{req_id}"
        )

        # Halt execution and return the permission requirement
        {:halt, {:permission_required, req_id, call_data}, agent_state}
      else
        {:ok, call_data, agent_state}
      end
    end
  end

  defp permission_action(call_data) do
    case call_data.name do
      "edit_file" -> :write
      "write_file" -> :write
      "delete_file" -> :write
      "run_command" -> :execute
      _ -> :read
    end
  end
end

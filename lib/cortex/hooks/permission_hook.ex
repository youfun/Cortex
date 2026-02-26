defmodule Cortex.Hooks.PermissionHook do
  @behaviour Cortex.Agents.Hook

  alias Cortex.Core.Security
  alias Cortex.Workspaces

  require Logger

  @impl true
  def before_tool_call(agent_state, call_data) do
    if Map.get(call_data, :_permission_granted) do
      {:ok, call_data, agent_state}
    else
      action = permission_action(call_data)

      cond do
        action == :read ->
          {:ok, call_data, agent_state}

        action == :write and path_within_workspace?(call_data) ->
          {:ok, call_data, agent_state}

        action in [:write, :execute] ->
          req_id = Ecto.UUID.generate()

          Logger.info(
            "Permission required for tool #{call_data.name} (action: #{action}) req_id: #{req_id}"
          )

          {:halt, {:permission_required, req_id, call_data}, agent_state}

        true ->
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

  defp path_within_workspace?(call_data) do
    args = call_data[:args] || call_data["args"] || %{}
    path = Map.get(args, "path") || Map.get(args, :path)

    if is_binary(path) do
      root = Workspaces.workspace_root()
      match?({:ok, _}, Security.validate_path(path, root, log_violations: false))
    else
      false
    end
  end
end

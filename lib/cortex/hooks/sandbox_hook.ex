defmodule Cortex.Hooks.SandboxHook do
  @behaviour Cortex.Agents.Hook

  alias Cortex.Core.Security
  alias Cortex.Workspaces
  require Logger

  @impl true
  def before_tool_call(agent_state, call_data) do
    args = call_data.args || %{}
    path = Map.get(args, "path") || Map.get(args, :path)

    if is_binary(path) do
      # Validate
      root = Workspaces.workspace_root()

      case Security.validate_path(path, root) do
        {:ok, _safe_path} ->
          {:ok, call_data, agent_state}

        {:error, reason} ->
          Logger.warning("Sandbox violation for tool #{call_data.name}: #{inspect(reason)}")
          {:halt, {:error, "Sandbox violation: #{inspect(reason)}"}, agent_state}
      end
    else
      {:ok, call_data, agent_state}
    end
  end
end

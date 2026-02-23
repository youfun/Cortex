defmodule Cortex.Tools.Handlers.EditFile do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Core.Security
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  @impl true
  def execute(args, ctx) do
    path = get_arg(args, :path)
    old_string = get_arg(args, :old_string)
    new_string = get_arg(args, :new_string)

    cond do
      is_nil(path) ->
        {:error, "Missing required argument: path"}

      is_nil(old_string) ->
        {:error, "Missing required argument: old_string"}

      is_nil(new_string) ->
        {:error, "Missing required argument: new_string"}

      true ->
        project_root = Map.get(ctx, :project_root, Workspaces.workspace_root())
        do_execute(path, old_string, new_string, project_root, ctx)
    end
  end

  defp do_execute(path, old_string, new_string, project_root, ctx) do
    agent_id = Map.get(ctx, :agent_id)

    with {:ok, safe_path} <- Security.validate_path_with_folders(path, project_root, agent_id: agent_id),
         {:ok, content} <- File.read(safe_path) do
      if String.contains?(content, old_string) do
        new_content = String.replace(content, old_string, new_string, global: false)
        File.write!(safe_path, new_content)

        # 发射文件变更信号
        SignalHub.emit(
          "file.changed.edit",
          %{
            provider: "tool",
            event: "file",
            action: "changed",
            actor: "edit_file_handler",
            origin: %{
              channel: "tool",
              client: "edit_file_handler",
              platform: "server",
              session_id: Map.get(ctx, :session_id)
            },
            path: path,
            old_string_preview: String.slice(old_string, 0, 100),
            new_string_preview: String.slice(new_string, 0, 100),
            session_id: Map.get(ctx, :session_id)
          },
          source: "/tool/edit"
        )

        {:ok, "Successfully edited #{path}"}
      else
        {:error, "old_string not found in #{path}. Read the file first to get exact content."}
      end
    else
      {:error, reason} when reason in [:path_escapes_boundary, :path_outside_boundary] ->
        {:error, {:permission_denied, reason}}

      {:error, :path_not_authorized} ->
        {:error, {:permission_denied, "Path not in authorized folders: #{path}"}}

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Failed to read #{path}: #{inspect(reason)}"}
    end
  end

  defp get_arg(args, key) when is_atom(key) do
    Map.get(args, key) || Map.get(args, Atom.to_string(key))
  end
end

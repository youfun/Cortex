defmodule Cortex.Tools.Handlers.WriteFile do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Core.Security
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  @impl true
  def execute(args, ctx) do
    path = Map.get(args, :path)
    content = Map.get(args, :content)

    cond do
      is_nil(path) ->
        {:error, "Missing required argument: path"}

      is_nil(content) ->
        {:error, "Missing required argument: content"}

      true ->
        project_root = Map.get(ctx, :project_root, Workspaces.workspace_root())
        do_execute(path, content, project_root, ctx)
    end
  end

  defp do_execute(path, content, project_root, ctx) do
    agent_id = Map.get(ctx, :agent_id)

    with {:ok, safe_path} <- Security.validate_path_with_folders(path, project_root, agent_id: agent_id) do
      # 确保目录存在
      safe_path |> Path.dirname() |> File.mkdir_p!()

      case File.write(safe_path, content) do
        :ok ->
          # 发射文件变更信号（UI 编辑器组件订阅此信号）
          SignalHub.emit(
            "file.changed.write",
            %{
              provider: "tool",
              event: "file",
              action: "changed",
              actor: "write_file_handler",
              origin: %{
                channel: "tool",
                client: "write_file_handler",
                platform: "server",
                session_id: Map.get(ctx, :session_id)
              },
              path: path,
              bytes: byte_size(content),
              session_id: Map.get(ctx, :session_id)
            },
            source: "/tool/write"
          )

          {:ok, "Successfully wrote #{byte_size(content)} bytes to #{path}"}

        {:error, reason} ->
          SignalHub.emit(
            "tool.error.write",
            %{
              provider: "tool",
              event: "file",
              action: "write_error",
              actor: "write_file_handler",
              origin: %{
                channel: "tool",
                client: "write_file_handler",
                platform: "server",
                session_id: Map.get(ctx, :session_id)
              },
              path: path,
              reason: reason,
              session_id: Map.get(ctx, :session_id)
            },
            source: "/tool/write"
          )

          {:error, "Failed to write #{path}: #{inspect(reason)}"}
      end
    else
      {:error, :path_escapes_boundary} ->
        {:error, {:permission_denied, "Path escapes project boundary: #{path}"}}

      {:error, :path_not_authorized} ->
        {:error, {:permission_denied, "Path not in authorized folders: #{path}"}}
    end
  end
end

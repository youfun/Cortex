defmodule Cortex.Tools.Handlers.ReadFile do
  @moduledoc """
  Read 工具：读取文件内容。

  信号流：
  1. 接收 tool.call.read 信号
  2. 执行读取
  3. 发射 tool.result.read 信号
  """

  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Core.Security
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  @impl true
  def execute(args, ctx) do
    case Map.get(args, :path) do
      nil ->
        {:error, "Missing required argument: path"}

      path ->
        project_root = Map.get(ctx, :project_root, Workspaces.workspace_root())
        do_execute(path, project_root, ctx)
    end
  end

  defp do_execute(path, project_root, ctx) do
    agent_id = Map.get(ctx, :agent_id)

    with {:ok, safe_path} <- Security.validate_path_with_folders(path, project_root, agent_id: agent_id),
         {:ok, content} <- File.read(safe_path) do
      # 发射成功信号
      SignalHub.emit(
        "tool.result.read",
        %{
          provider: "tool",
          event: "file",
          action: "read",
          actor: "read_file_handler",
          origin: %{
            channel: "tool",
            client: "read_file_handler",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          path: path,
          content: content,
          bytes: byte_size(content),
          session_id: Map.get(ctx, :session_id)
        },
        source: "/tool/read"
      )

      {:ok, content}
    else
      {:error, reason} when reason in [:path_escapes_boundary, :path_outside_boundary] ->
        SignalHub.emit(
          "tool.error.read",
          %{
            provider: "tool",
            event: "file",
            action: "read_error",
            actor: "read_file_handler",
            origin: %{
              channel: "tool",
              client: "read_file_handler",
              platform: "server",
              session_id: Map.get(ctx, :session_id)
            },
            path: path,
            reason: reason,
            session_id: Map.get(ctx, :session_id)
          },
          source: "/tool/read"
        )

        {:error, {:permission_denied, reason}}

      {:error, :path_not_authorized} ->
        SignalHub.emit(
          "tool.error.read",
          %{
            provider: "tool",
            event: "file",
            action: "read_error",
            actor: "read_file_handler",
            origin: %{
              channel: "tool",
              client: "read_file_handler",
              platform: "server",
              session_id: Map.get(ctx, :session_id)
            },
            path: path,
            reason: :path_not_authorized,
            session_id: Map.get(ctx, :session_id)
          },
          source: "/tool/read"
        )

        {:error, {:permission_denied, "Path not in authorized folders: #{path}"}}

      {:error, :enoent} ->
        SignalHub.emit(
          "tool.error.read",
          %{
            provider: "tool",
            event: "file",
            action: "read_error",
            actor: "read_file_handler",
            origin: %{
              channel: "tool",
              client: "read_file_handler",
              platform: "server",
              session_id: Map.get(ctx, :session_id)
            },
            path: path,
            reason: :enoent,
            session_id: Map.get(ctx, :session_id)
          },
          source: "/tool/read"
        )

        {:error, "no such file: #{path}"}

      {:error, reason} ->
        SignalHub.emit(
          "tool.error.read",
          %{
            provider: "tool",
            event: "file",
            action: "read_error",
            actor: "read_file_handler",
            origin: %{
              channel: "tool",
              client: "read_file_handler",
              platform: "server",
              session_id: Map.get(ctx, :session_id)
            },
            path: path,
            reason: reason,
            session_id: Map.get(ctx, :session_id)
          },
          source: "/tool/read"
        )

        {:error, "Failed to read file #{path}: #{inspect(reason)}"}
    end
  end
end

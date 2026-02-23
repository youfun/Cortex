defmodule Cortex.Tools.Handlers.BccExtract do
  @moduledoc """
  BCC Extract 工具：从源码提取 FileRecord JSON（AST 结构）。

  信号流：
  1. 接收 tool.call.bcc_extract 信号
  2. 执行 `bcc extract`
  3. 发射 tool.result.bcc_extract 信号
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
        mode = Map.get(args, :mode, "ast")
        project_root = Map.get(ctx, :project_root, Workspaces.workspace_root())
        do_execute(path, mode, project_root, ctx)
    end
  end

  defp do_execute(path, mode, project_root, ctx) do
    with {:ok, safe_path} <- Security.validate_path(path, project_root) do
      bcc_bin = Path.join([File.cwd!(), "priv", "bin", "bcc"])

      if File.exists?(bcc_bin) do
        cmd_args = ["extract", safe_path, "--mode", mode]

        case System.cmd(bcc_bin, cmd_args, stderr_to_stdout: true) do
          {output, 0} ->
            SignalHub.emit(
              "tool.result.bcc_extract",
              %{
                provider: "tool",
                event: "code",
                action: "extract",
                actor: "bcc_extract_handler",
                origin: %{
                  channel: "tool",
                  client: "bcc_extract_handler",
                  platform: "server",
                  session_id: Map.get(ctx, :session_id)
                },
                path: path,
                mode: mode,
                content: output,
                session_id: Map.get(ctx, :session_id)
              },
              source: "/tool/bcc_extract"
            )

            {:ok, output}

          {output, _status} ->
            {:error, "BCC extract failed: #{output}"}
        end
      else
        {:error, "BCC binary not found at #{bcc_bin}"}
      end
    else
      {:error, reason} ->
        {:error, {:permission_denied, reason}}
    end
  end
end

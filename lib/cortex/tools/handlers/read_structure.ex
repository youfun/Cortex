defmodule Cortex.Tools.Handlers.ReadStructure do
  @moduledoc """
  ReadStructure 工具：提取代码文件的结构摘要（AST 解析 + 正则降级）。

  用于 Token 优化——返回模块、函数签名、类型定义等，不包含函数体实现。

  信号流：
  1. 接收 tool.call.read_structure 信号
  2. 执行结构提取
  3. 发射 tool.result.read_structure 信号
  """

  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Core.Security
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  alias Cortex.Tools.Handlers.ReadStructure.ElixirParser
  alias Cortex.Tools.Handlers.ReadStructure.FallbackParser
  alias Cortex.Tools.Handlers.ReadStructure.GoParser
  alias Cortex.Tools.Handlers.ReadStructure.JsParser
  alias Cortex.Tools.Handlers.ReadStructure.PythonParser
  alias Cortex.Tools.Handlers.ReadStructure.RustParser

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
    with {:ok, safe_path} <- Security.validate_path(path, project_root),
         {:ok, content} <- File.read(safe_path) do
      structure = extract_structure(safe_path, content)

      SignalHub.emit(
        "tool.result.read_structure",
        %{
          provider: "tool",
          event: "file",
          action: "read_structure",
          actor: "read_structure_handler",
          origin: %{
            channel: "tool",
            client: "read_structure_handler",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          path: path,
          structure: structure,
          bytes: byte_size(structure),
          session_id: Map.get(ctx, :session_id)
        },
        source: "/tool/read_structure"
      )

      {:ok, structure}
    else
      {:error, reason} when reason in [:path_escapes_boundary, :path_outside_boundary] ->
        emit_error(ctx, path, reason)
        {:error, {:permission_denied, reason}}

      {:error, :enoent} ->
        emit_error(ctx, path, :enoent)
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        emit_error(ctx, path, reason)
        {:error, "Failed to read file #{path}: #{inspect(reason)}"}
    end
  end

  defp extract_structure(path, content) do
    cond do
      String.ends_with?(path, [".ex", ".exs"]) ->
        ElixirParser.extract(content)

      String.ends_with?(path, [".js", ".jsx", ".ts", ".tsx"]) ->
        JsParser.extract(content)

      String.ends_with?(path, ".rs") ->
        RustParser.extract(content)

      String.ends_with?(path, ".py") ->
        PythonParser.extract(content)

      String.ends_with?(path, ".go") ->
        GoParser.extract(content)

      true ->
        FallbackParser.extract(content, path)
    end
  end

  defp emit_error(ctx, path, reason) do
    SignalHub.emit(
      "tool.error.read_structure",
      %{
        provider: "tool",
        event: "file",
        action: "read_structure_error",
        actor: "read_structure_handler",
        origin: %{
          channel: "tool",
          client: "read_structure_handler",
          platform: "server",
          session_id: Map.get(ctx, :session_id)
        },
        path: path,
        reason: reason,
        session_id: Map.get(ctx, :session_id)
      },
      source: "/tool/read_structure"
    )
  end
end

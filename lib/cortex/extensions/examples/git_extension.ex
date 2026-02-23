defmodule Cortex.Extensions.Examples.GitExtension do
  @moduledoc """
  Git Extension - 提供 Git 操作工具

  功能：
  - git_status: 查看仓库状态
  - git_diff: 查看文件差异
  - git_log: 查看提交历史

  使用方法：
  ```elixir
  # 加载 Extension
  Cortex.Extensions.Manager.load(Cortex.Extensions.Examples.GitExtension)

  # 在对话中使用
  # "Show me the git status"
  # "What changed in the last commit?"
  ```
  """

  @behaviour Cortex.Extensions.Extension

  require Logger

  @impl true
  def init(_config) do
    # 验证 git 是否可用
    case System.cmd("git", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("[GitExtension] Git available: #{String.trim(output)}")
        {:ok, %{git_available: true}}

      {error, _} ->
        Logger.error("[GitExtension] Git not found: #{error}")
        {:error, :git_not_available}
    end
  end

  @impl true
  def name, do: "GitExtension"

  @impl true
  def description, do: "Git operations integration for Cortex"

  @impl true
  def tools do
    [
      %Cortex.Tools.Tool{
        name: "git_status",
        description:
          "Get the current git repository status, showing modified, staged, and untracked files",
        parameters: [],
        module: __MODULE__.Tools.GitStatus
      },
      %Cortex.Tools.Tool{
        name: "git_diff",
        description: "Show changes in files. Can show staged or unstaged changes.",
        parameters: [
          file: [
            type: :string,
            required: false,
            doc: "Specific file to show diff for (optional)"
          ],
          staged: [
            type: :boolean,
            required: false,
            doc: "Show staged changes (default: false, shows unstaged)"
          ]
        ],
        module: __MODULE__.Tools.GitDiff
      },
      %Cortex.Tools.Tool{
        name: "git_log",
        description: "Show commit history",
        parameters: [
          count: [
            type: :integer,
            required: false,
            doc: "Number of commits to show (default: 10)"
          ],
          oneline: [
            type: :boolean,
            required: false,
            doc: "Show one line per commit (default: true)"
          ]
        ],
        module: __MODULE__.Tools.GitLog
      }
    ]
  end

  # ===== 工具实现 =====

  defmodule Tools.GitStatus do
    @moduledoc """
    获取 Git 仓库状态
    """

    def execute(_args) do
      workspace_root = Cortex.Workspaces.workspace_root()

      case System.cmd("git", ["status", "--short"], cd: workspace_root, stderr_to_stdout: true) do
        {output, 0} ->
          if String.trim(output) == "" do
            {:ok, "Working tree clean - no changes"}
          else
            {:ok, "Git status:\n#{output}"}
          end

        {error, _} ->
          {:error, "Git status failed: #{error}"}
      end
    end
  end

  defmodule Tools.GitDiff do
    @moduledoc """
    显示文件差异
    """

    def execute(args) do
      workspace_root = Cortex.Workspaces.workspace_root()
      file = Map.get(args, "file")
      staged = Map.get(args, "staged", false)

      git_args =
        if staged do
          ["diff", "--cached"]
        else
          ["diff"]
        end

      git_args = if file, do: append_one(git_args, file), else: git_args

      case System.cmd("git", git_args, cd: workspace_root, stderr_to_stdout: true) do
        {output, 0} ->
          if String.trim(output) == "" do
            {:ok, "No changes to show"}
          else
            # 限制输出长度避免 token 过多
            truncated = String.slice(output, 0, 5000)
            suffix = if String.length(output) > 5000, do: "\n\n... (truncated)", else: ""
            {:ok, "Git diff:\n```\n#{truncated}#{suffix}\n```"}
          end

        {error, _} ->
          {:error, "Git diff failed: #{error}"}
      end
    end

    defp append_one(list, item) do
      list
      |> Enum.reverse()
      |> then(&[item | &1])
      |> Enum.reverse()
    end
  end

  defmodule Tools.GitLog do
    @moduledoc """
    显示提交历史
    """

    def execute(args) do
      workspace_root = Cortex.Workspaces.workspace_root()
      count = Map.get(args, "count", 10)
      oneline = Map.get(args, "oneline", true)

      git_args =
        if oneline do
          ["log", "--oneline", "-#{count}"]
        else
          ["log", "-#{count}"]
        end

      case System.cmd("git", git_args, cd: workspace_root, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, "Git log (last #{count} commits):\n#{output}"}

        {error, _} ->
          {:error, "Git log failed: #{error}"}
      end
    end
  end
end

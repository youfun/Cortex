defmodule Cortex.Utils.FileUtils do
  @moduledoc """
  Utility functions for file operations.
  """
  require Logger

  @doc """
  Generates a file tree text representation of the given project path.
  Uses git ls-files if available, falling back to recursive glob.
  """
  def get_file_tree(project_path) do
    # 优先使用 git ls-files
    case System.cmd("git", ["ls-files", "--cached", "--others", "--exclude-standard"],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        files = String.split(output, "
", trim: true)
        tree = build_tree_text(files, project_path)
        {:ok, tree}

      _ ->
        # 回退到 glob
        Logger.warning(
          "[FileUtils] git is not available or failed, falling back to glob scanning"
        )

        files =
          project_path
          |> Path.join("**/*")
          |> Path.wildcard()
          |> Enum.filter(&File.regular?/1)
          |> Enum.map(&Path.relative_to(&1, project_path))

        tree = build_tree_text(files, project_path)
        {:ok, tree}
    end
  end

  defp build_tree_text(files, project_path) do
    files
    |> Enum.take(500)
    |> Enum.map_join(
      "
",
      fn path ->
        full_path = Path.join(project_path, path)

        size =
          case File.stat(full_path) do
            {:ok, %{size: s}} -> "(#{Float.round(s / 1024, 1)}KB)"
            _ -> ""
          end

        "  - #{path} #{size}"
      end
    )
  end
end

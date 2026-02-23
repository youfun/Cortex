defmodule Cortex.Memory do
  @moduledoc """
  Persistent memory loader.
  """

  @global_memory_path "MEMORY.md"

  def load_memory(workspace_root, workspace_id \\ nil) do
    global = read_memory(Path.join(workspace_root, @global_memory_path))

    workspace =
      case workspace_id do
        nil -> ""
        id -> read_memory(Path.join(workspace_root, "workspaces/#{id}/MEMORY.md"))
      end

    build_section(global, workspace)
  end

  def update_memory(workspace_root, level, content, workspace_id \\ nil)
      when level in [:global, :workspace] do
    path =
      case level do
        :global ->
          Path.join(workspace_root, @global_memory_path)

        :workspace ->
          Path.join(workspace_root, "workspaces/#{workspace_id}/MEMORY.md")
      end

    path |> Path.dirname() |> File.mkdir_p!()
    File.write(path, content)
  end

  defp read_memory(path) do
    case File.read(path) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> ""
    end
  end

  defp build_section(global, workspace) do
    parts =
      [
        if(global != "", do: "### Global Preferences\n" <> global, else: nil),
        if(workspace != "", do: "### Project Context\n" <> workspace, else: nil)
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> ""
      _ -> "## Your Memory\n" <> Enum.join(parts, "\n\n")
    end
  end
end

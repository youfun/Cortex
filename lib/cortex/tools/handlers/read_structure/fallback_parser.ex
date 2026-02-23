defmodule Cortex.Tools.Handlers.ReadStructure.FallbackParser do
  @moduledoc false

  @default_preview_lines 50

  def extract(content, path) do
    lines = String.split(content, "\n")
    preview = Enum.take(lines, @default_preview_lines)
    total_lines = length(lines)
    file_size = byte_size(content)

    """
    [Unsupported File Type - Preview Only]

    File: #{path}
    Size: #{file_size} bytes
    Lines: #{total_lines}

    Preview (first #{@default_preview_lines} lines):
    ---
    #{Enum.join(preview, "\n")}
    ---

    Note: This file type does not support structured extraction.
    Use read_file to get full content if needed.
    """
  end
end

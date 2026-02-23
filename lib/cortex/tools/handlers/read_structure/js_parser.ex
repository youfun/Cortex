defmodule Cortex.Tools.Handlers.ReadStructure.JsParser do
  @moduledoc false

  @patterns [
    ~r/^export\s+(default\s+)?(function|class|const|let|var|interface|type|enum)\s+(\w+)/m,
    ~r/^(function)\s+(\w+)\s*\(/m,
    ~r/^(class)\s+(\w+)/m,
    ~r/^(interface|type)\s+(\w+)/m
  ]

  def extract(content) do
    matches =
      @patterns
      |> Enum.flat_map(&Regex.scan(&1, content))
      |> Enum.map(&List.first/1)
      |> Enum.uniq()

    "[JavaScript/TypeScript Structure]\n\n" <> Enum.join(matches, "\n")
  end
end

defmodule Cortex.Tools.Handlers.ReadStructure.RustParser do
  @moduledoc false

  @patterns [
    ~r/^pub\s+(fn|struct|enum|trait|type|const|static)\s+(\w+)/m,
    ~r/^(fn|struct|enum|trait|impl)\s+(\w+)/m
  ]

  def extract(content) do
    matches =
      @patterns
      |> Enum.flat_map(&Regex.scan(&1, content))
      |> Enum.map(&List.first/1)
      |> Enum.uniq()

    "[Rust Structure]\n\n" <> Enum.join(matches, "\n")
  end
end

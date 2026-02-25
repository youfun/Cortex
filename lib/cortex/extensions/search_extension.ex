defmodule Cortex.Extensions.SearchExtension do
  @behaviour Cortex.Extensions.Extension

  def name, do: "search"
  def description, do: "Web search capability via Brave or Tavily"
  def hooks, do: []

  def tools do
    [
      %Cortex.Tools.Tool{
        name: "web_search",
        description: "Search the web for real-time information. Returns titles, URLs, and snippets.",
        parameters: [
          query: [type: :string, required: true, doc: "The search query"],
          count: [type: :integer, required: false, doc: "Number of results (default: 5, max: 10)"],
          provider: [type: :string, required: false, doc: "Force a specific provider: brave | tavily"]
        ],
        module: Cortex.Tools.Handlers.WebSearch
      }
    ]
  end

  def init(_config), do: {:ok, %{}}
end

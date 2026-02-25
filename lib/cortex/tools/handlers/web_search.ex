defmodule Cortex.Tools.Handlers.WebSearch do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Search.Dispatcher

  @impl true
  def execute(args, _ctx) do
    query = Map.get(args, :query) || Map.get(args, "query", "")
    count = Map.get(args, :count) || Map.get(args, "count", 5)
    provider = Map.get(args, :provider) || Map.get(args, "provider")

    opts = [count: count]
    opts = if provider, do: Keyword.put(opts, :provider, provider), else: opts

    case Dispatcher.search(query, opts) do
      {:ok, results} -> {:ok, format_results(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_results(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {r, i} ->
      "#{i}. #{r.title}\n   URL: #{r.url}\n   #{r.snippet}"
    end)
  end
end

defmodule Cortex.Search.Providers.Brave do
  @moduledoc """
  Brave Web Search API provider.
  """

  @behaviour Cortex.Search.Provider

  @impl true
  def name, do: "brave"

  @impl true
  def available? do
    api_key() != nil and api_key() != ""
  end

  @impl true
  def search(query, opts \\ []) do
    count = Keyword.get(opts, :count, 5) |> min(10)

    case Req.get(base_url() <> "/web/search",
           params: %{q: query, count: count},
           headers: [
             {"Accept", "application/json"},
             {"Accept-Encoding", "gzip"},
             {"X-Subscription-Token", api_key()}
           ],
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        results = parse_results(body)
        {:ok, results}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Brave API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Brave request failed: #{inspect(reason)}"}
    end
  end

  defp parse_results(%{"web" => %{"results" => results}}) when is_list(results) do
    Enum.map(results, fn r ->
      %{
        title: r["title"] || "",
        url: r["url"] || "",
        snippet: r["description"] || "",
        published_date: r["age"]
      }
    end)
  end

  defp parse_results(_), do: []

  defp api_key do
    case search_settings_field(:brave_api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> System.get_env("BRAVE_API_KEY")
    end
  end

  defp base_url do
    Application.get_env(:cortex, :search, [])
    |> get_in([:providers, :brave, :base_url]) || "https://api.search.brave.com/res/v1"
  end

  defp search_settings_field(field) do
    try do
      settings = Cortex.Config.SearchSettings.get_settings()
      Map.get(settings, field)
    rescue
      _ -> nil
    end
  end
end

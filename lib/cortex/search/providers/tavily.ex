defmodule Cortex.Search.Providers.Tavily do
  @moduledoc """
  Tavily Search API provider.
  """

  @behaviour Cortex.Search.Provider

  @impl true
  def name, do: "tavily"

  @impl true
  def available? do
    api_key() != nil and api_key() != ""
  end

  @impl true
  def search(query, opts \\ []) do
    count = Keyword.get(opts, :count, 5) |> min(10)

    case Req.post(base_url() <> "/search",
           json: %{query: query, max_results: count, api_key: api_key()},
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_results(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Tavily API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Tavily request failed: #{inspect(reason)}"}
    end
  end

  defp parse_results(%{"results" => results}) when is_list(results) do
    Enum.map(results, fn r ->
      %{
        title: r["title"] || "",
        url: r["url"] || "",
        snippet: r["content"] || "",
        published_date: r["published_date"]
      }
    end)
  end

  defp parse_results(_), do: []

  defp api_key do
    case search_settings_field(:tavily_api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> System.get_env("TAVILY_API_KEY")
    end
  end

  defp base_url do
    Application.get_env(:cortex, :search, [])
    |> get_in([:providers, :tavily, :base_url]) || "https://api.tavily.com"
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

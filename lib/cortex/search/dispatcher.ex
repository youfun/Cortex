defmodule Cortex.Search.Dispatcher do
  @moduledoc """
  Routes search queries to available providers with fallback logic.
  Fallback chain: configured_default -> first_available -> error
  """

  @providers [
    brave: Cortex.Search.Providers.Brave,
    tavily: Cortex.Search.Providers.Tavily
  ]

  def search(query, opts \\ []) do
    case resolve_provider(opts[:provider]) do
      nil -> {:error, "No search provider configured. Set BRAVE_API_KEY or TAVILY_API_KEY."}
      mod -> mod.search(query, opts)
    end
  end

  # Forced provider: use it directly, no fallback
  defp resolve_provider(forced) when is_binary(forced) do
    key = String.to_existing_atom(forced)
    mod = @providers[key]
    if mod && mod.available?(), do: mod, else: nil
  rescue
    ArgumentError -> nil
  end

  defp resolve_provider(_) do
    default = get_default_provider()

    cond do
      default && @providers[default] && @providers[default].available?() ->
        @providers[default]

      true ->
        Enum.find_value(@providers, fn {_key, mod} ->
          if mod.available?(), do: mod
        end)
    end
  end

  defp get_default_provider do
    case search_settings_from_db() do
      %{default_provider: p} when is_binary(p) and p != "" ->
        String.to_existing_atom(p)

      _ ->
        Application.get_env(:cortex, :search, [])[:default_provider] || :tavily
    end
  rescue
    ArgumentError -> :tavily
  end

  defp search_settings_from_db do
    try do
      Cortex.Config.SearchSettings.get_settings()
    rescue
      _ -> nil
    end
  end
end

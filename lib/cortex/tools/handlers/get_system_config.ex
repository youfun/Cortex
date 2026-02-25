defmodule Cortex.Tools.Handlers.GetSystemConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Channels
  alias Cortex.Config.Settings

  @impl true
  def execute(args, _ctx) do
    domain = Map.get(args, :domain) || Map.get(args, "domain", "all")

    result =
      case domain do
        "channels" -> %{channels: get_channels_config()}
        "models" -> %{models: get_models_config()}
        "search" -> %{search: get_search_config()}
        "all" -> %{
          channels: get_channels_config(),
          models: get_models_config(),
          search: get_search_config()
        }
        _ -> %{error: "Unknown domain: #{domain}"}
      end

    {:ok, Jason.encode!(result, pretty: true)}
  end

  defp get_channels_config do
    Channels.list_channel_configs()
    |> Enum.map(fn c ->
      %{adapter: c.adapter, enabled: c.enabled}
    end)
  end

  defp get_models_config do
    %{
      default_model: Settings.get_skill_default_model(),
      available_models: Settings.list_available_models()
        |> Enum.map(fn m -> %{name: m.name, provider: m.provider_drive, enabled: m.enabled} end)
    }
  end

  defp get_search_config do
    try do
      settings = Cortex.Config.SearchSettings.get_settings()
      %{
        default_provider: settings.default_provider,
        brave_api_key: mask_key(settings.brave_api_key),
        tavily_api_key: mask_key(settings.tavily_api_key),
        enable_llm_title_generation: settings.enable_llm_title_generation
      }
    rescue
      _ -> %{status: "not_configured"}
    end
  end

  defp mask_key(nil), do: nil
  defp mask_key(""), do: nil
  defp mask_key(key) when byte_size(key) <= 4, do: "****"
  defp mask_key(key), do: String.slice(key, 0, 4) <> "****"
end

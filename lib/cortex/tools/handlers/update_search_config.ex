defmodule Cortex.Tools.Handlers.UpdateSearchConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Config.SearchSettings
  alias Cortex.SignalHub

  @impl true
  def execute(args, ctx) do
    old_settings = SearchSettings.get_settings()

    case SearchSettings.update_settings(args) do
      {:ok, new_settings} ->
        SignalHub.emit("config.search.updated", %{
          provider: "config",
          event: "search",
          action: "updated",
          actor: "llm_agent",
          origin: %{
            channel: "tool",
            client: "config_handler",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          old_value: mask_keys(Map.from_struct(old_settings) |> Map.drop([:__meta__])),
          new_value: mask_keys(Map.from_struct(new_settings) |> Map.drop([:__meta__]))
        }, source: "/tool/config")

        {:ok, "Search configuration updated successfully."}

      {:error, changeset} ->
        {:error, "Failed to update: #{inspect(changeset.errors)}"}
    end
  end

  defp mask_keys(map) do
    Map.new(map, fn
      {k, v} when k in [:brave_api_key, :tavily_api_key] -> {k, mask(v)}
      kv -> kv
    end)
  end

  defp mask(nil), do: nil
  defp mask(""), do: nil
  defp mask(key) when byte_size(key) <= 4, do: "****"
  defp mask(key), do: String.slice(key, 0, 4) <> "****"
end

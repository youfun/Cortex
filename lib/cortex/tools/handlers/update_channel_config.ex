defmodule Cortex.Tools.Handlers.UpdateChannelConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Channels
  alias Cortex.SignalHub

  @impl true
  def execute(args, ctx) do
    adapter = Map.get(args, :adapter) || Map.get(args, "adapter")
    enabled = Map.get(args, :enabled)
    config = Map.get(args, :config) || Map.get(args, "config", %{})

    attrs = %{adapter: adapter, enabled: enabled, config: config}
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    result = case Channels.get_channel_config_by_adapter(adapter) do
      nil ->
        Channels.create_channel_config(attrs)
      existing ->
        Channels.update_channel_config(existing, attrs)
    end

    case result do
      {:ok, _config} ->
        SignalHub.emit("config.channel.updated", %{
          provider: "config",
          event: "channel",
          action: "updated",
          actor: "llm_agent",
          origin: %{
            channel: "tool",
            client: "config_handler",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          adapter: adapter
        }, source: "/tool/config")

        {:ok, "Channel '#{adapter}' configuration updated."}

      {:error, changeset} ->
        {:error, "Failed to update channel: #{inspect(changeset.errors)}"}
    end
  end
end

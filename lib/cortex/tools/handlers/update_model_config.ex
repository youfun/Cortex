defmodule Cortex.Tools.Handlers.UpdateModelConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Config
  alias Cortex.Config.Settings
  alias Cortex.SignalHub

  @impl true
  def execute(args, ctx) do
    model_name = Map.get(args, :model_name) || Map.get(args, "model_name")
    action = Map.get(args, :action) || Map.get(args, "action", "update")

    result =
      case action do
        "enable" -> Settings.enable_model(model_name)
        "disable" -> Settings.disable_model(model_name)
        "set_default" -> Settings.set_skill_default_model(model_name)
        "update" ->
          case Config.get_llm_model_by_name(model_name) do
            nil -> {:error, :not_found}
            model ->
              attrs = Map.drop(args, [:model_name, :action, "model_name", "action"])
              Config.update_llm_model(model, attrs)
          end
        _ ->
          {:error, "Unknown action: #{action}"}
      end

    case result do
      {:ok, _} ->
        SignalHub.emit("config.model.updated", %{
          provider: "config",
          event: "model",
          action: "updated",
          actor: "llm_agent",
          origin: %{
            channel: "tool",
            client: "config_handler",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          model_name: model_name,
          model_action: action
        }, source: "/tool/config")

        {:ok, "Model '#{model_name}' #{action} completed."}

      {:error, :not_found} ->
        {:error, "Model '#{model_name}' not found."}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Failed: #{inspect(changeset.errors)}"}

      {:error, reason} ->
        {:error, "Failed: #{inspect(reason)}"}
    end
  end
end

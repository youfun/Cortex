defmodule Cortex.Conversations.TitleGenerator do
  @moduledoc "根据首条消息异步生成对话标题"

  require Logger

  alias Cortex.Config.Settings
  alias Cortex.Conversations
  alias Cortex.LLM.Client

  @system_prompt "Generate a concise title (max 6 words) for this conversation. Reply with only the title, no quotes or punctuation."

  @doc """
  在首条用户消息发送后异步触发标题生成。
  调用方需确保只在首条消息时调用。
  """
  def maybe_generate(conversation_id, first_message, model_name \\ nil) do
    mode = Settings.get_title_generation()

    case mode do
      "disabled" ->
        :skip

      "conversation" ->
        effective_model = model_name || Settings.get_effective_skill_default_model()
        async_generate(conversation_id, first_message, effective_model)

      "model" ->
        title_model = Settings.get_title_model() || Settings.get_effective_skill_default_model()
        async_generate(conversation_id, first_message, title_model)

      _ ->
        :skip
    end
  end

  defp async_generate(conversation_id, first_message, model_name) do
    Task.Supervisor.start_child(Cortex.AgentTaskSupervisor, fn ->
      generate(conversation_id, first_message, model_name)
    end)
  end

  defp generate(conversation_id, first_message, model_name) do
    prompt = "#{@system_prompt}\n\nUser message: #{String.slice(first_message, 0, 200)}"

    case Client.complete(model_name, prompt, max_tokens: 20) do
      {:ok, title} when is_binary(title) and title != "" ->
        clean_title = title |> String.trim() |> String.slice(0, 50)

        case Conversations.get_conversation(conversation_id) do
          nil -> :ok
          conversation -> Conversations.update_conversation(conversation, %{title: clean_title})
        end

      {:ok, _} ->
        Logger.debug("[TitleGenerator] Empty title response, skipping")

      {:error, reason} ->
        Logger.warning("[TitleGenerator] Failed to generate title: #{inspect(reason)}")
    end
  end
end

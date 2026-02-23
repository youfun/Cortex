defmodule Cortex.Channels.Telegram.Dispatcher do
  @moduledoc """
  Telegram 响应器 GenServer。
  监听 SignalHub 上的特定信号，并将其转换为 Telegram API 调用。
  """
  use GenServer
  require Logger
  alias Cortex.Channels.Telegram.Client
  alias Cortex.Conversations
  alias Cortex.SignalHub

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    token = Application.get_env(:cortex, :telegram, [])[:bot_token]

    if token && token != "" do
      Logger.info("[Telegram.Dispatcher] Starting dispatcher...")
      client = Client.new(token)

      # 订阅 Telegram 相关指令信号
      SignalHub.subscribe("jido.telegram.cmd.*")
      SignalHub.subscribe("agent.response")
      SignalHub.subscribe("tts.result")

      {:ok, %{client: client}}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(
        {:signal, %Jido.Signal{type: "jido.telegram.cmd.send_message", data: data}},
        state
      ) do
    payload = signal_payload(data)
    chat_id = payload[:chat_id] || payload["chat_id"]
    text = payload[:text] || payload["text"]

    if chat_id && text do
      opts = Map.drop(payload, [:chat_id, :text, "chat_id", "text"]) |> Map.to_list()

      case Client.send_message(state.client, chat_id, text, opts) do
        {:ok, _result} ->
          Logger.debug("[Telegram.Dispatcher] Message sent to #{chat_id}")

        {:error, reason} ->
          Logger.error("[Telegram.Dispatcher] Failed to send message: #{inspect(reason)}")
      end
    else
      Logger.error("[Telegram.Dispatcher] Invalid send_message signal data: #{inspect(data)}")
    end

    {:noreply, state}
  end

  # 处理其他类型的指令（如 send_photo）
  @impl true
  def handle_info(
        {:signal, %Jido.Signal{type: "jido.telegram.cmd.send_photo", data: data}},
        state
      ) do
    payload = signal_payload(data)
    chat_id = payload[:chat_id] || payload["chat_id"]
    photo = payload[:photo] || payload["photo"]

    if chat_id && photo do
      case Client.send_photo(state.client, chat_id, photo) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          Logger.error("[Telegram.Dispatcher] Failed to send photo: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:signal, %Jido.Signal{type: "jido.telegram.cmd.send_document", data: data}},
        state
      ) do
    payload = signal_payload(data)
    chat_id = payload[:chat_id] || payload["chat_id"]
    document = payload[:document] || payload["document"]

    if chat_id && document do
      case Client.send_document(state.client, chat_id, document) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          Logger.error("[Telegram.Dispatcher] Failed to send document: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:signal, %Jido.Signal{type: "jido.telegram.cmd.send_voice", data: data}},
        state
      ) do
    payload = signal_payload(data)
    chat_id = payload[:chat_id] || payload["chat_id"]
    voice = payload[:voice] || payload["voice"] || payload[:voice_url] || payload["voice_url"]

    if chat_id && voice do
      case Client.send_voice(state.client, chat_id, voice) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          Logger.error("[Telegram.Dispatcher] Failed to send voice: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "agent.response", data: data}}, state) do
    payload = signal_payload(data)

    maybe_dispatch_agent_response(state, payload)

    {:noreply, state}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "tts.result", data: data}}, state) do
    payload = signal_payload(data)
    context = payload[:context] || payload["context"] || %{}

    if context[:channel] == "telegram" || context["channel"] == "telegram" do
      chat_id = context[:chat_id] || context["chat_id"]
      audio_url = payload[:audio_url] || payload["audio_url"]

      if chat_id && audio_url do
        case Client.send_voice(state.client, chat_id, audio_url) do
          {:ok, _result} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[Telegram.Dispatcher] Failed to send voice from tts.result: #{inspect(reason)}"
            )
        end
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[Telegram.Dispatcher] Received unknown signal: #{inspect(msg)}")
    {:noreply, state}
  end

  defp signal_payload(data) when is_map(data) do
    payload = Map.get(data, :payload) || Map.get(data, "payload")

    if is_map(payload) and map_size(payload) > 0 do
      payload
    else
      data
    end
  end

  defp maybe_dispatch_agent_response(state, payload) when is_map(payload) do
    with session_id when is_binary(session_id) <- payload[:session_id] || payload["session_id"],
         content when is_binary(content) and content != "" <-
           payload[:content] || payload["content"],
         %{} = conversation <- Conversations.get_conversation(session_id),
         chat_id when not is_nil(chat_id) <- conversation_telegram_chat_id(conversation) do
      # 始终发送文本响应
      send_telegram_text(state.client, chat_id, content)

      # 如果开启了语音，则触发 TTS
      if telegram_voice_enabled?(conversation) do
        trigger_tts(chat_id, content, conversation)
      end
    else
      _ -> :ok
    end
  end

  defp telegram_voice_enabled?(conversation) do
    meta = conversation.meta || %{}
    meta["telegram_voice_enabled"] == true || meta[:telegram_voice_enabled] == true
  end

  defp trigger_tts(chat_id, content, conversation) do
    meta = conversation.meta || %{}
    speaker = meta["telegram_voice_speaker"] || meta[:telegram_voice_speaker] || "Vivian"

    SignalHub.emit("tts.request", %{
      provider: "telegram",
      event: "tts",
      action: "request",
      actor: "dispatcher",
      origin: %{channel: "telegram", client: "dispatcher", platform: "server"},
      payload: %{
        text: content,
        model_type: "custom_voice",
        params: %{
          language: "Auto",
          speaker: speaker
        },
        context: %{
          channel: "telegram",
          chat_id: chat_id
        }
      }
    })
  end

  defp conversation_telegram_chat_id(conversation) do
    get_in(conversation.meta || %{}, ["telegram_chat_id"]) ||
      get_in(conversation.meta || %{}, [:telegram_chat_id])
  end

  defp send_telegram_text(client, chat_id, content) do
    case Client.send_message(client, chat_id, content, []) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.error("[Telegram.Dispatcher] Failed to send message: #{inspect(reason)}")
    end
  end
end

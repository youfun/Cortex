defmodule Cortex.Channels.Telegram.CommandHandler do
  @moduledoc """
  Handles Telegram slash commands and routes them into Jido signals.
  """
  use GenServer
  require Logger

  alias Cortex.Conversations
  alias Cortex.Config.ModelSelector
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  @help_text """
  可用指令：
  /start - 开启新对话
  /new   - 开启新对话
  /reset - 清空当前对话上下文
  /help  - 查看帮助
  """

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    SignalHub.subscribe("telegram.command")
    Logger.info("[Telegram.CommandHandler] Started and subscribed to telegram.command")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "telegram.command", data: data}}, state) do
    payload = signal_payload(data)
    text = payload[:text] || payload["text"] || ""
    chat_id = payload[:chat_id] || payload["chat_id"]
    origin = payload[:origin] || payload["origin"]

    case parse_command(text) do
      {:ok, "start", _args} ->
        handle_new(chat_id, origin, :start)

      {:ok, "new", _args} ->
        handle_new(chat_id, origin, :new)

      {:ok, "reset", _args} ->
        handle_reset(chat_id, origin)

      {:ok, "help", _args} ->
        send_message(chat_id, @help_text, origin)

      {:ok, unknown, _args} ->
        send_message(chat_id, "未知指令：/#{unknown}\n输入 /help 查看可用指令。", origin)

      :error ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_new(nil, _origin, _source) do
    Logger.warning("[Telegram.CommandHandler] /new missing chat_id")
    :ok
  end

  defp handle_new(chat_id, origin, _source) do
    with {:ok, workspace_id} <- ensure_workspace_id() do
      if existing = Conversations.get_conversation_by_meta("telegram_chat_id", chat_id) do
        SignalHub.emit(
          "agent.cancel",
          %{
            provider: "telegram",
            event: "agent",
            action: "cancel",
            actor: "command_handler",
            origin: origin || default_origin(),
            session_id: existing.id
          },
          source: "/telegram/command_handler"
        )

        _ = unlink_conversation(existing)
      end

      case ModelSelector.default_model_info() do
        {:ok, {model_name, model_id}} ->
          attrs = %{
            title: new_conversation_title(chat_id),
            status: "active",
            meta: %{"telegram_chat_id" => chat_id},
            model_config: ModelSelector.model_config_from_id(model_id)
          }

          case Conversations.create_conversation(attrs, workspace_id) do
            {:ok, conversation} ->
              ensure_session(conversation.id, workspace_id, model_name)
              send_message(chat_id, "✅ 已开启新的对话。", origin)

            {:error, reason} ->
              Logger.error(
                "[Telegram.CommandHandler] create_conversation failed: #{inspect(reason)}"
              )

              send_message(chat_id, "创建新对话失败，请稍后重试。", origin)
          end

        {:error, :no_available_models} ->
          Logger.error("[Telegram.CommandHandler] No available models configured")
          send_message(chat_id, "未找到可用模型，请先在 UI 配置并启用模型。", origin)
      end
    else
      {:error, reason} ->
        Logger.error("[Telegram.CommandHandler] ensure_workspace_id failed: #{inspect(reason)}")
        send_message(chat_id, "工作区初始化失败，请稍后重试。", origin)
    end
  end

  defp handle_reset(nil, _origin) do
    Logger.warning("[Telegram.CommandHandler] /reset missing chat_id")
    :ok
  end

  defp handle_reset(chat_id, origin) do
    with {:ok, workspace_id} <- ensure_workspace_id(),
         %{} = conversation <- Conversations.get_conversation_by_meta("telegram_chat_id", chat_id) do
      case ModelSelector.default_model_info() do
        {:ok, {default_model_name, default_model_id}} ->
          case ModelSelector.resolve_model_from_config(
                 conversation.model_config || %{},
                 default_model_name,
                 default_model_id
               ) do
            {:ok, {model_name, _model_id}} ->
              ensure_session(conversation.id, workspace_id, model_name)

            {:error, :no_available_models} ->
              Logger.error("[Telegram.CommandHandler] No available models configured")
              send_message(chat_id, "未找到可用模型，请先在 UI 配置并启用模型。", origin)
          end

        {:error, :no_available_models} ->
          Logger.error("[Telegram.CommandHandler] No available models configured")
          send_message(chat_id, "未找到可用模型，请先在 UI 配置并启用模型。", origin)
      end

      SignalHub.emit(
        "agent.conversation.switch",
        %{
          provider: "telegram",
          event: "conversation",
          action: "reset",
          actor: "user",
          origin: origin || default_origin(),
          conversation_id: conversation.id,
          history: [],
          session_id: conversation.id
        },
        source: "/telegram/command_handler"
      )

      send_message(chat_id, "♻️ 已清空当前对话上下文。", origin)
    else
      nil ->
        handle_new(chat_id, origin, :reset)

      {:error, reason} ->
        Logger.error("[Telegram.CommandHandler] reset failed: #{inspect(reason)}")
        send_message(chat_id, "重置失败，请稍后重试。", origin)
    end
  end

  defp ensure_workspace_id do
    cwd = Workspaces.ensure_workspace_root!()

    case Enum.find(Workspaces.list_workspaces(), fn ws -> ws.path == cwd end) do
      nil ->
        case Workspaces.create_workspace(%{name: "default", path: cwd, status: "active"}) do
          {:ok, ws} -> {:ok, ws.id}
          {:error, reason} -> {:error, reason}
        end

      ws ->
        {:ok, ws.id}
    end
  end

  defp ensure_session(session_id, workspace_id, model_name) do
    case Registry.lookup(Cortex.SessionRegistry, session_id) do
      [] ->
        DynamicSupervisor.start_child(
          Cortex.SessionSupervisor,
          {Cortex.Agents.LLMAgent,
           session_id: session_id, workspace_id: workspace_id, model: model_name}
        )

      _ ->
        :ok
    end
  end

  defp unlink_conversation(conversation) do
    meta =
      conversation.meta
      |> Kernel.||(%{})
      |> Map.delete("telegram_chat_id")
      |> Map.delete(:telegram_chat_id)

    Conversations.update_conversation(conversation, %{meta: meta})
  end

  defp new_conversation_title(_chat_id) do
    ts = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M")
    "tele #{ts}"
  end

  defp parse_command(text) when is_binary(text) do
    trimmed = String.trim(text)

    if String.starts_with?(trimmed, "/") do
      [cmd | rest] = String.split(trimmed, ~r/\s+/, parts: 2)

      name =
        cmd
        |> String.trim_leading("/")
        |> String.split("@")
        |> List.first()
        |> String.downcase()

      args = if rest == [], do: "", else: List.first(rest)
      {:ok, name, args}
    else
      :error
    end
  end

  defp parse_command(_), do: :error

  defp send_message(nil, _text, _origin), do: :ok

  defp send_message(chat_id, text, origin) do
    SignalHub.emit(
      "jido.telegram.cmd.send_message",
      %{
        provider: "telegram",
        event: "command",
        action: "send_message",
        actor: "command_handler",
        origin: origin || default_origin(),
        chat_id: chat_id,
        text: text
      },
      source: "/telegram/command_handler"
    )
  end

  defp default_origin do
    %{channel: "telegram", client: "command_handler", platform: "server"}
  end

  defp signal_payload(data) when is_map(data) do
    payload = Map.get(data, :payload) || Map.get(data, "payload")

    if is_map(payload) and map_size(payload) > 0 do
      payload
    else
      data
    end
  end
end

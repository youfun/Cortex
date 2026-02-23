defmodule Cortex.Channels.Telegram.Poller do
  @moduledoc """
  Telegram 轮询器 GenServer。
  负责长轮询获取 Update，并将其转换为 Jido 信号发布到 SignalHub。
  """
  use GenServer
  require Logger
  alias Cortex.Channels.Telegram.Client
  alias Cortex.Conversations
  alias Cortex.Config.ModelSelector
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  @poll_timeout 30
  @retry_interval 5000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    token = Application.get_env(:cortex, :telegram, [])[:bot_token]

    if token && token != "" do
      Logger.info(
        "[Telegram.Poller] Starting poller poll_timeout=#{@poll_timeout}s retry_interval=#{@retry_interval}ms token_prefix=#{String.slice(token, 0..5)}..."
      )

      client = Client.new(token)
      # 异步开始第一轮轮询
      send(self(), :poll)
      {:ok, %{client: client, offset: 0, bot_info: nil, polls: 0}}
    else
      Logger.warning("[Telegram.Poller] TELEGRAM_BOT_TOKEN not configured. Poller is disabled.")

      :ignore
    end
  end

  @impl true
  def handle_info(:poll, state) do
    # 第一次运行先确认 Bot 信息
    state = maybe_fetch_bot_info(state)

    polls = state.polls + 1
    Logger.debug("[Telegram.Poller] Polling getUpdates offset=#{state.offset} poll=#{polls}")

    case Client.get_updates(state.client, offset: state.offset, timeout: @poll_timeout) do
      {:ok, updates} ->
        if updates == [] do
          Logger.debug("[Telegram.Poller] getUpdates returned 0 updates offset=#{state.offset}")
        else
          last_id =
            updates
            |> Enum.map(& &1["update_id"])
            |> Enum.reject(&is_nil/1)
            |> List.last()

          Logger.info(
            "[Telegram.Poller] getUpdates returned #{length(updates)} updates offset=#{state.offset} last_update_id=#{inspect(last_id)}"
          )
        end

        new_offset = process_updates(updates, state)
        # 立即开始下一次轮询
        send(self(), :poll)
        {:noreply, %{state | offset: new_offset, polls: polls}}

      {:error, reason} ->
        Logger.error(
          "[Telegram.Poller] Error fetching updates: #{inspect(reason)}. Retrying in 5s..."
        )

        Process.send_after(self(), :poll, @retry_interval)
        {:noreply, %{state | polls: polls}}
    end
  end

  defp maybe_fetch_bot_info(%{bot_info: nil} = state) do
    case Client.get_me(state.client) do
      {:ok, info} ->
        Logger.info("[Telegram.Poller] Connected as @#{info["username"]}")
        maybe_warn_webhook(state.client)
        %{state | bot_info: info}

      {:error, reason} ->
        Logger.warning("[Telegram.Poller] getMe failed: #{inspect(reason)}")
        state

      other ->
        Logger.warning("[Telegram.Poller] getMe unexpected response: #{inspect(other)}")
        state
    end
  end

  defp maybe_fetch_bot_info(state), do: state

  defp process_updates([], state), do: state.offset

  defp process_updates(updates, state) do
    Enum.each(updates, fn update ->
      emit_signal(update, state)
    end)

    max_update_id =
      updates
      |> Enum.map(& &1["update_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)

    if is_integer(max_update_id) do
      max_update_id + 1
    else
      state.offset
    end
  end

  defp emit_signal(update, state) do
    # 提取用户信息用于白名单校验
    from = get_in(update, ["message", "from"]) || %{}
    user_id = from["id"] |> Kernel.to_string()
    username = from["username"]

    if allowed?(user_id, username) do
      do_emit_signal(update, state)
    else
      Logger.warning(
        "[Telegram.Poller] Unauthorized access attempt from user_id=#{user_id} username=#{username}"
      )

      :ok
    end
  end

  defp allowed?(id, username) do
    allow_from = Application.get_env(:cortex, :telegram, [])[:allow_from] || []

    # 如果没有配置白名单，则默认允许所有人（方便调试）
    if allow_from == [] do
      true
    else
      # 检查 ID 或 Username 是否在白名单中
      Enum.any?(allow_from, fn pattern ->
        pattern == id or (is_binary(username) and pattern == username)
      end)
    end
  end

  defp do_emit_signal(update, state) do
    # 来源标识 (遵循 /telegram/bot_username 路径风格)
    bot_name = if state.bot_info, do: state.bot_info["username"], else: "unknown_bot"
    source = "/telegram/#{bot_name}"

    # 提取核心数据
    {type, data, meta} = translate_update(update)

    chat_id = meta[:chat_id]
    user_id = meta[:user_id]
    message_id = meta[:message_id]

    bot_id = if state.bot_info, do: state.bot_info["id"], else: nil

    origin =
      %{
        channel: "telegram",
        client: "bot",
        platform: "server",
        bot_id: bot_id,
        chat_id_hash: if(chat_id, do: "c_#{chat_id}", else: nil),
        user_id_hash: if(user_id, do: "u_#{user_id}", else: nil),
        message_id: message_id
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    # 组装满足规范的 data
    # 根据 translate_update 返回的 type 决定 provider/event/action/actor
    {provider, event, action, actor} =
      case type do
        "telegram.command" -> {"telegram", "command", "execute", "user"}
        "telegram.message.text" -> {"telegram", "message", "receive", "user"}
        _ -> {"telegram", "event", "other", "user"}
      end

    signal_data =
      data
      |> Map.put(:origin, origin)
      |> Map.put(:provider, provider)
      |> Map.put(:event, event)
      |> Map.put(:action, action)
      |> Map.put(:actor, actor)

    # 发射信号
    case SignalHub.emit(type, signal_data, source: source) do
      {:ok, _signal} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[Telegram.Poller] SignalHub.emit failed: type=#{type} reason=#{inspect(reason)}"
        )
    end

    if type == "telegram.message.text" do
      dispatch_text_message(Map.put(data, :origin, origin))
    end
  end

  # 转换 Telegram Update 为结构化 Signal Data
  defp translate_update(%{"message" => %{"text" => text, "chat" => chat} = msg} = update) do
    type =
      if String.starts_with?(text, "/"), do: "telegram.command", else: "telegram.message.text"

    data = %{
      chat_id: chat["id"],
      text: text,
      from: msg["from"],
      message_id: msg["message_id"],
      update_id: update["update_id"]
    }

    meta = %{
      chat_id: chat["id"],
      user_id: get_in(msg, ["from", "id"]),
      message_id: msg["message_id"]
    }

    {type, data, meta}
  end

  defp translate_update(update) do
    # 通用后备
    {"telegram.received", %{raw: update, update_id: update["update_id"]},
     %{chat_id: nil, user_id: nil, message_id: nil}}
  end

  defp dispatch_text_message(data) do
    chat_id = data[:chat_id] || data["chat_id"]
    text = data[:text] || data["text"]

    Logger.info("[Telegram.Poller] Routing text message chat_id=#{inspect(chat_id)}")

    case ModelSelector.default_model_info() do
      {:ok, {default_model_name, default_model_id}} ->
        with {:ok, workspace_id} <- ensure_workspace_id(),
             {:ok, conversation} <-
               Conversations.get_or_create_by_meta(
                 "telegram_chat_id",
                 chat_id,
                 workspace_id,
                 %{
                   title: default_conversation_title(),
                   status: "active",
                   model_config: ModelSelector.model_config_from_id(default_model_id)
                 }
               ) do
          case resolve_conversation_model(conversation, default_model_name, default_model_id) do
            {:ok, {model_name, _model_id, conversation}} ->
              session_id = conversation.id
              ensure_session(session_id, workspace_id, model_name)

              Logger.info(
                "[Telegram.Poller] Emitting agent.chat.request session_id=#{session_id} workspace_id=#{workspace_id}"
              )

              SignalHub.emit(
                "user.input.chat",
                %{
                  provider: "telegram",
                  event: "chat",
                  action: "input",
                  actor: "user",
                  origin: data[:origin],
                  session_id: session_id,
                  conversation_id: conversation.id,
                  content: text
                },
                source: "/telegram/poller"
              )

              SignalHub.emit(
                "agent.chat.request",
                %{
                  provider: "telegram",
                  event: "chat",
                  action: "request",
                  actor: "user",
                  origin: data[:origin],
                  session_id: session_id,
                  conversation_id: conversation.id,
                  content: text,
                  model: model_name
                },
                source: "/telegram/poller"
              )

            {:error, :no_available_models} ->
              Logger.error("[Telegram.Poller] No available models configured")
              send_message(chat_id, "未找到可用模型，请先在 UI 配置并启用模型。", data[:origin])
          end
        else
          {:error, reason} ->
            Logger.error("[Telegram.Poller] Failed to route message: #{inspect(reason)}")

          _ ->
            Logger.error("[Telegram.Poller] Failed to route message: unknown error")
        end

      {:error, :no_available_models} ->
        Logger.error("[Telegram.Poller] No available models configured")
        send_message(chat_id, "未找到可用模型，请先在 UI 配置并启用模型。", data[:origin])
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
        Logger.info("[Telegram.Poller] Starting LLMAgent session_id=#{session_id}")

        DynamicSupervisor.start_child(
          Cortex.SessionSupervisor,
          {Cortex.Agents.LLMAgent,
           session_id: session_id, workspace_id: workspace_id, model: model_name}
        )

      _ ->
        :ok
    end
  end

  defp resolve_conversation_model(conversation, default_model_name, default_model_id) do
    case ModelSelector.resolve_model_from_config(
           conversation.model_config || %{},
           default_model_name,
           default_model_id
         ) do
      {:ok, {model_name, model_id}} ->
        updated =
          if model_id &&
               ModelSelector.model_id_from_config(conversation.model_config || %{}) != model_id do
            maybe_update_model_config(conversation, model_id)
          else
            conversation
          end

        {:ok, {model_name, model_id, updated}}

      {:error, :no_available_models} ->
        {:error, :no_available_models}
    end
  end

  defp send_message(nil, _text, _origin), do: :ok

  defp send_message(chat_id, text, origin) do
    SignalHub.emit(
      "jido.telegram.cmd.send_message",
      %{
        provider: "telegram",
        event: "command",
        action: "send_message",
        actor: "poller",
        origin: origin || default_origin(),
        chat_id: chat_id,
        text: text
      },
      source: "/telegram/poller"
    )
  end

  defp default_origin do
    %{channel: "telegram", client: "poller", platform: "server"}
  end

  defp default_conversation_title do
    ts = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M")
    "tele #{ts}"
  end

  defp maybe_update_model_config(conversation, model_id) do
    existing_id = ModelSelector.model_id_from_config(conversation.model_config || %{})

    if existing_id == model_id do
      conversation
    else
      new_config =
        conversation.model_config
        |> Kernel.||(%{})
        |> Map.put(:model_id, model_id)
        |> Map.put("model_id", model_id)

      case Conversations.update_conversation(conversation, %{model_config: new_config}) do
        {:ok, updated} -> updated
        _ -> conversation
      end
    end
  end

  defp maybe_warn_webhook(client) do
    case Client.get_webhook_info(client) do
      {:ok, %{"url" => url}} when is_binary(url) and url != "" ->
        Logger.warning(
          "[Telegram.Poller] Webhook is set (url present). getUpdates will NOT receive messages until webhook is deleted."
        )

      {:ok, _info} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Telegram.Poller] getWebhookInfo failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end
end

defmodule Cortex.Channels.Feishu.Receiver do
  @moduledoc """
  Feishu Webhook 接收器。
  监听 Feishu 消息信号，并路由到 Agent 会话。
  """
  use GenServer
  require Logger
  alias Cortex.Conversations
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    SignalHub.subscribe("feishu.message.text")
    Logger.info("[Feishu.Receiver] Started and subscribed to feishu.message.text")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "feishu.message.text", data: data}}, state) do
    payload = signal_payload(data)
    dispatch_text_message(payload)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp dispatch_text_message(data) do
    chat_id = data[:chat_id] || data["chat_id"]
    text = data[:text] || data["text"]

    with {:ok, workspace_id} <- ensure_workspace_id(),
         {:ok, conversation} <-
           Conversations.get_or_create_by_meta(
             "feishu_chat_id",
             chat_id,
             workspace_id,
             title: "Feishu #{chat_id}",
             status: "active"
           ) do
      session_id = conversation.id
      ensure_session(session_id, workspace_id)

      SignalHub.emit(
        "user.input.chat",
        %{
          provider: "feishu",
          event: "chat",
          action: "input",
          actor: "user",
          origin: data[:origin] || data["origin"],
          session_id: session_id,
          conversation_id: conversation.id,
          content: text
        },
        source: "/feishu/receiver"
      )

      SignalHub.emit(
        "agent.chat.request",
        %{
          provider: "feishu",
          event: "chat",
          action: "request",
          actor: "user",
          origin: data[:origin] || data["origin"],
          session_id: session_id,
          conversation_id: conversation.id,
          content: text
        },
        source: "/feishu/receiver"
      )
    else
      {:error, reason} ->
        Logger.error("[Feishu.Receiver] Failed to route message: #{inspect(reason)}")

      _ ->
        Logger.error("[Feishu.Receiver] Failed to route message: unknown error")
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

  defp ensure_session(session_id, workspace_id) do
    case Registry.lookup(Cortex.SessionRegistry, session_id) do
      [] ->
        DynamicSupervisor.start_child(
          Cortex.SessionSupervisor,
          {Cortex.Agents.LLMAgent, session_id: session_id, workspace_id: workspace_id}
        )

      _ ->
        :ok
    end
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

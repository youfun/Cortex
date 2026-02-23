defmodule Cortex.Channels.Feishu.Dispatcher do
  @moduledoc """
  Feishu 响应器 GenServer。
  监听 SignalHub 上的特定信号，并将其转换为 Feishu API 调用。
  """
  use GenServer
  require Logger
  alias Cortex.Channels.Feishu.Client
  alias Cortex.Conversations
  alias Cortex.SignalHub

  @token_refresh_skew 60

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    cfg = Application.get_env(:cortex, :feishu, [])
    app_id = cfg[:app_id]
    app_secret = cfg[:app_secret]

    if present?(app_id) and present?(app_secret) do
      Logger.info("[Feishu.Dispatcher] Starting dispatcher...")
      client = Client.new()

      SignalHub.subscribe("jido.feishu.cmd.*")
      SignalHub.subscribe("agent.response")

      {:ok, %{client: client, app_id: app_id, app_secret: app_secret, token: nil, token_exp: 0}}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(
        {:signal, %Jido.Signal{type: "jido.feishu.cmd.send_message", data: data}},
        state
      ) do
    payload = signal_payload(data)

    receive_id =
      payload[:receive_id] || payload["receive_id"] || payload[:chat_id] || payload["chat_id"]

    receive_id_type =
      payload[:receive_id_type] || payload["receive_id_type"] ||
        if(payload[:chat_id] || payload["chat_id"], do: "chat_id", else: "open_id")

    text = payload[:text] || payload["text"]

    if receive_id && text do
      with {:ok, state} <- ensure_token(state),
           {:ok, _result} <-
             Client.send_text_message(
               state.client,
               state.token,
               receive_id_type,
               receive_id,
               text
             ) do
        Logger.debug("[Feishu.Dispatcher] Message sent to #{receive_id}")
        {:noreply, state}
      else
        {:error, reason} ->
          Logger.error("[Feishu.Dispatcher] Failed to send message: #{inspect(reason)}")
          {:noreply, state}
      end
    else
      Logger.error("[Feishu.Dispatcher] Invalid send_message signal data: #{inspect(data)}")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "agent.response", data: data}}, state) do
    payload = signal_payload(data)
    session_id = payload[:session_id] || payload["session_id"]
    content = payload[:content] || payload["content"]

    case Conversations.get_conversation(session_id) do
      %{} = conversation ->
        meta = conversation.meta || %{}
        receive_id = get_in(meta, ["feishu_chat_id"]) || get_in(meta, [:feishu_chat_id])

        receive_id_type =
          get_in(meta, ["feishu_receive_id_type"]) || get_in(meta, [:feishu_receive_id_type]) ||
            "chat_id"

        if receive_id && content do
          with {:ok, state} <- ensure_token(state),
               {:ok, _result} <-
                 Client.send_text_message(
                   state.client,
                   state.token,
                   receive_id_type,
                   receive_id,
                   content
                 ) do
            :ok
          else
            {:error, reason} ->
              Logger.error("[Feishu.Dispatcher] Failed to send message: #{inspect(reason)}")
          end
        end

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[Feishu.Dispatcher] Received unknown signal: #{inspect(msg)}")
    {:noreply, state}
  end

  defp ensure_token(state) do
    now = System.system_time(:second)

    if state.token && state.token_exp > now do
      {:ok, state}
    else
      case Client.get_tenant_access_token(state.client, state.app_id, state.app_secret) do
        {:ok, %{"tenant_access_token" => token, "expire" => expire}} ->
          exp = now + max(expire - @token_refresh_skew, 0)
          {:ok, %{state | token: token, token_exp: exp}}

        {:error, reason} ->
          {:error, reason}
      end
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

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(value), do: not is_nil(value)
end

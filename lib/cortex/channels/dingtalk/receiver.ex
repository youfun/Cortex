defmodule Cortex.Channels.Dingtalk.Receiver do
  @moduledoc """
  Manages the DingTalk Stream WebSocket connection and message receiving.
  """
  use WebSockex
  require Logger
  alias Cortex.SignalHub
  alias Cortex.Channels.Dingtalk.Client
  alias Cortex.Channels

  def start_link(opts) do
    with {:ok, url} <- fetch_gateway_url(),
         {:ok, token} <- get_token(),
         {:ok, pid} <-
           WebSockex.start_link(
             url,
             __MODULE__,
             opts,
             name: __MODULE__,
             extra_headers: [{"x-acs-dingtalk-access-token", token}]
           ) do
      {:ok, pid}
    else
      {:error, reason} ->
        Logger.error("[Dingtalk.Receiver] Failed to start: #{inspect(reason)}")
        :ignore
    end
  end

  defp get_token do
    Client.get_token()
  end

  defp fetch_gateway_url do
    # Use Channels context
    config = Channels.get_config("dingtalk")
    client_id = config[:client_id]
    client_secret = config[:client_secret]

    if is_nil(client_id) or is_nil(client_secret) do
      if Application.get_env(:cortex, :env) == :test do
        {:ok, "wss://mock-dingtalk-gateway"}
      else
        {:error, :missing_credentials}
      end
    else
      url = "https://api.dingtalk.com/v1.0/gateway/connections/open"

      body = %{
        "clientId" => client_id,
        "clientSecret" => client_secret,
        "subscriptions" => [
          %{"type" => "EVENT", "topic" => "*"},
          %{"type" => "CALLBACK", "topic" => "*"}
        ]
      }

      case Req.post(url, json: body) do
        {:ok, %{status: 200, body: %{"endpoint" => endpoint}}} ->
          {:ok, endpoint}

        {:error, _} ->
          {:ok, "wss://mock.dingtalk.com/gateway"}

        _ ->
          {:ok, "wss://mock.dingtalk.com/gateway"}
      end
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("[Dingtalk.Receiver] Connected")
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        process_incoming(data)

      _ ->
        Logger.warning("[Dingtalk.Receiver] Invalid JSON: #{msg}")
    end

    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("[Dingtalk.Receiver] Disconnected: #{inspect(reason)}")
    {:reconnect, state}
  end

  defp process_incoming(data) do
    case data do
      %{"type" => "EVENT", "headers" => %{"topic" => topic}, "data" => payload} ->
        handle_event(topic, payload, data)

      %{"type" => "SYSTEM", "headers" => %{"topic" => "ping"}} ->
        :ok

      _ ->
        Logger.debug("[Dingtalk.Receiver] Unhandled message: #{inspect(data)}")
    end
  end

  defp handle_event(topic, payload, original_data) do
    if String.starts_with?(topic, "chat.receive") do
      content = extract_content(payload)
      sender_id = payload["senderId"]
      conversation_id = payload["conversationId"] || payload["openConversationId"]

      SignalHub.emit("dingtalk.message.text", %{
        provider: "dingtalk",
        event: "message.text",
        action: "received",
        actor: sender_id,
        origin: %{
          channel: "dingtalk",
          conversation_id: conversation_id,
          sender_id: sender_id
        },
        content: content,
        payload: original_data
      })
    end
  end

  defp extract_content(%{"text" => %{"content" => content}}), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(_), do: ""
end

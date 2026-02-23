defmodule Cortex.Channels.Dingtalk.Dispatcher do
  @moduledoc """
  Dispatches outgoing messages to DingTalk via Client API.
  Subscribes to agent responses.
  """
  use GenServer
  require Logger
  alias Cortex.SignalHub
  alias Cortex.Channels.Dingtalk.Client
  alias Cortex.Channels.Shared.TextChunker

  # 4000 characters is a safe limit for DingTalk markdown/text
  @msg_limit 4000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    SignalHub.subscribe("agent.chat.response")
    # Also subscribe to tool outputs or other events if needed
    Logger.info("[Dingtalk.Dispatcher] Started")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "agent.chat.response", data: data}}, state) do
    # Check if this response is meant for DingTalk
    # The 'origin' field in signal usually contains the source channel info.

    origin = data[:origin] || data["origin"] || %{}
    channel = origin[:channel] || origin["channel"]

    if channel == "dingtalk" do
      conversation_id = origin[:conversation_id] || origin["conversation_id"]
      content = data[:content] || data["content"] || ""

      dispatch_message(conversation_id, content)
    end

    {:noreply, state}
  end

  defp dispatch_message(conversation_id, content) do
    # Chunk long messages
    chunks = TextChunker.chunk_text(content, @msg_limit)

    Enum.each(chunks, fn chunk ->
      case Client.send_message(conversation_id, chunk) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.error("[Dingtalk.Dispatcher] Failed to send message: #{inspect(reason)}")
      end
    end)
  end
end

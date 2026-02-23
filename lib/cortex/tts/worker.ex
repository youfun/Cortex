defmodule Cortex.TTS.Worker do
  @moduledoc """
  Handles TTS task execution by calling the remote Python bridge.
  """
  use GenServer
  require Logger
  alias Cortex.SignalHub
  alias Cortex.TTS.Router
  alias Cortex.TTS.NodeManager

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Subscribe to tts.request signals
    SignalHub.subscribe("tts.request")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "tts.request", data: data}}, state) do
    payload = data.payload || %{}

    case Router.select_node(payload) do
      {:ok, node_id} ->
        # Asynchronously process to not block the GenServer
        Task.start(fn -> execute_tts(node_id, payload) end)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("[TTS.Worker] Failed to route request: #{inspect(reason)}")
        # Emit error signal
        emit_result({:error, reason}, payload)
        {:noreply, state}
    end
  end

  defp execute_tts(node_id, payload) do
    nodes = NodeManager.list_nodes()
    node = Map.get(nodes, node_id)

    if node do
      # In a real scenario, node.info would contain the internal IP/URL
      # For now, let's assume it has an 'api_url'
      api_url = node.info[:api_url] || node.info["api_url"]

      if api_url do
        call_python_bridge(api_url, payload)
      else
        Logger.error("[TTS.Worker] Node #{node_id} missing api_url")
        emit_result({:error, :missing_api_url}, payload)
      end
    else
      emit_result({:error, :node_not_found}, payload)
    end
  end

  defp call_python_bridge(api_url, payload) do
    model_type = payload[:model_type] || payload["model_type"] || "custom_voice"
    endpoint = "#{api_url}/tts/#{model_type}"

    # Extract params and text
    text = payload[:text] || payload["text"]
    params = payload[:params] || payload["params"] || %{}

    body = Map.merge(params, %{text: text})

    case Req.post(endpoint, json: body, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: resp_body}} ->
        # Assume Python returns JSON with audio_url and duration
        emit_result({:ok, resp_body}, payload)

      {:ok, resp} ->
        Logger.error("[TTS.Worker] Python bridge returned status #{resp.status}")
        emit_result({:error, "Bridge error: #{resp.status}"}, payload)

      {:error, reason} ->
        Logger.error("[TTS.Worker] Failed to call Python bridge: #{inspect(reason)}")
        emit_result({:error, reason}, payload)
    end
  end

  defp emit_result(result, request_payload) do
    context = request_payload[:context] || request_payload["context"] || %{}

    data =
      case result do
        {:ok, bridge_resp} ->
          %{
            audio_url: bridge_resp["audio_url"] || bridge_resp[:audio_url],
            duration_ms: bridge_resp["duration_ms"] || bridge_resp[:duration_ms],
            format: bridge_resp["format"] || bridge_resp[:format] || "wav",
            context: context
          }

        {:error, reason} ->
          %{
            error: inspect(reason),
            context: context
          }
      end

    SignalHub.emit("tts.result", %{
      provider: "tool",
      event: "tts",
      action: result_action(result),
      actor: "tts_worker",
      origin: %{channel: "system", client: "tts_worker", platform: "server"},
      payload: data
    })
  end

  defp result_action({:ok, _}), do: "resolve"
  defp result_action({:error, _}), do: "reject"
end

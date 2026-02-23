defmodule Cortex.Channels.Dingtalk.Client do
  @moduledoc """
  Manages DingTalk API interactions and Access Token lifecycle.
  """
  use GenServer
  require Logger
  alias Cortex.Channels

  @base_url "https://api.dingtalk.com"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_token do
    GenServer.call(__MODULE__, :get_token)
  end

  def send_message(conversation_id, content) do
    GenServer.call(__MODULE__, {:send_message, conversation_id, content})
  end

  # -- GenServer Callbacks --

  @impl true
  def init(_opts) do
    # Load config initially
    conf = get_config()

    state = %{
      client_id: conf[:client_id],
      client_secret: conf[:client_secret],
      access_token: nil,
      expires_at: 0
    }

    # Initial fetch
    send(self(), :refresh_token)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_token, _from, state) do
    if token_valid?(state) do
      {:reply, {:ok, state.access_token}, state}
    else
      case fetch_access_token(state.client_id, state.client_secret) do
        {:ok, token, expires_in} ->
          new_state = update_token_state(state, token, expires_in)
          {:reply, {:ok, token}, new_state}

        error ->
          {:reply, error, state}
      end
    end
  end

  @impl true
  def handle_call({:send_message, conversation_id, content}, _from, state) do
    # Refresh config on send? Or rely on periodic refresh?
    # For now, keep using state credentials.

    state =
      if token_valid?(state) do
        state
      else
        case fetch_access_token(state.client_id, state.client_secret) do
          {:ok, token, expires_in} -> update_token_state(state, token, expires_in)
          _ -> state
        end
      end

    result = post_message(state.access_token, conversation_id, content)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:refresh_token, state) do
    # Re-read config to pick up changes
    conf = get_config()
    new_state = %{state | client_id: conf[:client_id], client_secret: conf[:client_secret]}

    case fetch_access_token(new_state.client_id, new_state.client_secret) do
      {:ok, token, expires_in} ->
        Logger.info("[Dingtalk.Client] Token refreshed, expires in #{expires_in}s")
        Process.send_after(self(), :refresh_token, floor(expires_in * 0.9 * 1000))
        {:noreply, update_token_state(new_state, token, expires_in)}

      {:error, reason} ->
        Logger.error("[Dingtalk.Client] Failed to refresh token: #{inspect(reason)}")
        Process.send_after(self(), :refresh_token, 60_000)
        {:noreply, new_state}
    end
  end

  # -- Internal Helpers --

  defp get_config do
    # Fetch from Context which merges DB + Env
    Channels.get_config("dingtalk")
  end

  defp token_valid?(%{access_token: nil}), do: false

  defp token_valid?(%{expires_at: expires_at}) do
    System.system_time(:second) < expires_at
  end

  defp update_token_state(state, token, expires_in) do
    %{state | access_token: token, expires_at: System.system_time(:second) + expires_in}
  end

  defp fetch_access_token(nil, _), do: {:error, :missing_credentials}
  defp fetch_access_token(_, nil), do: {:error, :missing_credentials}

  defp fetch_access_token(key, secret) do
    url = "#{@base_url}/v1.0/oauth2/accessToken"
    body = %{"appKey" => key, "appSecret" => secret}

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: %{"accessToken" => token, "expireIn" => expire_in}}} ->
        {:ok, token, expire_in}

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_message(token, conversation_id, content) do
    url = "#{@base_url}/v1.0/robot/groupMessages/send"

    headers = [
      {"x-acs-dingtalk-access-token", token}
    ]

    body = %{
      "openConversationId" => conversation_id,
      "msgParam" => content_to_msg_param(content),
      "msgKey" => "sampleMarkdown"
    }

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: %{"processQueryKey" => _} = resp}} ->
        {:ok, resp}

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_to_msg_param(text) when is_binary(text) do
    %{
      "title" => "New Message",
      "text" => text
    }
    |> Jason.encode!()
  end
end

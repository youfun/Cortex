defmodule Cortex.Channels.Telegram.Client do
  @moduledoc """
  Telegram Bot API 客户端，基于 Req 实现。
  提供无状态的 API 调用封装。
  """
  require Logger

  @api_base_url "https://api.telegram.org"

  @doc """
  根据配置创建一个 Req 实例。
  """
  def new(token) when is_binary(token) do
    Req.new(base_url: "#{@api_base_url}/bot#{token}")
  end

  @doc """
  验证 Bot Token 并获取 Bot 信息。
  """
  def get_me(client) do
    client
    |> Req.get(url: "/getMe")
    |> handle_response()
  end

  @doc """
  获取更新消息。
  支持 offset, limit, timeout (用于长轮询)。
  """
  def get_updates(client, opts \\ []) do
    # Telegram long-poll timeout is in seconds; align Req receive_timeout (ms)
    # slightly above it to avoid client-side timeouts.
    receive_timeout =
      case Keyword.get(opts, :timeout) do
        t when is_integer(t) and t > 0 -> (t + 5) * 1000
        _ -> nil
      end

    req_opts =
      if receive_timeout do
        [url: "/getUpdates", params: opts, receive_timeout: receive_timeout]
      else
        [url: "/getUpdates", params: opts]
      end

    client
    |> Req.get(req_opts)
    |> handle_response()
  end

  @doc """
  获取当前 webhook 状态信息。
  若 url 不为空，长轮询 getUpdates 将无法收到消息。
  """
  def get_webhook_info(client) do
    client
    |> Req.get(url: "/getWebhookInfo")
    |> handle_response()
  end

  @doc """
  发送文本消息。
  """
  def send_message(client, chat_id, text, opts \\ []) do
    # 支持解析模式 (markdown, html 等)
    body = Map.merge(%{chat_id: chat_id, text: text}, Map.new(opts))

    client
    |> Req.post(url: "/sendMessage", json: body)
    |> handle_response()
  end

  @doc """
  发送照片。
  `photo` 可以是 file_id, URL, 或者 {:file, "path/to/file"}。
  """
  def send_photo(client, chat_id, photo, opts \\ []) do
    # Req 的 multipart 支持非常方便
    # 如果是本地文件，请确保传入结构符合 Req 要求
    body = Map.merge(%{chat_id: chat_id, photo: photo}, Map.new(opts))

    client
    |> Req.post(url: "/sendPhoto", json: body)
    |> handle_response()
  end

  @doc """
  发送文件。
  `document` 可以是 file_id, URL, 或者 {:file, "path/to/file"}。
  """
  def send_document(client, chat_id, document, opts \\ []) do
    body = Map.merge(%{chat_id: chat_id, document: document}, Map.new(opts))

    client
    |> Req.post(url: "/sendDocument", json: body)
    |> handle_response()
  end

  @doc """
  发送语音。
  `voice` 可以是 file_id, URL, 或者 {:file, "path/to/file"}。
  """
  def send_voice(client, chat_id, voice, opts \\ []) do
    body = Map.merge(%{chat_id: chat_id, voice: voice}, Map.new(opts))

    client
    |> Req.post(url: "/sendVoice", json: body)
    |> handle_response()
  end

  @doc """
  获取文件信息（用于下载）。
  """
  def get_file(client, file_id) do
    client
    |> Req.get(url: "/getFile", params: [file_id: file_id])
    |> handle_response()
  end

  @doc """
  下载文件原始数据。
  注意：下载使用的是 /file/bot<token>/<file_path> 路径。
  """
  def download_file(token, file_path) do
    url = "#{@api_base_url}/file/bot#{token}/#{file_path}"
    Req.get(url)
  end

  # 私有处理逻辑
  defp handle_response({:ok, %{status: 200, body: %{"ok" => true, "result" => result}}}) do
    {:ok, result}
  end

  defp handle_response({:ok, %{body: %{"ok" => false, "description" => desc}}}) do
    Logger.error("Telegram API Error: #{desc}")
    {:error, desc}
  end

  defp handle_response({:ok, %{status: status} = resp}) when is_integer(status) do
    Logger.error("Telegram Unexpected Status: status=#{status} resp=#{inspect(resp)}")
    {:error, {:http_status, status}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("Telegram Request Failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_response(other) do
    Logger.error("Telegram Unexpected Response: #{inspect(other)}")
    {:error, :unexpected_response}
  end
end

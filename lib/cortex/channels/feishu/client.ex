defmodule Cortex.Channels.Feishu.Client do
  @moduledoc """
  Feishu Open Platform API 客户端，基于 Req 实现。
  提供无状态的 API 调用封装。
  """
  require Logger

  @api_base_url "https://open.feishu.cn"

  def new do
    Req.new(base_url: @api_base_url)
  end

  @doc """
  获取 tenant_access_token (internal)。
  """
  def get_tenant_access_token(client, app_id, app_secret) do
    body = %{app_id: app_id, app_secret: app_secret}

    client
    |> Req.post(url: "/open-apis/auth/v3/tenant_access_token/internal/", json: body)
    |> handle_token_response()
  end

  @doc """
  发送文本消息。
  receive_id_type 常用: chat_id / open_id / user_id / union_id / email。
  """
  def send_text_message(client, token, receive_id_type, receive_id, text) do
    body = %{
      receive_id: receive_id,
      msg_type: "text",
      content: Jason.encode!(%{text: text})
    }

    client
    |> Req.post(
      url: "/open-apis/im/v1/messages",
      params: [receive_id_type: receive_id_type],
      json: body,
      headers: [{"Authorization", "Bearer #{token}"}]
    )
    |> handle_response()
  end

  defp handle_token_response({:ok, %{status: 200, body: %{"code" => 0} = body}}) do
    {:ok, body}
  end

  defp handle_token_response({:ok, %{status: status, body: body}}) do
    Logger.error("Feishu token request failed: #{status} #{inspect(body)}")
    {:error, body}
  end

  defp handle_token_response({:error, reason}) do
    Logger.error("Feishu token request error: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_response({:ok, %{status: 200, body: %{"code" => 0, "data" => data}}}) do
    {:ok, data}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Logger.error("Feishu API Error: #{status} #{inspect(body)}")
    {:error, body}
  end

  defp handle_response({:error, reason}) do
    Logger.error("Feishu Request Failed: #{inspect(reason)}")
    {:error, reason}
  end
end

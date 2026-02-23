defmodule CortexWeb.FeishuWebhookController do
  use CortexWeb, :controller
  require Logger
  alias Cortex.SignalHub

  def webhook(conn, params) do
    case params do
      %{"type" => "url_verification", "challenge" => challenge} = body ->
        if verified_token?(body["token"]) do
          json(conn, %{challenge: challenge})
        else
          send_resp(conn, 401, "invalid token")
        end

      %{"schema" => "2.0", "header" => header, "event" => event} ->
        if verified_token?(header["token"]) do
          handle_event(header, event)
          json(conn, %{code: 0})
        else
          send_resp(conn, 401, "invalid token")
        end

      _ ->
        send_resp(conn, 400, "bad request")
    end
  end

  defp verified_token?(incoming_token) do
    cfg = Application.get_env(:cortex, :feishu, [])
    token = cfg[:verification_token]

    if token && token != "" do
      incoming_token == token
    else
      false
    end
  end

  defp handle_event(%{"event_type" => "im.message.receive_v1"} = header, event) do
    message = event["message"] || %{}
    sender = event["sender"] || %{}

    if message["message_type"] == "text" do
      chat_id = message["chat_id"]
      message_id = message["message_id"]
      sender_id = sender["sender_id"] || %{}
      open_id = sender_id["open_id"] || sender_id["user_id"] || sender_id["union_id"]
      raw_content = message["content"]
      text = decode_text_content(raw_content)

      origin = %{
        channel: "feishu",
        client: "webhook",
        platform: "server",
        app_id: header["app_id"],
        tenant_key: header["tenant_key"],
        chat_id_hash: "c_#{chat_id}",
        user_id_hash: "u_#{open_id}",
        message_id: message_id
      }

      SignalHub.emit(
        "feishu.message.text",
        %{
          provider: "feishu",
          event: "message",
          action: "receive",
          actor: "user",
          origin: origin,
          chat_id: chat_id,
          text: text,
          sender_id: sender_id,
          message_id: message_id
        },
        source: "/feishu/webhook"
      )
    end
  end

  defp handle_event(_header, _event) do
    :ok
  end

  defp decode_text_content(nil), do: ""

  defp decode_text_content(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"text" => text}} -> text
      _ -> content
    end
  end

  defp decode_text_content(_), do: ""
end

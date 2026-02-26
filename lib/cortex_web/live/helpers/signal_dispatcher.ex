defmodule CortexWeb.SignalDispatcher do
  @moduledoc """
  Signal dispatching extracted from JidoLive.
  """

  import Phoenix.Component, only: [assign: 2]

  import Phoenix.LiveView,
    only: [stream_insert: 3, stream_insert: 4, push_event: 3, send_update: 2]

  alias Cortex.Conversations
  alias CortexWeb.AgentLiveHelpers, as: Helpers
  alias CortexWeb.PermissionHelpers

  def dispatch(type, signal, socket) do
    case type do
      "agent.response" -> handle_agent_response(signal, socket)
      "conversation.created" -> handle_conversation_created(signal, socket)
      "conversation.updated" -> handle_conversation_updated(signal, socket)
      "conversation.message.created" -> handle_message_created(signal, socket)
      "conversation.message.updated" -> handle_message_updated(signal, socket)
      "tool.call.request" -> handle_tool_call_request(signal, socket)
      "tool.call.result" -> handle_tool_result(signal, socket)
      "tool.call.blocked" -> handle_tool_blocked(signal, socket)
      "tool.result." <> _tool_name -> handle_tool_result(signal, socket)
      "tool.stream.shell" -> handle_tool_stream(signal, socket)
      "file.changed." <> _ -> handle_file_changed(signal, socket)
      "skill.loaded" -> handle_skill_loaded(signal, socket)
      "agent.think" -> handle_think(signal, socket)
      "agent.response.chunk" -> handle_response_chunk(signal, socket)
      "agent.error" -> handle_error(signal, socket)
      "agent.turn.end" -> handle_turn_complete(signal, socket)
      "agent.run.end" -> handle_run_end(signal, socket)
      "permission.request" -> handle_permission_request(signal, socket)
      "tts.result" -> handle_tts_result(signal, socket)
      _ -> socket
    end
  end

  defp handle_tts_result(signal, socket) do
    payload = Helpers.signal_payload(signal)
    context = payload[:context] || payload["context"] || %{}

    # 检查是否属于当前会话
    # 如果 context 中有 session_id，则匹配它；如果没有，可能需要其他逻辑
    is_current_session =
      case context[:session_id] || context["session_id"] do
        # 如果没指定，暂时假设是当前活动的
        nil -> true
        sid -> sid == socket.assigns.session_id
      end

    if (is_current_session and Map.has_key?(payload, :audio_url)) or
         Map.has_key?(payload, "audio_url") do
      audio_url = payload[:audio_url] || payload["audio_url"]
      push_event(socket, "play_audio", %{url: audio_url})
    else
      socket
    end
  end

  defp handle_agent_response(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      assign(socket, is_thinking: false)
    else
      socket
    end
  end

  defp handle_conversation_created(signal, socket) do
    payload = Helpers.signal_payload(signal)
    workspace_id = payload[:workspace_id] || payload["workspace_id"]
    conversation = payload[:conversation] || payload["conversation"]

    if workspace_id == socket.assigns.workspace.id and is_map(conversation) do
      stream_insert(socket, :conversations, conversation, at: 0)
    else
      socket
    end
  end

  defp handle_conversation_updated(signal, socket) do
    payload = Helpers.signal_payload(signal)
    workspace_id = payload[:workspace_id] || payload["workspace_id"]
    conversation = payload[:conversation] || payload["conversation"]

    if workspace_id == socket.assigns.workspace.id and is_map(conversation) and
         conversation.status == "active" do
      stream_insert(socket, :conversations, conversation, at: 0)
    else
      socket
    end
  end

  defp handle_message_created(signal, socket) do
    payload = Helpers.signal_payload(signal)
    msg = payload[:message] || payload["message"]
    session_id = payload[:session_id] || payload["session_id"]

    socket =
      if is_map(msg) and Helpers.belongs_to_session?(signal, socket) do
        stream_insert(socket, :messages, msg)
      else
        socket
      end

    if is_binary(session_id) do
      case Conversations.get_conversation(session_id) do
        %Cortex.Conversations.Conversation{workspace_id: ws_id, status: "active"} = conv ->
          if ws_id == socket.assigns.workspace.id do
            stream_insert(socket, :conversations, conv, at: 0)
          else
            socket
          end

        _ ->
          socket
      end
    else
      socket
    end
  end

  defp handle_message_updated(signal, socket) do
    payload = Helpers.signal_payload(signal)
    msg = payload[:message] || payload["message"]

    if is_map(msg) and Helpers.belongs_to_session?(signal, socket) do
      stream_insert(socket, :messages, msg)
    else
      socket
    end
  end

  defp handle_tool_result(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      socket = adjust_pending_tool_calls(socket, -1)
      payload = Helpers.signal_payload(signal)
      result = Map.get(payload, :result, payload)

      _content =
        cond do
          is_binary(result) ->
            result

          is_map(result) and is_binary(Map.get(result, :output)) ->
            Map.get(result, :output)

          true ->
            inspect(result)
        end

      socket
    else
      socket
    end
  end

  defp handle_tool_call_request(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      adjust_pending_tool_calls(socket, 1)
    else
      socket
    end
  end

  defp handle_tool_stream(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      payload = Helpers.signal_payload(signal)

      send_update(CortexWeb.Components.TerminalComponent,
        id: "shell-terminal",
        shell_chunk: payload[:chunk] || payload["chunk"]
      )

      socket
    else
      socket
    end
  end

  defp handle_file_changed(signal, socket) do
    payload = Helpers.signal_payload(signal)
    path = payload[:path] || payload["path"]
    
    # Track file in conversation
    socket = track_file(socket, path)
    
    # Notify editor component to refresh if file is open
    send_update(CortexWeb.EditorComponent, 
      id: "editor-component", 
      action: :refresh_file, 
      path: path
    )
    
    push_event(socket, "file_changed", %{path: path})
  end

  defp track_file(socket, path) when is_binary(path) do
    files = socket.assigns[:conversation_files] || []
    
    if path not in files do
      Phoenix.Component.assign(socket, conversation_files: [path | files])
    else
      socket
    end
  end

  defp track_file(socket, _), do: socket

  defp handle_skill_loaded(signal, socket) do
    payload = Helpers.signal_payload(signal)

    Helpers.stream_ui_message(socket, %{
      content: "✅ Skill loaded: #{payload[:name] || payload["name"]}"
    })
  end

  defp handle_think(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      payload = Helpers.signal_payload(signal)

      assign(socket,
        is_thinking: true,
        plan_thought_text: payload[:thought] || payload["thought"] || ""
      )
    else
      socket
    end
  end

  defp handle_response_chunk(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      payload = Helpers.signal_payload(signal)
      message_id = payload[:message_id] || payload["message_id"]
      chunk = payload[:chunk] || payload["chunk"]

      Helpers.accumulate_stream_chunk(socket, message_id, chunk)
    else
      socket
    end
  end

  defp handle_error(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      payload = Helpers.signal_payload(signal)

      socket
      |> Helpers.stream_ui_message(%{
        content_type: "error",
        content: "Error: #{payload[:reason] || payload["reason"]}"
      })
      |> assign(is_thinking: false)
    else
      socket
    end
  end

  defp handle_turn_complete(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      socket
      |> Helpers.clear_streaming_state()
      |> assign(pending_tool_calls_count: 0)
    else
      socket
    end
  end

  defp handle_run_end(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      socket
      |> Helpers.clear_streaming_state()
      |> assign(pending_tool_calls_count: 0)
    else
      socket
    end
  end

  defp adjust_pending_tool_calls(socket, delta) do
    current = socket.assigns.pending_tool_calls_count || 0
    next = max(current + delta, 0)
    assign(socket, pending_tool_calls_count: next)
  end

  defp handle_tool_blocked(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      payload = Helpers.signal_payload(signal)

      Helpers.stream_ui_message(socket, %{
        content_type: "notification",
        content: "Tool call blocked: #{payload[:reason] || payload["reason"] || "unknown reason"}"
      })
    else
      socket
    end
  end

  defp handle_permission_request(signal, socket) do
    if Helpers.belongs_to_session?(signal, socket) do
      payload = Helpers.signal_payload(signal)

      # action 在信号顶层 data 中，不在 payload 里
      action =
        case signal.data[:action] || signal.data["action"] do
          # permission.request 通常是写操作
          "request" -> :write
          other when is_binary(other) -> String.to_existing_atom(other)
          other -> other || :read
        end

      request = %{
        request_id: payload[:request_id] || payload["request_id"],
        path: payload[:path] || payload["path"] || "unknown",
        action: action,
        # Surface tool/command metadata if present for UI display.
        tool: payload[:tool] || payload["tool"],
        command: payload[:command] || payload["command"],
        reason: payload[:reason] || payload["reason"],
        params: payload
      }

      PermissionHelpers.enqueue(socket, request)
    else
      socket
    end
  end
end

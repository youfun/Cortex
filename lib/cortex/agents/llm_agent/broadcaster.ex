defmodule Cortex.Agents.LLMAgent.Broadcaster do
  @moduledoc """
  信号广播模块。

  负责将 LLMAgent 内部事件转换为标准化的 SignalHub 信号。
  """

  alias Cortex.SignalCatalog
  alias Cortex.SignalHub

  @doc """
  发射信号到 SignalHub。

  ## 参数
  - `session_id` - 会话 ID
  - `msg` - 内部消息元组
  - `opts` - 可选参数（如 model_name, tool_name）
  """
  def emit(session_id, msg, opts \\ [])

  def emit(session_id, {:agent_response, content}, opts) do
    SignalHub.emit(
      SignalCatalog.agent_response(),
      %{
        provider: "agent",
        event: "response",
        action: "finish",
        actor: "llm_agent",
        origin: agent_origin(session_id),
        session_id: session_id,
        conversation_id: conversation_id_from_session(session_id),
        model_name: Keyword.get(opts, :model_name),
        content: content
      },
      source: "/agent/llm"
    )
  end

  def emit(session_id, {:agent_response_start, message_id}, _opts) do
    SignalHub.emit(
      SignalCatalog.agent_response_start(),
      %{
        provider: "agent",
        event: "response",
        action: "start",
        actor: "llm_agent",
        origin: agent_origin(session_id),
        session_id: session_id,
        message_id: message_id
      },
      source: "/agent/llm"
    )
  end

  def emit(session_id, {:agent_response_chunk, message_id, chunk}, _opts) do
    SignalHub.emit(
      SignalCatalog.agent_response_chunk(),
      %{
        provider: "agent",
        event: "response",
        action: "chunk",
        actor: "llm_agent",
        origin: agent_origin(session_id),
        session_id: session_id,
        message_id: message_id,
        chunk: chunk
      },
      source: "/agent/llm"
    )
  end

  def emit(session_id, {:tool_result, call_id, output}, opts) do
    tool_name = Keyword.get(opts, :tool_name, "unknown")

    SignalHub.emit(
      SignalCatalog.tool_call_result(),
      %{
        provider: "agent",
        event: "tool",
        action: "call_result",
        actor: "llm_agent",
        origin: agent_origin(session_id),
        session_id: session_id,
        call_id: call_id,
        result: output,
        tool: tool_name
      },
      source: "/agent/llm"
    )
  end

  def emit(session_id, {:agent_error, reason}, _opts) do
    SignalHub.emit(
      SignalCatalog.agent_error(),
      %{
        provider: "agent",
        event: "error",
        action: "notify",
        actor: "llm_agent",
        origin: agent_origin(session_id),
        session_id: session_id,
        reason: reason
      },
      source: "/agent/llm"
    )
  end

  def emit(session_id, {:turn_complete, status}, _opts) do
    SignalHub.emit(
      SignalCatalog.agent_turn_end(),
      %{
        provider: "agent",
        event: "turn",
        action: "end",
        actor: "llm_agent",
        origin: agent_origin(session_id),
        session_id: session_id,
        status: status
      },
      source: "/agent/llm"
    )
  end

  def emit(_session_id, _msg, _opts), do: :ok

  # Private helpers

  defp agent_origin(session_id) do
    %{
      channel: "agent",
      client: "llm_agent",
      platform: "server",
      session_id: session_id
    }
  end

  defp conversation_id_from_session("session_" <> rest), do: rest
  defp conversation_id_from_session(session_id), do: session_id
end

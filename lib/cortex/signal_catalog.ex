defmodule Cortex.SignalCatalog do
  @moduledoc """
  Unified signal event catalog.

  All signal types should be defined here to keep the contract stable and auditable.
  """

  # === Session lifecycle ===
  @session_start "session.start"
  @session_shutdown "session.shutdown"

  # === Agent lifecycle ===
  @agent_chat_request "agent.chat.request"
  @agent_chat_handled "agent.chat.handled"
  @agent_turn_start "agent.turn.start"
  @agent_turn_end "agent.turn.end"
  @agent_run_end "agent.run.end"
  @agent_response "agent.response"
  @agent_response_start "agent.response.start"
  @agent_response_chunk "agent.response.chunk"
  @agent_error "agent.error"
  @agent_retry "agent.retry"

  # === Input & context ===
  @context_input_transform "context.input.transform"
  @context_build_start "context.build.start"
  @context_build_result "context.build.result"

  # === Tool calls ===
  @tool_call_request "tool.call.request"
  @tool_call_blocked "tool.call.blocked"
  @tool_call_result "tool.call.result"

  # === Permission ===
  @permission_request "permission.request"
  @permission_resolved "permission.resolved"

  # === Session maintenance ===
  @session_compact_request "session.compact.request"
  @session_compact_result "session.compact.result"

  # === Model/strategy ===
  @model_select "model.select"
  @strategy_select "strategy.select"

  def session_start, do: @session_start
  def session_shutdown, do: @session_shutdown
  def agent_chat_request, do: @agent_chat_request
  def agent_chat_handled, do: @agent_chat_handled
  def agent_turn_start, do: @agent_turn_start
  def agent_turn_end, do: @agent_turn_end
  def agent_run_end, do: @agent_run_end
  def agent_response, do: @agent_response
  def agent_response_start, do: @agent_response_start
  def agent_response_chunk, do: @agent_response_chunk
  def agent_error, do: @agent_error
  def agent_retry, do: @agent_retry
  def context_input_transform, do: @context_input_transform
  def context_build_start, do: @context_build_start
  def context_build_result, do: @context_build_result
  def tool_call_request, do: @tool_call_request
  def tool_call_blocked, do: @tool_call_blocked
  def tool_call_result, do: @tool_call_result
  def permission_request, do: @permission_request
  def permission_resolved, do: @permission_resolved
  def session_compact_request, do: @session_compact_request
  def session_compact_result, do: @session_compact_result
  def model_select, do: @model_select
  def strategy_select, do: @strategy_select

  @doc "Returns the full standard event catalog."
  def catalog do
    [
      @session_start,
      @session_shutdown,
      @agent_chat_request,
      @agent_chat_handled,
      @agent_turn_start,
      @agent_turn_end,
      @agent_run_end,
      @agent_response,
      @agent_response_start,
      @agent_response_chunk,
      @agent_error,
      @agent_retry,
      @context_input_transform,
      @context_build_start,
      @context_build_result,
      @tool_call_request,
      @tool_call_blocked,
      @tool_call_result,
      @permission_request,
      @permission_resolved,
      @session_compact_request,
      @session_compact_result,
      @model_select,
      @strategy_select
    ]
  end

  @doc "Check if a signal type is part of the standard catalog."
  def valid?(type) when is_binary(type), do: type in catalog()
  def valid?(_type), do: false
end

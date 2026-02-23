defmodule Cortex.Agents.LLMAgent.LoopHandler do
  @moduledoc """
  LLM 循环处理模块。

  负责：
  - 处理 LLM 循环成功/失败结果
  - 启动和取消循环
  - Steering 队列管理
  - Hook 集成
  """

  require Logger

  alias Cortex.Agents.AgentLoop
  alias Cortex.Agents.Compaction
  alias Cortex.Agents.HookRunner
  alias Cortex.Agents.Steering
  alias Cortex.Agents.LLMAgent.Broadcaster
  alias Cortex.Agents.LLMAgent.ToolExecution
  alias Cortex.SignalCatalog
  alias Cortex.SignalHub
  alias Cortex.History.Tape.{Store, EntryBuilder}

  @doc """
  处理 LLM 循环成功结果。

  ## 参数
  - `response` - LLM 响应（ReqLLM.Response）
  - `state` - Agent 状态

  ## 返回
  `{:noreply, new_state}`
  """
  def on_ok(response, state) do
    Logger.debug("[LoopHandler] ===== LOOP_RESULT RECEIVED (SUCCESS) =====")

    # Clear any in-flight loop handle
    state = %{state | loop_ref: nil, loop: nil}

    new_llm_context = response.context
    assistant_msg = response.message
    text_content = ReqLLM.Response.text(response) || ""
    tool_calls = ReqLLM.Response.tool_calls(response) || []

    tool_calls =
      if tool_calls == [] do
        case response do
          %{message: %{tool_calls: calls}} when is_list(calls) -> calls
          _ -> tool_calls
        end
      else
        tool_calls
      end

    Logger.debug("[LoopHandler] response.message: #{inspect(assistant_msg, pretty: true)}")
    Logger.debug("[LoopHandler] extracted tool_calls: #{inspect(tool_calls, pretty: true)}")

    # Tape 写入：assistant message
    if text_content != "" do
      Store.append(
        state.session_id,
        EntryBuilder.message("assistant", text_content, session_id: state.session_id)
      )
    end

    # Tape 写入：tool_calls
    if tool_calls != [] do
      normalized_calls = normalize_tool_calls(tool_calls)

      Store.append(
        state.session_id,
        EntryBuilder.tool_call(normalized_calls, session_id: state.session_id)
      )
    end

    if text_content != "" do
      Broadcaster.emit(state.session_id, {:agent_response, text_content},
        model_name: state.config.model
      )
    end

    if tool_calls == [] do
      Logger.debug("[LoopHandler] No tool calls, turn complete. Checking steering...")

      # on_agent_end Hook 调用
      HookRunner.run_notify(state.hooks, :on_agent_end, state)

      case Steering.check(state.steering_queue) do
        {steering_msg, remaining_queue} ->
          Logger.info("[LoopHandler] Steering detected after response! Injecting user message.")

          user_msg = ReqLLM.Context.user(steering_msg.content)
          new_llm_context = ReqLLM.Context.append(new_llm_context, user_msg)

          state = %{
            state
            | steering_queue: remaining_queue,
              llm_context: new_llm_context
          }

          state = start(state, new_llm_context, state.config)

          {:noreply, %{state | status: :thinking}}

        nil ->
          Broadcaster.emit(state.session_id, {:turn_complete, :success}, [])

          duration_ms =
            case state.run_started_at do
              nil -> 0
              started_at -> max(0, now_ms() - started_at)
            end

          SignalHub.emit(
            SignalCatalog.agent_run_end(),
            %{
              provider: "agent",
              event: "agent",
              action: "run_end",
              actor: "llm_agent",
              origin: agent_origin(state.session_id),
              session_id: state.session_id,
              turn_count: state.turn_count,
              duration_ms: duration_ms
            },
            source: "/agent/llm"
          )

          {:noreply,
           %{
             state
             | llm_context: new_llm_context,
               status: :idle,
               loop_ref: nil,
               loop: nil,
               run_started_at: nil
           }}
      end
    else
      Logger.debug("[LoopHandler] Processing #{length(tool_calls)} tool calls")
      state = ToolExecution.process_calls(state, tool_calls, new_llm_context)

      {:noreply, state}
    end
  end

  @doc """
  处理 LLM 循环错误结果。

  ## 参数
  - `reason` - 错误原因
  - `state` - Agent 状态

  ## 返回
  `{:noreply, new_state}`
  """
  def on_error(reason, state) do
    Logger.error("[LoopHandler] ===== LOOP_RESULT RECEIVED (ERROR) =====")
    Logger.error("[LoopHandler] Error reason: #{inspect(reason, pretty: true, limit: :infinity)}")

    user_reason = Cortex.Agents.Retry.user_message(reason) || inspect(reason)
    Broadcaster.emit(state.session_id, {:agent_error, user_reason}, [])

    case Steering.check(state.steering_queue) do
      {steering_msg, remaining_queue} ->
        Logger.info("[LoopHandler] Steering detected after error! Injecting user message.")

        user_msg = ReqLLM.Context.user(steering_msg.content)
        new_llm_context = ReqLLM.Context.append(state.llm_context, user_msg)

        state = %{
          state
          | steering_queue: remaining_queue,
            llm_context: new_llm_context
        }

        state = start(state, new_llm_context, state.config)

        {:noreply, %{state | status: :thinking}}

      nil ->
        {:noreply, %{state | status: :idle, loop_ref: nil, loop: nil}}
    end
  end

  @doc """
  启动 LLM 循环。

  ## 参数
  - `state` - Agent 状态
  - `history` - LLM 上下文
  - `config` - 配置

  ## 返回
  更新后的 state
  """
  def start(state, history, config) do
    turn_id = "turn_#{state.turn_count + 1}_#{state.session_id}"

    SignalHub.emit(
      SignalCatalog.context_build_start(),
      %{
        provider: "agent",
        event: "context",
        action: "build_start",
        actor: "llm_agent",
        origin: agent_origin(state.session_id),
        session_id: state.session_id,
        turn_id: turn_id
      },
      source: "/agent/llm"
    )

    case HookRunner.run(state.hooks, :on_before_agent, state, %{context: history}) do
      {:ok, modifications, new_state} ->
        # 支持 Hook 返回 modifications map
        final_history =
          case modifications do
            %{context: modified_context} ->
              modified_context

            %{system_prompt: custom_prompt} ->
              # 临时替换 system prompt（仅当前 turn）
              messages = history.messages

              case messages do
                [%ReqLLM.Message{role: :system} | rest] ->
                  %{history | messages: [ReqLLM.Context.system(custom_prompt) | rest]}

                _ ->
                  %{history | messages: [ReqLLM.Context.system(custom_prompt) | messages]}
              end

            _ ->
              history
          end

        SignalHub.emit(
          SignalCatalog.context_build_result(),
          %{
            provider: "agent",
            event: "context",
            action: "build_result",
            actor: "llm_agent",
            origin: agent_origin(new_state.session_id),
            session_id: new_state.session_id,
            turn_id: turn_id,
            message_count: length(final_history.messages)
          },
          source: "/agent/llm"
        )

        do_start(new_state, final_history, config)

      {:halt, reason, new_state} ->
        Logger.warning("[LoopHandler] on_before_agent hook halted: #{inspect(reason)}")
        %{new_state | status: :idle, loop_ref: nil, loop: nil}
    end
  end

  @doc """
  取消进行中的循环。

  ## 参数
  - `state` - Agent 状态

  ## 返回
  更新后的 state
  """
  def cancel_inflight(%{loop: nil} = state), do: state

  def cancel_inflight(%{loop: loop} = state) do
    _ = AgentLoop.cancel(loop)
    %{state | loop: nil, loop_ref: nil}
  end

  # Private helpers

  defp do_start(state, history, config) do
    state = cancel_inflight(state)
    next_turn = state.turn_count + 1

    # 传递 hooks 和 agent_state 给 Compaction
    history =
      case Compaction.maybe_compact(history, config.model,
             hooks: state.hooks,
             agent_state: state
           ) do
        {:ok, compacted} -> compacted
      end

    case AgentLoop.run(state.session_id, history, config, turn_count: state.turn_count) do
      {:ok, loop} ->
        %{state | turn_count: next_turn, loop_ref: loop.ref, loop: loop}

      {:error, :max_turns} ->
        %{state | status: :idle, loop_ref: nil, loop: nil}
    end
  end

  defp normalize_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      %{
        id: tc.id,
        name: ReqLLM.ToolCall.name(tc),
        args: ReqLLM.ToolCall.args_map(tc)
      }
    end)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp agent_origin(session_id) do
    %{
      channel: "agent",
      client: "llm_agent",
      platform: "server",
      session_id: session_id
    }
  end
end

defmodule Cortex.Agents.AgentLoop do
  @moduledoc """
  Autonomous agent loop runner.
  Handles turn counting, timeout, and LLM streaming execution.
  """

  require Logger

  alias Cortex.LLM.Client
  alias Cortex.Memory.BudgetEnforcer
  alias Cortex.SignalCatalog
  alias Cortex.SignalHub
  alias Cortex.Tools.Registry, as: ToolRegistry
  alias Jido.Signal.TraceContext

  @max_turns 25
  @turn_timeout 120_000
  @receive_timeout 300_000
  @connect_timeout 60_000

  @type loop_handle :: %{
          ref: reference(),
          task_pid: pid(),
          timeout_ref: reference()
        }

  def run(session_id, context, config, opts \\ []) do
    turn_count = Keyword.get(opts, :turn_count, 0)
    max_turns = Keyword.get(opts, :max_turns, @max_turns)
    turn_timeout = Keyword.get(opts, :turn_timeout, @turn_timeout)
    loop_ref = Keyword.get(opts, :loop_ref, make_ref())

    if turn_count >= max_turns do
      emit_error(session_id, "Max turns (#{max_turns}) exceeded")
      emit_turn_complete(session_id, "max_turns")
      {:error, :max_turns}
    else
      SignalHub.emit(
        SignalCatalog.agent_turn_start(),
        %{
          provider: "agent",
          event: "turn",
          action: "start",
          actor: "agent_loop",
          origin: %{
            channel: "agent",
            client: "agent_loop",
            platform: "server",
            session_id: session_id
          },
          session_id: session_id,
          turn: turn_count + 1
        },
        source: "/agent/loop"
      )

      timeout_ref =
        Process.send_after(
          via_pid(session_id),
          {:loop_result, loop_ref, {:error, :turn_timeout}},
          turn_timeout
        )

      run_loop_fun = Keyword.get(opts, :run_loop_fun, &run_loop/3)
      trace_ctx = TraceContext.current()

      case Task.Supervisor.start_child(Cortex.AgentTaskSupervisor, fn ->
             if trace_ctx, do: TraceContext.set(trace_ctx)
             result = run_loop_fun.(session_id, context, config)
             Process.cancel_timer(timeout_ref)
             send(via_pid(session_id), {:loop_result, loop_ref, result})
           end) do
        {:ok, task_pid} ->
          {:ok, %{ref: loop_ref, task_pid: task_pid, timeout_ref: timeout_ref}}

        {:error, reason} ->
          Process.cancel_timer(timeout_ref)
          emit_error(session_id, "Failed to start loop task: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @spec cancel(loop_handle()) :: :ok
  def cancel(%{task_pid: task_pid, timeout_ref: timeout_ref})
      when is_pid(task_pid) and is_reference(timeout_ref) do
    Process.cancel_timer(timeout_ref)

    # Task.Supervisor children live under a DynamicSupervisor; terminate them via DynamicSupervisor API.
    if Process.alive?(task_pid) do
      DynamicSupervisor.terminate_child(Cortex.AgentTaskSupervisor, task_pid)
    end

    :ok
  end

  def cancel(_), do: :ok

  defp run_loop(session_id, context, config) do
    Logger.debug("[AgentLoop] Running LLM loop for session #{session_id}")

    tools = ToolRegistry.to_llm_format()
    message_id = "agent_" <> Integer.to_string(System.unique_integer([:positive]))

    SignalHub.emit(
      SignalCatalog.agent_response_start(),
      %{
        provider: "agent",
        event: "response",
        action: "start",
        actor: "agent_loop",
        origin: %{
          channel: "agent",
          client: "agent_loop",
          platform: "server",
          session_id: session_id
        },
        session_id: session_id,
        message_id: message_id
      },
      source: "/agent/loop"
    )

    opts =
      [
        tools: tools,
        receive_timeout: @receive_timeout,
        connect_timeout: @connect_timeout,
        on_chunk: fn chunk ->
          SignalHub.emit(
            SignalCatalog.agent_response_chunk(),
            %{
              provider: "agent",
              event: "response",
              action: "chunk",
              actor: "agent_loop",
              origin: %{
                channel: "agent",
                client: "agent_loop",
                platform: "server",
                session_id: session_id
              },
              session_id: session_id,
              message_id: message_id,
              chunk: chunk
            },
            source: "/agent/loop"
          )
        end
      ]

    # Check budget before LLM call
    case BudgetEnforcer.check_and_enforce(context, config.model) do
      {:ok, context} ->
        # Within budget, proceed normally
        context = run_context_hooks(session_id, context, config)
        execute_llm_call(session_id, context, config.model, message_id, opts)

      {:compacted, context} ->
        # Auto-compacted, proceed with compacted context
        Logger.info("[AgentLoop] Context auto-compacted before LLM call (session: #{session_id})")

        SignalHub.emit(
          "agent.context.compacted",
          %{
            provider: "agent",
            event: "context",
            action: "compacted",
            actor: "agent_loop",
            origin: %{
              channel: "agent",
              client: "agent_loop",
              platform: "server",
              session_id: session_id
            },
            session_id: session_id,
            message_id: message_id
          },
          source: "/agent/loop"
        )

        context = run_context_hooks(session_id, context, config)
        execute_llm_call(session_id, context, config.model, message_id, opts)

      {:error, :budget_exceeded} ->
        # Budget exceeded even after compaction
        Logger.error("[AgentLoop] Budget exceeded even after compaction (session: #{session_id})")

        SignalHub.emit(
          SignalCatalog.agent_error(),
          %{
            provider: "agent",
            event: "error",
            action: "notify",
            actor: "agent_loop",
            origin: %{
              channel: "agent",
              client: "agent_loop",
              platform: "server",
              session_id: session_id
            },
            session_id: session_id,
            reason: "Context too large, cannot proceed even after compaction"
          },
          source: "/agent/loop"
        )

        {:error, :context_too_large}

      {:error, reason} ->
        # Other errors
        Logger.error(
          "[AgentLoop] Budget enforcement failed: #{inspect(reason)} (session: #{session_id})"
        )

        {:error, reason}
    end
  end

  defp execute_llm_call(session_id, context, model, _message_id, opts) do
    Cortex.Agents.Retry.retry(
      fn -> Client.stream_chat(model, context, opts) end,
      fn class, attempt, delay ->
        Logger.warning(
          "[AgentLoop] Retrying LLM chat due to #{class} error (attempt #{attempt + 1}, delay #{delay}ms)"
        )

        SignalHub.emit(
          SignalCatalog.agent_retry(),
          %{
            provider: "agent",
            event: "retry",
            action: "attempt",
            actor: "agent_loop",
            origin: %{
              channel: "agent",
              client: "agent_loop",
              platform: "server",
              session_id: session_id
            },
            session_id: session_id,
            error_class: class,
            attempt: attempt + 1,
            delay_ms: delay
          },
          source: "/agent/loop"
        )
      end
    )
  end

  defp emit_error(session_id, reason) do
    SignalHub.emit(
      SignalCatalog.agent_error(),
      %{
        provider: "agent",
        event: "error",
        action: "notify",
        actor: "agent_loop",
        origin: %{
          channel: "agent",
          client: "agent_loop",
          platform: "server",
          session_id: session_id
        },
        session_id: session_id,
        reason: reason
      },
      source: "/agent/loop"
    )
  end

  defp emit_turn_complete(session_id, status) do
    SignalHub.emit(
      SignalCatalog.agent_turn_end(),
      %{
        provider: "agent",
        event: "turn",
        action: "end",
        actor: "agent_loop",
        origin: %{
          channel: "agent",
          client: "agent_loop",
          platform: "server",
          session_id: session_id
        },
        session_id: session_id,
        status: status
      },
      source: "/agent/loop"
    )
  end

  defp via_pid(session_id) do
    case Registry.lookup(Cortex.SessionRegistry, session_id) do
      [{pid, _}] -> pid
      _ -> self()
    end
  end

  defp run_context_hooks(session_id, %ReqLLM.Context{messages: messages} = context, config) do
    hooks = Cortex.Extensions.HookRegistry.get_hooks(session_id)

    agent_state = %{
      session_id: session_id,
      config: config,
      status: :thinking,
      turn_count: 0
    }

    data = %{messages: messages, model: config.model}
    new_data = Cortex.Agents.HookRunner.run_filter(hooks, :on_context, agent_state, data)

    case new_data do
      %{messages: msgs} when is_list(msgs) -> %{context | messages: msgs}
      _ -> context
    end
  end
end

defmodule Cortex.Session.Coordinator do
  @moduledoc """
  Agent 会话生命周期协调器。

  统一管理 Agent 的启动、停止、切换、状态保存与恢复。
  """

  alias Cortex.Agents.LLMAgent
  alias Cortex.Conversations
  alias Cortex.Session.Factory
  alias Cortex.SignalHub
  alias Cortex.SignalCatalog

  require Logger

  @doc """
  确保会话 Agent 正在运行。幂等操作。
  """
  def ensure_session(conversation_id, opts \\ []) do
    session_id = session_id(conversation_id)

    case LLMAgent.whereis(session_id) do
      nil ->
        start_session(conversation_id, session_id, opts)

      pid ->
        {:ok, %{session_id: session_id, pid: pid, conversation_id: conversation_id}}
    end
  end

  @doc """
  停止会话 Agent。先保存状态再停止。
  """
  def stop_session(conversation_id) do
    session_id = session_id(conversation_id)

    case LLMAgent.whereis(session_id) do
      nil ->
        {:ok, :not_running}

      pid ->
        _ = save_state(conversation_id, session_id)
        :ok = DynamicSupervisor.terminate_child(Cortex.SessionSupervisor, pid)

        SignalHub.emit(
          SignalCatalog.session_shutdown(),
          %{
            provider: "session",
            event: "session",
            action: "shutdown",
            actor: "coordinator",
            origin: %{
              channel: "system",
              client: "coordinator",
              platform: "server",
              session_id: session_id
            },
            session_id: session_id,
            conversation_id: conversation_id
          }
        )

        Logger.info("[Coordinator] Stopped: #{session_id}")
        {:ok, :stopped}
    end
  end

  @doc """
  切换会话。保存旧 Agent 状态并延迟停止旧会话。
  """
  def switch_session(old_conversation_id, new_conversation_id, opts) do
    if old_conversation_id && running?(old_conversation_id) do
      _ = save_state(old_conversation_id, session_id(old_conversation_id))
      schedule_stop(old_conversation_id, :timer.minutes(2))
    end

    ensure_session(new_conversation_id, opts)
  end

  @doc """
  检查 Agent 是否正在运行。
  """
  def running?(conversation_id) do
    LLMAgent.whereis(session_id(conversation_id)) != nil
  end

  @doc """
  conversation_id -> session_id 映射。
  """
  def session_id(conversation_id) do
    "session_#{conversation_id}"
  end

  @doc """
  保存 Agent 当前状态到数据库。
  """
  def save_state(conversation_id, session_id \\ nil) do
    sid = session_id || session_id(conversation_id)

    case LLMAgent.whereis(sid) do
      nil ->
        {:error, :not_running}

      pid ->
        llm_context = LLMAgent.get_llm_context(pid)

        Conversations.update_conversation(
          Conversations.get_conversation!(conversation_id),
          %{llm_context: llm_context}
        )
    end
  end

  defp start_session(conversation_id, session_id, opts) do
    agent_opts =
      Factory.build_opts(
        session_id: session_id,
        model: Keyword.get(opts, :model),
        workspace_id: Keyword.get(opts, :workspace_id)
      )

    case DynamicSupervisor.start_child(Cortex.SessionSupervisor, {LLMAgent, agent_opts}) do
      {:ok, pid} ->
        Logger.info("[Coordinator] Started: #{session_id}")

        if Keyword.get(opts, :restore_history, true) do
          restore_history(conversation_id, pid)
        end

        {:ok, %{session_id: session_id, pid: pid, conversation_id: conversation_id}}

      {:error, {:already_started, pid}} ->
        {:ok, %{session_id: session_id, pid: pid, conversation_id: conversation_id}}

      {:error, reason} ->
        Logger.error("[Coordinator] Failed to start: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp restore_history(conversation_id, pid) do
    conversation = Conversations.get_conversation!(conversation_id)
    ctx = conversation.llm_context

    if is_list(ctx) and ctx != [] do
      :ok = LLMAgent.reset_history(pid, ctx)
      Logger.info("[Coordinator] Restored #{length(ctx)} messages for #{conversation_id}")
    end
  end

  defp schedule_stop(conversation_id, delay) do
    Task.start(fn ->
      Process.sleep(delay)

      if running?(conversation_id) do
        _ = stop_session(conversation_id)
      end
    end)
  end
end

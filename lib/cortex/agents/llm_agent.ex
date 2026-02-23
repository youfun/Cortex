defmodule Cortex.Agents.LLMAgent do
  @moduledoc """
  Refined LLMAgent following the JidoCode pattern.
  - GenServer managed session.
  - Registry-based tool lookup.
  - Standardized signal-based events.
  - Recursive tool-calling loop.

  ## 历史记录系统

  该模块使用 Tape 作为唯一的历史记录系统：

  1. **llm_context** - LLM 对话上下文
     - 用途：发送给 LLM 进行推理
     - 内容：用户消息、LLM 响应、工具调用、工具返回结果
     - 格式：严格的消息格式（ReqLLM.Context）
     - 恢复：通过 TapeContext.to_llm_messages/2 从 Tape 恢复

  2. **Tape** - 完整历史记录（外部存储）
     - 用途：审计、调试、UI 展示、历史恢复
     - 内容：所有信号和事件（对话 + 工具调用 + 系统事件）
     - 格式：Entry 结构（kind, payload, timestamp, trace_id）
     - 查询：通过 Tape.Store.list_entries/1 查询

  ### 设计原则

  - 所有历史记录写入 Tape（通过 EntryBuilder）
  - llm_context 仅用于当前会话的 LLM 推理
  - 历史恢复时从 Tape 投影到 llm_context
  """

  use GenServer
  require Logger

  alias Cortex.Agents.PermissionFlow
  alias Cortex.Agents.Prompts
  alias Cortex.Agents.AgentLoop
  alias Cortex.Agents.Steering
  alias Cortex.Agents.HookRunner
  alias Cortex.Agents.LLMAgent.HistoryHelpers
  alias Cortex.Agents.LLMAgent.Broadcaster
  alias Cortex.Agents.LLMAgent.ToolExecution
  alias Cortex.Agents.LLMAgent.LoopHandler
  alias Cortex.SignalCatalog
  alias Cortex.SignalHub
  alias Cortex.Workspaces
  alias Jido.Signal.Trace
  alias Jido.Signal.TraceContext

  @default_timeout 60_000

  defstruct [
    :session_id,
    :config,
    # LLM 对话上下文（发给模型）
    :llm_context,
    :pending_tool_calls,
    :status,
    :turn_count,
    :loop_ref,
    :loop,
    :steering_queue,
    :hooks,
    :run_started_at
  ]

  # Client API

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def via(session_id) do
    {:via, Registry, {Cortex.SessionRegistry, session_id}}
  end

  @doc """
  通过 session_id 查找 Agent 进程。返回 pid 或 nil。
  """
  def whereis(session_id) do
    case Registry.lookup(Cortex.SessionRegistry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def chat(pid, message) do
    GenServer.call(pid, {:chat, message}, @default_timeout + 5000)
  end

  def set_model(pid, model_name) do
    GenServer.cast(pid, {:set_model, model_name})
  end

  def add_context(pid, msg) do
    GenServer.call(pid, {:add_context, msg})
  end

  def resolve_permission(pid, request_id, decision) do
    GenServer.cast(pid, {:resolve_permission, request_id, decision})
  end

  def reset_history(pid, llm_context) when is_list(llm_context) do
    GenServer.call(pid, {:reset_history, llm_context})
  end

  def reset_history(pid, _) do
    GenServer.call(pid, {:reset_history, []})
  end

  @doc """
  获取完整历史记录（从 Tape 查询）
  """
  def get_full_history(pid) do
    GenServer.call(pid, :get_full_history)
  end

  @doc """
  获取 LLM 对话上下文（用于理解当前对话状态）
  """
  def get_llm_context(pid) do
    GenServer.call(pid, :get_llm_context)
  end

  def cancel(pid) do
    GenServer.cast(pid, :cancel)
  end

  # Server Callbacks

  @impl true

  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    # 订阅信号总线
    SignalHub.subscribe(SignalCatalog.agent_chat_request())
    SignalHub.subscribe("agent.conversation.switch")
    SignalHub.subscribe("agent.model.change")
    SignalHub.subscribe("agent.context.add")
    SignalHub.subscribe(SignalCatalog.permission_resolved())
    SignalHub.subscribe("agent.cancel")
    SignalHub.subscribe("agent.steering.inject")

    # [NEW] 订阅记忆系统信号
    SignalHub.subscribe("memory.proposal.created")
    SignalHub.subscribe("memory.preconscious.surfaced")

    # 加载系统提示词（包含工具说明和当前可用技能）
    system_prompt =
      Prompts.build_system_prompt(
        workspace_root: Workspaces.workspace_root(),
        workspace_id: Keyword.get(opts, :workspace_id)
      )

    # [S7] 使用 TapeContext 从 Tape 恢复历史
    alias Cortex.History.TapeContext
    restored_messages = TapeContext.to_llm_messages(session_id, limit: 100)

    Logger.info(
      "[LLMAgent] Initialized with session: #{session_id}. Restored #{length(restored_messages)} messages from Tape."
    )

    initial_messages = [ReqLLM.Context.system(system_prompt) | restored_messages]
    initial_context = ReqLLM.Context.new(initial_messages)

    Logger.debug(
      "[LLMAgent] Initial context valid: #{inspect(ReqLLM.Context.validate(initial_context))}"
    )

    SignalHub.emit(
      SignalCatalog.session_start(),
      %{
        provider: "agent",
        event: "session",
        action: "start",
        actor: "llm_agent",
        origin: %{
          channel: "agent",
          client: "llm_agent",
          platform: "server",
          session_id: session_id
        },
        session_id: session_id,
        workspace: Workspaces.workspace_root(),
        model: Keyword.get(opts, :model, "gemini-3-flash"),
        restored_messages: length(restored_messages)
      },
      source: "/agent/llm"
    )

    {:ok,
     %__MODULE__{
       session_id: session_id,
       config: %{model: Keyword.get(opts, :model, "gemini-3-flash")},
       llm_context: initial_context,
       pending_tool_calls: %{},
       status: :idle,
       turn_count: 0,
       loop_ref: nil,
       loop: nil,
       steering_queue: Steering.new(),
       hooks: [
         Cortex.Hooks.MemoryHook,
         Cortex.Hooks.SkillInvokeHook,
         Cortex.Hooks.SandboxHook,
         Cortex.Hooks.PermissionHook
       ],
       run_started_at: nil
     }}
  end

  @impl true
  def terminate(reason, state) do
    SignalHub.emit(
      SignalCatalog.session_shutdown(),
      %{
        provider: "agent",
        event: "session",
        action: "shutdown",
        actor: "llm_agent",
        origin: %{
          channel: "agent",
          client: "llm_agent",
          platform: "server",
          session_id: state.session_id
        },
        session_id: state.session_id,
        reason: inspect(reason),
        turn_count: state.turn_count
      },
      source: "/agent/llm"
    )

    :ok
  end

  @impl true

  def handle_call({:chat, message}, _from, state) do
    Logger.debug(
      "[LLMAgent] ===== CHAT CALLED ===== Session: #{state.session_id} Status: #{state.status}"
    )

    Logger.debug("[LLMAgent] Message content: #{inspect(message)}")

    case process_chat_input(state, message) do
      {:ok, new_message, new_state} ->
        if new_state.status == :idle do
          # 正常开始对话
          user_msg = ReqLLM.Context.user(new_message)
          new_llm_context = ReqLLM.Context.append(new_state.llm_context, user_msg)

          new_state = refresh_system_prompt(new_state)

          new_state =
            LoopHandler.start(
              %{new_state | turn_count: 0, run_started_at: now_ms()},
              new_llm_context,
              new_state.config
            )

          {:reply, :ok,
           %{
             new_state
             | llm_context: new_llm_context,
               status: :thinking
           }}
        else
          # Agent 正在忙：优先取消正在运行的 loop，并立即开始新一轮对话
          if new_state.loop do
            Logger.info("[LLMAgent] Agent busy, cancelling in-flight loop for new input")
            AgentLoop.cancel(new_state.loop)

            user_msg = ReqLLM.Context.user(new_message)
            new_llm_context = ReqLLM.Context.append(new_state.llm_context, user_msg)

            new_state = refresh_system_prompt(%{new_state | loop_ref: nil, loop: nil})

            new_state =
              LoopHandler.start(
                %{new_state | run_started_at: now_ms()},
                new_llm_context,
                new_state.config
              )

            {:reply, :ok,
             %{
               new_state
               | llm_context: new_llm_context,
                 status: :thinking
             }}
          else
            # 没有可取消的 loop，退回 steering 队列
            Logger.info("[LLMAgent] Agent busy, pushing message to steering queue")
            new_queue = Steering.push(new_state.steering_queue, new_message)
            {:reply, :ok, %{new_state | steering_queue: new_queue}}
          end
        end

      {:handled, _response, new_state} ->
        # Hook 完全接管了输入，直接返回响应，不启动 Agent 循环
        Logger.info("[LLMAgent] Input handled by hook, skipping agent loop")
        {:reply, {:ok, :handled_by_hook}, new_state}

      {:halt, reason, new_state} ->
        Logger.warning("[LLMAgent] Input hook halted: #{inspect(reason)}")
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true

  def handle_call({:add_context, msg}, _from, state) do
    # add_context 用于添加系统通知等非对话内容

    new_llm_context =
      case msg do
        %{role: "system", content: content} ->
          ReqLLM.Context.append(state.llm_context, ReqLLM.Context.system(content))

        %{content: content} ->
          ReqLLM.Context.append(state.llm_context, ReqLLM.Context.system(content))

        content when is_binary(content) ->
          ReqLLM.Context.append(state.llm_context, ReqLLM.Context.system(content))

        _ ->
          state.llm_context
      end

    {:reply, :ok, %{state | llm_context: new_llm_context}}
  end

  @impl true
  def handle_call({:reset_history, history}, _from, state) do
    clean_messages = HistoryHelpers.sanitize_messages(history, include_system?: true)
    final_messages = HistoryHelpers.ensure_system_prompt(clean_messages)
    new_llm_context = ReqLLM.Context.new(final_messages)

    new_state = %{
      state
      | llm_context: new_llm_context,
        pending_tool_calls: %{},
        status: :idle,
        turn_count: 0,
        loop_ref: nil
    }

    Logger.info("[LLMAgent] Reset llm_context with #{length(final_messages)} sanitized messages")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_full_history, _from, state) do
    # 从 Tape 查询完整历史
    alias Cortex.History.Tape.Store
    entries = Store.list_entries(state.session_id)
    {:reply, entries, state}
  end

  @impl true
  def handle_call(:get_llm_context, _from, state) do
    {:reply, state.llm_context.messages, state}
  end

  @impl true

  def handle_cast({:set_model, model_name}, state) do
    Logger.debug("[LLMAgent] Setting model to: #{model_name}")

    {:noreply, %{state | config: Map.put(state.config, :model, model_name)}}
  end

  @impl true
  def handle_cast({:resolve_permission, request_id, decision}, state) do
    case PermissionFlow.resolve(state.pending_tool_calls, request_id) do
      {:ok, call_id, tool_call_data} ->
        if decision in [:allow, :allow_always, "allow", "allow_always"] do
          # Resume tool execution
          call_data_with_perm = Map.put(tool_call_data, :_permission_granted, true)
          new_state = ToolExecution.execute_with_hooks(call_data_with_perm, state)

          {:noreply, %{new_state | status: :executing_tools}}
        else
          # Notify failure and continue history
          send(
            self(),
            {:tool_result, call_id, "Error: User denied permission.",
             %{tool_name: tool_call_data.name, status: "error", elapsed_ms: 0}}
          )

          {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:cancel, state) do
    # Cancel any ongoing thinking/tool execution
    Logger.info("[LLMAgent] Cancelling current operation for session #{state.session_id}")

    state = LoopHandler.cancel_inflight(state)

    Broadcaster.emit(state.session_id, {:turn_complete, :cancelled}, [])

    {:noreply,
     %{
       state
       | status: :idle,
         pending_tool_calls: %{},
         turn_count: 0,
         loop_ref: nil,
         loop: nil,
         run_started_at: nil
     }}
  end

  # ============================================================================
  # 信号处理器 (Signal-Driven Architecture)
  # ============================================================================

  @impl true
  def handle_info({:signal, %{type: "agent.chat.request", data: data} = signal}, state) do
    # 只处理属于当前 session 的聊天请求
    if payload_get(data, :session_id) == state.session_id do
      # [NEW] Establish trace context
      setup_trace_context(signal)

      Logger.debug(
        "[LLMAgent] Received chat request signal for session: #{state.session_id} Status: #{state.status}"
      )

      message = payload_get(data, :content)

      case process_chat_input(state, message) do
        {:ok, new_message, new_state} ->
          model_override = payload_get(data, :model)

          config =
            if model_override,
              do: Map.put(new_state.config, :model, model_override),
              else: new_state.config

          if new_state.status == :idle do
            user_msg = ReqLLM.Context.user(new_message)

            new_state = refresh_system_prompt(new_state)
            new_llm_context = ReqLLM.Context.append(new_state.llm_context, user_msg)

            new_state =
              LoopHandler.start(
                %{new_state | turn_count: 0, run_started_at: now_ms()},
                new_llm_context,
                config
              )

            {:noreply,
             %{
               new_state
               | config: config,
                 llm_context: new_llm_context,
                 status: :thinking
             }}
          else
            Logger.info("[LLMAgent] Agent busy, pushing signal message to steering queue")
            new_queue = Steering.push(new_state.steering_queue, new_message)
            {:noreply, %{new_state | steering_queue: new_queue}}
          end

        {:halt, reason, new_state} ->
          Logger.warning("[LLMAgent] Signal chat request halted: #{inspect(reason)}")
          {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:signal, %{type: "agent.steering.inject", data: data}}, state) do
    if payload_get(data, :session_id) == state.session_id do
      message = payload_get(data, :content)
      Logger.info("[LLMAgent] Received steering inject signal: #{inspect(message)}")
      new_queue = Steering.push(state.steering_queue, message)
      {:noreply, %{state | steering_queue: new_queue}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:signal, %{type: "agent.conversation.switch", data: data}}, state) do
    if payload_get(data, :session_id) == state.session_id do
      Logger.debug("[LLMAgent] Received conversation switch signal")

      history = payload_get(data, :history) || []

      conversation_messages = HistoryHelpers.sanitize_messages(history, include_system?: false)
      system_prompt = Prompts.build_system_prompt(workspace_root: Workspaces.workspace_root())
      final_messages = [ReqLLM.Context.system(system_prompt) | conversation_messages]

      new_llm_context = ReqLLM.Context.new(final_messages)

      Logger.info(
        "[LLMAgent] Switched conversation, reset context with #{length(final_messages)} messages"
      )

      {:noreply,
       %{
         state
         | llm_context: new_llm_context,
           pending_tool_calls: %{},
           status: :idle,
           turn_count: 0,
           loop_ref: nil
       }}
    else
      {:noreply, state}
    end
  end

  def handle_info({:signal, %{type: "agent.model.change", data: data}}, state) do
    if payload_get(data, :session_id) == state.session_id do
      model_name = payload_get(data, :model_name)
      Logger.debug("[LLMAgent] Received model change signal: #{model_name}")

      {:noreply, %{state | config: Map.put(state.config, :model, model_name)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:signal, %{type: "agent.context.add", data: data}}, state) do
    if payload_get(data, :session_id) == state.session_id do
      Logger.debug("[LLMAgent] Received context add signal")

      msg = payload_get(data, :message)

      new_llm_context =
        case msg do
          %{role: "system", content: content} ->
            ReqLLM.Context.append(state.llm_context, ReqLLM.Context.system(content))

          %{content: content} ->
            ReqLLM.Context.append(state.llm_context, ReqLLM.Context.system(content))

          content when is_binary(content) ->
            ReqLLM.Context.append(state.llm_context, ReqLLM.Context.system(content))

          _ ->
            state.llm_context
        end

      {:noreply, %{state | llm_context: new_llm_context}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:signal, %{type: "permission.resolved", data: data}}, state) do
    if payload_get(data, :session_id) == state.session_id do
      Logger.debug("[LLMAgent] Received permission resolution signal")

      request_id = payload_get(data, :request_id)
      decision = payload_get(data, :decision)

      # 复用现有的 resolve_permission 逻辑
      case PermissionFlow.resolve(state.pending_tool_calls, request_id) do
        {:ok, _call_id, tool_call_data} ->
          if decision in [:allow, :allow_always, "allow", "allow_always"] do
            call_data_with_perm = Map.put(tool_call_data, :_permission_granted, true)
            new_state = ToolExecution.execute_with_hooks(call_data_with_perm, state)

            {:noreply, %{new_state | status: :executing_tools}}
          else
            # Notify failure
            Broadcaster.emit(
              state.session_id,
              {:tool_result, tool_call_data.id, "Permission denied by user"},
              tool_name: tool_call_data.name
            )

            new_pending = Map.delete(state.pending_tool_calls, request_id)

            if map_size(new_pending) == 0 do
              Broadcaster.emit(state.session_id, {:turn_complete, :permission_denied}, [])
              {:noreply, %{state | pending_tool_calls: new_pending, status: :idle}}
            else
              {:noreply, %{state | pending_tool_calls: new_pending}}
            end
          end

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:signal, %{type: "agent.cancel", data: data}}, state) do
    if payload_get(data, :session_id) == state.session_id do
      Logger.info("[LLMAgent] Received cancel signal for session #{state.session_id}")
      state = LoopHandler.cancel_inflight(state)
      Broadcaster.emit(state.session_id, {:turn_complete, :cancelled}, [])

      {:noreply,
       %{
         state
         | status: :idle,
           pending_tool_calls: %{},
           turn_count: 0,
           loop_ref: nil,
           loop: nil,
           run_started_at: nil
       }}
    else
      {:noreply, state}
    end
  end

  # [NEW] 记忆系统信号处理
  def handle_info({:signal, %{type: "memory.proposal.created", data: data}}, state) do
    confidence = payload_get(data, :confidence) || 0

    proposal_id = payload_get(data, :proposal_id)
    source_signal_type = payload_get(data, :source_signal_type)
    source_actor = payload_get(data, :source_actor)

    safe_source? =
      source_actor in ["user", :user] and
        (source_signal_type == "agent.chat.request" or
           (is_binary(source_signal_type) and
              String.starts_with?(source_signal_type, "user.input.")))

    # Auto-accept: safe source with confidence >= 0.65 (lowered from 0.8)
    # Also auto-accept tool-originated proposals (facts from file/shell usage)
    tool_source? = source_actor in ["subconscious_engine", :subconscious_engine]

    auto_accept? =
      (safe_source? and confidence >= 0.65) or
        (tool_source? and confidence >= 0.70)

    if auto_accept? do
      Logger.debug("[LLMAgent] Auto-accepting proposal: #{proposal_id} (confidence: #{confidence})")
      Cortex.Memory.Store.accept_proposal(proposal_id)
      {:noreply, state}
    else
      # Low confidence or unsafe source: silently store as pending, don't pollute LLM context
      Logger.debug("[LLMAgent] Proposal #{proposal_id} kept pending (confidence: #{confidence})")
      {:noreply, state}
    end
  end

  def handle_info({:signal, %{type: "memory.preconscious.surfaced", data: data}}, state) do
    # 预意识浮现的记忆：添加到上下文
    content = "💡 相关记忆: #{payload_get(data, :content)} (相关度: #{payload_get(data, :activation)})"

    new_llm_context =
      ReqLLM.Context.append(state.llm_context, ReqLLM.Context.system(content))

    {:noreply, %{state | llm_context: new_llm_context}}
  end

  # 忽略不相关的信号
  def handle_info({:signal, _}, state), do: {:noreply, state}

  @impl true
  def handle_info({:tool_result, call_id, raw_output, tool_meta}, state) do
    tool_name = tool_meta.tool_name

    # 写入 Tape
    alias Cortex.History.Tape.{Store, EntryBuilder}

    entry =
      EntryBuilder.tool_result(
        tool_name,
        call_id,
        tool_meta.status,
        raw_output,
        elapsed_ms: tool_meta.elapsed_ms,
        session_id: state.session_id
      )

    Store.append(state.session_id, entry)

    result_data = %{
      call_id: call_id,
      tool_name: tool_name,
      output: raw_output
    }

    case HookRunner.run(state.hooks, :on_tool_result, state, result_data) do
      {:ok, %{output: output}, new_state} ->
        # Hook 修改了输出
        process_tool_result(call_id, tool_name, output, new_state)

      {:pass, _reason, new_state} ->
        # Hook 不修改输出
        process_tool_result(call_id, tool_name, raw_output, new_state)

      {:halt, reason, new_state} ->
        Logger.warning("[LLMAgent] Tool result hook halted: #{inspect(reason)}")
        {:noreply, new_state}
    end
  end

  def handle_info({:loop_result, loop_ref, {:ok, response}}, state) do
    if state.loop_ref != loop_ref do
      {:noreply, state}
    else
      LoopHandler.on_ok(response, state)
    end
  end

  def handle_info({:loop_result, {:ok, response}}, state) do
    LoopHandler.on_ok(response, state)
  end

  def handle_info({:loop_result, loop_ref, {:error, reason}}, state) do
    if state.loop_ref != loop_ref do
      {:noreply, state}
    else
      LoopHandler.on_error(reason, state)
    end
  end

  def handle_info({:permission_required, req_id, call_data}, state) do
    new_pending =
      state.pending_tool_calls
      |> PermissionFlow.track_pending(call_data.id, Map.put(call_data, :req_id, req_id))

    signal_data = %{
      session_id: state.session_id,
      request_id: req_id,
      tool: call_data.name,
      path: ToolExecution.permission_path(call_data),
      action: ToolExecution.permission_action(call_data),
      params: call_data.args
    }

    SignalHub.emit(
      SignalCatalog.permission_request(),
      Map.merge(signal_data, %{
        provider: "agent",
        event: "permission",
        action: "request",
        actor: "llm_agent",
        origin: agent_origin(state.session_id)
      }),
      source: "/agent/llm"
    )

    {:noreply, %{state | pending_tool_calls: new_pending, status: :waiting_permission}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  # Helpers

  defp process_tool_result(call_id, tool_name, output, state) do
    # 修复双重 inspect：只在非字符串时才 inspect
    output_str =
      if is_binary(output),
        do: output,
        else: inspect(output, limit: :infinity, printable_limit: :infinity)

    tool_msg = ReqLLM.Context.tool_result(call_id, tool_name, output_str)
    new_llm_context = ReqLLM.Context.append(state.llm_context, tool_msg)

    Broadcaster.emit(state.session_id, {:tool_result, call_id, output}, tool_name: tool_name)

    new_pending = Map.delete(state.pending_tool_calls, call_id)

    updated_state = %{
      state
      | llm_context: new_llm_context,
        pending_tool_calls: new_pending
    }

    if map_size(new_pending) == 0 do
      case Steering.check(state.steering_queue) do
        {steering_msg, remaining_queue} ->
          Logger.info("[LLMAgent] Steering detected after tools! Injecting user message.")

          user_msg = ReqLLM.Context.user(steering_msg.content)
          steered_context = ReqLLM.Context.append(new_llm_context, user_msg)

          steering_state = %{
            updated_state
            | steering_queue: remaining_queue,
              llm_context: steered_context
          }

          new_state = LoopHandler.start(steering_state, steered_context, steering_state.config)

          {:noreply,
           %{
             new_state
             | llm_context: steered_context,
               pending_tool_calls: new_pending,
               status: :thinking,
               turn_count: new_state.turn_count
           }}

        nil ->
          new_state = LoopHandler.start(updated_state, new_llm_context, updated_state.config)

          {:noreply,
           %{
             new_state
             | llm_context: new_llm_context,
               pending_tool_calls: new_pending,
               status: :thinking,
               turn_count: new_state.turn_count
           }}
      end
    else
      {:noreply, updated_state}
    end
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

  defp process_chat_input(state, message) do
    case HookRunner.run(state.hooks, :on_input, state, message) do
      {:ok, new_message, new_state} ->
        if new_message != message do
          SignalHub.emit(
            SignalCatalog.context_input_transform(),
            %{
              provider: "agent",
              event: "context",
              action: "input_transform",
              actor: "llm_agent",
              origin: agent_origin(new_state.session_id),
              session_id: new_state.session_id,
              original_text: message,
              transformed_text: new_message
            },
            source: "/agent/llm"
          )
        end

        {:ok, new_message, new_state}

      {:transform, new_message, new_state} ->
        SignalHub.emit(
          SignalCatalog.context_input_transform(),
          %{
            provider: "agent",
            event: "context",
            action: "input_transform",
            actor: "llm_agent",
            origin: agent_origin(new_state.session_id),
            session_id: new_state.session_id,
            original_text: message,
            transformed_text: new_message
          },
          source: "/agent/llm"
        )

        {:ok, new_message, new_state}

      {:continue, new_message, new_state} ->
        {:ok, new_message, new_state}

      {:handled, response, new_state} ->
        # Hook 完全接管了输入，直接返回响应
        SignalHub.emit(
          SignalCatalog.agent_response(),
          %{
            provider: "agent",
            event: "response",
            action: "complete",
            actor: "hook",
            origin: agent_origin(new_state.session_id),
            session_id: new_state.session_id,
            content: response,
            handled_by: "hook"
          },
          source: "/agent/llm"
        )

        {:handled, response, new_state}

      {:halt, reason, new_state} ->
        {:halt, reason, new_state}
    end
  end

  defp refresh_system_prompt(state) do
    Logger.debug("[LLMAgent] Refreshing dynamic system prompt...")

    new_system_prompt =
      Prompts.build_system_prompt(
        workspace_root: Workspaces.workspace_root(),
        workspace_id: state.session_id
      )

    # 替换第一条系统消息，如果不存在则在最前面插入
    new_messages =
      case state.llm_context.messages do
        [%ReqLLM.Message{role: :system} | rest] ->
          [ReqLLM.Context.system(new_system_prompt) | rest]

        messages ->
          [ReqLLM.Context.system(new_system_prompt) | messages]
      end

    %{state | llm_context: %{state.llm_context | messages: new_messages}}
  end

  defp payload_get(data, key) when is_map(data) do
    payload =
      case data do
        %{payload: p} when is_map(p) -> p
        %{"payload" => p} when is_map(p) -> p
        _ -> %{}
      end

    Map.get(payload, key) ||
      Map.get(payload, to_string(key)) ||
      Map.get(data, key) ||
      Map.get(data, to_string(key))
  end

  defp setup_trace_context(%Jido.Signal{} = signal) do
    TraceContext.ensure_from_signal(signal)
    :ok
  end

  defp setup_trace_context(signal) do
    # If signal is not a struct but a map (e.g. from tests or partial data)
    ctx = Trace.new_root(causation_id: Map.get(signal, :id))
    TraceContext.set(ctx)
    :ok
  end
end

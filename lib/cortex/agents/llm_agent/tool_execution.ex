defmodule Cortex.Agents.LLMAgent.ToolExecution do
  @moduledoc """
  工具执行模块。

  负责：
  - 批量处理工具调用
  - 异步执行工具
  - Hook 集成
  - 权限检查
  - 错误处理和信号发射
  """

  require Logger

  alias Cortex.Agents.HookRunner
  alias Cortex.SignalCatalog
  alias Cortex.SignalHub
  alias Cortex.Tools.ToolRunner
  alias Cortex.Workspaces
  alias Jido.Signal.TraceContext

  @doc """
  处理多个工具调用。

  ## 参数
  - `state` - Agent 状态
  - `tool_calls` - 工具调用列表
  - `llm_context` - LLM 上下文

  ## 返回
  更新后的 state，包含 pending_tool_calls
  """
  def process_calls(state, tool_calls, llm_context) do
    Logger.debug("[ToolExecution] Processing #{length(tool_calls)} tool calls")

    {final_state, new_pending} =
      Enum.reduce(tool_calls, {state, %{}}, fn tc, {current_state, acc} ->
        tool_name = ReqLLM.ToolCall.name(tc)
        tool_args = ReqLLM.ToolCall.args_map(tc)

        Logger.debug(
          "[ToolExecution] Tool call parsed: id=#{tc.id}, name='#{tool_name}', args=#{inspect(tool_args)}"
        )

        cond do
          is_nil(tool_name) or tool_name == "" ->
            Logger.warning("[ToolExecution] Skipping tool call with empty name, id=#{tc.id}")
            {current_state, acc}

          true ->
            call_data = %{
              id: tc.id,
              name: tool_name,
              args: tool_args
            }

            SignalHub.emit(
              SignalCatalog.tool_call_request(),
              %{
                provider: "agent",
                event: "tool",
                action: "call_request",
                actor: "llm_agent",
                origin: agent_origin(current_state.session_id),
                session_id: current_state.session_id,
                turn_id: "turn_#{current_state.turn_count}",
                tool: tool_name,
                params: tool_args,
                call_id: tc.id
              },
              source: "/agent/llm"
            )

            next_state = execute_with_hooks(call_data, current_state)
            {next_state, Map.put(acc, tc.id, call_data)}
        end
      end)

    if map_size(new_pending) == 0 do
      Logger.warning("[ToolExecution] No valid tool calls to execute, completing turn")
      # 使用 Broadcaster 发射信号
      Cortex.Agents.LLMAgent.Broadcaster.emit(
        final_state.session_id,
        {:turn_complete, :success},
        []
      )

      %{final_state | llm_context: llm_context, status: :idle}
    else
      %{
        final_state
        | llm_context: llm_context,
          pending_tool_calls: new_pending,
          status: :executing_tools
      }
    end
  end

  @doc """
  通过 Hook 执行工具调用。

  ## 参数
  - `call_data` - 工具调用数据 %{id, name, args}
  - `state` - Agent 状态

  ## 返回
  更新后的 state
  """
  def execute_with_hooks(call_data, state) do
    hooks = state.hooks || []

    case HookRunner.run(hooks, :before_tool_call, state, call_data) do
      {:ok, final_call_data, final_state} ->
        execute_async(final_state.session_id, final_call_data)
        final_state

      {:halt, {:permission_required, req_id, data}, final_state} ->
        SignalHub.emit(
          SignalCatalog.tool_call_blocked(),
          %{
            provider: "agent",
            event: "tool",
            action: "call_blocked",
            actor: "llm_agent",
            origin: agent_origin(final_state.session_id),
            session_id: final_state.session_id,
            tool: call_data.name,
            reason: "permission_required",
            request_id: req_id
          },
          source: "/agent/llm"
        )

        send(self(), {:permission_required, req_id, data})
        final_state

      {:halt, {:error, reason}, final_state} ->
        SignalHub.emit(
          SignalCatalog.tool_call_blocked(),
          %{
            provider: "agent",
            event: "tool",
            action: "call_blocked",
            actor: "llm_agent",
            origin: agent_origin(final_state.session_id),
            session_id: final_state.session_id,
            tool: call_data.name,
            reason: inspect(reason)
          },
          source: "/agent/llm"
        )

        send(
          self(),
          {:tool_result, call_data.id, "Error: #{inspect(reason)}",
           %{tool_name: call_data.name, status: "error", elapsed_ms: 0}}
        )

        final_state

      {:halt, reason, final_state} ->
        Logger.warning("[ToolExecution] Hook halted with reason: #{inspect(reason)}")

        SignalHub.emit(
          SignalCatalog.tool_call_blocked(),
          %{
            provider: "agent",
            event: "tool",
            action: "call_blocked",
            actor: "llm_agent",
            origin: agent_origin(final_state.session_id),
            session_id: final_state.session_id,
            tool: call_data.name,
            reason: inspect(reason)
          },
          source: "/agent/llm"
        )

        send(
          self(),
          {:tool_result, call_data.id, "Error: Hook halted execution: #{inspect(reason)}",
           %{tool_name: call_data.name, status: "error", elapsed_ms: 0}}
        )

        final_state
    end
  end

  @doc """
  异步执行工具。

  ## 参数
  - `session_id` - 会话 ID
  - `call_data` - 工具调用数据

  ## 返回
  :ok 或 {:error, reason}
  """
  def execute_async(session_id, call_data) do
    parent = via_pid(session_id)
    trace_ctx = TraceContext.current()

    Logger.debug(
      "[ToolExecution] Executing tool: '#{call_data.name}' with args: #{inspect(call_data.args)}"
    )

    case Task.Supervisor.start_child(Cortex.AgentTaskSupervisor, fn ->
           if trace_ctx, do: TraceContext.set(trace_ctx)
           Logger.debug("[ToolExecution] Tool task started for: '#{call_data.name}'")

           result =
             ToolRunner.execute(call_data.name, call_data.args, %{
               session_id: session_id,
               agent_id: session_id,
               project_root: Workspaces.workspace_root()
             })

           Logger.debug(
             "[ToolExecution] ToolRunner.execute result for '#{call_data.name}': #{inspect(result)}"
           )

           case result do
             {:ok, output, elapsed_ms} ->
               Logger.debug("[ToolExecution] Tool '#{call_data.name}' executed successfully")

               send(parent, {
                 :tool_result,
                 call_data.id,
                 output,
                 %{tool_name: call_data.name, status: "ok", elapsed_ms: elapsed_ms}
               })

             {:error, {:approval_required, reason}, _ms} ->
               Logger.debug(
                 "[ToolExecution] Tool '#{call_data.name}' requires approval: #{reason}"
               )

               req_id = "approval_#{call_data.id}_#{System.system_time(:millisecond)}"

               SignalHub.emit(
                 "permission.request",
                 %{
                   provider: "agent",
                   event: "permission",
                   action: "request",
                   actor: "tool_interceptor",
                   origin: %{channel: "agent", client: "llm_agent", platform: "server"},
                   session_id: session_id,
                   tool: call_data.name,
                   reason: reason,
                   request_id: req_id
                 },
                 source: "/agent/llm/tool"
               )

               send(parent, {:permission_required, req_id, call_data})

             {:error, {:permission_denied, req_id}, _ms} ->
               Logger.debug(
                 "[ToolExecution] Tool '#{call_data.name}' requires permission: #{req_id}"
               )

               send(parent, {:permission_required, req_id, call_data})

             {:error, :tool_not_found, _ms} ->
               Logger.error("[ToolExecution] Tool not found: '#{call_data.name}'")
               error_ctx = Cortex.Tools.ErrorContext.format(call_data.name, :tool_not_found)

               send(parent, {
                 :tool_result,
                 call_data.id,
                 error_ctx,
                 %{tool_name: call_data.name, status: "error", elapsed_ms: 0}
               })

             {:error, reason, elapsed_ms} ->
               Logger.error(
                 "[ToolExecution] Tool '#{call_data.name}' execution error: #{inspect(reason)}"
               )

               error_ctx =
                 Cortex.Tools.ErrorContext.format(call_data.name, reason,
                   elapsed_ms: elapsed_ms
                 )

               emit_tool_error_signal(session_id, call_data, reason, elapsed_ms)

               send(parent, {
                 :tool_result,
                 call_data.id,
                 error_ctx,
                 %{tool_name: call_data.name, status: "error", elapsed_ms: elapsed_ms}
               })
           end
         end) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.error("[ToolExecution] Failed to start tool task: #{inspect(reason)}")

        send(
          parent,
          {
            :tool_result,
            call_data.id,
            "Error: Failed to start tool execution: #{inspect(reason)}",
            %{tool_name: call_data.name, status: "error", elapsed_ms: 0}
          }
        )
    end
  end

  @doc """
  获取权限动作类型。
  """
  def permission_action(call_data) do
    case call_data.name do
      "edit_file" -> :write
      "write_file" -> :write
      "delete_file" -> :write
      "run_command" -> :execute
      _ -> :read
    end
  end

  @doc """
  获取权限路径。
  """
  def permission_path(call_data) do
    args = call_data.args || %{}

    case call_data.name do
      "run_command" ->
        command = args["command"] || args[:command] || "unknown"
        cmd_args = args["args"] || args[:args] || []
        "cmd:#{command} #{Enum.join(List.wrap(cmd_args), " ")}"

      _ ->
        args["path"] || args[:path] || "unknown"
    end
  end

  # Private helpers

  defp via_pid(session_id) do
    case Registry.lookup(Cortex.SessionRegistry, session_id) do
      [{pid, _}] -> pid
      _ -> self()
    end
  end

  defp emit_tool_error_signal(session_id, call_data, reason, elapsed_ms) do
    SignalHub.emit(
      "tool.error",
      %{
        provider: "tool",
        event: "tool",
        action: "error",
        actor: "tool_runner",
        origin: agent_origin(session_id),
        session_id: session_id,
        tool_name: call_data.name,
        call_id: call_data.id,
        reason: reason,
        elapsed_ms: elapsed_ms
      },
      source: "/agent/llm/tool"
    )
  end

  defp agent_origin(session_id) do
    %{
      channel: "agent",
      client: "llm_agent",
      platform: "server",
      session_id: session_id
    }
  end
end

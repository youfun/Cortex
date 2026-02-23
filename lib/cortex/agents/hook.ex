defmodule Cortex.Agents.Hook do
  @moduledoc """
  Defines the behaviour for Agent hooks.
  Hooks can intercept and modify the flow of the agent at various stages.

  ## Hook 阶段 (Lifecycle Stages)

  ### 输入阶段
  - `on_input/2` — 用户输入到达后，支持 transform / handled / continue

  ### Agent 循环阶段
  - `on_before_agent/2` — Agent 循环启动前，支持修改 system prompt
  - `on_context/2` — LLM 调用前，修改/过滤消息历史
  - `on_agent_end/2` — Agent 循环完成后通知

  ### 工具阶段
  - `before_tool_call/2` — 工具调用前拦截
  - `on_tool_result/2` — 工具结果返回后修改

  ### Session 阶段
  - `on_session_start/1` — Session 启动
  - `on_session_shutdown/1` — Session 关闭
  - `on_compaction_before/2` — Compaction 执行前

  """

  # === 输入阶段 ===

  @doc "用户输入拦截。支持三种返回值。"
  @callback on_input(agent_state :: map(), message :: any()) ::
              {:ok, new_message :: any(), new_agent_state :: map()}
              | {:continue, new_message :: any(), new_agent_state :: map()}
              | {:transform, new_message :: any(), new_agent_state :: map()}
              | {:handled, response :: any(), new_agent_state :: map()}
              | {:halt, reason :: any(), new_agent_state :: map()}

  # === Agent 循环阶段 ===

  @doc """
  Agent 循环启动前。可注入消息或修改 system prompt。
  返回 map 可包含:
    - :context — 修改后的 llm_context
    - :system_prompt — 修改后的 system prompt (仅当前 turn 有效)
    - :inject_messages — 注入的额外消息列表
  """
  @callback on_before_agent(agent_state :: map(), data :: map()) ::
              {:ok, modifications :: map(), new_agent_state :: map()}
              | {:halt, reason :: any(), new_agent_state :: map()}

  @doc """
  LLM 调用前最后时刻。可修改/过滤消息历史。
  data 包含:
    - :messages — 当前消息列表
    - :model — 当前模型名称
  返回修改后的消息列表。
  """
  @callback on_context(agent_state :: map(), data :: map()) ::
              {:ok, messages :: list(), new_agent_state :: map()}
              | {:pass, reason :: any(), new_agent_state :: map()}

  @doc "Agent 循环完成后通知 (不可拦截)。"
  @callback on_agent_end(agent_state :: map(), data :: map()) :: :ok

  # === 工具阶段 ===

  @callback before_tool_call(agent_state :: map(), call_data :: map()) ::
              {:ok, new_call_data :: map(), new_agent_state :: map()}
              | {:halt, reason :: any(), new_agent_state :: map()}

  @doc "工具结果返回后修改。返回的 result_data 必须是 map，且至少包含 :output。"
  @callback on_tool_result(agent_state :: map(), result_data :: map()) ::
              {:ok, new_result :: map(), new_agent_state :: map()}
              | {:pass, any(), new_agent_state :: map()}

  # === Session 阶段 ===

  @callback on_session_start(agent_state :: map()) :: :ok
  @callback on_session_shutdown(agent_state :: map()) :: :ok

  @doc """
  Compaction 执行前。可取消或自定义压缩策略。
  data 包含:
    - :messages — 当前消息列表
    - :token_count — 当前 token 数
    - :threshold — 触发阈值
  """
  @callback on_compaction_before(agent_state :: map(), data :: map()) ::
              {:ok, data :: map(), new_agent_state :: map()}
              | {:cancel, reason :: any(), new_agent_state :: map()}
              | {:custom, compressed_messages :: list(), new_agent_state :: map()}

  @optional_callbacks [
    on_input: 2,
    on_before_agent: 2,
    on_context: 2,
    on_agent_end: 2,
    before_tool_call: 2,
    on_tool_result: 2,
    on_session_start: 1,
    on_session_shutdown: 1,
    on_compaction_before: 2
  ]
end

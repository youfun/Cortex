# S4-S8 实施回顾与逻辑分析

> 分析时间：2026-02-18  
> 覆盖范围：S4（handle_loop_ok 增强）至 S8（Extension 动态注册）

---

## 一、实施完整性检查

### 已完成阶段

| 阶段 | 任务 | 状态 | 证据 |
|---|---|---|---|
| S4 | handle_loop_ok → Tape 写入 + on_agent_end | ✅ | `llm_agent.ex` L1165-1180, L1205 |
| S5 | start_loop 增强（system_prompt 修改） | ✅ | `llm_agent.ex` L1698-1715 |
| S6 | Compaction Hook 调用 | ✅ | `compaction.ex` L61-73, L339-344 |
| S7 | Tape 高级特性（TapeContext + from_last_anchor） | ✅ | `tape_context.ex`, `store.ex` L40-43 |
| S8 | Extension 动态注册 | ✅ | `registry.ex`, `loader.ex`, `manager.ex` |

---

## 二、逻辑问题分析

### 2.1 S4-S5：LLMAgent 状态管理

#### 问题 1：full_history 未完全移除

**位置**：`lib/cortex/agents/llm_agent.ex` L1175-1190

**现状**：
```elixir
# [S4] Tape 写入：assistant message
if text_content != \"\" do
  Store.append(state.session_id, 
    EntryBuilder.message(\"assistant\", text_content, session_id: state.session_id))
end

# ✅ 加入完整历史记录（Phase S7 将移除）
full_entry = %{
  type: \"assistant_response\",
  timestamp: DateTime.utc_now(),
  data: assistant_msg,
  metadata: %{...}
}
new_full_history = state.full_history ++ [full_entry]
```

**问题**：
- S7 计划中明确要求移除 `full_history`，但 S4-S6 实施时仍在维护
- 导致双重写入：Tape + full_history
- `defstruct` 中 `full_history` 字段已移除，但代码中仍在使用

**影响**：
- 编译时会报错：`state.full_history` 不存在
- 需要全局搜索并移除所有 `new_full_history` 相关代码

**修复建议**：
```bash
# 搜索所有 full_history 引用
grep -rn "full_history" lib/cortex/agents/llm_agent.ex

# 移除所有 full_entry 构造和 new_full_history 赋值
```

---

#### 问题 2：on_before_agent Hook 返回值处理不完整

**位置**：`lib/cortex/agents/llm_agent.ex` L1698-1715

**现状**：
```elixir
case HookRunner.run(state.hooks, :on_before_agent, state, %{context: history}) do
  {:ok, modifications, new_state} ->
    final_history = 
      case modifications do
        %{context: modified_context} -> modified_context
        %{system_prompt: custom_prompt} -> ...
        _ -> history  # 默认返回原 history
      end
    ...
  {:halt, reason, new_state} -> ...
end
```

**问题**：
- `modifications` 为空 map `%{}` 时，返回原 history（正确）
- 但如果 Hook 返回 `{:ok, %{unknown_key: value}, state}`，也会返回原 history
- 缺少对未知 key 的警告日志

**影响**：
- Hook 开发者可能误以为修改生效，但实际被忽略
- 调试困难

**修复建议**：
```elixir
case modifications do
  %{context: modified_context} -> modified_context
  %{system_prompt: custom_prompt} -> ...
  %{} -> history  # 空 map，正常
  other ->
    Logger.warning(\"[LLMAgent] Unknown modification keys: #{inspect(Map.keys(other))}\")
    history
end
```

---

### 2.2 S6：Compaction Hook 集成

#### 问题 3：Hook 返回值类型不一致

**位置**：`lib/cortex/agents/compaction.ex` L61-73

**现状**：
```elixir
case run_compaction_hooks(hooks, agent_state, hook_data) do
  {:ok, _data, _new_state} -> compact(context, model_name, keep_recent)
  {:cancel, reason, _new_state} -> {:ok, context}
  {:custom, custom_messages, _new_state} -> 
    {:ok, %ReqLLM.Context{context | messages: custom_messages}}
end
```

**问题**：
- `{:ok, ...}` 分支调用 `compact/3`，返回 `{:ok, context}`
- `{:cancel, ...}` 分支直接返回 `{:ok, context}`
- `{:custom, ...}` 分支直接返回 `{:ok, %ReqLLM.Context{...}}`
- 三个分支的返回值类型一致（都是 `{:ok, context}`），但语义不同

**影响**：
- 调用方无法区分是"正常压缩"还是"Hook 取消"还是"Hook 自定义"
- 缺少 telemetry 事件区分

**修复建议**：
```elixir
case run_compaction_hooks(hooks, agent_state, hook_data) do
  {:ok, _data, _new_state} -> 
    result = compact(context, model_name, keep_recent)
    emit_telemetry(:compaction_completed, %{strategy: :normal})
    result
    
  {:cancel, reason, _new_state} -> 
    emit_telemetry(:compaction_cancelled, %{reason: reason})
    {:ok, context}
    
  {:custom, custom_messages, _new_state} -> 
    emit_telemetry(:compaction_custom, %{message_count: length(custom_messages)})
    {:ok, %ReqLLM.Context{context | messages: custom_messages}}
end
```

---

### 2.3 S7：TapeContext 投影逻辑

#### 问题 4：entry_to_message 缺少错误处理

**位置**：`lib/cortex/history/tape_context.ex` L36-67

**现状**：
```elixir
def entry_to_message(%Entry{kind: :message, payload: payload}) do
  role = Map.get(payload, :role) || Map.get(payload, \"role\")
  content = Map.get(payload, :content) || Map.get(payload, \"content\")

  case role do
    \"system\" -> ReqLLM.Context.system(content)
    \"user\" -> ReqLLM.Context.user(content)
    \"assistant\" -> ReqLLM.Context.assistant(content)
    _ -> nil
  end
end
```

**问题**：
- 如果 `payload` 中缺少 `role` 或 `content`，会返回 `nil`
- 如果 `content` 为 `nil`，`ReqLLM.Context.user(nil)` 可能导致错误
- 缺少对损坏 Entry 的日志记录

**影响**：
- 恢复 LLM 上下文时可能丢失消息
- 调试困难，无法定位损坏的 Entry

**修复建议**：
```elixir
def entry_to_message(%Entry{kind: :message, payload: payload} = entry) do
  role = Map.get(payload, :role) || Map.get(payload, \"role\")
  content = Map.get(payload, :content) || Map.get(payload, \"content\")

  cond do
    is_nil(role) or is_nil(content) ->
      Logger.warning(\"[TapeContext] Invalid message entry: #{inspect(entry)}\")
      nil
      
    true ->
      case role do
        \"system\" -> ReqLLM.Context.system(content)
        \"user\" -> ReqLLM.Context.user(content)
        \"assistant\" -> ReqLLM.Context.assistant(content)
        _ -> 
          Logger.warning(\"[TapeContext] Unknown role: #{role}\")
          nil
      end
  end
end
```

---

### 2.4 S8：Extension 动态注册

#### 问题 5：Extension 加载失败后状态不一致

**位置**：`lib/cortex/extensions/manager.ex` L76-80

**现状**：
```elixir
{:reload, module} ->
  if Map.has_key?(state.loaded, module) do
    Loader.unload_extension(module)
    case Loader.load_extension(module) do
      :ok -> ...
      {:error, reason} = error ->
        # 重载失败，从已加载列表中移除
        new_loaded = Map.delete(state.loaded, module)
        {:reply, error, %{state | loaded: new_loaded}}
    end
  end
```

**问题**：
- `unload_extension` 已执行（hooks 和 tools 已移除）
- 但 `load_extension` 失败，Extension 处于"半卸载"状态
- 如果用户再次调用 `reload`，会因为 `not_loaded` 而失败

**影响**：
- Extension 状态不一致
- 需要手动 `load` 才能恢复

**修复建议**：
```elixir
{:reload, module} ->
  if Map.has_key?(state.loaded, module) do
    # 先尝试加载新版本，成功后再卸载旧版本
    case Loader.load_extension(module) do
      :ok ->
        Loader.unload_extension(module)  # 卸载旧版本
        new_loaded = Map.put(state.loaded, module, %{loaded_at: DateTime.utc_now()})
        {:reply, :ok, %{state | loaded: new_loaded}}
        
      {:error, reason} = error ->
        Logger.error(\"[ExtensionManager] Reload failed, keeping old version: #{inspect(reason)}\")
        {:reply, error, state}  # 保持旧版本
    end
  end
```

---

## 三、测试策略合规性分析

### 3.1 BDD 主导原则

根据 `.github/prompts/2-planning.prompt.md` L52-61：

> 1. **BDD 场景 (主)**：所有可从用户/系统视角描述的行为契约，必须且仅通过 BDD 场景验证。
> 2. **Unit Test (补充)**：仅在组合爆炸的边界 case 或纯算法/数据变换时补充。
> 3. **禁止重复**：如果一个行为已被 BDD 场景覆盖，不得再为同一行为编写 Unit Test。

### 3.2 当前测试覆盖情况

#### S4-S6：Extension Lifecycle

**现有 BDD 场景**：`test/bdd/dsl/extension_lifecycle.dsl`

```gherkin
# EXT-LIFECYCLE-001: HookRegistry 启动
# EXT-LIFECYCLE-002: on_input Hook 处理
# EXT-LIFECYCLE-003: Context hooks 修改消息
# EXT-LIFECYCLE-004: 工具调用
# EXT-LIFECYCLE-005: Session 生命周期信号
```

**覆盖度分析**：

| 功能 | BDD 覆盖 | 缺失场景 |
|---|---|---|
| on_agent_end Hook 调用 | ❌ | 需要补充 |
| on_before_agent 修改 system_prompt | ❌ | 需要补充 |
| on_compaction_before Hook | ❌ | 需要补充 |
| Session 信号发射 | ✅ | EXT-LIFECYCLE-005 |

**建议补充场景**：

```gherkin
Scenario: [EXT-LIFECYCLE-006] on_agent_end Hook 在 turn 完成时被调用
  GIVEN start_agent session_id=\"test_session\"
  GIVEN register_test_hook hook_name=\"TestEndHook\" callback=\"on_agent_end\"
  WHEN send_chat_message session_id=\"test_session\" content=\"Hello\"
  THEN wait_for_turn_complete session_id=\"test_session\"
  THEN assert_hook_called hook_name=\"TestEndHook\" callback=\"on_agent_end\"

Scenario: [EXT-LIFECYCLE-007] on_before_agent Hook 临时修改 system_prompt
  GIVEN start_agent session_id=\"test_session\"
  GIVEN register_test_hook hook_name=\"RustModeHook\" callback=\"on_before_agent\" returns='{\"system_prompt\":\"You are a Rust expert\"}'
  WHEN send_chat_message session_id=\"test_session\" content=\"Write Rust code\"
  THEN assert_llm_received_system_prompt contains=\"Rust expert\"
  WHEN send_chat_message session_id=\"test_session\" content=\"Another message\"
  THEN assert_llm_received_system_prompt not_contains=\"Rust expert\"

Scenario: [EXT-LIFECYCLE-008] on_compaction_before Hook 取消压缩
  GIVEN start_agent session_id=\"test_session\"
  GIVEN register_test_hook hook_name=\"NoCompactHook\" callback=\"on_compaction_before\" returns='{\"cancel\":\"user_request\"}'
  WHEN fill_context_to_threshold session_id=\"test_session\"
  THEN assert_compaction_not_triggered session_id=\"test_session\"
```

---

#### S7：Tape 系统

**现有 BDD 场景**：`test/bdd/dsl/tape_*.dsl`

```gherkin
# tape_storage.dsl: 基础存储和查询
# tape_branching.dsl: 分支和锚点
# tape_integration.dsl: 与 Agent 集成
```

**覆盖度分析**：

| 功能 | BDD 覆盖 | 缺失场景 |
|---|---|---|
| TapeContext.to_llm_messages | ❌ | 需要补充 |
| from_last_anchor 查询 | ✅ | tape_branching.dsl |
| Entry 转 Message 投影 | ❌ | 需要补充 |

**建议补充场景**：

```gherkin
Scenario: [TAPE-CONTEXT-001] TapeContext 恢复 LLM 消息
  GIVEN start_agent session_id=\"test_session\"
  WHEN send_chat_message session_id=\"test_session\" content=\"Hello\"
  WHEN restart_agent session_id=\"test_session\"
  THEN assert_llm_context_restored session_id=\"test_session\" contains=\"Hello\"

Scenario: [TAPE-CONTEXT-002] 从锚点恢复上下文
  GIVEN start_agent session_id=\"test_session\"
  WHEN send_chat_message session_id=\"test_session\" content=\"Message 1\"
  WHEN create_anchor session_id=\"test_session\" label=\"checkpoint\"
  WHEN send_chat_message session_id=\"test_session\" content=\"Message 2\"
  WHEN restore_from_anchor session_id=\"test_session\" label=\"checkpoint\"
  THEN assert_llm_context_contains session_id=\"test_session\" content=\"Message 2\"
  THEN assert_llm_context_not_contains session_id=\"test_session\" content=\"Message 1\"
```

**一致性约束**：
- BDD 测试只允许从 Tape 验证恢复结果，不得再使用 `history.jsonl` 作为 fallback 或断言来源。

---

#### S8：Extension 动态注册

**现有 BDD 场景**：无

**建议补充场景**：

```gherkin
Feature: Extension 动态注册

Scenario: [EXT-DYNAMIC-001] 运行时注册动态工具
  GIVEN start_agent session_id=\"test_session\"
  WHEN register_dynamic_tool tool_name=\"custom_tool\" description=\"A custom tool\"
  THEN assert_tool_available tool_name=\"custom_tool\"
  WHEN send_chat_message session_id=\"test_session\" content=\"Use custom_tool\"
  THEN assert_tool_called tool_name=\"custom_tool\"

Scenario: [EXT-DYNAMIC-002] 卸载动态工具
  GIVEN start_agent session_id=\"test_session\"
  GIVEN register_dynamic_tool tool_name=\"temp_tool\"
  WHEN unregister_dynamic_tool tool_name=\"temp_tool\"
  THEN assert_tool_not_available tool_name=\"temp_tool\"

Scenario: [EXT-DYNAMIC-003] Extension 加载和卸载
  GIVEN extension_module module=\"TestExtension\"
  WHEN load_extension module=\"TestExtension\"
  THEN assert_extension_loaded module=\"TestExtension\"
  THEN assert_hooks_registered hooks=[\"TestHook\"]
  THEN assert_tools_registered tools=[\"test_tool\"]
  WHEN unload_extension module=\"TestExtension\"
  THEN assert_extension_not_loaded module=\"TestExtension\"
  THEN assert_hooks_unregistered hooks=[\"TestHook\"]
  THEN assert_tools_unregistered tools=[\"test_tool\"]
```

---

### 3.3 Unit Test 补充建议

根据 BDD 主导原则，以下场景适合 Unit Test：

#### 1. TapeContext 投影逻辑（纯函数）

**文件**：`test/cortex/history/tape_context_test.exs`

```elixir
describe \"entry_to_message/1\" do
  test \"converts message entry with atom keys\" do
    entry = %Entry{kind: :message, payload: %{role: \"user\", content: \"Hello\"}}
    assert %ReqLLM.Message{role: :user, content: \"Hello\"} = TapeContext.entry_to_message(entry)
  end

  test \"converts message entry with string keys\" do
    entry = %Entry{kind: :message, payload: %{\"role\" => \"user\", \"content\" => \"Hello\"}}
    assert %ReqLLM.Message{role: :user, content: \"Hello\"} = TapeContext.entry_to_message(entry)
  end

  test \"returns nil for invalid entry\" do
    entry = %Entry{kind: :message, payload: %{}}
    assert nil == TapeContext.entry_to_message(entry)
  end
end
```

#### 2. ToolRegistry 动态注册（边界 case）

**文件**：`test/cortex/tools/registry_test.exs`

```elixir
describe \"register_dynamic/2\" do
  test \"registers dynamic tool\" do
    tool = %Tool{name: \"test_tool\", description: \"Test\", parameters: []}
    assert :ok = Registry.register_dynamic(tool)
    assert {:ok, ^tool} = Registry.get(\"test_tool\")
  end

  test \"dynamic tool appears in to_llm_format\" do
    tool = %Tool{name: \"dynamic_tool\", description: \"Dynamic\", parameters: []}
    Registry.register_dynamic(tool)
    llm_tools = Registry.to_llm_format()
    assert Enum.any?(llm_tools, fn t -> t.name == \"dynamic_tool\" end)
  end

  test \"unregister_dynamic removes tool\" do
    tool = %Tool{name: \"temp_tool\", description: \"Temp\", parameters: []}
    Registry.register_dynamic(tool)
    assert :ok = Registry.unregister_dynamic(\"temp_tool\")
    assert :error = Registry.get(\"temp_tool\")
  end
end
```

---

## 四、总结与建议

### 4.1 逻辑问题优先级

| 问题 | 优先级 | 影响范围 | 修复难度 |
|---|---|---|---|
| 问题 1：full_history 未移除 | 🔴 高 | 编译错误 | 中 |
| 问题 4：entry_to_message 缺少错误处理 | 🟡 中 | 数据恢复 | 低 |
| 问题 5：Extension 重载状态不一致 | 🟡 中 | 运行时稳定性 | 中 |
| 问题 2：Hook 返回值处理不完整 | 🟢 低 | 调试体验 | 低 |
| 问题 3：Compaction Hook 返回值类型 | 🟢 低 | 可观测性 | 低 |

### 4.2 测试补充优先级

| 测试类型 | 优先级 | 场景数量 | 工作量 |
|---|---|---|---|
| S4-S6 Extension Lifecycle BDD | 🔴 高 | 3 个 | 1-2 天 |
| S7 TapeContext BDD | 🟡 中 | 2 个 | 0.5 天 |
| S8 Extension 动态注册 BDD | 🟡 中 | 3 个 | 1 天 |
| TapeContext Unit Test | 🟢 低 | 5-10 个 | 0.5 天 |
| ToolRegistry Unit Test | 🟢 低 | 5-10 个 | 0.5 天 |

### 4.3 立即行动项

1. **修复编译错误**（优先级：🔴 高）
   - 移除所有 `full_history` 相关代码
   - 移除未使用的函数（`restore_messages_from_tape` 等）

2. **补充核心 BDD 场景**（优先级：🔴 高）
   - S4-S6 Extension Lifecycle（3 个场景）
   - S8 Extension 动态注册（3 个场景）

3. **增强错误处理**（优先级：🟡 中）
   - TapeContext 投影逻辑
   - Extension Manager 重载逻辑

4. **补充 Unit Test**（优先级：🟢 低）
   - TapeContext 纯函数测试
   - ToolRegistry 边界 case 测试

---

## 五、合规性声明

本分析遵循以下原则：

1. **BDD 主导**：所有用户/系统视角的行为契约通过 BDD 验证
2. **Unit Test 补充**：仅在纯函数/边界 case 时补充单元测试
3. **禁止重复**：不为已有 BDD 场景的行为编写 Unit Test

当前测试策略符合项目规范，建议按优先级补充缺失的 BDD 场景。

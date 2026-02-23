# 向后兼容代码移除实施风险分析

日期：2026-02-19
状态：⚠️ **发现严重问题，需要回滚部分变更**

## 🚨 严重问题：LLMAgent 状态不一致

### 问题描述
`LLMAgent` 的 `defstruct` 中没有 `full_history` 字段，但代码中有 **40+ 处**引用该字段：
- L319, L334, L381, L383, L504, L521, L618, L620, L716, L717, L742, L743, L764, L765, L825, L847, L853, L862, L876, L887, L1160, L1186, L1192, L1227, L1236, L1263, L1269, L1281, L1333, L1338

### 根本原因
根据 `@moduledoc` (L18-21)，`full_history` 是"完整历史记录"，用于审计、调试、UI 展示。但在某个重构中（可能是 Phase S7 Tape 迁移），该字段从 `defstruct` 中移除，而代码逻辑未同步更新。

### 影响范围
- ✅ 所有测试失败：`KeyError: key :full_history not found`
- ✅ Agent 无法处理聊天请求
- ✅ 工具调用结果无法记录
- ✅ Steering 队列无法工作
- ✅ 记忆系统集成失效

### 解决方案选项

#### 选项 A: 回滚到使用 full_history（推荐）
**理由**: 代码逻辑完整，只是 `defstruct` 缺失字段
**步骤**:
1. 在 `defstruct` 中添加 `:full_history` 字段
2. 在 `init/1` 中初始化为 `[]`
3. 保持现有代码逻辑不变

**优点**: 最小改动，立即修复问题
**缺点**: 保留了"双轨历史"系统（与 Tape 重复）

#### 选项 B: 完全移除 full_history 引用（高风险）
**理由**: 彻底迁移到 Tape 作为唯一历史源
**步骤**:
1. 移除所有 `full_history` 赋值和读取
2. 确保所有历史操作都通过 Tape
3. 更新 `get_full_history/1` 直接查询 Tape

**优点**: 符合架构目标（Tape 唯一真相源）
**缺点**: 需要大量代码变更，风险极高

### 建议
**立即执行选项 A**，将 Phase S7（移除 full_history）作为独立任务，在充分测试后再执行。

---

## 已完成的变更总览（需要验证）

### Phase 1 & 2 (低风险，已完成)
1. ✅ **A1**: 移除死代码 - `restore_messages_from_tape/1` 和 `tape_entry_to_message/1` 已在之前移除
2. ✅ **A3**: 删除 7 个 `.bak` 备份文件（3464 行代码）
3. ✅ **B1**: 验证 `tool_result` 签名 - 已全部使用 3 参数版本
4. ✅ **B2**: 验证 SignalBridge 文档 - 已正确标注为单向桥接

### Phase 2 & 3 (中等风险，已完成)
5. ✅ **A5**: 迁移 PubSub 订阅者 - `signal_subscriber.ex` 从 PubSub 迁移到 SignalHub
6. ✅ **B3-1**: 增强非标准信号监控 - 日志级别从 warning 提升到 error
7. ✅ **A2**: 移除 SignalBridge 模块 - 从监督树和文件系统删除
8. ✅ **A6**: 移除 SessionEventBridge 的 PubSub 双重广播
9. ✅ **A4**: 移除 `deprecated_events/0` 函数和 JSONL 中的 `deprecated` 字段

## 🚨 关键风险点分析

### 风险 1: SignalHub 订阅语义变化 ⚠️ HIGH

**问题**:
```elixir
# 旧代码 (PubSub)
Phoenix.PubSub.subscribe(Cortex.PubSub, "jido.studio.signals")
# 接收格式: {:signal, %Jido.Signal{}}

# 新代码 (SignalHub)
{:ok, _sub} = Cortex.SignalHub.subscribe("**", target: self())
# 接收格式: 需要验证是否一致
```

**潜在影响**:
- LiveView 的 `handle_info` 可能无法正确匹配信号消息
- 如果 SignalHub 的投递格式与 PubSub 不同，会导致信号丢失
- 所有 LiveView 页面可能无法接收到 Agent 响应、工具结果等关键事件

**验证需求**:
1. 检查 SignalHub.subscribe 的投递格式是否为 `{:signal, %Jido.Signal{}}`
2. 检查所有 LiveView 的 `handle_info` 是否正确匹配
3. 运行集成测试验证信号流

### 风险 2: SessionEventBridge 订阅者未知 ⚠️ MEDIUM

**问题**:
移除了 PubSub 广播：
```elixir
# 删除了这段代码
Phoenix.PubSub.broadcast(
  @pubsub,
  "acp.session.update:#{plan_id}",
  {:acp_session_update, plan_id, session_update, stage}
)
```

**潜在影响**:
- 如果有其他模块订阅了 `"acp.session.update:#{plan_id}"` topic，它们将收不到更新
- ACP 相关的 LiveView 可能无法显示会话状态

**验证需求**:
```bash
grep -rn "acp.session.update" lib/
grep -rn "acp_session_update" lib/
```

### 风险 3: 非标准信号兼容路径仍然存在 ⚠️ LOW

**当前状态**:
SignalRecorder 仍然处理 3 种信号格式：
1. `{:signal, %Jido.Signal{}}` - 标准格式 ✅
2. `{:signal, signal}` - 非标准（signal 非 struct）⚠️
3. `%Jido.Signal{}` - 裸 struct ⚠️

**计划中的 Phase 4 B3-2** 要移除 2 和 3，但：
- 当前只是增强了监控（error 日志）
- 没有实际移除兼容路径
- 需要先运行系统观察是否有非标准信号

**建议**: 保持当前状态，观察 1-2 个 Sprint 后再决定是否移除

### 风险 4: HookRunner 裸输出兼容 ⚠️ UNKNOWN

**计划中的 Phase 4 B4**:
```elixir
# lib/cortex/agents/llm_agent.ex L796
{:ok, output, new_state} when not is_map(output) ->
  # 向后兼容裸输出
  process_tool_result(call_id, tool_name, output, new_state)
```

**风险**:
- 没有调研现有 Hook 实现是否依赖裸输出
- 贸然移除可能导致某些 Hook 失效

**验证需求**:
```bash
grep -rn "on_tool_result" lib/cortex/hooks/
# 检查所有 Hook 的返回值格式
```

## 🔍 未完成的验证步骤

### 1. 编译检查
```bash
mix compile --warnings-as-errors
```

### 2. 静态引用检查
```bash
# 验证 SignalBridge 完全移除
grep -rn "SignalBridge" lib/ test/

# 验证 deprecated_events 完全移除
grep -rn "deprecated_events" lib/

# 验证 PubSub signal topic 完全移除
grep -rn "jido.studio.signals" lib/
```

### 3. 测试执行
```bash
mix test test/cortex/agents/ --trace
mix test test/cortex/history/ --trace
mix test test/cortex_web/ --trace
```

### 4. 信号流验证
需要手动测试：
- LiveView 能否接收 `agent.response` 信号
- LiveView 能否接收 `tool.call.result` 信号
- ACP 会话更新是否正常工作

## 📋 建议的后续步骤

### 立即执行（必需）
1. **运行编译检查** - 确保没有语法错误和未解决的引用
2. **运行测试套件** - 验证核心功能未被破坏
3. **检查 ACP 订阅者** - 确认 SessionEventBridge 的变更不会影响现有功能

### 暂缓执行（需要更多调研）
4. **Phase 4 B3-2** - 移除非标准信号兼容路径
   - 先观察 error 日志，确认无非标准信号后再移除
5. **Phase 4 B4** - 移除 HookRunner 裸输出兼容
   - 先调研所有 Hook 实现，确认都返回 map 格式

### 回滚考虑
如果测试失败，优先回滚的变更：
1. **A5** - SignalHub 订阅迁移（最高风险）
2. **A2** - SignalBridge 移除（依赖 A5）
3. **A6** - SessionEventBridge PubSub 移除

## 🎯 关键问题

### Q1: SignalHub.subscribe("**") 的投递格式是什么？
需要查看 SignalHub 源码或文档确认。

### Q2: 是否有其他模块订阅了 "acp.session.update:#{plan_id}"？
需要全局搜索确认。

### Q3: 当前系统是否有非标准信号投递？
需要运行系统并观察 SignalRecorder 的 error 日志。

### Q4: 所有 Hook 是否都返回 map 格式的 tool_result？
需要审查 `lib/cortex/hooks/` 下的所有实现。

## 结论

**当前实施进度**: 9/12 步骤完成（75%）

**风险等级**: 🟡 MEDIUM-HIGH
- Phase 1-3 的变更相对安全（删除死代码、备份文件、deprecated 标记）
- **最大风险点**: SignalHub 订阅迁移（A5）可能导致 LiveView 无法接收信号
- Phase 4 应该暂缓，需要更多观察和调研

**建议**:
1. ✅ 立即运行编译和测试验证当前变更
2. ✅ 手动测试 LiveView 信号接收
3. ⏸️ 暂停 Phase 4，观察系统运行 1-2 个 Sprint
4. 📝 根据观察结果决定是否继续 Phase 4

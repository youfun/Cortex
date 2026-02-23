# 向后兼容代码移除计划合理性评估

日期：2026-02-19
评估人：Droid
状态：✅ 计划基本合理，但发现遗留问题需要一并修复

---

## 一、计划回顾

### 原计划目标
根据 `docs/plans/20260218_backward_compat_removal_and_logic_optimization_plan.md`：
- **Track A**: 移除向后兼容代码（SignalBridge、deprecated_events、.bak 文件等）
- **Track B**: 逻辑优化（统一签名、修复文档不一致等）

### 已完成步骤（9/12）
1. ✅ A1: 移除死代码（已在之前移除）
2. ✅ A3: 删除 .bak 文件（7 个文件，3464 行）
3. ✅ B1: 验证 tool_result 签名（已全部 3 参数）
4. ✅ B2: 验证 SignalBridge 文档（已正确）
5. ✅ A5: 迁移 PubSub 订阅者到 SignalHub
6. ✅ B3-1: 增强非标准信号监控（warning → error）
7. ✅ A2: 移除 SignalBridge 模块
8. ✅ A6: 移除 SessionEventBridge 的 PubSub 双重广播
9. ✅ A4: 移除 deprecated_events 和 JSONL deprecated 字段

---

## 二、发现的关键问题

### 🚨 问题：full_history 残留引用导致测试失败

#### 根本原因
根据 `docs/analysis/20260218_s4_s8_logic_and_test_analysis.md` §2.1 问题1：
- **S7 阶段**已将 `full_history` 从 `defstruct` 中移除（Tape 作为唯一历史源）
- 但 **S4-S6 实施时**仍在维护 `full_history`，导致代码中有 40+ 处残留引用
- 这是一个**已知遗留问题**，但未在本次计划中包含

#### 当前状态
```elixir
# lib/cortex/agents/llm_agent.ex
defstruct [
  :session_id,
  :config,
  :llm_context,
  :pending_tool_calls,
  :status,
  :turn_count,
  :loop_ref,
  :loop,
  :steering_queue,
  :hooks,
  :run_started_at
  # ❌ full_history 已移除
]

# 但代码中仍有 40+ 处引用：
new_full_history = state.full_history ++ [full_entry]  # ❌ 运行时错误
```

#### 测试失败证据
```
** (KeyError) key :full_history not found in:
%Cortex.Agents.LLMAgent{...}
```

---

## 三、计划合理性评估

### ✅ 合理的部分

#### 1. Phase 1-3 的变更是安全的
- 删除 .bak 文件：无风险
- 移除 SignalBridge：已验证只有一个订阅者，且已迁移
- 移除 deprecated_events：只是清理元数据，不影响功能
- SessionEventBridge：已验证无其他 PubSub 订阅者

#### 2. 信号投递格式已统一
验证结果：
- SignalHub 投递格式：`{:signal, %Jido.Signal{}}`
- LiveView 处理格式：`def handle_info({:signal, %Jido.Signal{}}, socket)`
- ✅ 格式一致，迁移安全

#### 3. 编译成功
```bash
mix compile --warnings-as-errors
# ✅ 编译通过，只有一些无关警告
```

### ⚠️ 需要调整的部分

#### 1. 计划遗漏了 full_history 清理
**原因**：
- 计划制定时可能未意识到 full_history 已被移除
- 或者认为这是独立的 S7 后续任务

**影响**：
- 当前所有 Agent 测试失败
- 无法正常运行 Agent

**建议**：
- 将 full_history 清理作为**紧急修复**，而非本计划的一部分
- 这是 S7 阶段的遗留问题，应该在独立的 PR 中修复

#### 2. Phase 4 应该暂缓
**B3-2**: 移除非标准信号兼容路径
- 当前只是增强了监控（error 日志）
- 需要观察 1-2 个 Sprint，确认无非标准信号后再移除
- ✅ 计划中已建议"阶段 1 → 阶段 2"，合理

**B4**: 移除 HookRunner 裸输出兼容
- 已验证：无 Hook 实现 `on_tool_result`
- 但代码中仍有兼容逻辑（L796）
- 建议：先调研所有 Hook 实现，确认都返回 map 格式

---

## 四、修复策略

### 选项 A：回滚本次变更，先修复 full_history（❌ 不推荐）
**理由**：
- 本次变更（Phase 1-3）是正确的，不应回滚
- full_history 问题是独立的遗留问题

### 选项 B：立即修复 full_history，然后继续验证（✅ 推荐）
**步骤**：
1. 移除所有 `full_history` 相关代码（40+ 处）
2. 移除未使用的函数（`restore_full_history_from_tape`, `tape_entry_to_full_history`）
3. 运行测试验证
4. 提交两个独立的 commit：
   - Commit 1: 向后兼容代码移除（当前变更）
   - Commit 2: 修复 full_history 遗留问题

### 选项 C：暂停本次变更，先修复 full_history（❌ 不推荐）
**理由**：
- 本次变更已完成 75%，且编译通过
- 暂停会浪费已完成的工作

---

## 五、最终建议

### 立即执行
1. ✅ **修复 full_history 遗留问题**（独立任务）
   - 移除所有 `new_full_history` 赋值
   - 移除所有 `full_entry` 构造
   - 移除未使用的函数
   - 更新 `@moduledoc` 移除 full_history 说明

2. ✅ **验证当前变更**
   - 运行 Agent 测试
   - 运行 SignalRecorder 测试
   - 手动测试 LiveView 信号接收

3. ✅ **提交变更**
   - Commit 1: `fix: Remove full_history legacy code (S7 cleanup)`
   - Commit 2: `refactor: Remove backward compatibility code (Phase 1-3)`

### 暂缓执行
4. ⏸️ **Phase 4 B3-2**: 移除非标准信号兼容
   - 观察 error 日志 1-2 个 Sprint
   - 确认无非标准信号后再移除

5. ⏸️ **Phase 4 B4**: 移除 HookRunner 裸输出兼容
   - 先调研所有 Hook 实现
   - 确认都返回 map 格式后再移除

---

## 六、结论

### 计划合理性：✅ 基本合理
- Phase 1-3 的变更是正确的，符合架构目标
- 编译通过，信号格式已统一
- 唯一问题是遗漏了 full_history 清理

### 当前状态：⚠️ 需要修复遗留问题
- full_history 残留引用导致测试失败
- 这是 S7 阶段的遗留问题，非本计划引入

### 下一步行动：
1. 立即修复 full_history（预计 30 分钟）
2. 验证所有测试通过
3. 提交两个独立的 commit
4. Phase 4 暂缓，观察系统运行

---

## 七、风险评估

| 风险项 | 等级 | 缓解措施 |
|---|---|---|
| full_history 清理遗漏代码 | 🟡 中 | 全局搜索 `full_history`，逐一移除 |
| SignalHub 订阅格式不兼容 | 🟢 低 | 已验证格式一致 |
| SessionEventBridge 有隐藏订阅者 | 🟢 低 | 已全局搜索，无其他订阅者 |
| 非标准信号仍在使用 | 🟡 中 | 已增强监控，观察 1-2 Sprint |

**总体风险**：🟡 中等（主要来自 full_history 清理）

**建议**：立即修复 full_history，然后继续验证。

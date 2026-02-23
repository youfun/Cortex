# Phase S7: full_history 字段移除计划书

**日期**: 2026-02-20  
**状态**: 📋 待执行  
**优先级**: P1 - 高优先级（架构清理）  
**预计工期**: 2-3 天

---

## 执行摘要

Phase S7 旨在完成从双轨历史系统（`llm_context` + `full_history`）到单一 Tape 系统的迁移。当前代码中仍有 **35 处** `full_history` 引用，但该字段已从 `defstruct` 中移除，导致潜在的运行时错误。

**核心目标**:
- 移除所有 `full_history` 字段引用
- 确保所有历史查询通过 Tape 系统
- 清理数据库 schema 中的 `full_history` 列
- 更新相关测试和文档

---

## 一、背景分析

### 1.1 当前架构状态

根据 `LLMAgent` 模块文档（`lib/cortex/agents/llm_agent.ex:11-29`）：

```elixir
该模块使用 Tape 作为唯一的历史记录系统：

1. **llm_context** - LLM 对话上下文（内存）
   - 用途：发送给 LLM 的消息列表
   - 格式：ReqLLM.Message 结构体列表
   - 恢复：通过 TapeContext.to_llm_messages/2 从 Tape 恢复

2. **Tape** - 完整历史记录（外部存储）
   - 用途：审计、调试、UI 展示、回放
   - 格式：Tape.Entry 结构体（包含 trace_id, span_id）
   - 存储：JSONL 文件（.jido/tape/<session_id>.jsonl）
   - 查询：通过 Tape.Store.list_entries/1 查询

核心原则：
- 所有历史记录写入 Tape（通过 EntryBuilder）
- llm_context 仅保留最近 N 条消息（内存优化）
- 历史恢复时从 Tape 投影到 llm_context
```

**问题**: 代码中仍在维护 `full_history` 字段，与架构文档不一致。

### 1.2 历史遗留原因

根据分析文档（`docs/analysis/20260219_implementation_risk_analysis.md`）：

> 在某个重构中（可能是 Phase S7 Tape 迁移），`full_history` 字段从 `defstruct` 中移除，而代码逻辑未同步更新。

**时间线推测**:
1. **Phase 1-3**: 引入 Tape 系统，与 `full_history` 并存
2. **Phase 4-6**: 逐步迁移功能到 Tape
3. **Phase S7 (计划)**: 完全移除 `full_history`，但未完成
4. **当前状态**: `defstruct` 已移除字段，但代码逻辑未清理

### 1.3 影响范围统计

| 类型 | 数量 | 说明 |
|---|---|---|
| 代码引用 (lib/) | 35 处 | 包括读取、写入、传递 |
| 测试引用 (test/) | 0 处 | 测试已完全迁移到 Tape |
| 数据库字段 | 2 处 | `conversations` 表和迁移文件 |
| 文档注释 | 10+ 处 | 标注 "Phase S7 将移除" |

**关键发现**: 测试代码已完全不依赖 `full_history`，说明 Tape 系统功能完整。

---

## 二、执行计划

### 2.1 Phase S7.1: 代码清理（1 天）

#### 任务 S7.1.1: 移除 LLMAgent 中的 full_history 引用

**文件**: `lib/cortex/agents/llm_agent.ex`

**变更点**:
1. **L64**: 移除 `defstruct` 中的注释（字段已不存在）
   ```elixir
   # 删除这行注释
   # 完整历史记录（Phase S7 将移除，改用 Tape）
   ```

2. **L334-336**: 修改 `get_full_history/1` 实现
   ```elixir
   # 当前实现（错误）
   def handle_call(:get_full_history, _from, state) do
     {:reply, state.full_history, state}  # ❌ 字段不存在
   end
   
   # 新实现（正确）
   def handle_call(:get_full_history, _from, state) do
     alias Cortex.History.Tape.Store
     entries = Store.list_entries(state.session_id)
     {:reply, entries, state}
   end
   ```

3. **L780-789**: 移除 `full_entry` 构造和 `new_full_history` 赋值
   ```elixir
   # 删除这段代码
   # ✅ 同时加入完整历史记录（Phase S7 将移除 full_history）
   full_entry = %{
     type: "assistant_response",
     timestamp: DateTime.utc_now(),
     data: assistant_msg,
     metadata: %{...}
   }
   new_full_history = state.full_history ++ [full_entry]
   ```

4. **其他位置**: 移除所有 `full_history: new_full_history` 赋值

**验证**:
```bash
# 确认所有引用已移除
grep -rn "full_history" lib/cortex/agents/llm_agent.ex
# 预期输出：0 处
```

#### 任务 S7.1.2: 移除 LoopHandler 中的 full_history 引用

**文件**: `lib/cortex/agents/llm_agent/loop_handler.ex`

**变更点**:
1. **L66**: 移除注释
2. **L78, L106, L112, L147, L156, L193, L199**: 移除所有 `full_history` 相关代码

**模式**:
```elixir
# 删除所有类似代码
new_full_history = Map.get(state, :full_history, []) ++ [full_entry]
%{state | full_history: new_full_history}
```

#### 任务 S7.1.3: 移除 ToolExecution 中的 full_history 引用

**文件**: `lib/cortex/agents/llm_agent/tool_execution.ex`

**变更点**:
1. **L29**: 移除文档注释
2. **L34**: 移除函数参数 `full_history`
   ```elixir
   # 当前签名
   def process_calls(state, tool_calls, llm_context, full_history)
   
   # 新签名
   def process_calls(state, tool_calls, llm_context)
   ```

3. **L89, L94**: 移除返回值中的 `full_history` 字段

#### 任务 S7.1.4: 更新 SessionCoordinator

**文件**: `lib/cortex/session/coordinator.ex`

**变更点**:
1. **L107-111**: 修改 `save_state/1` 实现
   ```elixir
   # 当前实现
   full_history = LLMAgent.get_full_history(pid)
   %{llm_context: llm_context, full_history: full_history}
   
   # 新实现
   # full_history 已通过 Tape 持久化，无需单独保存
   %{llm_context: llm_context}
   ```

#### 任务 S7.1.5: 更新 BDD Instructions

**文件**: `lib/cortex/bdd/instructions/v1.ex`

**变更点**:
1. **L464**: 修改历史查询逻辑
   ```elixir
   # 当前实现
   history = Cortex.Agents.LLMAgent.get_full_history(pid)
   
   # 新实现
   alias Cortex.History.Tape.Store
   history = Store.list_entries(session_id)
   ```

**预期结果**: 代码中不再有任何 `full_history` 引用。

---

### 2.2 Phase S7.2: 数据库清理（0.5 天）

#### 任务 S7.2.1: 创建迁移文件移除 full_history 列

**文件**: `priv/repo/migrations/YYYYMMDD_remove_full_history_from_conversations.exs`

```elixir
defmodule Cortex.Repo.Migrations.RemoveFullHistoryFromConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      remove :full_history
    end

    # 移除索引
    drop_if_exists index(:conversations, [:full_history])
  end
end
```

#### 任务 S7.2.2: 更新 Conversation Schema

**文件**: `lib/cortex/conversations/conversation.ex`

**变更点**:
1. **L24**: 移除字段定义
   ```elixir
   # 删除这行
   field :full_history, {:array, :map}, default: []
   ```

2. **L47**: 从 changeset 中移除
   ```elixir
   # 删除 :full_history
   |> cast(attrs, [
     :current_plan_id,
     :title,
     :context,
     :status,
     :last_used_at,
     :is_pinned,
     :kind,
     :model_config,
     :meta,
     :llm_context
     # :full_history  # ❌ 移除
   ])
   ```

#### 任务 S7.2.3: 运行迁移

```bash
# 开发环境
mix ecto.migrate

# 测试环境
MIX_ENV=test mix ecto.migrate
```

---

### 2.3 Phase S7.3: 测试验证（0.5 天）

#### 任务 S7.3.1: 运行完整测试套件

```bash
mix test
```

**预期结果**: 所有测试通过（当前 140 个失败应不受影响）

#### 任务 S7.3.2: 验证 Tape 系统功能

**测试场景**:
1. 创建新会话，发送消息
2. 查询 Tape 历史：`Tape.Store.list_entries(session_id)`
3. 恢复 LLM 上下文：`TapeContext.to_llm_messages(session_id)`
4. 验证 JSONL 文件生成：`.jido/tape/<session_id>.jsonl`

**验证脚本**:
```elixir
# test/cortex/history/tape_full_workflow_test.exs
defmodule Cortex.History.TapeFullWorkflowTest do
  use Cortex.DataCase
  alias Cortex.Agents.LLMAgent
  alias Cortex.History.Tape.Store
  alias Cortex.History.TapeContext

  test "complete workflow: chat -> tape -> restore" do
    session_id = "test_session_#{System.unique_integer()}"
    
    # 1. 启动 Agent 并发送消息
    {:ok, pid} = LLMAgent.start_link(session_id: session_id)
    LLMAgent.chat(pid, "Hello, world!")
    
    # 2. 验证 Tape 中有记录
    entries = Store.list_entries(session_id)
    assert length(entries) > 0
    
    # 3. 恢复 LLM 上下文
    messages = TapeContext.to_llm_messages(session_id)
    assert Enum.any?(messages, fn msg -> msg.content =~ "Hello, world!" end)
    
    # 4. 验证 JSONL 文件存在
    tape_file = Path.join([
      Cortex.Workspaces.workspace_root(),
      ".jido/tape",
      "#{session_id}.jsonl"
    ])
    assert File.exists?(tape_file)
  end
end
```

#### 任务 S7.3.3: 验证 BDD 测试

```bash
# 运行所有 BDD 生成测试
mix test test/bdd_generated/
```

**关注点**: 确保历史断言仍然有效（应使用 Tape 查询）

---

### 2.4 Phase S7.4: 文档更新（0.5 天）

#### 任务 S7.4.1: 更新架构文档

**文件**: `AGENTS.md`

**变更点**:
1. 移除所有 "Phase S7 将移除" 的注释
2. 更新双轨历史系统说明：
   ```markdown
   ### 4. 单一历史系统 (The Memory)
   
   系统使用 Tape 作为唯一的历史记录系统：
   - **Tape**: 完整历史记录，存储在 `.jido/tape/<session_id>.jsonl`
   - **llm_context**: 从 Tape 投影的 LLM 消息列表（内存优化）
   
   所有历史查询通过 `Tape.Store` 和 `TapeContext` 进行。
   ```

#### 任务 S7.4.2: 更新分析文档

**文件**: `docs/analysis/20260220_test_failures_analysis.md`

**变更点**:
1. 移除 "full_history 字段状态" 章节
2. 更新为：
   ```markdown
   ### ✅ Phase S7 已完成
   
   `full_history` 字段已从代码和数据库中完全移除，系统现在使用 Tape 作为唯一历史源。
   ```

#### 任务 S7.4.3: 创建完成报告

**文件**: `docs/progress/20260220_phase_s7_completion.md`

**内容**:
- 执行摘要
- 变更清单
- 测试结果
- 遗留问题（如有）

---

## 三、风险评估

### 3.1 技术风险

| 风险 | 等级 | 缓解措施 |
|---|---|---|
| Tape 系统性能问题 | 🟡 中 | 已有索引和缓存机制，测试中验证 |
| 历史恢复逻辑错误 | 🟡 中 | 通过 `TapeContext` 测试覆盖 |
| 数据库迁移失败 | 🟢 低 | 只是删除列，风险极低 |
| 现有功能回归 | 🟡 中 | 完整测试套件验证 |

### 3.2 业务风险

| 风险 | 等级 | 缓解措施 |
|---|---|---|
| 用户数据丢失 | 🟢 低 | Tape 已持久化所有历史，无数据丢失 |
| UI 展示异常 | 🟡 中 | 验证 LiveView 历史查询逻辑 |
| 调试能力下降 | 🟢 低 | Tape 提供更强大的调试能力（trace_id） |

### 3.3 回滚计划

如果发现严重问题，可以回滚：

1. **代码回滚**: 恢复 `full_history` 字段和相关逻辑
2. **数据库回滚**: 运行反向迁移
   ```bash
   mix ecto.rollback
   ```

**回滚成本**: 低（所有变更都在版本控制中）

---

## 四、执行检查清单

### Phase S7.1: 代码清理
- [x] S7.1.1: 移除 LLMAgent 中的 full_history 引用
- [x] S7.1.2: 移除 LoopHandler 中的 full_history 引用
- [x] S7.1.3: 移除 ToolExecution 中的 full_history 引用
- [x] S7.1.4: 更新 SessionCoordinator
- [x] S7.1.5: 更新 BDD Instructions
- [x] 验证：`grep -rn "full_history" lib/` 返回 0 处

### Phase S7.2: 数据库清理
- [x] S7.2.1: 创建迁移文件
- [x] S7.2.2: 更新 Conversation Schema
- [ ] S7.2.3: 运行迁移（dev + test）
- [ ] 验证：`mix ecto.migrations` 显示迁移已执行

### Phase S7.3: 测试验证
- [ ] S7.3.1: 运行完整测试套件（`mix test`）
- [ ] S7.3.2: 验证 Tape 系统功能（新增测试）
- [ ] S7.3.3: 验证 BDD 测试（`mix test test/bdd_generated/`）
- [ ] 验证：所有测试通过或失败数不增加

### Phase S7.4: 文档更新
- [x] S7.4.1: 更新 AGENTS.md
- [x] S7.4.2: 更新分析文档
- [x] S7.4.3: 创建完成报告
- [ ] 验证：`grep -rn "Phase S7" docs/` 只返回历史记录

---

## 五、成功标准

### 5.1 代码质量
- ✅ 代码中不再有 `full_history` 引用
- ✅ 所有编译警告消失
- ✅ 代码符合架构文档描述

### 5.2 功能完整性
- ✅ 所有历史查询通过 Tape 系统
- ✅ LLM 上下文恢复正常工作
- ✅ BDD 测试中的历史断言正常工作

### 5.3 测试覆盖
- ✅ 测试通过率不下降
- ✅ 新增 Tape 完整工作流测试
- ✅ 所有 BDD 测试通过

### 5.4 文档完整性
- ✅ 架构文档与代码一致
- ✅ 所有 "Phase S7 将移除" 注释已清理
- ✅ 完成报告已创建

---

## 六、后续优化（可选）

### 6.1 性能优化
- 为 Tape 查询添加缓存层
- 优化 JSONL 文件读取性能
- 实现 Tape 分片（大会话支持）

### 6.2 功能增强
- 实现 Tape 压缩（历史归档）
- 添加 Tape 导出/导入功能
- 支持 Tape 分支和合并（时间旅行）

### 6.3 监控和调试
- 添加 Tape 写入性能监控
- 实现 Tape 可视化工具
- 添加 Tape 完整性检查

---

## 七、参考资料

### 相关文档
- [测试失败分析报告](../analysis/20260220_test_failures_analysis.md)
- [S4-S8 实施回顾](../analysis/20260218_s4_s8_logic_and_test_analysis.md)
- [实施风险分析](../analysis/20260219_implementation_risk_analysis.md)
- [数据库迁移修复报告](../progress/20260220_database_migration_fix.md)

### 相关代码
- `lib/cortex/agents/llm_agent.ex` - LLMAgent 主模块
- `lib/cortex/history/tape/` - Tape 系统实现
- `lib/cortex/history/tape_context.ex` - Tape 到 LLM 消息投影
- `priv/repo/migrations/20260210013509_add_dual_track_history.exs` - 原始迁移

### 相关 Issues
- Phase S7 计划（原始设计文档）
- full_history 清理脚本：`scripts/clean_full_history.py`

---

## 八、执行时间表

| 阶段 | 预计时间 | 负责人 | 状态 |
|---|---|---|---|
| S7.1: 代码清理 | 1 天 | TBD | 📋 待执行 |
| S7.2: 数据库清理 | 0.5 天 | TBD | 📋 待执行 |
| S7.3: 测试验证 | 0.5 天 | TBD | 📋 待执行 |
| S7.4: 文档更新 | 0.5 天 | TBD | 📋 待执行 |
| **总计** | **2.5 天** | | |

**建议开始时间**: 在完成当前 P0 测试修复后立即执行  
**预计完成时间**: 2026-02-23

---

## 九、批准和签署

| 角色 | 姓名 | 签名 | 日期 |
|---|---|---|---|
| 技术负责人 | | | |
| 架构师 | | | |
| 测试负责人 | | | |

---

**文档版本**: v1.0  
**最后更新**: 2026-02-20  
**下次审查**: Phase S7 完成后

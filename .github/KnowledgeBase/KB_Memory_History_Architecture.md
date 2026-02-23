# 内存与历史子系统设计

- 内存子系统受 `Cortex.Memory.Supervisor` 监督，包含**工作记忆（Tape）**、**长期记忆（KG/Observations）**与**展示记忆（SQLite）**三部分。
- **工作记忆（Tape）**：作为 Agent 的精简工作记忆，存储关键业务里程碑。采用 JSONL 格式（`.jido/tape/`），支持分支（Branching）和秒级会话恢复。
- **长期记忆（Long-term Memory）**：由观测、知识图谱（KG）和提议系统组成，负责跨会话的知识沉淀。
- **展示记忆（Display Memory）**：由 `Cortex.Messages.Writer` 负责写入 SQLite 数据库，专门用于 UI 展示和状态追踪。
- **全量审计轨（Archive Track）**：由 `SignalRecorder` 记录全量信号到 `history.jsonl`，作为系统调试和审计的“黑匣子”。

# Jido 内存系统当前状态（2026-02-15 更新）

## 1. 运行时拓扑（启动了哪些进程）
内存与历史系统由多组独立进程组成：

- `Cortex.History.Tape.Store`: 管理工作记忆条目。
- `Cortex.History.SignalRecorder`: 记录全量审计日志。
- `Cortex.Messages.Writer`: 同步信号到 SQLite。
- `Cortex.Memory.Store`: 管理观测数据。
- `Cortex.Memory.Subconscious`: 信号抽取与提议生成。
- `Cortex.Memory.Consolidator`: 知识图谱维护。

## 2. 核心存储体系（三轨并行）

### 2.1 轨道 A：全量审计轨 (Archive Track)
- **组件**：`Cortex.History.SignalRecorder`
- **存储**：`history.jsonl`
- **特性**：携带全链路 Trace ID，记录所有内部信号（排除 `memory.*`, `kg.*`, `ui.*` 等潜意识噪音）。

### 2.2 轨道 B：结构化工作记忆 (Context Track / Tape)
- **组件**：`Cortex.History.Tape.Store`
- **存储**：`.jido/tape/<encoded_session_id>.jsonl`
- **特性**：
    - **精简化**：仅记录关键里程碑（Chat Request, Response, Tool Call/Result）。
    - **可逆映射**：文件名采用 Base64 URL 编码 Session ID，确保 100% 可还原。
    - **DateTime 强类型**：内存与磁盘统一使用 ISO8601/DateTime 结构体，保证排序一致性。
    - **分支化**：支持并行探索场景下的快速会话克隆。

### 2.3 轨道 C：UI 展示记忆 (Display Track)
- **组件**：`Cortex.Messages.Writer`
- **存储**：SQLite 数据库 (`messages` 表)
- **特性**：支持消息状态机（`executing` -> `completed`），提供 UI 所需的分页加载和实时更新信号。


### 2.4 轨道 D：Token 预算管理 (Token Budget Management)
- **组件**：`Cortex.Memory.TokenBudget` (策略层) 与 `Cortex.Agents.TokenCounter` (执行层)
- **特性**：
    - **统一估算**：全系统共享 `TokenCounter` 的细粒度中英文混合估算算法（中文≈2, 英文≈1.3）。
    - **模型感知**：支持查询 Gemini, Claude, GPT 等主流模型的上下文窗口限制（128k - 1M+）。
    - **优先级裁剪**：`TokenBudget.crop_to_budget` 支持根据 Token 预算自动裁剪低优先级上下文，确保 Prompt 不溢出。
    - **动态分配**：支持为记忆、系统提示词、工具定义动态分配 Token 比例。

## 3. 核心流程

### 3.1 会话恢复流程
1. `LLMAgent` 启动时调用 `Tape.Store.list_entries(session_id, limit: 100)`。
2. 从 Tape 恢复对话上下文（`llm_context`）。
3. UI 通过 `Messages.Writer` 发射的 `conversation.message.created` 信号渲染界面。

### 3.2 审计轨使用边界
- `history.jsonl` 仅作为审计与调试用途，不作为功能性恢复或 BDD 断言来源。
- BDD 与运行时恢复流程一律以 Tape 为唯一来源，不做 `history.jsonl` fallback。

### 3.2 观测与提议 (见原有逻辑)
- `Subconscious` 监听 Tape 支持的信号（如工具结果），通过规则抽取提议。
- 高置信度提议可由 `LLMAgent` 自动接受并转化为长期记忆。

## 4. 存储规约
- **文件沙箱**：所有 Tape 操作通过 `Cortex.Workspaces.workspace_root()` 定位，遵循项目沙箱规约。
- **信号标准**：强制执行 `SignalHub` 的规范化发射（provider, event, action, actor, origin），确保审计链完整。
- **BDD 路径脱敏**：生成的测试代码自动将绝对路径替换为 `./`，确保跨机器兼容性。

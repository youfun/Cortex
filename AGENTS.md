# Cortex Development Guidelines

This is a **signal-driven coding agent workstation** built with the Phoenix web framework and powered by the BEAM VM.

## Architecture Principles (V3 Core)

### 1. Signal-First Communication (The Nervous System)

Cortex 是一个**多通道汇聚中心**（GUI + SNS Bot + Webhook + 任务中心 + Agent 自进化（skills自进化）），信号总线是让这些异构入口统一协作的核心基础设施。

#### 1.1 核心规则：跨边界必须走信号

不同**组件**之间的通信必须通过 `SignalHub`（CloudEvents 1.0.2），禁止直接函数调用。所有发射的信号必须遵循严格的组装规范。

#### 1.2 信号组装规范 (Signal Assembly Specification)

为保证审计、路由和跨通道一致性，所有通过 `SignalHub.emit` 发射的信号必须包含以下必需字段：

- **`provider`**: 信号产生的子系统（如 `ui`, `agent`, `tool`, `system`, `telegram`, `webhook`）
- **`event`**: 业务领域事件名（如 `chat`, `model`, `file`, `permission`, `session`）
- **`action`**: 具体动作（如 `request`, `change`, `read`, `resolve`, `create`）
- **`actor`**: 触发动作的实体标识（如 `user`, `llm_agent`, `loader`, `system_exec`）
- **`origin`**: 审计来源元数据，必须包含 `channel` 和 `client`
  - 通用字段：`channel`, `client`, `platform`, `user_id_hash`, `session_id`
  - 示例：`%{channel: "ui", client: "web", platform: "windows", session_id: "..."}`

所有非固定路由字段必须放入 `payload` 中。`SignalHub.emit` 会自动将未识别的顶层字段移入 `payload` 并进行结构校验。

**Correct — 规范化发射：**
```elixir
SignalHub.emit("agent.chat.request", %{
  provider: "ui",
  event: "chat",
  action: "request",
  actor: "user",
  origin: %{channel: "ui", client: "web", platform: "macos"},
  content: "Hello",
  session_id: "session_123"
}, source: "/ui/web/chat")
```

**Incorrect — 缺少必需字段（将被拒绝）：**
```elixir
# ERROR: Missing provider, event, action, actor, origin
SignalHub.emit("agent.chat.request", %{content: "Hello"}, source: "/ui")
```

#### 1.3 模块内部允许直接调用

同一模块（如 Memory 子系统内部）的协作**可以**使用直接函数调用，无需走信号总线：

```elixir
# ✅ 模块内部直接调用 —— 高性能、易调试
defp do_recall(index_pid, query, opts) do
  Index.recall(index_pid, query, opts)
end

# ✅ 操作完成后发射信号 —— 通知外部订阅者
SignalHub.emit("memory.index.recalled", %{query: query, count: length(results)})
```

#### 1.3 防级联保护

信号回调中**禁止**触发可能产生新信号的链式反应。已知案例：`load_working_memory` 曾因信号反馈循环达到 131K signals/sec。

- **读操作**不发射信号
- **写操作**完成后只发射一次结果通知，不订阅自己的通知类型

#### 1.4 信号的三大职责

| 职责 | 示例 | 说明 |
|---|---|---|
| **跨通道统一入口** | `agent.chat.request` | GUI/Telegram/Webhook 统一触发 |
| **异步事件通知** | `agent.response`, `tool.result.*` | Dispatcher 自动转发到对应通道 |
| **审计与回放** | `SignalRecorder →  history.jsonl` | 全量持久化，支持调试回放 |

#### 1.6 信号投递形态 (Standard Delivery Format)

为消除歧义并简化订阅端逻辑，V3 架构统一信号投递形态为：

- `{:signal, %Jido.Signal{...}}`

所有订阅端应仅处理此形态。不再推荐直接匹配 `%Jido.Signal{}` 结构体，除非是在某些特殊的底层中间件中。

```elixir
def handle_info({:signal, %Jido.Signal{type: type} = signal}, state) do
  handle_signal(type, signal, state)
end
```

### 2. 4+1 Minimalism Philosophy (The Hands)
The system provides exactly 5 core tools, inspired by Pi's design. **No other tools are allowed.**

- `read_file(path)` - Read file contents
- `write_file(path, content)` - Create/overwrite files
- `edit_file(path, diff)` - Precise string replacement
- `shell(command)` - Execute CLI commands
- `iex(code)` - Persistent Elixir REPL

Additional functionality (e.g., listing directories, git ops) MUST be implemented as **Skills** using the `shell` tool, not as new hardcoded tools.

### 3. Security Sandbox (The Shield)
- **Path Sandbox**: All file operations are strictly confined to the workspace root. Path traversal (`../`) is blocked.
- **Command Audit**: High-risk shell commands (e.g., `rm`, `git push`, `npm install`) are intercepted and require explicit user approval via the `system.approval_required` signal.

### 4. Tape-First History (The Memory)

The system now depends on Tape as the single source of truth for historical data:

- **Tape**: Stores every signal and tool interaction under `./tape/<session_id>.jsonl` and is queried through `Tape.Store` and `TapeContext`. Tape entries remain immutable and power auditing, UI playback, and LLM recovery.
- **LLM Context (`llm_context`)**: A sliding window derived from Tape via `TapeContext.to_llm_messages/2`, trimmed to the portion actively used for inference. Agents write through the Tape API rather than keeping a separate `full_history` field.

### 5. Self-Evolution via Skills (The Growth)
Agents can extend themselves by writing Markdown files to ` skills/<name>/SKILL.md`.
- **Hot Reload**: The `SkillsWatcher` detects file changes and instantly reloads skills.
- **Signal Feedback**: Emits `skill.loaded` or `skill.error` signals to inform the Agent of success/failure.

## Project Guidelines

- **Signal Persistence**: All signals are automatically persisted to ` history.jsonl`.
- **Documentation Persistence**: All analysis docs, summary docs, planning docs, and progress reports MUST be saved as Markdown files under `docs/` in the corresponding subfolders:
  - `docs/analysis/` (分析文档)
  - `docs/summary/` (总结文档)
  - `docs/plans/` (计划文档)
  - `docs/progress/` (进度报告)
  Do not only output content to the TUI; ensure it is persisted to the local filesystem for long-term reference.
- **Dependency Management**: Use `:req` for HTTP. Avoid adding new dependencies unless absolutely necessary.
- **Process Isolation**: LiveView MUST NOT hold PIDs of Agents. Agents are supervised by `SessionSupervisor` and recovered automatically.
- **Testing**: Use `mix test` to verify signal flows. Tests should emit signals and assert on side effects (DB updates or outgoing signals), not check internal state.

### 标准迭代工作流 (BDD + Taskctl)

在进行功能新增、Bug 修复或重构任务时，或者用户指令以 `code` 开头时，Agent 必须遵循 **BDD 驱动的任务迭代流程**（见 `.agent/skills/bddc/SKILL.md`）。此流程结合了任务规划 (`taskctl`)、行为规范定义 (`bddc`) 和代码实现。

当任务涉及功能迭代时，请引用并参考 `.agent/prompts/feature_iteration.md` 中的详细指令。

#### 智能规划模式 (Planning Mode)

当 Agent 处于 `plan` 模式，或者用户指令以 `plan` 开头时，必须激活规划流程：
- **Prompt 引导**：使用 `.github/prompts/2-planning.prompt.md` 作为核心规约。
- **产出物**：必须在 `docs/plans/` 目录下生成规划文档（文件名应根据任务内容分析并命名，格式如 `YYYYMMDD_task_description_planning.md`），作为后续实施的唯一蓝图。
- **核心流程**：遵循“规划先行”原则，先完成架构分析、任务依赖图（DAG）和 BDD 场景定义，严禁在未完成规划的情况下直接编写代码。

- 关于工具的具体用法和路径解析（BDDC, BCC, Taskctl），请参考 `.github/KnowledgeBase` 下的相关文档。

输出计划文件时，请在计划中附上此次 BDD 驱动迭代流程 的相关说明



### 📚 Architecture References

Cortex incorporates best practices from several reference projects:

- **Gong**: Elixir Agent engine with ReAct loops and hook system (`docs/gong-master`)
- **OpenClaw China**: China IM platform integration patterns (`docs/openclaw-china-main`)
- **Pi Mono**: TypeScript Agent toolkit with modular design (`docs/pi-mono-main`)
- **Cli**: Command-line tools and compilers (`docs/Cli-master`)
- **Arbor**: Memory system with vector search and knowledge graphs (`docs/arbor_reference`)

For detailed architecture guidance, see:
- [Reference Architecture Guide](docs/REFERENCE_ARCHITECTURE.md)
- [References Index](docs/REFERENCES_INDEX.md)
- [Project Reference Guide](REFERENCE_GUIDE.md)


For detailed Elixir development standards, architectural principles, and coding patterns, please refer to:
- [.github/Guidelines/ElixirStyleGuide.md](.github/Guidelines/ElixirStyleGuide.md)

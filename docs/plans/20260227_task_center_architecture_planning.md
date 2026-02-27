# Cortex 任务中心架构设计方案

**日期**: 2026-02-27  
**版本**: v1.0  
**状态**: 规划中

---

## 一、背景与目标

### 1.1 项目背景

Cortex 是一个**信号驱动的多通道 AI Agent 工作站**，当前已支持：
- GUI（Phoenix LiveView）
- SNS Bot（Telegram、飞书、钉钉）
- Webhook 接入
- Agent 自进化（Skills 系统）

现需增加**任务中心（Task Center）**，作为第五个核心通道，实现：
- 异步任务调度与执行
- 长时任务管理（如代码重构、批量分析）
- 定时任务支持
- 多 Agent 协作任务编排

### 1.2 调研总结

#### OpenClaw/NanoClaw 架构特点

**OpenClaw**（2026 年主流 AI Agent 框架）：
- **架构**：单进程 Node.js + SQLite 持久化
- **通信**：基于文件系统 IPC 的容器隔离
- **任务模型**：Gateway（控制平面）+ Agent Runtime（思考循环）+ Skills（扩展）
- **问题**：安全性差（无沙箱）、单用户架构、复杂度高（45+ 依赖）

**NanoClaw**（安全优化版本）：
- **核心改进**：容器级隔离（Docker/Apple Containers）
- **代码量**：~500 行 TypeScript（极简主义）
- **特性**：Agent Swarms（多 Agent 协作）、Skills over Features
- **安全**：OS 级文件系统隔离 + 5 分钟超时

#### AI Agent 任务队列通用模式

根据调研，业界主流架构模式包括：

1. **Orchestrator-Worker 模式**（中心化编排）
   - 中央调度器分解任务并分配给专业 Worker
   - 适合复杂、可并行化的工作流

2. **Actor Model + Digital Twins**（状态本地化）
   - 每个 Agent 作为独立 Actor 管理自己的状态
   - 避免网络延迟，提升推理效率

3. **Event-Driven Queue**（事件驱动队列）
   - 异步消息队列 + 背压管理
   - 提升可预测性和弹性

4. **Hierarchical Decomposition**（层级分解）
   - 多层任务分解，顶层协调器管理子 Agent
   - 平衡控制力和可扩展性

#### Elixir/Phoenix 生态最佳实践

- **GenServer + Task.Supervisor**：轻量级后台任务
- **Oban**：生产级任务队列（PostgreSQL 后端）
- **GenStage/Flow**：背压感知的流式处理
- **DynamicSupervisor**：动态进程管理（Cortex 已使用）

---

## 二、Cortex 任务中心架构设计

### 2.1 核心设计原则

#### 原则 1：信号驱动，零直接调用
- 任务中心与其他组件通过 `SignalHub` 通信
- 任务生命周期事件全部发射信号（创建、启动、完成、失败）

#### 原则 2：BEAM 原生，拥抱 OTP
- 利用 Elixir 轻量级进程模型，避免引入外部队列（如 Redis）
- 使用 `DynamicSupervisor` + `GenServer` 实现任务隔离和容错

#### 原则 3：Tape-First 审计
- 所有任务信号自动持久化到 `Tape.Store`
- 支持任务回放和调试

#### 原则 4：Skills 优先
- 任务执行逻辑通过 Skills 扩展，而非硬编码工具
- 支持用户自定义任务类型

### 2.2 架构组件

```
┌─────────────────────────────────────────────────────────────┐
│                      Cortex Application                      │
├─────────────────────────────────────────────────────────────┤
│  SignalHub (CloudEvents 1.0.2 Bus)                          │
│    ↓ task.create.request                                    │
│    ↓ task.status.changed                                    │
│    ↓ task.result.ready                                      │
├─────────────────────────────────────────────────────────────┤
│  TaskCenter.Coordinator (GenServer)                         │
│    - 任务注册表（ETS）                                        │
│    - 优先级队列管理                                           │
│    - 任务调度策略                                             │
├─────────────────────────────────────────────────────────────┤
│  TaskCenter.Supervisor (DynamicSupervisor)                  │
│    ├─ TaskWorker (GenServer) - 执行单个任务                  │
│    ├─ TaskWorker (GenServer)                                │
│    └─ TaskWorker (GenServer)                                │
├─────────────────────────────────────────────────────────────┤
│  TaskCenter.Store (GenServer)                               │
│    - SQLite 持久化（任务元数据、状态、结果）                   │
│    - 定时任务调度（cron-like）                                │
├─────────────────────────────────────────────────────────────┤
│  TaskCenter.Executor (Protocol)                             │
│    - 任务执行协议（支持 Skills、Shell、Agent 调用）            │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 信号规范

#### 任务创建
```elixir
SignalHub.emit("task.create.request", %{
  provider: "ui",           # 或 "telegram", "webhook"
  event: "task",
  action: "create",
  actor: "user",
  origin: %{channel: "ui", client: "web", platform: "macos"},
  task_type: "code_refactor",  # 任务类型（对应 Skill）
  priority: :normal,           # :high, :normal, :low
  schedule: nil,               # 立即执行，或 cron 表达式
  params: %{
    target_path: "lib/cortex",
    instructions: "重构信号处理逻辑"
  }
}, source: "/ui/web/tasks")
```

#### 任务状态变更
```elixir
SignalHub.emit("task.status.changed", %{
  provider: "task_center",
  event: "task",
  action: "status_changed",
  actor: "coordinator",
  origin: %{channel: "system", client: "task_center", platform: "server"},
  task_id: "task_123",
  old_status: :pending,
  new_status: :running,
  worker_pid: "#PID<0.456.0>"
})
```

#### 任务完成
```elixir
SignalHub.emit("task.result.ready", %{
  provider: "task_center",
  event: "task",
  action: "result_ready",
  actor: "worker",
  origin: %{channel: "system", client: "task_worker", platform: "server"},
  task_id: "task_123",
  status: :completed,  # 或 :failed
  result: %{
    files_modified: 12,
    summary: "重构完成，所有测试通过"
  },
  duration_ms: 45000
})
```

### 2.4 任务生命周期

```
[创建] → [排队] → [调度] → [执行] → [完成/失败]
  ↓        ↓        ↓        ↓          ↓
 信号    信号     信号     信号       信号
  ↓        ↓        ↓        ↓          ↓
Tape    Tape     Tape     Tape       Tape
```

1. **创建阶段**：
   - 接收 `task.create.request` 信号
   - 验证任务类型和参数
   - 分配 `task_id`，写入 `TaskCenter.Store`
   - 发射 `task.status.changed` (pending)

2. **排队阶段**：
   - `TaskCenter.Coordinator` 根据优先级排队
   - 检查并发限制（如最多 5 个并行任务）

3. **调度阶段**：
   - 从队列取出任务
   - 通过 `DynamicSupervisor` 启动 `TaskWorker`
   - 发射 `task.status.changed` (running)

4. **执行阶段**：
   - `TaskWorker` 调用 `TaskCenter.Executor` 协议
   - 根据 `task_type` 加载对应 Skill
   - 执行过程中可发射进度信号（`task.progress.updated`）

5. **完成阶段**：
   - 发射 `task.result.ready`
   - 更新 `TaskCenter.Store`
   - 通知原始请求通道（通过 `SignalDispatcher`）

### 2.5 与现有系统集成

#### 与 Agent 系统集成
- 任务可以调用 `LLMAgent` 执行复杂推理
- 通过信号触发：`agent.chat.request` → 等待 `agent.response`

#### 与 Skills 系统集成
- 任务类型映射到 Skills（如 `code_refactor` → `skills/code_refactor/SKILL.md`）
- 利用现有 `SkillsWatcher` 热重载机制

#### 与 Memory 系统集成
- 长时任务可以访问 `WorkingMemory` 和 `Subconscious`
- 任务结果可以写入 Memory 作为知识积累

#### 与 Tape 系统集成
- 所有任务信号自动记录到 `Tape.Store`
- 支持任务历史查询和回放

---

## 三、技术实现细节

### 3.1 数据模型

#### Task Schema (SQLite)
```elixir
defmodule Cortex.TaskCenter.Task do
  use Ecto.Schema

  schema "tasks" do
    field :task_id, :string
    field :task_type, :string
    field :status, Ecto.Enum, values: [:pending, :running, :completed, :failed, :cancelled]
    field :priority, Ecto.Enum, values: [:high, :normal, :low]
    field :schedule, :string  # cron 表达式或 nil
    field :params, :map
    field :result, :map
    field :error, :string
    field :created_by, :string  # origin channel
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    timestamps()
  end
end
```

### 3.2 核心模块

#### TaskCenter.Coordinator
```elixir
defmodule Cortex.TaskCenter.Coordinator do
  use GenServer
  
  @max_concurrent_tasks 5
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # 订阅任务创建信号
    SignalHub.subscribe("task.create.request")
    
    # 初始化 ETS 队列
    :ets.new(:task_queue, [:ordered_set, :named_table, :public])
    
    {:ok, %{running_tasks: %{}, pending_queue: []}}
  end
  
  def handle_info({:signal, %Jido.Signal{type: "task.create.request"} = signal}, state) do
    task = create_task(signal.data)
    enqueue_task(task, state)
  end
  
  defp enqueue_task(task, state) do
    if map_size(state.running_tasks) < @max_concurrent_tasks do
      dispatch_task(task)
      {:noreply, %{state | running_tasks: Map.put(state.running_tasks, task.task_id, task)}}
    else
      {:noreply, %{state | pending_queue: [task | state.pending_queue]}}
    end
  end
  
  defp dispatch_task(task) do
    {:ok, pid} = DynamicSupervisor.start_child(
      Cortex.TaskCenter.Supervisor,
      {Cortex.TaskCenter.TaskWorker, task}
    )
    
    SignalHub.emit("task.status.changed", %{
      provider: "task_center",
      event: "task",
      action: "status_changed",
      actor: "coordinator",
      origin: %{channel: "system", client: "task_center"},
      task_id: task.task_id,
      new_status: :running,
      worker_pid: inspect(pid)
    })
  end
end
```

#### TaskCenter.TaskWorker
```elixir
defmodule Cortex.TaskCenter.TaskWorker do
  use GenServer, restart: :transient
  
  def start_link(task) do
    GenServer.start_link(__MODULE__, task)
  end
  
  def init(task) do
    # 异步执行任务
    send(self(), :execute)
    {:ok, task}
  end
  
  def handle_info(:execute, task) do
    result = Cortex.TaskCenter.Executor.execute(task)
    
    SignalHub.emit("task.result.ready", %{
      provider: "task_center",
      event: "task",
      action: "result_ready",
      actor: "worker",
      origin: %{channel: "system", client: "task_worker"},
      task_id: task.task_id,
      status: result.status,
      result: result.data
    })
    
    {:stop, :normal, task}
  end
end
```

#### TaskCenter.Executor (Protocol)
```elixir
defprotocol Cortex.TaskCenter.Executor do
  @doc "执行任务并返回结果"
  def execute(task)
end

defimpl Cortex.TaskCenter.Executor, for: Map do
  def execute(%{task_type: "code_refactor"} = task) do
    # 调用 Skills 系统
    skill = Cortex.Skills.Loader.load("code_refactor")
    Cortex.Skills.Skill.execute(skill, task.params)
  end
  
  def execute(%{task_type: "agent_analysis"} = task) do
    # 调用 Agent 系统
    {:ok, agent} = Cortex.Session.Coordinator.ensure_session(task.session_id)
    Cortex.Agents.LLMAgent.chat(agent.pid, task.params.prompt)
  end
end
```

### 3.3 定时任务支持

使用 Quantum（Elixir cron 库）或自实现：

```elixir
defmodule Cortex.TaskCenter.Scheduler do
  use GenServer
  
  def init(_) do
    # 每分钟检查一次待调度任务
    :timer.send_interval(60_000, :check_scheduled_tasks)
    {:ok, %{}}
  end
  
  def handle_info(:check_scheduled_tasks, state) do
    tasks = Cortex.TaskCenter.Store.get_scheduled_tasks()
    
    Enum.each(tasks, fn task ->
      if should_run?(task) do
        SignalHub.emit("task.create.request", task_to_signal(task))
      end
    end)
    
    {:noreply, state}
  end
end
```

---

## 四、与 OpenClaw/NanoClaw 对比

| 特性 | OpenClaw | NanoClaw | Cortex TaskCenter |
|------|----------|----------|-------------------|
| **架构** | 单进程 Node.js | 容器隔离 | BEAM 多进程 |
| **通信** | 文件系统 IPC | 文件系统 IPC | 信号总线（内存） |
| **隔离** | 无 | OS 级容器 | 进程级（OTP） |
| **持久化** | SQLite | SQLite | SQLite + Tape |
| **扩展性** | Skills（文件） | Skills（文件） | Skills（热重载） |
| **多 Agent** | 单 Agent | Agent Swarms | 原生支持（SessionSupervisor） |
| **审计** | 日志 | 日志 | Tape（全量回放） |
| **容错** | 无 | 超时重启 | OTP Supervisor 树 |
| **并发** | 单线程 | 容器并发 | BEAM 调度器 |

**Cortex 优势**：
1. **BEAM 原生并发**：无需容器开销，轻量级进程隔离
2. **信号驱动**：统一通信模型，易于审计和扩展
3. **OTP 容错**：自动重启失败任务，无需手动管理
4. **Tape 审计**：全量信号持久化，支持时间旅行调试

---

## 五、实施路线图

### Phase 1: 核心基础设施（1-2 周）
- [ ] 实现 `TaskCenter.Coordinator`（任务调度）
- [ ] 实现 `TaskCenter.TaskWorker`（任务执行）
- [ ] 实现 `TaskCenter.Store`（SQLite 持久化）
- [ ] 定义任务信号规范
- [ ] 集成到 `Application` 启动树

### Phase 2: Skills 集成（1 周）
- [ ] 实现 `TaskCenter.Executor` 协议
- [ ] 支持通过 Skills 扩展任务类型
- [ ] 实现示例任务：`code_analysis`、`batch_refactor`

### Phase 3: UI 集成（1 周）
- [ ] 在 LiveView 中添加任务中心面板
- [ ] 实时显示任务状态（通过 SignalDispatcher）
- [ ] 支持手动创建/取消任务

### Phase 4: 高级特性（2 周）
- [ ] 定时任务调度（cron 支持）
- [ ] 任务依赖管理（DAG）
- [ ] 多 Agent 协作任务（Agent Swarms）
- [ ] 任务优先级和资源限制

### Phase 5: 测试与文档（1 周）
- [ ] 单元测试（任务生命周期）
- [ ] 集成测试（信号流）
- [ ] 性能测试（并发任务）
- [ ] 用户文档和 API 文档

---

## 六、风险与挑战

### 6.1 技术风险
- **并发控制**：需要精细管理任务并发数，避免资源耗尽
- **长时任务**：需要支持任务暂停/恢复（可能需要引入 Saga 模式）
- **错误恢复**：任务失败后的重试策略需要仔细设计

### 6.2 架构风险
- **信号风暴**：高频任务可能导致信号总线过载（需要背压机制）
- **状态一致性**：任务状态在 Store 和 Coordinator 之间需要保持同步

### 6.3 缓解措施
- 引入背压机制（GenStage）
- 使用 ETS 作为 Coordinator 的内存缓存
- 实现任务超时和自动清理机制

---

## 七、总结

Cortex 任务中心将采用**信号驱动 + BEAM 原生并发**的架构，充分利用 Elixir/OTP 的优势，避免引入外部依赖。相比 OpenClaw/NanoClaw 的容器隔离方案，Cortex 的进程隔离更轻量、更高效，同时通过 Tape 系统提供更强的审计能力。

核心设计遵循 Cortex V3 架构原则：
- ✅ 信号驱动通信
- ✅ BEAM 原生并发
- ✅ Tape-First 审计
- ✅ Skills 优先扩展

---

## 附录：参考资料

### A. 调研来源
- [AI Agent Task Queue Management Patterns](https://blog.logrocket.com/ai-agent-task-queues/)
- [Multi-Agent Architectures: Patterns Every AI Engineer Should Know](https://dev.to/sateesh2020/multi-agent-architectures-patterns-every-ai-engine...)
- [NanoClaw: Lightweight, Secure AI Assistant](https://lilys.ai/notes/en/openai-agent-builder-20260208/nanoclaw-lightweight-...)
- [Elixir GenServer Guide: Use Cases & Best Practices](https://bluetickconsultants.medium.com/elixir-genserver-guide-use-cases-call-...)

### B. Cortex 相关文档
- [AGENTS.md](../../AGENTS.md) - Cortex 开发指南
- [Signal Hub 实现](../../lib/cortex/signal_hub.ex)
- [Session Coordinator](../../lib/cortex/session/coordinator.ex)
- [Skills 系统](../../lib/cortex/skills/)

---

**下一步行动**：
1. 与团队评审本方案
2. 确定 Phase 1 实施细节
3. 创建对应的 BDD 场景和任务分解（使用 `taskctl` 和 `bddc`）

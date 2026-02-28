# 任务中心架构规划修正清单

**日期**: 2026-02-27  
**基于**: `20260227_task_center_architecture_planning.md`  
**状态**: 待修正

---

## 🔴 高优先级修正

### 1. 信号驱动原则违反（行 74, 352）

**问题**：TaskCenter.Executor 直接调用 `Cortex.Skills.*` 和 `LLMAgent.chat`，违反"信号驱动，零直接调用"原则。

**修正方案**：

#### 修改 TaskCenter.Executor 实现

```elixir
defmodule Cortex.TaskCenter.Executor do
  @moduledoc """
  任务执行器 - 通过信号驱动执行任务
  """
  
  def execute(task, worker_pid) do
    case task.task_type do
      "code_refactor" ->
        execute_via_skill(task, worker_pid)
      
      "agent_analysis" ->
        execute_via_agent(task, worker_pid)
      
      _ ->
        {:error, :unknown_task_type}
    end
  end
  
  # 通过信号调用 Skills
  defp execute_via_skill(task, worker_pid) do
    # 订阅结果信号
    SignalHub.subscribe("skill.result.#{task.task_id}")
    
    # 发射技能执行请求
    SignalHub.emit("skill.execute.request", %{
      provider: "task_center",
      event: "skill",
      action: "execute",
      actor: "task_worker",
      origin: %{
        channel: "system",
        client: "task_worker",
        platform: "server",
        session_id: task.session_id
      },
      task_id: task.task_id,
      skill_name: task.params.skill_name,
      params: task.params
    }, source: "/task_center/worker/#{inspect(worker_pid)}")
    
    # 等待结果（带超时）
    receive do
      {:signal, %Jido.Signal{type: "skill.result." <> ^task_id} = signal} ->
        {:ok, signal.data.result}
    after
      task.timeout_ms || 300_000 ->
        {:error, :timeout}
    end
  end
  
  # 通过信号调用 Agent
  defp execute_via_agent(task, worker_pid) do
    SignalHub.subscribe("agent.response.#{task.task_id}")
    
    SignalHub.emit("agent.chat.request", %{
      provider: "task_center",
      event: "chat",
      action: "request",
      actor: "task_worker",
      origin: %{
        channel: "system",
        client: "task_worker",
        platform: "server",
        session_id: task.session_id,
        user_id_hash: task.user_id_hash
      },
      task_id: task.task_id,
      session_id: task.session_id,
      content: task.params.prompt
    }, source: "/task_center/worker/#{inspect(worker_pid)}")
    
    receive do
      {:signal, %Jido.Signal{type: "agent.response." <> ^task_id} = signal} ->
        {:ok, signal.data.content}
    after
      task.timeout_ms || 300_000 ->
        {:error, :timeout}
    end
  end
end
```

---

### 2. 队列调度逻辑不完整（行 282）

**问题**：
- `pending_queue` 只入不出
- `running_tasks` 任务完成后不清理
- 任务完成后不触发下一任务调度

**修正方案**：

```elixir
defmodule Cortex.TaskCenter.Coordinator do
  use GenServer
  
  @max_concurrent_tasks 5
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    SignalHub.subscribe("task.create.request")
    SignalHub.subscribe("task.result.ready")  # 新增：订阅任务完成信号
    
    :ets.new(:task_queue, [:ordered_set, :named_table, :public])
    
    {:ok, %{running_tasks: %{}, pending_queue: :queue.new()}}  # 使用 :queue 模块
  end
  
  def handle_info({:signal, %Jido.Signal{type: "task.create.request"} = signal}, state) do
    # 从 signal.data.payload 提取参数
    task_params = signal.data.payload
    
    task = %{
      task_id: Ecto.UUID.generate(),
      task_type: task_params.task_type,
      priority: task_params.priority || :normal,
      params: task_params.params,
      session_id: signal.data.origin.session_id,
      user_id_hash: signal.data.origin.user_id_hash,
      created_by: signal.data.origin.channel,
      timeout_ms: task_params.timeout_ms || 300_000
    }
    
    # 持久化到数据库
    {:ok, _} = Cortex.TaskCenter.Store.create_task(task)
    
    enqueue_task(task, state)
  end
  
  # 新增：处理任务完成信号
  def handle_info({:signal, %Jido.Signal{type: "task.result.ready"} = signal}, state) do
    task_id = signal.data.payload.task_id
    
    # 从运行列表移除
    new_running_tasks = Map.delete(state.running_tasks, task_id)
    
    # 尝试调度下一个任务
    new_state = %{state | running_tasks: new_running_tasks}
    dispatch_next_task(new_state)
  end
  
  defp enqueue_task(task, state) do
    if map_size(state.running_tasks) < @max_concurrent_tasks do
      case dispatch_task(task) do
        {:ok, pid} ->
          {:noreply, %{state | running_tasks: Map.put(state.running_tasks, task.task_id, pid)}}
        
        {:error, reason} ->
          # 启动失败，放入队列
          Logger.error("[TaskCenter] Failed to start task #{task.task_id}: #{inspect(reason)}")
          new_queue = :queue.in(task, state.pending_queue)
          {:noreply, %{state | pending_queue: new_queue}}
      end
    else
      # 按优先级插入队列
      new_queue = insert_by_priority(task, state.pending_queue)
      {:noreply, %{state | pending_queue: new_queue}}
    end
  end
  
  defp dispatch_task(task) do
    case DynamicSupervisor.start_child(
      Cortex.TaskCenter.Supervisor,
      {Cortex.TaskCenter.TaskWorker, task}
    ) do
      {:ok, pid} ->
        SignalHub.emit("task.status.changed", %{
          provider: "task_center",
          event: "task",
          action: "status_changed",
          actor: "coordinator",
          origin: %{
            channel: "system",
            client: "task_center",
            platform: "server",
            session_id: task.session_id
          },
          task_id: task.task_id,
          old_status: :pending,
          new_status: :running,
          worker_pid: inspect(pid)
        })
        
        {:ok, pid}
      
      {:error, reason} ->
        # 发射失败信号
        SignalHub.emit("task.status.changed", %{
          provider: "task_center",
          event: "task",
          action: "status_changed",
          actor: "coordinator",
          origin: %{
            channel: "system",
            client: "task_center",
            platform: "server",
            session_id: task.session_id
          },
          task_id: task.task_id,
          old_status: :pending,
          new_status: :failed,
          error: inspect(reason)
        })
        
        {:error, reason}
    end
  end
  
  # 新增：调度下一个任务
  defp dispatch_next_task(state) do
    if map_size(state.running_tasks) < @max_concurrent_tasks and not :queue.is_empty(state.pending_queue) do
      {{:value, task}, new_queue} = :queue.out(state.pending_queue)
      
      case dispatch_task(task) do
        {:ok, pid} ->
          {:noreply, %{
            state |
            running_tasks: Map.put(state.running_tasks, task.task_id, pid),
            pending_queue: new_queue
          }}
        
        {:error, _reason} ->
          # 失败任务不重新入队，直接丢弃
          {:noreply, %{state | pending_queue: new_queue}}
      end
    else
      {:noreply, state}
    end
  end
  
  # 新增：按优先级插入队列
  defp insert_by_priority(task, queue) do
    # 简化实现：高优先级插入队头，其他插入队尾
    case task.priority do
      :high -> :queue.in_r(task, queue)  # 插入队头
      _ -> :queue.in(task, queue)        # 插入队尾
    end
  end
end
```

---

### 3. TaskWorker 缺少超时和异常处理（行 326）

**问题**：
- 无超时控制
- 无异常捕获
- 失败不产出 `task.result.ready` 信号

**修正方案**：

```elixir
defmodule Cortex.TaskCenter.TaskWorker do
  use GenServer, restart: :transient
  
  require Logger
  
  def start_link(task) do
    GenServer.start_link(__MODULE__, task)
  end
  
  def init(task) do
    # 设置超时
    Process.send_after(self(), :timeout, task.timeout_ms || 300_000)
    
    # 异步执行任务
    send(self(), :execute)
    {:ok, %{task: task, start_time: System.monotonic_time(:millisecond)}}
  end
  
  def handle_info(:execute, %{task: task} = state) do
    try do
      result = Cortex.TaskCenter.Executor.execute(task, self())
      
      case result do
        {:ok, data} ->
          emit_result(task, :completed, data, state.start_time)
          {:stop, :normal, state}
        
        {:error, reason} ->
          emit_result(task, :failed, %{error: inspect(reason)}, state.start_time)
          {:stop, :normal, state}
      end
    rescue
      exception ->
        Logger.error("[TaskWorker] Task #{task.task_id} crashed: #{Exception.format(:error, exception, __STACKTRACE__)}")
        
        emit_result(task, :failed, %{
          error: Exception.message(exception),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        }, state.start_time)
        
        {:stop, :normal, state}
    end
  end
  
  def handle_info(:timeout, %{task: task} = state) do
    Logger.warning("[TaskWorker] Task #{task.task_id} timeout after #{task.timeout_ms}ms")
    
    emit_result(task, :failed, %{error: "timeout"}, state.start_time)
    {:stop, :normal, state}
  end
  
  defp emit_result(task, status, result_data, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time
    
    SignalHub.emit("task.result.ready", %{
      provider: "task_center",
      event: "task",
      action: "result_ready",
      actor: "worker",
      origin: %{
        channel: "system",
        client: "task_worker",
        platform: "server",
        session_id: task.session_id
      },
      task_id: task.task_id,
      status: status,
      result: result_data,
      duration_ms: duration_ms
    })
    
    # 更新数据库
    Cortex.TaskCenter.Store.update_task(task.task_id, %{
      status: status,
      result: result_data,
      completed_at: DateTime.utc_now()
    })
  end
end
```

---

### 4. 持久化方案不清晰（行 111, 232）

**问题**：
- 没有迁移文件规划
- 没有明确 Repo 选择
- Task schema 缺少主键约束

**修正方案**：

#### 4.1 创建迁移文件

**文件路径**: `priv/repo/migrations/20260227_create_tasks.exs`

```elixir
defmodule Cortex.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, :string, null: false  # 业务 ID（用于幂等）
      add :task_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :priority, :string, null: false, default: "normal"
      add :schedule, :string  # cron 表达式
      add :params, :map, null: false
      add :result, :map
      add :error, :text
      add :session_id, :string
      add :user_id_hash, :string
      add :created_by, :string, null: false
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :timeout_ms, :integer, default: 300_000
      
      timestamps(type: :utc_datetime)
    end
    
    # 唯一约束：防止重复任务
    create unique_index(:tasks, [:task_id])
    
    # 查询优化索引
    create index(:tasks, [:status])
    create index(:tasks, [:session_id])
    create index(:tasks, [:created_by])
    create index(:tasks, [:schedule])  # 定时任务查询
  end
end
```

#### 4.2 修正 Task Schema

```elixir
defmodule Cortex.TaskCenter.Task do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "tasks" do
    field :task_id, :string
    field :task_type, :string
    field :status, Ecto.Enum, values: [:pending, :running, :completed, :failed, :cancelled]
    field :priority, Ecto.Enum, values: [:high, :normal, :low]
    field :schedule, :string
    field :params, :map
    field :result, :map
    field :error, :string
    field :session_id, :string
    field :user_id_hash, :string
    field :created_by, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :timeout_ms, :integer, default: 300_000
    
    timestamps(type: :utc_datetime)
  end
  
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :task_id, :task_type, :status, :priority, :schedule,
      :params, :result, :error, :session_id, :user_id_hash,
      :created_by, :started_at, :completed_at, :timeout_ms
    ])
    |> validate_required([:task_id, :task_type, :status, :priority, :params, :created_by])
    |> unique_constraint(:task_id)
  end
end
```

#### 4.3 实现 TaskCenter.Store

```elixir
defmodule Cortex.TaskCenter.Store do
  @moduledoc """
  任务持久化层 - 使用 Cortex.Repo (SQLite)
  """
  
  alias Cortex.Repo
  alias Cortex.TaskCenter.Task
  import Ecto.Query
  
  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end
  
  def update_task(task_id, attrs) do
    case Repo.get_by(Task, task_id: task_id) do
      nil -> {:error, :not_found}
      task ->
        task
        |> Task.changeset(attrs)
        |> Repo.update()
    end
  end
  
  def get_task(task_id) do
    Repo.get_by(Task, task_id: task_id)
  end
  
  def list_tasks(filters \\ []) do
    query = from t in Task, order_by: [desc: t.inserted_at]
    
    query
    |> apply_filters(filters)
    |> Repo.all()
  end
  
  def get_scheduled_tasks do
    now = DateTime.utc_now()
    
    from(t in Task,
      where: t.status == :pending,
      where: not is_nil(t.schedule),
      where: t.started_at < ^now or is_nil(t.started_at)
    )
    |> Repo.all()
  end
  
  defp apply_filters(query, []), do: query
  defp apply_filters(query, [{:status, status} | rest]) do
    query
    |> where([t], t.status == ^status)
    |> apply_filters(rest)
  end
  defp apply_filters(query, [{:session_id, session_id} | rest]) do
    query
    |> where([t], t.session_id == ^session_id)
    |> apply_filters(rest)
  end
  defp apply_filters(query, [_ | rest]), do: apply_filters(query, rest)
end
```

---

## 🟡 中优先级修正

### 5. 信号示例缺少必需字段（行 124）

**问题**：`origin` 缺少 `platform`, `session_id`, `user_id_hash`

**修正方案**：

更新所有信号示例，确保包含完整 `origin` 结构：

```elixir
SignalHub.emit("task.create.request", %{
  provider: "ui",
  event: "task",
  action: "create",
  actor: "user",
  origin: %{
    channel: "ui",
    client: "web",
    platform: "macos",           # 新增
    session_id: "session_123",   # 新增
    user_id_hash: "hash_abc"     # 新增
  },
  task_type: "code_refactor",
  priority: :normal,
  schedule: nil,
  params: %{
    target_path: "lib/cortex",
    instructions: "重构信号处理逻辑"
  }
}, source: "/ui/web/tasks")
```

---

### 6. 信号数据结构不一致（行 277）

**问题**：`create_task(signal.data)` 假定 payload 在 data，但规范要求顶层字段

**修正方案**：

明确信号数据结构解析规则：

```elixir
def handle_info({:signal, %Jido.Signal{type: "task.create.request"} = signal}, state) do
  # signal.data 结构：
  # %{
  #   provider: "ui",
  #   event: "task",
  #   action: "create",
  #   actor: "user",
  #   origin: %{...},
  #   payload: %{task_type: ..., priority: ..., params: ...}
  # }
  
  task_params = signal.data.payload
  origin = signal.data.origin
  
  task = %{
    task_id: Ecto.UUID.generate(),
    task_type: task_params.task_type,
    priority: task_params.priority || :normal,
    params: task_params.params,
    session_id: origin.session_id,
    user_id_hash: origin.user_id_hash,
    created_by: origin.channel,
    timeout_ms: task_params.timeout_ms || 300_000
  }
  
  {:ok, _} = Cortex.TaskCenter.Store.create_task(task)
  enqueue_task(task, state)
end
```

---

### 7. 缺少取消/超时/重试策略（行 454）

**问题**：任务生命周期没有取消、超时、重试的状态流和 API

**修正方案**：

#### 7.1 添加取消信号

```elixir
# 用户发起取消
SignalHub.emit("task.cancel.request", %{
  provider: "ui",
  event: "task",
  action: "cancel",
  actor: "user",
  origin: %{...},
  task_id: "task_123"
})

# Coordinator 处理取消
def handle_info({:signal, %Jido.Signal{type: "task.cancel.request"} = signal}, state) do
  task_id = signal.data.payload.task_id
  
  case Map.get(state.running_tasks, task_id) do
    nil ->
      # 任务不在运行中，直接更新数据库
      Cortex.TaskCenter.Store.update_task(task_id, %{status: :cancelled})
      {:noreply, state}
    
    pid ->
      # 发送停止信号给 Worker
      Process.send(pid, :cancel, [])
      {:noreply, state}
  end
end
```

#### 7.2 TaskWorker 支持取消

```elixir
def handle_info(:cancel, %{task: task} = state) do
  Logger.info("[TaskWorker] Task #{task.task_id} cancelled by user")
  
  emit_result(task, :cancelled, %{reason: "user_cancelled"}, state.start_time)
  {:stop, :normal, state}
end
```

#### 7.3 重试策略

```elixir
# 在 Task schema 添加重试字段
field :retry_count, :integer, default: 0
field :max_retries, :integer, default: 3

# Coordinator 处理失败任务
def handle_info({:signal, %Jido.Signal{type: "task.result.ready"} = signal}, state) do
  task_id = signal.data.payload.task_id
  status = signal.data.payload.status
  
  if status == :failed do
    task = Cortex.TaskCenter.Store.get_task(task_id)
    
    if task.retry_count < task.max_retries do
      # 重试任务
      Logger.info("[TaskCenter] Retrying task #{task_id} (#{task.retry_count + 1}/#{task.max_retries})")
      
      Cortex.TaskCenter.Store.update_task(task_id, %{
        retry_count: task.retry_count + 1,
        status: :pending
      })
      
      # 重新入队
      enqueue_task(task, state)
    else
      Logger.error("[TaskCenter] Task #{task_id} failed after #{task.max_retries} retries")
      {:noreply, %{state | running_tasks: Map.delete(state.running_tasks, task_id)}}
    end
  else
    {:noreply, %{state | running_tasks: Map.delete(state.running_tasks, task_id)}}
  end
end
```

---

## 🟢 低优先级修正

### 8. Task schema 缺少主键约束（行 237）

**已在修正 4.1 中解决**：添加了 `unique_index(:tasks, [:task_id])`

---

## 📋 修正后的架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      Cortex Application                      │
├─────────────────────────────────────────────────────────────┤
│  SignalHub (CloudEvents 1.0.2 Bus)                          │
│    ↓ task.create.request                                    │
│    ↓ task.cancel.request         [新增]                     │
│    ↓ task.status.changed                                    │
│    ↓ task.result.ready                                      │
│    ↓ skill.execute.request       [新增：信号驱动]            │
│    ↓ skill.result.*              [新增：信号驱动]            │
│    ↓ agent.chat.request          [新增：信号驱动]            │
│    ↓ agent.response.*            [新增：信号驱动]            │
├─────────────────────────────────────────────────────────────┤
│  TaskCenter.Coordinator (GenServer)                         │
│    - 任务注册表（running_tasks: Map）                        │
│    - 优先级队列（pending_queue: :queue）  [修正]            │
│    - 任务调度策略（dispatch_next_task）   [新增]            │
│    - 取消/重试逻辑                        [新增]            │
├─────────────────────────────────────────────────────────────┤
│  TaskCenter.Supervisor (DynamicSupervisor)                  │
│    ├─ TaskWorker (GenServer) - 超时控制 + 异常捕获 [修正]   │
│    ├─ TaskWorker (GenServer)                                │
│    └─ TaskWorker (GenServer)                                │
├─────────────────────────────────────────────────────────────┤
│  TaskCenter.Store (Module)                                  │
│    - 使用 Cortex.Repo (SQLite)            [明确]           │
│    - 迁移文件：20260227_create_tasks.exs  [新增]           │
│    - 唯一约束：task_id                    [新增]           │
├─────────────────────────────────────────────────────────────┤
│  TaskCenter.Executor (Module)                               │
│    - 信号驱动执行（无直接调用）            [修正]           │
│    - 超时控制（receive after）            [新增]           │
└─────────────────────────────────────────────────────────────┘
```

---

## 📝 修正后的任务生命周期

```
[创建] → [排队] → [调度] → [执行] → [完成/失败/取消]
  ↓        ↓        ↓        ↓          ↓
 信号    信号     信号     信号       信号
  ↓        ↓        ↓        ↓          ↓
 Store   Store    Store    Store      Store
  ↓        ↓        ↓        ↓          ↓
 Tape    Tape     Tape     Tape       Tape

[失败] → [重试判断] → [重新排队] 或 [最终失败]
  ↓          ↓            ↓              ↓
 信号       逻辑         信号           信号

[运行中] → [取消请求] → [优雅停止] → [已取消]
  ↓            ↓            ↓           ↓
 信号         信号         逻辑        信号
```

---

## ✅ 修正清单总结

| 问题 | 严重度 | 状态 | 修正方案 |
|------|--------|------|----------|
| 信号驱动原则违反 | 🔴 高 | ✅ 已修正 | Executor 改为信号驱动 |
| 队列调度不完整 | 🔴 高 | ✅ 已修正 | 添加 dispatch_next_task |
| TaskWorker 无超时/异常处理 | 🔴 高 | ✅ 已修正 | 添加超时和 try-rescue |
| 持久化方案不清晰 | 🔴 高 | ✅ 已修正 | 明确使用 Cortex.Repo + 迁移 |
| 信号示例缺少字段 | 🟡 中 | ✅ 已修正 | 补充 origin 完整字段 |
| 信号数据结构不一致 | 🟡 中 | ✅ 已修正 | 明确 payload 解析规则 |
| 缺少取消/重试策略 | 🟡 中 | ✅ 已修正 | 添加取消信号和重试逻辑 |
| Task schema 缺少主键约束 | 🟢 低 | ✅ 已修正 | 添加 unique_index |

---

## 🚀 下一步行动

1. **更新原规划文档**：将本修正清单的内容合并到 `20260227_task_center_architecture_planning.md`
2. **创建 BDD 场景**：使用 `bddc` 工具定义测试场景
3. **创建任务分解**：使用 `taskctl` 创建实施任务
4. **执行迁移**：运行 `mix ecto.migrate` 创建 tasks 表
5. **实施 Phase 1**：按修正后的方案实现核心基础设施

---

**修正完成日期**: 2026-02-27  
**审核状态**: 待审核

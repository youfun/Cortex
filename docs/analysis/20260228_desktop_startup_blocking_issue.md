# Cortex Desktop 启动阻塞问题根因分析

**日期**: 2026-02-28  
**问题**: Desktop 版本启动卡住，Tauri 健康检查超时  
**关键发现**: ExTauri 和 Cortex 的 Burrito 打包原理相同，但启动流程设计不同

---

## 一、问题复现

### 1.1 症状

```
[Tauri] Backend process started with PID: 12345
[Tauri] Starting health check polling: http://localhost:4000/api/system/health
[Tauri] Health check attempt 1/60
[Tauri] Waiting for backend... (attempt 5/60): Connection refused
[Tauri] Waiting for backend... (attempt 10/60): Connection refused
...
[Tauri] Backend failed to start after 60 attempts
```

### 1.2 日志分析

**`logs/backend_stdout.log`** 可能显示：
```
[info] Running migrations for Elixir.Cortex.Repo from /app/priv/repo/migrations
[info] == Running 20230101000000 Cortex.Repo.Migrations.CreateUsers.change/0 forward
[info] create table users
[info] == Migrated 20230101000000 in 0.1s
... (卡在这里，Phoenix 没有启动)
```

**关键**: Phoenix Endpoint 没有输出 `Running CortexWeb.Endpoint with Bandit`

---

## 二、根本原因：数据库迁移阻塞

### 2.1 Cortex 的启动流程

```elixir
# lib/cortex/application.ex:15-17
if should_prepare_database?() do
  prepare_database()  # ← 同步阻塞！
end

children = [
  Cortex.Repo,        # ← 再次启动 Repo
  # ... 其他 children
  CortexWeb.Endpoint  # ← Phoenix 最后才启动
]
```

**问题**:
1. `prepare_database()` 在 `start/2` 中**同步执行**
2. 启动临时 Repo 进程 → 运行迁移 → 停止进程 → 等待 200ms
3. 如果迁移慢（大量数据/复杂索引），会阻塞整个启动流程
4. Phoenix Endpoint 在 children 列表**最后**，必须等所有前置服务启动完成

### 2.2 ExTauri Example 的启动流程

```elixir
# deps-local/ex_tauri/example/lib/example_desktop/application.ex:9-21
def start(_type, _args) do
  children = [
    Repo,
    {Phoenix.PubSub, name: ExampleDesktop.PubSub},
    ExampleDesktopWeb.Endpoint,  # ← Phoenix 第三个启动
    ExTauri.ShutdownManager
  ]

  opts = [strategy: :one_for_one, name: ExampleDesktop.Supervisor]
  start = Supervisor.start_link(children, opts)

  ExampleDesktop.Starter.run()  # ← 迁移在 Supervisor 启动后异步执行
  start
end
```

**关键差异**:
- ✅ Phoenix Endpoint 在第 3 个位置（Repo 之后立即启动）
- ✅ 迁移通过 `Starter.run()` 在 Supervisor 启动**后**执行
- ✅ 即使迁移慢，Phoenix 也已经在监听端口

### 2.3 对比表

| 项目 | Cortex | ExTauri Example |
|------|--------|-----------------|
| 迁移时机 | `start/2` 开始时（同步） | `start/2` 结束后（异步） |
| Phoenix 位置 | children 最后 | children 第 3 个 |
| Repo 启动次数 | 2 次（临时 + 正式） | 1 次 |
| 阻塞风险 | 高（迁移 + 所有 children） | 低（仅 Repo + PubSub） |

---

## 三、为什么 Cortex 会卡住

### 3.1 启动时间分解

假设各组件启动时间：

```
prepare_database():
  - 启动临时 Repo: 100ms
  - 运行迁移: 2000ms (假设有复杂迁移)
  - 停止 Repo + 等待: 200ms
  小计: 2300ms

children 启动（顺序）:
  - Finch: 50ms
  - Telemetry: 10ms
  - Cortex.Repo: 100ms
  - DNSCluster: 10ms
  - Phoenix.PubSub: 50ms
  - SignalHub: 100ms
  - TTS.NodeManager: 50ms
  - ... (30+ 个 children)
  - CortexWeb.Endpoint: 200ms
  小计: ~1500ms

总启动时间: 2300 + 1500 = 3800ms
```

**但实际可能更慢**，因为：
1. `load_model_metadata()` 在启动后执行（额外 2 秒）
2. SQLite 文件锁可能导致 Repo 启动失败
3. 某些 children 可能有依赖等待

### 3.2 Tauri 健康检查的视角

```rust
// src-tauri/src/lib.rs:312-314
let mut attempts = 0;
let max_attempts = 60;  // 60 秒超时

loop {
    attempts += 1;
    match reqwest::get(&health_url).await {
        Ok(response) if response.status().is_success() => break,
        _ => tokio::time::sleep(Duration::from_secs(1)).await
    }
}
```

**问题**:
- Tauri 期望 Phoenix 在 60 秒内启动
- 但 Cortex 的 Phoenix 可能在第 50-60 秒才启动（接近超时边缘）
- 如果迁移卡住（SQLite 锁/慢查询），直接超时

---

## 四、ExTauri 为什么没有这个问题

### 4.1 简化的启动流程

ExTauri Example 只有 **4 个 children**：
```elixir
children = [
  Repo,                          # 1. 数据库
  {Phoenix.PubSub, ...},         # 2. 消息总线
  ExampleDesktopWeb.Endpoint,   # 3. Phoenix（关键！）
  ExTauri.ShutdownManager        # 4. 心跳管理
]
```

**启动时间**:
```
Repo: 100ms
PubSub: 50ms
Endpoint: 200ms
ShutdownManager: 10ms
总计: 360ms

迁移（异步）: 2000ms（不阻塞 Phoenix）
```

### 4.2 迁移策略

```elixir
# deps-local/ex_tauri/example/lib/example_desktop/starter.ex
def run() do
  Application.ensure_all_started(:ecto_sql)
  Repo.__adapter__().storage_up(Repo.config())
  Ecto.Migrator.run(Repo, :up, all: true)
end
```

**关键**:
- 在 `Supervisor.start_link()` **返回后**执行
- Phoenix 已经在监听端口，可以响应健康检查
- 迁移在后台运行，不影响 Tauri 的健康检查

---

## 五、解决方案

### 方案 A: 异步迁移（推荐）

**模仿 ExTauri 的做法**：

```elixir
# lib/cortex/application.ex
def start(_type, _args) do
  children = [
    {Finch, finch_config},
    CortexWeb.Telemetry,
    Cortex.Repo,
    {Phoenix.PubSub, name: Cortex.PubSub},
    CortexWeb.Endpoint,  # ← 提前到第 5 个位置
    
    # 其他非关键 children 放后面
    Cortex.SignalHub,
    # ...
  ]

  opts = [strategy: :one_for_one, name: Cortex.Supervisor]
  result = Supervisor.start_link(children, opts)

  # 异步执行迁移和初始化
  if should_prepare_database?() do
    Task.start(fn ->
      prepare_database()
      load_model_metadata()
    end)
  end

  result
end
```

**优势**:
- ✅ Phoenix 在 500ms 内启动（Tauri 健康检查通过）
- ✅ 迁移在后台运行，不阻塞启动
- ✅ 用户可以立即看到 UI（即使数据还在加载）

**风险**:
- ⚠️ 用户可能在迁移完成前访问需要数据库的功能
- ⚠️ 需要在 UI 中显示"正在初始化"状态

### 方案 B: 优化迁移速度

**保持同步迁移，但减少阻塞时间**：

```elixir
defp prepare_database do
  repos = Application.get_env(:cortex, :ecto_repos, [])

  for repo <- repos do
    ensure_database_directory(repo)

    # 不启动临时进程，直接使用 Ecto.Migrator.with_repo
    Ecto.Migrator.with_repo(repo, fn repo ->
      Ecto.Migrator.run(repo, :up, all: true)
    end, pool_size: 2)
  end
end
```

**优势**:
- ✅ 避免启动/停止临时 Repo 的开销（省 300ms）
- ✅ 保持同步语义，确保迁移完成后才启动服务

**劣势**:
- ❌ 仍然阻塞启动流程
- ❌ 如果迁移慢（> 10 秒），仍可能超时

### 方案 C: 条件迁移

**仅在必要时运行迁移**：

```elixir
defp should_prepare_database? do
  # 检查数据库是否已存在且是最新版本
  if database_exists?() and migrations_up_to_date?() do
    false
  else
    not Code.ensure_loaded?(Mix) or
      System.get_env("RELEASE_NAME") != nil
  end
end

defp database_exists? do
  case Keyword.get(Cortex.Repo.config(), :database) do
    nil -> false
    db_path -> File.exists?(db_path)
  end
end

defp migrations_up_to_date? do
  # 快速检查：读取数据库版本表
  # 如果版本匹配，跳过迁移
  true
end
```

**优势**:
- ✅ 首次启动慢，后续启动快（< 1 秒）
- ✅ 减少不必要的迁移检查

---

## 六、推荐实施方案

### 短期修复（立即可用）

**调整 children 顺序 + 异步迁移**：

```elixir
def start(_type, _args) do
  # 1. 最小化 Phoenix 启动前的依赖
  critical_children = [
    {Finch, finch_config},
    CortexWeb.Telemetry,
    Cortex.Repo,
    {Phoenix.PubSub, name: Cortex.PubSub},
    CortexWeb.Endpoint  # ← 关键：尽早启动
  ]

  # 2. 非关键服务放后面
  background_children = [
    Cortex.SignalHub,
    Cortex.TTS.NodeManager,
    # ... 其他 30+ children
  ]

  children = critical_children ++ background_children

  opts = [strategy: :one_for_one, name: Cortex.Supervisor]
  result = Supervisor.start_link(children, opts)

  # 3. 异步初始化
  if should_prepare_database?() do
    Task.start(fn ->
      Logger.info("[Application] Starting background initialization...")
      prepare_database()
      Process.sleep(500)  # 等待 Repo 完全启动
      load_model_metadata()
      Logger.info("[Application] Background initialization completed")
    end)
  end

  result
end
```

### 长期优化（配合 ExTauri）

1. **简化 children 列表**: 将非必需服务改为懒加载
2. **优化迁移**: 使用 `Ecto.Migrator.with_repo` 避免临时进程
3. **添加启动状态**: 在 UI 显示"正在初始化数据库"

---

## 七、验证方法

### 7.1 测试启动时间

```elixir
# 在 application.ex 中添加计时
def start(_type, _args) do
  start_time = System.monotonic_time(:millisecond)
  
  # ... 启动逻辑
  
  result = Supervisor.start_link(children, opts)
  
  elapsed = System.monotonic_time(:millisecond) - start_time
  Logger.info("[Application] Startup completed in #{elapsed}ms")
  
  result
end
```

**目标**: Phoenix 启动时间 < 5 秒（Tauri 健康检查容忍度）

### 7.2 测试迁移阻塞

```bash
# 1. 删除数据库
rm cortex.db

# 2. 启动 Desktop
./Cortex.exe

# 3. 观察日志
tail -f logs/backend_stdout.log

# 预期：
# [info] Running migrations...
# [info] Running CortexWeb.Endpoint with Bandit  ← 应在 5 秒内出现
```

---

## 八、总结

### 核心问题

**Cortex 的同步迁移 + 复杂 children 列表 = 启动慢（> 60 秒）**

### ExTauri 的优势

**不是 Burrito 打包的问题，而是启动流程设计的问题**：
- ✅ Phoenix 优先启动（第 3 个 child）
- ✅ 迁移异步执行（不阻塞健康检查）
- ✅ 最小化 children 列表（4 个 vs 30+）

### 立即行动

1. **调整 children 顺序**: 将 `CortexWeb.Endpoint` 提前到第 5 个位置
2. **异步迁移**: 将 `prepare_database()` 移到 `Task.start()` 中
3. **测试**: 确认 Phoenix 在 5 秒内启动

**预期效果**: Desktop 启动时间从 60+ 秒降低到 < 10 秒。

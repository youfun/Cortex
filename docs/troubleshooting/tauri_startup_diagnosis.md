# Tauri Desktop 启动失败诊断指南

## 问题现象

- ✅ Tauri 日志显示正常启动
- ✅ 数据库迁移成功
- ✅ Backend 进程已启动（有 PID）
- ❌ GUI 窗口没有打开
- ❌ Health check 可能超时

## 诊断步骤

### 1. 检查 Backend 日志

Backend 的 stdout/stderr 应该输出到日志文件。根据 `src-tauri/src/lib.rs:215-216`：

```rust
let backend_stdout_log = log_dir.join("backend_stdout.log");
let backend_stderr_log = log_dir.join("backend_stderr.log");
```

**日志位置**（Windows）：
- `<exe_dir>/logs/backend_stdout.log`
- `<exe_dir>/logs/backend_stderr.log`
- `<exe_dir>/logs/tauri.log`

**检查内容**：
```bash
# 查看 Backend 是否真的启动了 Phoenix
cat logs/backend_stdout.log | grep -i "phoenix\|running\|started"

# 查看是否有错误
cat logs/backend_stderr.log
```

### 2. 检查 Phoenix 是否监听端口

Backend 启动后，Phoenix 应该输出类似：

```
[info] Running CortexWeb.Endpoint with Bandit 1.x.x at 0.0.0.0:4000 (http)
```

**如果没有这行日志**，说明 Phoenix 服务器没有启动。

### 3. 检查环境变量

确认 Tauri 传递的环境变量是否生效：

```rust
// src-tauri/src/lib.rs:237-241
.env("PORT", port.to_string())
.env("MIX_ENV", "prod")
.env("RELEASE_NAME", "cortex")
.env("PHX_SERVER", "true")      // ← 关键！
.env("DESKTOP_MODE", "true")
```

在 Backend 日志中应该能看到这些变量的效果。

### 4. 手动测试 Backend

**方式 1：直接运行 Backend 二进制**

```bash
# Windows (PowerShell)
$env:PHX_SERVER="true"
$env:PORT="4000"
$env:MIX_ENV="prod"
$env:DESKTOP_MODE="true"
.\burrito_out\cortex_windows.exe

# Linux/WSL
PHX_SERVER=true PORT=4000 MIX_ENV=prod DESKTOP_MODE=true ./burrito_out/cortex_linux
```

然后在浏览器访问 `http://localhost:4000/api/system/health`，应该返回：

```json
{"status":"ok","timestamp":"2026-02-27T..."}
```

**方式 2：使用 curl 测试**

```bash
curl http://localhost:4000/api/system/health
```

### 5. 检查 Health Check 超时

Tauri 会尝试 60 次（每次间隔 1 秒）：

```rust
// src-tauri/src/lib.rs:313-314
let mut attempts = 0;
let max_attempts = 60;
```

如果 Backend 启动慢，可能需要增加超时时间。

## 常见问题

### 问题 0：Mix.env() 在 Release 中不可用（已修复）

**症状**：Backend 启动后立即报错

```
** (UndefinedFunctionError) function Mix.env/0 is undefined (module Mix is not available)
    Mix.env()
    (cortex 0.1.40) lib/cortex_web/router.ex:59: CortexWeb.Router.check_auth/2
```

**原因**：在编译后的二进制文件（release/burrito）中，Mix 模块不可用，但 `lib/cortex_web/router.ex:59` 调用了 `Mix.env()`

**解决方案**（已在 2026-03-01 修复）：

将 `lib/cortex_web/router.ex` 中的 `Mix.env()` 替换为 `Application.get_env(:cortex, :env)`：

```elixir
# 修改前（错误）
cond do
  Mix.env() == :dev ->
    conn
  ...
end

# 修改后（正确）
cond do
  Application.get_env(:cortex, :env) == :dev ->
    conn
  ...
end
```

配置文件 `config/config.exs` 中已有：
```elixir
config :cortex, env: config_env()
```

**验证**：重新构建后，使用 `export PHX_SERVER="true"` 启动二进制，应该不再报错。

### 问题 1：Phoenix 服务器没有启动

**症状**：Backend 进程运行但没有监听端口

**原因**：`PHX_SERVER` 环境变量未生效

**解决方案**：

修改 `config/runtime.exs`，强制在 Desktop 模式下启动服务器：

```elixir
# config/runtime.exs (第 19-21 行)
if System.get_env("PHX_SERVER") || System.get_env("DESKTOP_MODE") do
  config :cortex, CortexWeb.Endpoint, server: true
end
```

### 问题 2：端口被占用

**症状**：Backend 启动失败，日志显示端口冲突

**解决方案**：

Tauri 使用随机端口（`src-tauri/src/lib.rs:189-194`）：

```rust
fn find_available_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .map(|a| a.port())
        .unwrap_or(4000)
}
```

如果仍然冲突，检查是否有其他 Cortex 实例在运行。

### 问题 3：数据库锁定

**症状**：Backend 启动但卡在数据库操作

**解决方案**：

检查 SQLite 数据库文件是否被其他进程锁定：

```bash
# Windows
tasklist | findstr cortex

# Linux
ps aux | grep cortex
```

杀死所有 Cortex 进程后重试。

### 问题 4：Health Endpoint 路由问题

**症状**：Backend 启动但 `/api/system/health` 返回 404

**检查**：

确认 `lib/cortex_web/router.ex` 中有：

```elixir
scope "/api/system", CortexWeb do
  pipe_through :api
  get "/health", SystemController, :health
  post "/shutdown", SystemController, :shutdown
end
```

确认 `lib/cortex_web/controllers/system_controller.ex` 中有：

```elixir
def health(conn, _params) do
  json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
end
```

## 调试增强

### 增加日志输出

修改 `src-tauri/src/lib.rs`，在 health check 循环中增加更详细的日志：

```rust
// 在第 332 行附近
match reqwest::get(&health_url).await {
    Ok(response) if response.status().is_success() => {
        // 成功
    }
    Ok(response) => {
        // 添加响应体日志
        let body = response.text().await.unwrap_or_default();
        log_to_file(log_file, &format!("Response body: {}", body));
    }
    Err(e) => {
        // 添加详细错误信息
        log_to_file(log_file, &format!("Connection error: {:?}", e));
    }
}
```

### 减少 Health Check 间隔

如果 Backend 启动很快，可以减少间隔：

```rust
// src-tauri/src/lib.rs:347, 358
tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;  // 从 1000 改为 500
```

## GitHub Actions 构建检查

确认 GitHub Actions 构建成功：

1. 检查 `build-desktop` job 是否成功
2. 检查 "Place sidecar binary for Tauri" 步骤是否执行
3. 下载 artifact 并验证文件结构：

```
cortex-desktop-Windows x86_64/
├── msi/
│   └── Cortex_0.1.39_x64_en-US.msi
└── nsis/
    └── Cortex_0.1.39_x64-setup.exe
```

## 下一步

1. **收集日志**：找到 `logs/backend_stdout.log` 和 `logs/tauri.log`
2. **手动测试**：直接运行 Backend 二进制，确认 Phoenix 启动
3. **检查端口**：确认 Health endpoint 可访问
4. **修改配置**：如果需要，修改 `config/runtime.exs` 强制启动服务器

---

**需要帮助？** 提供以下信息：
- `logs/backend_stdout.log` 的内容
- `logs/backend_stderr.log` 的内容
- `logs/tauri.log` 的最后 100 行
- 手动运行 Backend 的输出

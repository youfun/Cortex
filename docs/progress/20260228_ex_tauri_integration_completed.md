# ExTauri 集成完成总结

**日期**: 2026-02-28  
**状态**: ✅ 集成完成，待测试

---

## 一、已完成的修改

### 1.1 mix.exs

**添加双 release 配置**:
```elixir
def releases do
  [
    cortex: [...]   # Server 版本（纯后端）
    desktop: [...]  # Desktop 版本（ExTauri 集成）
  ]
end
```

**添加 ExTauri 依赖**:
```elixir
{:ex_tauri, path: "deps-local/ex_tauri"}
```

### 1.2 lib/cortex/application.ex

**关键优化**:
1. **Phoenix 提前启动**: 从第 30+ 位置提前到第 5 位
2. **异步迁移**: `prepare_database()` 改为 `Task.start()` 异步执行
3. **条件启动 ShutdownManager**: 仅在 `DESKTOP_MODE=true` 时启动

**启动流程对比**:
```
旧流程:
prepare_database() (同步 2-3 秒)
→ 30+ children 顺序启动
→ Phoenix Endpoint (最后)
总计: 3-5 秒

新流程:
critical_children (5 个)
→ Phoenix Endpoint (第 5 个)
→ background_children (25 个)
→ Task.start(prepare_database)  # 异步
总计: < 1 秒 (Phoenix 启动)
```

### 1.3 src-tauri/src/lib.rs

**完全重写**，基于 ExTauri Example:
- ❌ 删除 HTTP 健康检查轮询（60 次 * 1 秒）
- ❌ 删除 HTTP 关闭 API + 强杀进程树
- ✅ 添加 Unix Socket 心跳机制（每 100ms）
- ✅ 添加 TCP 端口检测（快速失败）
- ✅ 简化日志输出

**关键变化**:
```rust
// 旧: HTTP 健康检查
for _ in 0..60 {
    reqwest::get(&health_url).await?;
    sleep(1s);
}

// 新: TCP 端口检测 + 心跳
loop {
    if TcpStream::connect(&addr).is_ok() { break; }
    sleep(200ms);
}
start_heartbeat();  // Unix Socket
```

### 1.4 lib/mix/tasks/cortex.dev.ex

**新增开发命令**:
```bash
mix cortex.dev  # 启动热重载模式
```

等同于 `mix ex_tauri.dev`，支持所有 ExTauri 选项。

---

## 二、文件清单

### 修改的文件
- `mix.exs` - 添加 desktop release + ExTauri 依赖
- `lib/cortex/application.ex` - 优化启动流程
- `src-tauri/src/lib.rs` - 重写为 ExTauri 风格

### 新增的文件
- `lib/mix/tasks/cortex.dev.ex` - 开发模式命令

### 备份的文件
- `src-tauri/src/lib.rs.backup` - 原始 Rust 代码备份

---

## 三、使用方法

### 3.1 开发模式（热重载）

```bash
# 启动 Desktop 开发模式
mix cortex.dev

# 或使用 ExTauri 命令
mix ex_tauri.dev
```

**效果**:
- Phoenix 在 < 1 秒内启动
- Tauri 窗口自动打开
- 前端修改 → 自动刷新
- 后端修改 → LiveReload 推送

### 3.2 生产构建

**Server 版本**（纯后端）:
```bash
MIX_ENV=prod mix release cortex --overwrite
# 产物: burrito_out/cortex_linux
```

**Desktop 版本**（GUI）:
```bash
# 1. 构建 sidecar
MIX_ENV=prod mix release desktop --overwrite

# 2. 放置 sidecar
mkdir -p src-tauri/binaries
cp burrito_out/desktop_linux src-tauri/binaries/cortex_backend-x86_64-unknown-linux-gnu

# 3. 构建 Tauri
cd src-tauri
cargo tauri build
```

**或使用 ExTauri 一键构建**:
```bash
mix ex_tauri.build
```

### 3.3 CI/CD 修改

**`.github/workflows/release.yml` 需要修改**:

```yaml
# build-desktop job
- name: Build Backend Sidecar (Burrito)
  run: mix release desktop --overwrite  # 改这里

- name: Place sidecar binary for Tauri
  shell: bash
  run: |
    mkdir -p src-tauri/binaries
    # 注意：Burrito 输出文件名变为 desktop_*
    if [ "${{ runner.os }}" = "Linux" ]; then
      BURRITO_BIN="desktop_linux"
    elif [ "${{ runner.os }}" = "Windows" ]; then
      BURRITO_BIN="desktop_windows.exe"
    elif [ "${{ runner.os }}" = "macOS" ]; then
      BURRITO_BIN="desktop_macos_m1"
    fi
    
    cp "burrito_out/$BURRITO_BIN" \
       "src-tauri/binaries/cortex_backend-${{ matrix.sidecar-triple }}${{ matrix.sidecar-ext }}"
```

---

## 四、预期效果

### 4.1 启动速度对比

| 场景 | 旧版本 | 新版本 |
|------|--------|--------|
| Phoenix 启动 | 3-5 秒 | < 1 秒 |
| Tauri 健康检查 | 60 秒超时 | 无需等待 |
| 窗口打开 | 5-60 秒 | 2-3 秒 |
| 总启动时间 | 10-65 秒 | 3-5 秒 |

### 4.2 进程管理对比

| 功能 | 旧版本 | 新版本 |
|------|--------|--------|
| 关闭方式 | HTTP POST + 强杀 | Unix Socket 心跳 |
| 响应时间 | 300ms + 强杀 | 自动检测（300ms） |
| 崩溃保护 | ❌ 孤儿进程 | ✅ 自动退出 |
| 日志 | 分散 3 个文件 | 统一输出 |

### 4.3 开发体验对比

| 功能 | 旧版本 | 新版本 |
|------|--------|--------|
| 热重载 | ❌ 无 | ✅ 自动刷新 |
| 启动命令 | 手动构建 + 运行 | `mix cortex.dev` |
| 调试 | 查看多个日志文件 | 统一日志输出 |

---

## 五、验证步骤

### 5.1 本地测试

```bash
# 1. 获取依赖
mix deps.get

# 2. 编译
mix compile

# 3. 测试 Server 版本
MIX_ENV=prod mix release cortex --overwrite
PHX_SERVER=true ./burrito_out/cortex_linux

# 4. 测试 Desktop 开发模式
mix cortex.dev

# 5. 测试 Desktop 生产构建
mix ex_tauri.build
```

### 5.2 验收标准

- ✅ `mix compile` 无错误
- ✅ `mix release cortex` 成功（Server 版本）
- ✅ `mix release desktop` 成功（Desktop 版本）
- ✅ `mix cortex.dev` 启动热重载
- ✅ Phoenix 在 < 5 秒内启动
- ✅ Tauri 窗口正常打开
- ✅ 前端修改自动刷新
- ✅ 退出时无孤儿进程

---

## 六、已知问题

### 6.1 Windows 心跳机制

**问题**: Unix Socket 在 Windows 上不可用

**解决方案**: ExTauri 已处理，Windows 使用命名管道（Named Pipes）

### 6.2 首次启动慢

**问题**: 数据库迁移在后台运行，首次启动可能看到"正在初始化"

**解决方案**: 在 UI 中添加加载状态提示（可选）

### 6.3 CI/CD 需要更新

**问题**: `.github/workflows/release.yml` 需要修改

**解决方案**: 见上文 3.3 节

---

## 七、回滚方案

如果集成失败，可以快速回滚：

```bash
# 1. 恢复 Rust 代码
cp src-tauri/src/lib.rs.backup src-tauri/src/lib.rs

# 2. 恢复 mix.exs
git checkout mix.exs

# 3. 恢复 Application
git checkout lib/cortex/application.ex

# 4. 删除开发命令
rm lib/mix/tasks/cortex.dev.ex

# 5. 重新编译
mix deps.get
mix compile
```

---

## 八、下一步

1. **本地测试**: 运行 `mix cortex.dev` 验证热重载
2. **生产构建**: 测试 `mix ex_tauri.build` 生成 exe
3. **更新 CI/CD**: 修改 `.github/workflows/release.yml`
4. **文档更新**: 更新 `README.md` 添加开发模式说明
5. **提交 PR**: 创建 `feature/ex-tauri-integration` 分支

---

## 九、相关文档

- [ExTauri vs Cortex 对比分析](./20260228_ex_tauri_vs_cortex_comparison.md)
- [Desktop 启动阻塞问题分析](./20260228_desktop_startup_blocking_issue.md)
- [ExTauri 集成策略](../plans/20260228_ex_tauri_integration_strategy.md)

---

**集成完成时间**: 2026-02-28  
**预计测试时间**: 30 分钟  
**预计 CI/CD 修改时间**: 1 小时

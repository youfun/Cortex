# ExTauri 集成策略：双 Release 架构方案

**日期**: 2026-02-28  
**目标**: 在保留 Linux Server 版本的前提下，集成 ExTauri 实现 Desktop 热重载

---

## 一、当前架构分析

### 1.1 发布矩阵

根据 `.github/workflows/release.yml`，Cortex 有 **4 个发布目标**：

| 类型 | 平台 | 产物 | 用途 |
|------|------|------|------|
| **Server** | Linux x86_64 | `cortex_linux` | 无 GUI 的后端服务（CLI/API） |
| **Desktop** | Linux x86_64 | Tauri Bundle | 带 GUI 的桌面应用 |
| **Desktop** | Windows x86_64 | Tauri Bundle | 带 GUI 的桌面应用 |
| **Desktop** | macOS aarch64 | Tauri Bundle | 带 GUI 的桌面应用 |

### 1.2 关键差异

**Server 版本**:
```bash
# 构建流程
mix release cortex --overwrite
# 产物：burrito_out/cortex_linux（纯 Elixir 二进制）
# 启动：PHX_SERVER=true ./cortex_linux
```

**Desktop 版本**:
```bash
# 构建流程
mix release cortex --overwrite  # 生成 sidecar
cargo tauri build               # 打包 Tauri + sidecar
# 产物：src-tauri/target/*/release/bundle/（包含 GUI）
# 启动：双击 .exe/.app 或运行 bundle
```

### 1.3 问题

如果直接改为 `desktop` release，会导致：
- ❌ Server 版本无法构建（`mix release cortex` 失败）
- ❌ CI/CD 流程中断（`build-server` job 找不到 release）

---

## 二、解决方案：双 Release 配置

### 2.1 核心思路

**保留两个 release 配置**：
- `cortex`: 用于 Server 版本（纯后端）
- `desktop`: 用于 Desktop 版本（ExTauri 集成）

### 2.2 修改 `mix.exs`

```elixir
def releases do
  [
    # Server 版本：纯 Elixir 后端（无 Tauri）
    cortex: [
      steps: [:assemble, &Burrito.wrap/1],
      env: %{
        "RELEASE_NAME" => "cortex"
      },
      burrito: [
        targets: [
          linux: [os: :linux, cpu: :x86_64]
        ],
        debug: Mix.env() != :prod,
        debug_interpreter: Mix.env() != :prod
      ]
    ],

    # Desktop 版本：ExTauri 集成（Tauri sidecar）
    desktop: [
      steps: [:assemble, &Burrito.wrap/1],
      env: %{
        "RELEASE_NAME" => "desktop"
      },
      burrito: [
        targets: [
          windows: [os: :windows, cpu: :x86_64],
          linux: [os: :linux, cpu: :x86_64],
          macos_m1: [os: :darwin, cpu: :aarch64]
        ],
        debug: Mix.env() != :prod,
        debug_interpreter: Mix.env() != :prod
      ]
    ]
  ]
end
```

### 2.3 修改 CI/CD

**`build-server` job** (无变化):
```yaml
- name: Build Server Binary (Burrito)
  run: mix release cortex --overwrite
```

**`build-desktop` job** (改用 `desktop` release):
```yaml
- name: Build Backend Sidecar (Burrito)
  run: mix release desktop --overwrite  # 改这里

- name: Place sidecar binary for Tauri
  shell: bash
  run: |
    mkdir -p src-tauri/binaries
    # 注意：Burrito 输出文件名会变为 desktop_*
    cp "burrito_out/desktop_${{ matrix.burrito-suffix }}" \
       "src-tauri/binaries/cortex_backend-${{ matrix.sidecar-triple }}${{ matrix.sidecar-ext }}"
```

**关键点**: Burrito 输出文件名基于 release 名称：
- `cortex` release → `burrito_out/cortex_linux`
- `desktop` release → `burrito_out/desktop_linux`

### 2.4 修改 Tauri 配置

**`src-tauri/tauri.conf.json`** (无需改动):
```json
{
  "bundle": {
    "externalBin": [
      "binaries/cortex_backend"  // 保持不变
    ]
  }
}
```

Tauri 会自动根据平台选择正确的 sidecar 文件（通过 `-<triple>` 后缀）。

---

## 三、ExTauri 集成步骤

### 3.1 添加依赖

```elixir
# mix.exs
defp deps do
  [
    # ... 现有依赖
    {:ex_tauri, path: "deps-local/ex_tauri"}
  ]
end
```

### 3.2 添加 ShutdownManager

```elixir
# lib/cortex/application.ex
def start(_type, _args) do
  children = [
    # ... 现有 children
    
    # 仅在 Desktop 模式下启动 ShutdownManager
    maybe_shutdown_manager()
  ] |> List.flatten()
  
  # ...
end

defp maybe_shutdown_manager do
  if System.get_env("DESKTOP_MODE") == "true" do
    [ExTauri.ShutdownManager]
  else
    []
  end
end
```

**关键**: 通过 `DESKTOP_MODE` 环境变量区分 Server 和 Desktop 模式。

### 3.3 添加开发命令

```elixir
# lib/mix/tasks/cortex.dev.ex
defmodule Mix.Tasks.Cortex.Dev do
  @moduledoc """
  启动 Cortex Desktop 开发模式（热重载）
  
  ## 用法
  
      mix cortex.dev
  
  等同于：
      mix ex_tauri.dev
  """
  
  use Mix.Task
  
  @impl true
  def run(args) do
    # 确保使用 desktop release
    System.put_env("CORTEX_RELEASE", "desktop")
    
    # 调用 ExTauri 的开发模式
    Mix.Task.run("ex_tauri.dev", args)
  end
end
```

### 3.4 清理 Rust 代码

**保留的部分** (`src-tauri/src/lib.rs`):
- ✅ Tray 菜单逻辑
- ✅ 日志系统
- ✅ 窗口管理

**删除的部分**:
- ❌ 健康检查轮询（`loop { reqwest::get(...) }`）
- ❌ HTTP 关闭逻辑（`/api/system/shutdown`）
- ❌ 强制进程终止（`taskkill /F /T`）

**替换为 ExTauri 的心跳机制**:
```rust
// src-tauri/src/main.rs (参考 deps-local/ex_tauri/example/src-tauri/src/main.rs)
use std::io::Write;
use std::os::unix::net::UnixStream;

fn start_heartbeat(app_name: &str) {
    let socket_path = format!("/tmp/tauri_heartbeat_{}.sock", app_name);
    
    tauri::async_runtime::spawn(async move {
        loop {
            match UnixStream::connect(&socket_path) {
                Ok(mut stream) => {
                    loop {
                        if stream.write_all(&[1]).is_err() {
                            break;
                        }
                        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                    }
                }
                Err(_) => {
                    tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
                }
            }
        }
    });
}
```

---

## 四、使用流程

### 4.1 开发模式（热重载）

```bash
# 启动 Desktop 开发模式
mix cortex.dev

# 或直接使用 ExTauri
mix ex_tauri.dev
```

**效果**:
- Phoenix 自动启动（作为 sidecar）
- Tauri 窗口打开
- 前端修改 → 自动刷新
- 后端修改 → LiveReload 推送更新

### 4.2 生产构建

**Server 版本**:
```bash
MIX_ENV=prod mix release cortex --overwrite
# 产物：burrito_out/cortex_linux
```

**Desktop 版本**:
```bash
# 1. 构建 sidecar
MIX_ENV=prod mix release desktop --overwrite

# 2. 放置 sidecar 到 Tauri 目录
mkdir -p src-tauri/binaries
cp burrito_out/desktop_linux src-tauri/binaries/cortex_backend-x86_64-unknown-linux-gnu

# 3. 构建 Tauri 应用
cd src-tauri
cargo tauri build
```

**或使用 ExTauri 一键构建**:
```bash
mix ex_tauri.build
```

### 4.3 CI/CD 流程

**无需修改 `build-server` job**，只需修改 `build-desktop` job：

```yaml
- name: Build Backend Sidecar (Burrito)
  run: mix release desktop --overwrite  # 改这里

- name: Place sidecar binary for Tauri
  shell: bash
  run: |
    mkdir -p src-tauri/binaries
    # 根据平台选择正确的 Burrito 输出文件
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

## 五、优势总结

### 5.1 保持兼容性

| 场景 | 命令 | 产物 | 影响 |
|------|------|------|------|
| Server 部署 | `mix release cortex` | `cortex_linux` | ✅ 无变化 |
| Desktop 开发 | `mix cortex.dev` | 热重载 | ✅ 新增功能 |
| Desktop 构建 | `mix ex_tauri.build` | Tauri Bundle | ✅ 简化流程 |

### 5.2 解决的问题

1. ✅ **热重载**: 开发模式下自动刷新
2. ✅ **启动速度**: 跳过健康检查，< 5 秒启动
3. ✅ **进程管理**: Unix Socket 心跳，优雅关闭
4. ✅ **日志统一**: 集中输出，易于调试
5. ✅ **Server 兼容**: 保留纯后端版本

### 5.3 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| CI/CD 中断 | 中 | 先在 dev 分支测试 |
| Burrito 文件名变化 | 低 | 脚本自动处理 |
| ExTauri 依赖冲突 | 低 | 已在 `deps-local/` 本地化 |
| Server 模式误启动 ShutdownManager | 低 | 通过 `DESKTOP_MODE` 环境变量隔离 |

---

## 六、实施计划

### Phase 1: 本地验证（1 小时）

1. 修改 `mix.exs` 添加 `desktop` release
2. 添加 ExTauri 依赖
3. 测试 `mix release desktop` 是否成功
4. 测试 `mix release cortex` 是否仍然工作

### Phase 2: 集成 ExTauri（2 小时）

1. 添加 `ExTauri.ShutdownManager` 到 Application
2. 创建 `mix cortex.dev` 任务
3. 清理 Rust 健康检查代码
4. 添加心跳机制
5. 测试开发模式热重载

### Phase 3: CI/CD 适配（1 小时）

1. 修改 `.github/workflows/release.yml`
2. 更新 `build-desktop` job 使用 `desktop` release
3. 调整 sidecar 文件名处理逻辑
4. 在 dev 分支测试完整流程

### Phase 4: 文档更新（30 分钟）

1. 更新 `README.md` 添加开发模式说明
2. 更新 `docs/` 中的构建文档
3. 添加故障排查指南

**总预估时间**: 4.5 小时

---

## 七、回滚方案

如果集成失败，可以快速回滚：

```bash
# 1. 移除 ExTauri 依赖
# mix.exs: 删除 {:ex_tauri, ...}

# 2. 删除 desktop release
# mix.exs: 删除 releases() 中的 desktop 配置

# 3. 恢复 CI/CD
git revert <commit-hash>

# 4. 重新构建
mix deps.get
mix release cortex --overwrite
```

---

## 八、下一步行动

**立即执行**:
1. 在 dev 分支创建 `feature/ex-tauri-integration`
2. 按 Phase 1 步骤修改 `mix.exs`
3. 本地测试双 release 构建
4. 提交 PR 并在 CI 中验证

**验收标准**:
- ✅ `mix release cortex` 成功（Server 版本）
- ✅ `mix release desktop` 成功（Desktop 版本）
- ✅ `mix cortex.dev` 启动热重载
- ✅ CI/CD 构建 4 个产物（1 Server + 3 Desktop）
- ✅ Server 版本不包含 Tauri 依赖

---

**附录**: 相关文件清单

- `mix.exs` - 添加 `desktop` release
- `lib/cortex/application.ex` - 条件启动 ShutdownManager
- `lib/mix/tasks/cortex.dev.ex` - 新建开发模式任务
- `src-tauri/src/lib.rs` - 清理健康检查，添加心跳
- `.github/workflows/release.yml` - 修改 Desktop 构建流程

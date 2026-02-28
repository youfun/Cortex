# WSL 环境下的 Cortex Desktop 开发指南

**环境**: WSL2 (Linux 6.6.87.2-microsoft-standard-WSL2)  
**问题**: Tauri GUI 应用无法在纯 WSL 环境中直接运行  
**日期**: 2026-02-28

---

## 一、当前环境分析

### 1.1 检测结果

```bash
$ uname -a
Linux WIN-KLQHAJ0PF82 6.6.87.2-microsoft-standard-WSL2

$ echo $DISPLAY
:0  # ✅ WSLg 已启用
```

**结论**: WSLg 已配置，理论上可以运行 GUI 应用。

---

## 二、WSL 环境下的开发策略

### 策略 A: 在 WSL 中开发，在 Windows 中测试（推荐）

**工作流**:
```
WSL (开发) → 构建 Windows 二进制 → Windows 主机运行
```

**优势**:
- ✅ 利用 WSL 的 Linux 工具链
- ✅ 在真实 Windows 环境中测试
- ✅ 避免 WSLg 的兼容性问题

**步骤**:

1. **在 WSL 中构建 Windows 版本**:
```bash
# 安装 Windows 目标
rustup target add x86_64-pc-windows-msvc

# 构建 Desktop 版本
MIX_ENV=prod mix release desktop --overwrite

# 构建 Tauri（Windows 目标）
cd src-tauri
cargo tauri build --target x86_64-pc-windows-msvc
```

2. **在 Windows 中运行**:
```powershell
# 从 Windows 访问 WSL 文件系统
\\wsl$\Debian\home\Debian13\code\Cortex\src-tauri\target\x86_64-pc-windows-msvc\release\Cortex.exe
```

### 策略 B: 使用 WSLg 运行 Linux 版本

**前提**: Windows 11 + WSLg 已启用

**步骤**:

1. **安装 Linux GUI 依赖**:
```bash
sudo apt-get update
sudo apt-get install -y \
    libwebkit2gtk-4.1-dev \
    libappindicator3-dev \
    librsvg2-dev \
    patchelf \
    libgtk-3-dev
```

2. **构建 Linux 版本**:
```bash
MIX_ENV=prod mix release desktop --overwrite

cd src-tauri
cargo tauri build --target x86_64-unknown-linux-gnu
```

3. **运行**:
```bash
./src-tauri/target/x86_64-unknown-linux-gnu/release/cortex
```

**注意**: WSLg 可能有性能问题或兼容性问题。

### 策略 C: 仅测试 Server 版本（无 GUI）

**适用场景**: 只需验证后端逻辑

**步骤**:
```bash
# 构建 Server 版本
MIX_ENV=prod mix release cortex --overwrite

# 运行
PHX_SERVER=true PORT=4000 ./burrito_out/cortex_linux

# 在浏览器中访问
# Windows: http://localhost:4000
# WSL: curl http://localhost:4000
```

---

## 三、推荐工作流（混合开发）

### 3.1 日常开发

**在 WSL 中**:
```bash
# 1. 启动 Phoenix 开发服务器（无 GUI）
mix phx.server

# 2. 在 Windows 浏览器中访问
# http://localhost:4000
```

**优势**:
- ✅ 快速迭代（无需构建 Tauri）
- ✅ 使用 LiveReload
- ✅ 完整的开发工具链

### 3.2 测试 Desktop 功能

**在 WSL 中构建**:
```bash
# 构建 Windows 版本
MIX_ENV=prod mix release desktop --overwrite

# 放置 sidecar
mkdir -p src-tauri/binaries
cp burrito_out/desktop_windows.exe \
   src-tauri/binaries/cortex_backend-x86_64-pc-windows-msvc.exe

# 构建 Tauri
cd src-tauri
cargo tauri build --target x86_64-pc-windows-msvc
```

**在 Windows 中运行**:
```powershell
# 方式 1: 通过 WSL 路径
\\wsl$\Debian\home\Debian13\code\Cortex\src-tauri\target\x86_64-pc-windows-msvc\release\Cortex.exe

# 方式 2: 复制到 Windows
copy \\wsl$\Debian\home\Debian13\code\Cortex\src-tauri\target\x86_64-pc-windows-msvc\release\Cortex.exe C:\Temp\
C:\Temp\Cortex.exe
```

### 3.3 CI/CD 构建

**GitHub Actions 自动构建**:
- Linux 版本: 在 Ubuntu runner 上构建
- Windows 版本: 在 Windows runner 上构建
- macOS 版本: 在 macOS runner 上构建

**无需在 WSL 中构建所有平台**。

---

## 四、当前构建状态

### 4.1 已完成

```bash
$ mix release desktop --overwrite
✅ Successfully built desktop release
✅ Burrito wrapped: burrito_out/desktop_linux
```

### 4.2 下一步

**选项 1: 测试 Linux 版本（WSLg）**
```bash
# 安装依赖
sudo apt-get install -y libwebkit2gtk-4.1-dev libgtk-3-dev

# 构建
cd src-tauri
cargo tauri build --target x86_64-unknown-linux-gnu

# 运行
./target/x86_64-unknown-linux-gnu/release/cortex
```

**选项 2: 构建 Windows 版本（推荐）**
```bash
# 添加 Windows 目标
rustup target add x86_64-pc-windows-msvc

# 重新构建 sidecar（Windows）
MIX_ENV=prod mix release desktop --overwrite

# 注意：需要在 Windows 环境中构建 Tauri
# 或使用 GitHub Actions
```

**选项 3: 仅测试 Server 版本**
```bash
# 构建
MIX_ENV=prod mix release cortex --overwrite

# 运行
PHX_SERVER=true ./burrito_out/cortex_linux

# 访问 http://localhost:4000
```

---

## 五、开发模式的特殊处理

### 5.1 问题

`mix cortex.dev` 需要 Tauri 窗口，在 WSL 中无法直接使用。

### 5.2 解决方案

**创建 WSL 专用开发命令**:

```elixir
# lib/mix/tasks/cortex.dev_wsl.ex
defmodule Mix.Tasks.Cortex.DevWsl do
  @moduledoc """
  WSL 环境下的开发模式（无 GUI）
  
  启动 Phoenix 服务器，在 Windows 浏览器中访问
  """
  
  use Mix.Task
  
  @impl true
  def run(_args) do
    # 启动 Phoenix 开发服务器
    Mix.Task.run("phx.server")
  end
end
```

**使用**:
```bash
# WSL 中启动
mix cortex.dev_wsl

# Windows 浏览器访问
http://localhost:4000
```

---

## 六、最佳实践总结

### 6.1 开发阶段

| 任务 | 环境 | 命令 |
|------|------|------|
| 后端开发 | WSL | `mix phx.server` |
| 前端开发 | WSL | `mix phx.server` + Windows 浏览器 |
| 测试 API | WSL | `curl http://localhost:4000` |

### 6.2 测试阶段

| 任务 | 环境 | 命令 |
|------|------|------|
| Server 版本 | WSL | `mix release cortex` |
| Desktop Linux | WSL + WSLg | `mix ex_tauri.build` |
| Desktop Windows | Windows | 在 Windows 中构建 |

### 6.3 发布阶段

| 任务 | 环境 | 说明 |
|------|------|------|
| 所有平台 | GitHub Actions | 自动构建 4 个产物 |

---

## 七、故障排查

### 7.1 WSLg 不工作

**症状**: `DISPLAY=:0` 但 GUI 应用无法启动

**解决**:
```bash
# 检查 WSLg 状态
wslg --version

# 重启 WSL
# 在 Windows PowerShell 中:
wsl --shutdown
wsl
```

### 7.2 Tauri 构建失败

**症状**: `cargo tauri build` 报错

**解决**:
```bash
# 检查依赖
sudo apt-get install -y \
    libwebkit2gtk-4.1-dev \
    libappindicator3-dev \
    librsvg2-dev \
    patchelf

# 清理缓存
cargo clean
cargo tauri build
```

### 7.3 跨平台构建问题

**症状**: 在 WSL 中构建 Windows 版本失败

**解决**: 使用 GitHub Actions 或在 Windows 中构建

---

## 八、推荐配置

### 8.1 VS Code Remote - WSL

**优势**:
- ✅ 在 Windows 中使用 VS Code
- ✅ 代码在 WSL 中运行
- ✅ 浏览器在 Windows 中打开

**配置**:
```json
// .vscode/settings.json
{
  "remote.WSL.fileWatcher.polling": true,
  "terminal.integrated.defaultProfile.linux": "bash"
}
```

### 8.2 端口转发

WSL2 自动转发端口到 Windows，无需额外配置。

---

## 九、总结

### 当前状态

- ✅ ExTauri 集成完成
- ✅ `mix release desktop` 成功
- ⚠️ GUI 测试需要在 Windows 或 WSLg 中进行

### 推荐方案

**日常开发**: WSL + `mix phx.server` + Windows 浏览器  
**Desktop 测试**: GitHub Actions 或 Windows 本地构建  
**生产发布**: GitHub Actions 自动构建所有平台

### 下一步

1. **立即可用**: `mix phx.server` 测试后端功能
2. **Desktop 测试**: 等待 GitHub Actions 构建或在 Windows 中构建
3. **CI/CD 更新**: 修改 `.github/workflows/release.yml`

---

**文档创建时间**: 2026-02-28  
**适用环境**: WSL2 + Windows 11

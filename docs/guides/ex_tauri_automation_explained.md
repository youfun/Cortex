# ExTauri 自动构建机制说明

**日期**: 2026-02-28  
**问题**: ExTauri 是否需要手动移动二进制？  
**答案**: ❌ 不需要！ExTauri 已经自动处理了

---

## 一、ExTauri 的自动化流程

### 1.1 `mix ex_tauri.build` 做了什么

根据 `deps-local/ex_tauri/lib/ex_tauri.ex:130-168`，ExTauri 的 `wrap()` 函数自动执行：

```elixir
defp wrap() do
  # 1. 清理旧的 Burrito 缓存
  File.rm_rf!(Path.join([Path.expand("~"), "Library", "Application Support", ".burrito"]))

  # 2. 检查 desktop release 是否存在
  get_in(Mix.Project.config(), [:releases, :desktop]) ||
    raise "expected a burrito release configured for the app :desktop in your mix.exs"

  # 3. 自动构建 desktop release
  System.cmd("mix", ["release", "desktop", "--overwrite"],
    env: [{"MIX_ENV", "prod"}],
    into: IO.stream(:stdio, :line),
    stderr_to_stdout: true
  )

  # 4. 自动复制 sidecar 到 Tauri 期望的位置
  triplet = System.cmd("rustc", ["-Vv"]) |> ... # 获取平台 triplet
  File.cp!(
    "burrito_out/desktop_#{triplet}",
    "burrito_out/desktop-#{triplet}"  # Tauri 期望的文件名格式
  )
end
```

### 1.2 完整流程

```
mix ex_tauri.build
  ↓
ExTauri.run(["build"])
  ↓
wrap()  # 自动构建 + 复制
  ├─ mix release desktop --overwrite
  ├─ 生成 burrito_out/desktop_x86_64-unknown-linux-gnu
  └─ 复制为 burrito_out/desktop-x86_64-unknown-linux-gnu
  ↓
run_tauri_cli(["build"])
  ↓
cargo tauri build
  ├─ 自动检测 burrito_out/desktop-*
  └─ 打包到 src-tauri/target/release/bundle/
```

---

## 二、为什么 GitHub Actions 还需要手动处理？

### 2.1 问题

ExTauri 的自动化依赖于：
1. **本地 Rust 工具链**: 通过 `rustc -Vv` 获取平台 triplet
2. **单平台构建**: 假设在当前平台构建当前平台的二进制

但 GitHub Actions 需要：
1. **跨平台构建**: 在 Linux runner 上构建 Windows/macOS 版本
2. **矩阵构建**: 并行构建多个平台

### 2.2 ExTauri 的限制

```elixir
# ExTauri 只能处理当前平台
triplet = System.cmd("rustc", ["-Vv"]) |> ...
# 在 Linux 上运行 → x86_64-unknown-linux-gnu
# 在 Windows 上运行 → x86_64-pc-windows-msvc
# 在 macOS 上运行 → aarch64-apple-darwin

File.cp!(
  "burrito_out/desktop_#{triplet}",  # 只复制当前平台
  "burrito_out/desktop-#{triplet}"
)
```

**问题**: 如果在 Linux 上构建 Windows 版本，`rustc -Vv` 仍然返回 Linux triplet，导致找不到 `desktop_x86_64-pc-windows-msvc.exe`。

---

## 三、解决方案对比

### 方案 A: 使用 ExTauri（本地开发）✅

**适用场景**: 在本地开发机器上构建当前平台

**命令**:
```bash
# 自动构建 + 打包
mix ex_tauri.build

# 产物
src-tauri/target/release/bundle/
  ├── deb/Cortex_0.1.39_amd64.deb
  └── appimage/Cortex_0.1.39_amd64.AppImage
```

**优势**:
- ✅ 一键构建
- ✅ 自动处理 sidecar
- ✅ 无需手动移动文件

**劣势**:
- ❌ 只能构建当前平台
- ❌ 无法跨平台编译

### 方案 B: 手动处理（GitHub Actions）✅

**适用场景**: CI/CD 矩阵构建多个平台

**流程**:
```yaml
# 1. 构建 sidecar（指定平台）
- run: mix release desktop --overwrite

# 2. 手动放置到 Tauri 期望的位置
- run: |
    mkdir -p src-tauri/binaries
    cp burrito_out/${{ matrix.burrito-bin }} \
       src-tauri/binaries/cortex_backend-${{ matrix.sidecar-triple }}${{ matrix.sidecar-ext }}

# 3. 构建 Tauri（指定目标）
- run: cargo tauri build --target ${{ matrix.rust-target }}
```

**优势**:
- ✅ 支持跨平台构建
- ✅ 并行构建多个平台
- ✅ 完全控制构建流程

**劣势**:
- ❌ 需要手动配置 matrix
- ❌ 需要手动移动文件

---

## 四、最佳实践

### 4.1 本地开发

**使用 ExTauri 自动化**:
```bash
# 开发模式（热重载）
mix cortex.dev

# 生产构建（当前平台）
mix ex_tauri.build
```

**无需任何手动操作**！

### 4.2 CI/CD 发布

**使用 GitHub Actions 矩阵构建**:
```yaml
strategy:
  matrix:
    include:
      - os: ubuntu-22.04
        rust-target: x86_64-unknown-linux-gnu
        burrito-bin: desktop_linux
      - os: windows-2022
        rust-target: x86_64-pc-windows-msvc
        burrito-bin: desktop_windows.exe
      - os: macos-14
        rust-target: aarch64-apple-darwin
        burrito-bin: desktop_macos_m1
```

**需要手动处理 sidecar 放置**，因为 ExTauri 无法处理跨平台场景。

---

## 五、为什么不能完全依赖 ExTauri？

### 5.1 ExTauri 的设计目标

ExTauri 是为 **本地开发** 设计的：
- 开发者在 macOS 上开发 → 构建 macOS 版本
- 开发者在 Windows 上开发 → 构建 Windows 版本
- 开发者在 Linux 上开发 → 构建 Linux 版本

### 5.2 CI/CD 的需求

CI/CD 需要 **一次构建所有平台**：
- 在 Linux runner 上构建 Linux 版本
- 在 Windows runner 上构建 Windows 版本
- 在 macOS runner 上构建 macOS 版本
- **并行执行**，而不是串行

### 5.3 技术限制

ExTauri 的 `wrap()` 函数依赖：
```elixir
triplet = System.cmd("rustc", ["-Vv"]) |> ...
```

这个 triplet 是 **当前运行环境** 的平台，无法指定目标平台。

---

## 六、总结

### 本地开发 ✅

**完全自动化**，使用 ExTauri：
```bash
mix ex_tauri.build  # 一键构建当前平台
```

**ExTauri 自动处理**:
- ✅ 构建 desktop release
- ✅ 复制 sidecar 到正确位置
- ✅ 调用 cargo tauri build
- ✅ 生成安装包

### CI/CD 构建 ⚠️

**需要手动处理**，因为：
- ❌ ExTauri 无法处理跨平台构建
- ❌ 矩阵构建需要明确指定目标平台
- ❌ Burrito 输出文件名与 Tauri 期望不匹配

**解决方案**: 在 GitHub Actions 中手动放置 sidecar：
```yaml
- run: |
    mkdir -p src-tauri/binaries
    cp burrito_out/${{ matrix.burrito-bin }} \
       src-tauri/binaries/cortex_backend-${{ matrix.sidecar-triple }}${{ matrix.sidecar-ext }}
```

---

## 七、快速参考

| 场景 | 命令 | 是否需要手动处理 |
|------|------|------------------|
| 本地开发（当前平台） | `mix ex_tauri.build` | ❌ 不需要 |
| 本地开发（热重载） | `mix cortex.dev` | ❌ 不需要 |
| CI/CD（多平台） | GitHub Actions | ✅ 需要 |
| 手动跨平台构建 | 手动执行 | ✅ 需要 |

---

## 八、Vite 端口占用问题

### 问题

```
Error: Port 5173 is already in use
```

### 原因

之前的 `mix phx.server` 进程没有完全退出，Vite 进程仍在运行。

### 解决方案

```bash
# 1. 查找占用端口的进程
ps aux | grep vite | grep -v grep

# 2. 杀死进程
kill <PID>

# 3. 或者一键杀死所有 vite 进程
pkill -f vite

# 4. 重新启动
mix phx.server
```

### 预防措施

**优雅退出**:
```bash
# 使用 Ctrl+C 两次完全退出
# 或使用
mix phx.server
# 然后 Ctrl+C, Ctrl+C
```

---

**文档创建时间**: 2026-02-28  
**关键结论**: ExTauri 自动化适用于本地开发，CI/CD 需要手动处理跨平台构建

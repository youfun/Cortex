# Livebook vs Cortex 编译流程对比分析

## 📊 总体对比

| 特性 | Livebook | Cortex (我们的项目) |
|------|----------|-------------------|
| **触发方式** | Tag 推送 + 定时任务 + 手动 | 分支推送 + 手动 |
| **BEAM 安装** | `erlef/setup-beam@v1` | 自定义脚本 + 官方 action |
| **版本管理** | 外部 `versions` 文件 | Workflow 环境变量 |
| **平台支持** | 5 个平台（含 ARM） | 3 个平台 |
| **Tauri 集成** | `tauri-apps/tauri-action` | 手动 `cargo tauri build` |
| **代码签名** | ✅ macOS + Windows | ❌ 未配置 |
| **自动更新** | ✅ Tauri updater | ❌ 未配置 |
| **发布管理** | 自动创建 GitHub Release | 仅上传 Artifact |
| **Rust 缓存** | `Swatinem/rust-cache@v2` | ❌ 未配置 |

---

## 🎯 核心差异分析

### 1. 触发机制

#### Livebook（生产级）
```yaml
on:
  push:
    tags: ["v*.*.*"]      # Tag 触发正式版本
  schedule:
    - cron: "0 0 * * *"   # 每天自动构建 nightly
  workflow_dispatch:       # 手动触发
```

**优点：**
- ✅ 自动化程度高
- ✅ 支持正式版本 + 每日构建
- ✅ 适合持续交付

#### Cortex（开发测试）
```yaml
on:
  workflow_dispatch:
  push:
    branches: [main, master, test-custom-beam]
```

**特点：**
- ✅ 适合开发阶段
- ✅ 每次推送都构建（快速反馈）
- ⚠️ 缺少版本管理

**建议：** 
```yaml
on:
  push:
    tags: ["v*"]          # 添加 tag 触发
    branches: [main]      # 保留分支触发
  workflow_dispatch:
```

---

### 2. BEAM 环境配置

#### Livebook（标准方式）
```yaml
- name: Read versions
  run: |
    . versions           # 从外部文件读取版本
    echo "elixir=$elixir" >> $GITHUB_ENV
    echo "otp=$otp" >> $GITHUB_ENV

- uses: erlef/setup-beam@v1
  with:
    otp-version: ${{ env.otp }}
    elixir-version: ${{ env.elixir }}
```

**优点：**
- ✅ 版本集中管理（`versions` 文件）
- ✅ 与本地开发环境一致
- ✅ 简单可靠

**versions 文件示例：**
```bash
# versions
elixir=1.19.5
otp=28.3.1
ubuntu=22.04
```

#### Cortex（混合方式）
```yaml
env:
  OTP_VERSION: "28.3.1"
  ELIXIR_VERSION: "1.19.5"

# Linux: 自定义脚本（预编译包）
- name: Setup Custom BEAM (Linux)
  run: .github/scripts/setup-beam.sh

# Windows/macOS: 官方 action
- uses: erlef/setup-beam@v1
```

**优点：**
- ✅ Linux 使用最新版本（OTP 28.3.1）
- ✅ 灵活性高
- ⚠️ 复杂度较高

**建议：** 创建 `versions` 文件统一管理
```bash
# 在项目根目录创建
cat > versions << 'EOF'
elixir=1.19.5
otp=28.3.1
ubuntu=22.04
EOF
```

---

### 3. 平台支持

#### Livebook（全平台）
```yaml
matrix:
  include:
    - platform: macos-15
      gui_target: "aarch64-apple-darwin"    # Apple Silicon
    - platform: macos-15
      gui_target: "x86_64-apple-darwin"     # Intel Mac
    - platform: windows-2022
      gui_target: "x86_64-pc-windows-msvc"
    - platform: ubuntu-22.04-arm           # ARM Linux
      gui_target: "aarch64-unknown-linux-gnu"
    - platform: ubuntu-22.04
      gui_target: "x86_64-unknown-linux-gnu"
```

**特点：**
- ✅ 支持 5 个平台
- ✅ 包含 ARM 架构（macOS M1/M2, Linux ARM）
- ✅ 覆盖主流用户群体

#### Cortex（基础平台）
```yaml
matrix:
  include:
    - os: ubuntu-22.04
      rust-target: x86_64-unknown-linux-gnu
    - os: windows-2022
      rust-target: x86_64-pc-windows-msvc
    - os: macos-14
      rust-target: aarch64-apple-darwin     # 仅 Apple Silicon
```

**建议：** 添加 Intel Mac 支持
```yaml
- label: macOS x86_64
  os: macos-13                              # Intel Mac
  rust-target: x86_64-apple-darwin
```

---

### 4. Tauri 构建方式

#### Livebook（官方 Action）
```yaml
- name: Install Tauri CLI
  run: |
    if ! command -v cargo-tauri &> /dev/null; then
      cargo install tauri-cli --version "=2.8.0" --locked
    fi

- name: Build Tauri app
  uses: tauri-apps/tauri-action@v0.6      # 官方 action
  with:
    projectPath: rel/app_next
    tauriScript: ./tauri.sh
    args: --target ${{ matrix.gui_target }}
    tagName: ${{ github.ref_name }}
    releaseDraft: true
```

**优点：**
- ✅ 自动处理代码签名
- ✅ 自动上传到 GitHub Release
- ✅ 支持 Tauri updater
- ✅ 处理 asset 命名

#### Cortex（手动构建）
```yaml
- name: Install Tauri CLI
  run: cargo install tauri-cli --version "^2" --locked

- name: Build Tauri Desktop App
  working-directory: src-tauri
  run: cargo tauri build --target ${{ matrix.rust-target }}

- name: Upload Desktop Artifact
  uses: actions/upload-artifact@v4
```

**特点：**
- ✅ 简单直接
- ⚠️ 需要手动管理发布
- ❌ 没有代码签名
- ❌ 没有自动更新

**建议：** 使用 `tauri-apps/tauri-action`
```yaml
- uses: tauri-apps/tauri-action@v0.6
  with:
    projectPath: src-tauri
    args: --target ${{ matrix.rust-target }}
    # 如果有 tag，自动发布
    tagName: ${{ github.ref_type == 'tag' && github.ref_name || '' }}
```

---

### 5. 代码签名

#### Livebook（完整签名）

**macOS 签名：**
```yaml
- name: Install Apple certificate
  env:
    P12_BASE64: ${{ secrets.APPLE_CERTIFICATE_P12_BASE64 }}
    P12_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_P12_PASSWORD }}
  run: |
    # 创建临时 keychain
    # 导入证书
    # 配置签名

- name: Build Tauri app
  env:
    APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}
    APPLE_ID: ${{ secrets.APPLE_ID }}
    APPLE_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
    APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}

- name: Verify app notarization
  run: spctl -a -t exec -vvv "$app_path"
```

**Windows 签名：**
```yaml
- name: Install trusted-signing-cli
  run: cargo install trusted-signing-cli

- name: Build Tauri app
  env:
    AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
    AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
    AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
```

**重要性：**
- ✅ macOS Gatekeeper 不会阻止
- ✅ Windows SmartScreen 不会警告
- ✅ 用户信任度高
- ✅ 企业部署必需

#### Cortex（无签名）
```yaml
# 没有代码签名配置
```

**影响：**
- ⚠️ macOS 用户需要右键打开
- ⚠️ Windows 用户会看到 SmartScreen 警告
- ⚠️ 企业环境可能无法部署

**建议：** 至少添加 macOS 签名（Windows 签名成本较高）

---

### 6. 缓存策略

#### Livebook（优化的缓存）
```yaml
- name: Rust cache
  uses: Swatinem/rust-cache@v2
  with:
    workspaces: rel/app_next/src-tauri
    cache-directories: |
      ~/.cargo/bin              # 缓存已安装的工具
    key: ${{ matrix.gui_target }}
```

**效果：**
- ✅ Rust 编译时间减少 50-70%
- ✅ 自动管理缓存失效
- ✅ 跨平台支持

#### Cortex（基础缓存）
```yaml
- name: Cache Mix Dependencies
  uses: actions/cache@v4
  with:
    path: |
      deps
      _build
    key: mix-${{ runner.os }}-${{ hashFiles('**/mix.lock') }}
```

**特点：**
- ✅ 缓存 Elixir 依赖
- ⚠️ 没有缓存 Rust 编译产物

**建议：** 添加 Rust 缓存
```yaml
- name: Rust cache
  uses: Swatinem/rust-cache@v2
  with:
    workspaces: src-tauri
    key: ${{ matrix.rust-target }}
```

---

### 7. 发布管理

#### Livebook（自动化发布）
```yaml
jobs:
  create_release:
    steps:
      - name: Create release
        run: |
          if [[ "${{ github.ref_type }}" == "tag" ]]; then
            # Tag 推送 → 创建正式版本
            gh release create --draft ${{ github.ref_name }}
          else
            # 定时任务 → 更新 nightly 版本
            gh release edit nightly --notes "Automated nightly build"
          fi
```

**特点：**
- ✅ 自动创建 GitHub Release
- ✅ 支持正式版本 + nightly 版本
- ✅ 自动上传构建产物
- ✅ 用户可以直接下载

#### Cortex（手动发布）
```yaml
- name: Upload Desktop Artifact
  uses: actions/upload-artifact@v4
  with:
    name: cortex-desktop-${{ matrix.label }}
    path: src-tauri/target/.../bundle/**
```

**特点：**
- ✅ 简单
- ⚠️ 需要手动创建 Release
- ⚠️ Artifact 30 天后自动删除

**建议：** 添加自动发布
```yaml
- name: Upload to Release
  if: github.ref_type == 'tag'
  uses: softprops/action-gh-release@v1
  with:
    files: src-tauri/target/.../bundle/**/*
    draft: true
```

---

### 8. 依赖安装

#### Livebook（完整依赖）
```yaml
- name: Install dependencies (Linux)
  run: |
    sudo apt-get install -y \
      libwebkit2gtk-4.1-dev \
      libgtk-3-dev \
      libayatana-appindicator3-dev \
      librsvg2-dev \
      patchelf \
      libwxgtk3.0-gtk3-dev \    # wxWidgets（Erlang Observer）
      xdg-utils                  # 桌面集成
```

#### Cortex（基础依赖）
```yaml
- name: Install Linux system deps
  run: |
    sudo apt-get install -y \
      libwebkit2gtk-4.1-dev \
      libappindicator3-dev \
      librsvg2-dev \
      patchelf
```

**差异：**
- Livebook 包含 wxWidgets（用于 Erlang Observer GUI）
- Livebook 包含 xdg-utils（桌面环境集成）

---

## 🎯 改进建议优先级

### P0 - 立即改进

1. **添加 Rust 缓存**
   ```yaml
   - uses: Swatinem/rust-cache@v2
     with:
       workspaces: src-tauri
   ```
   **收益：** 构建时间减少 50%+

2. **使用 tauri-apps/tauri-action**
   ```yaml
   - uses: tauri-apps/tauri-action@v0.6
   ```
   **收益：** 自动处理发布、签名、更新

3. **修复 Windows ImageOS 问题**（已完成 ✅）

### P1 - 重要改进

4. **创建 versions 文件**
   ```bash
   elixir=1.19.5
   otp=28.3.1
   ```
   **收益：** 版本管理更清晰

5. **添加 Intel Mac 支持**
   ```yaml
   - os: macos-13
     rust-target: x86_64-apple-darwin
   ```
   **收益：** 覆盖更多用户

6. **添加自动发布**
   ```yaml
   on:
     push:
       tags: ["v*"]
   ```
   **收益：** 自动化发布流程

### P2 - 可选改进

7. **添加 macOS 代码签名**
   **收益：** 用户体验更好

8. **添加 Tauri updater**
   **收益：** 自动更新功能

9. **添加 nightly 构建**
   ```yaml
   schedule:
     - cron: "0 0 * * *"
   ```
   **收益：** 持续集成测试

---

## 📝 推荐的改进方案

### 方案 A：最小改进（快速见效）
```yaml
# 只添加 Rust 缓存 + tauri-action
- uses: Swatinem/rust-cache@v2
- uses: tauri-apps/tauri-action@v0.6
```
**时间：** 10 分钟  
**收益：** 构建时间减少 50%，自动发布

### 方案 B：标准改进（推荐）
```yaml
# 方案 A + versions 文件 + Intel Mac
```
**时间：** 30 分钟  
**收益：** 接近 Livebook 的质量

### 方案 C：完整改进（生产级）
```yaml
# 方案 B + 代码签名 + 自动更新 + nightly
```
**时间：** 2-3 小时  
**收益：** 生产级 CI/CD

---

## 🔍 关键学习点

1. **版本管理**：使用外部 `versions` 文件比硬编码更好
2. **缓存策略**：Rust 缓存是必需的，能大幅提升速度
3. **官方 Action**：`tauri-apps/tauri-action` 比手动构建更可靠
4. **代码签名**：对用户体验影响巨大
5. **发布自动化**：Tag 触发 + 自动创建 Release 是标准做法
6. **平台覆盖**：至少支持 Intel + ARM Mac
7. **Tauri CLI 版本**：Livebook 锁定精确版本（`=2.8.0`），我们用范围版本（`^2`）

---

## 💡 立即可用的改进代码

我可以帮你实现方案 A（最小改进）或方案 B（标准改进），你想要哪个？

# GitHub Actions Workflow 更新说明

**日期**: 2026-02-28  
**目的**: 适配 ExTauri 集成，支持双 release 构建（Server + Desktop）

---

## 一、更新内容

### 1.1 关键修改

**文件**: `.github/workflows/release.yml`

**修改 1: Desktop 构建使用 `desktop` release**
```yaml
# 旧版本
- name: Build Backend Sidecar (Burrito)
  run: mix release cortex --overwrite

# 新版本
- name: Build Backend Sidecar (Burrito)
  run: mix release desktop --overwrite
```

**修改 2: 更新 Burrito 输出文件名**
```yaml
# 旧版本
burrito-bin: cortex_linux
burrito-bin: cortex_windows.exe
burrito-bin: cortex_macos_m1

# 新版本
burrito-bin: desktop_linux
burrito-bin: desktop_windows.exe
burrito-bin: desktop_macos_m1
```

**原因**: Burrito 根据 release 名称生成输出文件：
- `cortex` release → `burrito_out/cortex_*`
- `desktop` release → `burrito_out/desktop_*`

### 1.2 构建矩阵

**保持不变**，仍然构建 4 个产物：

| 产物 | Job | Release | 平台 |
|------|-----|---------|------|
| Server | `build-server` | `cortex` | Linux x86_64 |
| Desktop | `build-desktop` | `desktop` | Linux x86_64 |
| Desktop | `build-desktop` | `desktop` | Windows x86_64 |
| Desktop | `build-desktop` | `desktop` | macOS aarch64 |

---

## 二、完整构建流程

### 2.1 Server 版本（无变化）

```yaml
build-server:
  steps:
    - name: Build Server Binary (Burrito)
      run: mix release cortex --overwrite
    
    - name: Upload Server Artifact
      uses: actions/upload-artifact@v4
      with:
        name: cortex-server-linux-x86_64
        path: burrito_out/cortex_linux
```

**产物**: `cortex-server-linux-x86_64.tar.gz`  
**内容**: 纯 Elixir 后端二进制（无 GUI）

### 2.2 Desktop 版本（已更新）

```yaml
build-desktop:
  strategy:
    matrix:
      include:
        - label: Linux x86_64
          burrito-bin: desktop_linux
        - label: Windows x86_64
          burrito-bin: desktop_windows.exe
        - label: macOS aarch64
          burrito-bin: desktop_macos_m1
  
  steps:
    - name: Build Backend Sidecar (Burrito)
      run: mix release desktop --overwrite  # ← 改这里
    
    - name: Place sidecar binary for Tauri
      run: |
        mkdir -p src-tauri/binaries
        cp "burrito_out/${{ matrix.burrito-bin }}" \
           "src-tauri/binaries/cortex_backend-${{ matrix.sidecar-triple }}${{ matrix.sidecar-ext }}"
    
    - name: Build Tauri Desktop App
      run: cargo tauri build --target ${{ matrix.rust-target }}
```

**产物**:
- `cortex-desktop-linux-x86_64.tar.gz`
- `cortex-desktop-windows-x86_64.tar.gz`
- `cortex-desktop-macos-aarch64.tar.gz`

**内容**: Tauri GUI 应用 + Phoenix sidecar

---

## 三、验证清单

### 3.1 本地验证

在提交前，确保本地构建成功：

```bash
# 1. Server 版本
MIX_ENV=prod mix release cortex --overwrite
ls -lh burrito_out/cortex_linux

# 2. Desktop 版本
MIX_ENV=prod mix release desktop --overwrite
ls -lh burrito_out/desktop_linux
ls -lh burrito_out/desktop_windows.exe  # 如果在 Windows 上
ls -lh burrito_out/desktop_macos_m1     # 如果在 macOS 上
```

### 3.2 CI/CD 验证

**推送到 dev 分支测试**:
```bash
git checkout -b test/ex-tauri-ci
git add .github/workflows/release.yml
git commit -m "ci: update workflow for ExTauri integration"
git push origin test/ex-tauri-ci
```

**检查 GitHub Actions**:
1. 访问 `https://github.com/<your-repo>/actions`
2. 查看 `Release` workflow 运行状态
3. 确认 4 个 job 都成功：
   - ✅ `build-server`
   - ✅ `build-desktop (Linux x86_64)`
   - ✅ `build-desktop (Windows x86_64)`
   - ✅ `build-desktop (macOS aarch64)`

### 3.3 产物验证

**下载 artifacts**:
```bash
# 使用 GitHub CLI
gh run download <run-id>

# 或在 GitHub Actions 页面手动下载
```

**验证内容**:
```bash
# Server 版本
tar -tzf cortex-server-linux-x86_64.tar.gz
# 应包含: cortex_linux

# Desktop 版本（Linux）
tar -tzf cortex-desktop-linux-x86_64.tar.gz
# 应包含: deb/, appimage/, 等

# Desktop 版本（Windows）
tar -tzf cortex-desktop-windows-x86_64.tar.gz
# 应包含: msi/, nsis/Cortex_*_x64-setup.exe

# Desktop 版本（macOS）
tar -tzf cortex-desktop-macos-aarch64.tar.gz
# 应包含: dmg/, app/
```

---

## 四、常见问题

### 4.1 Burrito 找不到 release

**错误**:
```
** (Mix) expected a burrito release configured for the app :desktop in your mix.exs
```

**原因**: `mix.exs` 中没有 `desktop` release 配置

**解决**: 确认 `mix.exs` 包含：
```elixir
def releases do
  [
    cortex: [...],
    desktop: [...]  # ← 必须存在
  ]
end
```

### 4.2 Sidecar 文件名不匹配

**错误**:
```
cp: cannot stat 'burrito_out/cortex_linux': No such file or directory
```

**原因**: Workflow 中 `burrito-bin` 配置错误

**解决**: 确认 matrix 配置：
```yaml
burrito-bin: desktop_linux  # 不是 cortex_linux
```

### 4.3 Tauri 构建失败

**错误**:
```
Error: failed to bundle project: error running tauri_bundler
```

**原因**: Sidecar 二进制未正确放置

**解决**: 检查 `src-tauri/binaries/` 目录：
```bash
ls -lh src-tauri/binaries/
# 应包含: cortex_backend-x86_64-unknown-linux-gnu
#         cortex_backend-x86_64-pc-windows-msvc.exe
#         cortex_backend-aarch64-apple-darwin
```

---

## 五、发布流程

### 5.1 开发分支（dev）

**触发条件**: 推送到 `dev` 分支

**行为**:
- ✅ 构建所有 4 个产物
- ✅ 上传 artifacts
- ❌ 不创建 GitHub Release

**用途**: 测试构建流程

### 5.2 预发布分支（pre-release）

**触发条件**: 推送到 `pre-release` 分支

**行为**:
- ✅ 构建所有 4 个产物
- ✅ 创建 GitHub Pre-release
- ✅ Tag: `v0.1.39-pre.123`

**用途**: 内部测试版本

### 5.3 正式发布（main）

**触发条件**: 推送到 `main` 分支

**行为**:
- ✅ 构建所有 4 个产物
- ✅ 创建 GitHub Release
- ✅ Tag: `v0.1.39`

**用途**: 公开发布版本

---

## 六、产物说明

### 6.1 Server 版本

**文件**: `cortex-server-linux-x86_64.tar.gz`

**内容**:
```
cortex_linux  # 单个可执行文件
```

**使用**:
```bash
tar -xzf cortex-server-linux-x86_64.tar.gz
chmod +x cortex_linux
PHX_SERVER=true PORT=4000 ./cortex_linux
```

**适用场景**:
- Linux 服务器部署
- Docker 容器
- 无 GUI 环境

### 6.2 Desktop 版本（Linux）

**文件**: `cortex-desktop-linux-x86_64.tar.gz`

**内容**:
```
deb/
  Cortex_0.1.39_amd64.deb
appimage/
  Cortex_0.1.39_amd64.AppImage
```

**使用**:
```bash
# Debian/Ubuntu
sudo dpkg -i Cortex_0.1.39_amd64.deb

# 或使用 AppImage
chmod +x Cortex_0.1.39_amd64.AppImage
./Cortex_0.1.39_amd64.AppImage
```

### 6.3 Desktop 版本（Windows）

**文件**: `cortex-desktop-windows-x86_64.tar.gz`

**内容**:
```
msi/
  Cortex_0.1.39_x64_en-US.msi
nsis/
  Cortex_0.1.39_x64-setup.exe
```

**使用**:
```powershell
# 运行安装程序
.\Cortex_0.1.39_x64-setup.exe

# 或使用 MSI
msiexec /i Cortex_0.1.39_x64_en-US.msi
```

### 6.4 Desktop 版本（macOS）

**文件**: `cortex-desktop-macos-aarch64.tar.gz`

**内容**:
```
dmg/
  Cortex_0.1.39_aarch64.dmg
macos/
  Cortex.app/
```

**使用**:
```bash
# 打开 DMG
open Cortex_0.1.39_aarch64.dmg

# 拖拽到 Applications
```

---

## 七、回滚方案

如果新 workflow 有问题，可以快速回滚：

```bash
# 1. 恢复 workflow 文件
git checkout HEAD~1 .github/workflows/release.yml

# 2. 提交回滚
git add .github/workflows/release.yml
git commit -m "revert: rollback workflow to previous version"
git push origin dev

# 3. 或直接在 GitHub 上 revert commit
```

---

## 八、下一步

### 8.1 立即执行

1. **提交更改**:
```bash
git add .github/workflows/release.yml
git commit -m "ci: update workflow for ExTauri integration

- Change desktop build to use 'desktop' release
- Update burrito output filenames (desktop_* instead of cortex_*)
- Maintain all 4 build targets (1 server + 3 desktop)
"
git push origin dev
```

2. **监控构建**:
- 访问 GitHub Actions 页面
- 等待所有 job 完成（约 30-45 分钟）

3. **下载测试**:
```bash
# 下载 Windows 版本
gh run download <run-id> -n "cortex-desktop-Windows x86_64"

# 在 Windows 中测试
.\Cortex_0.1.39_x64-setup.exe
```

### 8.2 后续优化

1. **添加自动测试**: 在构建后运行基本功能测试
2. **优化缓存**: 减少构建时间
3. **并行构建**: 进一步加速 CI/CD

---

## 九、总结

### 已完成

- ✅ 更新 workflow 使用 `desktop` release
- ✅ 修正 Burrito 输出文件名
- ✅ 保持 4 个构建目标不变
- ✅ Server 版本构建流程不受影响

### 待验证

- ⏳ 推送到 dev 分支触发构建
- ⏳ 下载并测试 Desktop 版本
- ⏳ 确认 exe 名称包含 "Cortex"

### 预期结果

**构建时间**: 30-45 分钟  
**产物数量**: 4 个（1 Server + 3 Desktop）  
**exe 名称**: `Cortex_0.1.39_x64-setup.exe` ✅

---

**文档创建时间**: 2026-02-28  
**适用版本**: Cortex v0.1.39+

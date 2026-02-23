# GitHub Actions Runner 兼容性说明

## Windows Server 2025 兼容性问题

### 问题描述

GitHub Actions 最近将 `windows-latest` 更新到 Windows Server 2025，但 `erlef/setup-beam@v1` 还不支持这个版本。

**错误信息：**
```
Tried to map a target OS from env. variable 'ImageOS' (got win25), but failed.
If you're using a self-hosted runner, you should set 'env': 'ImageOS': ... 
to one of the following: ['ubuntu22', 'ubuntu24', 'win19', 'win22', 'macos13', 'macos14', 'macos15']
```

### 解决方案

#### 方案 1：使用明确的 Runner 版本（推荐）✅

不使用 `windows-latest`，而是明确指定版本：

```yaml
jobs:
  build:
    runs-on: windows-2022  # 明确使用 Windows Server 2022
```

**优点：**
- 稳定，不会因为 GitHub 更新而突然失败
- 不需要额外配置
- 兼容性最好

**缺点：**
- 需要手动更新版本号

#### 方案 2：设置 ImageOS 环境变量

```yaml
- name: Setup BEAM
  uses: erlef/setup-beam@v1
  with:
    elixir-version: "1.19.5"
    otp-version: "28.3.1"
  env:
    ImageOS: win22  # 强制使用 win22 配置
```

**优点：**
- 可以继续使用 `windows-latest`
- 灵活性高

**缺点：**
- 可能与实际 OS 不匹配
- 需要额外配置

#### 方案 3：等待 setup-beam 更新

等待 `erlef/setup-beam` 支持 Windows Server 2025。

**跟踪 Issue：**
https://github.com/erlef/setup-beam/issues

### 当前配置

我们采用了 **方案 1 + 方案 2 的组合**：

```yaml
matrix:
  include:
    - label: Windows x86_64
      os: windows-2022        # 明确版本
      
    - label: macOS aarch64
      os: macos-14            # 明确版本

# 同时设置 ImageOS 作为备用
- name: Setup BEAM (Official)
  uses: erlef/setup-beam@v1
  env:
    ImageOS: ${{ runner.os == 'Windows' && 'win22' || 'macos14' }}
```

### 支持的 Runner 版本

| Runner | ImageOS | setup-beam 支持 |
|--------|---------|----------------|
| ubuntu-22.04 | ubuntu22 | ✅ |
| ubuntu-24.04 | ubuntu24 | ✅ |
| windows-2019 | win19 | ✅ |
| windows-2022 | win22 | ✅ |
| windows-2025 | win25 | ❌ (不支持) |
| macos-13 | macos13 | ✅ |
| macos-14 | macos14 | ✅ |
| macos-15 | macos15 | ✅ |

### 推荐配置

```yaml
jobs:
  build:
    strategy:
      matrix:
        include:
          # Linux - 使用最新 LTS
          - os: ubuntu-22.04
          
          # Windows - 使用 2022 (稳定)
          - os: windows-2022
          
          # macOS - 使用 14 (Apple Silicon)
          - os: macos-14
    
    runs-on: ${{ matrix.os }}
```

### 何时可以使用 latest

当 `erlef/setup-beam` 更新支持 Windows Server 2025 后，可以改回：

```yaml
# 未来可以这样写
runs-on: windows-latest
```

检查支持状态：
```bash
# 查看 setup-beam 最新版本
https://github.com/erlef/setup-beam/releases
```

### 相关资源

- [GitHub Actions Runner Images](https://github.com/actions/runner-images)
- [erlef/setup-beam](https://github.com/erlef/setup-beam)
- [Windows Server 2025 Release Notes](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md)

### 更新日志

- **2026-02-24**: 修复 Windows Server 2025 兼容性问题
  - 将 `windows-latest` 改为 `windows-2022`
  - 将 `macos-latest` 改为 `macos-14`
  - 添加 ImageOS 环境变量作为备用方案

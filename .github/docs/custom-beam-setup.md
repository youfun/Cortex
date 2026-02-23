# 自定义 BEAM 环境配置说明

## 概述

本项目支持两种方式在 GitHub Actions 中配置 Erlang/Elixir 环境：

1. **官方 Action** (`erlef/setup-beam`) - 简单但版本选择有限
2. **自定义脚本** (`.github/scripts/setup-beam.sh`) - 灵活，支持最新版本

## 方案对比

| 特性 | 官方 Action | 自定义脚本 |
|------|------------|-----------|
| 安装速度 | 快（有缓存） | 快（预编译包） |
| 版本支持 | 有限 | 完整（Hex.pm 所有版本） |
| 跨平台 | ✅ Linux/macOS/Windows | ⚠️ 仅 Linux |
| 维护成本 | 低 | 中 |
| 缓存支持 | 内置 | 需手动配置 |

## 使用自定义脚本

### 1. 配置版本

在 workflow 文件中设置环境变量：

```yaml
env:
  OTP_VERSION: "28.3.1"      # Erlang/OTP 版本
  OTP_SHORT: "28"            # OTP 主版本号
  ELIXIR_VERSION: "1.19.5"   # Elixir 版本
  UBUNTU_VERSION: "22.04"    # Ubuntu 版本（必须匹配 runner）
```

### 2. 在 Job 中使用

```yaml
jobs:
  build:
    runs-on: ubuntu-22.04  # 必须匹配 UBUNTU_VERSION
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Custom BEAM
        run: |
          chmod +x .github/scripts/setup-beam.sh
          .github/scripts/setup-beam.sh
      
      - name: Cache BEAM
        uses: actions/cache@v4
        with:
          path: |
            ~/erlang_${{ env.OTP_SHORT }}
            ~/elixir_otp${{ env.OTP_SHORT }}
          key: beam-${{ runner.os }}-otp${{ env.OTP_VERSION }}-elixir${{ env.ELIXIR_VERSION }}
```

## 版本兼容性

### 支持的 Ubuntu 版本

Hex.pm 提供以下 Ubuntu 版本的预编译包：
- Ubuntu 20.04
- Ubuntu 22.04
- Ubuntu 24.04

### 支持的 OTP 版本

查看可用版本：https://builds.hex.pm/builds/otp/

当前推荐：
- **OTP 28.3.1** - 最新稳定版
- **OTP 27.1** - 长期支持版
- **OTP 26.2** - 兼容性最好

### 支持的 Elixir 版本

查看可用版本：https://github.com/elixir-lang/elixir/releases

当前推荐：
- **Elixir 1.19.5** - 最新稳定版（需要 OTP 26+）
- **Elixir 1.17.3** - 广泛兼容（OTP 25-27）
- **Elixir 1.14.5** - 旧项目兼容（OTP 23-26）

## 注意事项

### 1. Runner 版本匹配

⚠️ **重要**：`runs-on` 必须与 `UBUNTU_VERSION` 匹配

```yaml
# ✅ 正确
env:
  UBUNTU_VERSION: "22.04"
jobs:
  build:
    runs-on: ubuntu-22.04

# ❌ 错误 - 版本不匹配
env:
  UBUNTU_VERSION: "22.04"
jobs:
  build:
    runs-on: ubuntu-latest  # 可能是 24.04
```

### 2. OTP 与 Elixir 兼容性

确保 Elixir 版本支持你选择的 OTP 版本：

| Elixir | 最低 OTP | 最高 OTP |
|--------|---------|---------|
| 1.19.x | 26 | 28+ |
| 1.17.x | 25 | 27 |
| 1.14.x | 23 | 26 |

### 3. Windows/macOS 支持

自定义脚本目前仅支持 Linux。对于 Windows/macOS，建议使用官方 action：

```yaml
- name: Setup BEAM (Windows/macOS)
  if: runner.os != 'Linux'
  uses: erlef/setup-beam@v1
  with:
    elixir-version: ${{ env.ELIXIR_VERSION }}
    otp-version: ${{ env.OTP_VERSION }}
```

## 性能优化

### 1. 启用缓存

```yaml
- name: Cache BEAM
  uses: actions/cache@v4
  with:
    path: |
      ~/erlang_${{ env.OTP_SHORT }}
      ~/elixir_otp${{ env.OTP_SHORT }}
    key: beam-${{ runner.os }}-otp${{ env.OTP_VERSION }}-elixir${{ env.ELIXIR_VERSION }}
    restore-keys: |
      beam-${{ runner.os }}-otp${{ env.OTP_VERSION }}-
```

### 2. 缓存依赖

```yaml
- name: Cache Mix Dependencies
  uses: actions/cache@v4
  with:
    path: |
      deps
      _build
    key: mix-${{ runner.os }}-${{ hashFiles('**/mix.lock') }}
    restore-keys: |
      mix-${{ runner.os }}-
```

### 3. 并行构建

```yaml
strategy:
  matrix:
    include:
      - os: ubuntu-22.04
        otp: "28.3.1"
        elixir: "1.19.5"
      - os: ubuntu-22.04
        otp: "27.1"
        elixir: "1.17.3"
```

## 故障排查

### 问题：下载失败

```
wget: unable to resolve host address 'builds.hex.pm'
```

**解决方案**：检查网络连接或使用镜像

### 问题：版本不匹配

```
ERROR: Elixir 1.19.5 requires Erlang/OTP 26 or later
```

**解决方案**：更新 OTP 版本或降低 Elixir 版本

### 问题：缓存未生效

**解决方案**：确保缓存 key 包含版本号，并且路径正确

## 示例 Workflow

完整示例见：`.github/workflows/build-release-custom-beam.yml`

## 参考资源

- [Hex.pm OTP Builds](https://builds.hex.pm/builds/otp/)
- [Elixir Releases](https://github.com/elixir-lang/elixir/releases)
- [Elixir Compatibility](https://hexdocs.pm/elixir/compatibility-and-deprecations.html)
- [erlef/setup-beam](https://github.com/erlef/setup-beam)

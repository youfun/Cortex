# 测试分支说明

## test-custom-beam 分支

这是一个专门用于测试自定义 BEAM (Erlang/Elixir) 环境配置的分支。

### 🎯 目的

测试在 GitHub Actions 中使用预编译的 Erlang/Elixir 包，而不是官方的 `erlef/setup-beam` action。

### 🚀 自动触发的 Workflows

推送到此分支会自动触发以下 workflows：

1. **Test Custom BEAM Setup** - 快速验证测试
   - 验证 Erlang/Elixir 安装
   - 测试 Mix 编译
   - 对比官方 action 的结果
   - 运行时间：~5 分钟

2. **Build Release (Custom BEAM)** - 完整构建测试
   - 构建服务器二进制文件
   - 构建桌面应用（Linux/Windows/macOS）
   - 运行时间：~20-30 分钟

### 📊 查看运行结果

访问 GitHub Actions 页面查看运行状态：
https://github.com/youfun/Cortex/actions

### 🔧 测试配置

当前测试的版本：
- **Erlang/OTP**: 28.3.1
- **Elixir**: 1.19.5
- **Ubuntu**: 22.04

### 📝 修改测试配置

如果需要测试其他版本，修改 workflow 文件中的环境变量：

```yaml
env:
  OTP_VERSION: "28.3.1"      # 修改 OTP 版本
  OTP_SHORT: "28"            # 修改 OTP 主版本号
  ELIXIR_VERSION: "1.19.5"   # 修改 Elixir 版本
  UBUNTU_VERSION: "22.04"    # 修改 Ubuntu 版本
```

### ✅ 验证成功后

如果测试通过，可以：

1. **合并到 main 分支**
   ```bash
   git checkout main
   git merge test-custom-beam
   git push origin main
   ```

2. **或者创建 Pull Request**
   访问：https://github.com/youfun/Cortex/pull/new/test-custom-beam

### 🗑️ 清理测试分支

测试完成后可以删除：

```bash
# 删除本地分支
git branch -D test-custom-beam

# 删除远程分支
git push origin --delete test-custom-beam
```

### 📚 相关文档

- [自定义 BEAM 配置说明](.github/docs/custom-beam-setup.md)
- [安装脚本](.github/scripts/setup-beam.sh)
- [测试 Workflow](.github/workflows/test-beam-setup.yml)
- [构建 Workflow](.github/workflows/build-release-custom-beam.yml)

### 🐛 故障排查

如果 workflow 失败，检查：

1. **版本兼容性** - 确保 Elixir 版本支持选择的 OTP 版本
2. **Ubuntu 版本** - 确保 `runs-on` 与 `UBUNTU_VERSION` 匹配
3. **下载链接** - 确保 Hex.pm 有对应版本的预编译包
4. **缓存问题** - 可以在 Actions 页面清除缓存重试

查看详细日志：
https://github.com/youfun/Cortex/actions

### 💡 提示

- 第一次运行会下载并安装 BEAM，需要 2-3 分钟
- 后续运行会使用缓存，只需要几秒钟
- 可以手动触发 workflow 测试（Actions 页面 -> Run workflow）

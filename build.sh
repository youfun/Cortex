#!/usr/bin/env bash

set -e

echo "========================================"
echo " Cortex 构建脚本 (WSL 单文件版)"
echo "========================================"

# 1. 环境
MIX_ENV=${MIX_ENV:-prod}
echo "当前环境: $MIX_ENV"

# 2. Burrito 输出路径（按你项目实际情况改）
BACKEND_SRC="burrito_out/cortex_windows.exe"

# 3. 同步版本号
echo ""
echo "🔄 同步版本号...注意版本号不改，可能会导致安装后缓存不更新从而软件实际还是旧版本"

if [[ ! -f mix.exs ]]; then
  echo "❌ 未找到 mix.exs"
  exit 1
fi

VERSION=$(grep -E 'version:\s*"[0-9.]+"' mix.exs | head -1 | sed -E 's/.*"([0-9.]+)".*/\1/')

if [[ -z "$VERSION" ]]; then
  echo "❌ 无法解析版本号"
  exit 1
fi

echo "检测到 Mix 版本: $VERSION"

# 4. 构建 Elixir Release
echo ""
echo "📦 构建 Elixir Release (Burrito)..."

export MIX_ENV=$MIX_ENV

echo "➡ 获取依赖"
mix deps.get

echo "➡ 编译项目"
mix compile

echo "➡ 编译前端资源"
mix assets.setup
mix assets.deploy

echo "➡ 生成单文件二进制"
mix release cortex --overwrite

# 5. 检查输出
echo ""
if [[ -f "$BACKEND_SRC" ]]; then
  echo "🎉 构建完成！版本: $VERSION"
  echo "单文件二进制位于: $BACKEND_SRC"
else
  echo "⚠ 未在 $BACKEND_SRC 找到输出文件"
  exit 1
fi

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

# 3. 同步版本号（自动递增）
echo ""
echo "🔄 自动递增版本号..."

if [[ ! -f mix.exs ]]; then
  echo "❌ 未找到 mix.exs"
  exit 1
fi

# 读取当前基础版本
CURRENT_VERSION=$(grep -oP 'base_version = "\K[^"]+' mix.exs)

if [[ -z "$CURRENT_VERSION" ]]; then
  echo "❌ 无法解析版本号"
  exit 1
fi

# 解析并递增 patch 版本
IFS='.' read -r major minor patch <<< "$CURRENT_VERSION"
new_patch=$((patch + 1))
NEW_VERSION="$major.$minor.$new_patch"

# 更新 mix.exs
sed -i "s/base_version = \"$CURRENT_VERSION\"/base_version = \"$NEW_VERSION\"/" mix.exs

echo "版本号已更新: $CURRENT_VERSION → $NEW_VERSION"

# 获取 Git 哈希
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
FULL_VERSION="$NEW_VERSION+$GIT_HASH"

echo "完整版本: $FULL_VERSION"

VERSION=$NEW_VERSION

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

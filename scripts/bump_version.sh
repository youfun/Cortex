#!/usr/bin/env bash
# 自动递增版本号脚本

set -e

MIX_FILE="mix.exs"

# 读取当前版本
current_version=$(grep -oP 'base_version = "\K[^"]+' "$MIX_FILE")

if [ -z "$current_version" ]; then
  echo "❌ 无法读取当前版本号"
  exit 1
fi

# 解析版本号
IFS='.' read -r major minor patch <<< "$current_version"

# 递增 patch 版本
new_patch=$((patch + 1))
new_version="$major.$minor.$new_patch"

# 更新 mix.exs
sed -i "s/base_version = \"$current_version\"/base_version = \"$new_version\"/" "$MIX_FILE"

echo "✅ 版本号已更新: $current_version → $new_version"
echo "📝 请提交更改: git add mix.exs && git commit -m 'chore: bump version to $new_version'"

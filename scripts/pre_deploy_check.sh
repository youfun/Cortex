#!/usr/bin/env bash
# 部署前预检脚本
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== [1/4] 编译检查 ==="
# 使用 test 环境编译，确保测试相关的内容被加载
MIX_ENV=test mix compile

echo ""
echo "=== [2/4] 静态代码分析 (Credo) ==="
mix credo --strict

echo ""
echo "=== [3/4] BDD 门禁检查 ==="
./scripts/bdd_gate.sh

echo ""
echo "=== [4/4] 依赖检查 ==="
mix deps.unlock --unused

echo ""
echo "=== 预检全部通过！可以直接交付或部署 ==="

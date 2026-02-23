# 总结：BDD Instructions V1 拆分（2026-02-21）

## 变更摘要
- `Cortex.BDD.Instructions.V1` 改为 dispatcher，聚合子模块能力与指令执行。
- 新增子模块：
  - `lib/cortex/bdd/instructions/v1/signal.ex`
  - `lib/cortex/bdd/instructions/v1/agent.ex`
  - `lib/cortex/bdd/instructions/v1/tool.ex`
  - `lib/cortex/bdd/instructions/v1/memory.ex`
  - `lib/cortex/bdd/instructions/v1/permission.ex`
  - `lib/cortex/bdd/instructions/v1/session.ex`
  - `lib/cortex/bdd/instructions/v1/helpers.ex`
- 新增 BDD 场景：`test/bdd/dsl/bdd_instructions_v1_split.dsl`

## 测试与验证
- `./scripts/bdd_gate.sh` 失败：DSL 解析报错（现存文件 `test/bdd/dsl/phase1_p0.dsl` 第 26 行）。
- `mix format` 失败：Mix PubSub 启动时 `eperm`。

## 备注
- `.github` 下未发现引用 `lib/cortex/bdd/instructions/v1.ex` 的说明文档需要更新。

# BDD: permission.request payload 字段覆盖

## 变更摘要
- 新增 BDD 场景验证 `permission.request` 信号携带 `command/reason/tool` 字段。
- 将 `.bddc.toml` 的 `docs_root` 调整为 `test/bdd/dsl` 以避免解析错误。

## 主要文件
- `docs/bdd/20260221_permission_request_payload.dsl`
- `test/bdd/dsl/permission_request_payload.dsl`
- `.bddc.toml`

## 测试/门禁
- `mix compile`：通过（存在 Mimic 相关 warning）。
- `./scripts/bdd_gate.sh`：编译通过，`mix test` 失败（Mix.PubSub 启动 `:eperm`）。

## 备注
- 当前环境权限限制导致 `mix test` 失败；需提升权限或调整运行环境。

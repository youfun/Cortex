# 编码准则与工具

## 面向信号的 Phoenix 工作
- 遵循 `AGENTS.md` 中描述的架构：跨边界通信必须走 `SignalHub`，状态变更后最多发射一条通知信号，模块内部助手不要重复发信号。
- 与 `docs/` 中的计划保持一致，任何新计划或差距分析都要写进 `docs/`，以便长期记录与审计。
- 把 Phoenix/LiveView Web 层（`lib/cortex_web/`、LiveView、组件与路由 Plug）当作主要入口点，让 context 模块（`lib/cortex/`）承担领域逻辑。

## 构建与依赖
- 用 `mix deps.get` 获取依赖、`mix compile` 编译；若资源文件改动，请先进入 `assets/` 运行 `npm install`（或 `npm ci`），再执行 `npm run deploy`，最后运行 `mix phx.digest` 重新生成静态指纹。
- 只有在工单明确要求更新 schema 时，才在仓库根的 mix 环境中运行 `mix ecto.create/migrate`；否则不要动数据迁移。
- 手动运行时可用 `mix phx.server` 或 `iex -S mix phx.server`；避免直接编辑服务器进程树，信号架构中由 `SessionSupervisor` 统一管理监督。

## 测试与质量
- 运行 `mix test` 完成单元/集成测试；若需要真实 API 或外部资源，使用 `LIVE=true mix test`。
- 代码变更后执行 `mix format` 与 `mix quality`（Credo + Dialyzer）确保风格统一。
- 信号流应当通过发射信号并断言下游副作用（数据库写入、消息发送）来验证，而不是窥探 GenServer 等内部状态。

## 工具与文档
- 除非有充分理由，否则尽量避免引入新依赖，HTTP 客户端优选 `Req`。
- Skills 的指令写在 `skills/<name>/SKILL.md` 里，SkillsWatcher 会热加载并在变更时发出 `skill.loaded` 或 `skill.error`。
- 任何架构变更都要写进 `docs/` 下的文档，并在 PR 描述里链接这些文档，让审阅者看到更新后的计划。

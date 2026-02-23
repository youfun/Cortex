# Cortex 的 API 选择规范

- `lib/cortex_web/router.ex` 与 Phoenix LiveView 会转发到 `lib/cortex/` 下的 context 模块。优先调用 context 函数，而不要直接跨命名空间调用，保持 Web 层轻量，让 context 负责 `Repo` 与 `SignalHub` 交互。
- 使用现有领域边界内的 context 模块，如 `Cortex.Memory`、`Cortex.SignalHub`、`Cortex.AgentSession` 与 `Cortex.Coding`。每个 context 都保持返回 `{:ok, result}` 或 `{:error, reason}`，便于下游信号处理器用模式匹配处理。
- 对于 HTTP 请求，按 `AGENTS.md` 的建议统一使用 `Req`，避免引入新 HTTP 库；将 HTTP 工作流封装在 context 函数中，便于测试替换。
- 在扩展信号总线时，通过 `SignalHub.emit/3` 传入所有必需元数据（`provider`、`event`、`action`、`actor`、`origin`），并把业务数据放在 `payload` 里，供 `SignalRecorder` 写入 `history.jsonl`。

更新 API 时，可参考 `docs/JIDO_MEMORY_TESTING_GUIDE.md` 与 `docs/CREDO_COMPLEXITY_REFACTOR_2026-02-12.md` 中的领域约束。

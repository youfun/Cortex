# Agent 工作流

这篇文档说明 Codex Agent 在动手修改源码前，如何将请求转成 `bd` 工作项。

## 1. 获取与上下文
- 先阅读 `AGENTS.md`、`.github/copilot-instructions.md` 与 `.github/KnowledgeBase/Index.md`，了解当前架构与目标。
- 理解需求后，在仓库根运行 `bd ready --json`，领取一个可负责的任务。记下返回的 `id`，然后用 `bd update <id> --status in_progress --json` 将状态改为 `in_progress`。
- 如果 `bd ready` 显示没有现成任务，可通过 `bd new --json` 创建，写一个简洁的 `title`、借最新 prompt/文档整理的 `description`，并附上相关标签。备注说明该任务来自当前用户请求。

## 2. 从 prompt 或文档生成任务
- 当 prompt 明确列出步骤或引用具体文档（例如 “按 `Copilot_Execution.md`”）时，将要做的工作用一两句话概括，并把这段描述放在 `bd new --json` 的 `description` 字段。
- 列出最关键的引用（文档名、信号规范、目标文件等），方便评审追溯。
- 任务创建后，在回复中回显 `id` 与 `title`，让用户清楚哪个 `bd` 任务涵盖了改动。

## 3. 持续更新与关闭
- 在工作过程中保持任务活跃：若有新发现，运行 `bd update <id> --status in_progress --json`；当代码准备好时，用 `bd update <id> --status review --json`（或 `--status done`）添加完成说明。
- 把任何阻塞问题记录为 `bd` 任务的评论以保持透明。
- 在修改与测试成功后，运行 `bd close <id> --reason "..." --json` 并在最终总结中说明任务已关闭。

遵循这一流程可确保知识库、`bd` 待办单与仓库状态保持一致。

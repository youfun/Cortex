# GitHub Copilot Instructions for Cortex

## 目的（Project Overview）

本文件定义在 Cortex 工作区内使用 Copilot/AI 助手的团队约定与工作流程。Cortex 是一个基于 BEAM 的信号驱动 agent 平台，采用 Phoenix/LiveView、Elixir 以及多个自研子系统（SignalHub、Skills、Agent 等）。

## 技术栈（Tech Stack）

- 语言: Elixir
- Web: Phoenix / LiveView
- HTTP 客户端: `Req`（项目中部分组件使用）
- 测试: `mix test`（支持 fixture 与 `LIVE=true` 的集成测试）
- 静态检查: `mix credo`, `mix dialyzer`
- 代码格式化: `mix format`

## 开发与代码规范（Coding Guidelines）

- 在函数体内部**不要添加行内注释**；保持实现清晰并使用有意义的函数名。
- 优先使用**模式匹配**而不是复杂条件分支。
- 函数返回约定：使用 `{:ok, result}` / `{:error, reason}` 元组。
- 提交前运行：`mix format` 和 `mix quality`（`mix quality` 运行 Credo / Dialyzer / 其他质量检查）。

## 测试（Testing）

- 本地单元/集成测试：`mix test`
- 需要真实外部资源（live API）时：`LIVE=true mix test`
- 如果测试依赖 fixture，优先使用项目内的 fixture 管理工具（见 `test/` 目录示例）。

## 任务跟踪（Issue Tracking）



## 信号总线与架构约束（SignalHub & Architecture Rules）

- 项目以 SignalHub 为跨组件通信总线，所有跨边界事件应遵循信号组装规范：必须包含 `provider`, `event`, `action`, `actor`, `origin` 等字段。
- 模块内部可以直接调用函数；对外通知使用信号。读操作不产生信号，写操作只发一次结果通知以避免反馈环路。
- 新增技能（Skills）请把说明写入 `skill/<name>/SKILL.md`，SkillWatcher 会自动热加载。

## 安全与沙箱（Security）

- 文件操作仅限于仓库根路径之内。
- 高风险 shell 命令（`rm`, `git push`, `npm install` 等）在自动化脚本中应受审计并需要显式批准。

## 贡献与工作流（Workflow）

1. 阅读并理解 `AGENTS.md` 与本文件。
<!-- 2. 使用 `bd` 领取任务并更新状态。 -->
3. 在独立分支上实现变更，运行 `mix test` 与 `mix quality` 并修复发现的问题。
4. 格式化代码：`mix format`。
<!-- 5. 提交并关闭 `bd` 任务；确保 `.beads/issues.jsonl` 与变更一起提交。 -->

## 事前检查清单（Pre-checks before coding）

- 已阅读 `AGENTS.md` 与 `docs/` 下相关设计文档。
<!-- - 找到并绑定 `bd` 任务。 -->
- 运行 `mix deps.get`（如需要）并确认测试能在本地通过。

## 编写合适的 Copilot/AI 提示（How to prompt AI in this repo）

- 在请求代码变更时，附上目标模块/文件路径与简单的复现步骤。
- 如果请求对系统行为有影响（信号格式、事件名、origin 字段），请提供示例信号及预期处理流程。

---

**参考**: 更多架构与信号规范见 [AGENTS.md](AGENTS.md)、`.github/Guidelines` 以及 `.github/KnowledgeBase` 中的文档，补充细节可同时参考 `docs/` 目录下的文件。

请在开始任何较大改动前阅读并遵循本文件中的流程与 `AGENTS.md`。

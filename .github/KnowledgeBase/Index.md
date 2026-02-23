# Cortex 知识库

## 指南
- 先阅读 `.github/Coding Guidelines and Tools.md` 与 `AGENTS.md`，了解信号优先文化、五大工具，以及要在 `docs/` 下记录计划的要求。
- 涉及多个领域的问题，务必先在 `docs/` 中用关键词（如 “SignalHub”、“SessionSupervisor”、“memory”）搜索，避免无谓地重新设计。
- 技能文档应保留在 `skills/<name>/SKILL.md`，不要直接修改 `deps/`、`_build/` 或生成的发布产物。
- 构建与发布脚本（`build.sh`、`build-on-win.exs`、`build_studio.bat`、`build_bcrypt_elixir_at_win.bat`）的说明见 [构建与发布流程](./KB_Jido_Studio_Building.md)，涵盖 WSL/Linux、Windows 以及 bcrypt/vix 辅助脚本。
- 将 prompt 转成 `bd` 任务时，请遵循 `.github/KnowledgeBase/KB_Agent_Task_Workflow.md`，其中说明何时执行 `bd ready`、如何使用 `bd new`，以及如何保持工单状态的更新。

## 项目：Cortex
### API 选择
- `lib/cortex_web/router.ex` 与 `lib/cortex_web/` 下的 LiveView 是 UI 驱动行为的入口；路由与事件输入应委托给 `lib/cortex/` 内的 context 函数。
- 使用 context 模块（如 `Cortex.Memory`、`Cortex.SignalHub`、`Cortex.AgentSession`）封装领域逻辑，并统一返回 `{:ok, result}` 或 `{:error, reason}`。
- 所有跨组件通知统一通过 `SignalHub.emit/3`，携带 `provider`、`event`、`action`、`actor` 与 `origin` 元数据以保持信号可追踪。

[API 说明](./KB_Jido_Studio_Choosing_APIs.md)

### 设计说明
- `KB_Memory_History_Architecture.md` 描述了内存子系统的当前状态，包括运行的进程（Store、WorkingMemory、Subconscious、Consolidator、Preconscious）及其信号。
- `SignalHub` 协调多通道（UI、webhook、agent），确保它们都接收到 `{:signal, %Jido.Signal{}}` 的规范投递。
- Skills 位于 `skills/`，`SkillsWatcher` 会发出生命周期信号（`skill.loaded`、`skill.error`），用于观测与调试。

[设计说明](./KB_Memory_History_Architecture.md)

### 安全
- `docs/AGENT_SESSION_MANAGER_SECURITY_REVIEW.md` 分析 ASM 安全策略并映射到 Cortex 的改进建议。

## 经验与学习
- 阅读 `docs/analysis-llm-context-sources.md`，了解如何整理 LLM 上下文，并区分哪些内容写入 `history.jsonl` 与 `llm_context`。

# 在线手册摘录
- `docs/KB_USAGE_GUIDE.zh-CN.md` 汇总了 Phoenix + Elixir 工具链的现场参考。
- 研究信号驱动内存模式时，可参考 `docs/JIDO_MEMORY_TESTING_GUIDE.md` 与 `docs/JIDO_MEMORY_REFINEMENT_PLAN.md`。

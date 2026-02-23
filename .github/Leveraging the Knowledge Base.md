# 利用知识库

- Cortex 的权威知识库位于 `docs/`，以及你正在建设的 `.github/KnowledgeBase` 目录。请阅读 `docs/CORTEX_REWRITE_PLAN_V3_FINAL.md`、`docs/JIDO_MEMORY_SYSTEM_PLAN.md` 与 CAPABILITY 系列文档，了解当前的信号与记忆工作。
- 在做设计或编码决策前，先在 `docs/` 中搜索涉及的子系统（例如处理 memory 时查 `docs/JIDO_MEMORY_TESTING_GUIDE.md`，涉及安全/质量优先级时查 `docs/CREDO_COMPLEXITY_REFACTOR_2026-02-12.md`）。
- 把 `.github/KnowledgeBase/Index.md` 当作快速参考，查找指南、API 选择与设计说明；每个主题都链向更完整的 `docs/` 文档。
- 保持知识库活跃：实现工单过程中若发现缺口，请新增或更新对应的 `docs/` 文档，在 `.github/KnowledgeBase/Index.md` 中注册，并在 PR 中提及以便审计。

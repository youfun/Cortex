# 知识库：Taskctl (Task Orchestration CLI)

Taskctl 是一个基于 Rust 开发的任务编排工具，支持任务的依赖关系管理（DAG）、校验及可视化，特别适用于 Agent 的任务规划。

## 核心功能
- **依赖管理**：通过 `blockedBy` 和 `blocks` 定义任务间的先后顺序。
- **DAG 校验**：自动检测循环依赖、缺失目标或非法的状态流转。
- **任务过滤**：通过 `ready` 命令识别当前环境下哪些任务已满足执行条件。
- **可视化**：生成 ASCII 图表或 JSON 结构的 DAG，方便人类审计和机器执行。

## 常用命令
```bash
# 创建任务并定义依赖
taskctl --store tasks.json create --subject "Refactor Auth" --add-blocks "Update Docs"

# 更新任务状态
taskctl --store tasks.json update --task-id <ID> --status in-progress

# 列出当前可执行的任务
taskctl --store tasks.json ready

# 查看任务依赖图 (ASCII)
taskctl --store tasks.json dag-ascii

# 校验 DAG 完整性
taskctl --store tasks.json validate
```

## Skill 位置
- **Agent Skill**: `docs/Cli-master/skills/orchestration/taskctl/SKILL.md`

## 在 Cortex 中的应用
作为 Agent 的“大脑存档”。Agent 在处理复杂请求时，应先使用 `taskctl` 建立任务计划，通过 `dag-ascii` 向人类开发者展示规划路径，并在执行过程中同步状态。

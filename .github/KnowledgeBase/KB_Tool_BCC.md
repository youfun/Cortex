# 知识库：BCC (Backend Compiler)

BCC 是一个多功能后端编译器，旨在辅助开发、自动化生成业务逻辑以及分析现有代码架构。

## 核心功能
- **代码生成 (`compile`)**：将 YAML 格式的业务定义编译为 Elixir 源码 (`.ex`)。支持 Pass Pipeline 优化。
- **源码提取 (`extract`)**：将现有源码（Elixir/TypeScript/PHP）提取为 JSON 结构的 `FileRecord`，便于分析。
- **链路追踪 (`trace`)**：审计设计文档与代码实现之间的覆盖关系。
- **缺陷修复 (`bugfix`)**：从 Git 历史中分析并提取导致 Bug 的 BDD 场景，实现“错误驱动开发”。

## 常用命令
```bash
# 从 YAML 生成 Elixir 模块
bcc compile service.yaml --dry-run

# 提取源码 AST 信息
bcc extract sample_service.ex --mode ast

# 审计项目追踪状态
bcc trace status src_dir docs_dir

# 从 Git 历史提取 BDD 修复场景
bcc bugfix /path/to/repo -o output/ --lang elixir
```

## Skill 位置
- **源码目录**: `docs/Cli-master/compiler/bcc`
- *注：当前该工具主要作为底层引擎，部分功能通过 Taskctl 编排调用。*

## 在 Cortex 中的应用
用于 Agent 分析大型遗留代码库（通过 `extract`）或根据设计草图快速生成业务逻辑骨架。

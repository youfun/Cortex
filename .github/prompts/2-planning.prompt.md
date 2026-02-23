# 任务迭代规划 (BDD-Driven Iteration Planning)

- **核心规约**：查阅 `.github/copilot-instructions.md` 和 `AGENTS.md` 获取全局准则。
- **架构参考**：必须深入分析 `.github/KnowledgeBase/` 下的文档（从 `Index.md` 开始），以获取项目特定的通信协议、数据模型和子系统边界说明。
- **专家规范**：遵循 `.github/Guidelines/ElixirStyleGuide.md` 进行地道化编程设计。
- **工作流**：必须执行 `.agent/prompts/feature_iteration.md` 定义的 BDD 任务迭代流程。

## 目标与约束

- **核心目标**：根据用户提出的任务目标或当前需要解决的问题，在 `docs/plans/` 目录下产出一个高标准、可执行的蓝图（文件名应根据任务内容分析并命名，格式如 `YYYYMMDD_task_description_planning.md`）。
- **执行逻辑**：此文档是后续编码实施的唯一指导。必须坚持“规划先行，按计划执行”的原则。
- **编辑权限**：你只能编辑该规划文档，用于记录和更新迭代方案。

## 规划文档结构要求

- 文件应以 `# !!!PLANNING!!!` 开头。
- `# UPDATES`：记录任务过程中发生的变更或用户的新反馈。
- `# ARCHITECTURAL ANALYSIS`：引用 Knowledge Base 中的规范，分析本次改动如何契合项目架构。
- `# TASK GRAPH (DAG)`：使用 `taskctl dag-ascii` 生成的任务依赖图，明确执行路径。
- `# BDD SPECIFICATION`：展示将在 `docs/bdd/` 下编写或更新的 DSL 场景预览。
- `# AFFECTED MODULES & FILES`：受影响的文件及其在系统中的角色。
- `# EXECUTION PLAN`：包含具体代码实现预览的详细步骤。
- `# VERIFICATION PLAN`：定义验收标准和测试命令。

## 第 1 步：分析与对齐 (Discovery)

- **理解任务**：深入分析用户的原始请求及当前的代码上下文（使用 `bcc` 或 `read_file`）。
- **查阅知识库**：识别项目特有的设计模式。如果涉及组件间通信，应在规划中明确符合项目规范的交互契约（如元数据字段、事件命名等）。
- **任务管理**：使用 `taskctl` 初始化迭代任务并定义明确的依赖关系。

## 第 2 步：行为定义 (Specification)

- **DSL 预览**：编写能体现功能价值或复现 Bug 的 BDD 场景预览。确保指令集与项目当前的域语言定义一致。
- **验证方案**：规划如何通过 `bddc check` 验证行为定义，并在 implementation 阶段作为守门员。

## 第 3 步：Elixir 专家级实现设计

在规划的具体步骤（`## STEP X`）中，预览代码必须遵循：
- **一致性布局**：严格遵守 Elixir 物理布局规范（moduledoc -> compiler directives -> struct/schema -> API -> callbacks -> private）。
- **地道实现**：
  - 模式匹配优先，严禁在函数体内堆砌复杂的 `if/else`。
  - 管道操作必须清晰，严禁将管道结果直接送入控制流逻辑。
  - 谓词和危险函数的命名必须符合 `?` 和 `!` 规范。
- **防御性逻辑**：结合项目知识库中的安全指南，规划对边界情况的处理。

## 第 4 步：质量红线与闭环

- **自动化验证**：计划中必须包含 `mix compile`、`mix format` 和项目特定的质量检查命令。
- **验收交付**：确保规划中定义的每一个步骤都是原子化的且可验证的。
- **标记完成**：在规划文档末尾添加 `# !!!FINISHED!!!`，表示 Agent 已准备好按此计划开始执行。

## 测试策略原则：BDD 主导，Unit Test 按需补充

规划文档的 `# VERIFICATION PLAN` 中，测试策略必须遵循以下分层原则，避免 BDD 与 Unit Test 重复验证同一行为：

1. **BDD 场景 (主)**：所有可从用户/系统视角描述的行为契约，必须且仅通过 BDD 场景验证。这是核心验收标准。
2. **Unit Test (补充)**：仅在以下情况补充少量单元测试——
   - **组合爆炸的边界 case**：如 AST 解析需要覆盖语法错误回退、嵌套模块、复杂宏展开等大量排列组合，用 BDD 描述过于冗长。
   - **纯算法/数据变换**：无副作用的纯函数逻辑（如 Token 估算公式、权重排序算法），BDD 场景粒度太粗无法精确断言。
3. **禁止重复**：如果一个行为已被 BDD 场景覆盖，不得再为同一行为编写 Unit Test。

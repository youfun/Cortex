---
name: bddc
description: 行为驱动开发编译器 (BDDC)。使用此技能通过 DSL 管理 BDD 测试，该 DSL 可编译为 ExUnit 测试。包括从 .dsl 文件生成测试、验证指令集以及通过 lint 确保测试质量。
---

# BDDC 技能 (行为驱动开发编译器)

此技能支持“提案者-执行者 (Proposer-Executor)”工作流，用于高质量的行为驱动测试。它使用自定义 DSL 描述业务场景，并将其编译为标准的 ExUnit 集成测试。

## 核心方法论：DSL + BDDC

1.  **DSL (领域特定语言)**：编写在 `.dsl` 文件中的人类可读场景。
2.  **指令规范 (Instruction Spec)**：一个正式契约（JSON/Elixir map），定义了可用的 `Given`、`When` 和 `Then` 步骤，包括它们的参数和类型。
3.  **编译器 (bddc)**：根据规范验证 DSL 文件并生成 ExUnit 测试代码的工具。
4.  **运行时 (Runtime)**：项目特定的调度器，负责执行每个指令的实际逻辑。

## 工具执行策略 (Tool Execution Strategy)

为了保证跨环境兼容性，项目在 `.github/tools/` 存放了预编译的二进制文件。Agent 应遵循以下逻辑：
1. **优先使用本地二进制路径**：在 Linux 环境下，直接使用 `.github/tools/bddc-linux-x86_64` 和 `.github/tools/taskctl-linux-x86_64`。
2. **路径规约与配置**：
   - **DSL 存放**：默认存放于 `test/bdd/dsl/`（避免放在 `docs/` 下被编译器错误扫描）。
   - **指令定义**：存放于 `priv/bdd/instructions_v1.exs`。
   - **路径修改**：通过根目录的 `.bddc.toml` 进行配置。
     ```toml
     [global]
     in = "test/bdd/dsl"           # DSL 输入目录
     out = "test/bdd_generated"    # 测试代码输出目录
     docs_root = "test/bdd"        # 文档根目录（影响模块命名）
     instructions = "priv/bdd/instructions_v1.exs"
     ```
3. **环境预检与依赖注入**：
   - 运行 `bddc compile` 前，**必须**确保项目已成功编译（`mix compile`）。
   - 显式指定指令文件：`bddc compile --instructions priv/bdd/instructions_v1.exs`。

## 核心规约 (Core Conventions)

### 1. DSL 参数与变量规约 (重要)
*   **变量定义**：使用 `LET var_name = 'value'`。注意 `var_name` **不要带 $ 前缀**（编译器在定义时会自动处理，带 $ 会导致引用失败）。
*   **变量引用**：在指令中使用 `$var_name`。
*   **字符串引号**：推荐使用单引号包裹 JSON 或复杂字符串，避免嵌套双引号引发的解析错误。
*   **禁止拼接**：DSL 不支持 `'a' + 'b'` 这种字符串拼接，必须在 `LET` 中定义完整字符串。

**正确示例：**
```bdd
LET args = '{"path":"file.txt","content":"hello"}'
WHEN execute_tool tool_name="write_file" args=$args
```

### 2. 自动化门禁 (Gate)
在完成任务前，必须运行以下脚本确保质量：
*   `./scripts/bdd_gate.sh`：专门针对 BDD 的编译与测试。
*   `./scripts/pre_deploy_check.sh`：全量检查（编译、Credo、BDD）。

## 标准迭代工作流 (Standard Iteration Workflow)

在进行功能新增、Bug 修复或重构任务时，必须遵循以下步骤：
1. **任务规划**：使用 `taskctl` 生成 DAG 图，明确执行路径。
2. **定义行为**：在 `test/bdd/dsl/` 编写 DSL 场景，确保测试先行。
3. **实现与验证**：按照规范修改代码，并运行 `./scripts/bdd_gate.sh` 进行闭环验证。
4. **自检交付**：运行 `./scripts/pre_deploy_check.sh`，确保无编译警告且静态分析通过。

## 常用 BDDC 命令

- `bddc compile` - 将 `.dsl` 文件转换为 `test/bdd_generated/*_test.exs`。
- `bddc check` - 全量验证（注意：在本项目中可能产生误报，优先使用 `compile`）。
- `bddc lint` - 检查测试异味（弱断言、固定休眠等）。

## 与 Gemini CLI 集成

当被要求“添加 BDD 测试”或“验证行为 X”时：
1. 搜索 `test/bdd/dsl/` 以获取相关 DSL。
2. 搜索 `priv/bdd/instructions_v1.exs` 以获取可用指令。
3. 提出 `.dsl` 修改建议。
4. 执行 `./scripts/bdd_gate.sh`。

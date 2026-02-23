# 知识库：BDDC (Behavior-Driven Development Compiler)

BDDC 是一个专为 Elixir 项目设计的 BDD 测试编译器。它允许开发者使用人类可读的 DSL（领域特定语言）编写业务场景，并将其自动编译为标准的 ExUnit 集成测试代码。

## 核心功能
- **DSL 编译**：将 `docs/bdd/*.dsl` 转换为 `test/bdd_generated/*_test.exs`。
- **静态验证**：在测试运行前检查指令名、参数类型、必填项及变量引用。
- **质量门禁**：通过 `lint` 功能检查测试异味（如弱断言、硬编码休眠）。
- **注解驱动**：支持在业务代码中使用 `@bdd` 注解自动生成指令注册表。

## 工具执行策略
为了保证跨环境兼容性，Agent 在调用工具时遵循“直接调用 -> 本地回退”逻辑。若全局命令不可用，请使用项目本地路径：
- **Linux**: `.github/tools/bddc-linux-x86_64`
- **Windows**: `.github/tools/bddc-win-amd64.cmd`

## 常用命令
```bash
# 编译所有 DSL 场景
bddc compile

# 执行全量检查（编译 + Lint + 运行时覆盖率验证）
bddc check

# 仅执行 Lint 检查
bddc lint

# 同步运行时能力到清单
bddc runtime.caps.sync
```

## 核心规约 (Usage Lessons)

为了确保测试的健壮性和避免编译器错误，必须遵循以下规约：

### 1. 复杂参数处理
由于 DSL 解析器对特殊字符（特别是引号嵌套）较敏感，**强烈建议对 Map 或 List 类型的参数使用变量定义**：
- 在 `SCENARIO` 内部先使用 `LET` 定义变量。
- 使用单引号 `'` 包裹整个 JSON 字符串。
- 示例：`LET $config = '{"key":"value","retry":true}'`
- 调用：`WHEN do_something args=$config`

### 2. 指令规范约束
在 `priv/bdd/instructions_v1.exs` 中定义的指令 Spec 必须严格包含：
- `allowed: nil`：即使没有枚举值约束，也必须显式声明，否则编译器会崩溃。
- `scopes`：必须包含 `:unit` 或 `:integration` 标签。

### 3. 环境依赖
`bddc compile` 命令在执行过程中会尝试反射加载 Elixir 模块以生成文档或验证指令。如果项目处于编译错误状态，该工具将无法运行。在运行 `bddc` 前应确保 `mix compile` 通过。

## Skill 位置
- **Agent Skill**: `.agent/skills/bddc/SKILL.md`

## 在 Cortex 中的应用
用于验证 Agent 修改后的代码行为是否符合业务预期。Agent 在提交更改前，应运行 `bddc check` 确保所有定义的行为场景通过。

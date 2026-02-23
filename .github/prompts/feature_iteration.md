# 提示词：BDD 驱动的任务迭代 (BDD-Driven Iteration)

**场景**：当你需要执行功能新增、Bug 修复或代码重构时。
**目标**：确保操作可审计、行为已定义、结果已验证。

## 工具执行策略 (Tool Execution Strategy)

在执行 CLI 工具（`bddc`, `taskctl`, `bcc`）时，请遵循以下逻辑：
1. **尝试直接调用**：优先尝试直接运行命令（例如 `taskctl`）。
2. **本地回退执行**：如果直接调用因命令不存在而失败，请转而使用项目本地对应的架构工具全路径：
   - **Linux x86_64**: `.github/tools/<tool_name>-linux-x86_64`
   - **Windows amd64**: `.github/tools/<tool_name>-win-amd64.exe` (或对应的 escript/cmd)
3. **环境检查**：运行 `bddc` 前确保已安装 Erlang/OTP。

---

## 指令集 (Instructions)

作为一个 AI Agent，在处理此任务时，你必须严格遵循以下工作流：

### 第一步：规划与对齐 (Planning)
1. 使用 `taskctl` 在 `.jido/tasks.json` 中初始化或更新任务列表。
2. 为本次迭代创建任务，并定义依赖关系（如：`Scaffold DSL` -> `Implement Code` -> `Verify`）。
3. 运行 `taskctl dag-ascii` 并将图表输出给用户，以确认你的执行路径。

### 第二步：定义行为规范 (Specification)
1. 在修改任何业务代码之前，先在 `docs/bdd/` 下编写或更新 `.dsl` 场景文件。
2. **架构与脚手架设计**：根据任务类型选择合适的生成器（参考 `ElixirStyleGuide.md` 8.1 章节）：
   - **BCC (架构驱动)**：跨系统集成、复杂业务逻辑或**非 Phoenix 耦合**的服务。编写 `service_definition.yaml` 并运行 `bcc compile` 生成 Elixir 骨架（参考 `.agent/skills/bcc_compiler/SKILL.md`）。
   - **Phoenix (数据驱动)**：如果使用了 Phoenix 框架，且是标准的数据库 CRUD、基础表管理，优先使用 `mix phx.gen.live` 或 `mix phx.gen.context`。
   - **Ecto (纯数据库变更)**：如果仅涉及表结构调整（如新增字段、索引），使用 `mix ecto.gen.migration`。
   - **原则**：严禁手动创建 Context/Schema 文件。Schema 应由 `phx.gen` 生成以确保 Ecto 映射准确；业务骨架应由 `bcc` 生成以确保接口严谨。
3. 如果是 **Bug 修复**：编写一个能复现该 Bug 的失败场景。
4. 如果是 **新功能**：编写描述该功能核心价值的成功路径场景。
5. 参考 `KB_Tool_BDDC.md` 确保 DSL 指令使用正确。

### 第三步：代码实现 (Implementation)
1. 使用 `bcc extract` 或 `read_file` 分析当前受影响的模块。
2. 如果在第二步生成了 `bcc` 骨架，在生成的函数体内填充具体的业务逻辑。
3. 按照 Elixir 专家规范进行代码修改。
4. 如果新增了 API，使用 `@bdd` 注解并运行 `bddc domain.autowire` 同步指令集。

### 第四步：闭环验证 (Verification)
1. 运行 `bddc check` 编译所有 DSL 并执行测试。
2. 确保 `test/bdd_generated/` 下生成的文件通过 `mix test`。
3. 运行 `mix format` 格式化此次涉及到的所有 ex/exs 文件。
4. 任务完成后，使用 `taskctl update` 将任务标记为 `completed`。

---

## 启动响应 (Initial Response)
"收到任务。我将首先使用 `taskctl` 建立执行计划并生成 DAG，随后通过 BDD DSL 定义行为规范并选择合适的生成器（BCC/Phoenix/Ecto）..."

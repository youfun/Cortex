# BDD 测试开发指南

## 快速开始

### 1. 首次设置

克隆项目后，需要生成 BDD 测试文件：

```bash
# 编译 DSL 并生成测试文件
.github/tools/bddc-linux-x86_64 compile

# 或者使用 bdd_gate.sh（包含编译和测试运行）
./scripts/bdd_gate.sh
```

### 2. 开发流程

#### 编写 BDD 场景

在 `test/bdd/dsl/` 目录下创建 `.dsl` 文件：

```dsl
[SCENARIO: MY-TEST-001] TITLE: My test scenario
  GIVEN signal_bus_is_clean
  WHEN signal_is_emitted type="test.event" data='{"value": 1}' session_id="test"
  THEN assert_signal_data type="test.event" path="provider" expected="bdd"
```

#### 编译并运行测试

```bash
# 编译 DSL 生成测试文件
.github/tools/bddc-linux-x86_64 compile

# 运行生成的测试
mix test test/bdd_generated/

# 或运行特定测试
mix test test/bdd_generated/my_test_generated_test.exs
```

### 3. 为什么生成的文件不提交到 Git？

- **避免 diff 噪音**：每次 DSL 修改都会重新生成大量测试代码
- **避免合并冲突**：多人协作时生成的文件容易冲突
- **保持源码简洁**：只提交 DSL 源文件（`.dsl`），生成的代码本地重建

### 4. CI/CD 集成

如果需要在 CI/CD 中运行 BDD 测试，在 pipeline 中添加编译步骤：

```yaml
# 示例：GitHub Actions
- name: Generate BDD tests
  run: .github/tools/bddc-linux-x86_64 compile

- name: Run BDD tests
  run: mix test test/bdd_generated/
```

### 5. 常见问题

#### Q: 为什么我的测试文件不见了？
A: 生成的测试文件在 `.gitignore` 中，需要本地运行编译脚本生成。

#### Q: 如何验证我的 DSL 语法？
A: 运行 `.github/tools/bddc-linux-x86_64 compile`，编译器会报告语法错误。

#### Q: 测试失败怎么办？
A: 检查 `lib/cortex/bdd/instructions/v1.ex` 中的指令实现，确保业务逻辑正确。

## 参考文档

- [BDDC 工具文档](.github/KnowledgeBase/KB_Tool_BDDC.md)
- [BDD 转换实施计划](docs/plans/20260219_bdd_conversion_implementation_plan.md)
- [BDD 转换进度报告](docs/progress/20260219_bdd_conversion_progress.md)

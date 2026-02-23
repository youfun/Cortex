# Skill: BCC Compiler (Backend Compiler)

## 概述
BCC (Backend Compiler) 是一个声明式后端骨架生成器。它允许开发者通过定义 YAML 合约，自动生成符合“端口与适配器”架构风格的 Elixir 服务代码。

## 核心工作流
1. **定义 (Definition)**: 编写 `.yaml` 文件描述模块职责、接口和依赖。
2. **编译 (Compile)**: 使用 `bcc` 工具生成 `.ex` 骨架文件。
3. **实现 (Implementation)**: 在生成的函数体内填充具体的业务逻辑。

## YAML 协议规范

### 1. 模块定义 (Module)
描述服务的基本信息。
```yaml
module:
  name: SnsConfigService    # 模块名 (PascalCase)
  responsibility: 管理 SNS 接入配置 # 简短描述模块职责
```

### 2. 端口定义 (Ports)
定义服务的公共 API。
- **name**: 函数名 (snake_case)。
- **kind**: `query` (只读/查询) 或 `command` (副作用/修改)。
- **input**: 输入参数名与类型的映射（如 `uuid`, `map`, `integer`, `string`, `list`, `boolean`）。
- **output**: 成功返回的数据结构映射。
- **errors**: 业务错误码列表（如 `AUTH-001`, `NOT-FOUND`）。

示例：
```yaml
ports:
  - name: test_connection
    kind: query
    input: { id: uuid }
    output: { status: string, message: string }
    errors: [SNS-AUTH-001, CONFIG-404]
```

### 3. 关系定义 (Relations)
定义服务依赖的其他模块或外部系统。
- **callee**: 依赖的模块名。
- **mode**: `sync` (同步调用) 或 `async` (异步通知/发射信号)。

示例：
```yaml
relations:
  - callee: SnsClient
    mode: sync
  - callee: SignalHub
    mode: async
```

## 工具使用指南

### 编译命令
```bash
.github/tools/bcc-linux-x86_64 compile <input.yaml> --output <output_path.ex>
```

### 参数说明
- `--dry-run`: 仅显示编译摘要，不生成文件。
- `--output`: 指定输出的 Elixir 文件路径。
- `--emit-ast`: 输出编译后的抽象语法树 (JSON 格式)。

## 最佳实践
1. **单一职责**: 每个 YAML 文件应只定义一个核心服务。
2. **错误码规范**: 使用结构化的错误码前缀（如 `SNS-`）以便于全局审计。
3. **信封模式**: BCC 生成的代码默认使用 `Envelope` 结构封装数据，确保在 Cortex 内部传递的一致性。

## 示例模板
参考 `docs/Cli-master/compiler/bcc/fixtures/session_service.yaml` 获取更多复杂场景的定义方式。

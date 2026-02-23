# 移除 jido_shell 依赖 — 自实现替代方案

> 日期：2025-02-20
> 状态：待实施

## 1. 背景

`jido_shell` → `hako (jido_vfs)` → `splode` 依赖链中，`splode 0.2.9` 与当前 Elixir 1.19.4 环境不兼容，导致编译失败。

项目实际仅使用了 `jido_shell` 的 **2 个接口**：

| 接口 | 用于文件 | 用途 |
|------|---------|------|
| `@behaviour Jido.Shell.Command` | `system_exec.ex` | 定义 `sys` 命令的 4 个 callback |
| `Jido.Shell.Error` | `system_exec.ex` | 构造 `shell/2` 和 `command/2` 错误 |

`shell_command.ex`（主执行路径）完全不依赖 jido_shell，用的是 `Sandbox.execute`。

## 2. 目标

- 移除 `jido_shell` 依赖（连带消除 `hako`、`splode` 等传递依赖）
- 在项目内自实现等价的极简接口
- **零功能变更**，`system_exec.ex` 只改 alias/behaviour 引用

## 3. 实施计划

### Step 1：创建 `Cortex.Shell.Command` behaviour

**文件**：`lib/cortex/shell/command.ex`

从 `Jido.Shell.Command` 提取 4 个 callback 定义，去掉对 `Jido.Shell.Session.State` 和 `Zoi` 的依赖（改用通用 `map()` 类型）：

```elixir
defmodule Cortex.Shell.Command do
  @type emit :: (event :: term() -> :ok)
  @type run_result :: {:ok, term()} | {:error, Cortex.Shell.Error.t()}

  @callback name() :: String.t()
  @callback summary() :: String.t()
  @callback schema() :: term()
  @callback run(state :: map(), args :: map(), emit :: emit()) :: run_result()
end
```

### Step 2：创建 `Cortex.Shell.Error` 结构体

**文件**：`lib/cortex/shell/error.ex`

只实现 `system_exec.ex` 实际调用的 2 个构造函数：

```elixir
defmodule Cortex.Shell.Error do
  defexception [:code, :message, context: %{}]

  @type t :: %__MODULE__{code: {atom(), atom()}, message: String.t(), context: map()}

  def shell(code, ctx \\ %{}) do
    %__MODULE__{code: {:shell, code}, message: to_string(code), context: ctx}
  end

  def command(code, ctx \\ %{}) do
    %__MODULE__{code: {:command, code}, message: to_string(code), context: ctx}
  end
end
```

### Step 3：修改 `system_exec.ex` 引用

**文件**：`lib/cortex/shell/commands/system_exec.ex`

```diff
- @behaviour Jido.Shell.Command
+ @behaviour Cortex.Shell.Command

- alias Jido.Shell.Error
+ alias Cortex.Shell.Error
```

仅改这 2 行，其余代码不动。

### Step 4：从 `mix.exs` 移除依赖

```diff
- {:jido_shell, github: "agentjido/jido_shell"},
```

### Step 5：清理锁文件和编译缓存

```bash
mix deps.clean jido_shell hako --unlock
mix deps.get
mix compile
```

## 4. 影响范围

| 变更项 | 文件数 | 说明 |
|--------|--------|------|
| 新增 | 2 | `command.ex` (~10行), `error.ex` (~15行) |
| 修改 | 2 | `system_exec.ex` (2行), `mix.exs` (1行) |
| 删除 | 0 | — |
| 移除的传递依赖 | ~10+ | jido_shell, hako, splode, git_cli, tentacat, ex_aws, ex_aws_s3, eternal, sprites 等 |

## 5. 验证

```bash
mix compile --warnings-as-errors  # 编译通过，无警告
mix phx.server                     # 服务正常启动
```

## 6. BDD 驱动迭代流程说明

本任务属于**依赖替换 + 轻量接口自实现**，变更范围极小（4 文件、约 30 行代码），无需完整 BDD 场景定义。验证标准为：`mix compile` 通过 + `mix phx.server` 正常启动。如后续 `system_exec.ex` 需要功能迭代，再按 `.agent/skills/bddc/SKILL.md` 中的 BDD 驱动流程进行。

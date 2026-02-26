# !!!PLANNING!!!

# 敏感数据脱敏 + Shell 授权绕过修复 — 统一安全加固计划

**日期**: 2026-02-23
**关联分析**: `docs/analysis/20260223_shell_folder_auth_bypass_analysis.md`
**范围**: Agent 工具链全链路敏感数据保护

---

# UPDATES

- 2026-02-23: 初始规划，整合 shell 授权绕过分析与敏感数据脱敏需求

---

# ARCHITECTURAL ANALYSIS

## 当前安全架构现状

系统已有三层安全机制：
1. **路径边界** (`Security.validate_path`) — 防止逃逸 workspace
2. **文件夹授权** (`Security.validate_path_with_folders`) — 细粒度目录控制
3. **命令拦截** (`ShellInterceptor` + 危险命令黑名单) — 高危操作审批

**缺失的第四层：内容级脱敏（Content-Level Redaction）**

即使路径和文件夹授权完备，Agent 仍可合法读取授权目录内的敏感文件（如 `.env`、`config/runtime.exs` 中的密钥）。当前系统对文件内容**零过滤**，读到什么就原样返回给 LLM。

## 两个问题的关系

| 问题 | 层级 | 攻击面 |
|------|------|--------|
| Shell 授权绕过 | 路径/目录级 | Agent 通过 `cat`/`cp` 等绕过文件夹授权 |
| 敏感数据泄露 | 内容级 | Agent 合法读取含密钥的文件，内容原样进入 LLM context |

两者互补：修复 shell 绕过堵住**路径级**漏洞，内容脱敏堵住**数据级**漏洞。需要统一在工具输出管道中解决。

## 信号流中的拦截点

```
工具执行 → 原始输出
              ↓
         [拦截点 1] ToolRunner.maybe_truncate (已有，仅截断)
              ↓
         [拦截点 2] ★ 新增：ContentRedactor.redact (内容脱敏)
              ↓
         [拦截点 3] ★ 新增：ShellPathGuard.check (shell 路径授权)
              ↓
         脱敏后输出 → LLM context / Tape / 信号
```

---

# TASK GRAPH (DAG)

```
Phase 1: 基础设施层
├── T1.1 ContentRedactor 模块 (敏感数据识别 + 占位符替换)
├── T1.2 SensitiveFileDetector 模块 (敏感文件类型识别)
└── T1.3 RedactionConfig (脱敏规则配置)

Phase 2: 工具集成层
├── T2.1 ReadFile 集成 ContentRedactor (依赖 T1.1, T1.2)
├── T2.2 ShellCommand 输出脱敏 (依赖 T1.1)
├── T2.3 ShellCommand 路径授权检查 (来自 bypass 分析)
├── T2.4 ToolRunner 统一脱敏管道 (依赖 T1.1)
└── T2.5 ToolExecution ctx 传递 agent_id (来自 bypass 分析)

Phase 3: 信号与审计层
├── T3.1 脱敏事件信号 (security.redaction.applied)
└── T3.2 脱敏审计日志

Phase 4: 测试与验证
├── T4.1 ContentRedactor 单元测试
├── T4.2 BDD 场景：敏感文件读取脱敏
├── T4.3 BDD 场景：shell 输出脱敏
└── T4.4 BDD 场景：shell 路径授权
```

---

# BDD SPECIFICATION

## 场景预览 1：敏感文件内容脱敏

```gherkin
Feature: 敏感数据内容级脱敏

  Scenario: 读取 .env 文件时自动脱敏
    Given workspace 中存在文件 ".env" 内容为:
      """
      DATABASE_URL=postgres://user:secret123@localhost/db
      API_KEY=sk-1234567890abcdef
      APP_NAME=my_app
      """
    When Agent 调用 read_file 读取 ".env"
    Then 返回内容中 "secret123" 被替换为 "[REDACTED]"
    And 返回内容中 "sk-1234567890abcdef" 被替换为 "[REDACTED]"
    And 返回内容中 "APP_NAME=my_app" 保持不变
    And 发射信号 "security.redaction.applied"

  Scenario: 读取普通代码文件不触发脱敏
    Given workspace 中存在文件 "lib/app.ex" 内容为:
      """
      defmodule App do
        def hello, do: "world"
      end
      """
    When Agent 调用 read_file 读取 "lib/app.ex"
    Then 返回内容与原文件完全一致
    And 不发射 "security.redaction.applied" 信号

  Scenario: Shell 命令输出中的敏感数据被脱敏
    Given workspace 中存在文件 ".env" 内容包含 "SECRET_KEY=abc123"
    When Agent 执行 shell 命令 "cat .env"
    Then 输出中 "abc123" 被替换为 "[REDACTED]"

  Scenario: 整个 .env 文件内容脱敏模式
    Given 脱敏配置中 ".env" 设置为 "full_redact" 模式
    When Agent 调用 read_file 读取 ".env"
    Then 返回内容为 "[REDACTED: .env file — 包含敏感环境变量，共 N 行]"
```

## 场景预览 2：Shell 路径授权（来自 bypass 分析）

```gherkin
Feature: Shell 命令路径授权

  Scenario: Shell 命令访问非授权目录被拦截
    Given Agent 被限制仅访问 "src/" 目录
    When Agent 执行 shell 命令 "cat config/secrets.exs"
    Then 命令被拒绝，返回 "Path not authorized: config/secrets.exs"

  Scenario: Shell 命令中的路径遍历被拦截
    Given Agent 被限制仅访问 "src/" 目录
    When Agent 执行 shell 命令 "cat ../other_project/data.db"
    Then 命令被拒绝，返回路径越界错误
```

---

# AFFECTED MODULES & FILES

## 新增文件

| 文件 | 职责 |
|------|------|
| `lib/cortex/core/content_redactor.ex` | 核心脱敏引擎：模式匹配 + 占位符替换 |
| `lib/cortex/core/sensitive_file_detector.ex` | 敏感文件类型识别（.env, *.key, *.pem 等） |
| `lib/cortex/core/redaction_config.ex` | 脱敏规则配置（可热更新） |
| `lib/cortex/tools/shell_path_guard.ex` | Shell 命令路径提取 + 授权检查 |
| `test/cortex/core/content_redactor_test.exs` | 脱敏引擎单元测试 |
| `test/cortex/core/sensitive_file_detector_test.exs` | 文件检测单元测试 |

## 修改文件

| 文件 | 修改内容 |
|------|----------|
| `lib/cortex/tools/tool_runner.ex` | 在 `maybe_truncate` 后增加 `maybe_redact` 管道 |
| `lib/cortex/tools/handlers/read_file.ex` | 集成 SensitiveFileDetector，对敏感文件启用全文脱敏 |
| `lib/cortex/tools/handlers/shell_command.ex` | 集成 ShellPathGuard + 输出脱敏，接收 agent_id |
| `lib/cortex/agents/llm_agent/tool_execution.ex` | ctx 中传递 agent_id |
| `lib/cortex/hooks/sandbox_hook.ex` | 增加对 shell command 参数的路径提取检查 |
| `lib/cortex/tools/shell_interceptor.ex` | 扩展：增加路径模式检查 |

---

# EXECUTION PLAN

## STEP 1: ContentRedactor — 核心脱敏引擎

```elixir
defmodule Cortex.Core.ContentRedactor do
  @moduledoc """
  内容级敏感数据脱敏引擎。
  
  支持两种模式：
  - :value_redact — 仅替换 key=value 中的 value 部分
  - :full_redact — 整个文件内容替换为摘要占位符
  """

  @redact_placeholder "[REDACTED]"

  # 敏感值模式（key=value 格式中的 value）
  @sensitive_key_patterns [
    ~r/(?i)(password|passwd|pwd)\s*[=:]\s*/,
    ~r/(?i)(secret|secret_key|secret_token)\s*[=:]\s*/,
    ~r/(?i)(api_key|apikey|api_secret)\s*[=:]\s*/,
    ~r/(?i)(access_key|access_token|auth_token)\s*[=:]\s*/,
    ~r/(?i)(private_key|encryption_key)\s*[=:]\s*/,
    ~r/(?i)(database_url|db_url|db_password)\s*[=:]\s*/,
    ~r/(?i)(aws_secret|aws_access_key_id)\s*[=:]\s*/,
    ~r/(?i)(stripe_secret|stripe_key)\s*[=:]\s*/,
    ~r/(?i)(sendgrid_api_key|mailgun_api_key)\s*[=:]\s*/,
    ~r/(?i)(jwt_secret|session_secret)\s*[=:]\s*/,
    ~r/(?i)(client_secret|oauth_secret)\s*[=:]\s*/
  ]

  # 独立敏感值模式（无需 key 上下文）
  @sensitive_value_patterns [
    # AWS keys
    ~r/AKIA[0-9A-Z]{16}/,
    # GitHub tokens
    ~r/gh[ps]_[A-Za-z0-9_]{36,}/,
    # Generic long hex secrets
    ~r/(?<![A-Za-z0-9])[0-9a-f]{32,64}(?![A-Za-z0-9])/,
    # Bearer tokens
    ~r/Bearer\s+[A-Za-z0-9\-._~+\/]+=*/,
    # Connection strings with passwords
    ~r/:\/\/[^:]+:[^@]+@/
  ]

  @doc "对内容执行 value-level 脱敏"
  def redact(content, opts \\ []) do
    mode = Keyword.get(opts, :mode, :value_redact)
    path = Keyword.get(opts, :path)

    case mode do
      :full_redact ->
        line_count = content |> String.split("\n") |> length()
        ext = if path, do: Path.extname(path), else: ""
        {"[REDACTED: #{Path.basename(path || "file")} — 敏感文件，共 #{line_count} 行]", true}

      :value_redact ->
        {redacted, changed?} = redact_values(content)
        {redacted, changed?}
    end
  end

  defp redact_values(content) do
    lines = String.split(content, "\n")
    
    {redacted_lines, any_changed?} =
      Enum.map_reduce(lines, false, fn line, changed_acc ->
        {new_line, line_changed?} = redact_line(line)
        {new_line, changed_acc or line_changed?}
      end)

    {Enum.join(redacted_lines, "\n"), any_changed?}
  end

  defp redact_line(line) do
    # 1. 检查 key=value 模式
    result = Enum.reduce(@sensitive_key_patterns, {line, false}, fn pattern, {current, changed} ->
      if Regex.match?(pattern, current) do
        new_line = Regex.replace(
          ~r/((?i)(?:password|passwd|pwd|secret|secret_key|secret_token|api_key|apikey|api_secret|access_key|access_token|auth_token|private_key|encryption_key|database_url|db_url|db_password|aws_secret|aws_access_key_id|stripe_secret|stripe_key|sendgrid_api_key|mailgun_api_key|jwt_secret|session_secret|client_secret|oauth_secret)\s*[=:]\s*)(.+)/,
          current,
          "\\1#{@redact_placeholder}"
        )
        {new_line, new_line != current or changed}
      else
        {current, changed}
      end
    end)

    # 2. 检查独立敏感值模式
    Enum.reduce(@sensitive_value_patterns, result, fn pattern, {current, changed} ->
      new_line = Regex.replace(pattern, current, @redact_placeholder)
      {new_line, new_line != current or changed}
    end)
  end
end
```

## STEP 2: SensitiveFileDetector — 敏感文件识别

```elixir
defmodule Cortex.Core.SensitiveFileDetector do
  @moduledoc """
  识别敏感文件类型，决定脱敏策略。
  """

  # 完全脱敏的文件（整个内容替换为占位符）
  @full_redact_files [
    ".env",
    ".env.local",
    ".env.production",
    ".env.staging",
    ".env.development"
  ]

  # 完全脱敏的文件扩展名
  @full_redact_extensions [
    ".pem",
    ".key",
    ".p12",
    ".pfx",
    ".jks",
    ".keystore"
  ]

  # 值级脱敏的文件模式
  @value_redact_patterns [
    ~r/\.env\..+$/,
    ~r/secrets?\.(ya?ml|json|toml|exs?)$/i,
    ~r/credentials?\.(ya?ml|json|toml|exs?)$/i,
    ~r/config\/runtime\.exs$/,
    ~r/config\/prod\.exs$/
  ]

  @doc """
  检测文件的脱敏策略。
  返回 :full_redact | :value_redact | :none
  """
  def detect(path) do
    basename = Path.basename(path)
    ext = Path.extname(path)

    cond do
      basename in @full_redact_files -> :full_redact
      ext in @full_redact_extensions -> :full_redact
      Enum.any?(@value_redact_patterns, &Regex.match?(&1, path)) -> :value_redact
      true -> :none
    end
  end
end
```

## STEP 3: RedactionConfig — 可配置脱敏规则

```elixir
defmodule Cortex.Core.RedactionConfig do
  @moduledoc """
  脱敏规则配置。支持 workspace 级别的 .redaction.json 配置文件。
  """

  @default_config %{
    enabled: true,
    full_redact_files: [".env", ".env.local", ".env.production"],
    full_redact_extensions: [".pem", ".key", ".p12"],
    value_redact_patterns: ["secrets.yml", "credentials.json", "config/runtime.exs"],
    custom_sensitive_keys: [],
    whitelist_files: []
  }

  def load(project_root) do
    config_path = Path.join(project_root, ".redaction.json")

    case File.read(config_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, user_config} -> merge_config(user_config)
          {:error, _} -> @default_config
        end
      {:error, _} -> @default_config
    end
  end

  def default_config, do: @default_config

  defp merge_config(user_config) do
    Map.merge(@default_config, atomize_keys(user_config))
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} rescue _ -> {k, v} end)
  end
end
```

## STEP 4: ToolRunner 集成统一脱敏管道

```elixir
# lib/cortex/tools/tool_runner.ex — 修改 execute/3
def execute(tool_name, args, ctx) do
  case Registry.get(tool_name) do
    {:ok, tool} ->
      {elapsed_us, result} =
        :timer.tc(fn ->
          tool.module.execute(normalize_args(args), ctx)
        end)

      elapsed_ms = div(elapsed_us, 1000)

      case result |> maybe_truncate(tool_name) |> maybe_redact(tool_name, args, ctx) do
        {:ok, output} -> {:ok, output, elapsed_ms}
        {:error, reason} -> {:error, reason, elapsed_ms}
      end

    :error ->
      {:error, :tool_not_found, 0}
  end
end

defp maybe_redact({:ok, content}, tool_name, args, ctx) when is_binary(content) do
  path = get_path_from_context(tool_name, args)

  if path do
    case Cortex.Core.SensitiveFileDetector.detect(path) do
      :none ->
        {:ok, content}

      mode ->
        {redacted, changed?} = Cortex.Core.ContentRedactor.redact(content, mode: mode, path: path)

        if changed? do
          emit_redaction_signal(path, mode, ctx)
        end

        {:ok, redacted}
    end
  else
    # shell 输出：始终执行 value_redact 扫描
    if tool_name == "shell" do
      {redacted, _} = Cortex.Core.ContentRedactor.redact(content, mode: :value_redact)
      {:ok, redacted}
    else
      {:ok, content}
    end
  end
end

defp maybe_redact(result, _tool_name, _args, _ctx), do: result

defp get_path_from_context(tool_name, args) when tool_name in ["read_file", "write_file", "edit_file"] do
  Map.get(args, :path) || Map.get(args, "path")
end
defp get_path_from_context(_, _), do: nil
```

## STEP 5: ShellPathGuard — Shell 路径授权（来自 bypass 分析方案 D Phase 1）

```elixir
defmodule Cortex.Tools.ShellPathGuard do
  @moduledoc """
  Shell 命令路径提取与授权检查。
  从 shell 命令中提取文件路径，验证是否在授权目录内。
  """

  alias Cortex.Core.Security

  # 文件操作命令 → 路径参数位置
  @file_commands %{
    "cat" => :all_args,
    "less" => :all_args,
    "more" => :all_args,
    "head" => :last_arg,
    "tail" => :last_arg,
    "ls" => :all_args,
    "cp" => :all_args,
    "mv" => :all_args,
    "ln" => :all_args,
    "touch" => :all_args,
    "mkdir" => :all_args,
    "rmdir" => :all_args,
    "chmod" => :last_arg,
    "chown" => :last_arg,
    "stat" => :all_args,
    "file" => :all_args,
    "wc" => :all_args,
    "sort" => :all_args,
    "uniq" => :all_args,
    "diff" => :all_args,
    "tar" => :special_tar,
    "find" => :first_arg,
    "grep" => :last_arg,
    "sed" => :last_arg,
    "awk" => :last_arg
  }

  def check(command, project_root, opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)

    with :ok <- check_path_traversal(command),
         :ok <- check_redirect_paths(command, project_root, agent_id),
         paths <- extract_paths(command),
         :ok <- validate_paths(paths, project_root, agent_id) do
      :ok
    end
  end

  defp check_path_traversal(command) do
    if Regex.match?(~r/\.\.\/|\.\.\\/, command) do
      {:error, {:permission_denied, "Path traversal detected in shell command"}}
    else
      :ok
    end
  end

  defp check_redirect_paths(command, project_root, agent_id) do
    case Regex.run(~r/>{1,2}\s*(\S+)/, command) do
      [_, path] ->
        case Security.validate_path_with_folders(path, project_root, agent_id: agent_id) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, {:permission_denied, "Redirect target not authorized: #{path} (#{reason})"}}
        end
      nil -> :ok
    end
  end

  def extract_paths(command) do
    # 处理管道：只检查第一个命令的路径参数
    first_cmd = command |> String.split("|") |> List.first() |> String.trim()
    parts = OptionParser.split(first_cmd)

    case parts do
      [cmd_name | args] ->
        cmd = Path.basename(cmd_name)
        extract_by_command(cmd, args)
      _ -> []
    end
  end

  defp extract_by_command(cmd, args) do
    case Map.get(@file_commands, cmd) do
      :all_args -> filter_non_flags(args)
      :last_arg -> if args != [], do: [List.last(args)], else: []
      :first_arg -> if args != [], do: [List.first(args)], else: []
      _ -> []
    end
  end

  defp filter_non_flags(args) do
    Enum.reject(args, &String.starts_with?(&1, "-"))
  end

  defp validate_paths([], _root, _agent_id), do: :ok
  defp validate_paths(paths, project_root, agent_id) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case Security.validate_path_with_folders(path, project_root, agent_id: agent_id) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:permission_denied, "Path not authorized: #{path} (#{reason})"}}}
      end
    end)
  end
end
```

## STEP 6: ShellCommand 集成修改

```elixir
# lib/cortex/tools/handlers/shell_command.ex — 修改 do_execute
defp do_execute(command, timeout, project_root, session_id, ctx) do
  agent_id = Map.get(ctx, :agent_id)

  with :ok <- check_command_safety(command, session_id),
       :ok <- Cortex.Tools.ShellInterceptor.check(command),
       :ok <- Cortex.Tools.ShellPathGuard.check(command, project_root, agent_id: agent_id) do
    execute_command(command, project_root, timeout, session_id)
  else
    {:approval_required, reason} ->
      {:error, {:approval_required, "User approval required for: #{reason}"}}
    error ->
      error
  end
end
```

## STEP 7: ToolExecution ctx 传递 agent_id

```elixir
# lib/cortex/agents/llm_agent/tool_execution.ex — 修改 execute_async
# 在 ToolRunner.execute 调用中增加 agent_id
result =
  ToolRunner.execute(call_data.name, call_data.args, %{
    session_id: session_id,
    agent_id: session_id,  # ← 新增：将 session_id 作为 agent_id
    project_root: Workspaces.workspace_root()
  })
```

---

# VERIFICATION PLAN

## 自动化验证命令

```bash
# 编译检查
mix compile --warnings-as-errors

# 格式化
mix format --check-formatted

# 单元测试
mix test test/cortex/core/content_redactor_test.exs
mix test test/cortex/core/sensitive_file_detector_test.exs
mix test test/cortex/tools/shell_path_guard_test.exs

# 集成测试
mix test test/cortex/tools/handlers/read_file_test.exs
mix test test/cortex/tools/handlers/shell_command_test.exs

# 全量测试
mix test
```

## 验收标准

1. `.env` 文件读取返回脱敏内容，密钥值被替换为 `[REDACTED]`
2. `.pem`/`.key` 文件读取返回摘要占位符，不暴露任何内容
3. 普通代码文件读取不受影响
4. Shell 命令 `cat .env` 输出经过脱敏
5. Shell 命令访问非授权目录被拦截（当 agent 有文件夹授权限制时）
6. Shell 命令中的 `../` 路径遍历被拦截
7. 脱敏事件通过信号总线广播，可审计
8. 所有现有测试继续通过

## 测试策略

- BDD 场景覆盖：敏感文件读取脱敏、shell 输出脱敏、shell 路径授权
- 单元测试补充：ContentRedactor 的各种模式匹配边界 case（部分匹配、多行、嵌套引号等）
- 禁止重复：BDD 已覆盖的行为不再写 Unit Test

---

# BDD 驱动迭代流程说明

本计划遵循项目的 BDD 驱动任务迭代流程（参见 `.agent/skills/bddc/SKILL.md`）：

1. **规划先行**：本文档作为实施蓝图，所有编码必须按此计划执行
2. **行为定义优先**：实施前先在 `docs/bdd/` 下编写 DSL 场景文件
3. **编译验证**：使用 `bddc compile` 生成 ExUnit 测试
4. **红-绿-重构**：先让 BDD 测试失败（红），实现功能使其通过（绿），再优化代码
5. **任务管理**：使用 `taskctl` 跟踪每个 Phase 的进度

---

# 实施优先级

| 优先级 | 任务 | 预估工作量 | 安全收益 |
|--------|------|-----------|----------|
| P0 | ContentRedactor + SensitiveFileDetector | 中 | 高 — 堵住内容级泄露 |
| P0 | ToolRunner 集成脱敏管道 | 小 | 高 — 全工具链覆盖 |
| P1 | ShellPathGuard + ShellCommand 集成 | 中 | 高 — 堵住路径级绕过 |
| P1 | ToolExecution 传递 agent_id | 小 | 高 — 前置依赖 |
| P2 | RedactionConfig 可配置化 | 小 | 中 — 用户自定义 |
| P2 | 脱敏审计信号 | 小 | 中 — 可观测性 |

---

# !!!FINISHED!!!

# 内置简易编辑器 (Built-in Simple Editor) 规划文档

> 日期: 2026-02-24
> 状态: Draft

---

## 1. 问题与动机

### 问题 1: Agent 修改文件后无法快速查看/微调

Agent 通过 `write_file` / `edit_file` 生成或修改代码后，用户必须切到外部编辑器查看结果。如果需要小修改（加个注释、改个变量名），要么让 Agent 再跑一轮 tool call（浪费 token），要么手动切出去改。

### 问题 2: 上下文注入依赖 Agent 自行 read_file

当前流程：用户想让 Agent 理解某个文件 → Agent 调用 `read_file` → 整个文件内容进入 LLM context → token 浪费。

现有的 `pending_context` 机制（FileBrowser 选文件 → 下次发消息时自动注入）已经部分解决了这个问题，但：
- 只能注入整个文件，不能选择片段
- 没有预览，用户不知道注入了什么
- 无法在注入前编辑/裁剪内容

### 核心定位

**不是** IDE，**是** Agent 工作流的辅助视图：
1. 查看 Agent 产出 → 快速微调 → 省掉一轮 tool call
2. 预览文件 → 选择片段 → 精准注入 LLM 上下文 → 省 token

---

## 2. 技术选型: live_monaco_editor

使用 [`live_monaco_editor`](https://hex.pm/packages/live_monaco_editor) (`~> 0.2`) 作为编辑器前端：

| 优势 | 说明 |
|---|---|
| 语法高亮 | Monaco 内置，开箱即用，支持 Elixir/JS/Markdown/YAML 等 |
| 选区 API | `editor.getModel().getValueInRange(selection)` — 精准获取选中片段 |
| LiveView 集成 | 官方 Phoenix LiveView 组件，`set_value` / `change_language` 直接操作 socket |
| 懒加载 | 资源按需加载，不影响首屏 |
| 只读模式 | `readOnly: true` 可用于纯预览场景 |

不需要自己造 textarea + 行号 + Tab 处理等轮子。

### 新增依赖

```elixir
# mix.exs
{:live_monaco_editor, "~> 0.2"}
```

### JS Hook 架构

基于你提供的参考代码，需要两个 Hook：

| Hook | 职责 |
|---|---|
| `MonacoEditorSync` | 后端 → 前端同步：`set_value`、`reveal_line`、`highlight_line`、`set_cursor` |
| `MonacoSelection` | 前端 → 后端同步：`content_changed`（500ms 防抖）、`text_selected`（300ms 防抖）、`cursor_position_changed` |

两个 Hook 挂在同一个编辑器容器上，职责分离。

---

## 3. 架构设计

### 3.1 组件结构

```
JidoLive
  ├── ChatPanel (现有)
  └── EditorPanel (新增 active_panel = "editor")
        └── EditorComponent (LiveComponent)
              ├── 标签栏 (tabs: 多文件切换)
              ├── Monaco Editor (live_monaco_editor 组件)
              ├── 状态栏 (行号/列号/语言/保存状态)
              └── 操作栏:
                    ├── [保存 ⌘S] → WriteFile handler
                    └── [注入上下文 ↗] → 选中文本或全文 → pending_context
```

### 3.2 两条核心数据流

#### 流程 A: Agent 产出 → 查看/编辑

```
Agent 调用 write_file/edit_file
  → SignalHub 发射 "file.changed.write" / "file.changed.edit"
  → SignalDispatcher handle_file_changed (已有)
  → 新增: 如果 EditorPanel 打开且该文件在 tabs 中
    → 重新读取文件内容
    → LiveMonacoEditor.set_value(socket, new_content, to: path)
    → MonacoEditorSync Hook 接收 lme:set_value 事件 → editor.setValue()
  → 用户在编辑器中微调 → Ctrl+S → WriteFile handler
```

#### 流程 B: 精准上下文注入

```
用户在编辑器中打开文件
  → 查看内容，选中关键片段
  → MonacoSelection Hook 推送 text_selected 事件到 LiveView
  → EditorComponent 暂存 selected_text
  → 用户点击 [注入上下文]
  → EditorComponent → send(self(), {:inject_context, %{type: :snippet, path, text, line_range}})
  → JidoLive 设置 pending_context = %{type: :snippet, ...}
  → 用户发消息时，snippet 作为 user message 注入 LLM
    （复用现有 emit_context_add / maybe_emit_pending_context）
```

### 3.3 信号设计

不新增信号类型。复用现有信号：
- `file.changed.write` / `file.changed.edit` — 触发编辑器内容刷新
- `agent.context.add` — 上下文注入（已有）

编辑器内部操作（输入、光标移动、选区变化）不发射信号，仅通过 LiveView 事件通信。

---

## 4. 实现方案

### 4.1 新增文件

| 文件 | 职责 |
|---|---|
| `lib/cortex_web/live/components/editor_component.ex` | 编辑器 LiveComponent |
| `assets/js/hooks/monaco_hooks.js` | MonacoEditorSync + MonacoSelection Hook |

### 4.2 修改文件

| 文件 | 变更 |
|---|---|
| `mix.exs` | 添加 `{:live_monaco_editor, "~> 0.2"}` |
| `assets/js/app.js` | 导入 `CodeEditorHook` + 自定义 Hook |
| `assets/css/app.css` | 导入 `live_monaco_editor.min.css` |
| `lib/cortex_web/live/jido_live.ex` | 添加 `editor` panel、`handle_info({:open_file_in_editor, path})`、`handle_info({:inject_context, ...})` |
| `lib/cortex_web/live/helpers/agent_live_helpers.ex` | `emit_pending_context/2` 新增 `:snippet` 类型处理 |
| `lib/cortex_web/live/helpers/signal_dispatcher.ex` | `handle_file_changed` 增加编辑器刷新逻辑 |
| `lib/cortex_web/live/components/file_browser_component.ex` | 文件项增加"在编辑器中打开"入口 |

### 4.3 EditorComponent 核心状态

```elixir
defmodule CortexWeb.Components.EditorComponent do
  use CortexWeb, :live_component

  # 状态
  # open_tabs: [%{path: String.t(), content: String.t(), dirty: boolean(), language: String.t()}]
  # active_tab: String.t() | nil  (当前活跃文件路径)
  # selected_text: String.t()     (Monaco 选区文本，由 MonacoSelection Hook 推送)
  # cursor: %{line: integer(), column: integer()}
  # save_status: :saved | :unsaved | :saving | :error
end
```

### 4.4 Monaco Editor 渲染

```heex
<LiveMonacoEditor.code_editor
  id="writer-monaco-editor"
  path={@active_tab}
  value={active_tab_content(@open_tabs, @active_tab)}
  style="height: 100%; width: 100%;"
  change="content_changed"
  target={@myself}
  opts={
    Map.merge(
      LiveMonacoEditor.default_opts(),
      %{
        "language" => active_tab_language(@open_tabs, @active_tab),
        "theme" => "vs-dark",
        "fontSize" => 13,
        "minimap" => %{"enabled" => false},
        "wordWrap" => "on",
        "scrollBeyondLastLine" => false
      }
    )
  }
/>
```

### 4.5 语言自动检测

```elixir
defp detect_language(path) do
  case Path.extname(path) do
    ".ex" -> "elixir"
    ".exs" -> "elixir"
    ".js" -> "javascript"
    ".ts" -> "typescript"
    ".md" -> "markdown"
    ".json" -> "json"
    ".yaml" -> "yaml"
    ".yml" -> "yaml"
    ".html" -> "html"
    ".heex" -> "html"
    ".css" -> "css"
    ".toml" -> "toml"
    ".rs" -> "rust"
    ".py" -> "python"
    _ -> "plaintext"
  end
end
```

### 4.6 上下文注入的 snippet 格式

注入到 LLM 的消息格式：

```elixir
# 选中片段注入
defp emit_pending_context(socket, %{type: :snippet, path: path, content: text, line_range: range}) do
  relative = Path.relative_to_cwd(path)
  range_str = if range, do: " (lines #{range.start}-#{range.end})", else: ""

  context_msg = %{
    role: "user",
    content: "[Context: #{relative}#{range_str}]\n```\n#{text}\n```"
  }

  emit_context_add(socket, context_msg, "/ui/editor/context")
end
```

这样 LLM 能清楚知道上下文来源和范围，比盲目 read_file 整个文件精准得多。

### 4.7 UI 布局

```
┌─ Editor ──────────────────────────────────────────────┐
│ [registry.ex ×] [config.exs ×]                        │  ← 标签栏
├───────────────────────────────────────────────────────┤
│                                                        │
│  ┌─ Monaco Editor ──────────────────────────────────┐  │
│  │  1 │ defmodule Cortex.Tools.Registry do          │  │
│  │  2 │   use GenServer                             │  │
│  │  3 │   ████████████████████  ← 选中片段          │  │
│  │  4 │   ...                                       │  │
│  └──────────────────────────────────────────────────┘  │
│                                                        │
├───────────────────────────────────────────────────────┤
│ Ln 3, Col 5 | elixir | ● Unsaved   [注入上下文] [保存] │  ← 状态/操作栏
└───────────────────────────────────────────────────────┘
```

样式遵循现有 Cortex 设计语言：
- 背景: `bg-slate-950`
- 边框: `border-slate-800`
- 强调色: `teal-600`
- Monaco theme: `vs-dark`

---

## 5. 安全

- 路径校验复用 `Security.validate_path_with_folders/3`
- 只能打开已授权路径下的文件（复用 `PermissionTracker`）
- 大文件 (>1MB) 拒绝打开，提示用户使用外部编辑器
- 文件内容不经过 SignalHub（避免大 payload 污染信号总线），仅通过 LiveView assign 传递

---

## 6. 与现有系统集成

| 集成点 | 方式 |
|---|---|
| `file.changed.*` 信号 | Agent 修改文件后，`handle_file_changed` 触发 `LiveMonacoEditor.set_value` 刷新编辑器 |
| `pending_context` 机制 | 新增 `:snippet` 类型，复用 `maybe_emit_pending_context` / `emit_context_add` |
| FileBrowserComponent | 文件项增加"在编辑器中打开"选项 |
| ChatPanel | Agent 输出中的文件路径可点击，在编辑器中打开 |
| WriteFile handler | 编辑器保存直接调用，复用安全校验和信号发射 |
| MonacoEditorSync Hook | `highlight_line` 可用于 Agent 指出修改位置时高亮对应行 |

---

## 7. 任务分解 (DAG)

```
Phase 1: 基础设施
  T1: 添加 live_monaco_editor 依赖 + JS/CSS 集成
  T2: 创建 monaco_hooks.js (MonacoEditorSync + MonacoSelection)
  T3: 注册 Hook 到 app.js

Phase 2: 编辑器组件
  T4: EditorComponent 骨架 (LiveComponent + tabs + Monaco + 状态栏)  [依赖 T1-T3]
  T5: JidoLive 集成 (editor panel 切换 + open_file 路由)  [依赖 T4]

Phase 3: 文件操作
  T6: 打开文件 (ReadFile + 安全校验 + 语言检测 + 大文件保护)  [依赖 T5]
  T7: 保存文件 (content_changed → dirty 标记 → Ctrl+S → WriteFile)  [依赖 T6]
  T8: Agent 修改后自动刷新 (file.changed → set_value)  [依赖 T6]
  T9: 多标签页 (切换/关闭/未保存提示)  [依赖 T6]

Phase 4: 上下文注入
  T10: 选中文本追踪 (MonacoSelection → selected_text)  [依赖 T4]
  T11: 注入上下文按钮 (snippet pending_context + emit_pending_context 处理)  [依赖 T10]

Phase 5: 入口集成
  T12: FileBrowser "在编辑器中打开" 入口  [依赖 T6]
  T13: ChatPanel 文件路径可点击打开  [依赖 T6]
```

---

## 8. BDD 场景

```gherkin
Feature: 内置简易编辑器

  Scenario: Agent 修改文件后自动刷新编辑器
    Given Agent 通过 edit_file 修改了 "lib/app.ex"
    When SignalHub 发射 "file.changed.edit" 信号
    And 编辑器中已打开 "lib/app.ex"
    Then Monaco Editor 内容自动刷新为最新版本

  Scenario: 用户在编辑器中微调并保存
    Given 编辑器中已打开 "lib/app.ex"
    When 用户修改内容
    Then 状态栏显示 "Unsaved"
    When 用户按 Ctrl+S
    Then 文件写入磁盘
    And 状态栏显示 "Saved"

  Scenario: 选中片段注入 LLM 上下文
    Given 编辑器中已打开 "lib/cortex/tools/registry.ex"
    When 用户选中第 10-25 行的代码
    And 点击 "注入上下文"
    Then pending_context 设置为 snippet 类型
    And 包含选中文本、文件路径和行范围
    When 用户在 Chat 中发送消息
    Then LLM 收到的上下文包含 "[Context: cortex/tools/registry.ex (lines 10-25)]"

  Scenario: 未选中文本时注入全文
    Given 编辑器中已打开 "config/dev.exs"
    When 用户未选中任何文本
    And 点击 "注入上下文"
    Then 整个文件内容作为 pending_context 注入

  Scenario: 自动检测语言
    Given 用户打开 "lib/app.ex"
    Then Monaco Editor 语言设置为 "elixir"
    When 用户切换到 "assets/js/app.js" 标签
    Then Monaco Editor 语言切换为 "javascript"

  Scenario: 拒绝打开未授权路径
    Given 用户未授权 "/etc" 文件夹
    When 尝试在编辑器中打开 "/etc/passwd"
    Then 显示权限拒绝提示

  Scenario: 拒绝打开大文件
    Given 存在 2MB 的文件
    When 尝试在编辑器中打开
    Then 显示 "文件过大，请使用外部编辑器" 提示
```

---

## 9. 后续可选增强 (不在本次范围)

- Agent 修改文件时高亮变更行（`highlight_line` 事件已在 Hook 中实现）
- 搜索替换 (Ctrl+F，Monaco 内置)
- LLM 上下文标注标记（持久化的锚点注释）
- Diff 视图（Monaco 内置 diff editor）
- 从 Chat 中点击 tool call 结果直接跳转到编辑器对应行

---

## 10. BDD 驱动迭代流程

1. **规划** (当前) → 架构分析 + 任务 DAG + BDD 场景
2. **BDD 编译** → Gherkin 场景编译为 ExUnit 测试骨架 (`bddc`)
3. **红灯** → 运行测试确认全部失败
4. **逐任务实现** → 按 DAG 顺序 T1→T13
5. **绿灯** → 所有 BDD 场景通过

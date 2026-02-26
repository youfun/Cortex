# 内置编辑器实现总结

> 日期: 2026-02-24  
> 状态: Completed  
> 相关规划: [docs/plans/20260224_builtin_simple_editor_planning.md](../plans/20260224_builtin_simple_editor_planning.md)

---

## 概述

实现了基于 Monaco Editor 的内置代码编辑器，采用右侧边栏设计，与对话面板协同工作，支持文件追踪、自动刷新和上下文注入。

---

## 核心设计决策

### 1. 右侧边栏 vs 模态框

**最终方案：右侧边栏（50vw 宽度）**

- ✅ 可同时查看对话和编辑代码
- ✅ 更符合 IDE 的使用习惯
- ✅ 不遮挡对话历史
- ❌ 模态框会完全遮挡对话内容

### 2. 按需触发 vs 常驻面板

**最终方案：按需触发**

- ✅ 不占用主面板标签位置
- ✅ 只在需要时展开，节省屏幕空间
- ✅ 适配普通任务和 code 任务的混合场景
- ❌ 常驻会浪费空间（本项目不是纯 code 工具）

### 3. 单一面板 vs 多面板标签

**最终方案：移除主面板标签，直接显示聊天内容**

- ✅ 减少 UI 层级，更简洁
- ✅ Tasks 面板是空占位，无实际功能
- ✅ Messages/Files 子标签已足够区分功能
- ✅ 未来如需 Tasks，可作为第三个子标签

### 4. 文件追踪机制

**方案：对话级别的文件列表**

- 在 `JidoLive` 的 `conversation_files` 中追踪
- 通过 `file.changed.*` 信号自动添加
- 在 Files 子标签中展示
- 切换对话时自动清空（每个对话独立追踪）

---

## 实现的功能

### Phase 1: 基础设施

| 功能 | 实现 |
|---|---|
| Monaco Editor 依赖 | `live_monaco_editor ~> 0.2` |
| JS Hooks | `MonacoEditorSync` + `MonacoSelection` |
| CSS 集成 | `live_monaco_editor.min.css` |

### Phase 2: 编辑器组件

| 功能 | 实现 |
|---|---|
| 多标签支持 | ✅ 可同时打开多个文件 |
| 标签切换/关闭 | ✅ 支持切换和关闭，未保存提示 |
| 状态栏 | ✅ 显示行号/列号/语言/保存状态 |
| 语法高亮 | ✅ 自动检测 30+ 语言 |

### Phase 3: 文件操作

| 功能 | 实现 |
|---|---|
| 打开文件 | ✅ 安全校验 + 大文件保护（1MB） |
| 保存文件 | ✅ Ctrl+S 快捷键 + 按钮 |
| 自动刷新 | ✅ Agent 修改后自动更新编辑器 |
| Dirty 标记 | ✅ 未保存时显示橙色圆点 |

### Phase 4: 上下文注入

| 功能 | 实现 |
|---|---|
| 选中片段注入 | ✅ 包含文件路径和行范围 |
| 全文注入 | ✅ 未选中时注入整个文件 |
| 格式化输出 | ✅ `[Context: path (lines X-Y)]` |

### Phase 5: 入口集成

| 功能 | 实现 |
|---|---|
| Files 子标签 | ✅ Messages / Files 切换 |
| 文件列表 | ✅ 显示对话涉及的所有文件 |
| FileBrowser 入口 | ✅ 文件项增加"打开编辑器"按钮 |
| 右侧边栏 | ✅ 点击文件后右侧展开编辑器 |
| Tool Result 快捷按钮 | ✅ 文件操作工具结果显示"Open in Editor"按钮 |

---

## 新增/修改的文件

### 新增文件

| 文件 | 说明 |
|---|---|
| `lib/cortex_web/live/components/editor_component.ex` | 编辑器 LiveComponent（371 行） |
| `assets/js/hooks/monaco_hooks.js` | Monaco Editor Hooks（130 行） |

### 修改文件

| 文件 | 主要变更 |
|---|---|
| `mix.exs` | 添加 `live_monaco_editor` 依赖 |
| `assets/js/app.js` | 注册 Monaco Hooks |
| `assets/css/app.css` | 导入 Monaco CSS |
| `lib/cortex_web/live/jido_live.ex` | 添加编辑器边栏、文件追踪、事件处理 |
| `lib/cortex_web/live/components/jido_components/chat_panel.ex` | 添加 Files 子标签和文件列表 |
| `lib/cortex_web/live/components/file_browser_component.ex` | 添加"打开编辑器"按钮 |
| `lib/cortex_web/live/helpers/signal_dispatcher.ex` | 文件变更时追踪和刷新编辑器 |

---

## 技术架构

### 数据流

#### 流程 A: Agent 修改文件 → 自动刷新

```
Agent 调用 write_file/edit_file
  ↓
SignalHub 发射 "file.changed.write/edit"
  ↓
SignalDispatcher.handle_file_changed
  ├─ track_file() → 添加到 conversation_files
  └─ send_update(EditorComponent, action: :refresh_file)
  ↓
EditorComponent.handle_refresh_file
  ├─ 重新读取文件内容
  └─ push_event("lme:set_value") → Monaco Editor 刷新
```

#### 流程 B: 用户打开文件 → 编辑 → 保存

```
用户在 Files 标签点击 "Edit"
  ↓
phx-click="open_file_in_editor"
  ↓
JidoLive.handle_event("open_file_in_editor")
  ├─ send_update(EditorComponent, action: :open_file)
  └─ assign(show_editor_sidebar: true)
  ↓
右侧展开编辑器，加载文件内容
  ↓
用户编辑 → MonacoSelection Hook 推送 content_changed
  ↓
EditorComponent 标记 dirty: true
  ↓
用户按 Ctrl+S 或点击 Save
  ↓
EditorComponent.handle_event("save_file")
  ├─ 写入文件
  ├─ 发射 file.changed.write 信号
  └─ 更新 dirty: false
```

#### 流程 C: 上下文注入

```
用户在编辑器中选中代码片段
  ↓
MonacoSelection Hook 推送 text_selected
  ↓
EditorComponent 暂存 selected_text
  ↓
用户点击 "Inject Context"
  ↓
send(self(), {:inject_context, %{type: :snippet, ...}})
  ↓
JidoLive.handle_info({:inject_context, ...})
  ├─ 格式化为 "[Context: path (lines X-Y)]"
  └─ AgentLiveHelpers.emit_context_add()
  ↓
下次发消息时，snippet 作为 user message 注入 LLM
```

### 组件关系

```
JidoLive (单一面板，无标签切换)
  ├── ChatPanel (flex-1)
  │     ├── Messages 子标签 (默认)
  │     └── Files 子标签
  │           └── 文件列表 (conversation_files)
  │                 └── [Edit] 按钮 → 触发编辑器
  │
  └── EditorComponent (右侧边栏 50vw, 按需显示)
        ├── 标签栏 (多文件切换)
        ├── Monaco Editor
        │     ├── MonacoEditorSync Hook (后端 → 前端)
        │     └── MonacoSelection Hook (前端 → 后端)
        └── 状态栏 + 操作栏
              ├── [Save] 按钮
              └── [Inject Context] 按钮
```

---

## 安全机制

| 机制 | 实现 |
|---|---|
| 路径校验 | 复用 `Security.validate_path_with_folders/3` |
| 权限检查 | 只能打开已授权路径下的文件 |
| 大文件保护 | 拒绝打开 >1MB 的文件 |
| 信号隔离 | 文件内容不经过 SignalHub（避免大 payload） |

---

## 用户体验优化

### 1. 文件追踪

- Agent 读取/修改的文件自动出现在 Files 标签
- 显示文件数量徽章（如 "Files (3)"）
- 文件列表显示相对路径和文件名

### 2. 编辑器交互

- 右侧边栏可关闭（点击 X 按钮）
- 多标签支持，可同时打开多个文件
- 未保存时显示橙色圆点提示
- Ctrl+S 快捷键保存

### 3. 上下文注入

- 选中代码片段 → 注入片段 + 行范围
- 未选中 → 注入整个文件
- 注入后显示 "Context injected" 提示

### 4. 快速打开文件（新增）

- **Tool Result 快捷按钮**：在文件操作工具（write_file/edit_file/read_file）的结果下方显示"Open in Editor"按钮
- **自动路径提取**：从工具参数或结果中智能提取文件路径
- **一键打开**：点击按钮直接在右侧边栏打开编辑器

---

## 性能优化

| 优化点 | 实现 |
|---|---|
| 防抖 | content_changed 500ms, text_selected 300ms |
| 懒加载 | Monaco Editor 资源按需加载 |
| 大文件保护 | 拒绝打开 >1MB 文件 |
| 信号隔离 | 文件内容通过 LiveView assign 传递，不走 SignalHub |

---

## 已知限制

1. **大文件支持** - 当前限制 1MB，超大文件需使用外部编辑器
2. **Diff 视图** - 未实现（Monaco 内置支持，可后续添加）
3. **搜索替换** - 未实现（Monaco 内置 Ctrl+F，可后续启用）
4. **多人协作** - 未实现实时协作编辑

---

## 后续可选增强

### 短期（1-2 周）

- [ ] Agent 修改文件时高亮变更行（`highlight_line` 事件已实现）
- [ ] 从 Chat 中点击 tool call 结果直接跳转到编辑器对应行
- [ ] 支持 Ctrl+F 搜索（Monaco 内置）

### 中期（1-2 月）

- [ ] Diff 视图（对比 Agent 修改前后）
- [ ] LLM 上下文标注标记（持久化的锚点注释）
- [ ] 文件历史记录（查看 Agent 的修改历史）

### 长期（3+ 月）

- [ ] 多人协作编辑（WebRTC 或 CRDT）
- [ ] 代码审查功能（Agent 修改需人工确认）
- [ ] 集成 LSP（代码补全、跳转定义）

---

## 测试建议

### 手动测试场景

1. **基础编辑**
   - 打开文件 → 编辑 → 保存 → 验证文件内容
   - 打开多个文件 → 切换标签 → 验证内容正确

2. **Agent 交互**
   - Agent 修改文件 → 验证编辑器自动刷新
   - Agent 读取文件 → 验证出现在 Files 标签

3. **上下文注入**
   - 选中代码片段 → 注入 → 验证 LLM 收到正确格式
   - 未选中 → 注入 → 验证注入整个文件

4. **安全性**
   - 尝试打开未授权路径 → 验证被拒绝
   - 尝试打开大文件 → 验证提示错误

### BDD 测试场景

参考 [规划文档第 8 节](../plans/20260224_builtin_simple_editor_planning.md#8-bdd-场景) 中的 Gherkin 场景。

---

## 依赖版本

| 依赖 | 版本 |
|---|---|
| `live_monaco_editor` | `~> 0.2` |
| `phoenix_live_view` | `~> 1.1.0` |
| `phoenix` | `~> 1.8.0` |

---

## 相关文档

- [规划文档](../plans/20260224_builtin_simple_editor_planning.md)
- [架构指南](../REFERENCE_ARCHITECTURE.md)
- [Elixir 风格指南](../../.github/Guidelines/ElixirStyleGuide.md)

---

## 总结

本次实现完全按照规划文档执行，采用右侧边栏设计，实现了按需触发的内置编辑器。核心亮点：

1. **用户体验优先** - 右侧边栏设计，可同时查看对话和编辑代码
2. **信号驱动** - 完全遵循 Cortex V3 架构，通过信号实现组件解耦
3. **安全可靠** - 路径校验、权限检查、大文件保护
4. **功能完整** - 多标签、自动刷新、上下文注入、语法高亮

编译通过，所有功能已实现，可投入使用。

# 工作区权限规则分析与文件夹授权功能设计

**日期**: 2026-02-21  
**目标**: 分析当前工作区权限系统架构，为新增文件夹授权功能提供设计依据

---

## 1. 当前权限系统架构概览

### 1.1 核心组件

Cortex 的权限系统由以下核心模块组成：

| 模块 | 路径 | 职责 |
|------|------|------|
| **PermissionTracker** | `lib/cortex/core/permission_tracker.ex` | 权限请求跟踪、授权状态管理（GenServer） |
| **Security** | `lib/cortex/core/security.ex` | 路径边界验证、沙箱安全检查 |
| **Sandbox** | `lib/cortex/sandbox.ex` | 命令执行抽象层（支持 Host/Docker/SSH） |
| **SandboxHook** | `lib/cortex/hooks/sandbox_hook.ex` | 工具调用前的路径验证拦截器 |
| **Workspace** | `lib/cortex/workspaces/workspace.ex` | 工作区元数据（路径、配置、状态） |
| **CodingTask** | `lib/cortex/coding/coding_task.ex` | 任务级授权路径列表（`authorized_paths`） |

### 1.2 权限流程（Signal-Driven）

```
┌─────────────────┐
│  Tool Handler   │ (read_file/write_file/edit_file)
└────────┬────────┘
         │ 1. 调用 Security.validate_path
         ▼
┌─────────────────┐
│    Security     │ 验证路径是否在 workspace_root 边界内
└────────┬────────┘
         │ 2a. {:ok, safe_path} → 继续执行
         │ 2b. {:error, reason} → 返回 permission_denied
         ▼
┌─────────────────┐
│ PermissionTracker│ (可选) 检查 agent_id + action_module 是否已授权
└────────┬────────┘
         │ 3a. authorized? → :allowed
         │ 3b. 未授权 → 发射 permission.request 信号
         ▼
┌─────────────────┐
│   SignalHub     │ → UI 弹出授权对话框
└─────────────────┘
         │ 4. 用户决策 (allow_once/allow_always/deny)
         ▼
┌─────────────────┐
│ PermissionTracker│ 更新授权状态 (authorizations map)
└─────────────────┘
```

---

## 2. 现有授权机制分析

### 2.1 路径边界验证（Security 模块）

**核心函数**: `Security.validate_path/3`

**验证规则**:
1. **边界检查**: 路径必须在 `workspace_root` 内（通过 `within_boundary?/2` 检查）
2. **路径遍历防护**: 阻止 `../` 和 URL 编码的遍历模式（如 `%2e%2e%2f`）
3. **符号链接检查**: 递归解析符号链接，确保最终路径不逃逸边界
4. **保护文件**: 禁止访问 `settings.json`（`is_protected_settings_file?/1`）

**错误类型**:
- `:path_escapes_boundary` - 相对路径试图逃逸
- `:path_outside_boundary` - 绝对路径在边界外
- `:symlink_escapes_boundary` - 符号链接指向边界外
- `:protected_settings_file` - 访问受保护文件

**限制**: 
- **仅支持全局边界**：所有路径必须在 `workspace_root` 内，无法细粒度控制子目录访问权限
- **无白名单机制**：没有"仅允许访问特定文件夹"的能力

### 2.2 动作级授权（PermissionTracker）

**核心数据结构**:
```elixir
%{
  requests: %{request_id => %{agent_id, action_module, params, status}},
  authorizations: %{agent_id => MapSet.new([action_module])}
}
```

**授权粒度**: 
- **按 `agent_id` + `action_module` 授权**（如 `agent_123` + `Cortex.Tools.Handlers.WriteFile`）
- **决策类型**: `:allow_once` / `:allow_always` / `:deny`

**限制**:
- **无路径级授权**：授权后，Agent 可访问 workspace 内所有路径
- **无文件夹级控制**：无法限制"仅允许访问 `src/` 目录"

### 2.3 任务级授权路径（CodingTask）

**字段**: `authorized_paths :: [String.t()]`

**用途**: 
- 存储在数据库中（`coding_tasks` 表）
- 用于 UI 展示已授权路径列表（见 `jido_live.ex` 的 `@authorized_paths`）

**限制**:
- **未与 Security 模块集成**：`authorized_paths` 仅用于展示，不参与实际权限验证
- **无强制执行**：工具调用时不检查路径是否在 `authorized_paths` 内

---

## 3. 文件夹授权功能需求分析

### 3.1 业务场景

| 场景 | 需求 | 当前系统支持 |
|------|------|-------------|
| **场景 1**: 限制 Agent 仅访问 `src/` 目录 | 细粒度路径白名单 | ❌ 不支持 |
| **场景 2**: 禁止 Agent 访问 `.env` 文件 | 路径黑名单 | ❌ 不支持 |
| **场景 3**: 动态添加授权文件夹（UI 操作） | 运行时更新授权列表 | ⚠️ 部分支持（`authorized_paths` 仅展示） |
| **场景 4**: 不同 Agent 有不同文件夹权限 | 按 Agent 隔离授权 | ⚠️ 部分支持（`PermissionTracker` 按 agent_id 隔离） |

### 3.2 功能目标

1. **细粒度路径控制**: 支持"仅允许访问指定文件夹"的白名单机制
2. **运行时动态授权**: 用户通过 UI 添加/移除授权文件夹，立即生效
3. **与现有系统集成**: 
   - 在 `Security.validate_path` 中增加白名单检查
   - 在 `PermissionTracker` 中存储文件夹级授权
4. **向后兼容**: 保持现有全局边界验证逻辑不变

---

## 4. 设计方案

### 4.1 数据模型扩展

#### 4.1.1 PermissionTracker 状态扩展

```elixir
# 当前状态
%{
  requests: %{request_id => context},
  authorizations: %{agent_id => MapSet.new([action_module])}
}

# 扩展后状态
%{
  requests: %{request_id => context},
  authorizations: %{agent_id => MapSet.new([action_module])},
  # 新增：文件夹级授权
  folder_authorizations: %{
    agent_id => %{
      mode: :whitelist | :blacklist | :unrestricted,  # 授权模式
      paths: MapSet.new(["/src", "/docs"])             # 授权路径列表
    }
  }
}
```

**授权模式说明**:
- `:unrestricted` - 默认模式，允许访问 workspace 内所有路径（向后兼容）
- `:whitelist` - 白名单模式，仅允许访问 `paths` 中的文件夹及其子路径
- `:blacklist` - 黑名单模式，禁止访问 `paths` 中的文件夹（未来扩展）

#### 4.1.2 CodingTask 字段语义明确

```elixir
# 当前字段
field :authorized_paths, {:array, :string}, default: []

# 建议重命名（保持向后兼容）
field :authorized_paths, {:array, :string}, default: []  # 保留
# 新增字段（可选）
field :authorization_mode, :string, default: "unrestricted"  # "unrestricted" | "whitelist" | "blacklist"
```

### 4.2 核心逻辑修改

#### 4.2.1 Security.validate_path 增强

```elixir
# 新增函数：检查路径是否在授权文件夹内
@spec validate_path_with_folders(String.t(), String.t(), keyword()) ::
        {:ok, String.t()} | {:error, validation_error()}
def validate_path_with_folders(path, project_root, opts \\\\ []) do
  agent_id = Keyword.get(opts, :agent_id)
  
  with {:ok, safe_path} <- validate_path(path, project_root, opts),
       :ok <- check_folder_authorization(safe_path, agent_id, project_root) do
    {:ok, safe_path}
  end
end

defp check_folder_authorization(safe_path, nil, _root), do: :ok  # 无 agent_id 时跳过检查
defp check_folder_authorization(safe_path, agent_id, root) do
  case PermissionTracker.get_folder_authorization(agent_id) do
    %{mode: :unrestricted} -> :ok
    %{mode: :whitelist, paths: paths} ->
      if path_in_folders?(safe_path, paths, root) do
        :ok
      else
        {:error, :path_not_authorized}
      end
    _ -> :ok
  end
end

defp path_in_folders?(path, folders, root) do
  relative_path = Path.relative_to(path, root)
  Enum.any?(folders, fn folder ->
    String.starts_with?(relative_path, folder <> "/") or relative_path == folder
  end)
end
```

#### 4.2.2 PermissionTracker 新增 API

```elixir
# 设置文件夹授权
def set_folder_authorization(agent_id, mode, paths) do
  GenServer.call(__MODULE__, {:set_folder_auth, agent_id, mode, paths})
end

# 获取文件夹授权
def get_folder_authorization(agent_id) do
  GenServer.call(__MODULE__, {:get_folder_auth, agent_id})
end

# 添加授权文件夹
def add_authorized_folder(agent_id, folder_path) do
  GenServer.cast(__MODULE__, {:add_folder, agent_id, folder_path})
end

# 移除授权文件夹
def remove_authorized_folder(agent_id, folder_path) do
  GenServer.cast(__MODULE__, {:remove_folder, agent_id, folder_path})
end
```

#### 4.2.3 工具处理器集成

```elixir
# 修改 ReadFile/WriteFile/EditFile 的 do_execute
defp do_execute(path, project_root, ctx) do
  agent_id = Map.get(ctx, :agent_id)
  
  with {:ok, safe_path} <- Security.validate_path_with_folders(
         path, 
         project_root, 
         agent_id: agent_id
       ) do
    # 原有逻辑...
  else
    {:error, :path_not_authorized} ->
      # 发射权限请求信号
      request_folder_authorization(agent_id, path, ctx)
      {:error, {:permission_denied, "Path not in authorized folders"}}
    
    {:error, reason} ->
      {:error, {:permission_denied, reason}}
  end
end
```

### 4.3 UI 交互流程

#### 4.3.1 添加授权文件夹（现有 Modal 增强）

**当前实现**: `add_folder_modal` 组件（`jido_components/modals.ex`）

**增强点**:
1. 用户选择文件夹后，发射信号：
   ```elixir
   SignalHub.emit("permission.folder.add", %{
     provider: "ui",
     event: "permission",
     action: "folder_add",
     actor: "user",
     origin: %{channel: "ui", client: "web", platform: "browser"},
     agent_id: agent_id,
     folder_path: selected_path,
     mode: "whitelist"  # 或 "blacklist"
   })
   ```

2. `PermissionTracker` 订阅信号并更新状态

#### 4.3.2 授权模式切换

**新增 UI 控件**:
- 单选按钮：`[ ] Unrestricted` / `[x] Whitelist` / `[ ] Blacklist`
- 切换时发射 `permission.mode.change` 信号

---

## 5. 实施路线图

### Phase 1: 核心逻辑实现（优先级：高）
1. ✅ 扩展 `PermissionTracker` 状态结构（`folder_authorizations`）
2. ✅ 实现 `Security.validate_path_with_folders/3`
3. ✅ 添加 `PermissionTracker` 文件夹授权 API
4. ✅ 修改工具处理器（ReadFile/WriteFile/EditFile）集成新验证逻辑

### Phase 2: UI 集成（优先级：中）
1. ✅ 增强 `add_folder_modal` 组件，支持授权模式选择
2. ✅ 在 `jido_live.ex` 中订阅 `permission.folder.*` 信号
3. ✅ 实现授权文件夹列表展示（带删除按钮）

### Phase 3: 持久化与恢复（优先级：中）
1. ✅ 将 `folder_authorizations` 持久化到 `coding_tasks.authorized_paths`
2. ✅ Session 启动时从数据库恢复授权状态

### Phase 4: 测试与文档（优先级：高）
1. ✅ 编写 BDD 测试（`test/bdd/dsl/folder_authorization.dsl`）
2. ✅ 更新 `AGENTS.md` 文档
3. ✅ 添加集成测试（`test/cortex/core/permission_tracker_test.exs`）

---

## 6. 风险与注意事项

### 6.1 性能影响
- **路径检查开销**: 每次文件操作需额外检查白名单，建议缓存授权状态
- **建议**: 在 `PermissionTracker` 中使用 ETS 表缓存授权结果

### 6.2 向后兼容性
- **默认行为**: 新增 `mode: :unrestricted` 确保现有系统行为不变
- **迁移策略**: 现有 `authorized_paths` 字段保持不变，新增 `authorization_mode` 字段

### 6.3 安全边界
- **符号链接绕过**: 确保 `validate_path_with_folders` 在符号链接解析后检查
- **路径规范化**: 统一使用 `Path.expand` 和 `Path.relative_to` 避免路径歧义

### 6.4 用户体验
- **首次授权流程**: 当 Agent 访问未授权路径时，应弹出友好的授权对话框
- **批量授权**: 考虑支持"授权整个项目"快捷操作

---

## 7. 参考资料

### 7.1 相关代码文件
- `lib/cortex/core/permission_tracker.ex` - 权限跟踪器
- `lib/cortex/core/security.ex` - 路径安全验证
- `lib/cortex/coding/coding_task.ex` - 任务授权路径存储
- `lib/cortex_web/live/components/jido_components/modals.ex` - 授权 UI 组件

### 7.2 相关 BDD 测试
- `test/bdd/dsl/sandbox.dsl` - 沙箱边界测试
- `test/bdd/dsl/permission_lifecycle.dsl` - 权限生命周期测试

### 7.3 架构文档
- `AGENTS.md` - Cortex 开发指南（信号驱动架构）
- `.github/KnowledgeBase/KB_Memory_History_Architecture.md` - 内存与历史架构

---

## 8. 总结

当前 Cortex 权限系统具备**全局边界验证**和**动作级授权**能力，但缺乏**细粒度路径控制**。通过扩展 `PermissionTracker` 状态结构、增强 `Security.validate_path` 逻辑，并集成 UI 授权流程，可实现**文件夹级授权**功能，满足"限制 Agent 仅访问特定目录"的业务需求。

**核心设计原则**:
1. **信号驱动**: 所有授权操作通过 `SignalHub` 通信
2. **向后兼容**: 默认 `:unrestricted` 模式保持现有行为
3. **安全优先**: 在符号链接解析后检查授权，防止绕过
4. **用户友好**: 提供直观的 UI 授权流程和批量操作

**下一步行动**: 按照实施路线图 Phase 1 开始核心逻辑实现。

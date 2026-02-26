# Cortex

[English](./README.md)

基于 Elixir/Phoenix 和 BEAM VM 构建的信号驱动个人智能体工作站。Cortex 提供本地优先、多通道的 AI 助理能力，遵循极简工具哲学和自进化技能系统。

## 特性

- **信号驱动架构** — 符合 CloudEvents 1.0.2 规范的信号总线 (`SignalHub`)，所有跨组件通信统一走信号，支持全量审计与回放。
- **4 核心工具** — `read_file`、`write_file`、`edit_file`、`shell`。其余功能通过技能扩展。
- **多通道接入** — Web UI (Phoenix LiveView)、Telegram Bot、飞书 Bot。所有通道共享统一的信号入口。
- **记忆系统** — 潜意识记忆，包含知识图谱、工作记忆、观察、反思和偏好追踪。支持 Token 预算感知的上下文构建。
- **Tape 优先历史** — 每个会话独立的不可变 JSONL 磁带 (`./tape/`)，驱动审计、UI 回放和 LLM 上下文恢复。
- **自进化技能** — 热加载的 Markdown 技能文件，放在 `skills/` 目录下，文件变更后数秒内自动注入 Agent 提示词。
- **安全沙箱** — 路径穿越拦截、危险命令审批流程。
- **Hook 系统** — 可扩展的 Agent 生命周期钩子（权限、沙箱、记忆、技能调用）。
- **桌面应用** — Tauri v2 封装，提供原生桌面体验。
- **TTS** — 计划中（文本转语音节点管理）。
- **LLM 灵活切换** — 通过 `req_llm` 配置多 LLM 提供商，支持运行时切换模型。

## 工作区与权限

- **默认工作区根目录**：`~/.cortex/workspace`
- **自定义**：通过应用配置 `:cortex, :workspace_root`（例如在 `config/runtime.exs`）
- **沙箱**：文件与 shell 工具被限制在工作区根目录内，禁止越界路径访问。

## 快速开始

### 环境要求

- Elixir 1.14+ / Erlang OTP 27+
- SQLite3
- Bun（前端资源构建）

### 安装

```bash
mix setup        # deps.get + ecto.setup + assets.setup + assets.build
mix phx.server   # 启动服务，访问 localhost:4000
```

### 开发

```bash
mix test          # 运行测试
mix format        # 格式化代码
mix credo         # 静态分析
mix precommit     # 全部质量检查
```

## 运行编译后的二进制

如果使用 Burrito 产物（例如 `burrito_out/jido_studio_linux`），需要通过环境变量启动，而不是 `mix`。

运行时最小环境变量：

- `RELEASE_NAME`：发布名（例如 `jido_studio`）
- `DATABASE_PATH`：SQLite 数据库文件路径
- `PORT`：HTTP 端口
- `PHX_SERVER`：必须为 `true`
- `SECRET_KEY_BASE`：密钥（不要提交到仓库）
- `AUTH_USER`：Basic Auth 用户名（默认 `admin`）
- `AUTH_PASS`：Basic Auth 密码（默认 `admin`）

示例：

```bash
export RELEASE_NAME=jido_studio
export DATABASE_PATH=./jido_studio_prod.db
export PORT=5005
export PHX_SERVER=true
export SECRET_KEY_BASE="<your-secret-key>"
export AUTH_USER="admin"
export AUTH_PASS="admin"

./jido_studio_linux
```

说明：

- 在任意开发机上运行 `mix phx.gen.secret` 生成新密钥。
- 密钥不要写进 `README`，也不要进入版本控制。

## 项目结构

```
lib/cortex/
├── signal_hub.ex          # 信号总线中枢
├── agents/                # LLM Agent、钩子、压缩、Token 计数
├── tools/handlers/        # 4 核心工具实现
├── memory/                # 潜意识、知识图谱、工作记忆
├── history/               # Tape、信号记录器、双轨过滤
├── session/               # 会话协调器、分支管理
├── skills/                # 技能加载器 + 热重载监听
├── core/                  # 安全沙箱、权限追踪
├── hooks/                 # Agent 生命周期钩子
├── channels/              # Telegram、飞书、钉钉、企微、Discord 适配器
├── extensions/            # 扩展系统与钩子注册
├── shell/                 # Shell 执行引擎
└── tts/                   # 文本转语音

lib/cortex_web/
├── live/
│   ├── jido_live.ex       # 主 LiveView（信号驱动）
│   ├── settings_live/     # 设置与通道配置 UI
│   └── components/        # 聊天面板、UI 组件
└── controllers/           # Webhook 端点

src-tauri/                 # Tauri v2 桌面封装
skills/                    # 用户自定义技能（热加载）
```

## 架构

```
┌──────────────────────────────────────────────────┐
│              LiveView / Tauri UI                  │
└────────────────────┬─────────────────────────────┘
                     │ 订阅
┌────────────┐       ▼
│ Telegram / │──▶ 信号总线 (jido_signal)
│ 飞书 Bot   │    CloudEvents 路由 & PubSub
└────────────┘       │
       ┌─────────────┼──────────────┬──────────────┐
       ▼             ▼              ▼              ▼
   ┌───────┐   ┌──────────┐  ┌──────────┐   ┌─────────┐
   │ 工具  │   │ LLM Agent│  │  技能    │   │  Tape   │
   │ 引擎  │   │ + 记忆   │  │  加载器  │   │  历史   │
   └───────┘   └──────────┘  └──────────┘   └─────────┘
```

## 通道支持

| 通道     | 状态   |
|----------|--------|
| Web UI   | 已上线 |
| Telegram | 已上线 |
| 飞书     | 已上线 |
| 钉钉     | 计划中 |
| 企业微信 | 计划中 |
| Discord  | 计划中 |

## 参考项目

Cortex 基于 Jido 框架构建，并借鉴了多个参考项目的架构模式和最佳实践：

- **Jido** — 核心 Elixir Agent 框架，信号驱动架构
- **Gong** — Elixir Agent 引擎，ReAct 循环与钩子系统
- **OpenClaw China** — 中国 IM 平台集成模式
- **Pi Mono** — OpenClaw 核心依赖
- **Arbor** — 记忆系统，向量搜索与知识图谱

## 许可证

MIT

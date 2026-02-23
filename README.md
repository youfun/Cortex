# Cortex

[中文](./README_CN.md)

**A Signal-Driven Personal Agent Workstation**

Cortex is a minimalist personal agent platform built on Elixir/Phoenix, designed around signal-driven architecture and self-evolution principles.

## Features

- **Signal-Driven Architecture** — CloudEvents 1.0.2 compliant signal bus (`SignalHub`) for cross-component communication, full audit, and replay.
- **4 Core Tools** — `read_file`, `write_file`, `edit_file`, `shell`. Everything else is extended via skills.
- **Multi-Channel Access** — Web UI (Phoenix LiveView), Telegram Bot, Feishu Bot. All channels share a unified signal entry.
- **Memory System** — Subconscious memory with knowledge graph, working memory, observation, reflection, and preference tracking. Token-budget aware context building.
- **Tape-First History** — Immutable JSONL tape per session (`./tape/`), powering audit, UI playback, and LLM context recovery.
- **Self-Evolving Skills** — Hot-loadable Markdown skills in `skills/`, auto-injected into agent prompts within seconds.
- **Security Sandbox** — Path traversal protection and dangerous command approval flow.
- **Session Branching** — Create isolated exploration branches from any conversation point.
- **Hook System** — Extensible agent lifecycle hooks (permissions, sandbox, memory, skill invocation).
- **Desktop App** — Tauri v2 wrapper for native desktop experience.
- **TTS** — Planned (text-to-speech node management).
- **Flexible LLM Switching** — Configure multiple providers via `req_llm`, switch models at runtime.

## Workspace & Permissions

- **Default workspace root**: `~/.cortex/workspace`
- **Override**: set application env `:cortex, :workspace_root` (for example in `config/runtime.exs`)
- **Sandbox**: file and shell tools are constrained to the workspace root; path traversal outside the root is blocked by design.

## Quick Start

### Prerequisites

- Elixir 1.14+ / Erlang OTP 27+
- SQLite3
- Bun (frontend assets)

### Installation

```bash
mix setup        # deps.get + ecto.setup + assets.setup + assets.build
mix phx.server   # start server, visit localhost:4000
```

### Development

```bash
mix test          # run tests
mix format        # format code
mix credo         # static analysis
mix precommit     # full quality checks
```

## Running the Compiled Binary

If you use the Burrito release (e.g. `burrito_out/jido_studio_linux`), run it with environment variables instead of `mix`.

Minimum runtime variables:

- `RELEASE_NAME`: release name (for example `jido_studio`)
- `DATABASE_PATH`: path to the SQLite database file
- `PORT`: HTTP port
- `PHX_SERVER`: must be `true`
- `SECRET_KEY_BASE`: secret key (do not commit)
- `AUTH_USER`: basic auth username (default `admin`)
- `AUTH_PASS`: basic auth password (default `admin`)

Example:

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

Notes:

- Generate a new secret with `mix phx.gen.secret` on any dev machine.
- Keep secrets out of `README` and out of version control.

## Project Structure

```
lib/cortex/
├── signal_hub.ex          # Signal bus core
├── agents/                # LLM Agent, hooks, compaction, token counting
├── tools/handlers/        # 4 core tool implementations
├── memory/                # Subconscious, knowledge graph, working memory
├── history/               # Tape, signal recorder, dual-track filter
├── session/               # Session coordinator, branch manager
├── skills/                # Skill loader + hot reload watcher
├── core/                  # Security sandbox, permission tracking
├── hooks/                 # Agent lifecycle hooks
├── channels/              # Telegram, Feishu, Dingtalk, WeCom, Discord adapters
├── extensions/            # Extensions and hook registration
├── shell/                 # Shell execution engine
└── tts/                   # Text-to-speech

lib/cortex_web/
├── live/
│   ├── jido_live.ex       # Main LiveView (signal-driven)
│   ├── settings_live/     # Settings & channel configuration UI
│   └── components/        # Chat panel, UI components
└── controllers/           # Webhook endpoints

src-tauri/                 # Tauri v2 desktop wrapper
skills/                    # User-defined skills (hot-loadable)
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│              LiveView / Tauri UI                  │
└────────────────────┬─────────────────────────────┘
                     │ subscribes
┌────────────┐       ▼
│ Telegram / │──▶ Signal Bus (jido_signal)
│ Feishu Bot │    CloudEvents Router & PubSub
└────────────┘       │
       ┌─────────────┼──────────────┬──────────────┐
       ▼             ▼              ▼              ▼
   ┌───────┐   ┌──────────┐  ┌──────────┐   ┌─────────┐
   │ Tools │   │ LLM Agent│  │ Skills   │   │  Tape   │
   │ Engine│   │ + Memory │  │ Loader   │   │ History │
   └───────┘   └──────────┘  └──────────┘   └─────────┘
```

## Channel Support

| Channel  | Status   |
|----------|----------|
| Web UI   | Live     |
| Telegram | Live     |
| Feishu   | Live     |
| Dingtalk | Planned  |
| WeCom    | Planned  |
| Discord  | Planned  |

## Reference Projects

Cortex is built on the Jido framework and draws from multiple reference architectures and best practices:

- **Jido** — Core Elixir agent framework with signal-driven architecture
- **Gong** — Elixir agent engine with ReAct loops and hook system
- **OpenClaw China** — China IM platform integration patterns
- **Pi Mono** — TypeScript agent toolkit with modular design
- **Cli** — Command-line tools and compilers
- **Arbor** — Memory system with vector search and knowledge graphs

## License

MIT

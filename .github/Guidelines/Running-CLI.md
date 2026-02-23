# 运行 CLI 辅助脚本

- 对短期 CLI 脚本使用 `mix run`，并尽量放在 `lib/mix/tasks/` 或 `scripts/`，以便一致地调用。
- 避免在 mix 之外写速记的 Elixir 脚本，项目依赖 mix 加载配置与依赖。

## 常用命令
- `mix run -e "Code"` 用于快速在 shell 中执行片段（例如 `mix run -e "IO.inspect(MyApp.hello())"`）。
- `mix run --no-start priv/scripts/some_task.exs` 用于无需启动整个应用即可运行的脚本。

## JavaScript 工具链
- 若在 `assets/` 安装或运行 Node 工具，优先尝试 `bun`，若当前环境没有 `bun` 再退回 `npm`。
- 在 `assets/package.json` 的 scripts 中记录推荐命令（如 `bun install` 或 `bun run deploy`），这样无论包管理器怎么变，命令都可复用。

## 日志与信号
- 若 CLI 任务触及信号总线，只有在最后一次状态更新后才发射信号，并务必包含完整的 origin 元数据。
- 脚本退出前清理临时文件并关闭打开的进程，避免漏掉 socket 给其他 mix 任务。

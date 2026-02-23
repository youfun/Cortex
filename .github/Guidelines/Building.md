# 构建 Phoenix 应用

- 在仓库根目录下使用 `mix compile` 构建 Elixir 代码。
- **不要**试图手动运行 `elixirc` 或 `erlc`；`mix` 会为你管理编译路径、配置与 OTP 发布。

## 典型流程
1. `mix deps.get` 以确保依赖被拉取并编译（拉取分支或修改 `mix.exs` 后需运行一次）。
2. `mix compile` 编译应用程序与所有 umbrella 依赖。
3. 若 UI 资源有改动，进入 `assets/` 目录，先运行 `npm ci`（或 `npm install`）再跑 `npm run deploy`，最后执行 `mix phx.digest` 生成静态资源指纹。

## 构建错误排查
- 始终从 `mix` 输出入手——Elixir 编译器的日志是真正的依据。
- `mix compile` 会指出错误涉及的模块、函数与文件；确认根因后再重新运行命令。
- 如果在 `mix quality` 中看到 Credo 或 Dialyzer 警告，仅修复你引入的那部分（除非另有指示）。

## 发布脚本
- 在 Linux 或 WSL 中，运行 `./build.sh` 会执行 `mix deps.get`、编译应用、部署资源，并生成 Burrito 单文件二进制（`burrito_out/cortex_windows.exe`）。`MIX_ENV` 可选覆盖，默认 `prod`。
- 在 Windows 上，`build_studio.bat` 会先启动 VS 工具链，再调用 `elixir build-on-win.exs` 完成相同的发布步骤，必要时可把二进制拷贝到 Tauri 附属程序中。
- 若在 Windows 上碰到 bcrypt/vix 依赖问题，请重新运行 `build_bcrypt_elixir_at_win.bat`；它会执行 `chcp 65001`、设置 VC 变量，并在 `mix compile` 之前重新编译 `vix`。

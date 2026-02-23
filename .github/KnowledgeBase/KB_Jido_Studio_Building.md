# 构建与发布流程

## Linux / WSL
- `build.sh` 是 WSL 或 Linux 环境下的单脚本入口，它会设置 `MIX_ENV`（默认 `prod`）、拉取依赖、编译项目、部署/设置静态资源，并执行 `mix release cortex --overwrite`，最终让 Burrito 产出 `burrito_out/cortex_windows.exe`。
- 脚本还会读取 `mix.exs` 同步版本元数据，然后再调用 `mix release`，以确保生成的二进制版本与 mix 文件一致，无需人工修改。
- 在 WSL 内运行 `bash ./build.sh`，需要更改发布标签时可通过 `MIX_ENV=staging` 等方式覆盖。

## Windows
- `build_studio.bat` 会先调用 Visual Studio 的 `vcvarsall.bat` 初始化环境，再转给 `elixir build-on-win.exs`。该 Elixir 脚本与 `build.sh` 的逻辑一致，但以 Windows `cmd`/PowerShell 语境编写。
- `build-on-win.exs` 负责拉取依赖、编译应用、运行 `assets.setup`/`assets.deploy` 并生成 Burrito 发布包，它会打印 `mix.exs` 中检测到的版本号，方便核对最终输出的二进制名称。
- 若要面向 Tauri 前端，可在 `build-on-win.exs` 中取消注释 `copy_backend/2`、`build_tauri/0` 等辅助函数，待 Cargo/Tauri 支持恢复后即可启用。

## Windows 上的 bcrypt / vix 问题
- 如果 `vix` 依赖在 Windows 上编译失败，先运行 `build_bcrypt_elixir_at_win.bat`：它会执行 `chcp 65001`、加载 Visual Studio 环境变量，并提示 `mix deps.compile vix --force` 以便在主应用 `mix compile` 前重建 `vix`。
- 当原生扩展缺失 `Makefile.win` 或出现其他 C 编译器问题时，务必在 `build_studio.bat` 之前先运行该脚本。

在这些脚本执行期间，遵循 `AGENTS.md` 中的信号优先原则：只有在最终状态变化后才发射信号，保持 origin 元数据一致，并将 Burrito 产出视为可审计的结果（会写入 `history.jsonl`）。

defmodule Mix.Tasks.Cortex.Dev do
  @moduledoc """
  启动 Cortex Desktop 开发模式（热重载）
  
  ## 用法
  
      mix cortex.dev
  
  等同于：
      mix ex_tauri.dev
  
  ## 选项
  
  所有 ExTauri.Dev 的选项都支持：
  
    * `--release` / `-r` - 使用 release 模式
    * `--target <TARGET>` - 指定目标平台
    * `--config <CONFIG>` - 使用自定义 tauri.conf.json
    * `--port <PORT>` - 指定端口
    * `--no-watch` - 禁用文件监听
    * `--features <FEATURES>` - 启用 Rust features
  
  ## 示例
  
      # 启动开发模式
      mix cortex.dev
      
      # 使用 release 模式（更快）
      mix cortex.dev --release
      
      # 指定端口
      mix cortex.dev --port 5000
  """
  
  use Mix.Task
  
  @impl true
  def run(args) do
    # 调用 ExTauri 的开发模式
    Mix.Task.run("ex_tauri.dev", args)
  end
end

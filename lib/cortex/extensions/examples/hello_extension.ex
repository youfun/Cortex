defmodule Cortex.Extensions.Examples.HelloExtension do
  @moduledoc """
  Hello World Extension - 最简单的 Extension 示例

  演示：
  - 基本的 Extension 结构
  - 注册一个简单的工具
  - 注册一个简单的 Hook

  使用方法：
  ```elixir
  # 在 IEx 中加载
  Cortex.Extensions.Manager.load(Cortex.Extensions.Examples.HelloExtension)

  # 查看已加载的 Extension
  Cortex.Extensions.Manager.list_loaded()

  # 卸载
  Cortex.Extensions.Manager.unload(Cortex.Extensions.Examples.HelloExtension)
  ```
  """

  @behaviour Cortex.Extensions.Extension

  require Logger

  @impl true
  def init(_config) do
    Logger.info("[HelloExtension] Initializing...")
    {:ok, %{initialized_at: DateTime.utc_now()}}
  end

  @impl true
  def name, do: "HelloExtension"

  @impl true
  def description, do: "A simple hello world extension demonstrating basic Extension capabilities"

  @impl true
  def tools do
    [
      %Cortex.Tools.Tool{
        name: "say_hello",
        description: "Say hello to someone. A simple demonstration tool.",
        parameters: [
          name: [
            type: :string,
            required: false,
            doc: "Name of the person to greet (default: 'World')"
          ],
          language: [
            type: :string,
            required: false,
            doc: "Language for greeting: 'en', 'zh', 'es' (default: 'en')"
          ]
        ],
        module: __MODULE__.Tools.SayHello
      }
    ]
  end

  @impl true
  def hooks do
    [__MODULE__.Hooks.LoggingHook]
  end

  # ===== 工具实现 =====

  defmodule Tools.SayHello do
    @moduledoc """
    简单的问候工具实现
    """

    def execute(args) do
      name = Map.get(args, "name", "World")
      language = Map.get(args, "language", "en")

      greeting =
        case language do
          "zh" -> "你好"
          "es" -> "Hola"
          "fr" -> "Bonjour"
          "ja" -> "こんにちは"
          _ -> "Hello"
        end

      message = "#{greeting}, #{name}! 👋"

      {:ok, message}
    end
  end

  # ===== Hook 实现 =====

  defmodule Hooks.LoggingHook do
    @moduledoc """
    简单的日志 Hook，记录 Agent 生命周期事件
    """

    @behaviour Cortex.Agents.Hook

    require Logger

    @impl true
    def on_agent_end(_ctx, _result) do
      Logger.info("[HelloExtension] Agent turn completed")
      :ok
    end

    @impl true
    def on_context(_ctx, messages) do
      Logger.debug("[HelloExtension] Context built with #{length(messages)} messages")
      {:ok, messages}
    end
  end
end

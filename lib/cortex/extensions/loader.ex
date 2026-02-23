defmodule Cortex.Extensions.Loader do
  @moduledoc """
  Extension 加载器。
  扫描 `lib/cortex/extensions/` 和 `extensions/` 目录加载 Extension 模块。
  """

  require Logger

  alias Cortex.Extensions.HookRegistry
  alias Cortex.Tools.Registry, as: ToolRegistry

  def load_extension(module) when is_atom(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :init, 1) do
      case module.init(%{}) do
        {:ok, _state} ->
          # 注册 hooks
          if function_exported?(module, :hooks, 0) do
            Enum.each(module.hooks(), &HookRegistry.register_global/1)
          end

          # 注册工具
          if function_exported?(module, :tools, 0) do
            Enum.each(module.tools(), fn tool ->
              ToolRegistry.register_dynamic(tool, source: module)
            end)
          end

          Logger.info("[ExtensionLoader] Loaded extension: #{module.name()}")
          :ok

        {:error, reason} ->
          Logger.error("[ExtensionLoader] Failed to load #{inspect(module)}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :not_an_extension}
    end
  end

  @doc """
  卸载 Extension，移除其注册的 hooks 和工具
  """
  def unload_extension(module) when is_atom(module) do
    # 卸载 hooks
    if function_exported?(module, :hooks, 0) do
      Enum.each(module.hooks(), &HookRegistry.unregister/1)
    end

    # 卸载工具
    if function_exported?(module, :tools, 0) do
      Enum.each(module.tools(), fn tool ->
        ToolRegistry.unregister_dynamic(tool.name)
      end)
    end

    Logger.info("[ExtensionLoader] Unloaded extension: #{module.name()}")
    :ok
  end
end

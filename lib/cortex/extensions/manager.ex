defmodule Cortex.Extensions.Manager do
  @moduledoc """
  Extension 生命周期管理 GenServer。
  维护已加载 Extension 列表，支持加载/卸载/重载。
  """
  use GenServer
  require Logger

  alias Cortex.Extensions.Loader

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "加载 Extension"
  def load(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:load, module})
  end

  @doc "卸载 Extension"
  def unload(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:unload, module})
  end

  @doc "重载 Extension（先卸载再加载）"
  def reload(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:reload, module})
  end

  @doc "列出所有已加载的 Extension"
  def list_loaded do
    GenServer.call(__MODULE__, :list_loaded)
  end

  # GenServer 实现

  @impl true
  def init(_opts) do
    Logger.info("[ExtensionManager] Starting...")
    {:ok, %{loaded: %{}}}
  end

  @impl true
  def handle_call({:load, module}, _from, state) do
    case Loader.load_extension(module) do
      :ok ->
        new_loaded = Map.put(state.loaded, module, %{loaded_at: DateTime.utc_now()})
        {:reply, :ok, %{state | loaded: new_loaded}}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:unload, module}, _from, state) do
    if Map.has_key?(state.loaded, module) do
      Loader.unload_extension(module)
      new_loaded = Map.delete(state.loaded, module)
      {:reply, :ok, %{state | loaded: new_loaded}}
    else
      {:reply, {:error, :not_loaded}, state}
    end
  end

  @impl true
  def handle_call({:reload, module}, _from, state) do
    if Map.has_key?(state.loaded, module) do
      Loader.unload_extension(module)

      case Loader.load_extension(module) do
        :ok ->
          new_loaded = Map.put(state.loaded, module, %{loaded_at: DateTime.utc_now()})
          {:reply, :ok, %{state | loaded: new_loaded}}

        {:error, _reason} = error ->
          # 重载失败，从已加载列表中移除
          new_loaded = Map.delete(state.loaded, module)
          {:reply, error, %{state | loaded: new_loaded}}
      end
    else
      {:reply, {:error, :not_loaded}, state}
    end
  end

  @impl true
  def handle_call(:list_loaded, _from, state) do
    {:reply, Map.keys(state.loaded), state}
  end
end

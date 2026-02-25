defmodule Cortex.Search.ConfigWatcher do
  @moduledoc """
  监听 config.search.updated 信号，清除搜索配置缓存。
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Cortex.SignalHub.subscribe("config.search.updated")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "config.search.updated"}}, state) do
    :persistent_term.erase({Cortex.Config.SearchSettings, :cached})
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end

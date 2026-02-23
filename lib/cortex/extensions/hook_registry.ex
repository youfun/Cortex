defmodule Cortex.Extensions.HookRegistry do
  @moduledoc """
  运行时 Hook 注册表。
  管理全局 Hook 列表和 Session 级 Hook 列表。
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "注册全局 Hook（对所有 Session 生效）"
  def register_global(hook_module) do
    GenServer.call(__MODULE__, {:register_global, hook_module})
  end

  @doc "注册 Session 级 Hook"
  def register_session(session_id, hook_module) do
    GenServer.call(__MODULE__, {:register_session, session_id, hook_module})
  end

  @doc "获取指定 Session 的完整 Hook 列表（全局 + Session 级）"
  def get_hooks(session_id) do
    GenServer.call(__MODULE__, {:get_hooks, session_id})
  end

  @doc "卸载 Hook"
  def unregister(hook_module) do
    GenServer.call(__MODULE__, {:unregister, hook_module})
  end

  # GenServer 实现
  @impl true
  def init(_opts) do
    {:ok,
     %{
       global_hooks: [Cortex.Hooks.SandboxHook, Cortex.Hooks.PermissionHook],
       session_hooks: %{}
     }}
  end

  @impl true
  def handle_call({:register_global, hook_module}, _from, state) do
    new_hooks = Enum.uniq(append_one(state.global_hooks, hook_module))
    {:reply, :ok, %{state | global_hooks: new_hooks}}
  end

  @impl true
  def handle_call({:register_session, session_id, hook_module}, _from, state) do
    session_list = Map.get(state.session_hooks, session_id, [])
    new_list = Enum.uniq(append_one(session_list, hook_module))
    new_session_hooks = Map.put(state.session_hooks, session_id, new_list)
    {:reply, :ok, %{state | session_hooks: new_session_hooks}}
  end

  @impl true
  def handle_call({:get_hooks, session_id}, _from, state) do
    session_list = Map.get(state.session_hooks, session_id, [])
    {:reply, state.global_hooks ++ session_list, state}
  end

  @impl true
  def handle_call({:unregister, hook_module}, _from, state) do
    new_global = Enum.reject(state.global_hooks, &(&1 == hook_module))

    new_session =
      Map.new(state.session_hooks, fn {k, v} ->
        {k, Enum.reject(v, &(&1 == hook_module))}
      end)

    {:reply, :ok, %{state | global_hooks: new_global, session_hooks: new_session}}
  end

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end
end

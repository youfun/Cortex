defmodule Cortex.History.Tape.Store do
  @moduledoc """
  Tape 存储服务。
  
  管理每个 session 的 Tape Entry 列表，提供查询和追加接口。
  """

  use GenServer
  require Logger

  alias Cortex.History.Tape.Entry

  @type session_id :: String.t()

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  追加一个 Entry 到指定 session 的 Tape。
  """
  @spec append(session_id(), Entry.t()) :: :ok
  def append(session_id, %Entry{} = entry) do
    GenServer.call(__MODULE__, {:append, session_id, entry})
  end

  @doc """
  列出指定 session 的 Entry 列表。
  
  ## 选项
  - limit: 限制返回数量（默认 100）
  """
  @spec list_entries(session_id(), keyword()) :: [Entry.t()]
  def list_entries(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:list_entries, session_id, opts})
  end

  @doc """
  从最后一个锚点开始获取 Entry 列表。
  """
  @spec from_last_anchor(session_id(), keyword()) :: [Entry.t()]
  def from_last_anchor(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:from_last_anchor, session_id, opts})
  end

  @doc """
  统计指定 session 的 Entry 数量。
  """
  @spec count_entries(session_id()) :: non_neg_integer()
  def count_entries(session_id) do
    GenServer.call(__MODULE__, {:count_entries, session_id})
  end

  @doc """
  清空指定 session 的所有 Entry。
  """
  @spec clear(session_id()) :: :ok
  def clear(session_id) do
    GenServer.call(__MODULE__, {:clear, session_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("[Tape.Store] Starting Tape Store")
    # state: %{session_id => [Entry.t()]}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:append, session_id, entry}, _from, state) do
    entries = Map.get(state, session_id, [])
    new_entries = [entry | entries]
    new_state = Map.put(state, session_id, new_entries)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:list_entries, session_id, opts}, _from, state) do
    entries = Map.get(state, session_id, [])
    limit = Keyword.get(opts, :limit, 100)
    result = entries |> Enum.reverse() |> Enum.take(limit)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:from_last_anchor, session_id, _opts}, _from, state) do
    entries = Map.get(state, session_id, [])
    
    # 找到最后一个 anchor
    anchor_index = Enum.find_index(entries, fn entry -> entry.kind == :anchor end)
    
    result =
      case anchor_index do
        nil -> entries |> Enum.reverse()
        idx -> entries |> Enum.take(idx) |> Enum.reverse()
      end
    
    {:reply, result, state}
  end

  @impl true
  def handle_call({:count_entries, session_id}, _from, state) do
    count = state |> Map.get(session_id, []) |> length()
    {:reply, count, state}
  end

  @impl true
  def handle_call({:clear, session_id}, _from, state) do
    new_state = Map.delete(state, session_id)
    {:reply, :ok, new_state}
  end
end

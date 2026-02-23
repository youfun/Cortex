defmodule Cortex.Memory.WorkingMemory do
  @moduledoc """
  工作记忆 —— 当前意识焦点。

  基于 Arbor Memory 的 WorkingMemory 模块，维护当前活跃的思维：
  - **Current Focus**: 当前关注点
  - **Curiosities**: 好奇心队列（想要探索的问题）
  - **Concerns**: 顾虑（需要解决的问题）
  - **Goals**: 当前目标

  工作记忆是有限的（类似人类工作记忆的 7±2 限制），
  新的项目进入时会自动挤出旧的项目。
  """

  use GenServer
  require Logger

  alias Cortex.Memory.SignalTypes
  alias Cortex.SignalHub

  @default_capacity 7
  @max_item_length 200

  defstruct [
    :capacity,
    focus: nil,
    curiosities: [],
    concerns: [],
    goals: [],
    last_updated: nil
  ]

  # Item structures
  defmodule Item do
    @moduledoc "工作记忆项目"
    defstruct [
      :id,
      :content,
      :created_at,
      :priority,
      metadata: %{}
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    capacity = Keyword.get(opts, :capacity, @default_capacity)
    GenServer.start_link(__MODULE__, capacity, name: name)
  end

  @doc """
  设置当前焦点。
  """
  def set_focus(content, opts \\ []) do
    GenServer.call(__MODULE__, {:set_focus, content, opts})
  end

  @doc """
  获取当前焦点。
  """
  def get_focus do
    GenServer.call(__MODULE__, :get_focus)
  end

  @doc """
  添加好奇心。
  """
  def add_curiosity(content, opts \\ []) do
    GenServer.call(__MODULE__, {:add_curiosity, content, opts})
  end

  @doc """
  添加顾虑。
  """
  def add_concern(content, opts \\ []) do
    GenServer.call(__MODULE__, {:add_concern, content, opts})
  end

  @doc """
  添加目标。
  """
  def add_goal(content, opts \\ []) do
    GenServer.call(__MODULE__, {:add_goal, content, opts})
  end

  @doc """
  列出所有工作记忆内容。
  """
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  清空所有工作记忆。
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  删除指定项目。
  """
  def remove(item_id) do
    GenServer.call(__MODULE__, {:remove, item_id})
  end

  @doc """
  获取统计信息。
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(capacity) do
    Logger.info("[Memory.WorkingMemory] Initialized with capacity #{capacity}")
    {:ok, %__MODULE__{capacity: capacity, last_updated: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:set_focus, content, opts}, _from, state) do
    item = create_item(content, :high, opts)

    new_state = %{
      state
      | focus: item,
        last_updated: DateTime.utc_now()
    }

    emit_signal(SignalTypes.memory_working_saved(), %{
      type: :focus,
      item_id: item.id,
      content_preview: String.slice(content, 0, 100)
    })

    {:reply, {:ok, item}, new_state}
  end

  @impl true
  def handle_call(:get_focus, _from, state) do
    {:reply, state.focus, state}
  end

  @impl true
  def handle_call({:add_curiosity, content, opts}, _from, state) do
    item = create_item(content, :medium, opts)
    new_curiosities = add_with_capacity(state.curiosities, item, state.capacity)

    new_state = %{
      state
      | curiosities: new_curiosities,
        last_updated: DateTime.utc_now()
    }

    emit_signal(SignalTypes.memory_working_saved(), %{
      type: :curiosity,
      item_id: item.id
    })

    {:reply, {:ok, item}, new_state}
  end

  @impl true
  def handle_call({:add_concern, content, opts}, _from, state) do
    item = create_item(content, :high, opts)
    new_concerns = add_with_capacity(state.concerns, item, state.capacity)

    new_state = %{
      state
      | concerns: new_concerns,
        last_updated: DateTime.utc_now()
    }

    emit_signal(SignalTypes.memory_working_saved(), %{
      type: :concern,
      item_id: item.id
    })

    {:reply, {:ok, item}, new_state}
  end

  @impl true
  def handle_call({:add_goal, content, opts}, _from, state) do
    item = create_item(content, :high, opts)
    new_goals = add_with_capacity(state.goals, item, div(state.capacity, 2))

    new_state = %{
      state
      | goals: new_goals,
        last_updated: DateTime.utc_now()
    }

    emit_signal(SignalTypes.memory_working_saved(), %{
      type: :goal,
      item_id: item.id
    })

    {:reply, {:ok, item}, new_state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    all = %{
      focus: state.focus,
      curiosities: state.curiosities,
      concerns: state.concerns,
      goals: state.goals
    }

    {:reply, all, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    new_state = %{
      state
      | focus: nil,
        curiosities: [],
        concerns: [],
        goals: [],
        last_updated: DateTime.utc_now()
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:remove, item_id}, _from, state) do
    new_state = %{
      state
      | focus: if(state.focus && state.focus.id == item_id, do: nil, else: state.focus),
        curiosities: Enum.reject(state.curiosities, &(&1.id == item_id)),
        concerns: Enum.reject(state.concerns, &(&1.id == item_id)),
        goals: Enum.reject(state.goals, &(&1.id == item_id)),
        last_updated: DateTime.utc_now()
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total_items =
      length(state.curiosities) +
        length(state.concerns) +
        length(state.goals) +
        if(state.focus, do: 1, else: 0)

    stats = %{
      total_items: total_items,
      focus_set: not is_nil(state.focus),
      curiosities_count: length(state.curiosities),
      concerns_count: length(state.concerns),
      goals_count: length(state.goals),
      capacity: state.capacity,
      utilization: Float.round(total_items / state.capacity, 2)
    }

    {:reply, stats, state}
  end

  # Private functions

  defp create_item(content, priority, opts) do
    id = Keyword.get(opts, :id, generate_id())
    metadata = Keyword.get(opts, :metadata, %{})

    # Truncate if too long
    truncated =
      if String.length(content) > @max_item_length do
        String.slice(content, 0, @max_item_length) <> "..."
      else
        content
      end

    %Item{
      id: id,
      content: truncated,
      created_at: DateTime.utc_now(),
      priority: priority,
      metadata: metadata
    }
  end

  defp add_with_capacity(list, item, capacity) do
    # Add to front, trim if exceeds capacity
    new_list = [item | list]

    if length(new_list) > capacity do
      Enum.take(new_list, capacity)
    else
      new_list
    end
  end

  defp generate_id do
    "wm_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp emit_signal(type, data) do
    signal_data =
      Map.merge(data, %{
        provider: "memory",
        event: "working",
        action: "save",
        actor: "working_memory",
        origin: %{channel: "memory", client: "working_memory", platform: "server"}
      })

    SignalHub.emit(type, signal_data, source: "/memory/working")
  end
end

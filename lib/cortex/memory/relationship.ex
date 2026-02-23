defmodule Cortex.Memory.Relationship do
  @moduledoc """
  人际关系建模 —— 追踪与用户的关系历史。

  基于 Arbor Memory 的 Relationship 模块，维护：
  - **Interaction History**: 互动历史（频次、时间）
  - **Trust Level**: 信任等级（影响自动决策）
  - **Communication Style**: 沟通风格偏好
  - **Shared Context**: 共享上下文和共同经历

  ## 信任等级

  - `:new` - 新关系（默认）
  - `:acquainted` - 已熟悉
  - `:trusted` - 已信任
  - `:close` - 密切关系
  """

  use GenServer
  require Logger

  alias Cortex.Core.Security
  alias Cortex.Workspaces
  alias Cortex.Memory.Store

  @default_relationships_path "relationships.json"

  @trust_levels [:new, :acquainted, :trusted, :close]

  defstruct [
    :path,
    :current_user_id,
    trust_level: :new,
    interaction_count: 0,
    first_interaction: nil,
    last_interaction: nil,
    communication_preferences: %{},
    shared_context: %{},
    interaction_history: []
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    path = Keyword.get(opts, :path, @default_relationships_path)
    GenServer.start_link(__MODULE__, path, name: name)
  end

  @doc """
  记录一次互动。
  """
  def record_interaction(type, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:record_interaction, type, metadata})
  end

  @doc """
  获取当前信任等级。
  """
  def trust_level do
    GenServer.call(__MODULE__, :trust_level)
  end

  @doc """
  更新信任等级。
  """
  def update_trust_level(level) when level in @trust_levels do
    GenServer.call(__MODULE__, {:update_trust_level, level})
  end

  @doc """
  设置沟通偏好。
  """
  def set_communication_preference(key, value) do
    GenServer.call(__MODULE__, {:set_preference, key, value})
  end

  @doc """
  获取关系摘要。
  """
  def summary do
    GenServer.call(__MODULE__, :summary)
  end

  @doc """
  检查是否允许自动操作（基于信任等级）。
  """
  def allow_auto_action?(action_risk_level) do
    GenServer.call(__MODULE__, {:allow_auto_action?, action_risk_level})
  end

  # Server Callbacks

  @impl true
  def init(path) do
    project_root = Workspaces.workspace_root()

    state =
      case Security.validate_path(path, project_root) do
        {:ok, validated_path} ->
          File.mkdir_p!(Path.dirname(validated_path))
          load_from_file(validated_path, project_root)

        {:error, reason} ->
          Logger.error("[Memory.Relationship] Path validation failed: #{inspect(reason)}")
          %__MODULE__{path: path}
      end

    Logger.info("[Memory.Relationship] Initialized with trust level: #{state.trust_level}")

    {:ok, state}
  end

  @impl true
  def handle_call({:record_interaction, type, metadata}, _from, state) do
    now = DateTime.utc_now()

    interaction = %{
      type: type,
      timestamp: now,
      metadata: metadata
    }

    # Add to history (keep last 100)
    new_history = [interaction | state.interaction_history] |> Enum.take(100)

    # Update trust level based on interaction count
    new_trust = calculate_trust_level(state.interaction_count + 1, state.trust_level)

    new_state = %{
      state
      | interaction_count: state.interaction_count + 1,
        last_interaction: now,
        first_interaction: state.first_interaction || now,
        interaction_history: new_history,
        trust_level: new_trust
    }

    save_to_file(new_state)

    # Also store as observation
    Store.append_observation("用户互动: #{type}", priority: :low)

    {:reply, {:ok, new_trust}, new_state}
  end

  @impl true
  def handle_call(:trust_level, _from, state) do
    {:reply, state.trust_level, state}
  end

  @impl true
  def handle_call({:update_trust_level, level}, _from, state) do
    new_state = %{state | trust_level: level}
    save_to_file(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_preference, key, value}, _from, state) do
    new_prefs = Map.put(state.communication_preferences, key, value)
    new_state = %{state | communication_preferences: new_prefs}
    save_to_file(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    days_since_first =
      if state.first_interaction do
        DateTime.diff(DateTime.utc_now(), state.first_interaction, :day)
      else
        0
      end

    summary = %{
      trust_level: state.trust_level,
      interaction_count: state.interaction_count,
      days_active: days_since_first,
      first_interaction: state.first_interaction,
      last_interaction: state.last_interaction,
      communication_preferences: state.communication_preferences
    }

    {:reply, summary, state}
  end

  @impl true
  def handle_call({:allow_auto_action?, risk_level}, _from, state) do
    allowed =
      case {state.trust_level, risk_level} do
        {:close, _} -> true
        {:trusted, :low} -> true
        {:trusted, :medium} -> true
        {:acquainted, :low} -> true
        _ -> false
      end

    {:reply, allowed, state}
  end

  # Private functions

  defp calculate_trust_level(count, current) do
    cond do
      count > 100 -> :close
      count > 50 -> if current == :close, do: :close, else: :trusted
      count > 10 -> if current in [:trusted, :close], do: current, else: :acquainted
      true -> current
    end
  end

  defp load_from_file(path, project_root) do
    case Security.atomic_read(path, project_root) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, map} -> from_map(map, path)
          {:error, _} -> %__MODULE__{path: path}
        end

      {:error, :enoent} ->
        %__MODULE__{path: path}

      {:error, _} ->
        %__MODULE__{path: path}
    end
  end

  defp save_to_file(state) do
    json =
      state
      |> to_map()
      |> Jason.encode!(pretty: true)

    case Security.atomic_write(state.path, json, Workspaces.workspace_root()) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[Memory.Relationship] Failed to write relationships: #{inspect(reason)}")
    end
  end

  defp to_map(state) do
    %{
      trust_level: state.trust_level,
      interaction_count: state.interaction_count,
      first_interaction:
        if(state.first_interaction, do: DateTime.to_iso8601(state.first_interaction)),
      last_interaction:
        if(state.last_interaction, do: DateTime.to_iso8601(state.last_interaction)),
      communication_preferences: state.communication_preferences,
      shared_context: state.shared_context,
      interaction_history: state.interaction_history
    }
  end

  defp from_map(map, path) do
    %__MODULE__{
      path: path,
      trust_level: String.to_existing_atom(map["trust_level"] || "new"),
      interaction_count: map["interaction_count"] || 0,
      first_interaction: parse_datetime(map["first_interaction"]),
      last_interaction: parse_datetime(map["last_interaction"]),
      communication_preferences: map["communication_preferences"] || %{},
      shared_context: map["shared_context"] || %{},
      interaction_history: map["interaction_history"] || []
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      {:error, _} -> nil
    end
  end
end

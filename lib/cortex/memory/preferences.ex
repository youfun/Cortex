defmodule Cortex.Memory.Preferences do
  @moduledoc """
  认知偏好 —— 可调节的记忆系统参数。

  基于 Arbor Memory 的 Preferences 模块，管理：
  - **Decay Rate**: 记忆衰减率（遗忘速度）
  - **Retrieval Threshold**: 检索阈值（什么算"记得"）
  - **Attention Span**: 注意力跨度（工作记忆容量）
  - **Curiosity Level**: 好奇心水平（探索倾向）

  这些偏好可以从交互中学习并自适应调整。
  """

  use GenServer
  require Logger

  alias Cortex.Core.Security
  alias Cortex.Workspaces

  @default_prefs_path "preferences.json"

  # Default preference values
  @defaults %{
    decay_rate: 0.05,
    retrieval_threshold: 0.3,
    attention_span: 7,
    curiosity_level: 0.5,
    consolidation_interval_hours: 6,
    auto_accept_proposals: false,
    max_proposals_per_session: 10,
    activation_threshold: 0.5,
    preference_confidence_threshold: 0.7
  }

  defstruct [
    :path,
    values: %{},
    last_updated: nil
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    path = Keyword.get(opts, :path, @default_prefs_path)
    GenServer.start_link(__MODULE__, path, name: name)
  end

  @doc """
  获取偏好值。
  """
  def get(key) when is_atom(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc """
  获取所有偏好。
  """
  def get_all do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc """
  设置偏好值。
  """
  def set(key, value) when is_atom(key) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  @doc """
  批量设置偏好。
  """
  def set_many(prefs) when is_map(prefs) do
    GenServer.call(__MODULE__, {:set_many, prefs})
  end

  @doc """
  重置为默认值。
  """
  def reset_to_defaults do
    GenServer.call(__MODULE__, :reset_to_defaults)
  end

  @doc """
  根据交互自适应调整偏好。

  例如：
  - 如果用户频繁接受某种类型的提议，降低阈值
  - 如果用户经常拒绝，提高阈值
  """
  def adapt_from_interaction(interaction_type, outcome) do
    GenServer.call(__MODULE__, {:adapt, interaction_type, outcome})
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
          Logger.error("[Memory.Preferences] Path validation failed: #{inspect(reason)}")
          %__MODULE__{path: path}
      end

    Logger.info("[Memory.Preferences] Initialized")

    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    value = Map.get(state.values, key, Map.get(@defaults, key))
    {:reply, value, state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    # Merge with defaults
    all = Map.merge(@defaults, state.values)
    {:reply, all, state}
  end

  @impl true
  def handle_call({:set, key, value}, _from, state) do
    new_values = Map.put(state.values, key, value)
    new_state = %{state | values: new_values, last_updated: DateTime.utc_now()}

    save_to_file(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_many, prefs}, _from, state) do
    new_values = Map.merge(state.values, prefs)
    new_state = %{state | values: new_values, last_updated: DateTime.utc_now()}

    save_to_file(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:reset_to_defaults, _from, state) do
    new_state = %{state | values: %{}, last_updated: DateTime.utc_now()}
    save_to_file(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:adapt, interaction_type, outcome}, _from, state) do
    new_values = adapt_preferences(state.values, interaction_type, outcome)
    new_state = %{state | values: new_values, last_updated: DateTime.utc_now()}

    save_to_file(new_state)
    {:reply, {:ok, new_values}, new_state}
  end

  # Private functions

  defp adapt_preferences(values, :proposal_accepted, _outcome) do
    # User accepted a proposal, slightly lower the threshold
    current = Map.get(values, :retrieval_threshold, @defaults.retrieval_threshold)
    new_threshold = max(current - 0.02, 0.1)
    Map.put(values, :retrieval_threshold, new_threshold)
  end

  defp adapt_preferences(values, :proposal_rejected, _outcome) do
    # User rejected a proposal, raise the threshold
    current = Map.get(values, :retrieval_threshold, @defaults.retrieval_threshold)
    new_threshold = min(current + 0.02, 0.9)
    Map.put(values, :retrieval_threshold, new_threshold)
  end

  defp adapt_preferences(values, :high_engagement, _outcome) do
    # User is engaged, increase curiosity
    current = Map.get(values, :curiosity_level, @defaults.curiosity_level)
    new_level = min(current + 0.05, 1.0)
    Map.put(values, :curiosity_level, new_level)
  end

  defp adapt_preferences(values, :low_engagement, _outcome) do
    # User is less engaged, decrease curiosity
    current = Map.get(values, :curiosity_level, @defaults.curiosity_level)
    new_level = max(current - 0.05, 0.1)
    Map.put(values, :curiosity_level, new_level)
  end

  defp adapt_preferences(values, _, _), do: values

  defp load_from_file(path, project_root) do
    case Security.atomic_read(path, project_root) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, map} ->
            atomized =
              map
              |> Map.get("values", %{})
              |> normalize_keys()

            %__MODULE__{
              path: path,
              values: atomized,
              last_updated: parse_datetime(map["last_updated"])
            }

          {:error, _} ->
            %__MODULE__{path: path}
        end

      {:error, :enoent} ->
        %__MODULE__{path: path}

      {:error, _} ->
        %__MODULE__{path: path}
    end
  end

  defp save_to_file(state) do
    json =
      %{
        values: state.values,
        last_updated: DateTime.to_iso8601(state.last_updated || DateTime.utc_now())
      }
      |> Jason.encode!(pretty: true)

    case Security.atomic_write(state.path, json, Workspaces.workspace_root()) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[Memory.Preferences] Failed to write preferences: #{inspect(reason)}")
    end
  end

  defp normalize_keys(values) when is_map(values) do
    allowed_keys = Map.keys(@defaults)

    Enum.reduce(values, %{}, fn {key, value}, acc ->
      key_atom =
        cond do
          is_atom(key) and key in allowed_keys ->
            key

          is_binary(key) ->
            Enum.find(allowed_keys, fn allowed -> Atom.to_string(allowed) == key end)

          true ->
            nil
        end

      if key_atom do
        Map.put(acc, key_atom, value)
      else
        acc
      end
    end)
  end

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end
end

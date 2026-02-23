defmodule Cortex.Memory.SelfKnowledge do
  @moduledoc """
  自我认知 —— 关于自身能力和特质的元知识。

  基于 Arbor Memory 的 SelfKnowledge 模块，维护：
  - **Capabilities**: 能力（我擅长什么）
  - **Traits**: 特质（我的行为特征）
  - **Values**: 价值观（我重视什么）
  - **Limitations**: 限制（我不擅长什么）

  自我认知从提议中提取，经过验证后提升到永久存储。
  """

  use GenServer
  require Logger

  alias Cortex.Core.Security
  alias Cortex.Workspaces

  @default_knowledge_path "self_knowledge.json"

  defstruct [
    :path,
    capabilities: %{},
    traits: %{},
    values: %{},
    limitations: %{},
    last_updated: nil
  ]

  # Knowledge item structure
  defmodule Item do
    @moduledoc "自我认知项目"
    defstruct [
      :id,
      :content,
      :confidence,
      :source_proposal_id,
      :created_at,
      :last_validated,
      metadata: %{}
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    path = Keyword.get(opts, :path, @default_knowledge_path)
    GenServer.start_link(__MODULE__, path, name: name)
  end

  @doc """
  添加或更新能力认知。
  """
  def add_capability(content, confidence \\ 0.7, opts \\ []) do
    GenServer.call(__MODULE__, {:add, :capabilities, content, confidence, opts})
  end

  @doc """
  添加或更新特质认知。
  """
  def add_trait(content, confidence \\ 0.7, opts \\ []) do
    GenServer.call(__MODULE__, {:add, :traits, content, confidence, opts})
  end

  @doc """
  添加或更新价值观认知。
  """
  def add_value(content, confidence \\ 0.7, opts \\ []) do
    GenServer.call(__MODULE__, {:add, :values, content, confidence, opts})
  end

  @doc """
  添加或更新限制认知。
  """
  def add_limitation(content, confidence \\ 0.7, opts \\ []) do
    GenServer.call(__MODULE__, {:add, :limitations, content, confidence, opts})
  end

  @doc """
  获取所有自我认知。
  """
  def get_all do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc """
  获取指定类型的认知。
  """
  def get_by_type(type) when type in [:capabilities, :traits, :values, :limitations] do
    GenServer.call(__MODULE__, {:get_by_type, type})
  end

  @doc """
  生成自我描述文本（用于系统提示词）。
  """
  def generate_description do
    GenServer.call(__MODULE__, :generate_description)
  end

  @doc """
  从提议提升为自我认知。
  """
  def promote_from_proposal(proposal_id, type) do
    GenServer.call(__MODULE__, {:promote, proposal_id, type})
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
          Logger.error("[Memory.SelfKnowledge] Path validation failed: #{inspect(reason)}")
          %__MODULE__{path: path}
      end

    Logger.info("[Memory.SelfKnowledge] Loaded #{count_items(state)} items")

    {:ok, state}
  end

  @impl true
  def handle_call({:add, type, content, confidence, opts}, _from, state) do
    item = create_item(content, confidence, opts)

    current_map = Map.get(state, type)
    new_map = Map.put(current_map, item.id, item)

    new_state =
      Map.merge(state, %{
        type => new_map,
        last_updated: DateTime.utc_now()
      })

    save_to_file(new_state)

    {:reply, {:ok, item}, new_state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    result = %{
      capabilities: Map.values(state.capabilities),
      traits: Map.values(state.traits),
      values: Map.values(state.values),
      limitations: Map.values(state.limitations)
    }

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_by_type, type}, _from, state) do
    items =
      state
      |> Map.get(type, %{})
      |> Map.values()
      |> sort_by_confidence()

    {:reply, items, state}
  end

  @impl true
  def handle_call(:generate_description, _from, state) do
    description = build_description(state)
    {:reply, description, state}
  end

  @impl true
  def handle_call({:promote, proposal_id, type}, _from, state) do
    alias Cortex.Memory.Proposal

    case Proposal.get(proposal_id) do
      nil ->
        {:reply, {:error, :proposal_not_found}, state}

      proposal ->
        # 接受提议
        {:ok, _} = Proposal.accept(proposal_id)

        # 提升为自我认知
        {:ok, item} =
          handle_call(
            {:add, type, proposal.content, proposal.confidence, source_proposal_id: proposal_id},
            nil,
            state
          )

        {:reply, {:ok, item}, state}
    end
  end

  # Private functions

  defp create_item(content, confidence, opts) do
    %Item{
      id: generate_id(),
      content: content,
      confidence: confidence,
      source_proposal_id: opts[:source_proposal_id],
      created_at: DateTime.utc_now(),
      last_validated: DateTime.utc_now()
    }
  end

  defp sort_by_confidence(items) do
    Enum.sort_by(items, & &1.confidence, :desc)
  end

  defp count_items(state) do
    length(Map.values(state.capabilities)) +
      length(Map.values(state.traits)) +
      length(Map.values(state.values)) +
      length(Map.values(state.limitations))
  end

  defp build_description(state) do
    sections = [
      build_section("Capabilities", state.capabilities),
      build_section("Traits", state.traits),
      build_section("Values", state.values),
      build_section("Limitations", state.limitations)
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp build_section(_title, items) when map_size(items) == 0, do: nil

  defp build_section(title, items) do
    content =
      items
      |> Map.values()
      |> sort_by_confidence()
      |> Enum.map_join("\n", fn item -> "- #{item.content}" end)

    "### #{title}\n#{content}"
  end

  defp load_from_file(path, project_root) do
    case Security.atomic_read(path, project_root) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, map} ->
            from_map(map, path)

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
      state
      |> to_map()
      |> Jason.encode!(pretty: true)

    case Security.atomic_write(state.path, json, Workspaces.workspace_root()) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[Memory.SelfKnowledge] Failed to write self knowledge: #{inspect(reason)}")
    end
  end

  defp to_map(state) do
    %{
      capabilities: map_to_list(state.capabilities),
      traits: map_to_list(state.traits),
      values: map_to_list(state.values),
      limitations: map_to_list(state.limitations),
      last_updated: DateTime.to_iso8601(state.last_updated || DateTime.utc_now())
    }
  end

  defp from_map(map, path) do
    %__MODULE__{
      path: path,
      capabilities: list_to_map(map["capabilities"]),
      traits: list_to_map(map["traits"]),
      values: list_to_map(map["values"]),
      limitations: list_to_map(map["limitations"]),
      last_updated: parse_datetime(map["last_updated"])
    }
  end

  defp map_to_list(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.map(fn item ->
      %{
        "id" => item.id,
        "content" => item.content,
        "confidence" => item.confidence,
        "source_proposal_id" => item.source_proposal_id,
        "created_at" => DateTime.to_iso8601(item.created_at),
        "last_validated" => DateTime.to_iso8601(item.last_validated),
        "metadata" => item.metadata
      }
    end)
  end

  defp list_to_map(nil), do: %{}
  defp list_to_map(list) when is_list(list), do: list_to_map(%{}, list)
  defp list_to_map(list) when is_map(list), do: list_to_map(Map.values(list))

  defp list_to_map(map, []), do: map

  defp list_to_map(map, [item | rest]) do
    new_map =
      Map.put(map, item["id"], %Item{
        id: item["id"],
        content: item["content"],
        confidence: item["confidence"] || 0.5,
        source_proposal_id: item["source_proposal_id"],
        created_at: parse_datetime(item["created_at"]),
        last_validated: parse_datetime(item["last_validated"]),
        metadata: item["metadata"] || %{}
      })

    list_to_map(new_map, rest)
  end

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp generate_id do
    "sk_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end
end

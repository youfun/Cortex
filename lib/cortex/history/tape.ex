defmodule Cortex.History.Tape do
  @moduledoc """
  Tape 数据结构定义。
  Tape 代表一个线性的、因果关联的事件序列，类似于磁带。
  """

  defstruct [
    # Tape ID (通常对应 session_id)
    :id,
    # Entry 列表 (倒序存储，头部是最新)
    entries: [],
    # 元数据
    metadata: %{}
  ]

  defmodule Entry do
    @moduledoc """
    Tape 中的单个条目（V3 新结构）

    ## 字段说明
    - seq_id: 单调递增的序列号（全局唯一）
    - kind: 语义分类（:message | :tool_call | :tool_result | :system | :anchor）
    - payload: 核心数据（结构因 kind 而异）
    - meta: 元数据（session_id, timestamp, elapsed_ms 等）
    """
    @derive Jason.Encoder
    defstruct [
      # 单调递增序列号
      :seq_id,
      # 语义分类
      :kind,
      # 核心数据
      :payload,
      # 元数据
      meta: %{}
    ]

    @type kind :: :message | :tool_call | :tool_result | :system | :anchor
    @type t :: %__MODULE__{
            seq_id: non_neg_integer(),
            kind: kind(),
            payload: map(),
            meta: map()
          }

    @behaviour Access

    @impl Access
    def fetch(%__MODULE__{} = entry, key) do
      Map.fetch(Map.from_struct(entry), key)
    end

    @impl Access
    def get_and_update(%__MODULE__{} = entry, key, fun) do
      map = Map.from_struct(entry)
      {get_value, updated_map} = Map.get_and_update(map, key, fun)
      {get_value, struct(__MODULE__, updated_map)}
    end

    @impl Access
    def pop(%__MODULE__{} = entry, key) do
      map = Map.from_struct(entry)
      {value, updated_map} = Map.pop(map, key)
      {value, struct(__MODULE__, updated_map)}
    end
  end
end

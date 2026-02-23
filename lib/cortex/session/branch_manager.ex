defmodule Cortex.Session.BranchManager do
  @moduledoc """
  会话分支管理器。

  实现 Pi 的会话树功能：
  - 从当前会话创建分支（子会话）
  - 分支在独立进程中运行
  - 分支完成后生成摘要信号
  - 主会话可以合并分支知识

  ## 使用场景

  1. Agent 需要"旁路探索"：尝试一种方案但不影响主对话
  2. 修复工具错误：在分支中调试和修复，成功后回到主线
  3. 并行任务：同时探索多个方向
  """

  use GenServer
  require Logger

  alias Cortex.SignalHub

  defstruct [
    :session_id,
    :parent_session_id,
    # 分支点（父会话的消息索引）
    :branch_point,
    # :active | :completed | :merged
    :status,
    # 分支完成后的摘要
    :summary,
    # child_id => %{pid, status, summary}
    branches: %{}
  ]

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def via(session_id) do
    {:via, Registry, {Cortex.SessionRegistry, {:branch, session_id}}}
  end

  @doc """
  从当前会话创建一个分支。

  返回新分支的 session_id。
  """
  def create_branch(parent_session_id, opts \\ []) do
    branch_id =
      Keyword.get(opts, :branch_id) ||
        "branch_#{System.unique_integer([:positive])}_#{parent_session_id}"

    purpose = Keyword.get(opts, :purpose, "exploration")

    # [NEW] Record branch point from Tape
    branch_point = Cortex.History.Tape.Store.count_entries(parent_session_id)

    # 发射分支创建信号
    SignalHub.emit(
      "session.branch.created",
      %{
        provider: "system",
        event: "session",
        action: "branch_create",
        actor: "branch_manager",
        origin: %{
          channel: "system",
          client: "branch_manager",
          platform: "server",
          session_id: parent_session_id,
          parent_session_id: parent_session_id,
          branch_session_id: branch_id
        },
        parent_session_id: parent_session_id,
        branch_session_id: branch_id,
        purpose: purpose,
        branch_point: branch_point
      },
      source: "/session/branch"
    )

    # 启动分支的 LLM Agent
    # 注意：这里假设 Cortex.SessionSupervisor 和 Cortex.Agents.LLMAgent 已存在并按此方式工作
    case DynamicSupervisor.start_child(
           Cortex.SessionSupervisor,
           {Cortex.Agents.LLMAgent, session_id: branch_id}
         ) do
      {:ok, _pid} ->
        {:ok, branch_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  完成分支并生成摘要。
  """
  def complete_branch(branch_session_id, summary) do
    SignalHub.emit(
      "session.branch.completed",
      %{
        provider: "system",
        event: "session",
        action: "branch_complete",
        actor: "branch_manager",
        origin: %{channel: "system", client: "branch_manager", platform: "server"},
        branch_session_id: branch_session_id,
        summary: summary
      },
      source: "/session/branch"
    )

    {:ok, summary}
  end

  @doc """
  将分支摘要合并回父会话。
  """
  def merge_branch(parent_session_id, branch_session_id, summary) do
    SignalHub.emit(
      "session.branch.merged",
      %{
        provider: "system",
        event: "session",
        action: "branch_merge",
        actor: "branch_manager",
        origin: %{channel: "system", client: "branch_manager", platform: "server"},
        parent_session_id: parent_session_id,
        branch_session_id: branch_session_id,
        summary: summary
      },
      source: "/session/branch"
    )

    {:ok, :merged}
  end

  # GenServer callbacks
  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       session_id: Keyword.fetch!(opts, :session_id),
       parent_session_id: Keyword.get(opts, :parent_session_id),
       status: :active
     }}
  end
end

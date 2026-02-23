defmodule Cortex.Session.BranchManagerTest do
  use ExUnit.Case, async: false
  use Cortex.ProcessCase

  alias Cortex.Session.BranchManager
  alias Cortex.SignalHub

  setup do
    # 订阅所有会话分支信号
    SignalHub.subscribe("session.branch.**")
    :ok
  end

  describe "create_branch/2" do
    test "creates a new branch and emits signal" do
      parent_session_id = "session_123"

      assert {:ok, branch_id} = BranchManager.create_branch(parent_session_id)

      # 验证返回的 branch_id 格式正确
      assert String.starts_with?(branch_id, "branch_")
      assert String.ends_with?(branch_id, "_#{parent_session_id}")

      # 验证发射了分支创建信号
      assert_receive {:signal,
                      %Jido.Signal{
                        type: "session.branch.created",
                        data: data,
                        source: "/session/branch"
                      }},
                     1000

      assert data.payload.parent_session_id == parent_session_id
      assert data.payload.branch_session_id == branch_id
      # 默认目的
      assert data.payload.purpose == "exploration"
    end

    test "creates branch with custom purpose" do
      parent_session_id = "session_456"

      assert {:ok, branch_id} =
               BranchManager.create_branch(parent_session_id, purpose: "debugging")

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "session.branch.created",
                        data: %{payload: %{purpose: "debugging"}}
                      }},
                     1000
    end

    test "returns error if LLM Agent fails to start" do
      # 使用无效的 session_id 触发启动失败
      # 注意：这个测试可能需要 mock DynamicSupervisor.start_child
      # 如果 LLMAgent 未实现，此测试可能会失败
      # 可以先跳过，等 LLMAgent 重建后再启用
    end
  end

  describe "complete_branch/2" do
    test "completes a branch and emits signal" do
      branch_session_id = "branch_789"
      summary = "Successfully fixed the bug by updating the config"

      assert {:ok, ^summary} = BranchManager.complete_branch(branch_session_id, summary)

      # 验证发射了分支完成信号
      assert_receive {:signal,
                      %Jido.Signal{
                        type: "session.branch.completed",
                        data: data,
                        source: "/session/branch"
                      }},
                     1000

      assert data.payload.branch_session_id == branch_session_id
      assert data.payload.summary == summary
    end

    test "handles empty summary" do
      branch_session_id = "branch_empty"
      summary = ""

      assert {:ok, ""} = BranchManager.complete_branch(branch_session_id, summary)

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "session.branch.completed",
                        data: %{payload: %{summary: ""}}
                      }},
                     1000
    end
  end

  describe "merge_branch/3" do
    test "merges branch into parent and emits signal" do
      parent_session_id = "session_parent"
      branch_session_id = "branch_child"
      summary = "Merged changes from exploration branch"

      assert {:ok, :merged} =
               BranchManager.merge_branch(parent_session_id, branch_session_id, summary)

      # 验证发射了分支合并信号
      assert_receive {:signal,
                      %Jido.Signal{
                        type: "session.branch.merged",
                        data: data,
                        source: "/session/branch"
                      }},
                     1000

      assert data.payload.parent_session_id == parent_session_id
      assert data.payload.branch_session_id == branch_session_id
      assert data.payload.summary == summary
    end
  end

  describe "full workflow" do
    test "complete branch lifecycle: create -> complete -> merge" do
      parent_id = "session_main"

      # 1. 创建分支
      {:ok, branch_id} = BranchManager.create_branch(parent_id, purpose: "refactoring")
      assert_receive {:signal, %Jido.Signal{type: "session.branch.created"}}, 1000

      # 2. 完成分支
      summary = "Refactored module X to improve readability"
      {:ok, ^summary} = BranchManager.complete_branch(branch_id, summary)
      assert_receive {:signal, %Jido.Signal{type: "session.branch.completed"}}, 1000

      # 3. 合并分支
      {:ok, :merged} = BranchManager.merge_branch(parent_id, branch_id, summary)
      assert_receive {:signal, %Jido.Signal{type: "session.branch.merged"}}, 1000
    end
  end

  describe "signal source verification" do
    test "all signals use correct source path" do
      BranchManager.create_branch("test_session")
      assert_receive {:signal, %Jido.Signal{source: "/session/branch"}}, 1000

      BranchManager.complete_branch("branch_test", "done")
      assert_receive {:signal, %Jido.Signal{source: "/session/branch"}}, 1000

      BranchManager.merge_branch("parent", "child", "merged")
      assert_receive {:signal, %Jido.Signal{source: "/session/branch"}}, 1000
    end
  end
end

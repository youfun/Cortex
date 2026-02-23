defmodule Cortex.Phase3Test do
  use ExUnit.Case, async: false

  alias Cortex.Core.Security
  alias Cortex.Tools.ShellInterceptor
  alias Cortex.Tools.Handlers.ShellCommand
  alias Cortex.SignalHub

  @project_root System.tmp_dir!() |> Path.join("jido_phase3_#{System.unique_integer()}")

  setup do
    File.mkdir_p!(@project_root)
    # Start SignalHub and Bridge if not started (usually they are started by application)
    # But for unit tests, we might need them.
    # Actually, Cortex.SignalHub is likely already running in the test environment if it's in application.ex.

    on_exit(fn -> File.rm_rf!(@project_root) end)
    :ok
  end

  describe "Security Sandbox" do
    test "validate_path blocks traversal" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("../../../etc/passwd", @project_root)

      assert {:error, :path_escapes_boundary} =
               Security.validate_path("subdir/../../etc/passwd", @project_root)
    end

    test "validate_path blocks URL encoded traversal" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("%2e%2e/%2e%2e/etc/passwd", @project_root)
    end

    test "validate_cwd uses validate_path" do
      assert {:error, :path_escapes_boundary} = Security.validate_cwd("../../../", @project_root)
      assert {:ok, _} = Security.validate_cwd("subdir", @project_root)
    end
  end

  describe "Shell Interceptor" do
    test "allows safe commands" do
      assert :ok = ShellInterceptor.check("ls -la")
      assert :ok = ShellInterceptor.check("echo hello")
    end

    test "requires approval for high-risk commands" do
      SignalHub.subscribe("permission.request")

      assert {:approval_required, _} = ShellInterceptor.check("npm install lodash")

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "permission.request",
                        data: %{payload: %{command: "npm install lodash"}}
                      }}

      assert {:approval_required, _} = ShellInterceptor.check("rm -rf tmp")

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "permission.request",
                        data: %{payload: %{command: "rm -rf tmp"}}
                      }}
    end
  end

  describe "Shell Command Integration" do
    test "blocks high-risk commands with approval required error" do
      ctx = %{project_root: @project_root, session_id: "test"}

      assert {:error, {:approval_required, _}} =
               ShellCommand.execute(%{command: "npm install lodash"}, ctx)
    end

    test "blocks dangerous commands with permission denied" do
      ctx = %{project_root: @project_root, session_id: "test"}

      assert {:error, {:permission_denied, _}} =
               ShellCommand.execute(%{command: "sudo rm -rf /"}, ctx)
    end
  end

  describe "Session Branching" do
    test "create_branch emits signal" do
      SignalHub.subscribe("session.branch.created")

      parent_id = "main_session"
      Cortex.Session.BranchManager.create_branch(parent_id, purpose: "test-branch")

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "session.branch.created",
                        data: %{payload: %{parent_session_id: ^parent_id}}
                      }}
    end

    test "complete_branch emits signal" do
      SignalHub.subscribe("session.branch.completed")
      branch_id = "branch_123"
      summary = "Found the bug"

      Cortex.Session.BranchManager.complete_branch(branch_id, summary)

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "session.branch.completed",
                        data: %{payload: %{branch_session_id: ^branch_id, summary: ^summary}}
                      }}
    end
  end
end

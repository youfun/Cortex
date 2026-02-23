defmodule Cortex.Tools.ShellInterceptorTest do
  use Cortex.ProcessCase, async: false

  alias Cortex.Tools.ShellInterceptor
  alias Cortex.SignalHub

  describe "check/1" do
    test "allows safe commands" do
      assert :ok == ShellInterceptor.check("echo hello")
      assert :ok == ShellInterceptor.check("ls -la")
      assert :ok == ShellInterceptor.check("cat file.txt")
      assert :ok == ShellInterceptor.check("mix compile")
    end

    test "requires approval for npm install" do
      SignalHub.subscribe("permission.request")

      assert {:approval_required, reason} = ShellInterceptor.check("npm install express")
      assert reason =~ "Installing npm packages"

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "permission.request",
                        data: %{payload: %{command: "npm install express"}}
                      }},
                     1000
    end

    test "requires approval for mix deps.get" do
      SignalHub.subscribe("permission.request")

      assert {:approval_required, reason} = ShellInterceptor.check("mix deps.get")
      assert reason =~ "Fetching Elixir dependencies"

      assert_receive {:signal, %Jido.Signal{type: "permission.request"}}, 1000
    end

    test "requires approval for pip install" do
      assert {:approval_required, _reason} = ShellInterceptor.check("pip install numpy")
    end

    test "requires approval for git push" do
      SignalHub.subscribe("permission.request")

      assert {:approval_required, reason} = ShellInterceptor.check("git push origin main")
      assert reason =~ "Git write operation"

      assert_receive {:signal, %Jido.Signal{type: "permission.request"}}, 1000
    end

    test "requires approval for git merge" do
      assert {:approval_required, _reason} = ShellInterceptor.check("git merge feature-branch")
    end

    test "requires approval for git rebase" do
      assert {:approval_required, _reason} = ShellInterceptor.check("git rebase main")
    end

    test "requires approval for rm commands" do
      SignalHub.subscribe("permission.request")

      assert {:approval_required, reason} = ShellInterceptor.check("rm old_file.txt")
      assert reason =~ "Deleting files"

      assert_receive {:signal, %Jido.Signal{type: "permission.request"}}, 1000
    end

    test "requires approval for mv commands" do
      assert {:approval_required, reason} = ShellInterceptor.check("mv old.txt new.txt")
      assert reason =~ "Moving/renaming files"
    end

    test "emits correct signal data" do
      SignalHub.subscribe("permission.request")

      ShellInterceptor.check("npm install react")

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "permission.request",
                        data: data,
                        source: "/security/interceptor"
                      }},
                     1000

      assert data.payload.command == "npm install react"
      assert data.payload.reason =~ "Installing npm packages"
      assert data.payload.tool == "shell"
      assert data.provider == "system"
      assert data.event == "permission"
      assert data.action == "request"
      assert data.actor == "shell_interceptor"
      assert data.origin.channel == "system"
    end

    test "handles compound commands" do
      # npm i 是 npm install 的简写
      assert {:approval_required, _} = ShellInterceptor.check("npm i lodash")
    end

    test "case insensitive command matching" do
      # 即使大写也应该被检测
      assert :ok == ShellInterceptor.check("Echo Hello")
    end
  end
end

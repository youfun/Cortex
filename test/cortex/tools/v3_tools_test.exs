defmodule Cortex.Tools.V3ToolsTest do
  use Cortex.ToolsCase, async: false

  alias Cortex.Tools.ToolRunner

  @project_root System.tmp_dir!() |> Path.join("jido_test_#{System.unique_integer()}")
  @ctx %{project_root: @project_root, session_id: "test_session"}

  setup do
    File.mkdir_p!(@project_root)
    on_exit(fn -> File.rm_rf!(@project_root) end)
    :ok
  end

  describe "read_file" do
    test "reads existing file" do
      path = Path.join(@project_root, "hello.txt")
      File.write!(path, "Hello World")

      assert {:ok, output, _} =
               ToolRunner.execute("read_file", %{path: path}, @ctx)

      assert output == "Hello World"
    end

    test "errors on non-existent file" do
      assert {:error, _, _} =
               ToolRunner.execute(
                 "read_file",
                 %{path: Path.join(@project_root, "nonexistent.txt")},
                 @ctx
               )
    end
  end

  describe "write_file" do
    test "creates new file" do
      path = Path.join(@project_root, "new.txt")

      assert {:ok, _, _} =
               ToolRunner.execute(
                 "write_file",
                 %{path: path, content: "New content"},
                 @ctx
               )

      assert File.read!(path) == "New content"
    end
  end

  describe "edit_file" do
    test "replaces exact string" do
      path = Path.join(@project_root, "edit_me.txt")
      File.write!(path, "Hello World\nFoo Bar")

      assert {:ok, _, _} =
               ToolRunner.execute(
                 "read_file",
                 %{path: path},
                 @ctx
               )

      assert {:ok, _, _} =
               ToolRunner.execute(
                 "edit_file",
                 %{
                   path: path,
                   old_string: "Foo Bar",
                   new_string: "Baz Qux"
                 },
                 @ctx
               )

      assert File.read!(path) == "Hello World\nBaz Qux"
    end
  end

  describe "shell" do
    test "executes simple command" do
      # 使用跨平台命令
      assert {:ok, output, _} =
               ToolRunner.execute(
                 "shell",
                 %{
                   command: "echo hello_from_shell"
                 },
                 @ctx
               )

      assert String.contains?(output, "hello_from_shell")
    end

    test "blocks dangerous commands" do
      assert {:error, {:permission_denied, _}, _} =
               ToolRunner.execute(
                 "shell",
                 %{
                   command: "sudo rm -rf /"
                 },
                 @ctx
               )
    end
  end

end

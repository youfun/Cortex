defmodule Cortex.Tools.Handlers.ReadStructureTest do
  use ExUnit.Case, async: true

  alias Cortex.Tools.Handlers.ReadStructure

  setup do
    # Create a temporary directory for test files
    tmp_dir = System.tmp_dir!() |> Path.join("read_structure_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "execute/2 with Elixir files" do
    test "extracts module structure from Elixir file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "sample.ex")

      content = """
      defmodule Sample do
        @moduledoc "A sample module"

        use GenServer
        alias Some.Module

        @type state :: map()

        @spec init(any()) :: {:ok, map()}
        def init(_args) do
          {:ok, %{}}
        end

        defp private_helper(x) do
          x + 1
        end
      end
      """

      File.write!(file_path, content)

      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:ok, result} = ReadStructure.execute(%{path: file_path}, ctx)

      # Verify structure extraction
      assert result =~ "defmodule Sample"
      assert result =~ "@moduledoc"
      assert result =~ "use GenServer"
      assert result =~ "alias Some.Module"
      assert result =~ "@type"
      assert result =~ "state"
      assert result =~ "@spec"
      assert result =~ "init"
      assert result =~ "def init/1"
      assert result =~ "defp private_helper/1"

      # Verify function bodies are NOT included
      refute result =~ "{:ok, %{}}"
      refute result =~ "x + 1"
    end

    test "handles syntax errors with regex fallback", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "broken.ex")

      content = """
      defmodule Broken do
        def incomplete(
      end
      """

      File.write!(file_path, content)

      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:ok, result} = ReadStructure.execute(%{path: file_path}, ctx)

      # Should still extract what it can via regex
      assert result =~ "Regex Fallback"
      assert result =~ "defmodule Broken"
    end
  end

  describe "execute/2 with Python files" do
    test "extracts Python structure with classes and functions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "sample.py")

      content = """
      from typing import List, Optional
      import os

      class UserService:
          def __init__(self, db_connection):
              self.db = db_connection

          def get_user(self, user_id: int) -> Optional[dict]:
              return self.db.query(user_id)

          async def create_user(self, name: str, email: str) -> dict:
              return await self.db.insert(name, email)

      def helper_function(x, y):
          return x + y

      @decorator
      def decorated_function():
          pass
      """

      File.write!(file_path, content)

      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:ok, result} = ReadStructure.execute(%{path: file_path}, ctx)

      assert result =~ "Python Structure"
      assert result =~ "from typing import"
      assert result =~ "import os"
      assert result =~ "class UserService"
      assert result =~ "def __init__"
      assert result =~ "def get_user"
      assert result =~ "async def create_user"
      assert result =~ "def helper_function"
      assert result =~ "@decorator"

      # 验证不包含函数体实现
      refute result =~ "self.db.query"
      refute result =~ "return x + y"
    end

    test "handles empty Python file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "empty.py")
      File.write!(file_path, "# Just a comment\n")

      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:ok, result} = ReadStructure.execute(%{path: file_path}, ctx)

      assert result =~ "Python Structure"
      assert result =~ "No class/function definitions found"
    end
  end

  describe "execute/2 with Golang files" do
    test "extracts Golang structure with types and functions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "sample.go")

      content = """
      package main

      import (
          "fmt"
          "net/http"
      )

      type User struct {
          ID   int
          Name string
      }

      type UserService interface {
          GetUser(id int) (*User, error)
      }

      func NewUserService() *UserService {
          return &UserService{}
      }

      func (s *UserService) GetUser(id int) (*User, error) {
          return &User{ID: id}, nil
      }

      const MaxUsers = 100

      var globalConfig Config
      """

      File.write!(file_path, content)

      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:ok, result} = ReadStructure.execute(%{path: file_path}, ctx)

      assert result =~ "Golang Structure"
      assert result =~ "package main"
      assert result =~ "import"
      assert result =~ "type User struct"
      assert result =~ "type UserService interface"
      assert result =~ "func NewUserService"
      assert result =~ "func (s *UserService) GetUser"
      assert result =~ "const MaxUsers"
      assert result =~ "var globalConfig"

      # 验证不包含函数体实现
      refute result =~ "return &User{ID: id}"
    end

    test "handles empty Golang file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "empty.go")
      File.write!(file_path, "// Just a comment\n")

      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:ok, result} = ReadStructure.execute(%{path: file_path}, ctx)

      assert result =~ "Golang Structure"
      assert result =~ "No package/type/func definitions found"
    end
  end

  describe "execute/2 with JavaScript files" do
    test "extracts JavaScript structure", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "sample.js")

      content = """
      export function myFunction(x) {
        return x * 2;
      }

      export class MyClass {
        constructor() {
          this.value = 0;
        }
      }

      const helper = () => {
        console.log("helper");
      };
      """

      File.write!(file_path, content)

      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:ok, result} = ReadStructure.execute(%{path: file_path}, ctx)

      assert result =~ "JavaScript/TypeScript Structure"
      assert result =~ "export function myFunction"
      assert result =~ "export class MyClass"
    end
  end

  describe "execute/2 with unsupported files" do
    test "returns preview for unsupported file types", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "data.json")

      content = """
      {
        "key": "value",
        "nested": {
          "data": [1, 2, 3]
        }
      }
      """

      File.write!(file_path, content)

      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:ok, result} = ReadStructure.execute(%{path: file_path}, ctx)

      assert result =~ "Unsupported File Type"
      assert result =~ "Preview"
      assert result =~ "data.json"
      assert result =~ ~s("key": "value")
    end
  end

  describe "execute/2 error handling" do
    test "returns error for missing file", %{tmp_dir: tmp_dir} do
      ctx = %{project_root: tmp_dir, session_id: "test"}
      {:error, msg} = ReadStructure.execute(%{path: "nonexistent.ex"}, ctx)

      assert msg =~ "File not found"
    end

    test "returns error for missing path argument" do
      ctx = %{project_root: "/tmp", session_id: "test"}
      {:error, msg} = ReadStructure.execute(%{}, ctx)

      assert msg == "Missing required argument: path"
    end
  end
end

defmodule Cortex.Tools.ToolSystemTest do
  use ExUnit.Case, async: false
  use Cortex.ProcessCase

  alias Cortex.Tools.{Registry, ToolRunner, Tool}
  alias Cortex.Agents.PermissionFlow

  defmodule MockHandler do
    @behaviour Cortex.Tools.ToolBehaviour
    def execute(args, _ctx) do
      if args[:fail] do
        {:error, "Mock failure"}
      else
        {:ok, "Executed with #{inspect(args)}"}
      end
    end
  end

  setup do
    # Registry is started by ProcessCase
    :ok
  end

  describe "Registry" do
    test "registers and retrieves a tool" do
      tool_name = "mock_tool_#{System.unique_integer()}"

      tool = %Tool{
        name: tool_name,
        description: "A mock tool",
        parameters: [arg1: [type: :string, required: true]],
        module: MockHandler
      }

      assert :ok = Registry.register(tool)
      assert {:ok, retrieved} = Registry.get(tool_name)
      assert retrieved.name == tool_name
      assert retrieved.module == MockHandler
    end

    test "generates LLM schema" do
      tool_name = "schema_tool_#{System.unique_integer()}"

      tool = %Tool{
        name: tool_name,
        description: "Schema test",
        parameters: [
          name: [type: :string, required: true, description: "The name"],
          age: [type: :integer, required: false, doc: "The age"]
        ],
        module: MockHandler
      }

      Registry.register(tool)

      schemas = Registry.to_llm_format()
      schema = Enum.find(schemas, fn s -> s.name == tool_name end)

      assert schema
      assert schema.description == "Schema test"
      props = schema.parameter_schema["properties"]
      assert props["name"]["type"] == "string"
      assert props["age"]["type"] == "integer"
      assert "name" in schema.parameter_schema["required"]
      refute "age" in schema.parameter_schema["required"]
    end
  end

  describe "ToolRunner" do
    test "executes a registered tool" do
      tool_name = "run_tool_#{System.unique_integer()}"

      tool = %Tool{
        name: tool_name,
        description: "Runner test",
        parameters: [],
        module: MockHandler
      }

      Registry.register(tool)

      args = %{"key" => "value", "fail" => false}
      assert {:ok, result, _elapsed_ms} = ToolRunner.execute(tool_name, args, %{})
      # Arguments should be normalized to atoms
      assert result =~ "Executed with %{fail: false, key: \"value\"}"
    end

    test "handles tool execution failure" do
      tool_name = "fail_tool_#{System.unique_integer()}"

      tool = %Tool{
        name: tool_name,
        description: "Fail test",
        parameters: [],
        module: MockHandler
      }

      Registry.register(tool)

      args = %{"fail" => true}
      assert {:error, "Mock failure", _elapsed_ms} = ToolRunner.execute(tool_name, args, %{})
    end

    test "returns error for non-existent tool" do
      assert {:error, :tool_not_found, _elapsed_ms} =
               ToolRunner.execute("non_existent_tool", %{}, %{})
    end
  end

  describe "PermissionFlow" do
    test "tracks and resolves pending requests" do
      pending = %{}
      call_id = "call_123"
      req_id = "req_abc"
      data = %{req_id: req_id, info: "test"}

      # Track
      pending = PermissionFlow.track_pending(pending, call_id, data)
      assert map_size(pending) == 1
      assert pending[call_id] == data

      # Resolve by req_id
      assert {:ok, ^call_id, ^data} = PermissionFlow.resolve(pending, req_id)

      # Resolve unknown
      assert :error = PermissionFlow.resolve(pending, "unknown_req")
    end
  end
end

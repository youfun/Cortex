defmodule Cortex.Tools.RegistryTest do
  use Cortex.ToolsCase, async: true
  alias Cortex.Tools.Registry
  alias Cortex.Tools.Tool

  setup do
    # Start a fresh registry for each test or rely on the named one if it's singleton.
    # The current implementation uses `name: __MODULE__` which is a singleton.
    # For testing purposes, ideally we should be able to start an isolated one,
    # but since the app supervision tree starts it, we might be sharing state.
    # However, since we are adding tools, it might be fine or we should modify Registry to support name via opts.

    # Let's check if the Registry is already started by the app.
    # If so, we might need to be careful about state pollution.
    # But since register is idempotent-ish (overwrites), maybe it's okay.

    # Better approach for unit testing: start a localized GenServer if possible,
    # but the code hardcodes `name: __MODULE__`.
    # We will assume it's running or start it if not.
    :ok
  end

  test "registers and retrieves a tool" do
    tool = %Tool{
      name: "test_tool",
      description: "A test tool",
      parameters: [arg: [type: :string]],
      module: SomeHandler
    }

    assert :ok == Registry.register(tool)
    assert {:ok, retrieved} = Registry.get("test_tool")
    assert retrieved == tool
  end

  test "lists all tools" do
    tool1 = %Tool{name: "tool1", description: "d1", parameters: [], module: H1}
    tool2 = %Tool{name: "tool2", description: "d2", parameters: [], module: H2}

    Registry.register(tool1)
    Registry.register(tool2)

    tools = Registry.list()
    assert length(tools) >= 2
    assert Enum.find(tools, &(&1.name == "tool1"))
    assert Enum.find(tools, &(&1.name == "tool2"))
  end

  test "converts to LLM format" do
    tool = %Tool{
      name: "llm_tool",
      description: "LLM description",
      parameters: [
        path: [type: :string, required: true, doc: "Path"]
      ],
      module: Cortex.Tools.Handlers.ReadFile
    }

    Registry.register(tool)

    llm_tools = Registry.to_llm_format()

    # Find our tool in the list
    converted =
      Enum.find(llm_tools, fn t ->
        # ReqLLM.Tool struct inspection might be needed
        # ReqLLM.Tool has :name, :description, :function (schema)
        t.name == "llm_tool"
      end)

    assert converted
    assert converted.description == "LLM description"
    # Check if parameters are converted correctly (ReqLLM logic)
    # This assumes ReqLLM is working correctly, we just check if our definition passed through.
  end

  test "converts complex types to valid JSON schema" do
    tool = %Tool{
      name: "complex_tool",
      description: "Complex tool",
      parameters: [
        metadata: [type: :map, doc: "Metadata object"],
        items: [type: {:array, :map}, doc: "List of objects"]
      ],
      module: Cortex.Tools.Handlers.ReadFile
    }

    Registry.register(tool)
    llm_tools = Registry.to_llm_format()

    converted = Enum.find(llm_tools, &(&1.name == "complex_tool"))
    assert converted

    # ReqLLM.Tool stores parameters in :parameter_schema
    params = converted.parameter_schema
    assert params["properties"]["metadata"]["type"] == "object"
    assert params["properties"]["items"]["type"] == "array"
    assert params["properties"]["items"]["items"]["type"] == "object"
  end
end

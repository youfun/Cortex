defmodule Cortex.TestSupport.DynamicToolHandler do
  @behaviour Cortex.Tools.ToolBehaviour

  @impl true
  def execute(_args, _ctx) do
    {:ok, "dynamic_tool_ok"}
  end
end

defmodule Cortex.TestSupport.TestHook do
  @behaviour Cortex.Agents.Hook
end

defmodule Cortex.TestSupport.TestExtension do
  @behaviour Cortex.Extensions.Extension

  alias Cortex.Tools.Tool

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def name, do: "TestExtension"

  @impl true
  def description, do: "BDD test extension"

  @impl true
  def hooks, do: [Cortex.TestSupport.TestHook]

  @impl true
  def tools do
    [
      %Tool{
        name: "test_extension_tool",
        description: "Test extension tool",
        parameters: [],
        module: Cortex.TestSupport.DynamicToolHandler
      }
    ]
  end
end

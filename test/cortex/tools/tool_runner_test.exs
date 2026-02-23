defmodule Cortex.Tools.ToolRunnerTest do
  use Cortex.ToolsCase, async: true
  alias Cortex.Tools.ToolRunner
  alias Cortex.Tools.Registry
  alias Cortex.Tools.Tool

  defmodule MockTool do
    def execute(%{content: content}, _ctx), do: {:ok, content}
  end

  test "truncates long output for unknown tool (default to tail)" do
    Registry.register(%Tool{
      name: "mock_tool",
      description: "Mock tool",
      parameters: [content: [type: :string, required: true]],
      module: MockTool
    })

    # 2000 lines
    long_content = String.duplicate("a\n", 2000)

    ctx = %{session_id: "test"}
    {:ok, result, _elapsed_ms} = ToolRunner.execute("mock_tool", %{content: long_content}, ctx)

    assert String.contains?(result, "[TRUNCATED: lines limit reached")
    assert String.contains?(result, "Output: 1000 lines")
  end

  test "truncates head for read_file" do
    long_content = String.duplicate("line\n", 2000)
    path = "long_file_test.txt"
    File.write!(path, long_content)

    ctx = %{session_id: "test", project_root: File.cwd!()}
    {:ok, result, _elapsed_ms} = ToolRunner.execute("read_file", %{path: path}, ctx)

    assert String.contains?(result, "[TRUNCATED: lines limit reached")
    # Head keeps start
    assert String.starts_with?(result, "line\n")

    File.rm!(path)
  end
end

defmodule Cortex.Actions.Utils.TruncateTest do
  use ExUnit.Case, async: true
  alias Cortex.Actions.Utils.Truncate

  test "truncates default (tail)" do
    text = String.duplicate("a", 100) <> "\n" <> String.duplicate("b", 100)

    # max_bytes = 10 -> will truncate almost everything
    params = %{text: text, max_bytes: 10}

    assert {:ok, result} = Truncate.run(params, %{})
    assert result.truncated == true
    assert result.truncated_by == :bytes
    # Tail keeps the end, so should end with b
    assert String.ends_with?(result.content, "b")
  end

  test "truncates head" do
    text = "line1\nline2\nline3"

    params = %{text: text, strategy: "head", max_lines: 1}

    assert {:ok, result} = Truncate.run(params, %{})
    assert result.truncated == true
    assert result.truncated_by == :lines
    assert result.content == "line1"
  end

  test "truncates tail" do
    text = "line1\nline2\nline3"

    params = %{text: text, strategy: "tail", max_lines: 1}

    assert {:ok, result} = Truncate.run(params, %{})
    assert result.truncated == true
    assert result.truncated_by == :lines
    assert result.content == "line3"
  end

  test "truncates line" do
    text = "This is a very long line that needs to be truncated."

    params = %{text: text, strategy: "line", max_chars: 10}

    assert {:ok, result} = Truncate.run(params, %{})
    assert result.truncated == true
    assert result.truncated_by == :chars
    assert String.starts_with?(result.content, "This is a ")
    assert String.ends_with?(result.content, " ... [truncated]")
  end

  test "missing text" do
    params = %{max_lines: 10}
    assert {:error, msg} = Truncate.run(params, %{})
    assert msg =~ "Missing required parameter"
  end

  test "invalid strategy" do
    params = %{text: "foo", strategy: "invalid"}
    assert {:error, msg} = Truncate.run(params, %{})
    assert msg =~ "Invalid strategy"
  end
end

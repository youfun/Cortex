defmodule Cortex.Tools.TruncateTest do
  use ExUnit.Case, async: true
  alias Cortex.Tools.Truncate

  describe "head truncation" do
    test "returns full content when under limits" do
      text = "line1\nline2\nline3"
      result = Truncate.truncate(text, :head, max_lines: 5, max_bytes: 100)
      assert result.content == text
      assert result.truncated == false
    end

    test "truncates by lines" do
      text = "line1\nline2\nline3"
      result = Truncate.truncate(text, :head, max_lines: 2)
      assert result.content == "line1\nline2"
      assert result.truncated == true
      assert result.truncated_by == :lines
      assert result.output_lines == 2
    end

    test "truncates by bytes" do
      text = "line1\nline2\nline3"
      # "line1\nline2" is 11 bytes
      result = Truncate.truncate(text, :head, max_bytes: 10)
      assert result.content == "line1"
      assert result.truncated == true
      assert result.truncated_by == :bytes
      assert result.output_lines == 1
    end
  end

  describe "tail truncation" do
    test "truncates by lines" do
      text = "line1\nline2\nline3"
      result = Truncate.truncate(text, :tail, max_lines: 2)
      assert result.content == "line2\nline3"
      assert result.truncated == true
      assert result.truncated_by == :lines
    end

    test "truncates by bytes" do
      text = "line1\nline2\nline3"
      # "line2\nline3" is 11 bytes
      result = Truncate.truncate(text, :tail, max_bytes: 10)
      # 10 bytes from end: "line3" (5) + "\n" (1) + "ine2" (4) = "ine2\nline3"
      assert result.content == "ine2\nline3"
      assert result.truncated == true
      assert result.truncated_by == :bytes
    end

    test "UTF-8 safe partial line truncation" do
      # "你好" is 6 bytes in UTF-8
      text = "abc\n你好"
      result = Truncate.truncate(text, :tail, max_bytes: 3)
      # Should only keep "你好" if we take 6 bytes, but we asked for 3.
      # 3 bytes is exactly "你" or "好".
      # Actually "你" is 3 bytes, "好" is 3 bytes.
      assert byte_size(result.content) <= 3
      assert result.truncated == true
    end
  end

  describe "truncate_line" do
    test "truncates long line" do
      text = "This is a very long line"
      result = Truncate.truncate_line(text, 10)
      assert result.content == "This is a  ... [truncated]"
      assert result.truncated == true
      assert result.truncated_by == :chars
    end
  end
end

defmodule Cortex.Channels.Shared.TextChunkerTest do
  use ExUnit.Case, async: true
  alias Cortex.Channels.Shared.TextChunker

  describe "chunk_text/2" do
    test "chunks text correctly" do
      assert TextChunker.chunk_text("abcdef", 2) == ["ab", "cd", "ef"]
      assert TextChunker.chunk_text("abcdef", 3) == ["abc", "def"]
      assert TextChunker.chunk_text("abcde", 3) == ["abc", "de"]
    end

    test "handles unicode" do
      assert TextChunker.chunk_text("你好世界", 2) == ["你好", "世界"]
    end

    test "empty string" do
      assert TextChunker.chunk_text("", 10) == []
    end
  end
end

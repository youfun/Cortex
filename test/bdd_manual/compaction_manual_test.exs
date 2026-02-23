defmodule Cortex.BDD.Manual.CompactionTest do
  use ExUnit.Case, async: false
  import Mimic

  setup :verify_on_exit!

  alias Cortex.BDD.Instructions.V1, as: Instr

  test "Token estimation basics" do
    ctx = %{run_id: "test"}
    ctx = Instr.run!(ctx, :when, :estimate_tokens, %{text: "Hello world"})
    Instr.run!(ctx, :then, :assert_tokens, %{expected: 3})

    ctx = Instr.run!(ctx, :when, :estimate_tokens, %{text: "你好世界"})
    Instr.run!(ctx, :then, :assert_tokens, %{expected: 8})
  end

  test "Sliding window preserves system messages" do
    messages = [
      %{role: "system", content: "sys"},
      %{role: "user", content: "1"},
      %{role: "assistant", content: "2"},
      %{role: "user", content: "3"}
    ]

    ctx = %{run_id: "test"}
    ctx = Instr.run!(ctx, :when, :sliding_window_split, %{messages: messages, window_size: 2})
    Instr.run!(ctx, :then, :assert_window_size, %{target: "old", expected: 1})
    Instr.run!(ctx, :then, :assert_window_size, %{target: "recent", expected: 3})
  end

  test "Compaction with LLM summary success" do
    messages = [
      %{role: "user", content: "q1"},
      %{role: "assistant", content: "a1"},
      %{role: "user", content: "q2"},
      %{role: "assistant", content: "a2"}
    ]

    ctx = %{run_id: "test"}
    ctx = Instr.run!(ctx, :given, :mock_compaction, %{summary: "Test Summary"})

    # Instructions.V1 forces keep_recent: 2, so [q1, a1] should be summarized
    # result should be [summary, q2, a2] -> 3 messages
    ctx = Instr.run!(ctx, :when, :compact, %{messages: messages})

    Instr.run!(ctx, :then, :assert_messages_count, %{expected: 3})
    Instr.run!(ctx, :then, :assert_message_content, %{index: 0, contains: "Test Summary"})
  end

  test "Compaction fallback to truncation on LLM failure" do
    messages = [
      %{role: "user", content: "q1"},
      %{role: "assistant", content: "a1"},
      %{role: "user", content: "q2"},
      %{role: "assistant", content: "a2"}
    ]

    ctx = %{run_id: "test"}
    ctx = Instr.run!(ctx, :given, :mock_compaction, %{fail: true})

    # LLM fails, so it should fallback to truncate_tool_outputs on all messages
    # In this case no tool outputs, so messages remain the same
    ctx = Instr.run!(ctx, :when, :compact, %{messages: messages})

    Instr.run!(ctx, :then, :assert_messages_count, %{expected: 4})
    Instr.run!(ctx, :then, :assert_message_content, %{index: 0, contains: "q1"})
  end
end

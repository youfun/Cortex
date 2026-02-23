defmodule Cortex.Hooks.MemoryHookTest do
  use ExUnit.Case, async: false

  alias Cortex.Hooks.MemoryHook
  alias Cortex.Memory.WorkingMemory

  setup do
    unless Process.whereis(WorkingMemory) do
      start_supervised!(WorkingMemory)
    end

    WorkingMemory.clear()
    :ok
  end

  describe "on_input/2 — sets WorkingMemory focus" do
    test "sets focus from user message" do
      agent_state = %{session_id: "test_session"}
      {:continue, _msg, _state} = MemoryHook.on_input(agent_state, "帮我写一个 GenServer")

      focus = WorkingMemory.get_focus()
      assert focus != nil
      assert focus.content =~ "GenServer"
    end

    test "truncates long messages" do
      agent_state = %{session_id: "test_session"}
      long_msg = String.duplicate("a", 500)
      {:continue, _msg, _state} = MemoryHook.on_input(agent_state, long_msg)

      focus = WorkingMemory.get_focus()
      assert focus != nil
      assert String.length(focus.content) <= 203
    end

    test "handles non-string input gracefully" do
      agent_state = %{session_id: "test_session"}
      {:continue, _msg, _state} = MemoryHook.on_input(agent_state, 42)

      # Should not crash, focus remains nil
      assert WorkingMemory.get_focus() == nil
    end
  end

  describe "before_tool_call/2 — adds curiosity" do
    test "adds curiosity for read_file" do
      agent_state = %{session_id: "test_session"}
      call_data = %{name: "read_file", args: %{"path" => "lib/app.ex"}}

      {:ok, _data, _state} = MemoryHook.before_tool_call(agent_state, call_data)

      all = WorkingMemory.list_all()
      curiosities = all.curiosities
      assert length(curiosities) >= 1
      assert hd(curiosities).content =~ "lib/app.ex"
    end

    test "adds curiosity for shell command" do
      agent_state = %{session_id: "test_session"}
      call_data = %{name: "shell", args: %{"command" => "mix test --trace"}}

      {:ok, _data, _state} = MemoryHook.before_tool_call(agent_state, call_data)

      all = WorkingMemory.list_all()
      curiosities = all.curiosities
      assert length(curiosities) >= 1
      assert hd(curiosities).content =~ "mix test"
    end

    test "adds curiosity for write_file" do
      agent_state = %{session_id: "test_session"}
      call_data = %{name: "write_file", args: %{"path" => "lib/new_module.ex"}}

      {:ok, _data, _state} = MemoryHook.before_tool_call(agent_state, call_data)

      all = WorkingMemory.list_all()
      curiosities = all.curiosities
      assert length(curiosities) >= 1
      assert hd(curiosities).content =~ "new_module.ex"
    end

    test "does not add curiosity for unknown tools" do
      agent_state = %{session_id: "test_session"}
      call_data = %{name: "unknown_tool", args: %{}}

      {:ok, _data, _state} = MemoryHook.before_tool_call(agent_state, call_data)

      all = WorkingMemory.list_all()
      assert all.curiosities == []
    end
  end

  describe "on_tool_result/2 — records concerns on errors" do
    test "adds concern when tool output contains error" do
      agent_state = %{session_id: "test_session"}
      result_data = %{output: "Error: file not found at lib/missing.ex"}

      {:ok, _data, _state} = MemoryHook.on_tool_result(agent_state, result_data)

      all = WorkingMemory.list_all()
      concerns = all.concerns
      assert length(concerns) >= 1
      assert hd(concerns).content =~ "Tool error"
    end

    test "does not add concern for successful output" do
      agent_state = %{session_id: "test_session"}
      result_data = %{output: "File written successfully to lib/app.ex"}

      {:ok, _data, _state} = MemoryHook.on_tool_result(agent_state, result_data)

      all = WorkingMemory.list_all()
      assert all.concerns == []
    end
  end

  describe "on_agent_end/1 — clears focus" do
    test "resets focus to idle when agent run ends" do
      agent_state = %{session_id: "test_session"}

      WorkingMemory.set_focus("some task")
      assert WorkingMemory.get_focus() != nil

      MemoryHook.on_agent_end(agent_state)

      focus = WorkingMemory.get_focus()
      assert focus.content == "(idle)"
    end
  end
end

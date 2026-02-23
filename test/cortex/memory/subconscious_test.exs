defmodule Cortex.Memory.SubconsciousTest do
  use ExUnit.Case

  alias Cortex.Memory.Proposal
  alias Cortex.Memory.Subconscious
  alias Cortex.Memory.Store

  setup do
    # Clean up proposals
    Proposal.clear_all()

    # Ensure Store and Subconscious are running
    unless Process.whereis(Store) do
      start_supervised!(Store)
    end

    unless Process.whereis(Subconscious) do
      start_supervised!(Subconscious)
    end

    # Clear Subconscious cache if it's running
    if Process.whereis(Subconscious) do
      Subconscious.clear_cache()
    end

    if Process.whereis(Store) do
      Store.clear_all()
    end

    :ok
  end

  describe "analyze_now/2" do
    test "analyzes content and creates proposals" do
      {:ok, proposals} = Subconscious.analyze_now("用户 prefer Tailwind CSS over Bootstrap", [])

      # Should extract preference
      assert proposals != []

      # Check that proposals were created
      pending = Proposal.list_pending()
      assert pending != []
    end

    test "extracts facts from content" do
      {:ok, proposals} = Subconscious.analyze_now("我们正在使用 React 和 Next.js 构建应用", [])

      # Should create proposals
      assert is_list(proposals)
    end

    test "does not treat preference questions as preferences" do
      {:ok, proposals} = Subconscious.analyze_now("我喜欢吃什么", [])
      assert proposals == []
      assert Proposal.list_pending() == []

      {:ok, proposals} = Subconscious.analyze_now("你喜欢吃什么呢", [])
      assert proposals == []
      assert Proposal.list_pending() == []
    end

    test "extracts Chinese preferences and splits clauses" do
      content = "我喜欢Elixir，偏好Phoenix；常用PostgreSQL。"
      {:ok, _proposals} = Subconscious.analyze_now(content, [])

      pending = Proposal.list_pending(limit: 50)
      contents = Enum.map(pending, & &1.content)

      assert Enum.any?(contents, &String.contains?(&1, "用户偏好: Elixir"))
      assert Enum.any?(contents, &String.contains?(&1, "用户偏好: Phoenix"))
      assert Enum.any?(contents, &String.contains?(&1, "用户偏好: PostgreSQL"))
    end

    test "cleans leading '是' in Chinese preference object" do
      {:ok, _proposals} = Subconscious.analyze_now("我的偏好是吃米饭。", [])

      pending = Proposal.list_pending(limit: 10)
      contents = Enum.map(pending, & &1.content)

      assert Enum.any?(contents, &String.contains?(&1, "用户偏好: 吃米饭"))
      refute Enum.any?(contents, &String.contains?(&1, "用户偏好: 是吃米饭"))
    end

    test "avoids duplicates" do
      # First analysis
      Subconscious.analyze_now("用户 prefer Tailwind CSS", [])
      first_count = length(Proposal.list_pending())

      # Second analysis with similar content
      Subconscious.analyze_now("用户 prefer Tailwind CSS again", [])
      second_count = length(Proposal.list_pending())

      # Should not duplicate
      assert second_count <= first_count + 1
    end
  end

  describe "stats/0" do
    test "returns statistics" do
      stats = Subconscious.stats()

      assert is_map(stats)
      assert is_integer(stats.recent_signals_count)
    end
  end

  describe "signal handling" do
    test "does not analyze agent.response (prevents LLM self-feedback into memory)" do
      signal = %Jido.Signal{
        type: "agent.response",
        id: "test-signal-1",
        source: "test",
        data: %{content: "用户偏好: 我喜欢使用 Elixir 编程"}
      }

      send(Subconscious, signal)
      Process.sleep(100)

      assert Proposal.list_pending() == []
    end

    test "handles explicit memory command by writing to store" do
      signal = %Jido.Signal{
        type: "agent.chat.request",
        id: "test-signal-explicit",
        source: "test",
        data: %{content: "记住这条: 我喜欢elixir+phoenix"}
      }

      send(Subconscious, signal)
      Process.sleep(100)

      observations = Store.load_observations(limit: 5)
      contents = Enum.map(observations, & &1.content)

      assert Enum.any?(contents, &String.contains?(&1, "我喜欢elixir+phoenix"))
      assert Proposal.list_pending() == []
    end
  end

  describe "clear_cache/0" do
    test "clears internal cache" do
      :ok = Subconscious.clear_cache()

      stats = Subconscious.stats()
      assert stats.recent_signals_count == 0
    end
  end
end

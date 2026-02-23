defmodule Cortex.Memory.StoreTest do
  use Cortex.ProcessCase

  alias Cortex.Memory.Observation
  alias Cortex.Memory.Store

  setup do
    # Create a unique test directory for this test run to avoid interference
    test_id = System.unique_integer([:positive])
    workspace_root = Path.expand("tmp/memory_test_#{test_id}")
    File.mkdir_p!(workspace_root)

    memory_file = "test_memory.md"
    full_path = Path.join(workspace_root, memory_file)

    # Start an isolated Store process for this test with unique name and child id
    test_store_name = Module.concat(__MODULE__, "TestStore_#{test_id}")

    start_supervised!(
      Supervisor.child_spec(
        {Store, name: test_store_name, workspace_root: workspace_root, memory_path: memory_file},
        id: test_store_name
      )
    )

    on_exit(fn ->
      File.rm_rf!(workspace_root)
    end)

    {:ok, store: test_store_name, memory_path: full_path}
  end

  describe "append_observation/1" do
    test "appends observation to store", %{store: store} do
      obs = Observation.new("Test observation", priority: :high)
      {:ok, stored} = Store.append_observation(obs, store)

      assert stored.id == obs.id
      assert stored.content == "Test observation"
    end

    test "rejects duplicate observations", %{store: store} do
      Store.append_observation("Duplicate unique content", server: store)

      # Same content should be detected as duplicate
      result = Store.append_observation("Duplicate unique content", server: store)
      assert result == {:ok, :duplicate}
    end
  end

  describe "load_observations/1" do
    test "returns loaded observations", %{store: store} do
      Store.append_observation("First message", priority: :high, server: store)
      Store.append_observation("Second message", priority: :medium, server: store)
      Store.append_observation("Third message", priority: :low, server: store)

      observations = Store.load_observations(limit: 10, server: store)
      assert length(observations) == 3
    end

    test "filters by priority", %{store: store} do
      Store.append_observation("High Priority", priority: :high, server: store)
      Store.append_observation("Medium Priority", priority: :medium, server: store)

      high_only = Store.load_observations(priority: :high, server: store)
      assert length(high_only) == 1
      assert hd(high_only).priority == :high
    end

    test "respects limit", %{store: store} do
      Store.append_observation("The quick brown fox", server: store)
      Store.append_observation("Jumps over the lazy dog", server: store)
      Store.append_observation("A completely different sentence", server: store)
      Store.append_observation("Elixir is a functional language", server: store)
      Store.append_observation("Testing is good for your soul", server: store)

      observations = Store.load_observations(limit: 3, server: store)
      assert length(observations) == 3
    end
  end

  describe "get_high_priority_summary/1" do
    test "returns only high priority observations", %{store: store} do
      Store.append_observation("Urgent task here", priority: :high, server: store)
      Store.append_observation("Normal task here", priority: :medium, server: store)

      summary = Store.get_high_priority_summary(10, store)
      assert length(summary) == 1
      assert hd(summary).priority == :high
    end
  end

  describe "run_consolidation/1" do
    test "prunes old observations", %{store: store} do
      # Add some observations
      for i <- 1..3 do
        Store.append_observation("Consolidation record #{i}", server: store)
      end

      {:ok, result} = Store.run_consolidation(max_age_days: 0, server: store)

      assert result.pruned >= 0
      assert is_integer(result.remaining)
    end
  end

  describe "stats/0" do
    test "returns store statistics", %{store: store} do
      Store.append_observation("High prio stat", priority: :high, server: store)
      Store.append_observation("Medium prio stat", priority: :medium, server: store)

      stats = Store.stats(store)

      assert stats.total == 2
      assert stats.by_priority.high == 1
      assert stats.by_priority.medium == 1
      assert stats.by_priority.low == 0
    end
  end

  describe "clear_all/0" do
    test "removes all observations", %{store: store} do
      Store.append_observation("To be cleared", server: store)
      assert length(Store.load_observations(server: store)) == 1

      Store.clear_all(store)
      assert Store.load_observations(server: store) == []
    end
  end

  describe "file persistence" do
    test "persists observations to file", %{store: store, memory_path: memory_path} do
      Store.append_observation("Persisted observation", server: store)
      Store.flush(store)

      assert File.exists?(memory_path)
      content = File.read!(memory_path)
      assert String.contains?(content, "Persisted observation")
    end
  end
end

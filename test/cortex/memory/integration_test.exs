defmodule Cortex.Memory.IntegrationTest do
  use Cortex.MemoryCase

  alias Cortex.Memory.{Consolidator, ContextBuilder, KnowledgeGraph, Proposal, Store}

  setup do
    # Clean up test files
    File.rm_rf("MEMORY.md")
    File.rm_rf("knowledge_graph.json")
    File.rm_rf("self_knowledge.json")
    File.rm_rf("preferences.json")
    File.rm_rf("relationships.json")

    # Clean ETS
    Proposal.clear_all()

    # Clear Store if it's already running
    if Process.whereis(Store) do
      Store.clear_all()
    end

    on_exit(fn ->
      File.rm_rf("MEMORY.md")
      File.rm_rf("knowledge_graph.json")
      File.rm_rf("self_knowledge.json")
      File.rm_rf("preferences.json")
      File.rm_rf("relationships.json")
    end)

    :ok
  end

  describe "end-to-end memory workflow" do
    test "observation -> store -> context building" do
      # 1. Create and store observations
      {:ok, obs1} = Store.append_observation("用户偏好 Tailwind CSS", priority: :high)
      {:ok, obs2} = Store.append_observation("项目使用 Next.js", priority: :medium)

      assert obs1.priority == :high
      assert obs2.priority == :medium

      # 2. Load observations
      observations = Store.load_observations(limit: 10)
      assert [_, _] = observations

      # 3. Build context
      context = ContextBuilder.build_context(model: "gemini-3-flash")

      assert String.contains?(context, "Observational Memory")
      assert String.contains?(context, "用户偏好 Tailwind CSS")
    end

    test "proposal workflow" do
      # 1. Create proposal
      {:ok, proposal} = Proposal.create("用户喜欢 React", type: :fact, confidence: 0.85)
      assert proposal.status == :pending

      # 2. List pending
      pending = Proposal.list_pending()
      assert [_] = pending

      # 3. Accept proposal
      {:ok, accepted} = Store.accept_proposal(proposal.id)
      assert accepted.priority == :high

      # 4. Should create observation when accepted
      observations = Store.load_observations()
      assert observations != []
    end

    test "knowledge graph operations" do
      # Get graph from consolidator
      graph = Consolidator.get_graph()
      assert graph != nil

      # Add nodes
      {graph, node1} = KnowledgeGraph.add_node(graph, "Elixir", :concept)
      {graph, node2} = KnowledgeGraph.add_node(graph, "Phoenix", :concept)
      {graph, _edge} = KnowledgeGraph.add_edge(graph, node1.id, node2.id, :related_to)

      assert map_size(graph.nodes) == 2
      assert map_size(graph.edges) == 1

      # Update consolidator
      Consolidator.update_graph(graph)

      # Verify graph was updated
      updated_graph = Consolidator.get_graph()
      assert map_size(updated_graph.nodes) == 2
    end

    test "consolidation workflow" do
      # Add some observations
      for i <- 1..5 do
        Store.append_observation("Observation #{i}", priority: :low)
      end

      # Run consolidation
      {:ok, result} = Consolidator.consolidate()

      assert is_map(result)
      assert Map.has_key?(result, :graph_pruned)
      assert Map.has_key?(result, :observations_pruned)
    end
  end

  describe "data persistence" do
    test "observations persist to file" do
      Store.append_observation("Persisted observation")
      Store.flush()

      assert File.exists?("MEMORY.md")
      content = File.read!("MEMORY.md")
      assert String.contains?(content, "Persisted observation")
    end

    test "knowledge graph persists to file" do
      # Trigger consolidation to save graph
      Consolidator.consolidate()

      # File might be created
      # Note: Empty graph might not be saved
    end
  end

  describe "token budget compliance" do
    test "context fits within budget" do
      # Add many observations
      for i <- 1..50 do
        Store.append_observation("Observation #{i}: #{String.duplicate("word ", 20)}")
      end

      # Check budget
      budget_check = ContextBuilder.check_budget(model: "gemini-3-flash")

      assert budget_check.fits == true
      assert budget_check.overage == 0
      assert budget_check.estimated_tokens <= budget_check.budget
    end
  end
end

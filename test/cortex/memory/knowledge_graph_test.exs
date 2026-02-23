defmodule Cortex.Memory.KnowledgeGraphTest do
  use ExUnit.Case, async: true

  alias Cortex.Memory.KnowledgeGraph

  describe "new/1" do
    test "creates empty knowledge graph" do
      graph = KnowledgeGraph.new("test")
      assert graph.name == "test"
      assert graph.nodes == %{}
      assert graph.edges == %{}
    end
  end

  describe "add_node/4" do
    test "adds node to graph" do
      graph = KnowledgeGraph.new("test")
      {updated, node} = KnowledgeGraph.add_node(graph, "Test content", :fact)

      assert node.content == "Test content"
      assert node.type == :fact
      assert node.strength == 1.0
      assert map_size(updated.nodes) == 1
    end

    test "adds node with custom options" do
      graph = KnowledgeGraph.new("test")

      {_updated, node} =
        KnowledgeGraph.add_node(graph, "Content", :concept,
          strength: 1.5,
          metadata: %{source: "test"}
        )

      assert node.strength == 1.5
      assert node.metadata == %{source: "test"}
    end
  end

  describe "get_node/2" do
    test "retrieves node and updates access info" do
      graph = KnowledgeGraph.new("test")
      {graph, node} = KnowledgeGraph.add_node(graph, "Test", :fact)

      original_count = node.access_count
      {updated_graph, retrieved} = KnowledgeGraph.get_node(graph, node.id)

      assert retrieved.id == node.id
      assert retrieved.access_count == original_count + 1
      assert updated_graph.nodes[node.id].access_count == original_count + 1
    end

    test "returns nil for non-existent node" do
      graph = KnowledgeGraph.new("test")
      assert KnowledgeGraph.get_node(graph, "non-existent") == nil
    end
  end

  describe "add_edge/5" do
    test "adds edge between nodes" do
      graph = KnowledgeGraph.new("test")
      {graph, node1} = KnowledgeGraph.add_node(graph, "Node 1", :fact)
      {graph, node2} = KnowledgeGraph.add_node(graph, "Node 2", :fact)

      {updated, edge} = KnowledgeGraph.add_edge(graph, node1.id, node2.id, :related_to)

      assert edge.source_id == node1.id
      assert edge.target_id == node2.id
      assert edge.type == :related_to
      assert map_size(updated.edges) == 1
    end

    test "raises error for non-existent source node" do
      graph = KnowledgeGraph.new("test")
      {graph, node} = KnowledgeGraph.add_node(graph, "Node", :fact)

      assert_raise ArgumentError, fn ->
        KnowledgeGraph.add_edge(graph, "non-existent", node.id)
      end
    end

    test "raises error for non-existent target node" do
      graph = KnowledgeGraph.new("test")
      {graph, node} = KnowledgeGraph.add_node(graph, "Node", :fact)

      assert_raise ArgumentError, fn ->
        KnowledgeGraph.add_edge(graph, node.id, "non-existent")
      end
    end
  end

  describe "reinforce/3" do
    test "increases node strength" do
      graph = KnowledgeGraph.new("test")
      {graph, node} = KnowledgeGraph.add_node(graph, "Test", :fact, strength: 1.0)

      reinforced = KnowledgeGraph.reinforce(graph, node.id, 0.2)
      reinforced_node = reinforced.nodes[node.id]

      assert reinforced_node.strength == 1.2
      assert reinforced_node.access_count == 1
    end

    test "caps strength at 2.0" do
      graph = KnowledgeGraph.new("test")
      {graph, node} = KnowledgeGraph.add_node(graph, "Test", :fact, strength: 1.9)

      reinforced = KnowledgeGraph.reinforce(graph, node.id, 0.5)
      assert reinforced.nodes[node.id].strength == 2.0
    end

    test "ignores non-existent node" do
      graph = KnowledgeGraph.new("test")
      assert KnowledgeGraph.reinforce(graph, "non-existent") == graph
    end
  end

  describe "decay/2" do
    test "decreases node strength over time" do
      graph = KnowledgeGraph.new("test")
      {graph, node} = KnowledgeGraph.add_node(graph, "Test", :fact, strength: 1.0)

      # Manually set last_accessed to yesterday
      yesterday = DateTime.add(DateTime.utc_now(), -86400, :second)
      old_node = %{node | last_accessed: yesterday}
      graph = %{graph | nodes: %{node.id => old_node}}

      decayed = KnowledgeGraph.decay(graph, 0.1)
      decayed_node = decayed.nodes[node.id]

      assert decayed_node.strength < 1.0
      assert decayed_node.strength >= 0.1
    end
  end

  describe "prune/3" do
    test "removes nodes below threshold" do
      graph = KnowledgeGraph.new("test")
      {graph, node1} = KnowledgeGraph.add_node(graph, "Strong", :fact, strength: 1.0)
      {graph, node2} = KnowledgeGraph.add_node(graph, "Weak", :fact, strength: 0.05)

      {pruned, count} = KnowledgeGraph.prune(graph, 0.1)

      assert count == 1
      assert map_size(pruned.nodes) == 1
      assert pruned.nodes[node1.id] != nil
      assert pruned.nodes[node2.id] == nil
    end

    test "removes edges of pruned nodes" do
      graph = KnowledgeGraph.new("test")
      {graph, node1} = KnowledgeGraph.add_node(graph, "Node 1", :fact, strength: 1.0)
      {graph, node2} = KnowledgeGraph.add_node(graph, "Node 2", :fact, strength: 0.05)
      {graph, _edge} = KnowledgeGraph.add_edge(graph, node1.id, node2.id)

      {pruned, _} = KnowledgeGraph.prune(graph, 0.1)

      assert map_size(pruned.edges) == 0
    end
  end

  describe "search/2" do
    test "finds nodes by content" do
      graph = KnowledgeGraph.new("test")
      {graph, _} = KnowledgeGraph.add_node(graph, "Elixir programming", :fact)
      {graph, _} = KnowledgeGraph.add_node(graph, "Python programming", :fact)
      {graph, _} = KnowledgeGraph.add_node(graph, "Cooking recipes", :fact)

      results = KnowledgeGraph.search(graph, "programming")
      assert length(results) == 2
    end

    test "is case insensitive" do
      graph = KnowledgeGraph.new("test")
      {graph, _} = KnowledgeGraph.add_node(graph, "Elixir Programming", :fact)

      results = KnowledgeGraph.search(graph, "programming")
      assert length(results) == 1
    end

    test "sorts by strength" do
      graph = KnowledgeGraph.new("test")
      {graph, _} = KnowledgeGraph.add_node(graph, "Low strength", :fact, strength: 0.5)
      {graph, _} = KnowledgeGraph.add_node(graph, "High strength", :fact, strength: 1.5)

      results = KnowledgeGraph.search(graph, "strength")
      assert hd(results).content == "High strength"
    end
  end

  describe "spreading_activation/3" do
    test "finds related nodes through edges" do
      graph = KnowledgeGraph.new("test")
      {graph, node1} = KnowledgeGraph.add_node(graph, "Elixir", :concept)
      {graph, node2} = KnowledgeGraph.add_node(graph, "Phoenix", :concept)
      {graph, node3} = KnowledgeGraph.add_node(graph, "Programming", :concept)

      {graph, _} = KnowledgeGraph.add_edge(graph, node1.id, node2.id, :related_to, strength: 0.8)
      {graph, _} = KnowledgeGraph.add_edge(graph, node2.id, node3.id, :related_to, strength: 0.8)

      activated = KnowledgeGraph.spreading_activation(graph, [node1.id], max_depth: 2)

      assert length(activated) >= 2
      activated_ids = Enum.map(activated, fn {node, _} -> node.id end)
      assert node2.id in activated_ids
    end

    test "filters by activation threshold" do
      graph = KnowledgeGraph.new("test")
      {graph, node1} = KnowledgeGraph.add_node(graph, "Source", :concept)
      {graph, node2} = KnowledgeGraph.add_node(graph, "Target", :concept)

      {graph, _} = KnowledgeGraph.add_edge(graph, node1.id, node2.id, :related_to, strength: 0.1)

      activated =
        KnowledgeGraph.spreading_activation(graph, [node1.id], activation_threshold: 0.5)

      # With low edge strength, activation should not spread
      assert length(activated) <= 1
    end
  end

  describe "stats/1" do
    test "returns graph statistics" do
      graph = KnowledgeGraph.new("test")
      {graph, _} = KnowledgeGraph.add_node(graph, "Node 1", :fact)
      {graph, _} = KnowledgeGraph.add_node(graph, "Node 2", :concept)

      {graph, _} =
        KnowledgeGraph.add_edge(
          graph,
          elem(Map.to_list(graph.nodes) |> hd(), 0),
          elem(Map.to_list(graph.nodes) |> Enum.at(1), 0)
        )

      stats = KnowledgeGraph.stats(graph)

      assert stats.node_count == 2
      assert stats.edge_count == 1
      assert stats.avg_strength > 0
      assert map_size(stats.by_type) > 0
    end
  end

  describe "serialization" do
    test "to_map and from_map round-trip" do
      graph = KnowledgeGraph.new("test")
      {graph, node} = KnowledgeGraph.add_node(graph, "Test", :fact, strength: 1.5)
      {graph, _} = KnowledgeGraph.add_node(graph, "Test 2", :concept)

      {graph, _} =
        KnowledgeGraph.add_edge(graph, node.id, elem(Map.to_list(graph.nodes) |> Enum.at(1), 0))

      map = KnowledgeGraph.to_map(graph)
      restored = KnowledgeGraph.from_map(map)

      assert restored.name == graph.name
      assert map_size(restored.nodes) == 2
      assert map_size(restored.edges) == 1
    end
  end
end

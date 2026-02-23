defmodule Cortex.TTS.NodeManagerTest do
  use ExUnit.Case, async: false
  alias Cortex.TTS.NodeManager
  alias Cortex.SignalHub

  setup do
    # Ensure NodeManager is clean or restarted if needed
    # Since it's a named process in the app, we might need to clear its state 
    # but for simple registration tests, it should be fine.
    :ok
  end

  test "registers a node via direct call" do
    node_id = "test_node_1"
    info = %{gpu: "RTX 4090", models: ["custom_voice"]}

    assert :ok = NodeManager.register_node(node_id, info)
    nodes = NodeManager.list_nodes()

    assert Map.has_key?(nodes, node_id)
    assert nodes[node_id].info == info
    assert nodes[node_id].status == :online
  end

  test "registers a node via signal" do
    node_id = "signal_node_1"
    payload = %{node_id: node_id, gpu: "RTX 3080"}

    {:ok, _} =
      SignalHub.emit("tts.node.register", %{
        provider: "gpu_node",
        event: "node",
        action: "register",
        actor: node_id,
        origin: %{channel: "gpu", client: "node", platform: "linux"},
        payload: payload
      })

    # Give it a moment to process the signal
    Process.sleep(100)

    nodes = NodeManager.list_nodes()
    assert Map.has_key?(nodes, node_id)
    assert nodes[node_id].status == :online
  end

  test "updates heartbeat via signal" do
    node_id = "heartbeat_node_1"
    NodeManager.register_node(node_id, %{})

    # Simulate time passing by manually setting last_seen back (if we had a way to inject state)
    # Instead, just verify it updates last_seen
    initial_nodes = NodeManager.list_nodes()
    initial_last_seen = initial_nodes[node_id].last_seen

    # Ensure time moves forward
    Process.sleep(10)

    {:ok, _} =
      SignalHub.emit("tts.node.heartbeat", %{
        provider: "gpu_node",
        event: "node",
        action: "heartbeat",
        actor: node_id,
        origin: %{channel: "gpu", client: "node", platform: "linux"},
        payload: %{node_id: node_id}
      })

    Process.sleep(100)

    updated_nodes = NodeManager.list_nodes()
    assert DateTime.compare(updated_nodes[node_id].last_seen, initial_last_seen) == :gt
  end
end

defmodule Cortex.Memory.InsightDetectorTest do
  use ExUnit.Case, async: false
  alias Cortex.Memory.InsightDetector
  alias Cortex.Memory.Consolidator
  alias Cortex.Memory.Proposal
  alias Cortex.Memory.Store

  setup do
    Mimic.copy(Consolidator)
    Mimic.copy(Proposal)
    Mimic.copy(Store)
    :ok
  end

  test "queues proposal when KG nodes exceed threshold" do
    Mimic.expect(Consolidator, :stats, fn -> %{graph: %{node_count: 200}} end)
    Mimic.expect(Store, :stats, fn -> %{total: 100} end)
    Mimic.expect(Proposal, :find_similar, fn _, _ -> nil end)
    Mimic.expect(Proposal, :create, fn _, _ -> {:ok, %{}} end)

    assert {:ok, :check_completed} = InsightDetector.detect_and_queue(node_threshold: 150)
  end

  test "queues proposal when observation count exceeds threshold" do
    Mimic.expect(Consolidator, :stats, fn -> %{graph: %{node_count: 50}} end)
    Mimic.expect(Store, :stats, fn -> %{total: 600} end)
    Mimic.expect(Proposal, :find_similar, fn _, _ -> nil end)
    Mimic.expect(Proposal, :create, fn _, _ -> {:ok, %{}} end)

    assert {:ok, :check_completed} = InsightDetector.detect_and_queue(obs_threshold: 500)
  end
end

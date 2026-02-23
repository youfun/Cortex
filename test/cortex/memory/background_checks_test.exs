defmodule Cortex.Memory.BackgroundChecksTest do
  use ExUnit.Case, async: false
  alias Cortex.Memory.BackgroundChecks
  alias Cortex.Memory.Store
  alias Cortex.Memory.Proposal
  alias Cortex.Memory.WorkingMemory
  alias Cortex.Memory.Preconscious

  setup do
    Mimic.copy(Store)
    Mimic.copy(Proposal)
    Mimic.copy(WorkingMemory)
    Mimic.copy(Preconscious)
    :ok
  end

  test "returns suggestions when memory store is full" do
    Mimic.expect(Store, :stats, fn -> %{total: 1000} end)
    Mimic.expect(Proposal, :stats, fn -> %{pending: 0} end)
    Mimic.expect(WorkingMemory, :get_focus, fn -> nil end)

    result = BackgroundChecks.run()
    assert "should_consolidate" in result.suggestions
    assert Enum.any?(result.warnings, &String.contains?(&1, "full"))
  end

  test "returns suggestions when pending proposals overflow" do
    Mimic.expect(Store, :stats, fn -> %{total: 100} end)
    Mimic.expect(Proposal, :stats, fn -> %{pending: 18} end)
    Mimic.expect(WorkingMemory, :get_focus, fn -> nil end)

    result = BackgroundChecks.run()
    assert "review_proposals" in result.suggestions
    assert Enum.any?(result.warnings, &String.contains?(&1, "nearly full"))
  end

  test "returns suggestions when preconscious surfaces items" do
    Mimic.expect(Store, :stats, fn -> %{total: 100} end)
    Mimic.expect(Proposal, :stats, fn -> %{pending: 0} end)
    Mimic.expect(WorkingMemory, :get_focus, fn -> %{content: "focus"} end)
    Mimic.expect(Preconscious, :check, fn _ -> [{:node, 0.8}] end)

    result = BackgroundChecks.run()
    assert Enum.any?(result.suggestions, &String.contains?(&1, "preconscious_surfaced"))
  end
end

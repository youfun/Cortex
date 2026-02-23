defmodule Cortex.History.DualTrackFilterTest do
  use ExUnit.Case, async: true

  alias Cortex.History.DualTrackFilter

  test "llm_visible? filters correctly" do
    assert DualTrackFilter.llm_visible?(%{type: "user.input.chat"})
    assert DualTrackFilter.llm_visible?(%{type: "agent.response"})
    assert DualTrackFilter.llm_visible?(%{type: "tool.result.read"})
    assert DualTrackFilter.llm_visible?(%{type: "tool.error.read"})
    assert DualTrackFilter.llm_visible?(%{type: "skill.loaded"})

    refute DualTrackFilter.llm_visible?(%{type: "system.heartbeat"})
    refute DualTrackFilter.llm_visible?(%{type: "tool.stream.shell"})
    refute DualTrackFilter.llm_visible?(%{type: "file.changed.write"})
  end

  test "filter_for_llm extracts subset" do
    signals = [
      %{type: "user.input.chat", data: %{content: "hi"}},
      %{type: "system.heartbeat", data: %{}},
      %{type: "agent.response", data: %{content: "hello"}}
    ]

    filtered = DualTrackFilter.filter_for_llm(signals)
    assert length(filtered) == 2
    assert Enum.at(filtered, 0).type == "user.input.chat"
    assert Enum.at(filtered, 1).type == "agent.response"
  end
end

defmodule Cortex.Memory.ContextBuilderTest do
  use Cortex.MemoryCase

  alias Cortex.Memory.ContextBuilder
  alias Cortex.Memory.Observation
  alias Cortex.Memory.Store

  setup do
    # Clean up test files
    File.rm_rf("MEMORY.md")

    # Clear the Store if it's already running
    if Process.whereis(Store) do
      Store.clear_all()
    end

    on_exit(fn ->
      File.rm_rf("MEMORY.md")
    end)

    :ok
  end

  describe "build_context/1" do
    test "returns empty string when no observations" do
      context = ContextBuilder.build_context(model: "gemini-3-flash")

      # Should either be empty or have headers only
      assert is_binary(context)
    end

    test "includes observations when available" do
      # Add some observations
      Store.append_observation("High priority item", priority: :high)
      Store.append_observation("Medium priority item", priority: :medium)

      context = ContextBuilder.build_context(model: "gemini-3-flash")

      assert String.contains?(context, "Observational Memory")
      assert String.contains?(context, "High priority item")
    end

    test "respects observation limit" do
      # Add many observations
      for i <- 1..20 do
        Store.append_observation("Observation #{i}")
      end

      context = ContextBuilder.build_context(model: "gemini-3-flash", observation_limit: 5)

      # Check that we have a limited context
      lines = String.split(context, "\n")
      # Should be relatively short due to limit
      assert length(lines) < 30
    end
  end

  describe "build_observations_section/1" do
    test "formats observations as section" do
      observations = [
        Observation.new("First", priority: :high),
        Observation.new("Second", priority: :medium)
      ]

      section = ContextBuilder.build_observations_section(observations)

      assert String.contains?(section, "Recent Observations")
      assert String.contains?(section, "[重要] First")
      assert String.contains?(section, "[一般] Second")
    end

    test "returns nil for empty list" do
      assert ContextBuilder.build_observations_section([]) == nil
    end
  end

  describe "build_high_priority_summary/1" do
    test "summarizes high priority items" do
      observations = [
        Observation.new("Important 1", priority: :high),
        Observation.new("Important 2", priority: :high)
      ]

      summary = ContextBuilder.build_high_priority_summary(observations)

      assert String.contains?(summary, "High Priority Notes")
      assert String.contains?(summary, "Important 1")
      assert String.contains?(summary, "Important 2")
    end

    test "returns nil when no high priority items" do
      observations = [
        Observation.new("Low", priority: :low)
      ]

      assert ContextBuilder.build_high_priority_summary(observations) == nil
    end
  end

  describe "format_observation_line/1" do
    test "formats with correct prefix" do
      high = Observation.new("Important", priority: :high)
      medium = Observation.new("Normal", priority: :medium)
      low = Observation.new("Note", priority: :low)

      assert String.contains?(ContextBuilder.format_observation_line(high), "[重要]")
      assert String.contains?(ContextBuilder.format_observation_line(medium), "[一般]")
      assert String.contains?(ContextBuilder.format_observation_line(low), "[备注]")
    end
  end

  describe "append_to_prompt/2" do
    test "appends memory context to base prompt" do
      base = "System instructions"

      # Add observation
      Store.append_observation("Test observation", priority: :high)

      result = ContextBuilder.append_to_prompt(base, model: "gemini-3-flash")

      assert String.starts_with?(result, "System instructions")
      assert String.contains?(result, "Observational Memory")
      assert String.contains?(result, "Test observation")
    end

    test "returns base prompt unchanged when no memory" do
      base = "System instructions"
      result = ContextBuilder.append_to_prompt(base, model: "gemini-3-flash")

      assert result == base
    end
  end

  describe "check_budget/1" do
    test "reports budget status" do
      result = ContextBuilder.check_budget(model: "gemini-3-flash")

      assert is_map(result)
      assert is_boolean(result.fits)
      assert is_integer(result.estimated_tokens)
      assert is_integer(result.budget)
      assert is_integer(result.overage)
    end
  end

  describe "stats/1" do
    test "returns statistics" do
      Store.append_observation("Test")

      stats = ContextBuilder.stats(model: "gemini-3-flash")

      assert stats.total_observations >= 1
      assert is_integer(stats.high_priority_count)
      assert is_integer(stats.memory_budget)
      assert is_binary(stats.memory_budget_formatted)
    end
  end
end

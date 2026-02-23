defmodule Cortex.Memory.ObservationTest do
  use ExUnit.Case, async: true

  alias Cortex.Memory.Observation

  describe "new/2" do
    test "creates observation with default values" do
      obs = Observation.new("Test content")

      assert obs.content == "Test content"
      assert obs.priority == :medium
      assert obs.id != nil
      assert obs.timestamp != nil
    end

    test "creates observation with custom priority" do
      obs = Observation.new("High priority", priority: :high)
      assert obs.priority == :high
    end

    test "creates observation with metadata" do
      obs = Observation.new("With metadata", metadata: %{source: "test"})
      assert obs.metadata == %{source: "test"}
    end
  end

  describe "to_markdown/1" do
    test "formats observation as markdown line" do
      obs =
        Observation.new("Test content",
          priority: :high,
          timestamp: ~U[2026-02-10 14:30:00Z]
        )

      markdown = Observation.to_markdown(obs)
      assert markdown == "🔴 14:30 Test content"
    end

    test "uses correct icons for priorities" do
      high = Observation.new("High", priority: :high, timestamp: ~U[2026-02-10 14:30:00Z])
      medium = Observation.new("Medium", priority: :medium, timestamp: ~U[2026-02-10 14:30:00Z])
      low = Observation.new("Low", priority: :low, timestamp: ~U[2026-02-10 14:30:00Z])

      assert String.starts_with?(Observation.to_markdown(high), "🔴")
      assert String.starts_with?(Observation.to_markdown(medium), "🟡")
      assert String.starts_with?(Observation.to_markdown(low), "🟢")
    end
  end

  describe "from_markdown/3" do
    test "parses markdown line into observation" do
      line = "🔴 14:30 用户偏好 Tailwind CSS"
      {:ok, obs} = Observation.from_markdown(line, ~D[2026-02-10])

      assert obs.priority == :high
      assert obs.content == "用户偏好 Tailwind CSS"
      assert obs.timestamp == ~U[2026-02-10 14:30:00Z]
    end

    test "returns error for invalid format" do
      line = "Invalid format without icon"
      assert {:error, _} = Observation.from_markdown(line)
    end
  end

  describe "parse_markdown/1" do
    test "parses full markdown content" do
      markdown = """
      # Observational Memory

      ## 2026-02-10
      🔴 14:30 用户正在构建一个 Next.js 应用
      🟡 15:00 用户拒绝了 Bootstrap

      ## 2026-02-11
      🟢 09:00 修正了 Ecto 查询问题
      """

      observations = Observation.parse_markdown(markdown)
      assert length(observations) == 3

      [first | _] = observations
      assert first.priority == :high
      assert first.content == "用户正在构建一个 Next.js 应用"
    end

    test "handles empty content" do
      assert Observation.parse_markdown("") == []
    end
  end

  describe "to_markdown_full/2" do
    test "round-trip: parse -> format -> parse" do
      original = [
        Observation.new("High priority item",
          priority: :high,
          timestamp: ~U[2026-02-10 16:00:00Z]
        ),
        Observation.new("Low priority item", priority: :low, timestamp: ~U[2026-02-10 14:30:00Z])
      ]

      markdown = Observation.to_markdown_full(original)
      reparsed = Observation.parse_markdown(markdown)

      assert length(reparsed) == 2

      # 验证内容一致（忽略 ID 和时间戳的微小差异）
      [first | _] = reparsed
      assert first.priority == :high
      assert String.contains?(first.content, "High priority item")
    end
  end

  describe "sorting and filtering" do
    test "sort_by_priority puts high first" do
      observations = [
        Observation.new("Low", priority: :low),
        Observation.new("High", priority: :high),
        Observation.new("Medium", priority: :medium)
      ]

      sorted = Observation.sort_by_priority(observations)
      priorities = Enum.map(sorted, & &1.priority)
      assert priorities == [:high, :medium, :low]
    end

    test "high_priority filters correctly" do
      observations = [
        Observation.new("High", priority: :high),
        Observation.new("Low", priority: :low)
      ]

      high = Observation.high_priority(observations)
      assert length(high) == 1
      assert hd(high).priority == :high
    end
  end

  describe "same_content?/2" do
    test "compares content ignoring id and timestamp" do
      a = Observation.new("Same content", priority: :high)
      b = Observation.new("Same content", priority: :high)
      c = Observation.new("Different content", priority: :high)

      assert Observation.same_content?(a, b)
      refute Observation.same_content?(a, c)
    end
  end

  describe "serialization" do
    test "to_map and from_map round-trip" do
      original =
        Observation.new("Test",
          priority: :high,
          metadata: %{key: "value"}
        )

      map = Observation.to_map(original)
      restored = Observation.from_map(map)

      assert restored.content == original.content
      assert restored.priority == original.priority
      assert restored.metadata == original.metadata
    end
  end
end

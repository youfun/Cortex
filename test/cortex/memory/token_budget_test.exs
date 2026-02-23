defmodule Cortex.Memory.TokenBudgetTest do
  use ExUnit.Case, async: true

  alias Cortex.Memory.TokenBudget

  describe "estimate_tokens/1" do
    test "estimates tokens for English text" do
      # "Hello world" -> 4 tokens (Hello(1.3) + space(1) + world(1.3) = 3.6 -> ceil -> 4)
      tokens = TokenBudget.estimate_tokens("Hello world")
      assert tokens == 4
    end

    test "estimates tokens for Chinese text" do
      # "你好世界" -> 8 tokens
      tokens = TokenBudget.estimate_tokens("你好世界")
      assert tokens == 8
    end

    test "handles nil input" do
      assert TokenBudget.estimate_tokens(nil) == 0
    end

    test "handles empty string" do
      assert TokenBudget.estimate_tokens("") == 0
    end
  end

  describe "estimate_tokens_list/1" do
    test "sums tokens for list of strings" do
      # "Hello" -> 2 tokens (Hello(1.3) + end = 2.3 -> ceil -> 2)
      # "world" -> 2 tokens (world(1.3) + end = 2.3 -> ceil -> 2)
      # Total: 4 tokens
      tokens = TokenBudget.estimate_tokens_list(["Hello", "world"])
      assert tokens == 4
    end
  end

  describe "get_context_size/1" do
    test "returns correct size for known models" do
      assert TokenBudget.get_context_size("gemini-3-flash") == 1_048_576
      assert TokenBudget.get_context_size("claude-opus") == 200_000
      assert TokenBudget.get_context_size("gpt-4o") == 128_000
    end

    test "returns default for unknown models" do
      assert TokenBudget.get_context_size("unknown-model") == 128_000
    end
  end

  describe "calculate_memory_budget/2" do
    test "calculates budget based on model" do
      # Gemini: 1,048,576 * 0.15 - 4000 = ~153,000
      budget = TokenBudget.calculate_memory_budget("gemini-3-flash")
      assert budget > 150_000
    end

    test "respects custom ratio" do
      budget_default = TokenBudget.calculate_memory_budget("gpt-4o")
      budget_low = TokenBudget.calculate_memory_budget("gpt-4o", memory_ratio: 0.05)

      assert budget_low < budget_default
    end
  end

  describe "crop_to_budget/3" do
    test "returns all items if within budget" do
      items = [
        %{content: "Short", priority: :high},
        %{content: "Also short", priority: :medium}
      ]

      result = TokenBudget.crop_to_budget(items, 1000)
      assert [_, _] = result.selected
      assert result.dropped == []
    end

    test "drops items when exceeding budget" do
      # ~500 tokens
      long_text = String.duplicate("word ", 100)

      items = [
        %{content: long_text, priority: :low},
        %{content: "Important", priority: :high}
      ]

      result = TokenBudget.crop_to_budget(items, 10)
      assert [_] = result.selected
      assert [_] = result.dropped
    end

    test "prioritizes high priority items" do
      items = [
        %{content: String.duplicate("a", 100), priority: :low},
        %{content: String.duplicate("b", 100), priority: :high}
      ]

      result = TokenBudget.crop_to_budget(items, 50)
      assert hd(result.selected).priority == :high
    end
  end

  describe "within_budget?/2" do
    test "returns true if within budget" do
      assert TokenBudget.within_budget?("Short text", 100)
    end

    test "returns false if exceeding budget" do
      long_text = String.duplicate("word ", 1000)
      refute TokenBudget.within_budget?(long_text, 100)
    end
  end

  describe "format_tokens/1" do
    test "formats tokens in human readable form" do
      assert TokenBudget.format_tokens(1_572_864) == "1.6M"
      assert TokenBudget.format_tokens(15728) == "15.7K"
      assert TokenBudget.format_tokens(500) == "500"
    end
  end

  describe "list_model_contexts/0" do
    test "returns map of model names to context sizes" do
      contexts = TokenBudget.list_model_contexts()
      assert is_map(contexts)
      assert contexts["gemini-3-flash"] == 1_048_576
      assert contexts["gpt-4o"] == 128_000
    end
  end
end

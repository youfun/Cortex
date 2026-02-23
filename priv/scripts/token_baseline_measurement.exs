#!/usr/bin/env elixir

# Token Baseline Measurement Script
# This script measures token usage for 10 different scenarios to establish a baseline

defmodule TokenBaselineMeasurement do
  @moduledoc """
  Measures token usage for various scenarios to establish a baseline.
  """

  alias Cortex.Agents.TokenCounter

  @scenarios [
    %{
      id: "BASELINE-001",
      name: "Simple English Query",
      text: "What is the weather today?",
      category: :simple_query
    },
    %{
      id: "BASELINE-002",
      name: "Simple Chinese Query",
      text: "今天天气怎么样？",
      category: :simple_query
    },
    %{
      id: "BASELINE-003",
      name: "Mixed Language Query",
      text: "请帮我查询 weather forecast for tomorrow",
      category: :mixed_query
    },
    %{
      id: "BASELINE-004",
      name: "Code Snippet",
      text: """
      def hello_world do
        IO.puts("Hello, World!")
      end
      """,
      category: :code
    },
    %{
      id: "BASELINE-005",
      name: "Long English Paragraph",
      text: """
      The quick brown fox jumps over the lazy dog. This is a sample paragraph
      that contains multiple sentences to test token counting for longer texts.
      We want to see how the token counter handles paragraphs with multiple
      sentences and various punctuation marks.
      """,
      category: :long_text
    },
    %{
      id: "BASELINE-006",
      name: "Long Chinese Paragraph",
      text: """
      这是一个测试段落，用于测试中文文本的 token 计数。我们希望看到 token 计数器
      如何处理包含多个句子的段落。这个段落包含了各种标点符号和多个句子，
      以便我们能够准确地测量 token 使用情况。
      """,
      category: :long_text
    },
    %{
      id: "BASELINE-007",
      name: "JSON Data",
      text: ~s({"name": "John Doe", "age": 30, "city": "New York", "hobbies": ["reading", "coding", "gaming"]}),
      category: :structured_data
    },
    %{
      id: "BASELINE-008",
      name: "Technical Documentation",
      text: """
      ## Installation

      To install this package, run:

      ```bash
      mix deps.get
      mix compile
      ```

      ## Usage

      First, start the application:

      ```elixir
      {:ok, pid} = MyApp.start_link()
      ```
      """,
      category: :documentation
    },
    %{
      id: "BASELINE-009",
      name: "Error Message",
      text: """
      ** (RuntimeError) An error occurred while processing your request.
      The system encountered an unexpected condition that prevented it from
      fulfilling the request. Please try again later or contact support.
      """,
      category: :error_message
    },
    %{
      id: "BASELINE-010",
      name: "Multi-turn Conversation",
      messages: [
        %{role: "user", content: "Hello, how are you?"},
        %{role: "assistant", content: "I'm doing well, thank you! How can I help you today?"},
        %{role: "user", content: "I need help with my code"},
        %{role: "assistant", content: "Sure! Please share your code and I'll be happy to help."}
      ],
      category: :conversation
    }
  ]

  def run do
    IO.puts("\n=== Token Baseline Measurement ===\n")
    IO.puts("Measuring token usage for 10 different scenarios...\n")

    results = Enum.map(@scenarios, &measure_scenario/1)

    print_summary(results)
    save_results(results)

    IO.puts("\n✅ Baseline measurement completed!")
    IO.puts("Results saved to: priv/baseline/token_baseline_results.json\n")
  end

  defp measure_scenario(%{messages: messages} = scenario) do
    tokens = TokenCounter.estimate_messages(messages)

    %{
      id: scenario.id,
      name: scenario.name,
      category: scenario.category,
      tokens: tokens,
      message_count: length(messages),
      type: :messages
    }
  end

  defp measure_scenario(scenario) do
    tokens = TokenCounter.estimate_tokens(scenario.text)
    char_count = String.length(scenario.text)

    %{
      id: scenario.id,
      name: scenario.name,
      category: scenario.category,
      tokens: tokens,
      char_count: char_count,
      type: :text
    }
  end

  defp print_summary(results) do
    IO.puts("| ID | Name | Category | Tokens | Details |")
    IO.puts("|----|----|----------|--------|---------|")

    Enum.each(results, fn result ->
      details = case result.type do
        :text -> "#{result.char_count} chars"
        :messages -> "#{result.message_count} messages"
      end

      IO.puts("| #{result.id} | #{result.name} | #{result.category} | #{result.tokens} | #{details} |")
    end)

    total_tokens = Enum.reduce(results, 0, fn r, acc -> acc + r.tokens end)
    avg_tokens = div(total_tokens, length(results))

    IO.puts("\n📊 Summary Statistics:")
    IO.puts("  - Total scenarios: #{length(results)}")
    IO.puts("  - Total tokens: #{total_tokens}")
    IO.puts("  - Average tokens per scenario: #{avg_tokens}")

    # Category breakdown
    category_stats = results
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, items} ->
      total = Enum.reduce(items, 0, fn r, acc -> acc + r.tokens end)
      avg = div(total, length(items))
      {category, %{count: length(items), total: total, avg: avg}}
    end)
    |> Enum.into(%{})

    IO.puts("\n📈 Category Breakdown:")
    Enum.each(category_stats, fn {category, stats} ->
      IO.puts("  - #{category}: #{stats.count} scenarios, #{stats.total} tokens (avg: #{stats.avg})")
    end)
  end

  defp save_results(results) do
    # Ensure directory exists
    File.mkdir_p!("priv/baseline")

    # Prepare data for JSON
    data = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: "1.0",
      scenarios: results,
      summary: %{
        total_scenarios: length(results),
        total_tokens: Enum.reduce(results, 0, fn r, acc -> acc + r.tokens end),
        average_tokens: div(Enum.reduce(results, 0, fn r, acc -> acc + r.tokens end), length(results))
      }
    }

    # Save to JSON file
    json = Jason.encode!(data, pretty: true)
    File.write!("priv/baseline/token_baseline_results.json", json)
  end
end

# Run the measurement
TokenBaselineMeasurement.run()

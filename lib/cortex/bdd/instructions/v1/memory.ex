defmodule Cortex.BDD.Instructions.V1.Memory do
  @moduledoc false

  import ExUnit.Assertions

  alias Cortex.Agents.SlidingWindow
  alias Cortex.BDD.Instructions.V1.Helpers
  alias Cortex.Config.LlmModel
  alias Cortex.Config.Metadata
  alias Cortex.Memory.TokenBudget
  alias Cortex.Tools.Truncate

  @spec capabilities() :: MapSet.t(atom())
  def capabilities do
    MapSet.new([
      :estimate_tokens,
      :assert_tokens,
      :estimate_messages,
      :assert_total_tokens,
      :sliding_window_split,
      :assert_window_size,
      :truncate_tool_outputs,
      :compact,
      :mock_compaction,
      :assert_messages_count,
      :assert_message_content,
      :truncate_head,
      :truncate_tail,
      :truncate_line,
      :assert_truncation_result
    ])
  end

  def run(ctx, kind, name, args) do
    case {kind, name} do
      {:when, :estimate_tokens} ->
        tokens = TokenBudget.estimate_tokens(args.text)
        {:ok, Map.put(ctx, :last_tokens, tokens)}

      {:when, :estimate_messages} ->
        messages = Helpers.parse_messages(args.messages)
        tokens = Cortex.Agents.TokenCounter.estimate_messages(messages)
        {:ok, Map.put(ctx, :last_tokens, tokens)}

      {:when, :sliding_window_split} ->
        messages = Helpers.parse_messages(args.messages)
        window_size = Map.get(args, :window_size, 20)
        {old, recent} = SlidingWindow.split(messages, window_size)
        {:ok, ctx |> Map.put(:window_old, old) |> Map.put(:window_recent, recent)}

      {:when, :truncate_tool_outputs} ->
        messages = Helpers.parse_messages(args.messages)
        truncated = Cortex.Agents.Compaction.truncate_tool_outputs(messages)
        {:ok, Map.put(ctx, :last_messages, truncated)}

      {:when, :compact} ->
        messages = Helpers.parse_messages(args.messages)
        model = Map.get(args, :model, "default")

        if Code.ensure_loaded?(Mimic) do
          Mimic.stub(Metadata, :get_model, fn _model ->
            %LlmModel{context_window: 128_000}
          end)

          mock_summary = Map.get(ctx, :mock_summary, "Default summary for testing")

          if Map.get(ctx, :mock_compaction_failure, false) do
            Mimic.expect(Cortex.LLM.Client, :complete, fn _model, _prompt ->
              {:error, "Mocked failure"}
            end)
          else
            Mimic.expect(Cortex.LLM.Client, :complete, fn _model, _prompt ->
              {:ok, mock_summary}
            end)
          end
        end

        context = %ReqLLM.Context{messages: messages}

        {:ok, compacted_context} =
          Cortex.Agents.Compaction.maybe_compact(context, model,
            threshold: 0.00001,
            keep_recent: 15
          )

        {:ok, Map.put(ctx, :last_messages, compacted_context.messages)}

      {:given, :mock_compaction} ->
        ctx =
          if Map.has_key?(args, :summary),
            do: Map.put(ctx, :mock_summary, args.summary),
            else: ctx

        new_ctx =
          if Map.get(args, :fail, false),
            do: Map.put(ctx, :mock_compaction_failure, true),
            else: ctx

        {:ok, new_ctx}

      {:when, :truncate_head} ->
        text = Helpers.get_text(ctx, args.content_var)
        opts = [max_lines: args[:max_lines], max_bytes: args[:max_bytes]]
        result = Truncate.truncate(text, :head, opts)
        {:ok, Map.put(ctx, :last_truncation, result)}

      {:when, :truncate_tail} ->
        text = Helpers.get_text(ctx, args.content_var)
        opts = [max_lines: args[:max_lines], max_bytes: args[:max_bytes]]
        result = Truncate.truncate(text, :tail, opts)
        {:ok, Map.put(ctx, :last_truncation, result)}

      {:when, :truncate_line} ->
        text = Helpers.get_text(ctx, args.content_var)
        result = Truncate.truncate_line(text, args.max_chars)
        {:ok, Map.put(ctx, :last_truncation, result)}

      {:then, :assert_tokens} ->
        actual = Map.fetch!(ctx, :last_tokens)

        assert actual == args.expected,
               "期望 tokens=#{args.expected}，实际：#{actual}"

        {:ok, ctx}

      {:then, :assert_total_tokens} ->
        actual = Map.fetch!(ctx, :last_tokens)

        assert actual == args.expected,
               "期望 total_tokens=#{args.expected}，实际：#{actual}"

        {:ok, ctx}

      {:then, :assert_window_size} ->
        old = Map.get(ctx, :window_old, [])
        recent = Map.get(ctx, :window_recent, [])

        case args.target do
          "old" -> assert length(old) == args.expected
          "recent" -> assert length(recent) == args.expected
        end

        {:ok, ctx}

      {:then, :assert_messages_count} ->
        actual = Map.fetch!(ctx, :last_messages)
        assert length(actual) == args.expected
        {:ok, ctx}

      {:then, :assert_message_content} ->
        messages = Map.fetch!(ctx, :last_messages)
        msg = Enum.at(messages, args.index)
        content = Helpers.get_message_content(msg)
        assert content =~ args.contains
        {:ok, ctx}

      {:then, :assert_truncation_result} ->
        actual = Map.fetch!(ctx, :last_truncation)

        if Map.has_key?(args, :truncated), do: assert(actual.truncated == args.truncated)

        if Map.has_key?(args, :truncated_by),
          do: assert(to_string(actual.truncated_by) == args.truncated_by)

        if Map.has_key?(args, :output_lines), do: assert(actual.output_lines == args.output_lines)

        {:ok, ctx}

      _ ->
        :no_match
    end
  end
end

defmodule Cortex.Agents.Compaction do
  @moduledoc """
  Context compaction engine using TokenCounter and SlidingWindow.
  Provides tiered compression with message role weights and hard limit protection.

  ## Compression Tiers (Sprint 1 Enhancement)
  1. Tier 1: Truncate old tool outputs
  2. Tier 2: LLM summarization of old messages
  3. Tier 3: Force drop oldest non-system messages (hard limit protection)

  ## Message Role Weights
  - system: ∞ (never truncated)
  - user (last): ∞ (never truncated)
  - user (history): 3 (high priority)
  - assistant: 2 (medium priority)
  - tool: 1 (low priority, truncated first)
  """

  import ReqLLM.Context, only: [assistant: 1]
  require Logger

  alias Cortex.Agents.TokenCounter
  alias Cortex.Agents.SlidingWindow
  alias Cortex.Config.Metadata
  alias Cortex.LLM.Client
  alias Cortex.SignalHub

  @default_threshold 0.8
  @default_keep_recent 15
  @max_tool_output_length 2000
  @hard_limit_threshold 0.95

  @doc """
  Evaluates if the context needs compaction based on token count and applies it if necessary.
  Supports on_compaction_before Hook for Extension system.
  """
  @spec maybe_compact(ReqLLM.Context.t(), String.t(), keyword()) :: {:ok, ReqLLM.Context.t()}
  def maybe_compact(%ReqLLM.Context{} = context, model_name, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    keep_recent = Keyword.get(opts, :keep_recent, @default_keep_recent)
    hooks = Keyword.get(opts, :hooks, [])
    agent_state = Keyword.get(opts, :agent_state, %{})

    max_tokens = get_context_limit(model_name)
    current_tokens = TokenCounter.estimate_messages(context.messages)

    cond do
      # Hard limit protection - force drop if over 95%
      current_tokens > max_tokens * @hard_limit_threshold ->
        force_drop(context, model_name, keep_recent)

      # Normal compaction - over soft threshold
      current_tokens > max_tokens * threshold ->
        # [S6] 调用 on_compaction_before Hook
        hook_data = %{
          messages: context.messages,
          token_count: current_tokens,
          threshold: threshold,
          max_tokens: max_tokens
        }

        case run_compaction_hooks(hooks, agent_state, hook_data) do
          {:ok, _data, _new_state} ->
            compact(context, model_name, keep_recent)

          {:cancel, reason, _new_state} ->
            Logger.info("[Compaction] Cancelled by hook: #{inspect(reason)}")
            {:ok, context}

          {:custom, custom_messages, _new_state} ->
            Logger.info("[Compaction] Using custom compression from hook")
            {:ok, %ReqLLM.Context{context | messages: custom_messages}}
        end

      # Within budget
      true ->
        {:ok, context}
    end
  end

  @doc """
  Main compaction logic with tiered compression:
  1. Tier 1: Truncate tool outputs in old messages
  2. Tier 2: LLM summarization of old messages
  3. Tier 3: Force drop oldest messages (fallback)
  """
  def compact(%ReqLLM.Context{messages: messages} = context, model_name, keep_recent) do
    original_count = length(messages)
    original_tokens = TokenCounter.estimate_messages(messages)

    {to_compress, to_keep} = SlidingWindow.split(messages, keep_recent)

    result =
      if Enum.empty?(to_compress) do
        # No old messages to compress, truncate recent tool outputs
        {:ok, %ReqLLM.Context{context | messages: truncate_tool_outputs(to_keep)}}
      else
        # Tier 1: Truncate tool outputs in old messages
        compressed_old = truncate_tool_outputs(to_compress)
        tier1_messages = compressed_old ++ to_keep

        if within_budget?(tier1_messages, model_name) do
          {:ok, %ReqLLM.Context{context | messages: tier1_messages}}
        else
          # Tier 2: LLM summarization
          attempt_summarization(context, model_name, compressed_old, to_keep)
        end
      end

    # Emit telemetry and signal on success
    case result do
      {:ok, %ReqLLM.Context{messages: new_messages}} = success ->
        new_count = length(new_messages)
        new_tokens = TokenCounter.estimate_messages(new_messages)
        strategy = determine_strategy(original_count, new_count, to_compress)

        emit_compaction_telemetry(
          original_count,
          new_count,
          original_tokens,
          new_tokens,
          strategy
        )

        notify_compaction_result(original_count, new_count, original_tokens, new_tokens, strategy)

        success

      error ->
        error
    end
  end

  @doc """
  Force drop oldest non-system messages when hard limit is reached.
  This is the last resort to prevent API errors.
  """
  def force_drop(%ReqLLM.Context{messages: messages} = context, model_name, _keep_recent) do
    max_tokens = get_context_limit(model_name)

    # Separate system messages and others
    {system_msgs, other_msgs} = Enum.split_with(messages, &(get_role(&1) == "system"))

    # Keep last user message + recent messages
    {last_user, rest} = extract_last_user_message(other_msgs)

    # Sort remaining by weight and timestamp, drop lowest priority first
    weighted = weight_messages(rest)

    # Keep dropping until within budget
    final_msgs =
      Enum.reduce_while(weighted, [], fn msg, acc ->
        candidate =
          system_msgs
          |> append_list([last_user | Enum.reverse(acc)])
          |> append_one(msg)

        tokens = TokenCounter.estimate_messages(candidate)

        if tokens < max_tokens * 0.9 do
          {:cont, [msg | acc]}
        else
          {:halt, acc}
        end
      end)
      |> Enum.reverse()

    result_messages = append_list(system_msgs, [last_user | final_msgs])

    # Emit telemetry and signal
    original_count = length(messages)
    original_tokens = TokenCounter.estimate_messages(messages)
    new_count = length(result_messages)
    new_tokens = TokenCounter.estimate_messages(result_messages)

    emit_compaction_telemetry(
      original_count,
      new_count,
      original_tokens,
      new_tokens,
      :tier3_force_drop
    )

    notify_compaction_result(
      original_count,
      new_count,
      original_tokens,
      new_tokens,
      :tier3_force_drop
    )

    {:ok, %ReqLLM.Context{context | messages: result_messages}}
  end

  @doc """
  Truncates long tool outputs to reduce context size without losing the fact that a tool was called.
  """
  def truncate_tool_outputs(messages) when is_list(messages) do
    Enum.map(messages, fn msg ->
      if get_role(msg) == "tool" do
        tool_call_id = Map.get(msg, :tool_call_id) || Map.get(msg, "tool_call_id")

        content = Map.get(msg, :content) || Map.get(msg, "content")

        new_content =
          if is_list(content) do
            Enum.map(content, fn
              %{text: text} = part when is_binary(text) ->
                if String.length(text) > @max_tool_output_length do
                  truncated =
                    String.slice(text, 0, @max_tool_output_length) <>
                      "\n\n... [Output truncated for brevity] ..."

                  truncated =
                    if is_binary(tool_call_id),
                      do: truncated <> "\n\n[tool_call_id: #{tool_call_id}]",
                      else: truncated

                  %{part | text: truncated}
                else
                  part
                end

              %{"text" => text} = part when is_binary(text) ->
                if String.length(text) > @max_tool_output_length do
                  truncated =
                    String.slice(text, 0, @max_tool_output_length) <>
                      "\n\n... [Output truncated for brevity] ..."

                  truncated =
                    if is_binary(tool_call_id),
                      do: truncated <> "\n\n[tool_call_id: #{tool_call_id}]",
                      else: truncated

                  Map.put(part, "text", truncated)
                else
                  part
                end

              part ->
                part
            end)
          else
            if is_binary(content) and String.length(content) > @max_tool_output_length do
              truncated =
                String.slice(content, 0, @max_tool_output_length) <>
                  "\n\n... [Output truncated for brevity] ..."

              if is_binary(tool_call_id),
                do: truncated <> "\n\n[tool_call_id: #{tool_call_id}]",
                else: truncated
            else
              content
            end
          end

        case msg do
          %_struct{} ->
            %{msg | content: new_content}

          _ ->
            Map.put(
              msg,
              if(Map.has_key?(msg, :content), do: :content, else: "content"),
              new_content
            )
        end
      else
        msg
      end
    end)
  end

  # Private helpers

  defp attempt_summarization(context, model_name, compressed_old, to_keep) do
    summary_prompt =
      "Summarize the following conversation context concisely. " <>
        "Preserve key decisions, file paths, tool results, and current task state. " <>
        "Focus on facts and outcomes, omit conversational filler."

    transcript = format_messages(compressed_old)

    case Client.complete(model_name, summary_prompt <> "\n\n" <> transcript) do
      {:ok, summary} ->
        summary_msg = assistant("[Context Summary]\n" <> summary)
        {systems, others} = Enum.split_with(to_keep, &(get_role(&1) == "system"))

        new_messages =
          systems
          |> append_one(summary_msg)
          |> append_list(others)

        %ReqLLM.Context{} = context
        {:ok, %{context | messages: new_messages}}

      {:error, _reason} ->
        # Tier 3: Force drop as last resort
        force_drop(context, model_name, @default_keep_recent)
    end
  end

  defp within_budget?(messages, model_name) do
    max_tokens = get_context_limit(model_name)
    current_tokens = TokenCounter.estimate_messages(messages)
    current_tokens < max_tokens * @default_threshold
  end

  defp extract_last_user_message(messages) do
    case Enum.reverse(messages) |> Enum.find(&(get_role(&1) == "user")) do
      nil ->
        # No user message found, return empty placeholder
        {%{role: "user", content: [%{text: "[No user message]"}]}, messages}

      last_user ->
        rest = Enum.reject(messages, &(&1 == last_user))
        {last_user, rest}
    end
  end

  defp weight_messages(messages) do
    messages
    |> Enum.with_index()
    |> Enum.map(fn {msg, idx} ->
      role = get_role(msg)

      weight =
        case role do
          "system" -> 999_999
          "user" -> 3
          "assistant" -> 2
          "tool" -> 1
          _ -> 1
        end

      # Combine weight with recency (higher index = more recent = higher priority)
      {msg, weight * 1000 + idx}
    end)
    |> Enum.sort_by(fn {_msg, score} -> score end, :desc)
    |> Enum.map(fn {msg, _score} -> msg end)
  end

  defp format_messages(messages) do
    Enum.map_join(messages, "\n", fn msg ->
      role = get_role(msg)
      content = get_content(msg)
      "#{role}: #{content}"
    end)
  end

  defp get_role(%{role: role}), do: to_string(role)
  defp get_role(%{"role" => role}), do: to_string(role)
  defp get_role(_), do: "unknown"

  defp get_content(msg) do
    content = Map.get(msg, :content) || Map.get(msg, "content")

    case content do
      text when is_binary(text) ->
        text

      parts when is_list(parts) ->
        Enum.map_join(parts, " ", fn
          %{text: text} -> text
          %{"text" => text} -> text
          _ -> ""
        end)

      _ ->
        ""
    end
  end

  defp get_context_limit(model_name) do
    case Metadata.get_model(model_name) do
      nil -> 128_000
      model -> model.context_window || 128_000
    end
  end

  # Telemetry and Signal helpers

  defp emit_compaction_telemetry(original_count, new_count, original_tokens, new_tokens, strategy) do
    tokens_saved_ratio =
      if original_tokens > 0 do
        1 - new_tokens / original_tokens
      else
        0
      end

    :telemetry.execute(
      [:cortex, :compaction, :completed],
      %{
        original_messages: original_count,
        compressed_messages: new_count,
        original_tokens: original_tokens,
        compressed_tokens: new_tokens,
        tokens_saved_ratio: tokens_saved_ratio
      },
      %{strategy: strategy}
    )
  end

  defp notify_compaction_result(original_count, new_count, original_tokens, new_tokens, strategy) do
    SignalHub.emit(
      "memory.compaction.completed",
      %{
        provider: "agent",
        event: "compaction",
        action: "completed",
        actor: "system",
        origin: %{channel: "system", client: "compaction_engine"},
        original_messages: original_count,
        compressed_messages: new_count,
        original_tokens: original_tokens,
        compressed_tokens: new_tokens,
        messages_saved: original_count - new_count,
        tokens_saved: original_tokens - new_tokens,
        strategy: to_string(strategy)
      }, source: "/agent/compaction")
  end

  defp determine_strategy(original_count, new_count, to_compress) do
    cond do
      Enum.empty?(to_compress) -> :tier1_truncate_only
      new_count < original_count * 0.7 -> :tier2_llm_summary
      true -> :tier1_truncate
    end
  end

  # [S6] Hook runner for compaction
  defp run_compaction_hooks([], _agent_state, data), do: {:ok, data, %{}}

  defp run_compaction_hooks(hooks, agent_state, data) do
    alias Cortex.Agents.HookRunner
    HookRunner.run(hooks, :on_compaction_before, agent_state, data)
  end

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end

  defp append_list(list, tail) do
    tail
    |> Enum.reverse()
    |> then(&Enum.reverse(list, &1))
  end
end

defmodule Cortex.Tools.ToolRunner do
  @moduledoc """
  Single entry point for tool execution.
  """

  alias Cortex.Tools.Registry
  alias Cortex.Tools.Truncate

  def execute(tool_name, args, ctx) do
    case Registry.get(tool_name) do
      {:ok, tool} ->
        {elapsed_us, result} =
          :timer.tc(fn ->
            tool.module.execute(normalize_args(args), ctx)
          end)

        elapsed_ms = div(elapsed_us, 1000)

        case maybe_truncate(tool_name, result) do
          {:ok, output} -> {:ok, output, elapsed_ms}
          {:error, reason} -> {:error, reason, elapsed_ms}
        end

      :error ->
        {:error, :tool_not_found, 0}
    end
  end

  defp maybe_truncate(tool_name, {:ok, content}) when is_binary(content) do
    strategy =
      case tool_name do
        "read_file" -> :head
        "shell" -> :tail
        _ -> :tail
      end

    # Default limits: 30,000 bytes, 1,000 lines
    result = Truncate.truncate(content, strategy, max_bytes: 30_000, max_lines: 1000)

    if result.truncated do
      {:ok, format_truncated_result(result)}
    else
      {:ok, content}
    end
  end

  defp maybe_truncate(_tool_name, result), do: result

  defp format_truncated_result(result) do
    marker =
      "\n\n[TRUNCATED: #{result.truncated_by} limit reached. " <>
        "Total: #{result.total_lines} lines, #{result.total_bytes} bytes. " <>
        "Output: #{result.output_lines} lines, #{result.output_bytes} bytes.]"

    result.content <> marker
  end

  def execute_batch(calls, ctx, opts \\ []) when is_list(calls) do
    _ = opts

    Enum.map(calls, fn call ->
      id = Map.get(call, :id) || Map.get(call, "id")
      name = Map.get(call, :name) || Map.get(call, "name")
      args = Map.get(call, :args) || Map.get(call, "args") || %{}

      result =
        if is_binary(name) and name != "" do
          execute(name, args, ctx)
        else
          {:error, :tool_not_found, 0}
        end

      %{id: id, name: name, result: result}
    end)
  end

  defp normalize_args(args) when is_map(args) do
    Map.new(args, fn
      {k, v} when is_binary(k) ->
        case Cortex.Utils.SafeAtom.to_existing(k) do
          {:ok, atom} -> {atom, v}
          {:error, :not_found} -> {k, v}
        end

      {k, v} ->
        {k, v}
    end)
  end

  defp normalize_args(args), do: args
end

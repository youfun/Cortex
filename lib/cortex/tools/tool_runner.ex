defmodule Cortex.Tools.ToolRunner do
  @moduledoc """
  Single entry point for tool execution.
  """

  alias Cortex.Core.ContentRedactor
  alias Cortex.Core.SensitiveFileDetector
  alias Cortex.Tools.Registry
  alias Cortex.Tools.Truncate

  def execute(tool_name, args, ctx) do
    case Registry.get(tool_name) do
      {:ok, tool} ->
        case Cortex.Tools.ToolInterceptor.check(tool_name, args, ctx) do
          {:approval_required, reason} ->
            {:error, {:approval_required, reason}, 0}

          :ok ->
            normalized_args = normalize_args(args)

            {elapsed_us, result} =
              :timer.tc(fn ->
                tool.module.execute(normalized_args, ctx)
              end)

            elapsed_ms = div(elapsed_us, 1000)

            truncated = maybe_truncate(tool_name, result)
            redacted = maybe_redact(truncated, tool_name, normalized_args)

            case redacted do
              {:ok, output} -> {:ok, output, elapsed_ms}
              {:error, reason} -> {:error, reason, elapsed_ms}
            end
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

  defp maybe_redact({:ok, content}, tool_name, args) when is_binary(content) do
    path = get_path_from_args(tool_name, args)

    if path do
      case SensitiveFileDetector.detect(path) do
        :none ->
          {:ok, content}

        mode ->
          {redacted, _changed?} = ContentRedactor.redact(content, mode: mode, path: path)
          {:ok, redacted}
      end
    else
      if tool_name == "shell" do
        {redacted, _} = ContentRedactor.redact(content, mode: :value_redact)
        {:ok, redacted}
      else
        {:ok, content}
      end
    end
  end

  defp maybe_redact(result, _tool_name, _args), do: result

  defp get_path_from_args(tool_name, args)
       when tool_name in ["read_file", "write_file", "edit_file"] do
    Map.get(args, :path) || Map.get(args, "path")
  end

  defp get_path_from_args(_, _), do: nil

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

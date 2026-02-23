defmodule Cortex.Tools.Truncate do
  @moduledoc """
  Output truncation system, ported from Gong.Truncate.

  Strategies:
  - `:head` — Keep start, truncate end (supports max_lines + max_bytes).
  - `:tail` — Keep end, truncate start (supports max_lines + max_bytes).

  Single line truncation:
  - `truncate_line/2` — Truncate single line by character count.

  All operations are UTF-8 safe.
  """

  defmodule Result do
    @moduledoc "Truncation result structure"
    @derive Jason.Encoder
    defstruct content: "",
              truncated: false,
              truncated_by: nil,
              total_lines: 0,
              total_bytes: 0,
              output_lines: 0,
              output_bytes: 0,
              last_line_partial: false,
              first_line_exceeds_limit: false,
              max_lines: nil,
              max_bytes: nil
  end

  @default_max_bytes 30_000

  @type strategy :: :head | :tail

  @doc "Truncate text based on strategy, returns %Result{}"
  @spec truncate(String.t(), strategy(), keyword()) :: %Result{}
  def truncate(text, strategy \\ :tail, opts \\ [])

  def truncate(text, :head, opts) do
    max_lines = Keyword.get(opts, :max_lines)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    truncate_head(text, max_lines, max_bytes)
  end

  def truncate(text, :tail, opts) do
    max_lines = Keyword.get(opts, :max_lines)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    truncate_tail(text, max_lines, max_bytes)
  end

  @doc "Single line truncation: if exceeds max_chars, truncate and add marker."
  @spec truncate_line(String.t(), non_neg_integer()) :: %Result{}
  def truncate_line(text, max_chars) do
    total_bytes = byte_size(text)

    if String.length(text) <= max_chars do
      %Result{
        content: text,
        truncated: false,
        total_lines: 1,
        total_bytes: total_bytes,
        output_lines: 1,
        output_bytes: total_bytes
      }
    else
      truncated = String.slice(text, 0, max_chars)
      content = truncated <> " ... [truncated]"

      %Result{
        content: content,
        truncated: true,
        truncated_by: :chars,
        total_lines: 1,
        total_bytes: total_bytes,
        output_lines: 1,
        output_bytes: byte_size(content)
      }
    end
  end

  # ── Head Truncation: Keep Start ──

  defp truncate_head(text, max_lines, max_bytes) do
    total_bytes = byte_size(text)
    lines = String.split(text, "
")
    total_line_count = length(lines)
    effective_max_lines = max_lines || total_line_count

    within_lines = total_line_count <= effective_max_lines
    within_bytes = total_bytes <= max_bytes

    if within_lines and within_bytes do
      %Result{
        content: text,
        truncated: false,
        total_lines: total_line_count,
        total_bytes: total_bytes,
        output_lines: total_line_count,
        output_bytes: total_bytes,
        max_lines: max_lines,
        max_bytes: max_bytes
      }
    else
      do_truncate_head(
        lines,
        effective_max_lines,
        max_bytes,
        total_line_count,
        total_bytes,
        max_lines
      )
    end
  end

  defp do_truncate_head(
         lines,
         effective_max_lines,
         max_bytes,
         total_line_count,
         total_bytes,
         orig_max_lines
       ) do
    {kept, count, _bytes, truncated_by} =
      acc_head(lines, effective_max_lines, max_bytes, [], 0, 0)

    content = Enum.join(kept, "
")
    first_exceeds = count == 0 and truncated_by == :bytes

    %Result{
      content: content,
      truncated: true,
      truncated_by: truncated_by,
      total_lines: total_line_count,
      total_bytes: total_bytes,
      output_lines: count,
      output_bytes: byte_size(content),
      first_line_exceeds_limit: first_exceeds,
      max_lines: orig_max_lines,
      max_bytes: max_bytes
    }
  end

  defp acc_head([], _max_lines, _max_bytes, kept, count, bytes) do
    {Enum.reverse(kept), count, bytes, nil}
  end

  defp acc_head([line | rest], max_lines, max_bytes, kept, count, bytes) do
    if count >= max_lines do
      {Enum.reverse(kept), count, bytes, :lines}
    else
      separator = if count == 0, do: 0, else: 1
      new_bytes = bytes + separator + byte_size(line)

      if new_bytes > max_bytes do
        if count == 0 do
          {[], 0, 0, :bytes}
        else
          {Enum.reverse(kept), count, bytes, :bytes}
        end
      else
        acc_head(rest, max_lines, max_bytes, [line | kept], count + 1, new_bytes)
      end
    end
  end

  # ── Tail Truncation: Keep End ──

  defp truncate_tail(text, max_lines, max_bytes) do
    total_bytes = byte_size(text)
    lines = String.split(text, "
")
    total_line_count = length(lines)
    effective_max_lines = max_lines || total_line_count

    within_lines = total_line_count <= effective_max_lines
    within_bytes = total_bytes <= max_bytes

    if within_lines and within_bytes do
      %Result{
        content: text,
        truncated: false,
        total_lines: total_line_count,
        total_bytes: total_bytes,
        output_lines: total_line_count,
        output_bytes: total_bytes,
        max_lines: max_lines,
        max_bytes: max_bytes
      }
    else
      do_truncate_tail(
        lines,
        effective_max_lines,
        max_bytes,
        total_line_count,
        total_bytes,
        max_lines
      )
    end
  end

  defp do_truncate_tail(
         lines,
         effective_max_lines,
         max_bytes,
         total_line_count,
         total_bytes,
         orig_max_lines
       ) do
    reversed = Enum.reverse(lines)

    {kept, count, _bytes, truncated_by, partial} =
      acc_tail(reversed, effective_max_lines, max_bytes, [], 0, 0)

    # acc_tail with [line | kept] on reversed input [L3, L2, L1] gives [L1, L2, L3]
    # No further reverse needed.
    content = Enum.join(kept, "\n")

    %Result{
      content: content,
      truncated: true,
      truncated_by: truncated_by,
      total_lines: total_line_count,
      total_bytes: total_bytes,
      output_lines: count,
      output_bytes: byte_size(content),
      last_line_partial: partial,
      max_lines: orig_max_lines,
      max_bytes: max_bytes
    }
  end

  defp acc_tail([], _max_lines, _max_bytes, kept, count, bytes) do
    {kept, count, bytes, nil, false}
  end

  defp acc_tail([line | rest], max_lines, max_bytes, kept, count, bytes) do
    if count >= max_lines do
      {kept, count, bytes, :lines, false}
    else
      separator = if count == 0, do: 0, else: 1
      line_bytes = byte_size(line)
      new_bytes = bytes + separator + line_bytes

      if new_bytes > max_bytes do
        remaining_budget = max_bytes - bytes - separator

        if remaining_budget > 0 do
          start = max(line_bytes - remaining_budget, 0)
          partial_line = safe_tail_part(line, start, line_bytes - start)

          {[partial_line | kept], count + 1, bytes + separator + byte_size(partial_line), :bytes,
           true}
        else
          {kept, count, bytes, :bytes, false}
        end
      else
        acc_tail(rest, max_lines, max_bytes, [line | kept], count + 1, new_bytes)
      end
    end
  end

  # ── UTF-8 Safety Helpers ──

  defp safe_tail_part(binary, start, len) do
    raw = binary_part(binary, start, min(len, byte_size(binary) - start))
    skip_leading_continuation(raw)
  end

  defp skip_leading_continuation(<<>>), do: <<>>

  defp skip_leading_continuation(binary) do
    do_skip_leading(binary, 0)
  end

  defp do_skip_leading(binary, skipped) when skipped >= 3, do: binary

  defp do_skip_leading(<<byte, rest::binary>>, skipped) when Bitwise.band(byte, 0xC0) == 0x80 do
    do_skip_leading(rest, skipped + 1)
  end

  defp do_skip_leading(binary, _skipped), do: binary
end

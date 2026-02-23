defmodule Cortex.Channels.Shared.TextChunker do
  @moduledoc """
  Utilities for splitting text into chunks suitable for IM platforms.
  """

  @doc """
  Chunks text into pieces of at most `limit` characters.
  """
  def chunk_text(text, limit) when is_binary(text) and is_integer(limit) and limit > 0 do
    text
    |> String.graphemes()
    |> Enum.chunk_every(limit)
    |> Enum.map(&Enum.join/1)
  end
end

defmodule Cortex.Agents.Steering do
  @moduledoc """
  Pure functional steering queue for agents.
  Ported from Gong.Steering.
  """

  @type steering_message :: %{
          content: String.t(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @doc "Initialize an empty steering queue."
  def new, do: []

  @doc "Push a new steering message into the queue."
  def push(queue, content, metadata \\ %{}) when is_list(queue) and is_binary(content) do
    msg = %{
      content: content,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }

    append_one(queue, msg)
  end

  @doc """
  Check for pending steering messages.
  Returns {message, remaining_queue} or nil.
  """
  def check([]), do: nil

  def check([msg | rest]) do
    {msg, rest}
  end

  @doc "Clear the steering queue."
  def clear, do: []

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end
end

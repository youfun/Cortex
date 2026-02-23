defmodule Cortex.Agents.SteeringTest do
  use ExUnit.Case, async: true
  alias Cortex.Agents.Steering

  test "new queue is empty" do
    assert Steering.new() == []
  end

  test "pushing adds message to queue" do
    queue = Steering.new()
    queue = Steering.push(queue, "Hello")
    assert length(queue) == 1
    [msg] = queue
    assert msg.content == "Hello"
    assert %DateTime{} = msg.timestamp
  end

  test "check retrieves oldest message" do
    queue =
      Steering.new()
      |> Steering.push("First")
      |> Steering.push("Second")

    assert {msg1, queue} = Steering.check(queue)
    assert msg1.content == "First"
    assert {msg2, []} = Steering.check(queue)
    assert msg2.content == "Second"
    assert Steering.check([]) == nil
  end

  test "clear returns empty queue" do
    queue = Steering.new() |> Steering.push("A")
    assert Steering.clear() == []
  end
end

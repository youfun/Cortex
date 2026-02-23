defmodule Cortex.Channels.Dingtalk.DispatcherTest do
  use ExUnit.Case
  alias Cortex.Channels.Dingtalk.Dispatcher

  test "module exists" do
    assert Code.ensure_loaded?(Dispatcher)
  end
end

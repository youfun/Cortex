defmodule Cortex.ToolsCase do
  @moduledoc """
  Test case for tool-related tests.

  Ensures Tools.Registry (and supporting processes) are running.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Cortex.ToolsCase
    end
  end

  setup _tags do
    Cortex.ProcessCase.ensure_test_processes()
    :ok
  end
end

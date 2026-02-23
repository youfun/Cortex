defmodule Cortex.MemoryCase do
  @moduledoc """
  Test case for memory-related tests.

  Ensures Memory.Store and Memory.Consolidator are running.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Cortex.MemoryCase
    end
  end

  setup _tags do
    Cortex.ProcessCase.ensure_test_processes()

    Cortex.ProcessCase.start_additional_processes([
      Cortex.Memory.Store,
      Cortex.Memory.Consolidator
    ])

    :ok
  end
end

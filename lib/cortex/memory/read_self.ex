defmodule Cortex.Memory.ReadSelf do
  @moduledoc """
  Memory System Introspection Module.

  Aggregates statistics and state from various memory components to provide
  a comprehensive view of the agent's memory system status.
  """

  alias Cortex.Memory.{Store, Consolidator, Proposal, Subconscious, ReflectionProcessor}

  @doc """
  Reads the current state of the memory system.

  Returns a map containing:
  - `memory_system`: Stats from Store, Consolidator, and Proposal.
  - `cognition`: Stats from Subconscious and ReflectionProcessor.
  - `identity`: Placeholder for SelfKnowledge (if implemented).
  """
  def read_self do
    %{
      memory_system: %{
        store: Store.stats(),
        consolidator: Consolidator.stats(),
        proposal: Proposal.stats()
      },
      cognition: %{
        subconscious: Subconscious.stats(),
        reflection: ReflectionProcessor.stats()
      },
      identity:
        %{
          # Future: SelfKnowledge.get_all()
        }
    }
  end
end

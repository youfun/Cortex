defmodule Cortex.Tools.Memory.CreateProposal do
  @moduledoc """
  Tool to create a memory proposal.
  """
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Memory.Proposal

  @impl true
  def execute(args, _ctx) do
    content = Map.get(args, :content)

    if is_nil(content) do
      {:error, "Missing required argument: content"}
    else
      type_str = Map.get(args, :type, "fact")
      confidence = Map.get(args, :confidence, 0.5)
      evidence = Map.get(args, :evidence, [])

      type_atom =
        case type_str do
          "fact" -> :fact
          "insight" -> :insight
          "learning" -> :learning
          "pattern" -> :pattern
          "preference" -> :preference
          _ -> :fact
        end

      opts = [
        type: type_atom,
        confidence: confidence,
        evidence: evidence
      ]

      case Proposal.create(content, opts) do
        {:ok, proposal} ->
          {:ok, Proposal.to_map(proposal)}
      end
    end
  end
end

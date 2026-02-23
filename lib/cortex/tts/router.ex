defmodule Cortex.TTS.Router do
  @moduledoc """
  Routes TTS requests to available GPU nodes.
  """
  alias Cortex.TTS.NodeManager

  @doc """
  Selects the best available node for a request.
  For now, uses a simple "first online node" strategy.
  """
  def select_node(_request) do
    nodes = NodeManager.list_nodes()

    found = Enum.find(nodes, fn {_id, node} -> node.status == :online end)

    case found do
      {id, _node} -> {:ok, id}
      nil -> {:error, :no_available_nodes}
    end
  end
end

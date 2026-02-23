defmodule Cortex.LLM.Tools do
  @moduledoc """
  Provides ReqLLM.Tool schemas from the central tools registry.
  """

  alias Cortex.Tools.Registry

  @doc """
  Returns a list of ReqLLM.Tool structs for file operations.
  """
  def file_tools do
    Registry.to_llm_format()
  end
end

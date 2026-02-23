defmodule Cortex.Memory.CognitivePromptsTest do
  use ExUnit.Case, async: true
  alias Cortex.Memory.CognitivePrompts

  test "returns correct prompts for modes" do
    assert String.contains?(CognitivePrompts.prompt_for(:creative), "CREATIVE")
    assert String.contains?(CognitivePrompts.prompt_for(:analytical), "ANALYTICAL")
    assert String.contains?(CognitivePrompts.prompt_for(:memory), "MEMORY-FOCUSED")
    assert String.contains?(CognitivePrompts.prompt_for(:unknown), "STANDARD")
  end

  test "model_for always returns nil" do
    assert is_nil(CognitivePrompts.model_for(:any))
  end
end

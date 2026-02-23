defmodule Cortex.ConfigFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Cortex.Config` context.
  """

  @doc """
  Generate a unique llm_model name.
  """
  def unique_llm_model_name, do: "test-model-#{System.unique_integer([:positive])}"

  @doc """
  Generate a llm_model.
  """
  def llm_model_fixture(attrs \\ %{}) do
    {:ok, llm_model} =
      attrs
      |> Enum.into(%{
        adapter: "openai",
        architecture: %{"input_modalities" => ["text"], "output_modalities" => ["text"]},
        capabilities: %{"vision" => true, "function_calling" => true},
        context_window: 8192,
        custom_overrides: %{},
        display_name: "Test Model",
        enabled: true,
        name: unique_llm_model_name(),
        pricing: %{"input" => 2.5, "output" => 10.0},
        provider_drive: "openai",
        source: "seed",
        status: "active",
        api_key: "sk-test",
        base_url: "https://api.openai.com/v1"
      })
      |> Cortex.Config.create_llm_model()

    llm_model
  end
end

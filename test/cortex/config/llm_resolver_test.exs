defmodule Cortex.Config.LlmResolverTest do
  use Cortex.DataCase, async: false
  alias Cortex.Config.LlmResolver
  alias Cortex.Config
  alias Cortex.Config.Metadata

  describe "resolve/1" do
    test "resolves native config from database" do
      {:ok, _model} =
        Config.create_llm_model(%{
          name: "test-resolve-model",
          provider_drive: "openai",
          adapter: "openai",
          source: "custom",
          enabled: true,
          api_key: "db-key",
          base_url: "https://db.url"
        })

      Metadata.reload()

      config = %{"backend" => "native", "model" => "test-resolve-model"}
      assert {:ok, result} = LlmResolver.resolve(config)
      assert result.backend == "native"
      assert result.model == "test-resolve-model"
      assert result.adapter == "openai"
      assert result.api_key == "db-key"
      assert result.base_url == "https://db.url"
    end

    test "falls back to default for unknown model" do
      config = %{backend: "native", model: "unknown-model"}
      assert {:ok, result} = LlmResolver.resolve(config)
      assert result.backend == "native"
      assert result.model == "gemini-3-flash"
    end
  end
end

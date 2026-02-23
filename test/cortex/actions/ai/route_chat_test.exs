defmodule Cortex.Actions.AI.RouteChatTest do
  use Cortex.DataCase, async: false
  use Cortex.ProcessCase
  use Mimic
  alias Cortex.Actions.AI.RouteChat

  setup do
    # 默认 mock LLM Config 避免所有测试都去查数据库（除非明确需要）
    stub(Cortex.LLM.Config, :get, fn model ->
      {:ok, "google:google/gemini-3-flash:free", [model: model]}
    end)

    :ok
  end

  describe "run/2 validation" do
    test "returns error for unknown backend" do
      assert {:error, "未知的后端类型: \"unknown\""} =
               RouteChat.run(%{backend: "unknown", prompt: "hi"}, %{})
    end
  end

  describe "run/2 success paths" do
    test "calls native LLM via ReqLLM.Generation" do
      ReqLLM.Generation
      |> expect(:generate_text, fn model, messages, _opts ->
        assert model == "google/gemini-3-flash"
        assert List.last(messages).content == "hello"

        response = %ReqLLM.Response{
          id: "resp_test_1",
          model: model,
          context: ReqLLM.Context.new([]),
          message: %ReqLLM.Message{
            role: :assistant,
            content: [ReqLLM.Message.ContentPart.text("Native response")],
            tool_calls: nil
          },
          usage: %{total_tokens: 10},
          finish_reason: :stop,
          provider_meta: %{},
          stream?: false,
          stream: nil,
          object: nil,
          error: nil
        }

        {:ok, response}
      end)

      assert {:ok, result} =
               RouteChat.run(
                 %{
                   backend: "native",
                   prompt: "hello",
                   model: "llama3"
                 },
                 %{}
               )

      assert result.text == "Native response"
      assert result.backend == "native"
      assert result.usage.total_tokens == 10
    end
  end
end

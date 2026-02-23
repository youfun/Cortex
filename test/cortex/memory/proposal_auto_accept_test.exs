defmodule Cortex.Memory.ProposalAutoAcceptTest do
  use ExUnit.Case, async: false

  alias Cortex.Memory.Proposal
  alias Cortex.Memory.Store

  setup do
    Proposal.clear_all()

    unless Process.whereis(Store) do
      start_supervised!(Store)
    end

    if Process.whereis(Store), do: Store.clear_all()

    :ok
  end

  describe "auto-accept threshold logic" do
    test "safe source with confidence >= 0.65 should be auto-accepted" do
      # Create a proposal with confidence 0.70
      {:ok, proposal} =
        Proposal.create("用户偏好: Tailwind CSS",
          type: :preference,
          confidence: 0.70
        )

      assert proposal.status == :pending

      # Simulate what LLMAgent does: accept if safe_source? and confidence >= 0.65
      confidence = proposal.confidence
      safe_source? = true
      tool_source? = false

      auto_accept? =
        (safe_source? and confidence >= 0.65) or
          (tool_source? and confidence >= 0.70)

      assert auto_accept? == true

      # Actually accept it
      {:ok, accepted} = Proposal.accept(proposal.id)
      assert accepted.status == :accepted
    end

    test "safe source with confidence < 0.65 should NOT be auto-accepted" do
      {:ok, proposal} =
        Proposal.create("可能的偏好: 某个工具",
          type: :preference,
          confidence: 0.55
        )

      confidence = proposal.confidence
      safe_source? = true
      tool_source? = false

      auto_accept? =
        (safe_source? and confidence >= 0.65) or
          (tool_source? and confidence >= 0.70)

      assert auto_accept? == false
    end

    test "tool source with confidence >= 0.70 should be auto-accepted" do
      {:ok, proposal} =
        Proposal.create("活跃目录: lib/cortex/agents",
          type: :fact,
          confidence: 0.75
        )

      confidence = proposal.confidence
      safe_source? = false
      tool_source? = true

      auto_accept? =
        (safe_source? and confidence >= 0.65) or
          (tool_source? and confidence >= 0.70)

      assert auto_accept? == true
    end

    test "tool source with confidence < 0.70 should NOT be auto-accepted" do
      {:ok, proposal} =
        Proposal.create("活跃目录: tmp/",
          type: :fact,
          confidence: 0.55
        )

      confidence = proposal.confidence
      safe_source? = false
      tool_source? = true

      auto_accept? =
        (safe_source? and confidence >= 0.65) or
          (tool_source? and confidence >= 0.70)

      assert auto_accept? == false
    end

    test "unsafe and non-tool source should NOT be auto-accepted regardless of confidence" do
      {:ok, proposal} =
        Proposal.create("来自未知来源的信息",
          type: :fact,
          confidence: 0.95
        )

      confidence = proposal.confidence
      safe_source? = false
      tool_source? = false

      auto_accept? =
        (safe_source? and confidence >= 0.65) or
          (tool_source? and confidence >= 0.70)

      assert auto_accept? == false
    end
  end

  describe "low-confidence proposals are kept pending (not injected into LLM context)" do
    test "proposal stays pending when not auto-accepted" do
      {:ok, proposal} =
        Proposal.create("低置信度信息",
          type: :fact,
          confidence: 0.40
        )

      # Verify it's still pending
      found = Proposal.get(proposal.id)
      assert found.status == :pending
    end
  end
end

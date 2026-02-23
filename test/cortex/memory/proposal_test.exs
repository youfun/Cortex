defmodule Cortex.Memory.ProposalTest do
  use ExUnit.Case, async: false

  alias Cortex.Memory.Proposal

  setup do
    # Clean up ETS table before each test
    Proposal.clear_all()
    :ok
  end

  describe "new/2" do
    test "creates proposal with default values" do
      proposal = Proposal.new("Test content")

      assert proposal.content == "Test content"
      assert proposal.type == :fact
      assert proposal.status == :pending
      assert proposal.confidence == 0.5
    end

    test "creates proposal with custom type" do
      proposal = Proposal.new("Test", type: :insight, confidence: 0.85)
      assert proposal.type == :insight
      assert proposal.confidence == 0.85
    end

    test "validates proposal type" do
      assert_raise ArgumentError, fn ->
        Proposal.new("Test", type: :invalid_type)
      end
    end

    test "validates confidence range" do
      assert_raise ArgumentError, fn ->
        Proposal.new("Test", confidence: 1.5)
      end

      assert_raise ArgumentError, fn ->
        Proposal.new("Test", confidence: -0.1)
      end
    end
  end

  describe "create/2" do
    test "creates and stores proposal" do
      {:ok, proposal} = Proposal.create("Test content", type: :fact)

      assert proposal.content == "Test content"
      assert proposal.status == :pending

      # Verify it can be retrieved
      retrieved = Proposal.get(proposal.id)
      assert retrieved.id == proposal.id
    end
  end

  describe "accept/1" do
    test "accepts pending proposal" do
      {:ok, proposal} = Proposal.create("Test", confidence: 0.8)
      assert proposal.status == :pending

      {:ok, accepted} = Proposal.accept(proposal.id)
      assert accepted.status == :accepted
      assert accepted.decided_at != nil
    end

    test "returns error for non-existent proposal" do
      assert {:error, :not_found} = Proposal.accept("non-existent-id")
    end

    test "returns error for already decided proposal" do
      {:ok, proposal} = Proposal.create("Test")
      {:ok, _} = Proposal.accept(proposal.id)

      assert {:error, :already_decided} = Proposal.accept(proposal.id)
    end
  end

  describe "reject/1" do
    test "rejects pending proposal" do
      {:ok, proposal} = Proposal.create("Test")
      {:ok, rejected} = Proposal.reject(proposal.id)

      assert rejected.status == :rejected
    end
  end

  describe "defer/1" do
    test "defers pending proposal" do
      {:ok, proposal} = Proposal.create("Test")
      {:ok, deferred} = Proposal.defer(proposal.id)

      assert deferred.status == :deferred
    end
  end

  describe "list_pending/1" do
    test "returns pending proposals" do
      {:ok, p1} = Proposal.create("First", type: :fact)
      {:ok, p2} = Proposal.create("Second", type: :insight)
      {:ok, p3} = Proposal.create("Third", type: :fact)

      # Accept one
      Proposal.accept(p2.id)

      pending = Proposal.list_pending()
      assert length(pending) == 2

      ids = Enum.map(pending, & &1.id)
      assert p1.id in ids
      assert p3.id in ids
      refute p2.id in ids
    end

    test "filters by min_confidence" do
      {:ok, _} = Proposal.create("Low", confidence: 0.3)
      {:ok, _} = Proposal.create("High", confidence: 0.8)

      pending = Proposal.list_pending(min_confidence: 0.5)
      assert length(pending) == 1
      assert hd(pending).content == "High"
    end

    test "respects limit" do
      for i <- 1..5 do
        Proposal.create("Proposal #{i}")
      end

      pending = Proposal.list_pending(limit: 3)
      assert length(pending) == 3
    end
  end

  describe "stats/0" do
    test "returns proposal statistics" do
      # Create proposals
      {:ok, p1} = Proposal.create("First")
      {:ok, p2} = Proposal.create("Second")
      {:ok, _p3} = Proposal.create("Third")

      # Change statuses
      Proposal.accept(p1.id)
      Proposal.reject(p2.id)

      stats = Proposal.stats()

      assert stats.total == 3
      assert stats.pending == 1
      assert stats.accepted == 1
      assert stats.rejected == 1
      assert stats.deferred == 0
    end
  end

  describe "find_similar/2" do
    test "finds similar proposals" do
      {:ok, p1} = Proposal.create("用户偏好 Tailwind CSS")

      # Exact match
      found = Proposal.find_similar("用户偏好 Tailwind CSS", threshold: 0.9)
      assert found.id == p1.id

      # Similar but not exact
      found2 = Proposal.find_similar("用户喜欢 Tailwind CSS", threshold: 0.5)
      assert found2.id == p1.id

      # Different content
      not_found = Proposal.find_similar("完全不同的内容", threshold: 0.9)
      assert not_found == nil
    end
  end

  describe "delete/1" do
    test "deletes proposal" do
      {:ok, proposal} = Proposal.create("To be deleted")
      assert Proposal.get(proposal.id) != nil

      :ok = Proposal.delete(proposal.id)
      assert Proposal.get(proposal.id) == nil
    end

    test "returns error for non-existent proposal" do
      assert {:error, :not_found} = Proposal.delete("non-existent")
    end
  end

  describe "serialization" do
    test "to_map and from_map round-trip" do
      {:ok, proposal} =
        Proposal.create("Test",
          type: :insight,
          confidence: 0.85
        )

      map = Proposal.to_map(proposal)
      restored = Proposal.from_map(map)

      assert restored.content == proposal.content
      assert restored.type == proposal.type
      assert restored.confidence == proposal.confidence
    end
  end
end

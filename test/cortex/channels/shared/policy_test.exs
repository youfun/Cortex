defmodule Cortex.Channels.Shared.PolicyTest do
  use ExUnit.Case, async: true
  alias Cortex.Channels.Shared.Policy

  describe "check_dm_policy/3" do
    test "allows open policy" do
      assert Policy.check_dm_policy("open", "user1") == :ok
    end

    test "whitelist policy" do
      assert Policy.check_dm_policy("whitelist", "user1", ["user1", "user2"]) == :ok

      assert Policy.check_dm_policy("whitelist", "user3", ["user1", "user2"]) ==
               {:error, :policy_violation}
    end

    test "blacklist policy" do
      assert Policy.check_dm_policy("blacklist", "user1", ["user1", "user2"]) ==
               {:error, :policy_violation}

      assert Policy.check_dm_policy("blacklist", "user3", ["user1", "user2"]) == :ok
    end
  end

  describe "check_group_policy/5" do
    test "allows open policy" do
      assert Policy.check_group_policy("open", "group1") == :ok
    end

    test "whitelist policy" do
      assert Policy.check_group_policy("whitelist", "group1", ["group1"]) == :ok

      assert Policy.check_group_policy("whitelist", "group2", ["group1"]) ==
               {:error, :policy_violation}
    end

    test "blacklist policy" do
      assert Policy.check_group_policy("blacklist", "group1", ["group1"]) ==
               {:error, :policy_violation}

      assert Policy.check_group_policy("blacklist", "group2", ["group1"]) == :ok
    end

    test "require mention" do
      assert Policy.check_group_policy("open", "group1", [], true, true) == :ok

      assert Policy.check_group_policy("open", "group1", [], true, false) ==
               {:error, :mention_required}
    end

    test "no mention required" do
      assert Policy.check_group_policy("open", "group1", [], false, false) == :ok
    end
  end
end

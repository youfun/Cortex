defmodule Cortex.Channels.Shared.Policy do
  @moduledoc """
  Implements shared policy logic for channels (DM and Group).
  """

  @doc """
  Checks if a DM message should be processed based on the policy.

  ## Parameters
    - policy: "open" | "whitelist" | "blacklist"
    - sender_id: String, the ID of the sender.
    - allow_from: List of allowed sender IDs (for whitelist).

  ## Returns
    - :ok
    - {:error, :policy_violation}
  """
  def check_dm_policy(policy, sender_id, allow_from \\ []) do
    case policy do
      "open" ->
        :ok

      "whitelist" ->
        if sender_id in allow_from, do: :ok, else: {:error, :policy_violation}

      "blacklist" ->
        if sender_id in allow_from, do: {:error, :policy_violation}, else: :ok

      # Default to open
      _ ->
        :ok
    end
  end

  @doc """
  Checks if a group message should be processed.

  ## Parameters
    - policy: "open" | "whitelist" | "blacklist"
    - group_id: String, the ID of the group.
    - allow_from: List of allowed group IDs.
    - require_mention: boolean, if true, the bot must be mentioned.
    - mentioned_bot?: boolean, whether the bot was mentioned.

  ## Returns
    - :ok
    - {:error, :policy_violation}
    - {:error, :mention_required}
  """
  def check_group_policy(
        policy,
        group_id,
        allow_from \\ [],
        require_mention \\ false,
        mentioned_bot? \\ false
      ) do
    with :ok <- check_policy_list(policy, group_id, allow_from),
         :ok <- check_mention(require_mention, mentioned_bot?) do
      :ok
    end
  end

  defp check_policy_list("open", _id, _list), do: :ok

  defp check_policy_list("whitelist", id, list) do
    if id in list, do: :ok, else: {:error, :policy_violation}
  end

  defp check_policy_list("blacklist", id, list) do
    if id in list, do: {:error, :policy_violation}, else: :ok
  end

  defp check_policy_list(_, _id, _list), do: :ok

  defp check_mention(true, false), do: {:error, :mention_required}
  defp check_mention(_, _), do: :ok
end

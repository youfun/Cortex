defmodule Cortex.Memory.BackgroundChecks do
  @moduledoc """
  后台记忆检查与维护模块。
  负责定期检查记忆系统的健康状态，并在必要时提出建议或警告。
  """

  alias Cortex.Memory.Store
  alias Cortex.Memory.Proposal
  alias Cortex.Memory.WorkingMemory
  alias Cortex.Memory.Preconscious

  @doc """
  运行后台检查。

  ## 选项

  - `:skip_consolidation` - 跳过整合检查（默认：false）
  - `:skip_insights` - 跳过洞察检查（默认：false）

  ## 返回

  `%{actions: [], warnings: [], suggestions: []}`
  """
  def run(opts \\ []) do
    skip_consolidation = Keyword.get(opts, :skip_consolidation, false)
    _skip_insights = Keyword.get(opts, :skip_insights, false)

    {actions, warnings, suggestions} = {[], [], []}

    {actions, warnings, suggestions} =
      check_consolidation(actions, warnings, suggestions, skip_consolidation)

    {actions, warnings, suggestions} =
      check_pending_proposals(actions, warnings, suggestions)

    {actions, warnings, suggestions} =
      check_preconscious(actions, warnings, suggestions)

    %{
      actions: actions,
      warnings: warnings,
      suggestions: suggestions
    }
  end

  defp check_consolidation(actions, warnings, suggestions, true),
    do: {actions, warnings, suggestions}

  defp check_consolidation(actions, warnings, suggestions, false) do
    stats = Store.stats()
    total = Map.get(stats, :total, 0)

    # 从配置获取阈值，默认 800
    threshold =
      :cortex
      |> Application.get_env(:memory, [])
      |> get_in([:thresholds, :store_consolidation]) || 800

    # 如果观察项数量超过阈值，建议整合
    if total > threshold do
      {actions, append_one(warnings, "Memory store is getting full (#{total} items)"),
       append_one(suggestions, "should_consolidate")}
    else
      {actions, warnings, suggestions}
    end
  end

  defp check_pending_proposals(actions, warnings, suggestions) do
    stats = Proposal.stats()
    pending = Map.get(stats, :pending, 0)

    # 从配置获取阈值
    warning_threshold =
      :cortex
      |> Application.get_env(:memory, [])
      |> get_in([:thresholds, :proposal_pending_warning]) || 15

    max_threshold =
      :cortex
      |> Application.get_env(:memory, [])
      |> get_in([:thresholds, :proposal_pending_max]) || 20

    # 如果待审核提议接近上限，发出警告
    if pending > warning_threshold do
      {actions,
       append_one(
         warnings,
         "Pending proposals queue is nearly full (#{pending}/#{max_threshold})"
       ), append_one(suggestions, "review_proposals")}
    else
      {actions, warnings, suggestions}
    end
  end

  defp check_preconscious(actions, warnings, suggestions) do
    # 基于当前工作记忆焦点触发预意识检查
    case WorkingMemory.get_focus() do
      %{content: content} when is_binary(content) ->
        surfaced = Preconscious.check(content)

        if surfaced != [] do
          suggestion = "preconscious_surfaced: #{length(surfaced)} items"
          {actions, warnings, append_one(suggestions, suggestion)}
        else
          {actions, warnings, suggestions}
        end

      _ ->
        {actions, warnings, suggestions}
    end
  end

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end
end

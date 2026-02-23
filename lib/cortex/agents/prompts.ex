defmodule Cortex.Agents.Prompts do
  @moduledoc """
  Prompt templates for agent orchestration.
  """

  alias Cortex.Memory.ContextBuilder
  alias Cortex.Memory.TokenBudget
  alias Cortex.Workspaces

  @doc """
  构建包含技能信息的系统提示词。

  现在集成记忆上下文构建器，动态注入观察项，并平衡 Token 预算。
  """
  def build_system_prompt(opts \\ []) do
    workspace_root = Keyword.get(opts, :workspace_root, Workspaces.workspace_root())
    workspace_id = Keyword.get(opts, :workspace_id)
    model = Keyword.get(opts, :model, "gemini-3-flash")

    # 1. 加载并构建技能摘要 + always-on 内容
    {skills_summary, always_section} =
      case Cortex.Skills.Loader.load_all(workspace_root, emit_signals: false) do
        {:ok, skills} ->
          {
            Cortex.Skills.Loader.build_skills_summary(skills),
            Cortex.Skills.Loader.build_always_skills_section(skills)
          }

        _ ->
          {"", ""}
      end

    skills_material =
      [skills_summary, always_section]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    # 2. 估算技能占用
    skills_tokens = TokenBudget.estimate_tokens(skills_material)

    # 3. 计算总记忆预算 (Skills + Observations + Working Memory)
    # 设定为总上下文的 30%
    total_memory_budget = TokenBudget.calculate_memory_budget(model, memory_ratio: 0.30)

    # 4. 动态分配观察项预算
    # 至少保留 2000 tokens 给观察项
    observation_budget = max(total_memory_budget - skills_tokens, 2000)

    # 5. 加载全局记忆
    memory_section = Cortex.Memory.load_memory(workspace_root, workspace_id)

    # 6. 动态注入观察项上下文
    observation_context =
      ContextBuilder.build_context(
        workspace_root: workspace_root,
        workspace_id: workspace_id,
        model: model,
        token_budget: observation_budget,
        observation_limit: 20
      )

    parts =
      [
        base_prompt(),
        memory_section,
        observation_context,
        skills_summary,
        always_section
      ]
      |> Enum.reject(&(&1 == ""))

    Enum.join(parts, "\n\n")
  end

  defp base_prompt do
    """
    You are a coding agent with the following tools:

    - **read_file_structure(path)**: Extract code structure (modules, functions, types) without implementation bodies. Use this FIRST for code exploration to save tokens. Only use read_file when you need the full implementation.
    - **read_file(path)**: Read full file contents. Use only when you need implementation details after reviewing structure.
    - **write_file(path, content)**: Create or overwrite a file.
    - **edit_file(path, old_string, new_string)**: Replace exact text in a file.
    - **shell(command)**: Execute a shell command. Returns exit code and output.

    ## Guidelines

    - ALWAYS use read_file_structure first when exploring unfamiliar code - it saves 40-60% tokens
    - Only use read_file when you need full implementation details
    - Read files before editing to get exact content
    - Use shell for file exploration (ls, find, grep)
    - Use edit_file for surgical changes, write_file for new files
    - If the user uses /skill or @skill, follow that skill explicitly
    - You can extend yourself by writing new skills to skills/

    ## Self-Extension

    You can create new skills by writing Markdown files to `skills/<name>/SKILL.md`.
    Skills are automatically hot-loaded and will be available in your next turn.
    """
  end
end

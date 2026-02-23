defmodule Cortex.Phase4Test do
  use ExUnit.Case, async: false

  alias Cortex.Skills.Loader
  alias Cortex.Agents.Prompts

  @workspace_root System.tmp_dir!() |> Path.join("jido_phase4_#{System.unique_integer()}")

  setup do
    File.mkdir_p!(Path.join(@workspace_root, "skills/test-skill"))

    skill_content = """
    ---
    name: test-skill
    description: A test skill
    always: true
    ---
    # Test Skill
    Instruction for test skill
    """

    File.write!(Path.join(@workspace_root, "skills/test-skill/SKILL.md"), skill_content)

    on_exit(fn -> File.rm_rf!(@workspace_root) end)
    :ok
  end

  test "loads all skills from workspace" do
    assert {:ok, skills} = Loader.load_all(@workspace_root)
    assert Enum.any?(skills, &(&1.name == "test-skill"))
  end

  test "builds skills summary" do
    {:ok, skills} = Loader.load_all(@workspace_root)
    summary = Loader.build_skills_summary(skills)
    assert summary =~ "<skills>"
    assert summary =~ "test-skill"
    assert summary =~ "A test skill"
    assert summary =~ "always=\"true\""
  end

  test "builds always skills section" do
    {:ok, skills} = Loader.load_all(@workspace_root)
    always_section = Loader.build_always_skills_section(skills)
    assert always_section =~ "<always_skills>"
    assert always_section =~ "<![CDATA["
    assert always_section =~ "Instruction for test skill"
  end

  test "integrates skills into system prompt" do
    prompt = Prompts.build_system_prompt(workspace_root: @workspace_root)
    assert prompt =~ "<skills>"
    assert prompt =~ "test-skill"
    assert prompt =~ "<always_skills>"
    assert prompt =~ "You are a coding agent"
  end
end

defmodule Cortex.Skills.Skill do
  @moduledoc """
  技能定义结构。

  技能是 Markdown 文件，教导 Agent 如何执行特定任务客。
  存放在 `skills/<name>/SKILL.md`。

  ## 技能文件格式

  ```markdown
  ---
  name: my-skill
  description: 说明这个技能做什么
  ---

  # 技能名称

  给 Agent 的指令...
  ```
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          content: String.t(),
          file_path: String.t(),
          source: :workspace | :builtin,
          always: boolean(),
          loaded_at: DateTime.t()
        }

  defstruct [:name, :description, :content, :file_path, :source, :always, :loaded_at]
end

defmodule Cortex.Skills.Loader do
  @moduledoc """
  技能加载器。

  扫描 `skills/` 目录，解析 SKILL.md 文件并加载到注册表。

  加载优先级：
  1. 工作区技能 (skills/) — 最高优先级
  2. 内置技能 (priv/skills/) — 默认提供

  技能发现规则（与 Pi 一致）：
  - skills/ 下的直接 .md 文件
  - skills/<name>/SKILL.md 子目录中的文件
  """

  alias Cortex.Skills.Skill
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  require Logger

  @skills_dir "skills"
  @builtin_skills_dir "priv/skills"

  @doc """
  扫描并加载所有技能。

  返回 {:ok, [Skill.t()]} 或 {:error, reason}。
  """
  def load_all(workspace_root \\ Workspaces.workspace_root(), opts \\ []) do
    emit_signals? = Keyword.get(opts, :emit_signals, true)

    workspace_skills =
      load_from_dir(Path.join(workspace_root, @skills_dir), :workspace, emit_signals?)

    builtin_skills = load_from_dir(builtin_skills_root(), :builtin, emit_signals?)

    # 工作区技能覆盖同名内置技能
    all_skills =
      (workspace_skills ++ builtin_skills)
      |> Enum.uniq_by(& &1.name)

    if emit_signals? do
      SignalHub.emit(
        "skill.loaded.all",
        %{
          provider: "system",
          event: "skill",
          action: "load_all",
          actor: "loader",
          origin: %{channel: "system", client: "loader", platform: "server"},
          count: length(all_skills),
          names: Enum.map(all_skills, & &1.name)
        },
        source: "/skills/loader"
      )
    end

    {:ok, all_skills}
  end

  @doc """
  加载单个技能。
  """
  def load_skill(name, workspace_root \\ Workspaces.workspace_root()) do
    # 先查工作区
    workspace_path = Path.join([workspace_root, @skills_dir, name, "SKILL.md"])

    if File.exists?(workspace_path) do
      parse_skill_file(workspace_path, :workspace)
    else
      builtin_path = Path.join([builtin_skills_root(), name, "SKILL.md"])

      if File.exists?(builtin_path) do
        parse_skill_file(builtin_path, :builtin)
      else
        # 尝试直接 md 文件
        workspace_md_path = Path.join([workspace_root, @skills_dir, "#{name}.md"])

        if File.exists?(workspace_md_path) do
          parse_skill_file(workspace_md_path, :workspace)
        else
          {:error, :not_found}
        end
      end
    end
  end

  @doc """
  构建技能摘要（用于注入到系统提示词）。

  输出为 XML，包含名称、描述、位置与来源。
  Agent 需要详细内容时通过 read_file 读取。
  """
  def build_skills_summary(skills) do
    if Enum.empty?(skills) do
      ""
    else
      skills_body =
        Enum.map_join(skills, "\n", fn skill ->
          attrs =
            [
              {"name", skill.name},
              {"description", skill.description},
              {"path", relative_skill_path(skill.file_path)},
              {"source", Atom.to_string(skill.source)},
              {"always", if(skill.always, do: "true", else: "false")}
            ]
            |> Enum.map_join(" ", fn {key, value} -> "#{key}=\"#{xml_escape(value)}\"" end)

          "  <skill #{attrs} />"
        end)

      """
      <skills>
      <note>Read detailed instructions with read_file(path) when needed.</note>
      #{skills_body}
      </skills>
      """
      |> String.trim()
    end
  end

  @doc """
  构建 always-on 技能内容片段（完整内容注入）。
  """
  def build_always_skills_section(skills) do
    always_skills = Enum.filter(skills, & &1.always)

    if Enum.empty?(always_skills) do
      ""
    else
      body =
        Enum.map_join(always_skills, "\n", fn skill ->
          """
          <skill name="#{xml_escape(skill.name)}" path="#{xml_escape(relative_skill_path(skill.file_path))}" source="#{xml_escape(Atom.to_string(skill.source))}">
          <![CDATA[
          #{sanitize_cdata(skill.content)}
          ]]>
          </skill>
          """
          |> String.trim()
        end)

      """
      <always_skills>
      #{body}
      </always_skills>
      """
      |> String.trim()
    end
  end

  # === 私有函数 ===

  defp load_from_dir(dir, source, emit_signals?) do
    with true <- File.dir?(dir),
         {:ok, entries} <- File.ls(dir) do
      Enum.flat_map(entries, &load_dir_entry(dir, &1, source, emit_signals?))
    else
      _ -> []
    end
  end

  defp load_dir_entry(dir, entry, source, emit_signals?) do
    path = Path.join(dir, entry)

    cond do
      File.regular?(path) and String.ends_with?(entry, ".md") ->
        maybe_load_skill_file(path, source, emit_signals?)

      File.dir?(path) ->
        maybe_load_skill_file(Path.join(path, "SKILL.md"), source, emit_signals?)

      true ->
        []
    end
  end

  defp maybe_load_skill_file(path, source, emit_signals?) do
    if File.exists?(path) do
      case parse_skill_file(path, source, emit_signals?) do
        {:ok, skill} -> [skill]
        _ -> []
      end
    else
      []
    end
  end

  defp parse_skill_file(path, source, emit_signals? \\ true) do
    case File.read(path) do
      {:ok, content} ->
        {frontmatter, body} = parse_frontmatter(content)

        skill = %Skill{
          name: Map.get(frontmatter, "name", Path.basename(path, ".md")),
          description: Map.get(frontmatter, "description", ""),
          content: body,
          file_path: path,
          source: source,
          always: parse_bool(Map.get(frontmatter, "always", "false")),
          loaded_at: DateTime.utc_now()
        }

        if emit_signals? do
          SignalHub.emit(
            "skill.loaded",
            %{
              provider: "system",
              event: "skill",
              action: "load",
              actor: "loader",
              origin: %{channel: "system", client: "loader", platform: "server"},
              name: skill.name,
              source: source
            },
            source: "/skills/loader"
          )
        end

        {:ok, skill}

      {:error, reason} ->
        Logger.warning("[SkillsLoader] Failed to read #{path}: #{inspect(reason)}")

        SignalHub.emit(
          "skill.error",
          %{
            provider: "system",
            event: "skill",
            action: "error",
            actor: "loader",
            origin: %{channel: "system", client: "loader", platform: "server"},
            path: path,
            reason: reason
          },
          source: "/skills/loader"
        )

        {:error, reason}
    end
  end

  defp parse_frontmatter(content) do
    case Regex.run(
           ~r/\A---
(.*?)
---
(.*)\z/s,
           content
         ) do
      [_, frontmatter_str, body] ->
        # 简单的 YAML-like 解析（key: value 格式）
        frontmatter =
          frontmatter_str
          |> String.split("
")
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, ":", parts: 2) do
              [key, value] ->
                Map.put(acc, String.trim(key), String.trim(value))

              _ ->
                acc
            end
          end)

        {frontmatter, body}

      _ ->
        {%{}, content}
    end
  end

  defp parse_bool(value) when is_boolean(value), do: value

  defp parse_bool(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "yes" -> true
      "1" -> true
      _ -> false
    end
  end

  defp parse_bool(_value), do: false

  defp xml_escape(nil), do: ""

  defp xml_escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp xml_escape(value), do: xml_escape(to_string(value))

  defp sanitize_cdata(content) when is_binary(content) do
    String.replace(content, "]]>", "]]]]><![CDATA[>")
  end

  defp sanitize_cdata(content), do: to_string(content)

  defp builtin_skills_root do
    Application.app_dir(:cortex, @builtin_skills_dir)
  end

  defp relative_skill_path(path) do
    workspace_root = Workspaces.workspace_root()
    builtin_root = builtin_skills_root()

    cond do
      String.starts_with?(Path.expand(path), Path.expand(workspace_root)) ->
        Path.relative_to(path, workspace_root)

      String.starts_with?(Path.expand(path), Path.expand(builtin_root)) ->
        Path.relative_to(path, builtin_root)

      true ->
        path
    end
  end
end

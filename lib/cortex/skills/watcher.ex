defmodule Cortex.Skills.Watcher do
  @moduledoc """
  监听 `skills/` 目录变化，自动热加载技能。

  当检测到文件变化时：
  1. 解析变更的文件
  2. 更新技能注册表
  3. 发射 skill.loaded 或 skill.error 信号
  """

  use GenServer
  require Logger

  alias Cortex.Skills.Loader
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  # 3 秒轮询一次
  @poll_interval 3_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # 初始加载
    # 确保目录存在
    skills_dir = Path.join(Workspaces.ensure_workspace_root!(), "skills")
    File.mkdir_p!(skills_dir)

    {:ok, skills} = Loader.load_all()

    # 启动轮询定时器
    Process.send_after(self(), :poll, @poll_interval)

    {:ok,
     %{
       skills: Map.new(skills, &{&1.name, &1}),
       file_mtimes: build_mtime_map()
     }}
  end

  @impl true
  def handle_info(:poll, state) do
    new_mtimes = build_mtime_map()
    changed = find_changed_files(state.file_mtimes, new_mtimes)

    new_state =
      if Enum.empty?(changed) do
        state
      else
        Logger.info("[SkillsWatcher] Detected changes: #{inspect(changed)}")
        reload_skills(state, changed)
      end

    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, %{new_state | file_mtimes: new_mtimes}}
  end

  defp build_mtime_map do
    skills_dir = Path.join(Workspaces.workspace_root(), "skills")

    if File.dir?(skills_dir) do
      skills_dir
      |> Path.join("**/*.md")
      |> Path.wildcard()
      |> Map.new(fn path ->
        case File.stat(path) do
          {:ok, stat} -> {path, stat.mtime}
          _ -> {path, 0}
        end
      end)
    else
      %{}
    end
  end

  defp find_changed_files(old_mtimes, new_mtimes) do
    # 新增或修改的文件
    changed =
      Enum.filter(new_mtimes, fn {path, mtime} ->
        Map.get(old_mtimes, path) != mtime
      end)
      |> Enum.map(fn {path, _} -> path end)

    # 删除的文件
    deleted =
      old_mtimes
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(new_mtimes, &1))

    changed ++ deleted
  end

  defp reload_skills(state, _changed_files) do
    case Loader.load_all() do
      {:ok, skills} ->
        new_skills = Map.new(skills, &{&1.name, &1})

        # 发射加载成功信号
        Enum.each(skills, fn skill ->
          SignalHub.emit(
            "skill.loaded",
            %{
              provider: "system",
              event: "skill",
              action: "load",
              actor: "watcher",
              origin: %{channel: "system", client: "watcher", platform: "server"},
              name: skill.name,
              description: skill.description,
              source: skill.source
            },
            source: "/skills/watcher"
          )
        end)

        %{state | skills: new_skills}
    end
  end
end

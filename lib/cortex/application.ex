defmodule Cortex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    finch_config =
      Application.get_env(:cortex, :finch, name: Cortex.Finch)

    # 关键优化：将 Phoenix Endpoint 提前到第 5 个位置
    # 确保 Desktop 模式下健康检查能快速通过（< 5 秒）
    critical_children = [
      {Finch, finch_config},
      CortexWeb.Telemetry,
      Cortex.Repo,
      {Phoenix.PubSub, name: Cortex.PubSub},
      CortexWeb.Endpoint  # ← 提前启动 Phoenix
    ]

    # 非关键服务可以在 Phoenix 启动后再加载
    background_children = [
      {DNSCluster, query: Application.get_env(:cortex, :dns_cluster_query) || :ignore},
      # Signal Hub (must be started after PubSub)
      Cortex.SignalHub,
      Cortex.TTS.NodeManager,
      Cortex.TTS.Worker,
      Cortex.Messages.Writer,
      Cortex.History.SignalRecorder,
      # Tape Storage (Phase 2)
      Cortex.History.Tape.Store,
      # Memory System (Phase 1-3)
      Cortex.Memory.Store,
      Cortex.Memory.WorkingMemory,
      Cortex.Memory.Subconscious,
      Cortex.Memory.Consolidator,
      Cortex.Memory.Preconscious,
      Cortex.Memory.ReflectionProcessor,
      Cortex.Channels.Supervisor,
      {Registry, keys: :unique, name: Cortex.Registry},
      {Task.Supervisor, name: Cortex.AgentTaskSupervisor},
      {DynamicSupervisor, name: Cortex.SessionSupervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: Cortex.SessionRegistry},
      Cortex.Core.PermissionTracker,
      # Extension Hook Registry
      Cortex.Extensions.HookRegistry,
      # Extension Manager
      Cortex.Extensions.Manager,
      # 工具注册表
      Cortex.Tools.Registry,
      # Search config watcher
      Cortex.Search.ConfigWatcher,
      # 技能系统
      Cortex.Skills.Watcher,
      # Jido Agent Runtime (Phase 0: Multi-Agent Coordination)
      Cortex.Jido
    ]

    # Desktop 模式下添加 ExTauri.ShutdownManager
    children = critical_children ++ background_children ++ maybe_shutdown_manager()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cortex.Supervisor]

    result = Supervisor.start_link(children, opts)

    # 异步执行数据库迁移和初始化，避免阻塞 Phoenix 启动
    if should_prepare_database?() do
      Task.start(fn ->
        Logger.info("[Application] Starting background initialization...")
        prepare_database()
        # 等待 Repo 完全启动
        Process.sleep(500)
        load_model_metadata()
        Logger.info("[Application] Background initialization completed")
      end)
    else
      # 非 release 模式下仍然同步加载元数据
      load_model_metadata()
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CortexWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Desktop 模式下启动 ExTauri.ShutdownManager
  defp maybe_shutdown_manager do
    if System.get_env("DESKTOP_MODE") == "true" do
      [ExTauri.ShutdownManager]
    else
      []
    end
  end

  # 判断是否需要准备数据库（运行迁移）
  # 在以下情况下返回 true：
  # 1. 设置了 RELEASE_NAME 环境变量（标准 Elixir release）
  # 2. MIX_ENV=prod（生产环境）
  # 3. 使用了 Code.ensure_loaded?/1 检测到是打包后的环境
  defp should_prepare_database? do
    # 不要调用 Mix.env()，Burrito 打包后 Mix 模块不存在会崩溃
    # Code.ensure_loaded?(Mix) == false 说明是打包后的二进制环境
    not Code.ensure_loaded?(Mix) or
      System.get_env("RELEASE_NAME") != nil or
      Application.get_env(:cortex, :env) == :prod
  end

  defp prepare_database do
    repos = Application.get_env(:cortex, :ecto_repos, [])

    for repo <- repos do
      # 确保数据库文件所在目录存在
      ensure_database_directory(repo)

      case repo.start_link(pool_size: 2) do
        {:ok, pid} ->
          run_migrations(repo)
          # 先用 GenServer.stop 确保进程完全终止，再等待 SQLite 释放文件锁
          GenServer.stop(pid, :normal, 5_000)
          Process.sleep(200)

        {:error, {:already_started, _}} ->
          run_migrations(repo)

        error ->
          Logger.error("[Application] Failed to start repo for migrations: #{inspect(error)}")
      end
    end
  end

  defp ensure_database_directory(repo) do
    case Keyword.get(repo.config(), :database) do
      nil ->
        :ok

      db_path ->
        db_dir = Path.dirname(db_path)

        unless File.exists?(db_dir) do
          Logger.info("[Application] Creating database directory: #{db_dir}")
          File.mkdir_p!(db_dir)
        end
    end
  end

  defp run_migrations(repo) do
    app = Keyword.get(repo.config(), :otp_app)
    migrations_path = Path.join([:code.priv_dir(app) |> to_string(), "repo", "migrations"])
    Logger.info("[Application] Running migrations for #{inspect(repo)} from #{migrations_path}")

    try do
      Ecto.Migrator.run(repo, migrations_path, :up, all: true)
      Logger.info("[Application] Migrations completed successfully for #{inspect(repo)}")
    rescue
      e ->
        Logger.error(
          "[Application] Migration failed for #{inspect(repo)}: #{Exception.message(e)}"
        )

        reraise e, __STACKTRACE__
    end
  end

  defp load_model_metadata do
    # 在后台任务中加载，避免阻塞启动
    # 仅在非测试环境中加载
    if Application.get_env(:cortex, :env) != :test do
      Task.start(fn ->
        # 等待 Repo 完全启动和迁移完成
        # 增加等待时间，确保迁移完成
        wait_time = if should_prepare_database?(), do: 2000, else: 100
        Process.sleep(wait_time)

        Logger.info("[Application] Starting load_model_metadata...")

        try do
          # 加载种子数据
          Cortex.Config.Metadata.load_seeds()
          # 加载到缓存
          Cortex.Config.Metadata.reload()
          # 加载 ConfigExtension
          Cortex.Extensions.Manager.load(Cortex.Extensions.ConfigExtension)
          # 加载 SearchExtension
          Cortex.Extensions.Manager.load(Cortex.Extensions.SearchExtension)
          Logger.info("[Application] load_model_metadata completed successfully.")
        rescue
          e in [Exqlite.Error, Ecto.QueryError, DBConnection.ConnectionError] ->
            Logger.warning(
              "[Application] load_model_metadata failed (DB may not be ready): #{Exception.message(e)}"
            )
        end
      end)
    end
  end
end

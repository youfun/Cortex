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

    # 在生产环境中，我们可能需要显式运行迁移
    if System.get_env("RELEASE_NAME") do
      prepare_database()
    end

    children =
      [
        {Finch, finch_config},
        CortexWeb.Telemetry,
        Cortex.Repo,
        # 虽然我们下面手动运行了迁移，但保留这个 child spec 也是安全的，或者可以移除它
        # {Ecto.Migrator,
        #  repos: Application.fetch_env!(:cortex, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:cortex, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Cortex.PubSub},
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
      ] ++
        [
          # Start to serve requests, typically the last entry
          # This is a valid child spec (module name)
          CortexWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cortex.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # 启动后加载种子数据和缓存
        load_model_metadata()
        {:ok, pid}

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CortexWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp prepare_database do
    repos = Application.get_env(:cortex, :ecto_repos)

    for repo <- repos do
      case repo.start_link(pool_size: 2) do
        {:ok, _} ->
          run_migrations(repo)
          repo.stop()

        {:error, {:already_started, _}} ->
          run_migrations(repo)

        error ->
          Logger.error("[Application] Failed to start repo for migrations: #{inspect(error)}")
      end
    end
  end

  defp run_migrations(repo) do
    app = Keyword.get(repo.config(), :otp_app)
    migrations_path = Path.join([:code.priv_dir(app) |> to_string(), "repo", "migrations"])
    Logger.info("[Application] Running migrations for #{inspect(repo)} from #{migrations_path}")
    Ecto.Migrator.run(repo, migrations_path, :up, all: true)
  end

  defp load_model_metadata do
    # 在后台任务中加载，避免阻塞启动
    # 仅在非测试环境中加载
    if Application.get_env(:cortex, :env) != :test do
      Task.start(fn ->
        # 等待 Repo 完全启动和迁移完成
        # 增加等待时间，或者在生产环境中更谨慎
        wait_time = if System.get_env("RELEASE_NAME"), do: 2000, else: 100
        Process.sleep(wait_time)

        Logger.info("[Application] Starting load_model_metadata...")
        # 加载种子数据
        Cortex.Config.Metadata.load_seeds()
        # 加载到缓存
        Cortex.Config.Metadata.reload()
        # 加载 ConfigExtension
        Cortex.Extensions.Manager.load(Cortex.Extensions.ConfigExtension)
        Logger.info("[Application] load_model_metadata completed successfully.")
      end)
    end
  end
end

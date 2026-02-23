defmodule Cortex.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex,
      version: "0.1.32",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Cortex.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:jido, github: "agentjido/jido", override: true},
      {:jido_signal, github: "agentjido/jido_signal", override: true},
      {:splode, "~> 0.3.0", override: true},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.3", only: :test},
      {:earmark, "~> 1.4"},
      # {:agent_client_protocol, path: "../agent-client-protocol-elixir-main"},
      # {:jido_action, path: "../jido_action-main", override: true},
      {:websockex, "~> 0.4.3"},

      {:burrito, "~> 1.0"},
      {:nimble_parsec, "~> 1.0"},
      {:req_llm, github: "youfun/req_llm", branch: "feat/implicit-model-fallback", override: true}
    ]
  end

  def releases do
    [
      cortex: [
        steps: [:assemble, &Burrito.wrap/1],
        env: %{
          "RELEASE_NAME" => "cortex"
          # "CORTEX_DESKTOP" => "true"
        },
        burrito: [
          targets: [
            # windows: [os: :windows, cpu: :x86_64],
            linux: [os: :linux, cpu: :x86_64]
          ],
          debug: Mix.env() != :prod,
          debug_interpreter: Mix.env() != :prod
        ]
      ]
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  # }
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["cmd --cd assets bun install"],
      "assets.build": ["cmd --cd assets bun run build"],
      "assets.deploy": [
        "assets.build",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end

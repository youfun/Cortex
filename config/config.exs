# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cortex,
  env: config_env(),
  ecto_repos: [Cortex.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  channel_adapters: [
    Cortex.Channels.Telegram.Adapter,
    Cortex.Channels.Feishu.Adapter,
    Cortex.Channels.Dingtalk.Adapter
  ]

# Configures Repo to use binary_id by default for migrations
config :cortex, Cortex.Repo,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Configures the endpoint
config :cortex, CortexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CortexWeb.ErrorHTML, json: CortexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Cortex.PubSub,
  live_view: [signing_salt: "/VLcg3hd"]

# Finch connection pool for outbound HTTP (Req/ReqLLM).
config :cortex, :finch,
  name: Cortex.Finch,
  pools: %{
    default: [size: 64, count: 2]
  }

# Default Req options for LLM calls.
# ReqLLM validates its own option list; HTTP client options must be nested.
config :cortex, :llm_req_opts,
  req_http_options: [
    finch: Cortex.Finch,
    pool_timeout: 30_000
  ]

# Whether to require admin auth for root routes at compile time.
# Defaults to true so production requires auth; set to false in dev config if desired.
config :cortex, require_admin: true

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  cortex: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  cortex: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# jido_shell is no longer used
# config :jido_shell, :commands, %{
#   "sys" => Cortex.Shell.Commands.SystemExec
# }

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# LLMDB Configuration
config :llm_db,
  filter: %{
    allow: %{
      openai: ["*"],
      openrouter: ["*"],
      zenmux: ["*"]
    },
    deny: %{
      openai: [
        "o4-mini-2025-04-16",
        "o4-mini-deep-research-2025-06-26",
        "omni-moderation-2024-09-26",
        "omni-moderation-latest",
        "sora-2",
        "sora-2-pro",
        "text-embedding-3-large",
        "text-embedding-3-small",
        "text-embedding-ada-002",
        "tts-1",
        "tts-1-1106",
        "tts-1-hd",
        "tts-1-hd-1106",
        "whisper-1"
      ],
      openrouter: [
        "*/o4-mini-2025-04-16",
        "*/o4-mini-deep-research-2025-06-26",
        "*/omni-moderation-*",
        "*/sora-*",
        "*/text-embedding-*",
        "*/tts-*",
        "*/whisper-*"
      ],
      zenmux: [
        "*/o4-mini-2025-04-16",
        "*/o4-mini-deep-research-2025-06-26",
        "*/omni-moderation-*",
        "*/sora-*",
        "*/text-embedding-*",
        "*/tts-*",
        "*/whisper-*"
      ]
    }
  }

# Disable symlink warning on Windows
config :phoenix_live_view, :colocated_js, disable_symlink_warning: true

# Memory System configuration.
config :cortex, :memory,
  thresholds: [
    # Number of observation items to suggest consolidation
    store_consolidation: 800,
    # Number of nodes to suggest structural review
    node_insight: 100,
    # Number of observation items to suggest deep consolidation
    obs_insight: 500,
    # Warning limit for pending proposals
    proposal_pending_warning: 15,
    # Maximum pending proposals per agent
    proposal_pending_max: 20
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :btcpay_tracker,
  ecto_repos: [BtcpayTracker.Repo, BtcpayTracker.Repo.Replica],
  generators: [timestamp_type: :utc_datetime]

# Configure the primary Ecto repository
config :btcpay_tracker, BtcpayTracker.Repo,
  database: System.get_env("DATABASE_NAME") || "btcpay_tracker_dev",
  username: System.get_env("DATABASE_USER") || "postgres",
  password: System.get_env("DATABASE_PASSWORD") || "postgres",
  hostname: System.get_env("DATABASE_HOST") || "localhost", # Usually postgres_primary in Docker
  port: String.to_integer(System.get_env("DATABASE_PORT") || "5432"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  show_sensitive_data_on_connection_error: true,
  ssl: false # Adjust if your DB requires SSL

# Configure the replica Ecto repository
config :btcpay_tracker, BtcpayTracker.Repo.Replica,
  database: System.get_env("DATABASE_NAME") || "btcpay_tracker_dev", # Same database name
  username: System.get_env("DATABASE_USER") || "postgres",         # Can use same user as primary
  password: System.get_env("DATABASE_PASSWORD") || "postgres",     # Can use same password as primary
  hostname: System.get_env("REPLICA_DATABASE_HOST") || "localhost", # e.g., postgres_replica in Docker
  port: String.to_integer(System.get_env("DATABASE_PORT") || "5432"), # Replica internal port is still 5432
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  read_only: true, # Important: mark as read-only
  show_sensitive_data_on_connection_error: true,
  migrations_paths: [], # Do not look for migrations for the replica
  priv: false, # Explicitly state no priv directory for this repo
  ssl: false # Adjust if your DB requires SSL

# Configures the endpoint
config :btcpay_tracker, BtcpayTrackerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BtcpayTrackerWeb.ErrorHTML, json: BtcpayTrackerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BtcpayTracker.PubSub,
  live_view: [signing_salt: "xnxVzuNR"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  btcpay_tracker: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  btcpay_tracker: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :async_task_processor,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :async_task_processor, AsyncTaskProcessorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AsyncTaskProcessorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AsyncTaskProcessor.PubSub,
  live_view: [signing_salt: "LOdqa0w/"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :async_task_processor,
  poll_interval: 1000,
  inactive_interval: 3000,
  max_retries: 3,
  duration_to_complete_random: 3,
  min_workers: 3,
  max_workers: 10,
  event_per_worker: 3,
  pool_adjustment_interval: 5000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

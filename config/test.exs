import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :async_task_processor, AsyncTaskProcessorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/fV0/njLVAa/fIbr7l7UNZ01TybtTa2uii4vSs5d1+NaA9nvTpQDn5AmV08RVuRS",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :async_task_processor,
  duration_to_complete_random: 1

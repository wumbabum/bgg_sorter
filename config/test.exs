import Config

config :core, :bgg_req_client, Core.MockReqClient

# Configure ReqClient to use Req.Test stub for testing
config :core, Core.BggGateway.ReqClient,
  retry: false,
  receive_timeout: 1000,
  plug: {Req.Test, Core.BggGateway.ReqClient}

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :core, Core.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "core_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :web, Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "w5FjubOty76o4PMpifOcM8eaKWyruXMo8s1nOSpjfGNilK+cNYPf9s6cLaHav8Dg",
  server: true

# In test we don't send emails

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

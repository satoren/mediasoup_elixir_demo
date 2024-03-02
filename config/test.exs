import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mediasoup_elixir_demo, MediasoupElixirDemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "4+L8HHo/9C+yP6PfFT5r1nj8X8TmXu3j9nv44Gnt30oFPlNgz1w0teA/ZMYk4cQR",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

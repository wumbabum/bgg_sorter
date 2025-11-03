import Config

if System.get_env("PHX_SERVER") do
  config :web, Web.Endpoint, server: true
end

case config_env() do
  :dev ->
    config :tidewave, :root, File.cwd!()

    config :core, Core.BggGateway, bgg_api_key: System.fetch_env!("BGG_API_KEY")

  :test ->
    :ok

  :prod ->
    config :core, Core.BggGateway, bgg_api_key: System.fetch_env!("BGG_API_KEY")

    maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    config :core, Core.Repo,
      # ssl: true,
      url: System.fetch_env!("DATABASE_URL"),
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      # For machines with several cores, consider starting multiple pools of `pool_size`
      # pool_count: 4,
      socket_options: maybe_ipv6

    host = System.get_env("PHX_HOST") || "localhost"
    port = String.to_integer(System.get_env("PORT") || "7384")

    config :web, Web.Endpoint,
      url: [host: host, port: port, scheme: "http"],
      http: [
        # Enable IPv6 and bind on all interfaces.
        # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
        # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
        # for details about using IPv6 vs IPv4 and loopback vs public addresses.
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: port
      ],
      secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end

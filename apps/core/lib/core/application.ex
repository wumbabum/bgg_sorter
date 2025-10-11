defmodule Core.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Core.Repo,
      {DNSCluster, query: Application.get_env(:core, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Core.PubSub}
      # Start a worker by calling: Core.Worker.start_link(arg)
      # {Core.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Core.Supervisor)
  end
end

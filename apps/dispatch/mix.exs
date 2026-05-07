defmodule Dispatch.MixProject do
  use Mix.Project

  def project do
    [
      app: :dispatch,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Dispatch.Application, []}
    ]
  end

  defp deps do
    [
      {:oban, "~> 2.19"},
      {:phoenix_pubsub, "~> 2.1"},
      {:core, in_umbrella: true}
    ]
  end
end

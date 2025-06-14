defmodule RateLimiterMan.MixProject do
  use Mix.Project

  @project_name "Rate Limiter Man"
  @source_url "https://github.com/arcanemachine/rate_limiter_man"
  @version "0.2.3"

  def project do
    [
      app: :rate_limiter_man,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      description: "A simple rate limiter implementation (currently supports leaky bucket only)",
      package: package(),

      # Docs
      name: @project_name,
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: @project_name,
      extras: ["README.md"],
      formatters: ["html"],
      main: "readme"
    ]
  end

  defp package do
    [
      maintainers: ["Nicholas Moen"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(.formatter.exs mix.exs README.md CHANGELOG.md lib)
    ]
  end
end

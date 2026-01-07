defmodule Fivetrex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/lostbean/fivetrex"

  def project do
    [
      app: :fivetrex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [precommit: :test, ci: :test],
      name: "Fivetrex",
      description: "Elixir client library for the Fivetran REST API",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dotenvy, "~> 0.8", only: :test}
    ]
  end

  defp aliases do
    [
      precommit: [
        "format",
        "credo --strict",
        "compile --warnings-as-errors",
        "test"
      ],
      ci: [
        "format --check-formatted",
        "credo --strict",
        "compile --warnings-as-errors",
        "test --include integration"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        "API Modules": [
          Fivetrex.Groups,
          Fivetrex.Connectors,
          Fivetrex.Destinations
        ],
        Models: [
          Fivetrex.Models.Group,
          Fivetrex.Models.Connector,
          Fivetrex.Models.Destination
        ],
        Infrastructure: [
          Fivetrex.Client,
          Fivetrex.Error,
          Fivetrex.Stream
        ]
      ],
      nest_modules_by_prefix: [
        Fivetrex.Models
      ]
    ]
  end

  defp package do
    [
      name: "fivetrex",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end
end

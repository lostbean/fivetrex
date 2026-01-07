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
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
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

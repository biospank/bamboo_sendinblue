defmodule BambooSendinblue.Mixfile do
  use Mix.Project

  @project_url "https://github.com/biospank/bamboo_sendinblue"

  def project do
    [app: :bamboo_sendinblue,
     version: "0.2.0",
     elixir: ">= 1.6.6",
     source_url: @project_url,
     homepage_url: @project_url,
     name: "Bamboo SendinBlue Adapter",
     description: "A Bamboo adapter for SendinBlue",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     package: package(),
     deps: deps(),
     docs: [main: "README", extras: ["README.md"]]]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :bamboo]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:bamboo, "~> 1.1.0"},
      {:credo, "~> 0.10.2", only: [:dev, :test]},
      {:earmark, "~> 1.2.6", only: :dev},
      {:ex_doc, "~> 0.17.1", only: :dev},
      {:cowboy, "~> 2.5.0", only: [:test, :dev]},
      {:plug_cowboy, "~> 2.0", only: [:test, :dev]}
    ]
  end

  defp package do
    [
      maintainers: ["Fabio Petrucci"],
      licenses: ["MIT"],
      links: %{"GitHub" => @project_url}
    ]
  end
end

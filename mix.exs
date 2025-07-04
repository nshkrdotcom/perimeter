defmodule Perimeter.MixProject do
  use Mix.Project

  def project do
    [
      app: :perimeter,
      version: "0.0.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    A typing system for Elixir/OTP.
    """
  end

  defp package do
    [
      name: "perimeter",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/nshkrdotcom/perimeter"},
      maintainers: ["NSHkr"],
      source_url: "https://github.com/nshkrdotcom/perimeter"
    ]
  end
end

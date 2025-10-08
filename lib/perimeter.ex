defmodule Perimeter do
  @moduledoc """
  An implementation of the "Defensive Perimeter / Offensive Interior" design pattern for Elixir.

  Perimeter helps you build robust and maintainable applications by enforcing explicit
  data contracts at your system's perimeters. This allows you to write simple, assertive,
  and highly dynamic code in your core logic with confidence.

  ## Usage

      defmodule MyApp.Accounts do
        use Perimeter

        defcontract :create_user do
          required :email, :string, format: ~r/@/
          required :password, :string, min_length: 12
          optional :name, :string, max_length: 100
        end

        @guard input: :create_user
        def create_user(params) do
          # params are guaranteed valid here
          {:ok, %{email: params.email}}
        end
      end

  ## The Three-Zone Model

  1. **Defensive Perimeter**: Validates data at entry points using `@guard`
  2. **Transition Layer**: Automatically transforms and normalizes data
  3. **Offensive Interior**: Your business logic with guaranteed valid data

  See `Perimeter.Contract` for contract definition details and `Perimeter.Guard`
  for guard implementation.
  """

  @doc """
  Returns the library version.

  ## Examples

      iex> Perimeter.version()
      "0.1.0"

  """
  def version do
    "0.1.0"
  end

  @doc """
  Sets up a module to use Perimeter contracts and guards.

  Imports `Perimeter.Contract` for defining contracts and `Perimeter.Guard`
  for applying guards to functions.
  """
  defmacro __using__(_opts) do
    quote do
      use Perimeter.Contract
      use Perimeter.Guard
    end
  end
end

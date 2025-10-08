defmodule Perimeter.TestSupport.DocumentedModule do
  @moduledoc """
  A test module with documentation to verify metadata preservation.
  """

  use Perimeter

  defcontract :input do
    required(:email, :string)
  end

  @doc "Creates a new user account"
  @guard input: :input
  def create_user(params), do: {:ok, params}

  @doc false
  @guard input: :input
  def internal_create(params), do: {:ok, params}
end

defmodule Perimeter.Guard do
  @moduledoc """
  Provides the `@guard` attribute for enforcing contracts at function perimeters.

  Guards wrap function definitions to validate input parameters against defined
  contracts before executing the function body. This implements the "Defensive
  Perimeter" pattern.

  ## Usage

      defmodule MyModule do
        use Perimeter.Guard
        use Perimeter.Contract

        defcontract :input do
          required :email, :string
        end

        @guard input: :input
        def create_user(params) do
          # params.email is guaranteed to be a valid string
          {:ok, params.email}
        end
      end

  ## Options

    * `:input` - The name of the contract to validate input against (required)

  ## Behavior

  When validation fails, raises `Perimeter.ValidationError` with detailed
  violation information. When validation succeeds, the original function is
  called with the validated parameters.

  ## Implementation Details

  Guards work by:
  1. Registering guard attributes during compilation
  2. Using `@before_compile` to wrap guarded functions
  3. Injecting validation logic before the original function body
  4. Preserving function metadata (@doc, @spec, etc.)
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :guards, accumulate: true)
      @before_compile Perimeter.Guard
      @on_definition Perimeter.Guard
    end
  end

  @doc false
  def __on_definition__(env, kind, name, args, _guards, _body) do
    # Check if this function has a @guard attribute
    guards = Module.get_attribute(env.module, :guard)

    if guards && kind == :def do
      arity = length(args)
      # Store the guard for this function
      Module.put_attribute(env.module, :guards, {{name, arity}, guards})
      # Clear the guard attribute
      Module.delete_attribute(env.module, :guard)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    guards = Module.get_attribute(env.module, :guards)

    # Group guards by function name/arity
    guard_map =
      guards
      |> Enum.reverse()
      |> Map.new()

    # Generate wrapper functions for each guarded function
    wrappers =
      for {{name, arity}, guard_opts} <- guard_map do
        generate_wrapper(name, arity, guard_opts)
      end

    quote do
      (unquote_splicing(wrappers))
    end
  end

  defp generate_wrapper(name, arity, guard_opts) do
    # Generate parameter names
    params = generate_params(arity)

    # Get the contract name
    contract_name = Keyword.fetch!(guard_opts, :input)

    quote do
      # Make the original function overridable
      defoverridable [{unquote(name), unquote(arity)}]

      # Define the wrapper that validates input
      def unquote(name)(unquote_splicing(params)) do
        # Get the first parameter (should be the params map)
        params_arg = unquote(hd(params))

        # Validate against the contract
        case Perimeter.Validator.validate(__MODULE__, unquote(contract_name), params_arg) do
          {:ok, validated_params} ->
            # Call the original function with validated params
            # For single-arg functions, pass just the validated params
            # For multi-arg functions, pass validated params plus remaining args
            unquote(
              if arity == 1 do
                quote do: super(validated_params)
              else
                remaining_params = Enum.drop(params, 1)
                quote do: super(validated_params, unquote_splicing(remaining_params))
              end
            )

          {:error, violations} ->
            # Raise validation error
            raise Perimeter.ValidationError.new(violations)
        end
      end
    end
  end

  defp generate_params(arity) do
    for i <- 1..arity do
      Macro.var(:"param#{i}", __MODULE__)
    end
  end
end

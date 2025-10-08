defmodule Perimeter.Contract do
  @moduledoc """
  Provides macros for defining type contracts that are enforced at module perimeters.

  Contracts define the expected shape and constraints of data using a declarative DSL.
  They serve as both documentation and runtime validation specifications.

  ## Example

      defmodule MyApp.Accounts do
        use Perimeter.Contract

        defcontract :create_user do
          required :email, :string, format: ~r/@/
          required :password, :string, min_length: 12
          optional :name, :string, max_length: 100
        end
      end

      # Access the contract
      contract = MyApp.Accounts.__contract__(:create_user)

  ## Supported Types

  - `:string` - Binary string
  - `:integer` - Integer number
  - `:float` - Floating point number
  - `:boolean` - true or false
  - `:atom` - Atom value
  - `:map` - Map (can have nested fields)
  - `:list` - List of any items
  - `{:list, type}` - List of specific type (e.g., `{:list, :string}`)

  ## Constraints

  ### String constraints
  - `format: regex` - Must match regex pattern
  - `min_length: integer` - Minimum string length
  - `max_length: integer` - Maximum string length

  ### Number constraints (integer/float)
  - `min: number` - Minimum value
  - `max: number` - Maximum value

  ### Enum constraints
  - `in: list` - Value must be in list

  ## Nested Fields

  Maps can have nested field definitions:

      defcontract :user do
        required :email, :string
        optional :address, :map do
          required :city, :string
          required :zip, :string, format: ~r/^\d{5}$/
        end
      end
  """

  defstruct [:name, :fields]

  @type t :: %__MODULE__{
          name: atom(),
          fields: [field()]
        }

  @type field :: %{
          name: atom(),
          type: field_type(),
          required: boolean(),
          constraints: keyword(),
          nested_fields: [field()] | nil
        }

  @type field_type ::
          :string
          | :integer
          | :float
          | :boolean
          | :atom
          | :map
          | :list
          | {:list, field_type()}

  defmacro __using__(_opts) do
    quote do
      import Perimeter.Contract
      Module.register_attribute(__MODULE__, :contracts, accumulate: true)
      @before_compile Perimeter.Contract
    end
  end

  defmacro __before_compile__(env) do
    contracts = Module.get_attribute(env.module, :contracts)

    contract_functions =
      for {name, fields} <- contracts do
        # Reverse fields since we accumulated them in reverse order
        reversed_fields = Enum.reverse(fields)

        # Build AST for constructing fields at runtime
        fields_ast = build_fields_ast(reversed_fields)

        quote do
          def __contract__(unquote(name)) do
            %Perimeter.Contract{
              name: unquote(name),
              fields: unquote(fields_ast)
            }
          end
        end
      end

    quote do
      unquote(contract_functions)
      def __contract__(_), do: nil
    end
  end

  # Build AST for field construction that executes at runtime
  defp build_fields_ast(fields) do
    fields_list =
      Enum.map(fields, fn field ->
        constraints_ast = build_constraints_ast(field.constraints)

        nested_ast =
          if field.nested_fields do
            build_fields_ast(field.nested_fields)
          else
            nil
          end

        quote do
          %{
            name: unquote(field.name),
            type: unquote(Macro.escape(field.type)),
            required: unquote(field.required),
            constraints: unquote(constraints_ast),
            nested_fields: unquote(nested_ast)
          }
        end
      end)

    quote do: unquote(fields_list)
  end

  # Build AST for constraints, handling special cases like Regex
  defp build_constraints_ast(constraints) do
    constraints_list =
      Enum.map(constraints, fn
        {:format, %Regex{source: source, opts: opts}} ->
          # Generate code that compiles the regex at runtime
          quote do
            {:format, Regex.compile!(unquote(source), unquote(opts))}
          end

        {key, value} ->
          quote do
            {unquote(key), unquote(Macro.escape(value))}
          end
      end)

    quote do: unquote(constraints_list)
  end

  @doc """
  Defines a type contract.

  ## Examples

      defcontract :user do
        required :email, :string
        required :age, :integer
      end
  """
  defmacro defcontract(name, do: block) do
    quote do
      @current_contract_name unquote(name)
      @current_contract_fields []
      unquote(block)
      @contracts {unquote(name), @current_contract_fields}
      Module.delete_attribute(__MODULE__, :current_contract_name)
      Module.delete_attribute(__MODULE__, :current_contract_fields)
    end
  end

  @doc """
  Defines a required field in a contract.

  ## Examples

      required :email, :string
      required :age, :integer, min: 18, max: 150
      required :role, :atom, in: [:admin, :user]
  """
  defmacro required(name, type, opts_or_block \\ []) do
    case Macro.expand(opts_or_block, __CALLER__) do
      [do: block] ->
        # This is a nested field definition
        quote do
          # Save current nested context
          prev_nested = Module.get_attribute(__MODULE__, :current_nested_fields)
          @current_nested_fields []

          # Execute nested block
          unquote(block)

          # Capture nested fields
          nested = Enum.reverse(@current_nested_fields)

          # Restore previous context
          @current_nested_fields prev_nested

          # Create field with nested fields
          field = %{
            name: unquote(name),
            type: unquote(type),
            required: true,
            constraints: [],
            nested_fields: nested
          }

          # Add to appropriate context
          if prev_nested do
            @current_nested_fields [field | prev_nested]
          else
            @current_contract_fields [field | @current_contract_fields]
          end
        end

      opts when is_list(opts) ->
        # This is a simple field with constraints
        add_field(name, type, true, opts)

      _ ->
        # Fallback
        add_field(name, type, true, opts_or_block)
    end
  end

  @doc """
  Defines an optional field in a contract.

  ## Examples

      optional :bio, :string
      optional :age, :integer, min: 0
  """
  defmacro optional(name, type, opts_or_block \\ []) do
    case Macro.expand(opts_or_block, __CALLER__) do
      [do: block] ->
        # This is a nested field definition
        quote do
          # Save current nested context
          prev_nested = Module.get_attribute(__MODULE__, :current_nested_fields)
          @current_nested_fields []

          # Execute nested block
          unquote(block)

          # Capture nested fields
          nested = Enum.reverse(@current_nested_fields)

          # Restore previous context
          @current_nested_fields prev_nested

          # Create field with nested fields
          field = %{
            name: unquote(name),
            type: unquote(type),
            required: false,
            constraints: [],
            nested_fields: nested
          }

          # Add to appropriate context
          if prev_nested do
            @current_nested_fields [field | prev_nested]
          else
            @current_contract_fields [field | @current_contract_fields]
          end
        end

      opts when is_list(opts) ->
        # This is a simple field with constraints
        add_field(name, type, false, opts)

      _ ->
        # Fallback
        add_field(name, type, false, opts_or_block)
    end
  end

  defp add_field(name, type, required, opts) do
    quote bind_quoted: [name: name, type: type, required: required, opts: opts] do
      field = %{
        name: name,
        type: type,
        required: required,
        constraints: opts,
        nested_fields: nil
      }

      if Module.get_attribute(__MODULE__, :current_nested_fields) do
        @current_nested_fields [field | @current_nested_fields]
      else
        @current_contract_fields [field | @current_contract_fields]
      end
    end
  end
end
